import SwiftUI
import AppCore
import PersistenceKit
import ClaudeSwarmNotifications
import GitKit

struct SidebarView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var projectList: ProjectListViewModel
    @EnvironmentObject var notifier: Notifier
    @Binding var selectedSession: Session?
    @Binding var newSessionProjectId: String?
    @State private var showingAddProject = false
    @State private var showingSettings = false

    var body: some View {
        List(selection: $selectedSession) {
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
            AddProjectSheet(initialPath: droppedPath).environmentObject(env)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet().environmentObject(env)
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

struct AddProjectSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var projectList: ProjectListViewModel
    @Environment(\.dismiss) private var dismiss
    var initialPath: String? = nil
    @State private var name = ""
    @State private var path = ""
    @State private var baseBranch = "main"
    @State private var wrikeFolder = ""
    @State private var githubOwner = ""
    @State private var githubRepo = ""
    @State private var creating = false
    @State private var error: String?
    @State private var detectedRepo: String?

    var body: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $name)
                HStack {
                    TextField("Local path", text: $path)
                    Button("Choose…") { chooseDirectory() }
                }
                TextField("Default base branch", text: $baseBranch)
            }
            Section("GitHub") {
                if let detectedRepo {
                    Pill(text: detectedRepo, systemImage: "checkmark.seal", tint: Palette.green)
                }
                TextField("Owner", text: $githubOwner)
                TextField("Repo", text: $githubRepo)
            }
            Section("Wrike") {
                TextField("Folder ID (optional)", text: $wrikeFolder)
            }
            if let error {
                Section { Text(error).foregroundStyle(Palette.red) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
        .onAppear {
            if let initialPath, path.isEmpty {
                path = initialPath
                if name.isEmpty {
                    name = (initialPath as NSString).lastPathComponent
                }
                autodiscover(at: initialPath)
            }
        }
        .onChange(of: path) { _, newValue in
            autodiscover(at: newValue)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(creating ? "Adding…" : "Add") {
                    Task {
                        creating = true
                        await projectList.register(
                            name: name, path: path, baseBranch: baseBranch,
                            wrikeFolder: wrikeFolder.isEmpty ? nil : wrikeFolder,
                            githubOwner: githubOwner.isEmpty ? nil : githubOwner,
                            githubRepo: githubRepo.isEmpty ? nil : githubRepo
                        )
                        creating = false
                        if projectList.error == nil { dismiss() }
                        else { error = projectList.error }
                    }
                }
                .disabled(name.isEmpty || path.isEmpty || creating)
            }
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
            if name.isEmpty { name = url.lastPathComponent }
            autodiscover(at: url.path)
        }
    }

    private func autodiscover(at path: String) {
        guard !path.isEmpty,
              let origin = GitConfigParser.origin(in: URL(fileURLWithPath: path)) else {
            detectedRepo = nil
            return
        }
        if let owner = origin.owner, githubOwner.isEmpty { githubOwner = owner }
        if let repo = origin.repo, githubRepo.isEmpty { githubRepo = repo }
        if let owner = origin.owner, let repo = origin.repo {
            detectedRepo = "\(owner)/\(repo)"
        }
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
