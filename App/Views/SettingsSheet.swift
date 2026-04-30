import SwiftUI
import AppCore
import KeychainKit
import WrikeKit
import ApnsClient
import PairingProtocol

struct SettingsSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var wrikeToken: String = ""
    @State private var wrikeStored: Bool = false
    @State private var ghAuthLine: String = "Checking…"
    @State private var ghAuthenticated: Bool = false
    @State private var claudePath: String = ""
    @State private var defaultBranch: String = ""
    @State private var error: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            wrikeTab
                .tabItem { Label("Wrike", systemImage: "checklist") }
            githubTab
                .tabItem { Label("GitHub", systemImage: "arrow.triangle.pull") }
            iPhoneTab
                .tabItem { Label("iPhone", systemImage: "iphone.gen3") }
            apnsTab
                .tabItem { Label("APNs", systemImage: "bell.badge") }
        }
        .padding()
        .frame(width: 580, height: 480)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    save()
                    dismiss()
                }
            }
        }
        .task { await refresh() }
    }

    private var generalTab: some View {
        Form {
            Section("Claude Code") {
                HStack {
                    TextField("Executable path", text: $claudePath)
                    Button("Locate…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            claudePath = url.path
                        }
                    }
                }
            }
            Section("Defaults") {
                TextField("Default base branch", text: $defaultBranch)
            }
            if let error {
                Section { Text(error).foregroundStyle(Palette.red) }
            }
        }
        .formStyle(.grouped)
    }

    private var wrikeTab: some View {
        Form {
            Section("Personal Access Token") {
                if wrikeStored {
                    HStack(spacing: Metrics.Space.sm) {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(Palette.green)
                        Text("Token stored in Keychain").foregroundStyle(Palette.fg)
                        Spacer()
                        Button("Replace") { wrikeStored = false; wrikeToken = "" }
                        Button("Remove", role: .destructive) {
                            try? env.keychain.remove(account: KeychainAccount.wrike)
                            wrikeStored = false; wrikeToken = ""
                        }
                    }
                } else {
                    SecureField("Wrike PAT", text: $wrikeToken)
                    Button("Save token") {
                        do {
                            try env.keychain.set(wrikeToken, account: KeychainAccount.wrike)
                            wrikeStored = true
                            wrikeToken = ""
                        } catch {
                            self.error = "\(error)"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(wrikeToken.isEmpty)
                }
            }
            Section("Help") {
                Link("Generate a Wrike PAT", destination: URL(string: "https://help.wrike.com/hc/en-us/articles/210409445")!)
                    .foregroundStyle(Palette.blue)
            }
        }
        .formStyle(.grouped)
    }

    private var githubTab: some View {
        Form {
            Section("gh CLI") {
                HStack(spacing: Metrics.Space.sm) {
                    Image(systemName: ghAuthenticated ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .foregroundStyle(ghAuthenticated ? Palette.green : Palette.orange)
                    Text(ghAuthenticated ? "Authenticated" : "Not authenticated")
                        .foregroundStyle(Palette.fg)
                    Spacer()
                    Button("Recheck") { Task { await refresh() } }
                }
                Text(ghAuthLine)
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
                    .lineLimit(4)
            }
            Section("Help") {
                Text("This app uses the GitHub CLI for all GitHub operations. To authenticate, run `gh auth login` in a terminal — the app picks up your existing session.")
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
        }
        .formStyle(.grouped)
    }

    @State private var showPairingSheet = false
    @State private var honourBattery = true

    private var iPhoneTab: some View {
        Form {
            Section("Pairing") {
                Button {
                    showPairingSheet = true
                } label: {
                    Label("Pair new iPhone…", systemImage: "qrcode")
                }
                .buttonStyle(.borderedProminent)
            }
            Section("Paired devices") {
                if env.remote.pairedDevices.isEmpty {
                    Text("No iPhones paired yet.")
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                } else {
                    ForEach(env.remote.pairedDevices) { record in
                        HStack {
                            Image(systemName: "iphone.gen3")
                                .foregroundStyle(env.remote.liveDeviceIds.contains(record.id) ? Palette.green : Palette.fgMuted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.deviceName).font(Type.body)
                                Text("Last seen \(record.lastSeenAt.formatted(.relative(presentation: .named)))")
                                    .font(Type.caption)
                                    .foregroundStyle(Palette.fgMuted)
                            }
                            Spacer()
                            Button("Unpair", role: .destructive) {
                                Task { await env.remote.unpair(deviceId: record.id) }
                            }
                        }
                    }
                }
            }
            Section("Stay awake") {
                HStack {
                    Image(systemName: env.remote.sleepGuardHeld ? "sun.max.fill" : "moon.zzz")
                        .foregroundStyle(env.remote.sleepGuardHeld ? Palette.yellow : Palette.fgMuted)
                    Text(env.remote.sleepGuardHeld
                        ? "Mac is held awake — paired iPhone is online."
                        : "Mac will sleep normally.")
                        .font(Type.body)
                }
                Toggle("Allow sleep on battery", isOn: $honourBattery)
                    .onChange(of: honourBattery) { _, value in
                        Task { await env.remote.sleepGuard.setHonourBattery(value) }
                    }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showPairingSheet) {
            PairingSheet().environmentObject(env)
        }
    }

    @State private var apnsTeamId = ""
    @State private var apnsKeyId = ""
    @State private var apnsBundleId = "com.claudeswarm.remote"
    @State private var apnsEnvironment: ApnsConfig.Environment = .production
    @State private var apnsEnabled = false
    @State private var apnsKeyLoaded = false

    private var apnsTab: some View {
        Form {
            Section("Apple Developer credentials") {
                TextField("Team ID", text: $apnsTeamId)
                TextField("Key ID", text: $apnsKeyId)
                TextField("iOS bundle id", text: $apnsBundleId)
                Picker("Environment", selection: $apnsEnvironment) {
                    Text("Production").tag(ApnsConfig.Environment.production)
                    Text("Sandbox").tag(ApnsConfig.Environment.sandbox)
                }
                Toggle("Send pushes to paired devices", isOn: $apnsEnabled)
            }
            Section("APNs key (.p8)") {
                if apnsKeyLoaded {
                    HStack {
                        Image(systemName: "key.fill").foregroundStyle(Palette.green)
                        Text("Key stored in Keychain")
                        Spacer()
                        Button("Replace") { uploadKey() }
                        Button("Remove", role: .destructive) {
                            env.remote.removeApnsKey()
                            apnsKeyLoaded = false
                        }
                    }
                } else {
                    Button {
                        uploadKey()
                    } label: {
                        Label("Upload .p8 key…", systemImage: "doc.badge.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Section {
                Button("Save APNs settings") {
                    saveApns()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .task { reloadApns() }
    }

    private func uploadKey() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let pem = try String(contentsOf: url, encoding: .utf8)
                try env.remote.saveApnsKey(pem: pem)
                apnsKeyLoaded = true
            } catch {
                self.error = "Could not load .p8 file: \(error.localizedDescription)"
            }
        }
    }

    private func saveApns() {
        var cfg = env.remote.apnsConfig
        cfg.teamId = apnsTeamId
        cfg.keyId = apnsKeyId
        cfg.bundleId = apnsBundleId
        cfg.environment = apnsEnvironment
        cfg.enabled = apnsEnabled
        env.remote.saveApnsConfig(cfg)
    }

    private func reloadApns() {
        let cfg = env.remote.apnsConfig
        apnsTeamId = cfg.teamId
        apnsKeyId = cfg.keyId
        apnsBundleId = cfg.bundleId
        apnsEnvironment = cfg.environment
        apnsEnabled = cfg.enabled
        apnsKeyLoaded = env.remote.hasApnsKey()
    }

    private func refresh() async {
        let stored = (try? env.keychain.get(account: KeychainAccount.wrike)) != nil
        let path = env.settings.claudeExecutable
        let branch = env.settings.defaultBaseBranch
        let status = await env.github.authStatus()
        await MainActor.run {
            wrikeStored = stored
            claudePath = path
            defaultBranch = branch
            ghAuthenticated = status.authenticated
            ghAuthLine = status.user.map { "Logged in as \($0)" } ?? status.raw
        }
    }

    private func save() {
        env.settings.claudeExecutable = claudePath
        env.settings.defaultBaseBranch = defaultBranch
        env.saveSettings()
    }
}
