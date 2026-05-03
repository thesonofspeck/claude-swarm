import SwiftUI
import AppCore
import PersistenceKit
import WrikeKit
import GitHubKit

/// First thing you see when no session is selected. Three rails — recent
/// sessions, Wrike tasks across every mapped folder, and open PRs across
/// every project — plus a greeting and a quick "what shall we work on?"
/// search that filters the rails in place. Hydrates instantly from the
/// CachedTask + CachedPR tables; refreshes per-project in the background.
struct WelcomeView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var registry: RunningSessionRegistry
    @ObservedObject var feed: WelcomeFeed
    @Binding var selectedSession: Session?
    @Binding var newSessionProjectId: String?
    @State private var query: String = ""
    @State private var pendingTask: WelcomeFeed.TaskRow?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.xl) {
                hero
                rail(
                    title: "Pick up where you left off",
                    systemImage: "clock.arrow.circlepath",
                    tint: Palette.cyan,
                    isEmpty: feed.recentSessions.isEmpty,
                    emptyText: "No sessions yet. Start one from a Wrike task below."
                ) {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Metrics.Space.md) {
                        ForEach(feed.recentSessions) { row in
                            sessionCard(row)
                        }
                    }
                }
                rail(
                    title: "Tasks waiting for you",
                    systemImage: "checklist",
                    tint: Palette.purple,
                    refreshing: feed.refreshingTasks,
                    isEmpty: filteredTasks.isEmpty,
                    emptyText: query.isEmpty
                        ? "No mapped Wrike folders have active tasks. Map a folder via project settings."
                        : "No tasks match \"\(query)\""
                ) {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Metrics.Space.md) {
                        ForEach(filteredTasks) { row in
                            taskCard(row)
                        }
                    }
                }
                rail(
                    title: "PRs needing attention",
                    systemImage: "arrow.triangle.pull",
                    tint: Palette.orange,
                    refreshing: feed.refreshingPRs,
                    isEmpty: filteredPRs.isEmpty,
                    emptyText: query.isEmpty
                        ? "No open PRs across your projects."
                        : "No PRs match \"\(query)\""
                ) {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Metrics.Space.md) {
                        ForEach(filteredPRs) { row in
                            prCard(row)
                        }
                    }
                }
            }
            .padding(Metrics.Space.xl)
        }
        .background(Palette.bgBase)
        .task {
            feed.hydrateFromCache()
            await feed.refreshIfStale()
        }
        .sheet(item: $pendingTask) { row in
            WelcomeStartSessionSheet(row: row) {
                pendingTask = nil
            }
            .environmentObject(env)
            .environmentObject(registry)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(Type.display)
                        .foregroundStyle(Palette.fgBright)
                    Text("What shall we work on today?")
                        .font(Type.body)
                        .foregroundStyle(Palette.fgMuted)
                }
                Spacer()
                if let last = feed.lastRefreshedAt {
                    Text("Updated \(last.formatted(.relative(presentation: .named)))")
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                }
                IconButton(systemImage: "arrow.clockwise", help: "Refresh") {
                    Task { await feed.refreshAll() }
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.fgMuted)
                TextField("Filter sessions, tasks, PRs…", text: $query)
                    .textFieldStyle(.plain)
                    .font(Type.body)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.fgMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Metrics.Space.md)
            .padding(.vertical, Metrics.Space.sm + 2)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.lg)
                    .fill(Palette.bgRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.lg)
                    .stroke(Palette.divider, lineWidth: Metrics.Stroke.hairline)
            )
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<5: return "Burning the midnight oil"
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Still at it"
        }
    }

    // MARK: - Rail scaffold

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: Metrics.Space.md, alignment: .topLeading)]
    }

    private func rail<Content: View>(
        title: String,
        systemImage: String,
        tint: Color,
        refreshing: Bool = false,
        isEmpty: Bool,
        emptyText: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(title)
                    .font(Type.title)
                    .foregroundStyle(Palette.fgBright)
                if refreshing {
                    ProgressView().controlSize(.small).padding(.leading, 4)
                }
                Spacer()
            }
            if isEmpty {
                Card { Text(emptyText).font(Type.body).foregroundStyle(Palette.fgMuted) }
            } else {
                content()
            }
        }
    }

    // MARK: - Cards

    private var filteredTasks: [WelcomeFeed.TaskRow] { feed.tasks(matching: query) }
    private var filteredPRs: [WelcomeFeed.PRRow] { feed.prs(matching: query) }

    private func sessionCard(_ row: WelcomeFeed.SessionRow) -> some View {
        Button {
            selectedSession = row.session
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Pill(text: row.session.status.rawValue, tint: statusTint(row.session.status))
                        Spacer()
                        Text(row.session.updatedAt.formatted(.relative(presentation: .named)))
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                    }
                    Text(row.session.taskTitle ?? row.session.branch)
                        .font(Type.heading)
                        .foregroundStyle(Palette.fgBright)
                        .lineLimit(2)
                    if let project = row.project {
                        Text(project.name)
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                    }
                    Text(row.session.branch)
                        .font(Type.monoCaption)
                        .foregroundStyle(Palette.purple)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func taskCard(_ row: WelcomeFeed.TaskRow) -> some View {
        Button {
            pendingTask = row
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Pill(text: row.task.status, systemImage: "circle.fill", tint: Palette.cyan)
                        Spacer()
                        Text(row.project.name)
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                    }
                    Text(row.task.title)
                        .font(Type.heading)
                        .foregroundStyle(Palette.fgBright)
                        .lineLimit(2)
                    let desc = row.task.descriptionPlainText
                    if !desc.isEmpty {
                        Text(desc)
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                            .lineLimit(3)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func prCard(_ row: WelcomeFeed.PRRow) -> some View {
        let pr = row.pr
        return Button {
            if let url = URL(string: pr.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Pill(text: "#\(pr.number)", systemImage: "number", tint: Palette.orange)
                        if pr.isDraft == true {
                            Pill(text: "draft", tint: Palette.fgMuted)
                        }
                        Spacer()
                        Text(row.project.name)
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                    }
                    Text(pr.title)
                        .font(Type.heading)
                        .foregroundStyle(Palette.fgBright)
                        .lineLimit(2)
                    if let head = pr.headRefName {
                        Text(head)
                            .font(Type.monoCaption)
                            .foregroundStyle(Palette.purple)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func statusTint(_ status: SessionStatus) -> Color {
        switch status {
        case .running: return Palette.green
        case .waitingForInput: return Palette.yellow
        case .idle: return Palette.fgMuted
        case .starting: return Palette.cyan
        case .archived: return Palette.fgMuted
        case .merged: return Palette.purple
        case .failed: return Palette.red
        }
    }
}

/// Lightweight wrapper around the existing StartSessionSheet that knows
/// how to spin up a session from a Welcome card without dragging the
/// caller through TasksTab.
private struct WelcomeStartSessionSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var registry: RunningSessionRegistry
    let row: WelcomeFeed.TaskRow
    let onDone: () -> Void

    @State private var initialPrompt: String = ""
    @State private var starting = false
    @State private var error: String?

    var body: some View {
        StartSessionSheet(
            task: row.task,
            initialPrompt: $initialPrompt,
            starting: $starting,
            onConfirm: { await start() }
        )
        .onAppear { initialPrompt = row.task.descriptionPlainText }
        .alert("Couldn't start session", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func start() async {
        starting = true
        defer { starting = false }
        do {
            let result = try await env.sessionManager.start(
                for: row.project,
                taskId: row.task.id,
                taskTitle: row.task.title,
                initialPrompt: initialPrompt,
                claudeExecutable: env.settings.claudeExecutable
            )
            registry.register(result.spec)
            await env.wrikeBridge.transition(taskId: row.task.id, to: .inProgress)
            onDone()
        } catch {
            self.error = "\(error)"
        }
    }
}
