import Foundation

public struct GHUser: Codable, Equatable, Sendable {
    public let login: String
    public let avatar_url: String?
}

public struct GHPullRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    public let state: String
    public let html_url: String
    public let user: GHUser?
    public let head: Ref
    public let base: Ref
    public let draft: Bool?
    public let merged: Bool?

    public struct Ref: Codable, Equatable, Sendable {
        public let ref: String
        public let sha: String
    }
}

public struct GHReviewComment: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let body: String
    public let path: String?
    public let user: GHUser?
    public let created_at: String
    public let html_url: String
}

public struct GHCheckRun: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let status: String          // queued | in_progress | completed
    public let conclusion: String?     // success | failure | neutral | cancelled | skipped | timed_out | action_required
    public let html_url: String?
}

struct GHCheckRunsEnvelope: Codable {
    let total_count: Int
    let check_runs: [GHCheckRun]
}

public struct GHRepo: Codable, Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let full_name: String
    public let html_url: String
    public let owner: GHUser
}
