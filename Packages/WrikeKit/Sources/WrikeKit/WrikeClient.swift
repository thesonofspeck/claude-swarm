import Foundation
import KeychainKit

public actor WrikeClient {
    public enum WrikeError: Error, LocalizedError {
        case missingToken
        case http(status: Int, body: String)
        case decoding(Error)

        public var errorDescription: String? {
            switch self {
            case .missingToken: return "No Wrike token in Keychain"
            case .http(let s, let b): return "Wrike HTTP \(s): \(b)"
            case .decoding(let e): return "Wrike decode failed: \(e)"
            }
        }
    }

    public let baseURL: URL
    public let session: URLSession
    public let keychain: Keychain

    public init(
        baseURL: URL = URL(string: "https://www.wrike.com/api/v4")!,
        session: URLSession = .shared,
        keychain: Keychain = Keychain()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.keychain = keychain
    }

    public func setToken(_ token: String) throws {
        try keychain.set(token, account: KeychainAccount.wrike)
    }

    public func tasks(in folderId: String) async throws -> [WrikeTask] {
        try await getList("folders/\(folderId)/tasks?fields=[description]")
    }

    public func task(id: String) async throws -> WrikeTask? {
        try await getList("tasks/\(id)?fields=[description]").first
    }

    public func folders() async throws -> [WrikeFolder] {
        try await getList("folders")
    }

    public func customStatuses() async throws -> [WrikeCustomStatus] {
        try await getList("workflows")
    }

    private func getList<T: Codable>(_ path: String) async throws -> [T] {
        let token: String
        do { token = try keychain.get(account: KeychainAccount.wrike) }
        catch { throw WrikeError.missingToken }

        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw WrikeError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(WrikeEnvelope<T>.self, from: data).data
        } catch {
            throw WrikeError.decoding(error)
        }
    }
}
