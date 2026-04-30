import SwiftUI
import AppCore

struct ErrorBanner: View {
    let message: String?
    let onDismiss: () -> Void

    var body: some View {
        if let message {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.red)
                Text(message)
                    .font(Type.body)
                    .foregroundStyle(Palette.fg)
                    .lineLimit(2)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.fgMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Metrics.Space.md)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .fill(Palette.bgRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .stroke(Palette.red.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
            .frame(maxWidth: 720)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                onDismiss()
            }
        }
    }
}
