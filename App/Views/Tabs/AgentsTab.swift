import SwiftUI
import AppCore
import AgentBootstrap
import PersistenceKit

struct AgentsTab: View {
    @EnvironmentObject var env: AppEnvironment
    let project: Project?

    @State private var selectedAgent: String = "team-lead"
    @State private var content: String = ""
    @State private var dirty: Bool = false
    @State private var error: String?
    @State private var savedToast: Bool = false

    var body: some View {
        if let project {
            HSplitView {
                List(Installer.agentNames, id: \.self, selection: $selectedAgent) { name in
                    HStack(spacing: Metrics.Space.sm) {
                        Image(systemName: icon(for: name))
                            .foregroundStyle(tint(for: name))
                            .imageScale(.small)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(tint(for: name).opacity(0.10)))
                        Text(name)
                            .font(Type.body)
                            .foregroundStyle(Palette.fg)
                        Spacer()
                        if name == "team-lead" {
                            Pill(text: "PRIMARY", tint: Palette.blue)
                        }
                    }
                    .padding(.vertical, 2)
                    .tag(name)
                }
                .frame(minWidth: 220, idealWidth: 260)
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(Palette.bgSidebar)

                editor(for: project)
            }
            .task(id: "\(project.id)|\(selectedAgent)") { load(project: project) }
        } else {
            EmptyState(
                title: "No project selected",
                systemImage: "person.3",
                description: "Pick a project to view its agents.",
                tint: Palette.fgMuted
            )
        }
    }

    private func tint(for name: String) -> Color {
        switch name {
        case "team-lead": return Palette.blue
        case "ux-designer": return Palette.purple
        case "systems-architect": return Palette.cyan
        case "engineer": return Palette.green
        case "qe": return Palette.orange
        case "reviewer": return Palette.yellow
        default: return Palette.fgMuted
        }
    }

    private func icon(for name: String) -> String {
        switch name {
        case "team-lead": return "person.fill.badge.plus"
        case "ux-designer": return "paintpalette"
        case "systems-architect": return "square.grid.3x3"
        case "engineer": return "hammer"
        case "qe": return "ladybug"
        case "reviewer": return "checkmark.seal"
        default: return "person"
        }
    }

    private func editor(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: icon(for: selectedAgent))
                    .foregroundStyle(tint(for: selectedAgent))
                Text(selectedAgent)
                    .font(Type.heading)
                    .foregroundStyle(Palette.fgBright)
                if dirty {
                    Circle()
                        .fill(Palette.orange)
                        .frame(width: 6, height: 6)
                }
                Spacer()
                Button("Reset to default") {
                    resetToDefault(project: project)
                }
                .disabled(!fileExists(in: project))

                Button("Save") {
                    save(project: project)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!dirty)
            }
            .padding(.horizontal, Metrics.Space.lg)
            .padding(.top, Metrics.Space.md)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.orange)
                    .padding(.horizontal, Metrics.Space.lg)
            }

            TextEditor(text: $content)
                .font(Type.mono)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Metrics.Space.sm)
                .background(Palette.bgBase)
                .onChange(of: content) { _, _ in dirty = true }
                .overlay(alignment: .topTrailing) {
                    if savedToast {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Palette.green)
                            Text("Saved")
                                .font(Type.caption)
                                .foregroundStyle(Palette.fg)
                        }
                        .padding(.horizontal, Metrics.Space.sm)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: Metrics.Radius.md)
                                .fill(Palette.bgRaised)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Metrics.Radius.md)
                                .stroke(Palette.divider, lineWidth: Metrics.Stroke.hairline)
                        )
                        .padding(Metrics.Space.md)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
        }
    }

    private func agentURL(in project: Project) -> URL {
        AgentLayout.agentFile(
            in: URL(fileURLWithPath: project.localPath),
            name: selectedAgent
        )
    }

    private func fileExists(in project: Project) -> Bool {
        FileManager.default.fileExists(atPath: agentURL(in: project).path)
    }

    private func load(project: Project) {
        let url = agentURL(in: project)
        if let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) {
            content = text
        } else {
            // Fallback to bundled template (project hasn't been bootstrapped yet).
            if let bundled = try? BootstrapResources.agentTemplate(selectedAgent),
               let data = try? Data(contentsOf: bundled),
               let text = String(data: data, encoding: .utf8) {
                content = text
            } else {
                content = ""
            }
        }
        dirty = false
        error = nil
    }

    private func save(project: Project) {
        let url = agentURL(in: project)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(content.utf8).write(to: url, options: .atomic)
            dirty = false
            withAnimation { savedToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { savedToast = false }
            }
        } catch {
            self.error = "\(error)"
        }
    }

    private func resetToDefault(project: Project) {
        if let bundled = try? BootstrapResources.agentTemplate(selectedAgent),
           let data = try? Data(contentsOf: bundled),
           let text = String(data: data, encoding: .utf8) {
            content = text
            dirty = true
        }
    }
}
