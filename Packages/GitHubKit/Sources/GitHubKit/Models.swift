import Foundation

public struct GHUser: Codable, Equatable, Sendable {
    public let login: String
}

public enum GHPRState: String, Codable, Equatable, Sendable {
    case open, closed, merged

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
        guard let state = GHPRState(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown PR state: \(raw)"
            )
        }
        self = state
    }
}

public enum GHCheckConclusion: String, Codable, Equatable, Sendable {
    case success
    case failure
    case neutral
    case cancelled
    case skipped
    case timedOut = "timed_out"
    case actionRequired = "action_required"
    case stale
}

public struct GHPullRequest: Codable, Equatable, Identifiable, Sendable {
    public let number: Int
    public let title: String
    public let body: String?
    public let state: GHPRState
    public let url: String
    public let isDraft: Bool?
    public let merged: Bool?
    public let headRefName: String?
    public let baseRefName: String?
    public let headRefOid: String?
    public let author: GHUser?

    public var id: Int { number }
}

public struct GHReviewComment: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let body: String
    public let path: String?
    public let user: GHUser?
    public let createdAt: Date?
    public let url: String?

    enum CodingKeys: String, CodingKey {
        case id, body, path, user, url
        case createdAt = "created_at"
    }
}

public struct GHCheckRun: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let state: String
    public let conclusion: GHCheckConclusion?
    public let link: String?
    public let bucket: String?

    public var id: String { name + (link ?? "") }
}

public struct GHReviewThread: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let isResolved: Bool
    public let comments: Comments

    public struct Comments: Codable, Equatable, Sendable {
        public let nodes: [Comment]
        public struct Comment: Codable, Equatable, Sendable {
            public let databaseId: Int64
        }
    }

    public var firstCommentId: Int64? { comments.nodes.first?.databaseId }
}

public struct GHRepoSummary: Codable, Equatable, Identifiable, Sendable {
    public let nameWithOwner: String
    public let description: String?
    public let url: String
    public let isPrivate: Bool?
    public let updatedAt: Date?

    public var id: String { nameWithOwner }
}
