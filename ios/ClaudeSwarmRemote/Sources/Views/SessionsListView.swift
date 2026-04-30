import SwiftUI
import PairingProtocol

struct SessionsListView: View {
    @EnvironmentObject var hub: AppHub

    var body: some View {
        List {
            // Pending approvals across all paired Macs surface at the top.
            let pending = approvalsAcrossAllMacs()
            if !pending.isEmpty {
                Section("Needs you") {
                    ForEach(pending, id: \.req.id) { entry in
                        NavigationLink {
                            ApprovalView(macId: entry.macId, request: entry.req)
                        } label: {
                            ApprovalRow(request: entry.req)
                        }
                    }
                }
            }

            ForEach(hub.pairedMacs) { mac in
                Section {
                    let client = hub.clients[mac.macId]
                    if let client {
                        if client.sessions.isEmpty {
                            Text("No active sessions")
                                .font(AppType.caption)
                                .foregroundStyle(Palette.fgMuted)
                        } else {
                            ForEach(client.sessions) { session in
                                NavigationLink {
                                    SessionDetailView(macId: mac.macId, session: session)
                                } label: {
                                    SessionRow(session: session)
                                }
                            }
                        }
                    }
                } header: {
                    macHeader(for: mac)
                }
            }
        }
    }

    private struct ApprovalEntry { let macId: String; let req: ApprovalRequest }

    private func approvalsAcrossAllMacs() -> [ApprovalEntry] {
        hub.pairedMacs.flatMap { mac in
            (hub.clients[mac.macId]?.pendingApprovals ?? []).map { ApprovalEntry(macId: mac.macId, req: $0) }
        }
    }

    private func macHeader(for mac: PairedMac) -> some View {
        let live = hub.clients[mac.macId]?.state == .live
        return HStack {
            Image(systemName: "desktopcomputer")
                .foregroundStyle(live ? Palette.green : Palette.fgMuted)
            Text(mac.macName)
                .font(AppType.heading)
            Spacer()
            Pill(text: live ? "online" : "offline", tint: live ? Palette.green : Palette.fgMuted)
        }
    }
}

struct SessionRow: View {
    let session: SessionSummary
    var body: some View {
        HStack(spacing: Metrics.Space.sm) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(session.taskTitle ?? session.branch)
                    .font(AppType.body)
                Text(session.branch)
                    .font(AppType.monoCaption)
                    .foregroundStyle(Palette.fgMuted)
                    .lineLimit(1)
            }
            Spacer()
            if session.needsInput {
                Pill(text: "Waiting", systemImage: "exclamationmark.bubble", tint: Palette.yellow)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusDot: some View {
        Circle()
            .fill(color(for: session.status))
            .frame(width: 8, height: 8)
    }

    private func color(for status: SessionStatusPayload) -> Color {
        switch status {
        case .running, .starting: return Palette.green
        case .waitingForInput: return Palette.yellow
        case .prOpen: return Palette.blue
        case .merged: return Palette.purple
        case .failed: return Palette.red
        default: return Palette.fgMuted
        }
    }
}

struct ApprovalRow: View {
    let request: ApprovalRequest
    var body: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: request.toolCall?.isDestructive == true ? "exclamationmark.triangle.fill" : "questionmark.bubble.fill")
                .foregroundStyle(request.toolCall?.isDestructive == true ? Palette.red : Palette.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.taskTitle ?? request.projectName)
                    .font(AppType.body)
                if let tool = request.toolCall {
                    Text("\(tool.toolName): \(tool.argumentSummary)")
                        .font(AppType.monoCaption)
                        .foregroundStyle(Palette.fgMuted)
                        .lineLimit(1)
                } else {
                    Text(request.prompt)
                        .font(AppType.caption)
                        .foregroundStyle(Palette.fgMuted)
                        .lineLimit(1)
                }
            }
        }
    }
}
