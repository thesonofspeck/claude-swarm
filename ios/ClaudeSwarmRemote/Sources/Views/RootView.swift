import SwiftUI
import PairingProtocol

struct RootView: View {
    @Environment(AppHub.self) private var hub
    @State private var presentingPairing = false

    var body: some View {
        Group {
            if hub.pairedMacs.isEmpty {
                EmptyPairingView { presentingPairing = true }
            } else {
                NavigationStack {
                    SessionsListView()
                        .navigationTitle("Sessions")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button {
                                    presentingPairing = true
                                } label: {
                                    Image(systemName: "iphone.gen3")
                                }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $presentingPairing) {
            PairingFlowView()
                .environment(hub)
        }
    }
}

struct EmptyPairingView: View {
    let onPair: () -> Void

    var body: some View {
        VStack(spacing: Metrics.Space.lg) {
            ZStack {
                Circle()
                    .fill(Palette.blue.opacity(0.12))
                    .frame(width: 120, height: 120)
                Circle()
                    .strokeBorder(Palette.blue.opacity(0.25), lineWidth: 1)
                    .frame(width: 152, height: 152)
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Palette.blue)
            }
            VStack(spacing: 6) {
                Text("Pair your Mac")
                    .font(AppType.title)
                    .foregroundStyle(Palette.fgBright)
                Text("Open Claude Swarm on your Mac, click Settings → iPhone → Pair, and scan the QR.")
                    .font(AppType.body)
                    .foregroundStyle(Palette.fgMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Metrics.Space.xl)
            }
            Button {
                onPair()
            } label: {
                Label("Scan pairing QR", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, Metrics.Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgBase)
    }
}
