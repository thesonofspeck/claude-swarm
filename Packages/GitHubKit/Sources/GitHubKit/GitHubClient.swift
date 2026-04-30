import Foundation
import GitKit

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
        // Pushing inherits the user's git credential helper; gh's auth only
        // applies at PR-create time.
        _ = try await GitRunner().run(["push", "-u", "origin", branch], in: directory)
    }

    public func openInBrowser(url: String) async throws {
        _ = try await runner.run(["browse", url])
    }

    // MARK: - Issues

    public func listIssues(
        owner: String, repo: String, state: String = "open", limit: Int = 30
    ) async throws -> [GHIssue] {
        try await runner.runJSON([
            "issue", "list", "--repo", "\(owner)/\(repo)",
            "--state", state, "--limit", "\(limit)",
            "--json", "number,title,body,state,url,author,labels"
        ])
    }

    public struct CreatedIssue: Equatable, Sendable {
        public let number: Int
        public let url: String
    }

    public func createIssue(
        owner: String, repo: String,
        title: String, body: String?,
        labels: [String] = [], assignees: [String] = []
    ) async throws -> CreatedIssue {
        var args = ["issue", "create", "--repo", "\(owner)/\(repo)", "--title", title]
        if !labels.isEmpty { args.append(contentsOf: ["--label", labels.joined(separator: ",")]) }
        if !assignees.isEmpty { args.append(contentsOf: ["--assignee", assignees.joined(separator: ",")]) }
        let result: GhResult
        if let body, !body.isEmpty {
            args.append(contentsOf: ["--body-file", "-"])
            result = try await runner.run(args, stdin: Data(body.utf8))
        } else {
            args.append(contentsOf: ["--body", ""])
            result = try await runner.run(args)
        }
        let url = result.stdout.split(separator: "\n").first { $0.contains("github.com") }
            .map(String.init) ?? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = url.split(separator: "/").last.flatMap { Int($0) } ?? 0
        return CreatedIssue(number: number, url: url)
    }

    public func commentOnIssue(owner: String, repo: String, number: Int, body: String) async throws {
        _ = try await runner.run(
            ["issue", "comment", "\(number)", "--repo", "\(owner)/\(repo)", "--body-file", "-"],
            stdin: Data(body.utf8)
        )
    }

    public func closeIssue(owner: String, repo: String, number: Int) async throws {
        _ = try await runner.run(["issue", "close", "\(number)", "--repo", "\(owner)/\(repo)"])
    }

    public func reopenIssue(owner: String, repo: String, number: Int) async throws {
        _ = try await runner.run(["issue", "reopen", "\(number)", "--repo", "\(owner)/\(repo)"])
    }

    // MARK: - PR mutations

    public enum MergeMethod: String, Sendable {
        case squash, merge, rebase
        var flag: String {
            switch self {
            case .squash: return "--squash"
            case .merge: return "--merge"
            case .rebase: return "--rebase"
            }
        }
    }

    public func mergePR(
        owner: String, repo: String, number: Int,
        method: MergeMethod = .squash, deleteBranch: Bool = true, admin: Bool = false
    ) async throws {
        var args = ["pr", "merge", "\(number)", "--repo", "\(owner)/\(repo)", method.flag]
        if deleteBranch { args.append("--delete-branch") }
        if admin { args.append("--admin") }
        _ = try await runner.run(args)
    }

    public func updatePR(
        owner: String, repo: String, number: Int,
        title: String? = nil, body: String? = nil,
        addLabels: [String] = [], removeLabels: [String] = [],
        addReviewers: [String] = [], addAssignees: [String] = [],
        markReady: Bool = false
    ) async throws {
        var args = ["pr", "edit", "\(number)", "--repo", "\(owner)/\(repo)"]
        if let title { args.append(contentsOf: ["--title", title]) }
        if !addLabels.isEmpty { args.append(contentsOf: ["--add-label", addLabels.joined(separator: ",")]) }
        if !removeLabels.isEmpty { args.append(contentsOf: ["--remove-label", removeLabels.joined(separator: ",")]) }
        if !addReviewers.isEmpty { args.append(contentsOf: ["--add-reviewer", addReviewers.joined(separator: ",")]) }
        if !addAssignees.isEmpty { args.append(contentsOf: ["--add-assignee", addAssignees.joined(separator: ",")]) }
        if let body, !body.isEmpty {
            args.append(contentsOf: ["--body-file", "-"])
            _ = try await runner.run(args, stdin: Data(body.utf8))
        } else {
            _ = try await runner.run(args)
        }
        if markReady {
            _ = try await runner.run(["pr", "ready", "\(number)", "--repo", "\(owner)/\(repo)"])
        }
    }

    public func closePR(owner: String, repo: String, number: Int) async throws {
        _ = try await runner.run(["pr", "close", "\(number)", "--repo", "\(owner)/\(repo)"])
    }

    public func commentOnPR(owner: String, repo: String, number: Int, body: String) async throws {
        _ = try await runner.run(
            ["pr", "comment", "\(number)", "--repo", "\(owner)/\(repo)", "--body-file", "-"],
            stdin: Data(body.utf8)
        )
    }

    // MARK: - Labels

    public func labels(owner: String, repo: String) async throws -> [GHLabel] {
        try await runner.runJSON([
            "label", "list", "--repo", "\(owner)/\(repo)",
            "--json", "name,color,description"
        ])
    }

    public func createLabel(
        owner: String, repo: String,
        name: String, color: String? = nil, description: String? = nil
    ) async throws {
        var args = ["label", "create", name, "--repo", "\(owner)/\(repo)"]
        if let color { args.append(contentsOf: ["--color", color]) }
        if let description { args.append(contentsOf: ["--description", description]) }
        _ = try await runner.run(args)
    }

    // MARK: - Workflow runs

    public func workflowRuns(owner: String, repo: String, limit: Int = 20) async throws -> [GHWorkflowRun] {
        try await runner.runJSON([
            "run", "list", "--repo", "\(owner)/\(repo)",
            "--limit", "\(limit)",
            "--json", "databaseId,displayTitle,event,headBranch,status,conclusion,url,createdAt"
        ])
    }

    public func dispatchWorkflow(
        owner: String, repo: String, workflow: String,
        ref: String, inputs: [String: String] = [:]
    ) async throws {
        var args = [
            "workflow", "run", workflow,
            "--repo", "\(owner)/\(repo)",
            "--ref", ref
        ]
        for (k, v) in inputs {
            args.append(contentsOf: ["-f", "\(k)=\(v)"])
        }
        _ = try await runner.run(args)
    }

    public func cancelRun(owner: String, repo: String, runId: Int64) async throws {
        _ = try await runner.run(["run", "cancel", "\(runId)", "--repo", "\(owner)/\(repo)"])
    }

    public func rerunRun(owner: String, repo: String, runId: Int64) async throws {
        _ = try await runner.run(["run", "rerun", "\(runId)", "--repo", "\(owner)/\(repo)"])
    }

    // MARK: - Branches

    public func createBranch(
        owner: String, repo: String, branch: String, fromSha: String
    ) async throws {
        _ = try await runner.run([
            "api", "-X", "POST",
            "repos/\(owner)/\(repo)/git/refs",
            "-f", "ref=refs/heads/\(branch)",
            "-f", "sha=\(fromSha)"
        ])
    }

    public func deleteBranch(owner: String, repo: String, branch: String) async throws {
        _ = try await runner.run([
            "api", "-X", "DELETE",
            "repos/\(owner)/\(repo)/git/refs/heads/\(branch)"
        ])
    }

    // MARK: - Reviews & checks

    public func reviewComments(
        owner: String, repo: String, number: Int,
        maxPages: Int = 5, perPage: Int = 100
    ) async throws -> [GHReviewComment] {
        struct Comment: Decodable {
            let id: Int64
            let body: String
            let path: String?
            let user: GHUser?
            let html_url: String
            let created_at: Date?
        }
        let comments: [Comment] = try await runner.runJSON([
            "api", "repos/\(owner)/\(repo)/pulls/\(number)/comments",
            "--paginate",
            "-F", "per_page=\(perPage)"
        ])
        let bounded = comments.prefix(maxPages * perPage)
        return bounded.map {
            GHReviewComment(
                id: $0.id,
                body: $0.body,
                path: $0.path,
                user: $0.user,
                createdAt: $0.created_at,
                url: $0.html_url
            )
        }
    }

    public func replyToReviewComment(
        owner: String, repo: String, number: Int,
        commentId: Int64, body: String
    ) async throws {
        _ = try await runner.run([
            "api", "-X", "POST",
            "repos/\(owner)/\(repo)/pulls/\(number)/comments/\(commentId)/replies",
            "-f", "body=\(body)"
        ])
    }

    public func reviewThreads(owner: String, repo: String, number: Int) async throws -> [GHReviewThread] {
        // GraphQL gives us thread IDs (REST only exposes comment IDs). We
        // need thread IDs to call resolveReviewThread.
        struct Response: Decodable {
            struct DataPayload: Decodable {
                struct Repo: Decodable {
                    struct PR: Decodable {
                        struct Threads: Decodable {
                            let nodes: [GHReviewThread]
                        }
                        let reviewThreads: Threads
                    }
                    let pullRequest: PR
                }
                let repository: Repo
            }
            let data: DataPayload
        }
        let query = """
            query($owner:String!,$repo:String!,$number:Int!){
              repository(owner:$owner,name:$repo){
                pullRequest(number:$number){
                  reviewThreads(first:100){
                    nodes{ id isResolved comments(first:1){ nodes{ databaseId } } }
                  }
                }
              }
            }
            """
        let env: Response = try await runner.runJSON([
            "api", "graphql",
            "-f", "query=\(query)",
            "-F", "owner=\(owner)",
            "-F", "repo=\(repo)",
            "-F", "number=\(number)"
        ])
        return env.data.repository.pullRequest.reviewThreads.nodes
    }

    public func resolveReviewThread(threadId: String) async throws {
        let mutation = "mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ id isResolved } } }"
        _ = try await runner.run([
            "api", "graphql",
            "-f", "query=\(mutation)",
            "-F", "id=\(threadId)"
        ])
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
