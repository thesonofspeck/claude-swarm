import Foundation

public struct SyncService: Sendable {
    public let runner: GitRunner

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    public func remotes(in repo: URL) async throws -> [GitRemote] {
        let r = try await runner.run(["remote", "-v"], in: repo)
        var byName: [String: (fetch: String, push: String)] = [:]
        for line in r.stdout.split(separator: "\n") {
            // "origin\thttps://...\t(fetch)" or "(push)"
            let cols = line.split(separator: "\t")
            guard cols.count >= 3 else { continue }
            let name = String(cols[0])
            let url = String(cols[1])
            var entry = byName[name] ?? (fetch: "", push: "")
            if cols[2].contains("(fetch)") { entry.fetch = url }
            if cols[2].contains("(push)") { entry.push = url }
            byName[name] = entry
        }
        return byName.map { GitRemote(name: $0.key, fetchURL: $0.value.fetch, pushURL: $0.value.push) }
            .sorted { $0.name < $1.name }
    }

    public func fetch(remote: String = "origin", prune: Bool = true, in repo: URL) async throws {
        var args = ["fetch", remote]
        if prune { args.append("--prune") }
        _ = try await runner.run(args, in: repo)
    }

    public func fetchAll(prune: Bool = true, in repo: URL) async throws {
        var args = ["fetch", "--all"]
        if prune { args.append("--prune") }
        _ = try await runner.run(args, in: repo)
    }

    public enum PullStrategy: Sendable { case merge, rebase, ffOnly }

    public func pull(
        remote: String = "origin",
        branch: String? = nil,
        strategy: PullStrategy = .ffOnly,
        in repo: URL
    ) async throws {
        var args = ["pull"]
        switch strategy {
        case .merge: break
        case .rebase: args.append("--rebase")
        case .ffOnly: args.append("--ff-only")
        }
        args.append(remote)
        if let branch { args.append(branch) }
        _ = try await runner.run(args, in: repo)
    }

    public enum PushSafety: Sendable { case standard, withLease, force }

    public func push(
        remote: String = "origin",
        branch: String? = nil,
        setUpstream: Bool = false,
        safety: PushSafety = .standard,
        in repo: URL
    ) async throws {
        var args = ["push"]
        switch safety {
        case .standard: break
        case .withLease: args.append("--force-with-lease")
        case .force: args.append("--force")
        }
        if setUpstream { args.append("-u") }
        args.append(remote)
        if let branch { args.append(branch) }
        _ = try await runner.run(args, in: repo)
    }

    /// `git rev-list --left-right --count A...B` reports ahead/behind for
    /// the current branch vs its upstream, in that order. We tolerate
    /// upstream-not-set by returning zeros.
    public func aheadBehind(branch: String, upstream: String, in repo: URL) async throws -> (ahead: Int, behind: Int) {
        let r = try await runner.run(
            ["rev-list", "--left-right", "--count", "\(branch)...\(upstream)"],
            in: repo
        )
        let parts = r.stdout.split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1]) else { return (0, 0) }
        return (ahead, behind)
    }
}
