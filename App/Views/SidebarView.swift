import SwiftUI
import AppCore
import PersistenceKit
import ClaudeSwarmNotifications

struct SidebarView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var projectList: ProjectListViewModel
    @EnvironmentObject var notifier: Notifier
    @Binding var selectedSession: Session?
    @State private var showingAddProject = false
    @State private var showingSettings = false

    var body: some View {
        List(selection: $selectedSession) {
            ForEach(projectList.projects) { project in
                Section {
                    let sessions = projectList.sessions(for: project.id)
                    if sessions.isEmpty {
                        Text("No sessions yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(sessions) { session in
                            sessionRow(session).tag(session)
                        }
                    }
                } header: {
                    HStack {
                        Text(project.name)
                        Spacer()
                        let needsInputCount = projectList.sessions(for: project.id)
                            .filter { notifier.pendingSessionIds.contains($0.id) }.count
                        if needsInputCount > 0 {
                            Text("\(needsInputCount)●")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }

            Button {
                showingAddProject = true
            } label: {
                Label("Add project", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showingAddProject) {
            AddProjectSheet().environmentObject(env)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet().environmentObject(env)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        let needsInput = notifier.pendingSessionIds.contains(session.id)
        HStack(spacing: 8) {
            Circle()
                .fill(needsInput ? Color.yellow : Color.clear)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.taskTitle ?? session.branch)
                    .lineLimit(1)
                Text(session.branch)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel(needsInput
            ? "\(session.taskTitle ?? session.branch). Needs input."
            : (session.taskTitle ?? session.branch))
    }
}

struct AddProjectSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var projectList: ProjectListViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var path = ""
    @State private var baseBranch = "main"
    @State private var wrikeFolder = ""
    @State private var creating = false
    @State private var error: String?

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
            Section("Wrike") {
                TextField("Folder ID (optional)", text: $wrikeFolder)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 360)
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
                            wrikeFolder: wrikeFolder.isEmpty ? nil : wrikeFolder
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
        }
    }
}
