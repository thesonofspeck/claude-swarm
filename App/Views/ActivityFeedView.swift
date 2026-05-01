import SwiftUI
import AppCore
import PersistenceKit

struct ActivityFeedView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var events: [ActivityEvent] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: "bolt.heart").foregroundStyle(Palette.cyan).imageScale(.large)
                Text("Activity").font(Type.heading).foregroundStyle(Palette.fgBright)
                Spacer()
                Button {
                    Task { await load() }
                } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
            }
            .padding(Metrics.Space.md)
            Divider().background(Palette.divider)

            if events.isEmpty {
                EmptyState(
                    title: "No activity yet",
                    systemImage: "bolt.heart",
                    description: "Hook events from your sessions show up here as they happen.",
                    tint: Palette.fgMuted
                )
            } else {
                List {
                    ForEach(grouped, id: \.key) { (day, items) in
                        Section(day) {
                            ForEach(items) { event in
                                row(event)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Palette.bgBase)
            }
        }
        .background(Palette.bgSidebar)
        .task { await load() }
    }

    private var grouped: [(key: String, value: [ActivityEvent])] {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let groups = Dictionary(grouping: events) { formatter.string(from: $0.timestamp) }
        return groups.sorted { $0.value.first?.timestamp ?? Date.distantPast > $1.value.first?.timestamp ?? Date.distantPast }
            .map { (key: $0.key, value: $0.value) }
    }

    private func row(_ event: ActivityEvent) -> some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: icon(event)).foregroundStyle(tint(event))
            VStack(alignment: .leading, spacing: 2) {
                Text(label(for: event)).font(Type.body)
                if let msg = event.message, !msg.isEmpty {
                    Text(msg.prefix(160).description)
                        .font(Type.caption).foregroundStyle(Palette.fgMuted).lineLimit(2)
                }
                if let sessionId = event.sessionId {
                    Text("session: \(sessionId.prefix(8))")
                        .font(Type.monoCaption).foregroundStyle(Palette.fgMuted)
                }
            }
            Spacer()
            Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                .font(Type.monoCaption).foregroundStyle(Palette.fgMuted)
        }
        .padding(.vertical, 4)
    }

    private func icon(_ event: ActivityEvent) -> String {
        switch event.kind {
        case "Notification": return "bell.fill"
        case "Stop": return "pause.circle"
        case "SessionStart": return "play.circle"
        default: return "circle.dotted"
        }
    }

    private func tint(_ event: ActivityEvent) -> Color {
        switch event.kind {
        case "Notification": return Palette.yellow
        case "Stop": return Palette.fgMuted
        case "SessionStart": return Palette.green
        default: return Palette.fgMuted
        }
    }

    private func label(for event: ActivityEvent) -> String {
        switch event.kind {
        case "Notification": return "Needs input"
        case "Stop": return "Idle"
        case "SessionStart": return "Started"
        default: return event.kind
        }
    }

    private func load() async {
        let result = (try? await env.activity.recent(limit: 200)) ?? []
        await MainActor.run { events = result }
    }
}
