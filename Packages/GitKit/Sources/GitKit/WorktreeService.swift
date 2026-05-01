import Foundation

public struct Worktree: Equatable, Sendable {
    public let path: URL
    public let branch: String
    public let head: String
}

public struct WorktreeService: Sendable {
    public let runner: GitRunner

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    public func add(
        repo: URL,
        worktreePath: URL,
        branch: String,
        baseBranch: String
    ) async throws -> Worktree {
        try FileManager.default.createDirectory(
            at: worktreePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try await runner.run(
            ["worktree", "add", "-b", branch, worktreePath.path, baseBranch],
            in: repo
        )
        let head = try await runner.run(["rev-parse", "HEAD"], in: worktreePath)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return Worktree(path: worktreePath, branch: branch, head: head)
    }

    public func remove(repo: URL, worktreePath: URL, force: Bool = true) async throws {
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(worktreePath.path)
        _ = try await runner.run(args, in: repo)
    }

    public func list(repo: URL) async throws -> [Worktree] {
        let result = try await runner.run(["worktree", "list", "--porcelain"], in: repo)
        return parseList(result.stdout)
    }

    func parseList(_ text: String) -> [Worktree] {
        var trees: [Worktree] = []
        var path: URL?
        var head: String?
        var branch: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("worktree ") {
                if let p = path, let h = head, let b = branch {
                    trees.append(Worktree(path: p, branch: b, head: h))
                }
                path = URL(fileURLWithPath: String(line.dropFirst("worktree ".count)))
                head = nil
                branch = nil
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                branch = String(line.dropFirst("branch ".count))
                    .replacingOccurrences(of: "refs/heads/", with: "")
            }
        }
        if let p = path, let h = head, let b = branch {
            trees.append(Worktree(path: p, branch: b, head: h))
        }
        return trees
    }
}
