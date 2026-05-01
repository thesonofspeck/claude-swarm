import SwiftUI
import Observation
import AppCore
import ClaudeSwarmNotifications

@main
struct ClaudeSwarmApp: App {
    @State private var bootstrap = AppBootstrap()

    var body: some Scene {
        WindowGroup {
            BootstrapWindow(bootstrap: bootstrap)
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
            BootstrapSettings(bootstrap: bootstrap)
        }

        MenuBarExtra {
            BootstrapMenuBar(bootstrap: bootstrap)
        } label: {
            MenuBarLabel(bootstrap: bootstrap)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
@Observable
final class AppBootstrap {
    enum State {
        case loading
        case ready(AppEnvironment)
        case failed(Error)
    }

    var state: State = .loading

    init() { retry() }

    func retry() {
        state = .loading
        do {
            state = .ready(try AppEnvironment())
        } catch {
            state = .failed(error)
        }
    }
}

private struct BootstrapWindow: View {
    let bootstrap: AppBootstrap

    var body: some View {
        switch bootstrap.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.bgBase)
                .frame(minWidth: 1100, minHeight: 700)
        case .ready(let env):
            RootSplitView()
                .environment(env)
                .environment(env.notifier)
                .environment(env.projectList)
                .environment(env.registry)
                .frame(minWidth: 1100, minHeight: 700)
                .background(Palette.bgBase)
                .tint(Palette.blue)
                .task { await env.notifier.requestAuthorization() }
        case .failed(let error):
            RecoveryView(error: error) { bootstrap.retry() }
                .frame(minWidth: 1100, minHeight: 700)
        }
    }
}

private struct BootstrapSettings: View {
    let bootstrap: AppBootstrap
    var body: some View {
        if case .ready(let env) = bootstrap.state {
            SettingsSheet()
                .environment(env)
                .tint(Palette.blue)
        } else {
            Text("Claude Swarm is not running.")
                .foregroundStyle(Palette.fgMuted)
                .padding()
        }
    }
}

private struct BootstrapMenuBar: View {
    let bootstrap: AppBootstrap
    var body: some View {
        if case .ready(let env) = bootstrap.state {
            MenuBarStatusView()
                .environment(env)
                .environment(env.notifier)
                .environment(env.projectList)
        } else {
            Text("Claude Swarm is starting…")
                .foregroundStyle(Palette.fgMuted)
                .padding()
        }
    }
}

private struct MenuBarLabel: View {
    let bootstrap: AppBootstrap
    var body: some View {
        switch bootstrap.state {
        case .ready(let env):
            MenuBarLabelInner(notifier: env.notifier)
        default:
            Image(systemName: "sparkles.rectangle.stack")
        }
    }
}

private struct MenuBarLabelInner: View {
    let notifier: Notifier
    var body: some View {
        let n = notifier.pendingSessionIds.count
        if n > 0 {
            Image(systemName: "\(n).circle.fill")
        } else {
            Image(systemName: "sparkles.rectangle.stack")
        }
    }
}

struct RecoveryView: View {
    let error: Error
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: Metrics.Space.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Palette.red)
            Text("Claude Swarm couldn't start")
                .font(Type.display)
                .foregroundStyle(Palette.fgBright)
            Text(error.localizedDescription)
                .font(Type.body)
                .foregroundStyle(Palette.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            VStack(spacing: Metrics.Space.sm) {
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)

                Button {
                    NSWorkspace.shared.open(supportFolderURL)
                } label: {
                    Label("Open Application Support folder", systemImage: "folder").frame(maxWidth: .infinity)
                }

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power").frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: 280)

            Text("If the issue persists, move ~/Library/Application Support/ClaudeSwarm aside to reset local state.")
                .font(Type.caption)
                .foregroundStyle(Palette.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgBase)
    }

    private var supportFolderURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClaudeSwarm", isDirectory: true)
    }
}

extension Notification.Name {
    static let swarmAddProject = Notification.Name("ClaudeSwarm.AddProject")
    static let swarmSelectTab = Notification.Name("ClaudeSwarm.SelectTab")
    static let swarmRefresh = Notification.Name("ClaudeSwarm.Refresh")
}
