import SwiftUI
import AppCore
import KeychainKit

struct OnboardingSheet: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .welcome
    @State private var wrikeToken = ""
    @State private var ghAuthenticated = false
    @State private var ghLine = "Checking…"

    enum Step { case welcome, wrike, github, done }

    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case .welcome: welcome
            case .wrike: wrike
            case .github: github
            case .done: done
            }
        }
        .padding(32)
        .frame(width: 560, height: 420)
        .task { await checkGh() }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 56))
                .foregroundStyle(.accent)
            Text("Welcome to Claude Swarm").font(.largeTitle.weight(.semibold))
            Text("A home for every Claude Code session you run.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Get started") { step = .wrike }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private var wrike: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connect Wrike", systemImage: "checklist")
                .font(.title2.weight(.semibold))
            Text("We pull tasks from Wrike folders you map to your projects. You can do this later in Settings.")
                .foregroundStyle(.secondary)
            SecureField("Wrike Personal Access Token (optional)", text: $wrikeToken)
            Spacer()
            HStack {
                Button("Skip") { step = .github }
                Spacer()
                Button("Save and continue") {
                    if !wrikeToken.isEmpty {
                        try? env.keychain.set(wrikeToken, account: KeychainAccount.wrike)
                    }
                    step = .github
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var github: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Connect GitHub", systemImage: "arrow.triangle.pull")
                .font(.title2.weight(.semibold))
            Text("All GitHub operations go through the gh CLI, so we inherit your auth and host config.")
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: ghAuthenticated ? "checkmark.shield.fill" : "exclamationmark.shield")
                    .foregroundStyle(ghAuthenticated ? .green : .orange)
                Text(ghAuthenticated ? "Authenticated" : "Not authenticated yet")
                Spacer()
                Button("Recheck") { Task { await checkGh() } }
            }
            Text(ghLine).font(.caption).foregroundStyle(.secondary)
            if !ghAuthenticated {
                Text("Run `gh auth login` in a terminal, then click Recheck.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack {
                Button("Back") { step = .wrike }
                Spacer()
                Button("Continue") { step = .done }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("You're all set").font(.largeTitle.weight(.semibold))
            Text("Add your first project to start spinning up sessions.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Finish") {
                env.settings.hasCompletedOnboarding = true
                env.saveSettings()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func checkGh() async {
        let s = await env.github.authStatus()
        await MainActor.run {
            ghAuthenticated = s.authenticated
            ghLine = s.user.map { "Logged in as \($0)" } ?? s.raw
        }
    }
}
