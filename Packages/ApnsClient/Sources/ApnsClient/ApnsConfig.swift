import Foundation

public struct ApnsConfig: Codable, Equatable, Sendable {
    public enum Environment: String, Codable, Sendable {
        case sandbox, production
        public var host: String {
            switch self {
            case .sandbox:    return "api.sandbox.push.apple.com"
            case .production: return "api.push.apple.com"
            }
        }
    }

    public var teamId: String         // 10-char Apple Developer team id
    public var keyId: String          // 10-char .p8 key id
    public var bundleId: String       // iOS app bundle id (apns-topic)
    public var environment: Environment
    public var enabled: Bool

    public init(
        teamId: String = "",
        keyId: String = "",
        bundleId: String = "com.claudeswarm.remote",
        environment: Environment = .production,
        enabled: Bool = false
    ) {
        self.teamId = teamId
        self.keyId = keyId
        self.bundleId = bundleId
        self.environment = environment
        self.enabled = enabled
    }

    public var isComplete: Bool {
        !teamId.isEmpty && !keyId.isEmpty && !bundleId.isEmpty
    }
}

public enum ApnsKeyStorage {
    public static let keyAccount = "apns-p8"
}
