import SwiftUI
import PersistenceKit
import AppCore

struct InspectorView: View {
    let session: Session?

    var body: some View {
        Group {
            if let session {
                content(session)
            } else {
                EmptyState(
                    title: "No session",
                    systemImage: "info.circle",
                    description: "Select a session in the sidebar to see its details.",
                    tint: Palette.fgMuted
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func content(_ session: Session) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                taskBlock(session)
                branchBlock(session)
                prBlock(session)
                actionsBlock(session)
                Spacer(minLength: 0)
            }
            .padding(Metrics.Space.lg)
        }
    }

    private func taskBlock(_ session: Session) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                SectionLabel(title: "Task")
                Text(session.taskTitle ?? "—")
                    .font(Type.heading)
                    .foregroundStyle(Palette.fgBright)
                if let id = session.taskId {
                    Pill(text: id, systemImage: "tag", tint: Palette.cyan)
                }
            }
        }
    }

    private func branchBlock(_ session: Session) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                SectionLabel(title: "Branch")
                Text(session.branch)
                    .font(Type.mono)
                    .foregroundStyle(Palette.fg)
                    .textSelection(.enabled)
                HStack {
                    statusPill(for: session.status)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func prBlock(_ session: Session) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                SectionLabel(title: "Pull request")
                if let n = session.prNumber {
                    HStack(spacing: Metrics.Space.sm) {
                        Image(systemName: "arrow.triangle.pull")
                            .foregroundStyle(Palette.blue)
                        Text("#\(n)")
                            .font(Type.heading)
                            .foregroundStyle(Palette.fgBright)
                    }
                } else {
                    Text("Not opened")
                        .font(Type.body)
                        .foregroundStyle(Palette.fgMuted)
                }
            }
        }
    }

    private func actionsBlock(_ session: Session) -> some View {
        Card(padding: Metrics.Space.sm) {
            VStack(spacing: 0) {
                actionRow(label: "Open worktree in Finder", systemImage: "folder") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: session.worktreePath))
                }
                Divider().background(Palette.divider)
                actionRow(label: "Copy branch name", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.branch, forType: .string)
                }
            }
        }
    }

    private func actionRow(label: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .foregroundStyle(Palette.fgMuted)
                    .frame(width: 16)
                Text(label)
                    .font(Type.body)
                    .foregroundStyle(Palette.fg)
                Spacer()
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(Palette.fgMuted)
            }
            .padding(.horizontal, Metrics.Space.sm)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusPill(for status: SessionStatus) -> some View {
        let (label, tint, icon) = statusMeta(status)
        return Pill(text: label, systemImage: icon, tint: tint)
    }

    private func statusMeta(_ status: SessionStatus) -> (String, Color, String) {
        switch status {
        case .starting: return ("Starting", Palette.fgMuted, "circle.dotted")
        case .running: return ("Running", Palette.green, "circle.fill")
        case .waitingForInput: return ("Waiting", Palette.yellow, "circle.fill")
        case .idle: return ("Idle", Palette.fgMuted, "pause.circle")
        case .finished: return ("Finished", Palette.fgMuted, "checkmark.circle")
        case .archived: return ("Archived", Palette.fgMuted, "archivebox")
        case .prOpen: return ("PR open", Palette.blue, "arrow.triangle.pull")
        case .merged: return ("Merged", Palette.purple, "checkmark.seal.fill")
        case .failed: return ("Failed", Palette.red, "exclamationmark.triangle")
        }
    }
}
