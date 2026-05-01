import Foundation
import Observation
import UserNotifications
import UIKit

/// Manages APNs registration, notification categories, and routing of
/// notification actions back into the app.
@MainActor
@Observable
final class PushManager: NSObject {
    static let shared = PushManager()

    private(set) var deviceTokenHex: String?

    enum ActionEvent {
        case approve(approvalId: String, response: PairingResponseSurrogate)
        case openSession(sessionId: String)
    }

    /// Mirrors PairingProtocol.ApprovalResponse so this file doesn't import
    /// PairingProtocol just to forward the enum into NotificationCenter.
    enum PairingResponseSurrogate: String { case allow, deny }

    @ObservationIgnored
    let actionsContinuation: AsyncStream<ActionEvent>.Continuation
    @ObservationIgnored
    let actions: AsyncStream<ActionEvent>

    /// Stream of device-token changes so AppHub can fan-out to RelayClients
    /// without depending on Combine's `$deviceTokenHex.values`.
    @ObservationIgnored
    let tokens: AsyncStream<String?>
    @ObservationIgnored
    private let tokensContinuation: AsyncStream<String?>.Continuation

    override init() {
        var c: AsyncStream<ActionEvent>.Continuation!
        actions = AsyncStream { continuation in c = continuation }
        actionsContinuation = c
        var t: AsyncStream<String?>.Continuation!
        tokens = AsyncStream { continuation in t = continuation }
        tokensContinuation = t
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
        let hex = token.map { String(format: "%02x", $0) }.joined()
        deviceTokenHex = hex
        tokensContinuation.yield(hex)
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
