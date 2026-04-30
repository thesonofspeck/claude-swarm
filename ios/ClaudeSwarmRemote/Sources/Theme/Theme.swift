import SwiftUI
import UIKit

/// Atom One palette mirrored on iOS. Resolves per appearance via UIColor's
/// dynamic-provider initialiser so the same token works in light and dark.
enum Palette {
    static let bgDeep        = dynamic(light: 0xF5F5F5, dark: 0x181A1F)
    static let bgSidebar     = dynamic(light: 0xF0F0F0, dark: 0x21252B)
    static let bgBase        = dynamic(light: 0xFAFAFA, dark: 0x282C34)
    static let bgRaised      = dynamic(light: 0xFFFFFF, dark: 0x2C313A)
    static let bgSelection   = dynamic(light: 0xE5E5E6, dark: 0x3E4451)
    static let divider       = dynamic(light: 0xDCDDE0, dark: 0x181A1F)

    static let fg            = dynamic(light: 0x383A42, dark: 0xABB2BF)
    static let fgMuted       = dynamic(light: 0xA0A1A7, dark: 0x5C6370)
    static let fgBright      = dynamic(light: 0x202227, dark: 0xE5E5E5)

    static let blue          = dynamic(light: 0x4078F2, dark: 0x61AFEF)
    static let purple        = dynamic(light: 0xA626A4, dark: 0xC678DD)
    static let red           = dynamic(light: 0xE45649, dark: 0xE06C75)
    static let orange        = dynamic(light: 0x986801, dark: 0xD19A66)
    static let yellow        = dynamic(light: 0xC18401, dark: 0xE5C07B)
    static let green         = dynamic(light: 0x50A14F, dark: 0x98C379)
    static let cyan          = dynamic(light: 0x0184BC, dark: 0x56B6C2)

    private static func dynamic(light lightHex: UInt32, dark darkHex: UInt32, alpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            return UIColor(hex: isDark ? darkHex : lightHex, alpha: alpha)
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
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >>  8) & 0xFF) / 255
        let b = CGFloat( hex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
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
