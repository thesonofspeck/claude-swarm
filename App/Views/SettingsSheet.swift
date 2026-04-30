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
                .tabItem { Label("Push", systemImage: "bell.badge") }
            diagnosticsTab
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            activityTab
                .tabItem { Label("Activity", systemImage: "bolt.heart") }
        }
        .padding()
        .frame(width: 620, height: 540)
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
            Section("Tools") {
                ToolsStep(onContinue: {})
                    .environmentObject(env)
                    .frame(minHeight: 360)
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
            Section("Quiet hours") {
                Toggle("Hold pushes during quiet hours", isOn: $quietHoursEnabled)
                    .onChange(of: quietHoursEnabled) { _, _ in saveQuietHours() }
                if quietHoursEnabled {
                    DatePicker(
                        "Start",
                        selection: $quietHoursStart,
                        displayedComponents: [.hourAndMinute]
                    )
                    .onChange(of: quietHoursStart) { _, _ in saveQuietHours() }
                    DatePicker(
                        "End",
                        selection: $quietHoursEnd,
                        displayedComponents: [.hourAndMinute]
                    )
                    .onChange(of: quietHoursEnd) { _, _ in saveQuietHours() }
                    Text("Approval pushes during this window are held and delivered when it ends. Live WebSocket events still flow.")
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                }
            }
        }
        .formStyle(.grouped)
        .task { reloadQuietHours() }
        .sheet(isPresented: $showPairingSheet) {
            PairingSheet().environmentObject(env)
        }
    }

    @State private var quietHoursEnabled = false
    @State private var quietHoursStart = Date()
    @State private var quietHoursEnd = Date()

    private func reloadQuietHours() {
        quietHoursEnabled = env.settings.quietHoursEnabled
        quietHoursStart = dateFromMinute(env.settings.quietHoursStartMinute)
        quietHoursEnd = dateFromMinute(env.settings.quietHoursEndMinute)
    }

    private func saveQuietHours() {
        env.settings.quietHoursEnabled = quietHoursEnabled
        env.settings.quietHoursStartMinute = minuteFrom(quietHoursStart)
        env.settings.quietHoursEndMinute = minuteFrom(quietHoursEnd)
        env.saveSettings()
    }

    private func dateFromMinute(_ minutes: Int) -> Date {
        var comps = DateComponents()
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func minuteFrom(_ date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private var diagnosticsTab: some View {
        DiagnosticsView()
            .environmentObject(env)
    }

    private var activityTab: some View {
        ActivityFeedView()
            .environmentObject(env)
    }

    @State private var apnsTeamId = ""
    @State private var apnsKeyId = ""
    @State private var apnsBundleId = "com.claudeswarm.remote"
    @State private var apnsEnvironment: ApnsConfig.Environment = .production
    @State private var apnsEnabled = false
    @State private var apnsKeyLoaded = false
    @State private var pushBackend: PushBackend = .direct
    @State private var relayURL = ""
    @State private var relaySecret = ""
    @State private var relayEnabled = false
    @State private var relaySecretStored = false

    private var apnsTab: some View {
        Form {
            Section("Backend") {
                Picker("Send pushes via", selection: $pushBackend) {
                    Text("Company relay (recommended)").tag(PushBackend.relay)
                    Text("Direct from this Mac").tag(PushBackend.direct)
                }
                .pickerStyle(.inline)
                Text(pushBackend == .relay
                    ? "This Mac POSTs to your team's relay; the relay holds the .p8 key. No Developer Program seat needed here."
                    : "This Mac talks directly to APNs using a .p8 key stored locally. Each teammate needs their own key.")
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
            if pushBackend == .relay {
                relaySection
            } else {
                directSection
            }
            Section {
                Button("Save push settings") { saveApns() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .task { reloadApns() }
    }

    private var relaySection: some View {
        Group {
            Section("Relay") {
                TextField("Relay URL (https://swarm-push.internal/push)", text: $relayURL)
                Toggle("Send pushes via relay", isOn: $relayEnabled)
            }
            Section("Shared secret") {
                if relaySecretStored {
                    HStack {
                        Image(systemName: "key.fill").foregroundStyle(Palette.green)
                        Text("Secret stored in Keychain")
                        Spacer()
                        Button("Replace") { relaySecretStored = false; relaySecret = "" }
                    }
                } else {
                    SecureField("Shared secret", text: $relaySecret)
                    Button("Save secret") {
                        do {
                            try env.remote.saveRelaySecret(relaySecret)
                            relaySecretStored = true
                            relaySecret = ""
                        } catch {
                            self.error = "\(error)"
                        }
                    }
                    .disabled(relaySecret.isEmpty)
                }
                Text("Ask your relay operator for the URL and secret. The Mac signs each push with HMAC-SHA256(secret, timestamp + body).")
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
        }
    }

    private var directSection: some View {
        Group {
            Section("Apple Developer credentials") {
                TextField("Team ID", text: $apnsTeamId)
                TextField("Key ID", text: $apnsKeyId)
                TextField("iOS bundle id", text: $apnsBundleId)
                Picker("Environment", selection: $apnsEnvironment) {
                    Text("Production").tag(ApnsConfig.Environment.production)
                    Text("Sandbox").tag(ApnsConfig.Environment.sandbox)
                }
                Toggle("Send pushes directly", isOn: $apnsEnabled)
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
        }
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
        env.remote.pushBackend = pushBackend
        var direct = env.remote.apnsConfig
        direct.teamId = apnsTeamId
        direct.keyId = apnsKeyId
        direct.bundleId = apnsBundleId
        direct.environment = apnsEnvironment
        direct.enabled = apnsEnabled
        env.remote.saveApnsConfig(direct)

        var relay = env.remote.relayConfig
        relay.url = relayURL
        relay.enabled = relayEnabled
        env.remote.saveRelayConfig(relay)
    }

    private func reloadApns() {
        let direct = env.remote.apnsConfig
        apnsTeamId = direct.teamId
        apnsKeyId = direct.keyId
        apnsBundleId = direct.bundleId
        apnsEnvironment = direct.environment
        apnsEnabled = direct.enabled
        apnsKeyLoaded = env.remote.hasApnsKey()
        let relay = env.remote.relayConfig
        relayURL = relay.url
        relayEnabled = relay.enabled
        relaySecretStored = env.remote.hasRelaySecret()
        pushBackend = env.remote.pushBackend
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
