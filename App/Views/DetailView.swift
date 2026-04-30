import SwiftUI
import AppCore
import PersistenceKit
import GitKit
import DiffViewer
import TerminalUI
import SessionCore

enum DetailTab: String, CaseIterable, Identifiable {
    case terminal, files, diff, history, pr, tasks, memory, agents
    var id: String { rawValue }

    var label: String {
        switch self {
        case .terminal: return "Terminal"
        case .files: return "Files"
        case .diff: return "Diff"
        case .history: return "History"
        case .pr: return "PR"
        case .tasks: return "Tasks"
        case .memory: return "Memory"
        case .agents: return "Agents"
        }
    }

    var systemImage: String {
        switch self {
        case .terminal: return "terminal"
        case .files: return "folder"
        case .diff: return "arrow.left.arrow.right"
        case .history: return "clock.arrow.circlepath"
        case .pr: return "arrow.triangle.pull"
        case .tasks: return "checklist"
        case .memory: return "brain"
        case .agents: return "person.3"
        }
    }
}

struct DetailView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var registry: RunningSessionRegistry
    let session: Session?
    @State private var tab: DetailTab = .terminal

    var project: Project? {
        guard let session else { return nil }
        return try? env.projects.find(id: session.projectId)
    }

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
    }

    private var tabBar: some View {
        Picker("Tab", selection: $tab) {
            ForEach(DetailTab.allCases) { t in
                Label(t.label, systemImage: t.systemImage).tag(t)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var content: some View {
        if let session {
            switch tab {
            case .terminal: TerminalTab(session: session)
            case .files: FilesTab(session: session)
            case .diff: DiffTab(session: session)
            case .history: HistoryTab(session: session)
            case .pr: PRTab(session: session, project: project)
            case .tasks: TasksTab(session: session, project: project)
            case .memory: MemoryTab(project: project, session: session)
            case .agents: AgentsTab(project: project)
            }
        } else {
            ContentUnavailableView(
                "No session selected",
                systemImage: "rectangle.dashed",
                description: Text("Pick a session from the sidebar or start a new one from the Tasks tab.")
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
                        try? env.sessionsRepo.setStatus(id: session.id, .finished)
                        registry.remove(id: session.id)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Session not running",
                    systemImage: "powerplug",
                    description: Text("This session was started in a previous app launch. Start a new session from the Tasks tab.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            loading = true
            let url = URL(fileURLWithPath: session.worktreePath)
            files = (try? await env.diff.workingTreeDiff(in: url)) ?? []
            loading = false
        }
    }
}

struct HistoryTab: View {
    @EnvironmentObject var env: AppEnvironment
    let session: Session
    @State private var commits: [CommitSummary] = []
    @State private var selection: String?
    @State private var commitDiff: [DiffFile] = []

    var body: some View {
        HSplitView {
            List(commits, selection: $selection) { c in
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.subject).font(.callout)
                    HStack {
                        Text(c.id.prefix(7))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(c.author).font(.caption).foregroundStyle(.secondary)
                        Text(c.date.formatted(.relative(presentation: .named)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(Optional(c.id))
            }
            .frame(minWidth: 320)
            .task(id: session.id) {
                let url = URL(fileURLWithPath: session.worktreePath)
                commits = (try? await env.history.log(in: url)) ?? []
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
}
