import SwiftUI
import PairingProtocol

struct SessionDetailView: View {
    @EnvironmentObject var hub: AppHub
    let macId: String
    let session: SessionSummary

    @State private var input: String = ""
    @State private var sending = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                    branchBlock
                    pendingApprovalsBlock
                }
                .padding(Metrics.Space.lg)
            }
            inputBar
        }
        .background(Palette.bgBase)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(session.taskTitle ?? session.branch)
                    .font(AppType.heading)
                    .lineLimit(1)
            }
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Pill(text: session.status.rawValue, tint: statusColor)
            if session.needsInput {
                Pill(text: "Waiting", systemImage: "exclamationmark.bubble.fill", tint: Palette.yellow)
            }
            Spacer()
            Text(session.updatedAt.formatted(.relative(presentation: .named)))
                .font(AppType.caption)
                .foregroundStyle(Palette.fgMuted)
        }
        .padding(Metrics.Space.md)
    }

    private var branchBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Branch").font(AppType.label).foregroundStyle(Palette.fgMuted)
            Text(session.branch)
                .font(AppType.mono)
                .foregroundStyle(Palette.purple)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var pendingApprovalsBlock: some View {
        let approvals = hub.clients[macId]?.pendingApprovals.filter { $0.sessionId == session.id } ?? []
        if !approvals.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                Text("Pending approvals").font(AppType.label).foregroundStyle(Palette.fgMuted)
                ForEach(approvals) { req in
                    NavigationLink {
                        ApprovalView(macId: macId, request: req)
                    } label: {
                        ApprovalRow(request: req)
                            .padding(Metrics.Space.md)
                            .background(
                                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                                    .fill(Palette.bgRaised)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: Metrics.Space.sm) {
            TextField("Send a message to Claude…", text: $input, axis: .vertical)
                .focused($fieldFocused)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.send)
                .onSubmit { send() }
            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
                    .padding(.horizontal, Metrics.Space.sm)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let client = hub.clients[macId] else { return }
        sending = true
        client.sendInput(sessionId: session.id, text: text)
        input = ""
        sending = false
    }

    private var statusColor: Color {
        switch session.status {
        case .running, .starting: return Palette.green
        case .waitingForInput: return Palette.yellow
        case .prOpen: return Palette.blue
        case .merged: return Palette.purple
        case .failed: return Palette.red
        default: return Palette.fgMuted
        }
    }
}
