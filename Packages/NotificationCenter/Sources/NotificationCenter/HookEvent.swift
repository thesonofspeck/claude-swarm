import Foundation

public struct HookEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case notification = "Notification"
        case stop = "Stop"
        case sessionStart = "SessionStart"
        case postToolUse = "PostToolUse"
        case other
    }

    public let kind: Kind
    public let sessionId: String?
    public let projectPath: String?
    public let message: String?
    public let timestamp: Date

    public init(kind: Kind, sessionId: String?, projectPath: String?, message: String?, timestamp: Date = Date()) {
        self.kind = kind
        self.sessionId = sessionId
        self.projectPath = projectPath
        self.message = message
        self.timestamp = timestamp
    }
}
