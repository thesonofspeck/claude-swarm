import SwiftUI
import AppCore
import PersistenceKit
import WrikeKit

struct TasksTab: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var registry: RunningSessionRegistry
    let session: Session?
    let project: Project?

    @State private var tasks: [WrikeTask] = []
    @State private var loading = false
    @State private var error: String?
    @State private var pendingTask: WrikeTask?
    @State private var initialPrompt: String = ""
    @State private var starting = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .task(id: project?.id) { await load() }
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
        } else {
            List(tasks) { task in
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
            await env.wrikeBridge.transitionStarted(taskId: task.id)
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

