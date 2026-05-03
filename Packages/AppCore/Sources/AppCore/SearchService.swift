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
        for url in urls where url.pathExtension == "log" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // Bail before splitting if the file doesn't contain the
            // needle at all (one case-insensitive scan beats lowercasing
            // the whole file twice + splitting the haystack).
            if text.range(of: query, options: [.caseInsensitive]) == nil { continue }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (idx, line) in lines.enumerated() {
                if line.range(of: query, options: [.caseInsensitive]) != nil {
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
        // Run git-grep across every project in parallel; each subprocess
        // is independent, and a single slow repo no longer blocks the
        // other results.
        var hits: [Hit] = []
        await withTaskGroup(of: [Hit].self) { group in
            let exec = self.gitExecutable
            let limit = self.limitPerSource
            for project in projects {
                group.addTask {
                    await Self.runGitGrep(query: query, in: project, gitExecutable: exec, limit: limit)
                }
            }
            for await projectHits in group {
                hits.append(contentsOf: projectHits)
                if hits.count >= limitPerSource { group.cancelAll(); break }
            }
        }
        return Array(hits.prefix(limitPerSource))
    }

    private static func runGitGrep(
        query: String,
        in project: Project,
        gitExecutable: String,
        limit: Int
    ) async -> [Hit] {
        let directory = URL(fileURLWithPath: project.localPath)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) else {
            return []
        }
        let projectId = project.id
        // Hold the Process in a Sendable box so onCancel can terminate
        // it from the cancellation handler. A fresh keystroke (which
        // cancels the parent search Task) now kills the subprocess
        // instead of letting it finish into the void.
        let processBox = ProcessBox()
        return await withTaskCancellationHandler {
            await Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: gitExecutable)
                process.arguments = ["grep", "-n", "-I", "-F", "-i",
                                     "--max-count=\(limit)", "--", query]
                process.currentDirectoryURL = directory
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                processBox.set(process)
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
        } onCancel: {
            processBox.terminate()
        }
    }
}

/// Sendable mailbox so `onCancel` can reach across to a detached Task's
/// Process and call `terminate()`. NSLock-guarded; assignments are rare
/// (one per subprocess).
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ p: Process) {
        lock.lock(); defer { lock.unlock() }
        process = p
    }

    func terminate() {
        lock.lock()
        let p = process
        lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }
}
