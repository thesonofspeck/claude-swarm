import Foundation

public struct CommitService: Sendable {
    public let runner: GitRunner

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    public struct Author: Sendable, Equatable {
        public let name: String
        public let email: String
        public init(name: String, email: String) {
            self.name = name; self.email = email
        }
    }

    public func commit(
        message: String,
        amend: Bool = false,
        signOff: Bool = false,
        author: Author? = nil,
        allowEmpty: Bool = false,
        in repo: URL
    ) async throws -> String {
        var args = ["commit", "-m", message]
        if amend { args.append("--amend") }
        if signOff { args.append("--signoff") }
        if allowEmpty { args.append("--allow-empty") }
        if let author {
            args.append("--author=\(author.name) <\(author.email)>")
        }
        _ = try await runner.run(args, in: repo)
        return try await currentSHA(in: repo)
    }

    public func currentSHA(in repo: URL) async throws -> String {
        let r = try await runner.run(["rev-parse", "HEAD"], in: repo)
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func cherryPick(_ sha: String, mainline: Int? = nil, in repo: URL) async throws {
        var args = ["cherry-pick"]
        if let mainline { args.append("-m"); args.append("\(mainline)") }
        args.append(sha)
        _ = try await runner.run(args, in: repo)
    }

    public func cherryPickAbort(in repo: URL) async throws {
        _ = try await runner.run(["cherry-pick", "--abort"], in: repo)
    }

    public func revert(_ sha: String, noCommit: Bool = false, in repo: URL) async throws {
        var args = ["revert"]
        if noCommit { args.append("--no-commit") }
        args.append(sha)
        _ = try await runner.run(args, in: repo)
    }

    public func reset(to ref: String, mode: ResetMode = .mixed, in repo: URL) async throws {
        var args = ["reset"]
        switch mode {
        case .soft: args.append("--soft")
        case .mixed: args.append("--mixed")
        case .hard: args.append("--hard")
        }
        args.append(ref)
        _ = try await runner.run(args, in: repo)
    }

    public enum ResetMode: Sendable { case soft, mixed, hard }
}
