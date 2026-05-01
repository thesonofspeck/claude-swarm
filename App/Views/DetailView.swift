import SwiftUI
import AppCore
import PersistenceKit
import GitKit
import DiffViewer
import TerminalUI
import SessionCore

enum DetailTab: String, CaseIterable, Identifiable {
    case terminal, changes, files, diff, history, pr, tasks, memory, agents, library, policy, claudeMd, transcript
    var id: String { rawValue }

    var label: String {
        switch self {
        case .terminal: return "Terminal"
        case .changes: return "Changes"
        case .files: return "Files"
        case .diff: return "Diff"
        case .history: return "History"
        case .pr: return "PR"
        case .tasks: return "Tasks"
        case .memory: return "Memory"
        case .agents: return "Agents"
        case .library: return "Library"
        case .policy: return "Policy"
        case .claudeMd: return "CLAUDE.md"
        case .transcript: return "Transcript"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal: return "terminal"
        case .changes: return "checklist.unchecked"
        case .files: return "folder"
        case .diff: return "arrow.left.arrow.right"
        case .history: return "clock.arrow.circlepath"
        case .pr: return "arrow.triangle.pull"
        case .tasks: return "checklist"
        case .memory: return "brain"
        case .agents: return "person.3"
        case .library: return "books.vertical"
        case .policy: return "shield.lefthalf.filled"
        case .claudeMd: return "doc.text"
        case .transcript: return "text.alignleft"
        }
    }
}

struct DetailView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var registry: RunningSessionRegistry
    let session: Session?
    @State private var tab: DetailTab = .terminal
    @State private var project: Project?

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .animation(.easeInOut(duration: 0.18), value: tab)
        }
        .onChange(of: session?.id) { _, newId in
            registry.setForeground(newId)
        }
        .task(id: session?.projectId) {
            if let session {
                project = try? await env.projects.find(id: session.projectId)
            } else {
                project = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .swarmSelectTab)) { note in
            if let raw = note.object as? String, let t = DetailTab(rawValue: raw) {
                tab = t
            }
        }
    }

    private var tabBar: some View {
        Picker("Tab", selection: $tab) {
            ForEach(DetailTab.allCases) { t in
                Label(t.label, systemImage: t.systemImage).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(Metrics.Space.sm)
        .background(Palette.bgSidebar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.divider)
                .frame(height: Metrics.Stroke.hairline)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let session {
            switch tab {
            case .terminal: TerminalTab(session: session)
            case .changes: ChangesTab(session: session)
            case .files: FilesTab(session: session)
            case .diff: DiffTab(session: session)
            case .history: HistoryTab(session: session)
            case .pr: PRTab(session: session, project: project)
            case .tasks: TasksTab(session: session, project: project)
            case .memory: MemoryTab(project: project, session: session)
            case .agents: AgentsTab(project: project)
            case .library: LibraryTab(project: project)
            case .policy: PolicyTab(project: project)
            case .claudeMd: ClaudeMdTab(project: project)
            case .transcript: TranscriptTab(session: session)
            }
        } else {
            EmptyState(
                title: "No session selected",
                systemImage: "sparkles.rectangle.stack",
                description: "Pick a session from the sidebar or start a new one from the Tasks tab.",
                tint: Palette.blue
            )
        }
    }
}

struct TerminalTab: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var registry: RunningSessionRegistry
    let session: Session

    var body: some View {
        Group {
            if let spec = registry.spec(for: session.id) {
                PTYTerminalView(spec: spec) { _ in
                    Task { @MainActor in
                        try? await env.sessionsRepo.setStatus(id: session.id, .finished)
                        registry.remove(id: session.id)
                    }
                }
            } else {
                EmptyState(
                    title: "Session not running",
                    systemImage: "powerplug",
                    description: "This session was started in a previous app launch. Open the Transcript tab to read its scrollback.",
                    tint: Palette.fgMuted
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgBase)
    }
}

struct DiffTab: View {
    @EnvironmentObject var env: AppEnvironment
    let session: Session
    @State private var files: [DiffFile] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiffView(files: files)
            }
        }
        .task(id: session.id) {
            await reload()
        }
        .task(id: session.id) {
            // Pulse-driven reloads — fires after FSEvents debounce, after
            // PostToolUse hooks, and after every completed git operation
            // that touches working state.
            let ws = env.gitWorkspace(for: session.worktreePath)
            for await invalidations in ws.pulse.events() {
                if invalidations.contains(.status) || invalidations.contains(.files) {
                    await reload()
                }
            }
        }
    }

    private func reload() async {
        let url = URL(fileURLWithPath: session.worktreePath)
        let result = (try? await env.diff.workingTreeDiff(in: url)) ?? []
        files = result
        loading = false
    }
}

