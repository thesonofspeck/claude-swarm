import Foundation

public struct MergeService: Sendable {
    public let runner: GitRunner

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    public enum FastForward: Sendable { case allow, only, never }

    public func merge(
        _ branch: String,
        ff: FastForward = .allow,
        squash: Bool = false,
        message: String? = nil,
        in repo: URL
    ) async throws {
        var args = ["merge"]
        switch ff {
        case .allow: break
        case .only: args.append("--ff-only")
        case .never: args.append("--no-ff")
        }
        if squash { args.append("--squash") }
        if let message { args.append("-m"); args.append(message) }
        args.append(branch)
        _ = try await runner.run(args, in: repo)
    }

    public func abortMerge(in repo: URL) async throws {
        _ = try await runner.run(["merge", "--abort"], in: repo)
    }

    public func continueMerge(in repo: URL) async throws {
        _ = try await runner.run(["merge", "--continue"], in: repo)
    }

    public func rebase(onto branch: String, in repo: URL) async throws {
        _ = try await runner.run(["rebase", branch], in: repo)
    }

    public func abortRebase(in repo: URL) async throws {
        _ = try await runner.run(["rebase", "--abort"], in: repo)
    }

    public func continueRebase(in repo: URL) async throws {
        _ = try await runner.run(["rebase", "--continue"], in: repo)
    }

    public enum RepoState: String, Sendable, Equatable {
        case clean, mergeInProgress, rebaseInProgress, cherryPickInProgress, revertInProgress, bisectInProgress
    }

    /// Detects in-flight multi-step operations by checking for marker files
    /// inside `.git/`. Lets the UI surface a "Continue / Abort" banner when
    /// there's a half-finished merge or rebase.
    public func currentState(in repo: URL) -> RepoState {
        let gitDir = repo.appendingPathComponent(".git")
        let fm = FileManager.default
        if fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-merge").path) ||
           fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-apply").path) {
            return .rebaseInProgress
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("MERGE_HEAD").path) {
            return .mergeInProgress
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("CHERRY_PICK_HEAD").path) {
            return .cherryPickInProgress
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("REVERT_HEAD").path) {
            return .revertInProgress
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("BISECT_LOG").path) {
            return .bisectInProgress
        }
        return .clean
    }
}
