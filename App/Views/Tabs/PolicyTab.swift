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
