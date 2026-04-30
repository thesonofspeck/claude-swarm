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
                    HStack {
                        Image(systemName: icon(for: name)).foregroundStyle(.secondary)
                        Text(name)
                        Spacer()
                        if name == "team-lead" {
                            Text("primary").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .tag(name)
                }
                .frame(minWidth: 200, idealWidth: 240)
                .listStyle(.sidebar)

                editor(for: project)
            }
            .task(id: "\(project.id)|\(selectedAgent)") { load(project: project) }
        } else {
            ContentUnavailableView(
                "No project selected",
                systemImage: "person.3",
                description: Text("Pick a project to view its agents.")
            )
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedAgent).font(.headline)
                if dirty { Text("•").foregroundStyle(.orange) }
                Spacer()
                Button("Reset to default") {
                    resetToDefault(project: project)
                }
                .disabled(!fileExists(in: project))

                Button("Save") {
                    save(project: project)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!dirty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
            }

            TextEditor(text: $content)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .onChange(of: content) { _, _ in dirty = true }
                .overlay(alignment: .topTrailing) {
                    if savedToast {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                            .transition(.opacity)
                    }
                }
        }
    }

    private func agentURL(in project: Project) -> URL {
        URL(fileURLWithPath: project.localPath)
            .appendingPathComponent(".claude/agents/\(selectedAgent).md")
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
