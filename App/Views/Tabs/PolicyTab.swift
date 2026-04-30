import SwiftUI
import AppCore
import AgentBootstrap
import PersistenceKit

struct PolicyTab: View {
    @EnvironmentObject var env: AppEnvironment
    let project: Project?

    @State private var policy: ProjectPolicy = .default
    @State private var error: String?
    @State private var dirty = false
    @State private var savedToast = false
    @State private var permAllow: String = ""
    @State private var permDeny: String = ""
    @State private var permDirty = false

    var body: some View {
        if let project {
            content(project: project)
                .task(id: project.id) { load(project: project) }
        } else {
            EmptyState(
                title: "No project selected",
                systemImage: "shield.lefthalf.filled",
                description: "Pick a project to edit its approval policy.",
                tint: Palette.fgMuted
            )
        }
    }

    private func content(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Palette.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                    autoAllowSection
                    alwaysAskSection
                    destructiveSection
                    nativePermissionsSection(project: project)
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.orange)
                    }
                }
                .padding(Metrics.Space.lg)
            }
            actionBar(project: project)
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(Palette.cyan)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text("Approval policy")
                    .font(Type.heading)
                    .foregroundStyle(Palette.fgBright)
                Text("Auto-approve safe tools so only meaningful prompts reach iOS.")
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
            if dirty {
                Circle().fill(Palette.orange).frame(width: 6, height: 6)
            }
            Spacer()
        }
        .padding(Metrics.Space.md)
    }

    private var autoAllowSection: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            SectionLabel(title: "Auto-allow")
            Text("Tool calls in this list run without prompting.")
                .font(Type.caption).foregroundStyle(Palette.fgMuted)
            toolGrid(allTools: ProjectPolicy.knownTools, selected: $policy.autoAllow, exclude: policy.alwaysAsk, tint: Palette.green)
        }
    }

    private var alwaysAskSection: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            SectionLabel(title: "Always ask")
            Text("These tools always escalate to your iPhone — even if also in auto-allow.")
                .font(Type.caption).foregroundStyle(Palette.fgMuted)
            toolGrid(allTools: ProjectPolicy.knownTools, selected: $policy.alwaysAsk, exclude: [], tint: Palette.orange)
        }
    }

    private func nativePermissionsSection(project: Project) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            SectionLabel(title: "Native permissions (settings.json)")
            Text("Comma-or-newline-separated patterns Claude Code reads before any hook fires. Examples: Read(./src/**), Bash(git status:*), WebFetch(domain:github.com).")
                .font(Type.caption).foregroundStyle(Palette.fgMuted)
            VStack(alignment: .leading, spacing: 4) {
                Text("Allow").font(Type.label).foregroundStyle(Palette.green)
                TextEditor(text: $permAllow)
                    .font(Type.mono).frame(minHeight: 80)
                    .background(RoundedRectangle(cornerRadius: Metrics.Radius.md).fill(Palette.bgRaised))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.md).stroke(Palette.divider, lineWidth: 0.5))
                    .onChange(of: permAllow) { _, _ in permDirty = true }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Deny").font(Type.label).foregroundStyle(Palette.red)
                TextEditor(text: $permDeny)
                    .font(Type.mono).frame(minHeight: 80)
                    .background(RoundedRectangle(cornerRadius: Metrics.Radius.md).fill(Palette.bgRaised))
                    .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.md).stroke(Palette.divider, lineWidth: 0.5))
                    .onChange(of: permDeny) { _, _ in permDirty = true }
            }
            HStack {
                Spacer()
                Button("Save permissions") { savePermissions(project: project) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!permDirty)
            }
        }
    }

    private var destructiveSection: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            SectionLabel(title: "Destructive Bash patterns")
            Text("Even if Bash is auto-allowed, commands matching these regexes always ask. One per line.")
                .font(Type.caption).foregroundStyle(Palette.fgMuted)
            TextEditor(text: Binding(
                get: { policy.destructiveBashPatterns.joined(separator: "\n") },
                set: { newValue in
                    policy.destructiveBashPatterns = newValue.split(separator: "\n").map(String.init)
                    dirty = true
                }
            ))
            .font(Type.mono)
            .frame(minHeight: 120)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.md).fill(Palette.bgRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .stroke(Palette.divider, lineWidth: 0.5)
            )
        }
    }

    private func actionBar(project: Project) -> some View {
        HStack {
            Button("Reset to default") {
                policy = .default
                dirty = true
            }
            Spacer()
            if savedToast {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(Type.caption)
                    .foregroundStyle(Palette.green)
                    .transition(.opacity.combined(with: .scale))
            }
            Button("Save") { save(project: project) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!dirty)
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    @ViewBuilder
    private func toolGrid(allTools: [String], selected: Binding<[String]>, exclude: [String], tint: Color) -> some View {
        let columns = [GridItem(.adaptive(minimum: 140), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(allTools, id: \.self) { tool in
                Toggle(isOn: Binding(
                    get: { selected.wrappedValue.contains(tool) },
                    set: { newValue in
                        if newValue {
                            if !selected.wrappedValue.contains(tool) {
                                selected.wrappedValue.append(tool)
                            }
                        } else {
                            selected.wrappedValue.removeAll { $0 == tool }
                        }
                        dirty = true
                    }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(tint)
                        Text(tool).font(Type.body)
                        if exclude.contains(tool) {
                            Pill(text: "ask wins", tint: Palette.fgMuted)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func policyURL(in project: Project) -> URL {
        URL(fileURLWithPath: project.localPath).appendingPathComponent(".claude/policy.json")
    }

    private func load(project: Project) {
        let url = policyURL(in: project)
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode(ProjectPolicy.self, from: data) {
            policy = loaded
        } else {
            policy = .default
        }
        dirty = false
        error = nil
        loadPermissions(project: project)
    }

    private func settingsURL(in project: Project) -> URL {
        URL(fileURLWithPath: project.localPath).appendingPathComponent(".claude/settings.json")
    }

    private func loadPermissions(project: Project) {
        let url = settingsURL(in: project)
        let parsed = (try? Data(contentsOf: url))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let perms = parsed?["permissions"] as? [String: Any]
        permAllow = ((perms?["allow"] as? [String]) ?? []).joined(separator: "\n")
        permDeny = ((perms?["deny"] as? [String]) ?? []).joined(separator: "\n")
        permDirty = false
    }

    private func savePermissions(project: Project) {
        let url = settingsURL(in: project)
        var root = (try? Data(contentsOf: url))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            ?? [String: Any]()
        var perms = (root["permissions"] as? [String: Any]) ?? [:]
        perms["allow"] = splitPatterns(permAllow)
        perms["deny"] = splitPatterns(permDeny)
        root["permissions"] = perms
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            permDirty = false
            withAnimation { savedToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { savedToast = false }
            }
        } catch {
            self.error = "\(error)"
        }
    }

    private func splitPatterns(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func save(project: Project) {
        do {
            let url = policyURL(in: project)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(policy).write(to: url, options: .atomic)
            dirty = false
            withAnimation { savedToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { savedToast = false }
            }
        } catch {
            self.error = "\(error)"
        }
    }
}

struct ProjectPolicy: Codable, Equatable {
    var version: Int = 1
    var autoAllow: [String]
    var alwaysAsk: [String]
    var `default`: String      // "ask" / "allow" / "deny"
    var destructiveBashPatterns: [String]

    static let `default` = ProjectPolicy(
        autoAllow: ["Read", "Glob", "Grep", "WebSearch", "TodoWrite", "Skill"],
        alwaysAsk: ["Bash", "Edit", "Write", "NotebookEdit", "WebFetch"],
        default: "ask",
        destructiveBashPatterns: [
            "rm\\s+-rf",
            "rm\\s+-fr",
            "git\\s+push\\s+--force",
            "git\\s+reset\\s+--hard"
        ]
    )

    static let knownTools = [
        "Read", "Glob", "Grep", "Bash", "Edit", "Write",
        "NotebookEdit", "WebFetch", "WebSearch", "TodoWrite",
        "Task", "Skill", "ExitPlanMode"
    ]
}
