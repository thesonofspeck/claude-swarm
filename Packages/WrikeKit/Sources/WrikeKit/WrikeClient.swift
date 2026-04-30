import Foundation
import KeychainKit

public actor WrikeClient {
    public enum WrikeError: Error, LocalizedError {
        case missingToken
        case http(status: Int, body: String)
        case decoding(Error)
        case rateLimited(retryAfter: TimeInterval)
        case transport(Error)

        public var errorDescription: String? {
            switch self {
            case .missingToken: return "No Wrike token in Keychain. Add one in Settings."
            case .http(let s, let b): return "Wrike HTTP \(s): \(b)"
            case .decoding(let e): return "Wrike decode failed: \(e)"
            case .rateLimited(let s): return "Wrike rate-limited; retry in \(Int(s))s"
            case .transport(let e): return "Wrike network error: \(e)"
            }
        }
    }

    public let baseURL: URL
    public let session: URLSession
    public let keychain: Keychain
    public let maxRetries: Int

    public init(
        baseURL: URL = URL(string: "https://www.wrike.com/api/v4/")!,
        session: URLSession = .shared,
        keychain: Keychain = Keychain(),
        maxRetries: Int = 3
    ) {
        self.baseURL = baseURL
        self.session = session
        self.keychain = keychain
        self.maxRetries = maxRetries
    }

    public func setToken(_ token: String) throws {
        try keychain.set(token, account: KeychainAccount.wrike)
    }

    public func hasToken() async -> Bool {
        (try? keychain.get(account: KeychainAccount.wrike)) != nil
    }

    // MARK: - Endpoints

    public func tasks(in folderId: String) async throws -> [WrikeTask] {
        try await getList(path: "folders/\(folderId)/tasks", query: ["fields": "[description]"])
    }

    public func task(id: String) async throws -> WrikeTask? {
        try await getList(path: "tasks/\(id)", query: ["fields": "[description]"]).first
    }

    public func folders() async throws -> [WrikeFolder] {
        try await getList(path: "folders")
    }

    public func customStatuses() async throws -> [WrikeCustomStatus] {
        try await getList(path: "customstatuses")
    }

    /// Transition a task to a specific custom status. Wrike requires the
    /// raw custom-status id (workspace-specific); use `WrikeStatusMapper`
    /// to resolve a semantic transition like `.inProgress` to one.
    public func updateTaskStatus(taskId: String, customStatusId: String) async throws -> WrikeTask? {
        try await put(path: "tasks/\(taskId)", form: ["customStatus": customStatusId]).first
    }

    // MARK: - Tasks (full CRUD)

    public func createTask(in folderId: String, mutation: WrikeTaskMutation) async throws -> WrikeTask? {
        try await sendJSON(method: "POST", path: "folders/\(folderId)/tasks", body: mutation).first
    }

    public func updateTask(id: String, mutation: WrikeTaskMutation) async throws -> WrikeTask? {
        try await sendJSON(method: "PUT", path: "tasks/\(id)", body: mutation).first
    }

    public func deleteTask(id: String) async throws {
        _ = try await sendVoid(method: "DELETE", path: "tasks/\(id)")
    }

    // MARK: - Comments

    public func comments(taskId: String, limit: Int = 100) async throws -> [WrikeComment] {
        try await getList(path: "tasks/\(taskId)/comments", query: ["limit": "\(limit)"])
    }

    @discardableResult
    public func createComment(taskId: String, text: String, plainText: Bool = false) async throws -> WrikeComment? {
        var form: [String: String] = ["text": text]
        if plainText { form["plainText"] = "true" }
        return try await send(method: "POST", path: "tasks/\(taskId)/comments", form: form).first
    }

    public func deleteComment(id: String) async throws {
        _ = try await sendVoid(method: "DELETE", path: "comments/\(id)")
    }

    // MARK: - Attachments

    public func attachments(taskId: String) async throws -> [WrikeAttachment] {
        try await getList(path: "tasks/\(taskId)/attachments")
    }

    @discardableResult
    public func attachURL(taskId: String, url: String, name: String?) async throws -> WrikeAttachment? {
        var form: [String: String] = ["url": url]
        if let name { form["name"] = name }
        return try await send(method: "POST", path: "tasks/\(taskId)/attachments", form: form).first
    }

    // MARK: - Users

    public func currentUser() async throws -> WrikeUser? {
        try await getList(path: "contacts", query: ["me": "true"]).first
    }

    public func users() async throws -> [WrikeUser] {
        try await getList(path: "contacts")
    }

    // MARK: - HTTP plumbing

    private func put<T: Decodable>(path: String, form: [String: String]) async throws -> [T] {
        try await send(method: "PUT", path: path, form: form)
    }

    private func getList<T: Decodable>(path: String, query: [String: String] = [:]) async throws -> [T] {
        try await send(method: "GET", path: path, query: query)
    }

    private func sendJSON<T: Decodable, Body: Encodable>(
        method: String, path: String, body: Body
    ) async throws -> [T] {
        let encoder = JSONEncoder()
        let data = try encoder.encode(body)
        return try await send(method: method, path: path, jsonBody: data)
    }

    @discardableResult
    private func sendVoid(method: String, path: String) async throws -> Bool {
        struct Empty: Decodable {}
        let _: [Empty] = try await send(method: method, path: path)
        return true
    }

    private func send<T: Decodable>(
        method: String,
        path: String,
        query: [String: String] = [:],
        form: [String: String] = [:],
        jsonBody: Data? = nil
    ) async throws -> [T] {
        let token: String
        do { token = try keychain.get(account: KeychainAccount.wrike) }
        catch { throw WrikeError.missingToken }

        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw WrikeError.http(status: -1, body: "invalid url for path \(path)")
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw WrikeError.http(status: -1, body: "invalid url for path \(path)")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = jsonBody
        } else if !form.isEmpty {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = form.map { key, value -> String in
                let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(k)=\(v)"
            }.joined(separator: "&")
            req.httpBody = Data(body.utf8)
        }

        var attempt = 0
        while true {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw WrikeError.http(status: -1, body: "non-HTTP response")
                }
                switch http.statusCode {
                case 200..<300:
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    do {
                        return try decoder.decode(WrikeEnvelope<T>.self, from: data).data
                    } catch {
                        throw WrikeError.decoding(error)
                    }
                case 401, 403:
                    throw WrikeError.http(status: http.statusCode, body: bodyString(data))
                case 429:
                    let retry = (http.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(Double.init)) ?? pow(2.0, Double(attempt))
                    if attempt > maxRetries {
                        throw WrikeError.rateLimited(retryAfter: retry)
                    }
                    try await Task.sleep(nanoseconds: UInt64(retry * 1_000_000_000))
                case 500..<600:
                    if attempt > maxRetries {
                        throw WrikeError.http(status: http.statusCode, body: bodyString(data))
                    }
                    let backoff = pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                default:
                    throw WrikeError.http(status: http.statusCode, body: bodyString(data))
                }
            } catch let error as WrikeError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt > maxRetries { throw WrikeError.transport(error) }
                let backoff = pow(2.0, Double(attempt))
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
        }
    }

    private func bodyString(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }
}
