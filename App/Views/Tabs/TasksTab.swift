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
        HStack {
            if let project {
                Text(project.name)
                    .font(.headline)
                Spacer()
                if let folder = project.wrikeFolderId {
                    Label(folder, systemImage: "folder.badge.gearshape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh tasks")
            } else {
                Text("No project selected").font(.headline).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if let project, project.wrikeFolderId == nil {
            ContentUnavailableView(
                "No Wrike folder mapped",
                systemImage: "link.slash",
                description: Text("Edit this project to map it to a Wrike folder.")
            )
        } else if loading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error {
            ContentUnavailableView(
                "Couldn't load tasks",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if tasks.isEmpty {
            ContentUnavailableView(
                "No tasks",
                systemImage: "tray",
                description: Text("This Wrike folder has no tasks visible to you.")
            )
        } else {
            List(tasks) { task in
                TaskRow(task: task) {
                    pendingTask = task
                    initialPrompt = task.descriptionText?.htmlStripped ?? ""
                }
            }
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(.callout.weight(.medium))
                if let desc = task.descriptionText, !desc.isEmpty {
                    Text(desc.htmlStripped)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Label(task.status, systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let perm = task.permalink {
                        Link("Open in Wrike", destination: URL(string: perm)!)
                            .font(.caption2)
                    }
                }
            }
            Spacer()
            Button("Start session", action: onStart)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

extension String {
    var htmlStripped: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct StartSessionSheet: View {
    let task: WrikeTask
    @Binding var initialPrompt: String
    @Binding var starting: Bool
    let onConfirm: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start session for \(task.title)")
                .font(.headline)
            Text("A new git worktree and branch will be created. The team-lead agent will start with the prompt below.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $initialPrompt)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Start session") {
                    Task { await onConfirm() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(starting)
            }
        }
        .padding(20)
        .frame(width: 560, height: 380)
    }
}

