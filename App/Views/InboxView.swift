import SwiftUI
import AppCore
import PersistenceKit

/// Daily-pulse feed: hook events, PR review comments, CI failures, anything
/// that needs the user's attention. Click an item to jump to the matching
/// session or open the PR in the browser.
struct InboxView: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var feed: InboxFeed
    @Binding var selectedSession: Session?
    @State private var enabledKinds: Set<InboxFeed.Kind> = Set(InboxFeed.Kind.allCases)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            if feed.items.isEmpty {
                EmptyState(
                    title: "Inbox is clear",
                    systemImage: "tray",
                    description: "Pings, review comments, and CI failures land here. Run a session and you'll see hook events; open PRs and you'll see review threads.",
                    tint: Palette.green
                )
            } else {
                List {
                    ForEach(feed.filtered(enabledKinds)) { item in
                        row(item)
                            .listRowBackground(Palette.bgBase)
                            .listRowSeparatorTint(Palette.divider)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Palette.bgBase)
            }
        }
        .background(Palette.bgBase)
        .task {
            feed.hydrate()
            await feed.refreshIfStale()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.sm) {
            HStack {
                Image(systemName: "tray.full")
                    .foregroundStyle(Palette.cyan)
                Text("Inbox")
                    .font(Type.title)
                    .foregroundStyle(Palette.fgBright)
                if feed.refreshing {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if let last = feed.lastRefreshedAt {
                    Text("Updated \(last.formatted(.relative(presentation: .named)))")
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                }
                IconButton(systemImage: "arrow.clockwise", help: "Refresh") {
                    Task { await feed.refreshAll() }
                }
            }
            HStack(spacing: 6) {
                ForEach(InboxFeed.Kind.allCases, id: \.self) { kind in
                    Button {
                        if enabledKinds.contains(kind) {
                            enabledKinds.remove(kind)
                        } else {
                            enabledKinds.insert(kind)
                        }
                    } label: {
                        Pill(
                            text: kind.label,
                            tint: enabledKinds.contains(kind) ? tint(for: kind) : Palette.fgMuted
                        )
                        .opacity(enabledKinds.contains(kind) ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private func row(_ item: InboxFeed.Item) -> some View {
        Button {
            handleClick(item)
        } label: {
            HStack(alignment: .top, spacing: Metrics.Space.md) {
                Image(systemName: icon(for: item.kind))
                    .foregroundStyle(tint(for: item.kind))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.title)
                            .font(Type.body)
                            .foregroundStyle(Palette.fgBright)
                        if item.unread {
                            Circle().fill(Palette.yellow).frame(width: 6, height: 6)
                        }
                    }
                    if let detail = item.detail, !detail.isEmpty {
                        Text(detail)
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Pill(text: item.kind.label, tint: tint(for: item.kind))
                        Text(item.timestamp.formatted(.relative(presentation: .named)))
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private func tint(for kind: InboxFeed.Kind) -> Color {
        switch kind {
        case .needsInput: return Palette.yellow
        case .stop: return Palette.fgMuted
        case .postToolUse: return Palette.cyan
        case .prReviewComment: return Palette.purple
        case .ciFailure: return Palette.red
        case .other: return Palette.fgMuted
        }
    }

    private func icon(for kind: InboxFeed.Kind) -> String {
        switch kind {
        case .needsInput: return "exclamationmark.bubble"
        case .stop: return "pause.circle"
        case .postToolUse: return "wrench.and.screwdriver"
        case .prReviewComment: return "bubble.left.and.bubble.right"
        case .ciFailure: return "xmark.octagon"
        case .other: return "circle"
        }
    }

    private func handleClick(_ item: InboxFeed.Item) {
        if let sessionId = item.sessionId,
           let session = try? env.sessionsRepo.find(id: sessionId) {
            selectedSession = session
            return
        }
        if let url = item.prURL.flatMap(URL.init(string:)) {
            NSWorkspace.shared.open(url)
        }
    }
}
