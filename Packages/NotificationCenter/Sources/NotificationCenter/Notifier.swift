import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(AppKit)
import AppKit
#endif

@MainActor
public final class Notifier: ObservableObject {
    @Published public private(set) var pendingSessionIds: Set<String> = []

    public init() {}

    public func requestAuthorization() async {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        #endif
    }

    public func sessionNeedsInput(sessionId: String, title: String, body: String, isForeground: Bool) {
        let (inserted, _) = pendingSessionIds.insert(sessionId)
        guard inserted else { return }
        updateDockBadge()
        guard !isForeground else { return }

        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["sessionId": sessionId]
        let request = UNNotificationRequest(
            identifier: "session-needs-input-\(sessionId)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        #endif
    }

    public func clear(sessionId: String) {
        guard pendingSessionIds.remove(sessionId) != nil else { return }
        updateDockBadge()
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["session-needs-input-\(sessionId)"])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: ["session-needs-input-\(sessionId)"])
        #endif
    }

    private func updateDockBadge() {
        #if canImport(AppKit)
        let count = pendingSessionIds.count
        NSApp?.dockTile.badgeLabel = count == 0 ? nil : "\(count)"
        #endif
    }
}
