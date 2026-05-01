import Foundation

public enum MemoryNamespace: Equatable, Hashable, Sendable {
    case global
    case project(String)
    case session(String)

    public var asString: String {
        switch self {
        case .global: return "global"
        case .project(let id): return "project:\(id)"
        case .session(let id): return "session:\(id)"
        }
    }

    public static func parse(_ raw: String?) -> MemoryNamespace {
        guard let raw, !raw.isEmpty else { return .global }
        if raw == "global" { return .global }
        if raw.hasPrefix("project:") { return .project(String(raw.dropFirst("project:".count))) }
        if raw.hasPrefix("session:") { return .session(String(raw.dropFirst("session:".count))) }
        return .global
    }
}

public struct MemoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var namespace: String
    public var key: String?
    public var content: String
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        namespace: MemoryNamespace,
        key: String? = nil,
        content: String,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.namespace = namespace.asString
        self.key = key
        self.content = content
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var tagsArray: [String] { tags }
}

public enum MemoryStoreError: Error, LocalizedError {
    case noProjectRoot
    case malformedEntry(String)

    public var errorDescription: String? {
        switch self {
        case .noProjectRoot:
            return "Project-scoped memory operations require a project root."
        case .malformedEntry(let path):
            return "Malformed memory entry at \(path)."
        }
    }
}

