import Foundation
import GRDB

public struct Project: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public var id: String
    public var name: String
    public var localPath: String
    public var defaultBaseBranch: String
    public var wrikeFolderId: String?
    public var githubOwner: String?
    public var githubRepo: String?
    public var createdAt: Date

    public static let databaseTableName = "project"

    public init(
        id: String = UUID().uuidString,
        name: String,
        localPath: String,
        defaultBaseBranch: String = "main",
        wrikeFolderId: String? = nil,
        githubOwner: String? = nil,
        githubRepo: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.localPath = localPath
        self.defaultBaseBranch = defaultBaseBranch
        self.wrikeFolderId = wrikeFolderId
        self.githubOwner = githubOwner
        self.githubRepo = githubRepo
        self.createdAt = createdAt
    }
}

public enum SessionStatus: String, Codable, CaseIterable {
    case starting
    case running
    case waitingForInput
    case idle
    case finished
    case archived
    case prOpen
    case merged
    case failed
}

public struct Session: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public var id: String
    public var projectId: String
    public var taskId: String?
    public var taskTitle: String?
    public var branch: String
    public var worktreePath: String
    public var status: SessionStatus
    public var pid: Int32?
    public var prNumber: Int?
    public var transcriptPath: String
    public var createdAt: Date
    public var updatedAt: Date

    public static let databaseTableName = "session"

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        taskId: String? = nil,
        taskTitle: String? = nil,
        branch: String,
        worktreePath: String,
        status: SessionStatus = .starting,
        pid: Int32? = nil,
        prNumber: Int? = nil,
        transcriptPath: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.branch = branch
        self.worktreePath = worktreePath
        self.status = status
        self.pid = pid
        self.prNumber = prNumber
        self.transcriptPath = transcriptPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CachedTask: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public var id: String                 // Wrike task id
    public var projectId: String
    public var title: String
    public var descriptionText: String
    public var status: String
    public var permalink: String?
    public var fetchedAt: Date

    public static let databaseTableName = "task_cache"
}

public struct CachedPR: Codable, Identifiable, Equatable, FetchableRecord, MutablePersistableRecord {
    public var id: String                 // owner/repo#number
    public var sessionId: String?
    public var owner: String
    public var repo: String
    public var number: Int
    public var title: String
    public var state: String
    public var url: String
    public var headSha: String
    public var checksPassing: Int
    public var checksTotal: Int
    public var reviewCount: Int
    public var fetchedAt: Date

    public static let databaseTableName = "pr_cache"
}
