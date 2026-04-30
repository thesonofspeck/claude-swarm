import Foundation

/// All GitHub interactions go through `gh`. This means we inherit `gh auth`
/// state, host configuration, scopes, and rate limiting transparently.
public actor GitHubClient {
    public let runner: GhRunner

    public init(runner: GhRunner = GhRunner()) {
        self.runner = runner
    }

    // MARK: - Auth status

    public struct AuthStatus: Equatable, Sendable {
        public let authenticated: Bool
        public let user: String?
        public let raw: String
    }

    public func authStatus() async -> AuthStatus {
        do {
            let result = try await runner.run(["auth", "status"])
            let user = result.stderr
                .split(separator: "\n")
                .compactMap { line -> String? in
                    let s = String(line)
                    guard let range = s.range(of: "account ") else { return nil }
                    let after = s[range.upperBound...]
                    return String(after.split(separator: " ").first ?? "").trimmingCharacters(in: .whitespaces)
                }
                .first
            return AuthStatus(authenticated: true, user: user, raw: result.stderr)
        } catch let GhError.notAuthenticated(msg) {
            return AuthStatus(authenticated: false, user: nil, raw: msg)
        } catch {
            return AuthStatus(authenticated: false, user: nil, raw: "\(error)")
        }
    }

    // MARK: - Repos

    public func currentRepo(in directory: URL) async throws -> (owner: String, repo: String) {
        struct Body: Decodable { let owner: Owner; let name: String
            struct Owner: Decodable { let login: String }
        }
        let body: Body = try await runner.runJSON(["repo", "view", "--json", "owner,name"], in: directory)
        return (body.owner.login, body.name)
    }

    public func listRepos(limit: Int = 50) async throws -> [GHRepoSummary] {
        try await runner.runJSON([
            "repo", "list", "--limit", "\(limit)",
            "--json", "nameWithOwner,description,url,isPrivate,updatedAt"
        ])
    }

    public func searchRepos(query: String, limit: Int = 30) async throws -> [GHRepoSummary] {
        try await runner.runJSON([
            "search", "repos", query,
            "--limit", "\(limit)",
            "--json", "nameWithOwner,description,url,isPrivate,updatedAt"
        ])
    }

    // MARK: - PRs

    public func listPullRequests(
        owner: String, repo: String,
        state: String = "open", limit: Int = 30
    ) async throws -> [GHPullRequest] {
        try await runner.runJSON([
            "pr", "list",
            "--repo", "\(owner)/\(repo)",
            "--state", state,
            "--limit", "\(limit)",
            "--json", "number,title,body,state,url,isDraft,headRefName,baseRefName,author"
        ])
    }

    public func pullRequest(
        owner: String, repo: String, number: Int
    ) async throws -> GHPullRequest {
        try await runner.runJSON([
            "pr", "view", "\(number)",
            "--repo", "\(owner)/\(repo)",
            "--json", "number,title,body,state,url,isDraft,merged,headRefName,baseRefName,headRefOid,author"
        ])
    }

    public func pullRequestForBranch(
        in directory: URL, branch: String
    ) async throws -> GHPullRequest? {
        let prs: [GHPullRequest]
        do {
            prs = try await runner.runJSON([
                "pr", "list",
                "--head", branch,
                "--state", "all",
                "--limit", "1",
                "--json", "number,title,body,state,url,isDraft,merged,headRefName,baseRefName,headRefOid,author"
            ], in: directory)
        } catch {
            return nil
        }
        return prs.first
    }

    public struct CreatePRResult: Equatable, Sendable {
        public let number: Int
        public let url: String
    }

    public func createPullRequest(
        in directory: URL,
        title: String,
        body: String?,
        base: String,
        head: String?,
        draft: Bool = false
    ) async throws -> CreatePRResult {
        var args = ["pr", "create", "--title", title, "--base", base]
        if draft { args.append("--draft") }
        if let head { args.append(contentsOf: ["--head", head]) }
        if let body, !body.isEmpty {
            args.append(contentsOf: ["--body-file", "-"])
            let result = try await runner.run(args, in: directory, stdin: Data(body.utf8))
            return try parseCreateOutput(result)
        } else {
            args.append(contentsOf: ["--body", ""])
            let result = try await runner.run(args, in: directory)
            return try parseCreateOutput(result)
        }
    }

    private func parseCreateOutput(_ result: GhResult) throws -> CreatePRResult {
        let line = result.stdout
            .split(separator: "\n")
            .first { $0.contains("github.com") }
            .map(String.init) ?? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = line.split(separator: " ").first(where: { $0.hasPrefix("http") }).map(String.init)
                ?? Optional(line),
            let numberStr = url.split(separator: "/").last,
            let number = Int(numberStr)
        else {
            throw GhError.decoding(NSError(domain: "GitHubKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not parse PR URL from gh output: \(result.stdout)"]))
        }
        return CreatePRResult(number: number, url: url)
    }

    public func pushBranch(in directory: URL, branch: String) async throws {
        // Use git directly here; gh handles auth at PR-create time, not push.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["push", "-u", "origin", branch]
        process.currentDirectoryURL = directory
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let stderr = (try? err.fileHandleForReading.readToEnd()).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw GhError.nonZeroExit(code: process.terminationStatus, stderr: stderr)
        }
    }

    public func openInBrowser(url: String) async throws {
        _ = try await runner.run(["browse", url])
    }

    // MARK: - Reviews & checks

    public func reviewComments(owner: String, repo: String, number: Int) async throws -> [GHReviewComment] {
        struct Comment: Decodable {
            let id: Int64
            let body: String
            let path: String?
            let user: GHUser?
            let html_url: String
            let created_at: String?
        }
        let comments: [Comment] = try await runner.runJSON([
            "api", "repos/\(owner)/\(repo)/pulls/\(number)/comments",
            "--paginate"
        ])
        let formatter = ISO8601DateFormatter()
        return comments.map {
            GHReviewComment(
                id: $0.id,
                body: $0.body,
                path: $0.path,
                user: $0.user,
                createdAt: $0.created_at.flatMap(formatter.date(from:)),
                url: $0.html_url
            )
        }
    }

    public func checks(owner: String, repo: String, number: Int) async throws -> [GHCheckRun] {
        // `gh pr checks --json name,state,conclusion,link,bucket`
        try await runner.runJSON([
            "pr", "checks", "\(number)",
            "--repo", "\(owner)/\(repo)",
            "--json", "name,state,conclusion,link,bucket"
        ])
    }
}
