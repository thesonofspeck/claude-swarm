import SwiftUI
import AppCore
import PersistenceKit
import ClaudeSwarmNotifications

struct SidebarView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var vm: VMHolder = VMHolder()
    @Binding var selectedSession: Session?
    @State private var showingAddProject = false

    var body: some View {
        List(selection: $selectedSession) {
            ForEach(vm.projects) { project in
                Section(project.name) {
                    let sessions = vm.sessions(for: project.id)
                    ForEach(sessions) { session in
                        sessionRow(session)
                            .tag(session)
                    }
                    Button {
                    } label: {
                        Label("New session", systemImage: "plus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
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
        .task { vm.bind(to: env) }
        .sheet(isPresented: $showingAddProject) {
            AddProjectSheet().environmentObject(env)
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        let needsInput = env.notifier.pendingSessionIds.contains(session.id)
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

@MainActor
final class VMHolder: ObservableObject {
    @Published var projects: [PersistenceKit.Project] = []
    @Published var sessionsByProject: [String: [Session]] = [:]

    func bind(to env: AppEnvironment) {
        let list = ProjectListViewModel(env: env)
        self.projects = list.projects
        self.sessionsByProject = list.sessionsByProject
    }

    func sessions(for projectId: String) -> [Session] {
        sessionsByProject[projectId] ?? []
    }
}

struct AddProjectSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var path = ""
    @State private var baseBranch = "main"
    @State private var wrikeFolder = ""

    var body: some View {
        Form {
            Section("Project") {
                TextField("Name", text: $name)
                TextField("Local path", text: $path)
                TextField("Default base branch", text: $baseBranch)
            }
            Section("Wrike") {
                TextField("Folder ID", text: $wrikeFolder)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 320)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    do {
                        let project = PersistenceKit.Project(
                            name: name,
                            localPath: path,
                            defaultBaseBranch: baseBranch,
                            wrikeFolderId: wrikeFolder.isEmpty ? nil : wrikeFolder
                        )
                        try env.projects.upsert(project)
                        dismiss()
                    } catch {}
                }
                .disabled(name.isEmpty || path.isEmpty)
            }
        }
    }
}
