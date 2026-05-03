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

/// A pulsing dot used to mark sessions waiting for input. Uses
/// `symbolEffect(.pulse, options: .repeating)` so Reduce Motion is
/// respected automatically and the animation runs on the GPU.
struct PulseDot: View {
    var color: Color = Palette.yellow

    var body: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 8))
            .foregroundStyle(color)
            .symbolEffect(.pulse, options: .repeating)
            .shadow(color: color.opacity(0.5), radius: 3)
            .accessibilityHidden(true)
    }
}

/// Branded empty state. Wraps the system `ContentUnavailableView` with
/// an Atom-tinted symbol so empty screens feel intentional while still
/// inheriting the system's a11y / VoiceOver behavior.
struct EmptyState: View {
    let title: String
    let systemImage: String
    let description: String
    var tint: Color = Palette.blue

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
        } description: {
            Text(description)
                .font(Type.body)
                .foregroundStyle(Palette.fgMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.Space.xl)
    }
}

/// Toolbar/inline icon button styled to match Atom's restrained chrome.
/// `help` doubles as the VoiceOver label so icon-only buttons describe
/// themselves to assistive technologies (`.help` is a tooltip only).
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
        .accessibilityLabel(help.isEmpty ? Text(systemImage) : Text(help))
    }
}
