import Foundation

/// Working-tree state via `git status --porcelain=v2 -z`. The v2 + null
/// terminator combo gives us deterministic parsing across path quirks
/// (spaces, unicode, etc.) and exposes rename/copy info as adjacent records.
public struct StatusService: Sendable {
    public let runner: GitRunner

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    public func status(in repo: URL) async throws -> [WorkingChange] {
        let result = try await runner.run(
            ["status", "--porcelain=v2", "-z", "--untracked-files=all"],
            in: repo
        )
        return Self.parsePorcelainV2(result.stdout)
    }

    public func stage(_ paths: [String], in repo: URL) async throws {
        guard !paths.isEmpty else { return }
        _ = try await runner.run(["add", "--"] + paths, in: repo)
    }

    public func stageAll(in repo: URL) async throws {
        _ = try await runner.run(["add", "--all"], in: repo)
    }

    public func unstage(_ paths: [String], in repo: URL) async throws {
        guard !paths.isEmpty else { return }
        _ = try await runner.run(["restore", "--staged", "--"] + paths, in: repo)
    }

    public func discardWorktree(_ paths: [String], in repo: URL) async throws {
        guard !paths.isEmpty else { return }
        _ = try await runner.run(["restore", "--worktree", "--"] + paths, in: repo)
    }

    public func deleteUntracked(_ paths: [String], in repo: URL) async throws {
        // `git clean` is the safe way to remove untracked files; `-f` so it
        // actually runs, `--` so paths starting with `-` are still safe.
        guard !paths.isEmpty else { return }
        _ = try await runner.run(["clean", "-f", "--"] + paths, in: repo)
    }

    public func applyHunk(_ patch: String, reverse: Bool, cached: Bool, in repo: URL) async throws {
        var args = ["apply", "--whitespace=nowarn"]
        if reverse { args.append("--reverse") }
        if cached { args.append("--cached") }
        args.append("-")
        // Pipe the patch via stdin.
        try await runner.runWithStdin(args, stdin: patch, in: repo)
    }

    // MARK: - Parser

    /// Parses `git status --porcelain=v2 -z` into [WorkingChange]. Records
    /// are NUL-separated. Records can be:
    ///   `1 XY ...path`           — ordinary tracked changes
    ///   `2 XY ... path\0oldPath` — renames and copies (path then origPath)
    ///   `u XY ... path`          — unmerged
    ///   `? path`                 — untracked
    ///   `! path`                 — ignored
    static func parsePorcelainV2(_ raw: String) -> [WorkingChange] {
        let records = raw.split(separator: "\u{0}", omittingEmptySubsequences: true)
        var out: [WorkingChange] = []
        var i = 0
        while i < records.count {
            let rec = String(records[i])
            if rec.hasPrefix("1 ") {
                if let change = parseOrdinary(rec) { out.append(change) }
                i += 1
            } else if rec.hasPrefix("2 ") {
                let next = i + 1 < records.count ? String(records[i + 1]) : nil
                if let change = parseRename(rec, oldPath: next) { out.append(change) }
                i += 2
            } else if rec.hasPrefix("u ") {
                if let change = parseUnmerged(rec) { out.append(change) }
                i += 1
            } else if rec.hasPrefix("? ") {
                let path = String(rec.dropFirst(2))
                out.append(WorkingChange(
                    path: path, oldPath: nil,
                    stagedKind: nil, unstagedKind: .untracked, isUnmerged: false
                ))
                i += 1
            } else if rec.hasPrefix("! ") {
                let path = String(rec.dropFirst(2))
                out.append(WorkingChange(
                    path: path, oldPath: nil,
                    stagedKind: nil, unstagedKind: .ignored, isUnmerged: false
                ))
                i += 1
            } else {
                i += 1
            }
        }
        return out
    }

    private static func parseOrdinary(_ line: String) -> WorkingChange? {
        // "1 XY sub mH mI mW hH hI path"
        let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
        guard parts.count >= 9 else { return nil }
        let xy = String(parts[1])
        let path = String(parts[8])
        return WorkingChange(
            path: path,
            oldPath: nil,
            stagedKind: kindFromCode(xy.first),
            unstagedKind: kindFromCode(xy.last),
            isUnmerged: false
        )
    }

    private static func parseRename(_ line: String, oldPath: String?) -> WorkingChange? {
        // "2 XY sub mH mI mW hH hI Rscore path"  (path then old path on next record)
        let parts = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
        guard parts.count >= 10 else { return nil }
        let xy = String(parts[1])
        let path = String(parts[9])
        return WorkingChange(
            path: path,
            oldPath: oldPath,
            stagedKind: kindFromCode(xy.first),
            unstagedKind: kindFromCode(xy.last),
            isUnmerged: false
        )
    }

    private static func parseUnmerged(_ line: String) -> WorkingChange? {
        // "u XY sub m1 m2 m3 mW h1 h2 h3 path"
        let parts = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
        guard parts.count >= 11 else { return nil }
        let path = String(parts[10])
        return WorkingChange(
            path: path,
            oldPath: nil,
            stagedKind: nil,
            unstagedKind: .unmerged,
            isUnmerged: true
        )
    }

    private static func kindFromCode(_ c: Character?) -> WorkingChange.Kind? {
        switch c {
        case "M", "m": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "T": return .typeChange
        case "U": return .unmerged
        case ".": return nil    // unchanged in this slot
        default: return nil
        }
    }
}

extension GitRunner {
    /// Variant that pipes a string into git's stdin. Used for `git apply -`.
    func runWithStdin(_ args: [String], stdin: String, in directory: URL) async throws {
        try await Task.detached { [executable] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            process.currentDirectoryURL = directory
            let inPipe = Pipe()
            let errPipe = Pipe()
            let outPipe = Pipe()
            process.standardInput = inPipe
            process.standardError = errPipe
            process.standardOutput = outPipe
            do { try process.run() } catch { throw GitError.launchFailed("\(error)") }
            // Drain both output streams before waiting so a noisy
            // `git apply` can't fill a pipe and deadlock the wait.
            let outReader = Task.detached { _ = try? outPipe.fileHandleForReading.readToEnd() }
            let errReader = Task.detached { (try? errPipe.fileHandleForReading.readToEnd()) ?? Data() }
            try? inPipe.fileHandleForWriting.write(contentsOf: Data(stdin.utf8))
            try? inPipe.fileHandleForWriting.close()
            _ = await outReader.value
            let errData = await errReader.value
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let err = String(data: errData, encoding: .utf8) ?? ""
                throw GitError.nonZeroExit(code: process.terminationStatus, stderr: err)
            }
        }.value
    }
}
