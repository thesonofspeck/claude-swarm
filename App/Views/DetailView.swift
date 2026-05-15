import SwiftUI
import AppCore
import PersistenceKit
import GitKit
import DiffViewer
import TerminalUI
import SessionCore

enum DetailTab: String, CaseIterable, Identifiable {
    case terminal, changes, files, diff, history, pr, tasks, memory, agents, agentRuns, library, deploy, policy, claudeMd, transcript
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
        case .agentRuns: return "Runs"
        case .library: return "Library"
        case .deploy: return "Deploy"
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
        case .agentRuns: return "person.3.sequence"
        case .library: return "books.vertical"
        case .deploy: return "shippingbox"
        case .policy: return "shield.lefthalf.filled"
        case .claudeMd: return "doc.text"
        case .transcript: return "text.alignleft"
        }
    }
}

/// One open pane in the detail area. Each pane independently chooses
/// which tool it shows; the first pane is the clean default the session
/// opens to.
struct DetailPane: Identifiable, Equatable {
    let id = UUID()
    var tab: DetailTab
}

struct DetailView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(RunningSessionRegistry.self) private var registry
    let session: Session
    @State private var panes: [DetailPane] = [DetailPane(tab: .terminal)]
    @State private var project: Project?

    private static let maxPanes = 4

    var body: some View {
        HSplitView {
            ForEach($panes) { $pane in
                DetailPaneView(
                    session: session,
                    project: project,
                    tab: $pane.tab,
                    canClose: panes.count > 1,
                    canSplit: panes.count < Self.maxPanes,
                    onSplit: { splitPane(after: pane.id) },
                    onClose: { closePane(pane.id) }
                )
                .frame(minWidth: 360)
            }
        }
        .onChange(of: session.id) { _, newId in
            registry.setForeground(newId)
        }
        .task(id: session.projectId) {
            project = try? env.projects.find(id: session.projectId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .swarmSelectTab)) { note in
            // Menu / keyboard tab selection retargets the first pane so
            // ⌘1–⌘6 still land somewhere predictable.
            if let raw = note.object as? String, let t = DetailTab(rawValue: raw) {
                if panes.isEmpty {
                    panes = [DetailPane(tab: t)]
                } else {
                    panes[0].tab = t
                }
            }
        }
    }

    private func splitPane(after id: DetailPane.ID) {
        guard panes.count < Self.maxPanes,
              let idx = panes.firstIndex(where: { $0.id == id }) else { return }
        // A new pane defaults to Diff — the most common companion to the
        // terminal — and the user retargets it from the pane menu.
        let existing = Set(panes.map(\.tab))
        let suggested: DetailTab = existing.contains(.diff) ? .files : .diff
        withAnimation(.easeInOut(duration: 0.18)) {
            panes.insert(DetailPane(tab: suggested), at: idx + 1)
        }
    }

    private func closePane(_ id: DetailPane.ID) {
        guard panes.count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            panes.removeAll { $0.id == id }
        }
    }
}

/// A single pane: a slim header (tool picker + split / close) over the
/// tool's content. Keeps the existing tab views unchanged — this is
/// purely a layout shell so the detail area reads as "one clean view,
/// split in more as needed" instead of a 15-tab strip.
struct DetailPaneView: View {
    let session: Session
    let project: Project?
    @Binding var tab: DetailTab
    let canClose: Bool
    let canSplit: Bool
    let onSplit: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: tab)
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Menu {
                ForEach(DetailTab.allCases) { t in
                    Button {
                        tab = t
                    } label: {
                        Label(t.label, systemImage: t.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: tab.systemImage)
                        .foregroundStyle(Palette.fgMuted)
                    Text(tab.label)
                        .font(Type.body.weight(.medium))
                        .foregroundStyle(Palette.fgBright)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.fgMuted)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            if canSplit {
                Button(action: onSplit) {
                    Image(systemName: "rectangle.split.2x1")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.fgMuted)
                .help("Split — open another tool alongside")
            }
            if canClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.fgMuted)
                .help("Close pane")
            }
        }
        .padding(.horizontal, Metrics.Space.md)
        .padding(.vertical, 6)
        .background(Palette.bgSidebar)
    }

    @ViewBuilder
    private var content: some View {
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
        case .agentRuns: AgentRunTab(session: session)
        case .library: LibraryTab(project: project)
        case .deploy: DeployTab(project: project)
        case .policy: PolicyTab(project: project)
        case .claudeMd: ClaudeMdTab(project: project)
        case .transcript: TranscriptTab(session: session)
        }
    }
}

struct TerminalTab: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(RunningSessionRegistry.self) private var registry
    let session: Session

    var body: some View {
        Group {
            if let spec = registry.spec(for: session.id) {
                PTYTerminalView(spec: spec) { _ in
                    Task { @MainActor in
                        try? env.sessionsRepo.setStatus(id: session.id, .finished)
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
    @Environment(AppEnvironment.self) private var env
    let session: Session
    @State private var files: [DiffFile] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiffView(
                    files: files,
                    worktreeRoot: URL(fileURLWithPath: session.worktreePath),
                    onSaved: { _ in
                        // Saving the file invalidates status + files +
                        // history. The pulse will refire .reload() and
                        // the diff view rebuilds from the new contents.
                        env.gitWorkspace(for: session.worktreePath)
                            .invalidate([.status, .files])
                    }
                )
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
    @Environment(AppEnvironment.self) private var env
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
