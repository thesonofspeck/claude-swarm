import SwiftUI
import PairingProtocol

struct ApprovalView: View {
    @Environment(AppHub.self) private var hub
    @Environment(\.dismiss) private var dismiss
    let macId: String
    let request: ApprovalRequest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                header
                contextBlock
                promptBlock
                actions
            }
            .padding(Metrics.Space.lg)
        }
        .navigationTitle("Approval")
        .navigationBarTitleDisplayMode(.inline)
        .background(Palette.bgBase)
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .imageScale(.large)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(request.projectName)
                    .font(AppType.heading)
                    .foregroundStyle(Palette.fgBright)
                Text(request.taskTitle ?? "")
                    .font(AppType.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var contextBlock: some View {
        if let tool = request.toolCall {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tool call").font(AppType.label).foregroundStyle(Palette.fgMuted)
                HStack(spacing: 6) {
                    Pill(text: tool.toolName, tint: Palette.blue)
                    if tool.isDestructive {
                        Pill(text: "destructive", systemImage: "exclamationmark.triangle.fill", tint: Palette.red)
                    }
                }
                Text(tool.argumentSummary)
                    .font(AppType.mono)
                    .foregroundStyle(Palette.fg)
                    .padding(Metrics.Space.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.Radius.md)
                            .fill(Palette.bgRaised)
                    )
                    .textSelection(.enabled)
            }
        }
    }

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Prompt").font(AppType.label).foregroundStyle(Palette.fgMuted)
            Text(request.prompt)
                .font(AppType.body)
                .foregroundStyle(Palette.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metrics.Space.md)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.Radius.md)
                        .fill(Palette.bgRaised)
                )
        }
    }

    private var actions: some View {
        VStack(spacing: Metrics.Space.sm) {
            Button {
                respond(.allow)
            } label: {
                Label("Approve", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(role: .destructive) {
                respond(.deny)
            } label: {
                Label("Deny", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private var icon: String {
        request.toolCall?.isDestructive == true ? "exclamationmark.triangle.fill" : "questionmark.bubble.fill"
    }

    private var tint: Color {
        request.toolCall?.isDestructive == true ? Palette.red : Palette.yellow
    }

    private func respond(_ response: ApprovalResponse) {
        guard let client = hub.clients[macId] else { return }
        client.approve(request, response: response)
        dismiss()
    }
}
