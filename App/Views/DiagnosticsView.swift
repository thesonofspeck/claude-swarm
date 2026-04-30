import SwiftUI
import AppCore
import AgentBootstrap
import KeychainKit
import ToolDetector
import PersistenceKit

struct DiagnosticsView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var checks: [Check] = []
    @State private var running = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: "stethoscope").foregroundStyle(Palette.cyan).imageScale(.large)
                Text("Diagnostics")
                    .font(Type.heading)
                    .foregroundStyle(Palette.fgBright)
                Spacer()
                Button {
                    Task { await runChecks() }
                } label: {
                    if running {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Re-check", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(running)
            }
            .padding(Metrics.Space.md)

            Divider().background(Palette.divider)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(checks) { check in
                        row(check)
                        Divider().background(Palette.divider)
                    }
                }
            }
        }
        .background(Palette.bgSidebar)
        .task { await runChecks() }
    }

    private func row(_ check: Check) -> some View {
        HStack(alignment: .top, spacing: Metrics.Space.md) {
            statusIcon(check.status)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title).font(Type.body).foregroundStyle(Palette.fgBright)
                Text(check.detail).font(Type.caption).foregroundStyle(Palette.fgMuted)
            }
            Spacer()
            Pill(text: check.status.label, tint: check.status.color)
        }
        .padding(.horizontal, Metrics.Space.md)
        .padding(.vertical, Metrics.Space.sm)
    }

    @ViewBuilder
    private func statusIcon(_ status: CheckStatus) -> some View {
        Image(systemName: status.icon).foregroundStyle(status.color).imageScale(.medium)
    }

    private func runChecks() async {
        await MainActor.run { running = true }
        var results: [Check] = []
        results.append(contentsOf: await toolChecks())
        results.append(await ghAuthCheck())
        results.append(await wrikeTokenCheck())
        results.append(await pushBackendCheck())
        results.append(await hookSocketCheck())
        results.append(await sleepGuardCheck())
        results.append(await pairedDevicesCheck())
        results.append(await projectsCheck())
        await MainActor.run {
            checks = results
            running = false
        }
    }

    private func toolChecks() async -> [Check] {
        let detector = ToolDetector()
        let statuses = await detector.detectAll(overrides: [
            "claude": env.settings.claudeExecutable,
            "gh": env.settings.ghExecutable,
            "git": env.settings.gitExecutable,
            "python3": env.settings.pythonExecutable
        ].compactMapValues { $0.isEmpty ? nil : $0 })
        return statuses.map { s in
            Check(
                title: s.tool.displayName,
                detail: s.resolvedPath ?? (s.error ?? "Not found"),
                status: s.isFound ? .ok : (s.tool.required ? .warn : .info)
            )
        }
    }

    private func ghAuthCheck() async -> Check {
        let s = await env.github.authStatus()
        return Check(
            title: "gh auth",
            detail: s.user.map { "Logged in as \($0)" } ?? s.raw,
            status: s.authenticated ? .ok : .warn
        )
    }

    private func wrikeTokenCheck() async -> Check {
        let stored = (try? env.keychain.get(account: KeychainAccount.wrike)) != nil
        return Check(
            title: "Wrike token",
            detail: stored ? "Stored in Keychain" : "No token configured",
            status: stored ? .ok : .info
        )
    }

    private func pushBackendCheck() async -> Check {
        let backend = env.remote.pushBackend
        switch backend {
        case .relay:
            let cfg = env.remote.relayConfig
            let secret = env.remote.hasRelaySecret()
            if cfg.url.isEmpty {
                return Check(title: "Push relay", detail: "URL not set", status: .warn)
            }
            if !secret {
                return Check(title: "Push relay", detail: "Shared secret not stored", status: .warn)
            }
            return Check(title: "Push relay", detail: cfg.url, status: cfg.enabled ? .ok : .info)
        case .direct:
            let cfg = env.remote.apnsConfig
            let key = env.remote.hasApnsKey()
            if !cfg.isComplete || !key {
                return Check(title: "APNs (direct)", detail: "Team / Key / Bundle / .p8 incomplete", status: .warn)
            }
            return Check(title: "APNs (direct)", detail: "\(cfg.teamId) / \(cfg.keyId) / \(cfg.environment.rawValue)", status: cfg.enabled ? .ok : .info)
        }
    }

    private func hookSocketCheck() async -> Check {
        let path = AppDirectories.hooksSocket.path
        let exists = FileManager.default.fileExists(atPath: path)
        return Check(
            title: "Hook socket",
            detail: exists ? path : "Not bound (\(path))",
            status: exists ? .ok : .warn
        )
    }

    private func sleepGuardCheck() async -> Check {
        let held = env.remote.sleepGuardHeld
        let paired = env.remote.pairedDevices.count
        return Check(
            title: "Sleep guard",
            detail: held ? "Held — Mac stays awake" : (paired == 0 ? "No paired devices" : "Released (battery / off-hours)"),
            status: held ? .ok : (paired == 0 ? .info : .info)
        )
    }

    private func pairedDevicesCheck() async -> Check {
        let count = env.remote.pairedDevices.count
        let live = env.remote.liveDeviceIds.count
        return Check(
            title: "Paired iPhones",
            detail: "\(count) total, \(live) online",
            status: count > 0 ? .ok : .info
        )
    }

    private func projectsCheck() async -> Check {
        let count = (try? env.projects.all().count) ?? 0
        return Check(
            title: "Projects",
            detail: "\(count) registered",
            status: count > 0 ? .ok : .info
        )
    }
}

struct Check: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
    let status: CheckStatus
}

enum CheckStatus {
    case ok, warn, error, info

    var icon: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .info: return "info.circle"
        }
    }
    var color: Color {
        switch self {
        case .ok: return Palette.green
        case .warn: return Palette.orange
        case .error: return Palette.red
        case .info: return Palette.fgMuted
        }
    }
    var label: String {
        switch self {
        case .ok: return "OK"
        case .warn: return "WARN"
        case .error: return "ERROR"
        case .info: return "INFO"
        }
    }
}
