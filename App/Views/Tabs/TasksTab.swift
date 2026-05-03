import SwiftUI
import AppCore
import PersistenceKit
import WrikeKit

struct TasksTab: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(RunningSessionRegistry.self) private var registry
    let session: Session?
    let project: Project?

    @State private var tasks: [WrikeTask] = []
    @State private var loading = false
    @State private var error: String?
    @State private var pendingTask: WrikeTask?
    @State private var initialPrompt: String = ""
    @State private var starting = false
    @State private var showNewTask = false
    @State private var filter = WrikeFilter()

    private var filteredTasks: [WrikeTask] { filter.apply(to: tasks) }
    private var availableStatuses: [String] {
        Array(Set(tasks.map(\.status))).sorted()
    }
    private var availableImportances: [String] {
        Array(Set(tasks.compactMap(\.importance))).sorted { lhs, rhs in
            // Order High → Normal → Low so the picker matches user mental model.
            order(lhs) < order(rhs)
        }
    }
    private func order(_ importance: String) -> Int {
        switch importance {
        case "High": return 0
        case "Normal": return 1
        case "Low": return 2
        default: return 3
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !tasks.isEmpty || !filter.isEmpty {
                searchBar
                Divider().background(Palette.divider)
            }
            content
        }
        .task(id: project?.id) { await load() }
    }

    private var searchBar: some View {
        HStack(spacing: Metrics.Space.sm) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.fgMuted)
                TextField("Search title, description, or ID", text: $filter.query)
                    .textFieldStyle(.plain)
                if !filter.query.isEmpty {
                    Button {
                        filter.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.fgMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Metrics.Space.sm)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .fill(Palette.bgRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .stroke(Palette.divider, lineWidth: Metrics.Stroke.hairline)
            )

            statusFilterMenu
            importanceFilterMenu

            Toggle("Hide done", isOn: $filter.hideCompleted)
                .toggleStyle(.checkbox)
                .controlSize(.small)

            if !filter.isEmpty {
                Button("Clear") { filter = WrikeFilter() }
                    .buttonStyle(.plain)
                    .font(Type.label)
                    .foregroundStyle(Palette.fgMuted)
            }

            Spacer()

            Text("\(filteredTasks.count) of \(tasks.count)")
                .font(Type.caption)
                .foregroundStyle(Palette.fgMuted)
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private var statusFilterMenu: some View {
        Menu {
            if availableStatuses.isEmpty {
                Text("No statuses").foregroundStyle(Palette.fgMuted)
            } else {
                Button("All statuses") { filter.statuses = [] }
                Divider()
                ForEach(availableStatuses, id: \.self) { status in
                    Toggle(status, isOn: Binding(
                        get: { filter.statuses.contains(status) },
                        set: { on in
                            if on { filter.statuses.insert(status) }
                            else { filter.statuses.remove(status) }
                        }
                    ))
                }
            }
        } label: {
            Label(
                filter.statuses.isEmpty ? "Status" : "Status · \(filter.statuses.count)",
                systemImage: "circle.dashed.inset.filled"
            )
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 140)
    }

    private var importanceFilterMenu: some View {
        Menu {
            if availableImportances.isEmpty {
                Text("No importance").foregroundStyle(Palette.fgMuted)
            } else {
                Button("All priorities") { filter.importances = [] }
                Divider()
                ForEach(availableImportances, id: \.self) { imp in
                    Toggle(imp, isOn: Binding(
                        get: { filter.importances.contains(imp) },
                        set: { on in
                            if on { filter.importances.insert(imp) }
                            else { filter.importances.remove(imp) }
                        }
                    ))
                }
            }
        } label: {
            Label(
                filter.importances.isEmpty ? "Priority" : "Priority · \(filter.importances.count)",
                systemImage: "exclamationmark.circle"
            )
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 140)
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            if let project {
                ProjectInitial(name: project.name)
                Text(project.name)
                    .font(Type.heading)
                    .foregroundStyle(Palette.fgBright)
                Spacer()
                if let folder = project.wrikeFolderId {
                    Pill(text: folder, systemImage: "folder.badge.gearshape", tint: Palette.cyan)
                }
                IconButton(systemImage: "plus.circle", help: "New Wrike task") {
                    showNewTask = true
                }
                IconButton(systemImage: "arrow.clockwise", help: "Refresh tasks") {
                    Task { await load() }
                }
            } else {
                Text("No project selected")
                    .font(Type.heading)
                    .foregroundStyle(Palette.fgMuted)
                Spacer()
            }
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.divider).frame(height: Metrics.Stroke.hairline)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let project, project.wrikeFolderId == nil {
            EmptyState(
                title: "No Wrike folder mapped",
                systemImage: "link.slash",
                description: "Edit this project to map it to a Wrike folder.",
                tint: Palette.orange
            )
        } else if loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            EmptyState(
                title: "Couldn't load tasks",
                systemImage: "exclamationmark.triangle",
                description: error,
                tint: Palette.red
            )
        } else if tasks.isEmpty {
            EmptyState(
                title: "No tasks",
                systemImage: "tray",
                description: "This Wrike folder has no tasks visible to you.",
                tint: Palette.fgMuted
            )
        } else if filteredTasks.isEmpty {
            EmptyState(
                title: "No matches",
                systemImage: "line.3.horizontal.decrease.circle",
                description: "Adjust the search or clear filters to see more tasks.",
                tint: Palette.fgMuted
            )
        } else {
            List(filteredTasks) { task in
                TaskRow(task: task) {
                    pendingTask = task
                    initialPrompt = task.descriptionPlainText
                }
                .listRowBackground(Palette.bgBase)
                .listRowSeparatorTint(Palette.divider)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bgBase)
            .sheet(item: $pendingTask) { task in
                StartSessionSheet(
                    task: task,
                    initialPrompt: $initialPrompt,
                    starting: $starting,
                    onConfirm: { await startSession(for: task) }
                )
            }
            .sheet(isPresented: $showNewTask) {
                if let project {
                    NewWrikeTaskSheet(project: project).environment(env)
                }
            }
        }
    }

    private func startSession(for task: WrikeTask) async {
        guard let project else { return }
        await MainActor.run { starting = true }
        do {
            let result = try await env.sessionManager.start(
                for: project,
                taskId: task.id,
                taskTitle: task.title,
                initialPrompt: initialPrompt,
                claudeExecutable: env.settings.claudeExecutable
            )
            await MainActor.run {
                registry.register(result.spec)
                pendingTask = nil
                starting = false
            }
            await env.wrikeBridge.transition(taskId: task.id, to: .inProgress)
        } catch {
            await MainActor.run {
                self.error = "Could not start session: \(error.localizedDescription)"
                starting = false
            }
        }
    }

    private func load() async {
        guard let project, let folder = project.wrikeFolderId else {
            tasks = []; return
        }
        await MainActor.run { loading = true; error = nil }
        do {
            let result = try await env.wrike.tasks(in: folder)
            await MainActor.run {
                tasks = result
                loading = false
            }
        } catch {
            await MainActor.run {
                self.error = "\(error)"
                loading = false
            }
        }
    }
}

