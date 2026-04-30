import Foundation
import PersistenceKit
import ClaudeSwarmNotifications

extension HookEvent {
    public var resultingStatus: SessionStatus? {
        switch kind {
        case .notification: return .waitingForInput
        case .stop: return .idle
        case .sessionStart: return .running
        case .other: return nil
        }
    }
}
