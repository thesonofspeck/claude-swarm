import Foundation
import UserNotifications
import UIKit

/// Manages APNs registration, notification categories, and routing of
/// notification actions back into the app.
@MainActor
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    @Published private(set) var deviceTokenHex: String?

    enum ActionEvent {
        case approve(approvalId: String, response: PairingResponseSurrogate)
        case openSession(sessionId: String)
    }

    /// Mirrors PairingProtocol.ApprovalResponse so this file doesn't import
    /// PairingProtocol just to forward the enum into NotificationCenter.
    enum PairingResponseSurrogate: String { case allow, deny }

    let actionsContinuation: AsyncStream<ActionEvent>.Continuation
    let actions: AsyncStream<ActionEvent>

    override init() {
        var c: AsyncStream<ActionEvent>.Continuation!
        actions = AsyncStream { continuation in c = continuation }
        actionsContinuation = c
        super.init()
    }

    func setUp() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        registerCategories(on: center)
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            // User declined; in-app notifications still work via .live state.
        }
    }

    func setDeviceToken(_ token: Data) {
        deviceTokenHex = token.map { String(format: "%02x", $0) }.joined()
    }

    private func registerCategories(on center: UNUserNotificationCenter) {
        let approve = UNNotificationAction(
            identifier: "APPROVAL_ALLOW",
            title: "Approve",
            options: [.authenticationRequired]
        )
        let deny = UNNotificationAction(
            identifier: "APPROVAL_DENY",
            title: "Deny",
            options: [.authenticationRequired, .destructive]
        )
        let approval = UNNotificationCategory(
            identifier: "APPROVAL_REQUEST",
            actions: [approve, deny],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let needsInput = UNNotificationCategory(
            identifier: "NEEDS_INPUT",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([approval, needsInput])
    }
}

extension PushManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let approvalId = info["approvalId"] as? String
        let sessionId = info["sessionId"] as? String

        Task { @MainActor [weak self] in
            guard let self else { completionHandler(); return }
            switch response.actionIdentifier {
            case "APPROVAL_ALLOW":
                if let approvalId {
                    self.actionsContinuation.yield(.approve(approvalId: approvalId, response: .allow))
                }
            case "APPROVAL_DENY":
                if let approvalId {
                    self.actionsContinuation.yield(.approve(approvalId: approvalId, response: .deny))
                }
            default:
                if let sessionId {
                    self.actionsContinuation.yield(.openSession(sessionId: sessionId))
                }
            }
            completionHandler()
        }
    }
}
