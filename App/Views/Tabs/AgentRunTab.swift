import SwiftUI
import AppCore
import PersistenceKit

/// Visualizes the team-lead → engineer → qe → reviewer chain (and any
/// other Task-tool delegations) for the active session. Auto-refreshes
/// when the transcript file changes via the workspace pulse.
struct AgentRunTab: View {
    @EnvironmentObject var env: AppEnvironment
    let session: Session
    @State private var root: AgentRun?
    @State private var loading = true
    @State private var selectedRunId: UUID?
    @State private var lastParsedSize: UInt64 = 0

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let root {
                content(root)
            } else {
                EmptyState(
                    title: "No agent activity yet",
                    systemImage: "person.3",
                    description: "Once team-lead delegates work, you'll see each subagent's prompt, status, and result here.",
                    tint: Palette.purple
                )
            }
        }
        .task(id: session.id) { await reload() }
        .task(id: session.id) {
            // Reload only when the workspace pulse signals .files —
            // PostToolUse hooks and FSEvents both flow through it.
            // No polling timer; the transcript only changes when the
            // session is actually doing something.
            let ws = env.gitWorkspace(for: session.worktreePath)
            for await invalidations in ws.pulse.events() {
                if invalidations.contains(.files) || invalidations.contains(.history) {
                    await reload()
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ root: AgentRun) -> some View {
        HSplitView {
            List(selection: $selectedRunId) {
                Section("Run") {
                    runRow(root, depth: 0)
                    ForEach(root.children) { child in
                        runRow(child, depth: 1)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.bgBase)
            .frame(minWidth: 320)

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.bgBase)
        }
    }

    private func runRow(_ run: AgentRun, depth: Int) -> some View {
        HStack(spacing: Metrics.Space.sm) {
            ForEach(0..<depth, id: \.self) { _ in
                Rectangle().fill(Palette.divider).frame(width: 1)
            }
            Image(systemName: agentIcon(run.agent))
                .foregroundStyle(agentTint(run.agent))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.agent)
                    .font(Type.body)
                    .foregroundStyle(Palette.fgBright)
                if let prompt = run.prompt {
                    Text(prompt)
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
            Pill(text: run.status.rawValue, tint: statusTint(run.status))
        }
        .padding(.vertical, 2)
        .tag(Optional(run.id))
    }

    @ViewBuilder
    private var detailPane: some View {
        if let id = selectedRunId, let run = locate(id, in: root) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                    HStack {
                        Image(systemName: agentIcon(run.agent))
                            .foregroundStyle(agentTint(run.agent))
                            .imageScale(.large)
                        Text(run.agent)
                            .font(Type.title)
                            .foregroundStyle(Palette.fgBright)
                        Spacer()
                        Pill(text: run.status.rawValue, tint: statusTint(run.status))
                        if let dur = run.duration {
                            Pill(text: "\(Int(dur))s", systemImage: "clock", tint: Palette.fgMuted)
                        }
                    }
                    if let prompt = run.prompt {
                        section(title: "Prompt", body: prompt, monospaced: true)
                    }
                    if let summary = run.summary {
                        section(title: "Result", body: summary, monospaced: true)
                    }
                }
                .padding(Metrics.Space.lg)
            }
        } else {
            EmptyState(
                title: "Select an agent",
                systemImage: "person.3",
                description: "Pick a delegation on the left to see its prompt and result.",
                tint: Palette.fgMuted
            )
        }
    }

    private func section(title: String, body: String, monospaced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: title)
            Card {
                Text(body)
                    .font(monospaced ? Type.mono : Type.body)
                    .foregroundStyle(Palette.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func reload() async {
        let url = URL(fileURLWithPath: session.transcriptPath)
        // Skip the parse entirely if the transcript hasn't grown since
        // last parse — the parser is the single most expensive thing on
        // this tab.
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        if size == lastParsedSize, root != nil {
            loading = false
            return
        }
        let result = await Task.detached { AgentRunParser.parse(transcriptAt: url) }.value
        root = result
        lastParsedSize = size
        loading = false
    }

    private func locate(_ id: UUID, in node: AgentRun?) -> AgentRun? {
        guard let node else { return nil }
        if node.id == id { return node }
        for child in node.children { if let hit = locate(id, in: child) { return hit } }
        return nil
    }

    private func agentIcon(_ agent: String) -> String {
        switch agent {
        case "team-lead": return "person.crop.circle.badge.checkmark"
        case "ux-designer": return "paintbrush"
        case "systems-architect": return "square.stack.3d.up"
        case "engineer": return "hammer"
        case "qe": return "checkmark.shield"
        case "reviewer": return "eye"
        default: return "person.fill"
        }
    }

    private func agentTint(_ agent: String) -> Color {
        switch agent {
        case "team-lead": return Palette.purple
        case "ux-designer": return Palette.cyan
        case "systems-architect": return Palette.blue
        case "engineer": return Palette.green
        case "qe": return Palette.yellow
        case "reviewer": return Palette.orange
        default: return Palette.fgMuted
        }
    }

    private func statusTint(_ status: AgentRun.Status) -> Color {
        switch status {
        case .running: return Palette.cyan
        case .succeeded: return Palette.green
        case .failed: return Palette.red
        case .unknown: return Palette.fgMuted
        }
    }
}
