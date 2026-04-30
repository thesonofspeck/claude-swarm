import SwiftUI
import AppCore
import KeychainKit
import WrikeKit

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
        }
        .padding()
        .frame(width: 540, height: 420)
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
                        panel.allowedContentTypes = []
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
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
    }

    private var wrikeTab: some View {
        Form {
            Section("Personal Access Token") {
                if wrikeStored {
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                        Text("Token stored in Keychain")
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
                    .disabled(wrikeToken.isEmpty)
                }
            }
            Section("Help") {
                Link("Generate a Wrike PAT", destination: URL(string: "https://help.wrike.com/hc/en-us/articles/210409445")!)
            }
        }
        .formStyle(.grouped)
    }

    private var githubTab: some View {
        Form {
            Section("gh CLI") {
                HStack {
                    Image(systemName: ghAuthenticated ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .foregroundStyle(ghAuthenticated ? .green : .orange)
                    Text(ghAuthenticated ? "Authenticated" : "Not authenticated")
                    Spacer()
                    Button("Recheck") { Task { await refresh() } }
                }
                Text(ghAuthLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            Section("Help") {
                Text("This app uses the GitHub CLI for all GitHub operations. To authenticate, run `gh auth login` in a terminal — the app picks up your existing session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
