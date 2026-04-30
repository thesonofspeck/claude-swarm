import SwiftUI
import AppCore

@main
struct ClaudeSwarmApp: App {
    @StateObject private var env: AppEnvironment

    init() {
        do {
            _env = StateObject(wrappedValue: try AppEnvironment())
        } catch {
            fatalError("Failed to start app environment: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootSplitView()
                .environmentObject(env)
                .environmentObject(env.notifier)
                .environmentObject(env.projectList)
                .environmentObject(env.registry)
                .frame(minWidth: 1100, minHeight: 700)
                .task {
                    await env.notifier.requestAuthorization()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") {}
                    .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsSheet()
                .environmentObject(env)
        }
    }
}
