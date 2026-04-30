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
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                            .padding(.vertical, Metrics.Space.xs)
                    } else {
                        ForEach(sessions) { session in
                            sessionRow(session).tag(session)
                        }
                    }
                } header: {
                    projectHeader(project)
                }
            }

            Button {
                showingAddProject = true
            } label: {
                Label("Add project", systemImage: "folder.badge.plus")
                    .foregroundStyle(Palette.blue)
            }
            .buttonStyle(.plain)
            .padding(.top, Metrics.Space.sm)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Palette.bgSidebar)
        .sheet(isPresented: $showingAddProject) {
            AddProjectSheet().environmentObject(env)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet().environmentObject(env)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                IconButton(systemImage: "gearshape", help: "Settings") {
                    showingSettings = true
                }
            }
        }
    }

    private func projectHeader(_ project: Project) -> some View {
        let pendingCount = projectList.sessions(for: project.id)
            .filter { notifier.pendingSessionIds.contains($0.id) }.count
        return HStack(spacing: Metrics.Space.sm) {
            ProjectInitial(name: project.name)
            Text(project.name)
                .font(Type.heading)
                .foregroundStyle(Palette.fgBright)
            Spacer()
            if pendingCount > 0 {
                Pill(text: "\(pendingCount)", systemImage: "circle.fill", tint: Palette.yellow)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        let needsInput = notifier.pendingSessionIds.contains(session.id)
        HStack(spacing: Metrics.Space.sm) {
            if needsInput {
                PulseDot(color: Palette.yellow)
            } else {
                Image(systemName: statusIcon(session.status))
                    .imageScale(.small)
                    .foregroundStyle(statusColor(session.status))
                    .frame(width: 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.taskTitle ?? session.branch)
                    .font(Type.body)
                    .foregroundStyle(Palette.fg)
                    .lineLimit(1)
                Text(session.branch)
                    .font(Type.monoCaption)
                    .foregroundStyle(Palette.fgMuted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel(needsInput
            ? "\(session.taskTitle ?? session.branch). Needs input."
            : (session.taskTitle ?? session.branch))
    }

    private func statusIcon(_ status: SessionStatus) -> String {
        switch status {
        case .starting, .running: return "circle.dotted"
        case .waitingForInput: return "circle.fill"
        case .idle: return "pause.circle"
        case .finished, .archived: return "checkmark.circle"
        case .prOpen: return "arrow.triangle.pull"
        case .merged: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .starting, .running: return Palette.green
        case .waitingForInput: return Palette.yellow
        case .idle: return Palette.fgMuted
        case .finished, .archived: return Palette.fgMuted
        case .prOpen: return Palette.blue
        case .merged: return Palette.purple
        case .failed: return Palette.red
        }
    }
}

/// Tinted circle with the project's first letter — gives each project a
/// distinct visual hook without requiring a real avatar.
struct ProjectInitial: View {
    let name: String

    private var letter: String {
        String(name.prefix(1)).uppercased()
    }

    private var tint: Color {
        // Map name hash to one of the Atom palette accents for stable variety.
        let hue = abs(name.hashValue) % 6
        switch hue {
        case 0: return Palette.blue
        case 1: return Palette.purple
        case 2: return Palette.green
        case 3: return Palette.orange
        case 4: return Palette.cyan
        default: return Palette.yellow
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(tint.opacity(0.18))
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(tint.opacity(0.30), lineWidth: 0.5)
            Text(letter)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(width: 22, height: 22)
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
                Section { Text(error).foregroundStyle(Palette.red) }
            }
        }
        .formStyle(.grouped)
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
