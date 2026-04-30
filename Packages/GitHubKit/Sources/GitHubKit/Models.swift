import Foundation

public struct GHUser: Codable, Equatable, Sendable {
    public let login: String
}

public struct GHPullRequest: Codable, Equatable, Identifiable, Sendable {
    public let number: Int
    public let title: String
    public let body: String?
    public let state: String
    public let url: String
    public let isDraft: Bool?
    public let merged: Bool?
    public let headRefName: String?
    public let baseRefName: String?
    public let headRefOid: String?
    public let author: GHUser?

    public var id: Int { number }

    enum CodingKeys: String, CodingKey {
        case number, title, body, state, url
        case isDraft, merged
        case headRefName, baseRefName, headRefOid, author
    }
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
    public let state: String          // queued, in_progress, completed
    public let conclusion: String?    // success, failure, neutral, cancelled, skipped, timed_out, action_required
    public let link: String?
    public let bucket: String?

    public var id: String { name + (link ?? "") }
}

public struct GHRepoSummary: Codable, Equatable, Identifiable, Sendable {
    public let nameWithOwner: String
    public let description: String?
    public let url: String
    public let isPrivate: Bool?
    public let updatedAt: Date?

    public var id: String { nameWithOwner }
}
