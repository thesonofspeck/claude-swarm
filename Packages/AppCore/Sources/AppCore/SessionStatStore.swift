import Foundation
import Observation

/// Lazily-computed, cached branch diff stats for the sidebar's session
/// rows. One `git merge-base` + `git diff --shortstat` per session,
/// computed on first request and cached. Gives each session row a
/// Codex-style "+120 −18" change-size glance without blocking the UI.
@MainActor
@Observable
public final class SessionStatStore {
    public struct Stat: Sendable, Equatable {
        public var filesChanged: Int
        public var added: Int
        public var removed: Int

        public var isEmpty: Bool { filesChanged == 0 && added == 0 && removed == 0 }

        public init(filesChanged: Int = 0, added: Int = 0, removed: Int = 0) {
            self.filesChanged = filesChanged
            self.added = added
            self.removed = removed
        }
    }

    private var cache: [String: (stamp: Date, stat: Stat)] = [:]
    private var tasks: [String: Task<Stat, Never>] = [:]
    private let gitExecutable: String

    public init(gitExecutable: String = "/usr/bin/git") {
        self.gitExecutable = gitExecutable
    }

    public func stat(for sessionId: String) -> Stat? {
        cache[sessionId]?.stat
    }

    /// Compute the diff stat for a session if it hasn't been computed
    /// for `stamp` (the session's `updatedAt`) yet. A re-run for the
    /// same stamp is a no-op, so a row re-appearing on scroll is free;
    /// a newer stamp recomputes. Concurrent callers share one task.
    public func ensure(
        sessionId: String,
        worktreePath: String,
        baseBranch: String,
        stamp: Date
    ) async {
        if let cached = cache[sessionId], cached.stamp >= stamp { return }
        if let existing = tasks[sessionId] {
            _ = await existing.value
            return
        }
        let exec = gitExecutable
        let task = Task {
            await Self.compute(worktreePath: worktreePath, baseBranch: baseBranch, gitExecutable: exec)
        }
        tasks[sessionId] = task
        let result = await task.value
        tasks[sessionId] = nil
        cache[sessionId] = (stamp, result)
    }

    private static func compute(
        worktreePath: String,
        baseBranch: String,
        gitExecutable: String
    ) async -> Stat {
        await Task.detached {
            func run(_ args: [String]) -> String? {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: gitExecutable)
                p.arguments = args
                p.currentDirectoryURL = URL(fileURLWithPath: worktreePath)
                let out = Pipe()
                let err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do { try p.run() } catch { return nil }
                p.waitUntilExit()
                guard p.terminationStatus == 0 else { return nil }
                let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
                return String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // Diff from the merge-base so the number reflects only this
            // task's work (committed + uncommitted), not commits that
            // landed on the base branch after we forked.
            var fromRef = "HEAD"
            if let mb = run(["merge-base", baseBranch, "HEAD"]), !mb.isEmpty {
                fromRef = mb
            }
            let text = run(["diff", "--shortstat", fromRef]) ?? ""
            return parse(text)
        }.value
    }

    /// Parse " 3 files changed, 120 insertions(+), 18 deletions(-)".
    static func parse(_ text: String) -> Stat {
        var files = 0, added = 0, removed = 0
        for part in text.split(separator: ",") {
            let digits = part.filter(\.isNumber)
            guard let n = Int(digits) else { continue }
            if part.contains("file") { files = n }
            else if part.contains("insertion") { added = n }
            else if part.contains("deletion") { removed = n }
        }
        return Stat(filesChanged: files, added: added, removed: removed)
    }
}
