import Foundation
import KeychainKit

public actor GitHubClient {
    public enum GHError: Error, LocalizedError {
        case missingToken
        case http(status: Int, body: String)
        case decoding(Error)

        public var errorDescription: String? {
            switch self {
            case .missingToken: return "No GitHub token in Keychain or `gh` CLI"
            case .http(let s, let b): return "GitHub HTTP \(s): \(b)"
            case .decoding(let e): return "GitHub decode failed: \(e)"
            }
        }
    }

    public let baseURL: URL
    public let session: URLSession
    public let keychain: Keychain
    private var cachedToken: String?

    public init(
        baseURL: URL = URL(string: "https://api.github.com/")!,
        session: URLSession = .shared,
        keychain: Keychain = Keychain()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.keychain = keychain
    }

    public func setToken(_ token: String) throws {
        try keychain.set(token, account: KeychainAccount.github)
        cachedToken = token
    }

    private func token() async throws -> String {
        if let cached = cachedToken { return cached }
        if let kc = try? keychain.get(account: KeychainAccount.github) {
            cachedToken = kc
            return kc
        }
        if let gh = try? Self.readGhCliToken() {
            cachedToken = gh
            return gh
        }
        throw GHError.missingToken
    }

    private static func readGhCliToken() throws -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["gh", "auth", "token"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    // MARK: - REST

    public func listPullRequests(owner: String, repo: String, state: String = "open") async throws -> [GHPullRequest] {
        try await get("repos/\(owner)/\(repo)/pulls?state=\(state)")
    }

    public func pullRequest(owner: String, repo: String, number: Int) async throws -> GHPullRequest {
        try await get("repos/\(owner)/\(repo)/pulls/\(number)")
    }

    public func createPullRequest(
        owner: String, repo: String,
        title: String, head: String, base: String,
        body: String? = nil, draft: Bool = false
    ) async throws -> GHPullRequest {
        var payload: [String: Any] = [
            "title": title, "head": head, "base": base, "draft": draft
        ]
        if let body { payload["body"] = body }
        return try await post("repos/\(owner)/\(repo)/pulls", payload: payload)
    }

    public func reviewComments(owner: String, repo: String, number: Int) async throws -> [GHReviewComment] {
        try await get("repos/\(owner)/\(repo)/pulls/\(number)/comments")
    }

    public func checkRuns(owner: String, repo: String, sha: String) async throws -> [GHCheckRun] {
        let env: GHCheckRunsEnvelope = try await get("repos/\(owner)/\(repo)/commits/\(sha)/check-runs")
        return env.check_runs
    }

    public func searchPullRequests(query: String) async throws -> [GHPullRequest] {
        struct SearchEnvelope: Codable { let items: [GHPullRequest] }
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let env: SearchEnvelope = try await get("search/issues?q=\(escaped)+is:pr")
        return env.items
    }

    // MARK: - HTTP plumbing

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path: path, method: "GET", body: nil)
    }

    private func post<T: Decodable>(_ path: String, payload: [String: Any]) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try await request(path: path, method: "POST", body: body)
    }

    private func request<T: Decodable>(path: String, method: String, body: Data?) async throws -> T {
        let token = try await token()
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw GHError.http(status: -1, body: "invalid url for path \(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.httpBody = body
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GHError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw GHError.decoding(error) }
    }
}

