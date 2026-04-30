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
                .background(Palette.bgBase)
                .tint(Palette.blue)
                .task { await env.notifier.requestAuthorization() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") {
                    NotificationCenter.default.post(name: .swarmNewSession, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Add Project…") {
                    NotificationCenter.default.post(name: .swarmAddProject, object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Command Palette") {
                    NotificationCenter.default.post(name: .swarmCommandPalette, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                ForEach(Array(DetailTab.allCases.enumerated()), id: \.element) { idx, tab in
                    if idx < 9 {
                        Button(tab.label) {
                            NotificationCenter.default.post(name: .swarmSelectTab, object: tab.rawValue)
                        }
                        .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: .command)
                    }
                }

                Button("Refresh") {
                    NotificationCenter.default.post(name: .swarmRefresh, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsSheet()
                .environmentObject(env)
                .tint(Palette.blue)
        }
    }
}

extension Notification.Name {
    static let swarmAddProject = Notification.Name("ClaudeSwarm.AddProject")
    static let swarmSelectTab = Notification.Name("ClaudeSwarm.SelectTab")
    static let swarmRefresh = Notification.Name("ClaudeSwarm.Refresh")
}
