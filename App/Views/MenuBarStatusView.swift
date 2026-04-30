import SwiftUI
import AppCore
import PersistenceKit
import ClaudeSwarmNotifications

struct MenuBarStatusView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var notifier: Notifier
    @EnvironmentObject var projectList: ProjectListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if waitingSessions.isEmpty {
                Text("No sessions waiting")
                    .font(Type.body)
                    .foregroundStyle(Palette.fgMuted)
                    .padding(Metrics.Space.md)
            } else {
                ForEach(waitingSessions) { session in
                    Button { focus(session: session) } label: {
                        HStack(spacing: Metrics.Space.sm) {
                            Circle().fill(Palette.yellow).frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.taskTitle ?? session.branch)
                                    .font(Type.body)
                                Text(projectName(for: session))
                                    .font(Type.caption)
                                    .foregroundStyle(Palette.fgMuted)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, Metrics.Space.md)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            HStack {
                Button("Open Claude Swarm") { openMainWindow() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(.horizontal, Metrics.Space.md)
            .padding(.vertical, 6)
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(Palette.blue)
            Text("Claude Swarm")
                .font(Type.heading)
            Spacer()
            if !waitingSessions.isEmpty {
                Pill(text: "\(waitingSessions.count)", systemImage: "circle.fill", tint: Palette.yellow)
            }
        }
        .padding(Metrics.Space.md)
    }

    private var waitingSessions: [Session] {
        projectList.projects.flatMap { project in
            projectList.sessions(for: project.id)
                .filter { notifier.pendingSessionIds.contains($0.id) }
        }
    }

    private func projectName(for session: Session) -> String {
        projectList.projects.first { $0.id == session.projectId }?.name ?? ""
    }

    private func focus(session: Session) {
        openMainWindow()
        NotificationCenter.default.post(name: .swarmFocusSession, object: session.id)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeKey {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
}

extension Notification.Name {
    static let swarmFocusSession = Notification.Name("ClaudeSwarm.FocusSession")
}
