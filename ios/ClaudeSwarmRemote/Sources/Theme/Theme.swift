import SwiftUI
import UIKit
import AtomPalette

/// Atom One palette as iOS-side SwiftUI Colors. Hex values come from the
/// shared AtomPalette package; this file is just the platform wrapper
/// around UIColor's dynamic-provider initialiser.
enum Palette {
    static let bgDeep        = dyn(AtomHex.bgDeep)
    static let bgSidebar     = dyn(AtomHex.bgSidebar)
    static let bgBase        = dyn(AtomHex.bgBase)
    static let bgRaised      = dyn(AtomHex.bgRaised)
    static let bgSelection   = dyn(AtomHex.bgSelection)
    static let divider       = dyn(AtomHex.divider)

    static let fg            = dyn(AtomHex.fg)
    static let fgMuted       = dyn(AtomHex.fgMuted)
    static let fgBright      = dyn(AtomHex.fgBright)

    static let blue          = dyn(AtomHex.blue)
    static let purple        = dyn(AtomHex.purple)
    static let red           = dyn(AtomHex.red)
    static let orange        = dyn(AtomHex.orange)
    static let yellow        = dyn(AtomHex.yellow)
    static let green         = dyn(AtomHex.green)
    static let cyan          = dyn(AtomHex.cyan)

    private static func dyn(_ pair: AtomHex.Pair, alpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            return UIColor(hex: isDark ? pair.dark : pair.light, alpha: alpha)
        })
    }
}

enum Metrics {
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }
}

enum AppType {
    static let title = Font.system(.title2, design: .default).weight(.semibold)
    static let heading = Font.system(.headline, design: .default)
    static let body = Font.system(.body, design: .default)
    static let mono = Font.system(.body, design: .monospaced)
    static let caption = Font.system(.caption, design: .default)
    static let monoCaption = Font.system(.caption, design: .monospaced)
    static let label = Font.system(.caption2, design: .default).weight(.semibold)
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let (r, g, b) = HexToRGB.rgb(hex)
        self.init(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: alpha)
    }
}

struct Pill: View {
    let text: String
    var systemImage: String?
    var tint: Color = Palette.fgMuted

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text)
        }
        .font(AppType.label)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.10)))
        .overlay(Capsule().stroke(tint.opacity(0.18), lineWidth: 0.5))
    }
}
