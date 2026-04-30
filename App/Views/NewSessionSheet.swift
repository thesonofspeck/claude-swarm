import SwiftUI
import AppCore
import PersistenceKit

struct NewSessionSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var projectList: ProjectListViewModel
    @EnvironmentObject var registry: RunningSessionRegistry
    @Environment(\.dismiss) private var dismiss

    /// Pre-selected project (e.g. when launched with a session already in
    /// scope). If nil the sheet shows a project picker.
    let preselectedProjectId: String?

    @State private var projectId: String = ""
    @State private var taskTitle: String = ""
    @State private var taskId: String = ""
    @State private var prompt: String = ""
    @State private var starting = false
    @State private var drafting = false
    @State private var error: String?

    init(preselectedProjectId: String? = nil) {
        self.preselectedProjectId = preselectedProjectId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(Palette.green)
                    .imageScale(.large)
                Text("New session")
                    .font(Type.title)
                    .foregroundStyle(Palette.fgBright)
            }

            Form {
                Section("Project") {
                    Picker("Project", selection: $projectId) {
                        ForEach(projectList.projects) { project in
                            Text(project.name).tag(project.id)
                        }
                    }
                    .disabled(projectList.projects.isEmpty)
                }
                Section("Task") {
                    TextField("Title", text: $taskTitle)
                    TextField("Wrike ID (optional)", text: $taskId)
                }
                Section {
                    TextEditor(text: $prompt)
                        .font(Type.mono)
                        .frame(minHeight: 140)
                } header: {
                    HStack {
                        Text("Initial prompt")
                        Spacer()
                        Button {
                            Task { await draftPrompt() }
                        } label: {
                            if drafting {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Draft", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(!env.llm.isUsable || drafting || taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help(env.llm.isUsable ? "Expand the title into a fuller prompt" : "Configure the Anthropic API key in Settings → AI to enable")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(Palette.red) }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button {
                    Task { await start() }
                } label: {
                    Label(starting ? "Starting…" : "Start session", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(starting || projectId.isEmpty || taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Metrics.Space.lg)
        .frame(width: 580, height: 520)
        .background(Palette.bgSidebar)
        .onAppear {
            if let id = preselectedProjectId, projectList.projects.contains(where: { $0.id == id }) {
                projectId = id
            } else {
                projectId = projectList.projects.first?.id ?? ""
            }
        }
    }

    private func start() async {
        guard let project = projectList.projects.first(where: { $0.id == projectId }) else {
            error = "Pick a project."
            return
        }
        await MainActor.run { starting = true; error = nil }
        do {
            let result = try await env.sessionManager.start(
                for: project,
                taskId: taskId.isEmpty ? nil : taskId,
                taskTitle: taskTitle,
                initialPrompt: prompt.isEmpty ? nil : prompt,
                claudeExecutable: env.settings.claudeExecutable
            )
            await MainActor.run {
                registry.register(result.spec)
                if !taskId.isEmpty { Task { await env.wrikeBridge.transitionStarted(taskId: taskId) } }
                starting = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                self.error = "Could not start session: \(error.localizedDescription)"
                starting = false
            }
        }
    }

    private func draftPrompt() async {
        let project = projectList.projects.first { $0.id == projectId }
        await MainActor.run { drafting = true; error = nil }
        do {
            let result = try await env.llm.draftSessionPrompt(
                from: taskTitle,
                projectName: project?.name
            )
            await MainActor.run {
                prompt = result
                drafting = false
            }
        } catch {
            await MainActor.run {
                self.error = "Couldn't draft: \(error.localizedDescription)"
                drafting = false
            }
        }
    }
}
