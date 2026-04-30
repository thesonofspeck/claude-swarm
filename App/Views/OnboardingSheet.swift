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

    enum Step: Int, CaseIterable { case welcome, wrike, github, done }

    var body: some View {
        ZStack {
            backgroundGradient
            VStack(spacing: 0) {
                stepContent
                    .padding(Metrics.Space.xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                stepDots
                    .padding(.bottom, Metrics.Space.lg)
            }
        }
        .frame(width: 600, height: 460)
        .task { await checkGh() }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Palette.bgBase, Palette.bgSidebar, Palette.bgDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Palette.blue.opacity(0.08))
                .frame(width: 380, height: 380)
                .blur(radius: 80)
                .offset(x: 80, y: -120)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Palette.purple.opacity(0.06))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: -80, y: 80)
        }
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                Capsule()
                    .fill(s == step ? Palette.blue : Palette.fgMuted.opacity(0.4))
                    .frame(width: s == step ? 24 : 6, height: 6)
                    .animation(Motion.spring, value: step)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome: welcome
        case .wrike: wrike
        case .github: github
        case .done: done
        }
    }

    private var welcome: some View {
        VStack(spacing: Metrics.Space.lg) {
            ZStack {
                Circle().fill(Palette.blue.opacity(0.12)).frame(width: 110, height: 110)
                Circle().strokeBorder(Palette.blue.opacity(0.25), lineWidth: 1).frame(width: 138, height: 138)
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Palette.blue)
            }
            VStack(spacing: 6) {
                Text("Welcome to Claude Swarm")
                    .font(Type.display)
                    .foregroundStyle(Palette.fgBright)
                Text("A home for every Claude Code session you run.")
                    .font(Type.body)
                    .foregroundStyle(Palette.fgMuted)
            }
            Spacer()
            Button {
                withAnimation(Motion.spring) { step = .wrike }
            } label: {
                Label("Get started", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: 240)
        }
    }

    private var wrike: some View {
        stepLayout(
            icon: "checklist",
            title: "Connect Wrike",
            subtitle: "We pull tasks from Wrike folders you map to your projects. You can do this later in Settings."
        ) {
            SecureField("Wrike Personal Access Token (optional)", text: $wrikeToken)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 380)
        } actions: {
            Button("Skip") {
                withAnimation(Motion.spring) { step = .github }
            }
            Spacer()
            Button {
                if !wrikeToken.isEmpty {
                    try? env.keychain.set(wrikeToken, account: KeychainAccount.wrike)
                }
                withAnimation(Motion.spring) { step = .github }
            } label: {
                Label("Continue", systemImage: "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var github: some View {
        stepLayout(
            icon: "arrow.triangle.pull",
            title: "Connect GitHub",
            subtitle: "All GitHub operations go through the gh CLI, so we inherit your auth and host config."
        ) {
            Card {
                HStack(spacing: Metrics.Space.sm) {
                    Image(systemName: ghAuthenticated ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .foregroundStyle(ghAuthenticated ? Palette.green : Palette.orange)
                        .imageScale(.large)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ghAuthenticated ? "Authenticated" : "Not authenticated")
                            .font(Type.heading)
                            .foregroundStyle(Palette.fgBright)
                        Text(ghLine)
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Recheck") { Task { await checkGh() } }
                }
            }
            if !ghAuthenticated {
                Text("Run `gh auth login` in a terminal, then click Recheck.")
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
            }
        } actions: {
            Button("Back") {
                withAnimation(Motion.spring) { step = .wrike }
            }
            Spacer()
            Button {
                withAnimation(Motion.spring) { step = .done }
            } label: {
                Label("Continue", systemImage: "arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    private var done: some View {
        VStack(spacing: Metrics.Space.lg) {
            ZStack {
                Circle().fill(Palette.green.opacity(0.15)).frame(width: 110, height: 110)
                Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Palette.green)
            }
            VStack(spacing: 6) {
                Text("You're all set")
                    .font(Type.display)
                    .foregroundStyle(Palette.fgBright)
                Text("Add your first project to start spinning up sessions.")
                    .font(Type.body)
                    .foregroundStyle(Palette.fgMuted)
            }
            Spacer()
            Button {
                env.settings.hasCompletedOnboarding = true
                env.saveSettings()
                dismiss()
            } label: {
                Label("Finish", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: 240)
        }
    }

    @ViewBuilder
    private func stepLayout<Body: View, Actions: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder body: () -> Body,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Space.lg) {
            HStack(spacing: Metrics.Space.md) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Palette.blue)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Palette.blue.opacity(0.10)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Type.title).foregroundStyle(Palette.fgBright)
                    Text(subtitle).font(Type.body).foregroundStyle(Palette.fgMuted)
                }
                Spacer()
            }
            body()
            Spacer()
            HStack { actions() }
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
