import Foundation

public struct WrikeFolder: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let scope: String?
    public let permalink: String?
}

public struct WrikeTask: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let description: String?
    public let status: String
    public let permalink: String?
    public let importance: String?
    public let updatedDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, description, status, permalink, importance, updatedDate
    }
}

public struct WrikeCustomStatus: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let group: String
    public let standard: Bool
    public let color: String?
}

struct WrikeEnvelope<T: Codable>: Codable {
    let kind: String?
    let data: [T]

    enum CodingKeys: String, CodingKey {
        case kind, data
    }
}
