import SwiftUI
import AppCore
import PairingProtocol

#if canImport(CoreImage)
import CoreImage.CIFilterBuiltins
#endif

struct PairingSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var invite: PairingInvite?
    @State private var qrImage: NSImage?

    var body: some View {
        VStack(spacing: Metrics.Space.md) {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: "iphone.gen3")
                    .foregroundStyle(Palette.blue)
                    .imageScale(.large)
                Text("Pair iPhone")
                    .font(Type.title)
                    .foregroundStyle(Palette.fgBright)
                Spacer()
            }
            Text("Scan this code in the Claude Swarm Remote app on your iPhone. The code is valid for 5 minutes and works once.")
                .font(Type.body)
                .foregroundStyle(Palette.fgMuted)

            if let qrImage {
                Image(nsImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: 240, height: 240)
                    .padding(Metrics.Space.md)
                    .background(
                        RoundedRectangle(cornerRadius: Metrics.Radius.md)
                            .fill(Color.white)
                    )
            } else {
                ProgressView().frame(width: 240, height: 240)
            }

            if let invite {
                VStack(spacing: 4) {
                    Text("Manual fallback")
                        .font(Type.label)
                        .foregroundStyle(Palette.fgMuted)
                    HStack(spacing: Metrics.Space.sm) {
                        Pill(text: "\(invite.host):\(invite.port)", systemImage: "wifi", tint: Palette.cyan)
                        Pill(text: invite.pairingCode, systemImage: "key", tint: Palette.purple)
                    }
                }
            }

            Spacer()

            HStack {
                Button("New code") { Task { await regenerate() } }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Metrics.Space.lg)
        .frame(width: 460, height: 520)
        .background(Palette.bgSidebar)
        .task { await regenerate() }
    }

    private func regenerate() async {
        let issued = await env.remote.issueInvite()
        let encoded = (try? PairCodec.encodeInvite(issued)) ?? ""
        let img = await Task.detached { generateQR(from: encoded) }.value
        await MainActor.run {
            invite = issued
            qrImage = img
        }
    }
}

func generateQR(from string: String) -> NSImage? {
    #if canImport(CoreImage)
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let scale = CGAffineTransform(scaleX: 8, y: 8)
    let scaled = output.transformed(by: scale)
    let rep = NSCIImageRep(ciImage: scaled)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
    #else
    return nil
    #endif
}
