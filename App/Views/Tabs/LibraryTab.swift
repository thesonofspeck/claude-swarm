import SwiftUI
import AppCore
import LibraryKit
import PersistenceKit

struct LibraryTab: View {
    @Environment(AppEnvironment.self) private var env
    let project: Project?

    @State private var view: LibraryView = LibraryView(rows: [], teamManifest: nil, teamError: nil)
    @State private var loading = false
    @State private var error: String?
    @State private var refreshing = false
    @State private var showSettings = false

    var body: some View {
        if let project {
            content(project: project)
                .task(id: project.id) { await load(project: project) }
        } else {
            EmptyState(
                title: "No project selected",
                systemImage: "books.vertical",
                description: "Pick a project to manage its library.",
                tint: Palette.fgMuted
            )
        }
    }

    private func content(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(project: project)
            Divider().background(Palette.divider)
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                EmptyState(
                    title: "Couldn't load library",
                    systemImage: "exclamationmark.triangle",
                    description: error,
                    tint: Palette.orange
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                        ForEach(LibraryItemKind.allCases, id: \.self) { kind in
                            kindSection(project: project, kind: kind)
                        }
                    }
                    .padding(Metrics.Space.lg)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            TeamLibrarySettingsSheet().environment(env)
        }
    }

    private func header(project: Project) -> some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "books.vertical")
                .foregroundStyle(Palette.cyan).imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text("Library").font(Type.heading).foregroundStyle(Palette.fgBright)
                if let manifest = view.teamManifest {
                    Text("Team: \(manifest.name)")
                        .font(Type.caption).foregroundStyle(Palette.fgMuted)
                } else {
                    Text("No team library configured")
                        .font(Type.caption).foregroundStyle(Palette.fgMuted)
                }
            }
            Spacer()
            Button {
                Task { await refreshTeam(project: project) }
            } label: {
                if refreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh team library")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Team library settings")
        }
        .padding(Metrics.Space.md)
    }

    @ViewBuilder
    private func kindSection(project: Project, kind: LibraryItemKind) -> some View {
        let rows = view.rows.filter { $0.item.kind == kind }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                HStack(spacing: 6) {
                    Image(systemName: kind.systemImage).foregroundStyle(tint(for: kind))
                    Text(kind.displayName.uppercased() + "S")
                        .font(Type.label).tracking(0.6)
                        .foregroundStyle(Palette.fgMuted)
                    Spacer()
                    Pill(text: "\(rows.count)", tint: Palette.fgMuted)
                }
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            rowView(project: project, row: row)
                            if idx < rows.count - 1 {
                                Divider().background(Palette.divider)
                            }
                        }
                    }
                }
            }
        }
    }

    private func rowView(project: Project, row: LibraryView.Row) -> some View {
        HStack(spacing: Metrics.Space.md) {
            Image(systemName: row.item.kind.systemImage)
                .foregroundStyle(tint(for: row.item.kind))
                .frame(width: 24, height: 24)
                .background(Circle().fill(tint(for: row.item.kind).opacity(0.10)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.item.name).font(Type.body).foregroundStyle(Palette.fgBright)
                    sourcePill(row.source)
                    if row.teamHasUpdate {
                        Pill(text: "Update", systemImage: "arrow.up.circle", tint: Palette.blue)
                    }
                }
                if let desc = row.item.description {
                    Text(desc).font(Type.caption).foregroundStyle(Palette.fgMuted).lineLimit(2)
                } else if let v = row.item.version {
                    Text(v).font(Type.monoCaption).foregroundStyle(Palette.fgMuted)
                }
            }
            Spacer()
            actionButton(project: project, row: row)
        }
        .padding(.horizontal, Metrics.Space.md)
        .padding(.vertical, 10)
    }

    private func sourcePill(_ source: LibrarySource) -> some View {
        switch source {
        case .builtIn:
            return Pill(text: "BUILT-IN", tint: Palette.fgMuted)
        case .team:
            return Pill(text: "TEAM", systemImage: "person.2", tint: Palette.cyan)
        case .project:
            return Pill(text: "PROJECT", tint: Palette.purple)
        case .userOverride:
            return Pill(text: "OVERRIDE", tint: Palette.orange)
        }
    }

    @ViewBuilder
    private func actionButton(project: Project, row: LibraryView.Row) -> some View {
        if row.installed {
            HStack(spacing: 4) {
                if row.teamHasUpdate {
                    Button("Sync") {
                        Task { await install(project: project, row: row) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                Button(role: .destructive) {
                    Task { await uninstall(project: project, row: row) }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Uninstall from this project")
            }
        } else {
            Button {
                Task { await install(project: project, row: row) }
            } label: {
                Label("Install", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func tint(for kind: LibraryItemKind) -> Color {
        switch kind {
        case .agent: return Palette.blue
        case .skill: return Palette.green
        case .command: return Palette.purple
        case .mcp: return Palette.cyan
        case .hook: return Palette.orange
        case .claudeMd: return Palette.yellow
        }
    }

    // MARK: - Actions

    private func load(project: Project) async {
        loading = true; error = nil        do {
            try await env.library.setTeamConfig(env.settings.teamLibrary)
            let snap = await env.library.snapshot(in: URL(fileURLWithPath: project.localPath))
            await MainActor.run {
                view = snap
                loading = false
            }
        } catch {
            await MainActor.run {
                self.error = "\(error.localizedDescription)"
                loading = false
            }
        }
    }

    private func refreshTeam(project: Project) async {
        refreshing = true        do {
            try await env.library.setTeamConfig(env.settings.teamLibrary)
            let snap = await env.library.snapshot(in: URL(fileURLWithPath: project.localPath))
            await MainActor.run {
                view = snap
                refreshing = false
            }
        } catch {
            await MainActor.run {
                self.error = "\(error.localizedDescription)"
                refreshing = false
            }
        }
    }

    private func install(project: Project, row: LibraryView.Row) async {
        do {
            try await env.library.install(row.item, into: URL(fileURLWithPath: project.localPath))
            await load(project: project)
        } catch {
            self.error = "\(error.localizedDescription)"        }
    }

    private func uninstall(project: Project, row: LibraryView.Row) async {
        do {
            try await env.library.uninstall(row.item, from: URL(fileURLWithPath: project.localPath))
            await load(project: project)
        } catch {
            self.error = "\(error.localizedDescription)"        }
    }
}

struct TeamLibrarySettingsSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var transport: Transport = .git
    @State private var gitURL = ""
    @State private var gitBranch = ""
    @State private var localPath = ""

    enum Transport: String, CaseIterable, Identifiable {
        case git, local, disabled
        var id: Self { self }
        var label: String {
            switch self {
            case .git: return "Git repository"
            case .local: return "Local folder"
            case .disabled: return "Disabled"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text("Team library").font(Type.title).foregroundStyle(Palette.fgBright)
            Text("Pull shared agents, skills, MCP servers, slash commands, and CLAUDE.md from a single source so the whole team uses the same setup.")
                .font(Type.body).foregroundStyle(Palette.fgMuted)

            Form {
                Picker("Source", selection: $transport) {
                    ForEach(Transport.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .pickerStyle(.segmented)

                switch transport {
                case .git:
                    Section {
                        TextField("Git URL (e.g. git@github.com:acme/swarm-library.git)", text: $gitURL)
                        TextField("Branch (optional)", text: $gitBranch)
                    } footer: {
                        Text("Cloned into Application Support; refresh pulls origin/HEAD.")
                            .font(Type.caption).foregroundStyle(Palette.fgMuted)
                    }
                case .local:
                    Section {
                        HStack {
                            TextField("Folder path", text: $localPath)
                            Button("Choose…") { choose() }
                        }
                    } footer: {
                        Text("Read in place. Useful when the library is on a shared file mount.")
                            .font(Type.caption).foregroundStyle(Palette.fgMuted)
                    }
                case .disabled:
                    Text("No team library; you'll only see built-in and per-project items.")
                        .font(Type.caption).foregroundStyle(Palette.fgMuted)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Metrics.Space.lg)
        .frame(width: 580, height: 480)
        .background(Palette.bgSidebar)
        .task { reload() }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            localPath = url.path
        }
    }

    private func reload() {
        switch env.settings.teamLibrary {
        case .git(let url, let branch):
            transport = .git; gitURL = url; gitBranch = branch ?? ""
        case .local(let path):
            transport = .local; localPath = path
        case .disabled:
            transport = .disabled
        }
    }

    private func save() {
        switch transport {
        case .git:
            env.settings.teamLibrary = .git(
                url: gitURL,
                branch: gitBranch.isEmpty ? nil : gitBranch
            )
        case .local:
            env.settings.teamLibrary = .local(path: localPath)
        case .disabled:
            env.settings.teamLibrary = .disabled
        }
        env.saveSettings()
        dismiss()
    }
}
