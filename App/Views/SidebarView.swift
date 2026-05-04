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
                            sessionRow(session).tag(session)
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

    @State private var droppedPath: String? = nil

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
    private func sessionRow(_ session: Session) -> some View {
        let needsInput = notifier.pendingSessionIds.contains(session.id)
        HStack(spacing: Metrics.Space.sm) {
            if needsInput {
                PulseDot(color: Palette.yellow)
            } else {
                Image(systemName: statusIcon(session.status))
                    .imageScale(.small)
                    .foregroundStyle(statusColor(session.status))
                    .frame(width: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.taskTitle ?? session.branch)
                    .font(Type.body)
                    .foregroundStyle(Palette.fg)
                    .lineLimit(1)
                Text(session.branch)
                    .font(Type.monoCaption)
                    .foregroundStyle(Palette.fgMuted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel(needsInput
            ? "\(session.taskTitle ?? session.branch). Needs input."
            : (session.taskTitle ?? session.branch))
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
        // Map name hash to one of the Atom palette accents for stable variety.
        let hue = abs(name.hashValue) % 6
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
