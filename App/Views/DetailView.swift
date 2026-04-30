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
    let session: Session?
    @State private var tab: DetailTab = .terminal

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $tab) {
                ForEach(DetailTab.allCases) { t in
                    Label(t.label, systemImage: t.systemImage).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            .background(.ultraThinMaterial)

            Divider()

            if let session {
                content(for: session)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .animation(.easeInOut(duration: 0.18), value: tab)
            } else {
                ContentUnavailableView(
                    "No session selected",
                    systemImage: "rectangle.dashed",
                    description: Text("Pick a session from the sidebar or create a new one.")
                )
            }
        }
    }

    @ViewBuilder
    private func content(for session: Session) -> some View {
        switch tab {
        case .terminal: TerminalTab(session: session)
        case .files: FilesTab(session: session)
        case .diff: DiffTab(session: session)
        case .history: HistoryTab(session: session)
        case .pr: PRTab(session: session)
        case .tasks: TasksTab(session: session)
        case .memory: MemoryTab(session: session)
        case .agents: AgentsTab(session: session)
        }
    }
}

struct TerminalTab: View {
    @EnvironmentObject var env: AppEnvironment
    let session: Session

    var body: some View {
        // Session must already be running (spawned by SessionManager); the
        // PTYTerminalView attaches to a fresh `claude` invocation. In a fuller
        // build, the running PTY is held in AppEnvironment so re-renders reuse it.
        Text("Terminal placeholder for session \(session.id)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.secondary)
    }
}

struct FilesTab: View {
    let session: Session
    var body: some View {
        Text("Files browser: \(session.worktreePath)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.secondary)
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

    var body: some View {
        List(commits) { c in
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
        }
        .task(id: session.id) {
            let url = URL(fileURLWithPath: session.worktreePath)
            commits = (try? await env.history.log(in: url)) ?? []
        }
    }
}

struct PRTab: View {
    let session: Session
    var body: some View {
        VStack(spacing: 12) {
            Text("PR view")
                .font(.headline)
            Text(session.prNumber.map { "#\($0)" } ?? "No PR yet")
                .foregroundStyle(.secondary)
            Button("Open PR on GitHub") {}
                .disabled(session.prNumber == nil)
            Button("Push branch + Create PR") {}
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TasksTab: View {
    let session: Session
    var body: some View {
        Text("Wrike tasks for this project")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.secondary)
    }
}

struct MemoryTab: View {
    let session: Session
    var body: some View {
        Text("Memory entries for this project / session")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.secondary)
    }
}

struct AgentsTab: View {
    let session: Session
    var body: some View {
        Text("View / customize the 6 default subagents for this project")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.secondary)
    }
}
