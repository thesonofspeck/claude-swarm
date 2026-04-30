import SwiftUI

/// A monochrome capsule pill — used for status, tags, badges. Color
/// optionally tints the dot and text.
struct Pill: View {
    let text: String
    var systemImage: String?
    var tint: Color = Palette.fgMuted

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(Type.label)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Palette.pillBg)
        )
        .overlay(
            Capsule().stroke(tint.opacity(0.18), lineWidth: Metrics.Stroke.hairline)
        )
    }
}

struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(Type.label)
            .tracking(0.6)
            .foregroundStyle(Palette.fgMuted)
    }
}

/// A subtle card surface for grouped content — used for review comments,
/// inspector blocks, etc.
struct Card<Content: View>: View {
    var padding: CGFloat = Metrics.Space.md
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .fill(Palette.bgRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .stroke(Palette.divider, lineWidth: Metrics.Stroke.hairline)
            )
    }
}

/// A pulsing dot used to mark sessions waiting for input. Uses `symbolEffect`
/// on macOS 14+, falls back to opacity animation otherwise.
struct PulseDot: View {
    var color: Color = Palette.yellow
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .scaleEffect(pulsing ? 1.0 : 0.85)
            .opacity(pulsing ? 1.0 : 0.55)
            .shadow(color: color.opacity(0.5), radius: pulsing ? 3 : 0)
            .accessibilityHidden(true)
            .onAppear {
                withAnimation(Motion.pulse) {
                    pulsing = true
                }
            }
    }
}

/// Branded empty state. Wraps `ContentUnavailableView` but with an Atom-themed
/// icon halo and palette colors so empty screens feel intentional.
struct EmptyState: View {
    let title: String
    let systemImage: String
    let description: String
    var tint: Color = Palette.blue

    var body: some View {
        VStack(spacing: Metrics.Space.lg) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.10))
                    .frame(width: 96, height: 96)
                Circle()
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
                    .frame(width: 124, height: 124)
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(tint)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(Type.title)
                    .foregroundStyle(Palette.fgBright)
                Text(description)
                    .font(Type.body)
                    .foregroundStyle(Palette.fgMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.Space.xl)
    }
}

/// Toolbar/inline icon button styled to match Atom's restrained chrome.
struct IconButton: View {
    let systemImage: String
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .imageScale(.medium)
                .foregroundStyle(Palette.fgMuted)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
