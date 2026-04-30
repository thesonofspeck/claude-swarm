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
    public let descriptionText: String?
    public let status: String
    public let permalink: String?
    public let importance: String?
    public let updatedDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, status, permalink, importance, updatedDate
        case descriptionText = "description"
    }

    public var descriptionPlainText: String {
        WrikeText.strip(descriptionText ?? "")
    }
}

public enum WrikeText {
    public static func strip(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct WrikeCustomStatus: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let group: String
    public let standard: Bool?
    public let color: String?
}

struct WrikeEnvelope<T: Decodable>: Decodable {
    let kind: String?
    let data: [T]
}
