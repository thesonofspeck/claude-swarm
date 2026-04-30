import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Atom One Dark base, Atom blue accent, faint purple secondary glow.
// Glyph: three offset rounded rectangles representing layered Claude sessions.

struct Spec {
    let pixels: Int
    let filename: String
}

let specs: [Spec] = [
    .init(pixels: 16,   filename: "icon_16x16.png"),
    .init(pixels: 32,   filename: "icon_16x16@2x.png"),
    .init(pixels: 32,   filename: "icon_32x32.png"),
    .init(pixels: 64,   filename: "icon_32x32@2x.png"),
    .init(pixels: 128,  filename: "icon_128x128.png"),
    .init(pixels: 256,  filename: "icon_128x128@2x.png"),
    .init(pixels: 256,  filename: "icon_256x256.png"),
    .init(pixels: 512,  filename: "icon_256x256@2x.png"),
    .init(pixels: 512,  filename: "icon_512x512.png"),
    .init(pixels: 1024, filename: "icon_512x512@2x.png")
]

let outDir: URL
if CommandLine.arguments.count >= 2 {
    outDir = URL(fileURLWithPath: CommandLine.arguments[1])
} else {
    let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    outDir = here.appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")
}
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // Atom One Dark surface gradient: bgDeep -> bgBase
    let bg = CGGradient(
        colorsSpace: space,
        colors: [
            color(0x181A1F),
            color(0x282C34)
        ] as CFArray,
        locations: [0, 1]
    )!
    // Rounded squircle mask matching macOS Big Sur+ icon shape (squircle radius ~0.225 of side).
    let inset = s * 0.10
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Soft Atom blue glow top-right.
    let glow = CGGradient(
        colorsSpace: space,
        colors: [
            color(0x61AFEF, alpha: 0.45),
            color(0x61AFEF, alpha: 0)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: s * 0.78, y: s * 0.78),
        startRadius: 0,
        endCenter: CGPoint(x: s * 0.78, y: s * 0.78),
        endRadius: s * 0.55,
        options: []
    )

    // Soft purple glow bottom-left.
    let glow2 = CGGradient(
        colorsSpace: space,
        colors: [
            color(0xC678DD, alpha: 0.30),
            color(0xC678DD, alpha: 0)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawRadialGradient(
        glow2,
        startCenter: CGPoint(x: s * 0.22, y: s * 0.22),
        startRadius: 0,
        endCenter: CGPoint(x: s * 0.22, y: s * 0.22),
        endRadius: s * 0.5,
        options: []
    )

    // Three offset rounded squares — "swarm" of sessions in Atom blue + cyan + green.
    let glyphInset = s * 0.30
    let glyphRect = rect.insetBy(dx: glyphInset, dy: glyphInset)
    let r = glyphRect.width * 0.18
    let offsets: [(CGFloat, CGFloat, UInt32, CGFloat)] = [
        ( 0.12,  0.12, 0x98C379, 0.85),  // green back
        (-0.06,  0.00, 0x56B6C2, 0.95),  // cyan middle
        (-0.18, -0.10, 0x61AFEF, 1.00)   // blue front (signature)
    ]
    for (dx, dy, hex, alpha) in offsets {
        let r2 = glyphRect.offsetBy(dx: dx * glyphRect.width * 0.5, dy: dy * glyphRect.height * 0.5)
        ctx.setFillColor(color(hex, alpha: alpha))
        ctx.addPath(CGPath(roundedRect: r2, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.fillPath()
        // Inner stroke for crispness
        ctx.setStrokeColor(color(0x181A1F, alpha: 0.4))
        ctx.setLineWidth(s * 0.004)
        ctx.addPath(CGPath(roundedRect: r2, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.strokePath()
    }

    // Subtle inner bevel highlight along the squircle's top edge.
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let bevel = CGGradient(
        colorsSpace: space,
        colors: [
            color(0xFFFFFF, alpha: 0.10),
            color(0xFFFFFF, alpha: 0)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(bevel, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: s * 0.4), options: [])
    ctx.restoreGState()

    return ctx.makeImage()
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >>  8) & 0xFF) / 255
    let b = CGFloat( hex        & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: alpha)
}

for spec in specs {
    guard let image = render(size: spec.pixels) else {
        FileHandle.standardError.write(Data("Failed to render \(spec.pixels)px\n".utf8))
        continue
    }
    let url = outDir.appendingPathComponent(spec.filename)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write(Data("Failed to open \(url.path)\n".utf8))
        continue
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.path)")
}

// Update Contents.json with filename references.
let contents = """
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16",   "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16",   "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32",   "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32",   "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contents.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote Contents.json")