struct HistoryTab: View {
    @EnvironmentObject var env: AppEnvironment
    let session: Session
    @State private var commits: [CommitSummary] = []
    @State private var selection: String?
    @State private var commitDiff: [DiffFile] = []

    private var workspace: GitWorkspace {
        env.gitWorkspace(for: session.worktreePath)
    }

    var body: some View {
        HSplitView {
            List(commits, selection: $selection) { c in
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.subject)
                        .font(Type.body)
                        .foregroundStyle(Palette.fg)
                    HStack(spacing: Metrics.Space.sm) {
                        Text(c.id.prefix(7))
                            .font(Type.monoCaption)
                            .foregroundStyle(Palette.purple)
                        Text(c.author)
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                        Text(c.date.formatted(.relative(presentation: .named)))
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                    }
                }
                .tag(Optional(c.id))
                .contextMenu { contextMenu(for: c) }
            }
            .frame(minWidth: 320)
            .scrollContentBackground(.hidden)
            .background(Palette.bgBase)
            .task(id: session.id) {
                await reloadCommits()
            }
            .task(id: session.id) {
                let ws = env.gitWorkspace(for: session.worktreePath)
                for await invalidations in ws.pulse.events() {
                    if invalidations.contains(.history) || invalidations.contains(.branches) {
                        await reloadCommits()
                    }
                }
            }

            DiffView(files: commitDiff)
        }
        .onChange(of: selection) { _, sha in
            guard let sha else { commitDiff = []; return }
            Task {
                let url = URL(fileURLWithPath: session.worktreePath)
                commitDiff = (try? await env.diff.commitDiff(in: url, sha: sha)) ?? []
            }
        }
    }

    private func reloadCommits() async {
        let url = URL(fileURLWithPath: session.worktreePath)
        commits = (try? await env.history.log(in: url)) ?? []
    }

    @ViewBuilder
    private func contextMenu(for commit: CommitSummary) -> some View {
        Button("Copy SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.id, forType: .string)
        }
        Divider()
        Button("Cherry-pick onto current branch") {
            Task { await workspace.cherryPick(commit.id) }
        }
        Button("Revert", role: .destructive) {
            Task { await workspace.revert(commit.id) }
        }
        Divider()
        Menu("Reset current branch to here") {
            Button("Soft (keep index + worktree)") {
                Task { await reset(to: commit.id, mode: .soft) }
            }
            Button("Mixed (keep worktree)") {
                Task { await reset(to: commit.id, mode: .mixed) }
            }
            Button("Hard — discard everything", role: .destructive) {
                Task { await reset(to: commit.id, mode: .hard) }
            }
        }
        Button("Tag this commit…") {
            NotificationCenter.default.post(
                name: .swarmCreateTag,
                object: nil,
                userInfo: ["sha": commit.id]
            )
        }
    }

    private func reset(to sha: String, mode: CommitService.ResetMode) async {
        do {
            try await workspace.commits.reset(to: sha, mode: mode, in: workspace.repo)
            await workspace.reloadAll()
        } catch {
            // Surface through the workspace's error path next reload.
        }
    }
}

extension Notification.Name {
    static let swarmCreateTag = Notification.Name("ClaudeSwarm.CreateTag")
}
