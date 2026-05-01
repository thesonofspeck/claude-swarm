import SwiftUI
import Observation
import UIKit
import PairingProtocol

@main
struct ClaudeSwarmRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var hub = AppHub()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(hub)
                .environment(PushManager.shared)
                .background(Palette.bgBase.ignoresSafeArea())
                .tint(Palette.blue)
                .task { await hub.bootstrap() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Task { @MainActor in await PushManager.shared.setUp() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        Task { @MainActor in PushManager.shared.setDeviceToken(token) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Soft fail: app still works in foreground without push.
    }
}

@MainActor
@Observable
final class AppHub {
    var pairedMacs: [PairedMac] = []
    var clients: [String: RelayClient] = [:]   // keyed by macId

    let store = PairedMacStore()

    func bootstrap() async {
        pairedMacs = store.all()
        for mac in pairedMacs {
            ensureClient(for: mac)
        }
        Task { await observePushActions() }
        Task { await observeApnsToken() }
    }

    func ensureClient(for mac: PairedMac) {
        if clients[mac.macId] == nil {
            let client = RelayClient(mac: mac, deviceId: store.deviceId)
            clients[mac.macId] = client
            client.connect()
        }
    }

    func unpair(_ mac: PairedMac) {
        clients[mac.macId]?.disconnect()
        clients.removeValue(forKey: mac.macId)
        store.remove(macId: mac.macId)
        pairedMacs = store.all()
    }

    func savePaired(_ mac: PairedMac) {
        store.save(mac)
        pairedMacs = store.all()
        ensureClient(for: mac)
    }

    private func observePushActions() async {
        for await event in PushManager.shared.actions {
            switch event {
            case .approve(let approvalId, let response):
                let wireResponse: ApprovalResponse = response == .allow ? .allow : .deny
                for client in clients.values {
                    if client.pendingApprovals.contains(where: { $0.id == approvalId }) {
                        client.send(.approve(approvalId: approvalId, response: wireResponse))
                    }
                }
            case .openSession:
                break
            }
        }
    }

    private func observeApnsToken() async {
        // Mirror token changes into every RelayClient so the next Hello
        // carries it to the Mac.
        for await token in PushManager.shared.tokens {
            for client in clients.values {
                client.updateApnsToken(token)
            }
        }
    }
}
