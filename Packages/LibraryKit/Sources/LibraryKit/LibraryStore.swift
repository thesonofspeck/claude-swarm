import Foundation
import CryptoKit
import AgentBootstrap

/// Composite view of a library. For each item we know its source (built-in /
/// team / project), whether it's installed in the project, and whether the
/// installed version differs from the team version (so the UI can offer Sync).
public struct LibraryView: Equatable, Sendable {
    public struct Row: Equatable, Identifiable, Sendable {
        public let id: String           // synthetic: "<kind>/<id>"
        public let item: LibraryItem
        public let source: LibrarySource
        public var installed: Bool
        public var teamHasUpdate: Bool
    }

    public var rows: [Row]
    public var teamManifest: LibraryManifest?
    public var teamError: String?
}

public actor LibraryStore {
    public let teamSource: TeamLibrarySource
    private(set) var teamManifest: LibraryManifest?
    private(set) var teamRoot: URL?
    private(set) var teamConfig: TeamLibraryConfig = .disabled

    public init(teamSource: TeamLibrarySource) {
        self.teamSource = teamSource
    }

    public func setTeamConfig(_ config: TeamLibraryConfig) async throws {
        teamConfig = config
        guard config.isEnabled else {
            teamManifest = nil
            teamRoot = nil
            return
        }
        let (manifest, root) = try await teamSource.loadManifest(config)
        teamManifest = manifest
        teamRoot = root
    }

    public func snapshot(in projectRoot: URL) -> LibraryView {
        var rows: [LibraryView.Row] = []
        let lock = (try? loadLock(in: projectRoot)) ?? LibraryLock()
        let project = scanProject(in: projectRoot)

        // Built-in agents are always represented; install state derived
        // from presence of the project file.
        for name in Installer.agentNames {
            let id = "agent/\(name)"
            let installed = project.contains { $0.kind == .agent && $0.id == name }
            rows.append(LibraryView.Row(
                id: id,
                item: LibraryItem(
                    id: name, kind: .agent,
                    name: name, description: "Default agent",
                    path: "agents/\(name).md",
                    version: "builtin"
                ),
                source: .builtIn,
                installed: installed,
                teamHasUpdate: false
            ))
        }

        // Team items.
        for item in teamManifest?.items ?? [] {
            let key = "\(item.kind.rawValue)/\(item.id)"
            let installed = project.contains { $0.kind == item.kind && $0.id == item.id }
            let teamUpdate = installed && lock.installed[key]?.sha256 != computeTeamHash(item)
            rows.append(LibraryView.Row(
                id: key, item: item, source: .team,
                installed: installed, teamHasUpdate: teamUpdate
            ))
        }

        // Project-only items not represented above (custom agents the user
        // wrote, custom MCP entries, custom slash commands, etc.).
        for projItem in project {
            let key = "\(projItem.kind.rawValue)/\(projItem.id)"
            let alreadyShown = rows.contains { $0.id == key }
            if alreadyShown { continue }
            rows.append(LibraryView.Row(
                id: key, item: projItem, source: .project,
                installed: true, teamHasUpdate: false
            ))
        }

        rows.sort { lhs, rhs in
            if lhs.item.kind != rhs.item.kind {
                return lhs.item.kind.rawValue < rhs.item.kind.rawValue
            }
            return lhs.item.name.localizedStandardCompare(rhs.item.name) == .orderedAscending
        }
        return LibraryView(rows: rows, teamManifest: teamManifest, teamError: nil)
    }

    // MARK: - Install / uninstall

    public func install(_ item: LibraryItem, into projectRoot: URL) throws {
        switch item.kind {
        case .agent: try installAgent(item, projectRoot: projectRoot)
        case .skill: try installSkill(item, projectRoot: projectRoot)
        case .command: try installCommand(item, projectRoot: projectRoot)
        case .mcp: try installMcp(item, projectRoot: projectRoot)
        case .hook: try installHook(item, projectRoot: projectRoot)
        case .claudeMd: try installClaudeMd(item, projectRoot: projectRoot)
        }
        var lock = (try? loadLock(in: projectRoot)) ?? LibraryLock()
        let key = "\(item.kind.rawValue)/\(item.id)"
        lock.installed[key] = LibraryLock.Entry(version: item.version, sha256: computeTeamHash(item))
        try saveLock(lock, in: projectRoot)
    }

    public func uninstall(_ item: LibraryItem, from projectRoot: URL) throws {
        switch item.kind {
        case .agent:
            try? FileManager.default.removeItem(at: projectRoot.appendingPathComponent(".claude/agents/\(item.id).md"))
        case .skill:
            try? FileManager.default.removeItem(at: projectRoot.appendingPathComponent(".claude/skills/\(item.id).md"))
        case .command:
            try? FileManager.default.removeItem(at: projectRoot.appendingPathComponent(".claude/commands/\(item.id).md"))
        case .mcp:
            try removeMcpEntry(id: item.id, projectRoot: projectRoot)
        case .hook:
            try removeHookEntry(id: item.id, projectRoot: projectRoot)
        case .claudeMd:
            try? FileManager.default.removeItem(at: projectRoot.appendingPathComponent("CLAUDE.md"))
        }
        var lock = (try? loadLock(in: projectRoot)) ?? LibraryLock()
        let key = "\(item.kind.rawValue)/\(item.id)"
        lock.installed[key] = nil
        try saveLock(lock, in: projectRoot)
    }

    // MARK: - Per-kind installers

    private func teamFileURL(for item: LibraryItem) -> URL? {
        guard let teamRoot else { return nil }
        // Reject path traversal in manifest entries. A team-controlled
        // manifest can otherwise write outside the project (e.g.
        // `path: "../../etc/passwd"`).
        let resolved = teamRoot.appendingPathComponent(item.path).standardizedFileURL
        let root = teamRoot.standardizedFileURL
        guard resolved.path.hasPrefix(root.path + "/") else { return nil }
        guard !item.path.contains("..") else { return nil }
        return resolved
    }

    private func validatedDestination(in projectRoot: URL, relative: String) throws -> URL {
        let dest = projectRoot.appendingPathComponent(relative).standardizedFileURL
        let root = projectRoot.standardizedFileURL
        guard dest.path.hasPrefix(root.path + "/") else {
            throw SourceError.unsupported
        }
        return dest
    }

    private func installAgent(_ item: LibraryItem, projectRoot: URL) throws {
        let dest = try validatedDestination(in: projectRoot, relative: ".claude/agents/\(safeFilename(item.id)).md")
        try copy(itemFileURL(item), to: dest)
    }

    private func installSkill(_ item: LibraryItem, projectRoot: URL) throws {
        let dest = try validatedDestination(in: projectRoot, relative: ".claude/skills/\(safeFilename(item.id)).md")
        try copy(itemFileURL(item), to: dest)
    }

    private func installCommand(_ item: LibraryItem, projectRoot: URL) throws {
        let dest = try validatedDestination(in: projectRoot, relative: ".claude/commands/\(safeFilename(item.id)).md")
        try copy(itemFileURL(item), to: dest)
    }

    private func installClaudeMd(_ item: LibraryItem, projectRoot: URL) throws {
        let dest = try validatedDestination(in: projectRoot, relative: "CLAUDE.md")
        try copy(itemFileURL(item), to: dest)
    }

    private func safeFilename(_ id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }

    private func installMcp(_ item: LibraryItem, projectRoot: URL) throws {
        guard let source = teamFileURL(for: item) else { throw SourceError.unsupported }
        let entryData = try Data(contentsOf: source)
        guard let entry = try JSONSerialization.jsonObject(with: entryData) as? [String: Any] else {
            throw SourceError.unsupported
        }
        let mcpURL = projectRoot.appendingPathComponent(".mcp.json")
        var root = (try? Data(contentsOf: mcpURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            ?? [String: Any]()
        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        servers[item.id] = entry
        root["mcpServers"] = servers
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: mcpURL, options: .atomic)
    }

    private func installHook(_ item: LibraryItem, projectRoot: URL) throws {
        guard let source = teamFileURL(for: item) else { throw SourceError.unsupported }
        let entry = try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as? [String: Any] ?? [:]
        let settingsURL = projectRoot.appendingPathComponent(".claude/settings.json")
        var root = (try? Data(contentsOf: settingsURL))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            ?? [String: Any]()
        var hooks = (root["hooks"] as? [String: Any]) ?? [:]
        for (eventName, handlers) in entry {
            var existing = (hooks[eventName] as? [Any]) ?? []
            if let asArray = handlers as? [Any] {
                existing.append(contentsOf: asArray)
            } else {
                existing.append(handlers)
            }
            hooks[eventName] = existing
        }
        root["hooks"] = hooks
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: settingsURL, options: .atomic)
    }

    private func removeMcpEntry(id: String, projectRoot: URL) throws {
        let mcpURL = projectRoot.appendingPathComponent(".mcp.json")
        guard var root = try? JSONSerialization.jsonObject(with: Data(contentsOf: mcpURL)) as? [String: Any]
        else { return }
        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]
        servers[id] = nil
        root["mcpServers"] = servers
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: mcpURL, options: .atomic)
    }

    /// Removes any hook command containing `${id}` (or the literal id) from
    /// the project's `.claude/settings.json` `hooks` map. Bestguess based
    /// on substring; users with custom hooks can still edit by hand.
    private func removeHookEntry(id: String, projectRoot: URL) throws {
        let settingsURL = projectRoot.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = root["hooks"] as? [String: Any] else { return }

        for (eventName, value) in hooks {
            guard var entries = value as? [Any] else { continue }
            entries.removeAll { entry in
                guard let dict = entry as? [String: Any] else { return false }
                if let cmd = dict["command"] as? String, cmd.contains(id) { return true }
                if let nested = dict["hooks"] as? [Any] {
                    return nested.contains { ($0 as? [String: Any])?["command"] as? String == id
                        || (($0 as? [String: Any])?["command"] as? String)?.contains(id) == true }
                }
                return false
            }
            hooks[eventName] = entries.isEmpty ? nil : entries
        }
        root["hooks"] = hooks
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: settingsURL, options: .atomic)
    }

    private func itemFileURL(_ item: LibraryItem) throws -> URL {
        guard let url = teamFileURL(for: item),
              FileManager.default.fileExists(atPath: url.path) else {
            throw SourceError.unsupported
        }
        return url
    }

    private func copy(_ source: URL, to dest: URL) throws {
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
    }

    private func computeTeamHash(_ item: LibraryItem) -> String {
        guard let url = teamFileURL(for: item),
              let data = try? Data(contentsOf: url) else {
            return ""
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Project scan

    public struct ProjectInstalledItem: Equatable, Sendable {
        public let id: String
        public let kind: LibraryItemKind
        public let name: String
    }

    private func scanProject(in projectRoot: URL) -> [LibraryItem] {
        var out: [LibraryItem] = []
        let fm = FileManager.default
        out.append(contentsOf: scanDir(projectRoot.appendingPathComponent(".claude/agents"), kind: .agent))
        out.append(contentsOf: scanDir(projectRoot.appendingPathComponent(".claude/skills"), kind: .skill))
        out.append(contentsOf: scanDir(projectRoot.appendingPathComponent(".claude/commands"), kind: .command))

        // .mcp.json entries.
        if let data = try? Data(contentsOf: projectRoot.appendingPathComponent(".mcp.json")),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let servers = root["mcpServers"] as? [String: Any] {
            for (id, _) in servers {
                out.append(LibraryItem(
                    id: id, kind: .mcp, name: id, description: nil,
                    path: ".mcp.json#\(id)", version: nil
                ))
            }
        }
        if fm.fileExists(atPath: projectRoot.appendingPathComponent("CLAUDE.md").path) {
            out.append(LibraryItem(
                id: "CLAUDE.md", kind: .claudeMd, name: "CLAUDE.md",
                description: "Project memory", path: "CLAUDE.md", version: nil
            ))
        }
        return out
    }

    private func scanDir(_ url: URL, kind: LibraryItemKind) -> [LibraryItem] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "md" }
            .map { url in
                let id = url.deletingPathExtension().lastPathComponent
                return LibraryItem(
                    id: id, kind: kind, name: id, description: nil,
                    path: ".claude/\(kind.rawValue)/\(url.lastPathComponent)",
                    version: nil
                )
            }
    }

    // MARK: - Lock file

    private func loadLock(in projectRoot: URL) throws -> LibraryLock {
        let url = projectRoot.appendingPathComponent(".claude/swarm-library.lock.json")
        guard let data = try? Data(contentsOf: url) else { return LibraryLock() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryLock.self, from: data)
    }

    private func saveLock(_ lock: LibraryLock, in projectRoot: URL) throws {
        let url = projectRoot.appendingPathComponent(".claude/swarm-library.lock.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(lock)
        try data.write(to: url, options: .atomic)
    }

    enum SourceError: Error, LocalizedError {
        case unsupported
        var errorDescription: String? { "Unsupported library item." }
    }
}