private struct TaskRow: View {
    let task: WrikeTask
    let onStart: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.Space.md) {
            Image(systemName: "checklist")
                .foregroundStyle(Palette.purple)
                .imageScale(.medium)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.purple.opacity(0.10)))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(Type.body)
                    .foregroundStyle(Palette.fgBright)
                let desc = task.descriptionPlainText
                if !desc.isEmpty {
                    Text(desc)
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                        .lineLimit(2)
                }
                HStack(spacing: Metrics.Space.sm) {
                    Pill(text: task.status, systemImage: "circle.fill", tint: Palette.cyan)
                    if let perm = task.permalink, let url = URL(string: perm) {
                        Link(destination: url) {
                            Pill(text: "Wrike", systemImage: "arrow.up.right.square", tint: Palette.fgMuted)
                        }
                    }
                }
            }
            Spacer()
            Button("Start session", action: onStart)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

struct StartSessionSheet: View {
    let task: WrikeTask
    @Binding var initialPrompt: String
    @Binding var starting: Bool
    let onConfirm: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Palette.green)
                    .imageScale(.large)
                Text("Start session")
                    .font(Type.title)
                    .foregroundStyle(Palette.fgBright)
            }
            Text(task.title).font(Type.heading).foregroundStyle(Palette.fgBright)
            Text("A new git worktree and branch will be created. The team-lead agent will start with the prompt below.")
                .font(Type.caption)
                .foregroundStyle(Palette.fgMuted)

            TextEditor(text: $initialPrompt)
                .font(Type.mono)
                .scrollContentBackground(.hidden)
                .padding(Metrics.Space.sm)
                .background(Palette.bgBase)
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.Radius.md)
                        .stroke(Palette.divider, lineWidth: Metrics.Stroke.regular)
                )

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    Task { await onConfirm() }
                } label: {
                    Label(starting ? "Starting…" : "Start session", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(starting)
            }
        }
        .padding(Metrics.Space.xl)
        .frame(width: 580, height: 420)
        .background(Palette.bgSidebar)
    }
}

