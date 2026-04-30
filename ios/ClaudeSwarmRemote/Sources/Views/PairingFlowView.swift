import SwiftUI
import AVFoundation
import PairingProtocol

struct PairingFlowView: View {
    @EnvironmentObject var hub: AppHub
    @EnvironmentObject var push: PushManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: PairingViewModel
    @State private var showingScanner = true

    init() {
        _vm = StateObject(wrappedValue: PairingViewModel(store: PairedMacStore()))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bgBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Pair Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.status {
        case .idle, .connecting:
            VStack(spacing: 0) {
                if showingScanner {
                    QRScannerView { code in
                        showingScanner = false
                        Task { await vm.pair(fromCode: code, apnsToken: push.deviceTokenHex) }
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
                if vm.status == .connecting {
                    ProgressView("Connecting…").padding()
                }
            }
        case .authenticating:
            VStack(spacing: Metrics.Space.lg) {
                ProgressView()
                Text("Authenticating with Mac…")
                    .foregroundStyle(Palette.fgMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .success(let mac):
            successView(mac)
        case .failure(let reason):
            failureView(reason)
        }
    }

    private func successView(_ mac: PairedMac) -> some View {
        VStack(spacing: Metrics.Space.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Palette.green)
            Text("Paired with \(mac.macName)")
                .font(AppType.title)
                .foregroundStyle(Palette.fgBright)
            Button("Done") {
                hub.savePaired(mac)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(_ reason: String) -> some View {
        VStack(spacing: Metrics.Space.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Palette.red)
            Text("Pairing failed")
                .font(AppType.title)
                .foregroundStyle(Palette.fgBright)
            Text(reason)
                .font(AppType.body)
                .foregroundStyle(Palette.fgMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Metrics.Space.xl)
            Button("Try again") {
                vm.status = .idle
                showingScanner = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct QRScannerView: UIViewControllerRepresentable {
    let onDetect: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onDetect = onDetect
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onDetect: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !session.isRunning { session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.metadataObjectTypes = [.qr]
            output.setMetadataObjectsDelegate(self, queue: .main)
        }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              let value = object.stringValue else { return }
        session.stopRunning()
        onDetect?(value)
    }
}
