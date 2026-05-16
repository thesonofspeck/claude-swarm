import SwiftUI
import AppCore
import PersistenceKit
import ClaudeSwarmNotifications

struct SidebarView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ProjectListViewModel.self) private var projectList
    @Environment(Notifier.self) private var notifier
    @Binding var selectedSession: Session?
    @Binding var newSessionProjectId: String?
    @State private var showingAddProject = false
    @State private var showingSettings = false
    @State private var droppedPath: String? = nil

    var body: some View {
        List(selection: $selectedSession) {
            Button {
                selectedSession = nil
            } label: {
                Label {
                    Text("Home")
                        .font(Type.body)
                        .foregroundStyle(Palette.fgBright)
                } icon: {
                    Image(systemName: "house.fill")
                        .foregroundStyle(Palette.cyan)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
            .keyboardShortcut("0", modifiers: .command)
            .help("Welcome — ⌘0")

            if !recentSessions.isEmpty {
                Section("Recent") {
                    ForEach(recentSessions) { session in
                        Button {
                            selectedSession = session
                        } label: {
                            sessionRow(session, baseBranch: baseBranch(for: session))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            selectedSession?.id == session.id
                                ? Palette.bgSelection
                                : Color.clear
                        )
                        .contextMenu { sessionContextMenu(session) }
                    }
                }
            }

            ForEach(projectList.projects) { project in
                Section {
                    let sessions = projectList.sessions(for: project.id)
                    if sessions.isEmpty {
                        Button {
                            newSessionProjectId = project.id
                        } label: {
                            Label("New session", systemImage: "plus.circle")
                                .font(Type.caption)
                                .foregroundStyle(Palette.fgMuted)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, Metrics.Space.xs)
                    } else {
                        ForEach(sessions) { session in
                            sessionRow(session, baseBranch: project.defaultBaseBranch).tag(session)
                                .contextMenu { sessionContextMenu(session) }
                        }
                        Button {
                            newSessionProjectId = project.id
                        } label: {
                            Label("New session", systemImage: "plus.circle.fill")
                                .font(Type.caption)
                                .foregroundStyle(Palette.blue)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, Metrics.Space.xs)
                    }
                } header: {
                    projectHeader(project)
                        .contextMenu { projectContextMenu(project) }
                }
            }

            Button {
                showingAddProject = true
            } label: {
                Label("Add project", systemImage: "folder.badge.plus")
                    .foregroundStyle(Palette.blue)
            }
            .buttonStyle(.plain)
            .padding(.top, Metrics.Space.sm)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.bgSidebar)
        .onDrop(of: [.fileURL], delegate: ProjectDropDelegate(showSheet: $showingAddProject, sheetPath: $droppedPath))
        .sheet(isPresented: $showingAddProject) {
            AddProjectSheet(initialPath: droppedPath).environment(env)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet().environment(env)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                IconButton(systemImage: "gearshape", help: "Settings") {
                    showingSettings = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .swarmAddProject)) { _ in
            showingAddProject = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .swarmRefresh)) { _ in
            projectList.reload()
        }
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: Session) -> some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: session.worktreePath))
        } label: { Label("Open worktree in Finder", systemImage: "folder") }
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(session.branch, forType: .string)
        } label: { Label("Copy branch name", systemImage: "doc.on.doc") }
        Divider()
        Button(role: .destructive) {
            Task {
                try? await env.sessionManager.close(sessionId: session.id, deleteWorktree: true)
                projectList.reload()
            }
        } label: { Label("Delete worktree…", systemImage: "trash") }
    }

    @ViewBuilder
    private func projectContextMenu(_ project: Project) -> some View {
        Button {
            newSessionProjectId = project.id
        } label: { Label("New session…", systemImage: "plus.circle") }
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: project.localPath))
        } label: { Label("Open in Finder", systemImage: "folder") }
        Button {
            Task {
                try? await env.sessionManager.bootstrap(project: project)
            }
        } label: { Label("Reset agents to default", systemImage: "arrow.counterclockwise") }
        Divider()
        Button(role: .destructive) {
            projectList.remove(projectId: project.id)
        } label: { Label("Remove project", systemImage: "minus.circle") }
    }

    /// Recently-touched sessions across every project — the flat
    /// "watch and resume" rail at the top of the sidebar.
    private var recentSessions: [Session] {
        projectList.sessionsByProject.values
            .flatMap { $0 }
            .filter { $0.status != .archived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(6)
            .map { $0 }
    }

    private func baseBranch(for session: Session) -> String {
        projectList.projects.first { $0.id == session.projectId }?.defaultBaseBranch ?? "main"
    }

    private func projectHeader(_ project: Project) -> some View {
        let pendingCount = projectList.sessions(for: project.id)
            .filter { notifier.pendingSessionIds.contains($0.id) }.count
        return HStack(spacing: Metrics.Space.sm) {
            ProjectInitial(name: project.name)
            Text(project.name)
                .font(Type.heading)
                .foregroundStyle(Palette.fgBright)
            Spacer()
            if pendingCount > 0 {
                Pill(text: "\(pendingCount)", systemImage: "circle.fill", tint: Palette.yellow)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sessionRow(_ session: Session, baseBranch: String) -> some View {
        let needsInput = notifier.pendingSessionIds.contains(session.id)
        let stat = env.sessionStats.stat(for: session.id)
        HStack(alignment: .top, spacing: Metrics.Space.sm) {
            if needsInput {
                PulseDot(color: Palette.yellow)
                    .padding(.top, 4)
            } else {
                Image(systemName: statusIcon(session.status))
                    .imageScale(.small)
                    .foregroundStyle(statusColor(session.status))
                    .frame(width: 10)
                    .padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(session.taskTitle ?? session.branch)
                    .font(Type.body.weight(.medium))
                    .foregroundStyle(Palette.fgBright)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(statusLabel(session.status))
                        .font(Type.label)
                        .foregroundStyle(statusColor(session.status))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(statusColor(session.status).opacity(0.14))
                        )
                    Text(session.branch)
                        .font(Type.monoCaption)
                        .foregroundStyle(Palette.fgMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    if let stat, !stat.isEmpty {
                        HStack(spacing: 4) {
                            Text("+\(stat.added)")
                                .foregroundStyle(Palette.green)
                            Text("−\(stat.removed)")
                                .foregroundStyle(Palette.red)
                        }
                        .font(Type.monoCaption)
                    }
                }
            }
        }
        .padding(.vertical, 3)
        .task(id: session.updatedAt) {
            await env.sessionStats.ensure(
                sessionId: session.id,
                worktreePath: session.worktreePath,
                baseBranch: baseBranch,
                stamp: session.updatedAt
            )
        }
        .accessibilityLabel(accessibilityText(session, needsInput: needsInput, stat: stat))
    }

    private func accessibilityText(_ session: Session, needsInput: Bool, stat: SessionStatStore.Stat?) -> String {
        var parts = [session.taskTitle ?? session.branch, statusLabel(session.status)]
        if needsInput { parts.append("Needs input") }
        if let stat, !stat.isEmpty {
            parts.append("\(stat.added) added, \(stat.removed) removed")
        }
        return parts.joined(separator: ". ")
    }

    private func statusLabel(_ status: SessionStatus) -> String {
        switch status {
        case .starting: return "starting"
        case .running: return "running"
        case .waitingForInput: return "waiting"
        case .idle: return "idle"
        case .finished: return "done"
        case .archived: return "archived"
        case .prOpen: return "PR open"
        case .merged: return "merged"
        case .failed: return "failed"
        }
    }

    private func statusIcon(_ status: SessionStatus) -> String {
        switch status {
        case .starting, .running: return "circle.dotted"
        case .waitingForInput: return "circle.fill"
        case .idle: return "pause.circle"
        case .finished, .archived: return "checkmark.circle"
        case .prOpen: return "arrow.triangle.pull"
        case .merged: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .starting, .running: return Palette.green
        case .waitingForInput: return Palette.yellow
        case .idle: return Palette.fgMuted
        case .finished, .archived: return Palette.fgMuted
        case .prOpen: return Palette.blue
        case .merged: return Palette.purple
        case .failed: return Palette.red
        }
    }
}

/// Tinted circle with the project's first letter — gives each project a
/// distinct visual hook without requiring a real avatar.
struct ProjectInitial: View {
    let name: String

    private var letter: String {
        String(name.prefix(1)).uppercased()
    }

    private var tint: Color {
        // Sum of UTF-8 bytes, not `hashValue` — `String.hashValue` is
        // seeded per process launch, so a project's colour would change
        // every time the app restarts.
        let hue = name.utf8.reduce(0) { $0 &+ Int($1) } % 6
        switch hue {
        case 0: return Palette.blue
        case 1: return Palette.purple
        case 2: return Palette.green
        case 3: return Palette.orange
        case 4: return Palette.cyan
        default: return Palette.yellow
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(tint.opacity(0.18))
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(tint.opacity(0.30), lineWidth: 0.5)
            Text(letter)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(width: 22, height: 22)
    }
}

/// Thin shell — preserves the existing call sites and just hosts the
/// onboarding wizard. Drag-drop callers pass an `initialPath` and the
/// wizard short-circuits to the configure step.
struct AddProjectSheet: View {
    var initialPath: String? = nil

    var body: some View {
        OnboardingWizard(initialPath: initialPath)
    }
}

struct ProjectDropDelegate: DropDelegate {
    @Binding var showSheet: Bool
    @Binding var sheetPath: String?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.fileURL]).first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
            DispatchQueue.main.async {
                sheetPath = url.path
                showSheet = true
            }
        }
        return true
    }
}
