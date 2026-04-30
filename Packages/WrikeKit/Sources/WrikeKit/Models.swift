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

public struct WrikeUser: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let firstName: String?
    public let lastName: String?
    public let primaryEmail: String?
    public let title: String?
    public let avatarUrl: String?
    public let timezone: String?

    public var displayName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }
}

public struct WrikeComment: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let authorId: String?
    public let text: String
    public let createdDate: Date?
    public let taskId: String?
    public let folderId: String?
}

public struct WrikeAttachment: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: String?
    public let createdDate: Date?
    public let size: Int?
    public let type: String?
    public let taskId: String?
    public let authorId: String?
}

public struct WrikeCustomField: Codable, Equatable, Sendable {
    public let id: String
    public var value: String
}

/// Body shape used by `updateTask` / `createTask` JSON requests.
public struct WrikeTaskMutation: Codable, Equatable, Sendable {
    public var title: String?
    public var description: String?
    public var status: String?           // "Active" | "Completed" | "Deferred" | "Cancelled"
    public var importance: String?       // "High" | "Normal" | "Low"
    public var dates: Dates?
    public var priorityBefore: String?
    public var priorityAfter: String?
    public var responsibles: [String]?
    public var followers: [String]?
    public var addParents: [String]?
    public var removeParents: [String]?
    public var customFields: [WrikeCustomField]?

    public struct Dates: Codable, Equatable, Sendable {
        public var type: String?
        public var duration: Int?
        public var start: String?
        public var due: String?

        public init(type: String? = nil, duration: Int? = nil, start: String? = nil, due: String? = nil) {
            self.type = type; self.duration = duration; self.start = start; self.due = due
        }
    }

    public init(
        title: String? = nil, description: String? = nil,
        status: String? = nil, importance: String? = nil,
        dates: Dates? = nil,
        priorityBefore: String? = nil, priorityAfter: String? = nil,
        responsibles: [String]? = nil, followers: [String]? = nil,
        addParents: [String]? = nil, removeParents: [String]? = nil,
        customFields: [WrikeCustomField]? = nil
    ) {
        self.title = title; self.description = description
        self.status = status; self.importance = importance
        self.dates = dates
        self.priorityBefore = priorityBefore; self.priorityAfter = priorityAfter
        self.responsibles = responsibles; self.followers = followers
        self.addParents = addParents; self.removeParents = removeParents
        self.customFields = customFields
    }
}

struct WrikeEnvelope<T: Decodable>: Decodable {
    let kind: String?
    let data: [T]
}
