import Foundation
import PersistenceKit
import os

/// Cross-corpus full-text search. Three sources in parallel:
///
/// - **Transcripts**: every `.log` under `~/Library/Application Support/
///   ClaudeSwarm/transcripts/` (one per session). Cheap line-level grep.
/// - **Memory**: every Markdown file under `<projectRoot>/.claude/memory/`
///   plus the global root.
/// - **Code**: ripgrep-fast scan via `git grep -n` per project worktree
///   (skips .git/.build/etc. by default).
///
/// Results are returned grouped by source. Caller decides how to render.
public actor SearchService {
    public enum Source: String, Sendable, CaseIterable, Equatable {
        case transcripts, memory, code

        public var label: String {
            switch self {
            case .transcripts: return "Transcripts"
            case .memory: return "Memory"
            case .code: return "Code"
            }
        }
    }

    public struct Hit: Equatable, Sendable, Identifiable {
        public let id: String
        public let source: Source
        public let title: String
        public let snippet: String
        public let path: String
        public let line: Int?
        public let projectId: String?
        public let sessionId: String?
    }

    public struct Results: Equatable, Sendable {
        public var transcripts: [Hit] = []
        public var memory: [Hit] = []
        public var code: [Hit] = []
        public var truncated: Bool = false

        public var all: [Hit] { transcripts + memory + code }
    }

    public let transcriptsRoot: URL
    public let globalMemoryRoot: URL
    private let gitExecutable: String
    private let limitPerSource: Int

    private static let log = Logger(subsystem: "com.claudeswarm", category: "search")

    public init(
        transcriptsRoot: URL = AppDirectories.transcriptsDir,
        globalMemoryRoot: URL,
        gitExecutable: String = "/usr/bin/git",
        limitPerSource: Int = 50
    ) {
        self.transcriptsRoot = transcriptsRoot
        self.globalMemoryRoot = globalMemoryRoot
        self.gitExecutable = gitExecutable
        self.limitPerSource = limitPerSource
    }

    /// Run search across the requested sources concurrently.
    public func search(
        query: String,
        sources: Set<Source> = Set(Source.allCases),
        projects: [Project] = [],
        sessions: [Session] = []
    ) async -> Results {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return Results() }

        async let t: [Hit] = sources.contains(.transcripts) ? searchTranscripts(query: q, sessions: sessions) : []
        async let m: [Hit] = sources.contains(.memory) ? searchMemory(query: q, projects: projects) : []
        async let c: [Hit] = sources.contains(.code) ? searchCode(query: q, projects: projects) : []

        let (transcripts, memory, code) = await (t, m, c)
        var out = Results(transcripts: transcripts, memory: memory, code: code)
        out.truncated = (transcripts.count >= limitPerSource)
            || (memory.count >= limitPerSource)
            || (code.count >= limitPerSource)
        return out
    }

    // MARK: - Transcripts

    private func searchTranscripts(query: String, sessions: [Session]) async -> [Hit] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: transcriptsRoot.path) else { return [] }
        let urls = (try? fm.contentsOfDirectory(at: transcriptsRoot, includingPropertiesForKeys: nil)) ?? []
        let sessionsByPath = Dictionary(uniqueKeysWithValues: sessions.map { ($0.transcriptPath, $0) })
        var hits: [Hit] = []
        let needle = query.lowercased()
        for url in urls where url.pathExtension == "log" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (idx, line) in lines.enumerated() {
                if line.lowercased().contains(needle) {
                    let session = sessionsByPath[url.path]
                    hits.append(Hit(
                        id: "transcript:\(url.lastPathComponent):\(idx)",
                        source: .transcripts,
                        title: session?.taskTitle ?? url.deletingPathExtension().lastPathComponent,
                        snippet: String(line),
                        path: url.path,
                        line: idx + 1,
                        projectId: session?.projectId,
                        sessionId: session?.id
                    ))
                    if hits.count >= limitPerSource { return hits }
                }
            }
        }
        return hits
    }

    // MARK: - Memory

    private func searchMemory(query: String, projects: [Project]) async -> [Hit] {
        var hits: [Hit] = []
        let needle = query.lowercased()
        // Global namespace.
        hits.append(contentsOf: scanMemoryDirectory(globalMemoryRoot, needle: needle, projectId: nil))
        // Per-project project + session namespaces.
        for project in projects {
            let root = URL(fileURLWithPath: project.localPath).appendingPathComponent(".claude/memory")
            hits.append(contentsOf: scanMemoryDirectory(root, needle: needle, projectId: project.id))
            if hits.count >= limitPerSource { break }
        }
        return Array(hits.prefix(limitPerSource))
    }

    private func scanMemoryDirectory(_ root: URL, needle: String, projectId: String?) -> [Hit] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }
        var hits: [Hit] = []
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        for case let url as URL in enumerator where url.pathExtension == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if !text.lowercased().contains(needle) { continue }
            let snippet = firstMatchSnippet(in: text, needle: needle)
            hits.append(Hit(
                id: "memory:\(url.path)",
                source: .memory,
                title: url.deletingPathExtension().lastPathComponent,
                snippet: snippet,
                path: url.path,
                line: nil,
                projectId: projectId,
                sessionId: nil
            ))
            if hits.count >= limitPerSource { break }
        }
        return hits
    }

    private func firstMatchSnippet(in text: String, needle: String) -> String {
        let lower = text.lowercased()
        guard let range = lower.range(of: needle) else { return String(text.prefix(120)) }
        let lower16 = lower.utf16.distance(from: lower.utf16.startIndex, to: range.lowerBound.samePosition(in: lower.utf16) ?? lower.utf16.startIndex)
        let start = max(0, lower16 - 40)
        let end = min(text.utf16.count, lower16 + needle.utf16.count + 80)
        let s = text.utf16.index(text.utf16.startIndex, offsetBy: start)
        let e = text.utf16.index(text.utf16.startIndex, offsetBy: end)
        guard let r = Range(NSRange(location: start, length: end - start), in: text) else {
            return String(text.prefix(120))
        }
        _ = (s, e)
        return String(text[r]).replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Code

    private func searchCode(query: String, projects: [Project]) async -> [Hit] {
        var hits: [Hit] = []
        for project in projects {
            let project = project
            let projectHits = await runGitGrep(query: query, in: project)
            hits.append(contentsOf: projectHits)
            if hits.count >= limitPerSource { break }
        }
        return Array(hits.prefix(limitPerSource))
    }

    private func runGitGrep(query: String, in project: Project) async -> [Hit] {
        let directory = URL(fileURLWithPath: project.localPath)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) else {
            return []
        }
        let exec = self.gitExecutable
        let projectId = project.id
        let limit = limitPerSource
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: exec)
            // -n line numbers, -I skip binary, -F fixed strings, --max-count
            // per file, -i case-insensitive.
            process.arguments = ["grep", "-n", "-I", "-F", "-i",
                                 "--max-count=\(limit)", "--", query]
            process.currentDirectoryURL = directory
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            do { try process.run() } catch { return [] }
            process.waitUntilExit()
            let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
            let text = String(decoding: data, as: UTF8.self)
            var hits: [Hit] = []
            for line in text.split(separator: "\n") {
                // Format: "<path>:<line>:<text>"
                let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3, let lineNumber = Int(parts[1]) else { continue }
                let path = String(parts[0])
                let snippet = String(parts[2])
                hits.append(Hit(
                    id: "code:\(projectId):\(path):\(lineNumber)",
                    source: .code,
                    title: path,
                    snippet: snippet.trimmingCharacters(in: .whitespaces),
                    path: directory.appendingPathComponent(path).path,
                    line: lineNumber,
                    projectId: projectId,
                    sessionId: nil
                ))
                if hits.count >= limit { break }
            }
            return hits
        }.value
    }
}