/// Filesystem-backed memory: Markdown files with YAML frontmatter under
/// `<projectRoot>/.claude/memory/{global,project,session/<sessionId>}/`.
/// `global` lives outside the project so it's shared across all projects on
/// the machine.
public actor MemoryStore {
    public let projectRoot: URL?
    public let projectId: String?
    public let globalRoot: URL

    /// - Parameters:
    ///   - projectRoot: Repository root. Required for `.project` and `.session`
    ///     namespaces; pass `nil` for a global-only store.
    ///   - projectId: Used as the `id` portion of the `project:<id>` namespace
    ///     when serializing. Stored in frontmatter for traceability.
    ///   - globalRoot: Override the global memory directory (tests).
    public init(
        projectRoot: URL? = nil,
        projectId: String? = nil,
        globalRoot: URL
    ) throws {
        self.projectRoot = projectRoot
        self.projectId = projectId
        self.globalRoot = globalRoot
        // Inline directory creation — the actor's nonisolated init can't
        // call isolated members under Swift 6 strict concurrency.
        let fm = FileManager.default
        try fm.createDirectory(at: globalRoot, withIntermediateDirectories: true)
        if let projectRoot {
            try fm.createDirectory(
                at: projectRoot.appendingPathComponent(".claude/memory/project", isDirectory: true),
                withIntermediateDirectories: true
            )
            try fm.createDirectory(
                at: projectRoot.appendingPathComponent(".claude/memory/session", isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    // MARK: - Public API

    @discardableResult
    public func write(_ entry: MemoryEntry) throws -> MemoryEntry {
        var e = entry
        e.updatedAt = Date()
        let url = try fileURL(forNamespace: MemoryNamespace.parse(e.namespace), id: e.id)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(serialize(e).utf8).write(to: url, options: .atomic)
        return e
    }

    public func get(id: String) throws -> MemoryEntry? {
        for url in try allMarkdownURLs(namespace: nil) {
            if url.deletingPathExtension().lastPathComponent == id {
                return try parseFile(at: url)
            }
        }
        return nil
    }

    public func list(namespace: MemoryNamespace? = nil, limit: Int = 100) throws -> [MemoryEntry] {
        let urls = try allMarkdownURLs(namespace: namespace)
        let entries = urls.compactMap { try? parseFile(at: $0) }
        return Array(entries.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    public func search(_ text: String, namespace: MemoryNamespace? = nil, limit: Int = 20) throws -> [MemoryEntry] {
        let needle = text.lowercased()
        guard !needle.isEmpty else { return try list(namespace: namespace, limit: limit) }
        let urls = try allMarkdownURLs(namespace: namespace)
        let hits = urls.compactMap { url -> MemoryEntry? in
            guard let entry = try? parseFile(at: url) else { return nil }
            let haystack = ([entry.key, entry.content] + entry.tags)
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(needle) ? entry : nil
        }
        return Array(hits.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }

    public func delete(id: String) throws {
        for url in try allMarkdownURLs(namespace: nil) {
            if url.deletingPathExtension().lastPathComponent == id {
                try FileManager.default.removeItem(at: url)
                return
            }
        }
    }

    // MARK: - Path helpers

    private func projectMemoryRoot(_ projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".claude/memory/project", isDirectory: true)
    }

    private func sessionMemoryRoot(_ projectRoot: URL) -> URL {
        projectRoot.appendingPathComponent(".claude/memory/session", isDirectory: true)
    }

    private func fileURL(forNamespace namespace: MemoryNamespace, id: String) throws -> URL {
        let safeId = sanitizeFilename(id)
        switch namespace {
        case .global:
            return globalRoot.appendingPathComponent("\(safeId).md")
        case .project:
            guard let projectRoot else { throw MemoryStoreError.noProjectRoot }
            return projectMemoryRoot(projectRoot).appendingPathComponent("\(safeId).md")
        case .session(let sid):
            guard let projectRoot else { throw MemoryStoreError.noProjectRoot }
            return sessionMemoryRoot(projectRoot)
                .appendingPathComponent(sanitizeFilename(sid), isDirectory: true)
                .appendingPathComponent("\(safeId).md")
        }
    }

    private func allMarkdownURLs(namespace: MemoryNamespace?) throws -> [URL] {
        var roots: [URL] = []
        if let namespace {
            switch namespace {
            case .global:
                roots = [globalRoot]
            case .project:
                if let projectRoot { roots = [projectMemoryRoot(projectRoot)] }
            case .session(let sid):
                if let projectRoot {
                    roots = [sessionMemoryRoot(projectRoot).appendingPathComponent(sanitizeFilename(sid))]
                }
            }
        } else {
            roots.append(globalRoot)
            if let projectRoot {
                roots.append(projectMemoryRoot(projectRoot))
                roots.append(sessionMemoryRoot(projectRoot))
            }
        }
        var results: [URL] = []
        for root in roots {
            results.append(contentsOf: try walkMarkdown(in: root))
        }
        return results
    }

    private func walkMarkdown(in directory: URL) throws -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var results: [URL] = []
        for case let url as URL in enumerator {
            if url.pathExtension == "md" {
                results.append(url)
            }
        }
        return results
    }

    // MARK: - Serialization

    private func serialize(_ entry: MemoryEntry) -> String {
        var lines: [String] = ["---"]
        lines.append("id: \(yamlScalar(entry.id))")
        lines.append("namespace: \(yamlScalar(entry.namespace))")
        if let key = entry.key {
            lines.append("key: \(yamlScalar(key))")
        }
        if !entry.tags.isEmpty {
            let joined = entry.tags.map { yamlScalar($0) }.joined(separator: ", ")
            lines.append("tags: [\(joined)]")
        }
        lines.append("created: \(Self.iso8601.string(from: entry.createdAt))")
        lines.append("updated: \(Self.iso8601.string(from: entry.updatedAt))")
        lines.append("---")
        lines.append("")
        lines.append(entry.content)
        if !entry.content.hasSuffix("\n") {
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func parseFile(at url: URL) throws -> MemoryEntry {
        let raw = try String(contentsOf: url, encoding: .utf8)
        return try parseEntry(raw: raw, fileURL: url)
    }

    func parseEntry(raw: String, fileURL: URL) throws -> MemoryEntry {
        let inferredNamespace = inferNamespace(from: fileURL)
        let inferredId = fileURL.deletingPathExtension().lastPathComponent
        let mtime = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? Date()

        guard raw.hasPrefix("---\n") || raw.hasPrefix("---\r\n") else {
            return MemoryEntry(
                id: inferredId,
                namespace: inferredNamespace,
                content: raw,
                createdAt: mtime,
                updatedAt: mtime
            )
        }

        let afterOpener = raw.dropFirst(raw.hasPrefix("---\r\n") ? 5 : 4)
        guard let endRange = afterOpener.range(of: "\n---") else {
            throw MemoryStoreError.malformedEntry(fileURL.path)
        }
        let header = String(afterOpener[..<endRange.lowerBound])
        var body = String(afterOpener[endRange.upperBound...])
        // Skip the line break after the closing `---`.
        if body.hasPrefix("\r\n") {
            body.removeFirst(2)
        } else if body.hasPrefix("\n") {
            body.removeFirst(1)
        }

        var id = inferredId
        var namespace = inferredNamespace
        var key: String?
        var tags: [String] = []
        var created = mtime
        var updated = mtime

        for line in header.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let field = String(line[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            switch field {
            case "id": id = unquote(value)
            case "namespace": namespace = MemoryNamespace.parse(unquote(value))
            case "key": key = unquote(value)
            case "tags": tags = parseInlineList(value)
            case "created": if let d = Self.iso8601.date(from: value) { created = d }
            case "updated": if let d = Self.iso8601.date(from: value) { updated = d }
            default: break
            }
        }

        return MemoryEntry(
            id: id,
            namespace: namespace,
            key: key,
            content: body.trimmingCharacters(in: .newlines),
            tags: tags,
            createdAt: created,
            updatedAt: updated
        )
    }

    private func inferNamespace(from url: URL) -> MemoryNamespace {
        let resolved = url.standardizedFileURL.path
        if resolved.hasPrefix(globalRoot.standardizedFileURL.path) {
            return .global
        }
        guard let projectRoot else { return .global }
        let projDir = projectMemoryRoot(projectRoot).standardizedFileURL.path
        let sessDir = sessionMemoryRoot(projectRoot).standardizedFileURL.path
        if resolved.hasPrefix(projDir) {
            return .project(projectId ?? "")
        }
        if resolved.hasPrefix(sessDir) {
            let suffix = resolved.dropFirst(sessDir.count).drop(while: { $0 == "/" })
            let sid = String(suffix.split(separator: "/").first ?? "")
            return .session(sid)
        }
        return .global
    }

    // MARK: - Tiny YAML helpers

    private func yamlScalar(_ s: String) -> String {
        let needsQuoting = s.contains(":") || s.contains("#") || s.contains(",")
            || s.contains("[") || s.contains("]") || s.contains("\"") || s.hasPrefix(" ") || s.hasSuffix(" ")
            || s.isEmpty
        if !needsQuoting { return s }
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func unquote(_ s: String) -> String {
        guard s.count >= 2 else { return s }
        if (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            return String(s.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return s
    }

    private func parseInlineList(_ s: String) -> [String] {
        var trimmed = s.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else { return [] }
        trimmed = String(trimmed.dropFirst().dropLast())
        return trimmed.split(separator: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private func sanitizeFilename(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let cleaned = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? UUID().uuidString : cleaned
    }

    // ISO8601DateFormatter isn't Sendable, but its `string(from:)` and
    // `date(from:)` are documented thread-safe — `nonisolated(unsafe)`
    // tells the Swift 6 compiler we know what we're doing.
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
