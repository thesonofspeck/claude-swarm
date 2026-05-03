import SwiftUI
import AppCore
import PersistenceKit

struct CommandPalette: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ProjectListViewModel.self) private var projectList
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedSession: Session?

    @State private var query = ""
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider().background(Palette.divider)
            results
        }
        .frame(width: 640, height: 420)
        .background(Palette.bgSidebar)
        .onAppear { queryFocused = true }
    }

    private var field: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.fgMuted)
                .imageScale(.medium)
            TextField("Jump to project, session, task, or memory…", text: $query)
                .textFieldStyle(.plain)
                .font(Type.title)
                .focused($queryFocused)
                .onSubmit { activateFirst() }
            Text("ESC")
                .font(Type.label)
                .foregroundStyle(Palette.fgMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Palette.pillBg))
        }
        .padding(Metrics.Space.lg)
    }

    private var results: some View {
        let items = matches()
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if items.isEmpty {
                    Text(query.isEmpty ? "Type to search across projects, sessions, and tasks." : "No matches.")
                        .font(Type.body)
                        .foregroundStyle(Palette.fgMuted)
                        .padding(Metrics.Space.lg)
                } else {
                    ForEach(items) { item in
                        Button {
                            activate(item)
                        } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, Metrics.Space.sm)
        }
    }

    private func row(_ item: PaletteItem) -> some View {
        HStack(spacing: Metrics.Space.md) {
            Image(systemName: item.icon)
                .foregroundStyle(item.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Type.body)
                    .foregroundStyle(Palette.fgBright)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Pill(text: item.kindLabel, tint: item.tint)
        }
        .padding(.horizontal, Metrics.Space.lg)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func matches() -> [PaletteItem] {
        var out: [PaletteItem] = []
        let q = query.lowercased()
        for project in projectList.projects {
            if q.isEmpty || project.name.lowercased().contains(q) {
                out.append(PaletteItem(
                    id: "project-\(project.id)",
                    kind: .project(project.id),
                    icon: "folder",
                    tint: Palette.cyan,
                    title: project.name,
                    subtitle: project.localPath,
                    kindLabel: "PROJECT"
                ))
            }
            for session in projectList.sessions(for: project.id) {
                let title = session.taskTitle ?? session.branch
                if q.isEmpty || title.lowercased().contains(q) || session.branch.lowercased().contains(q) {
                    out.append(PaletteItem(
                        id: "session-\(session.id)",
                        kind: .session(session),
                        icon: "play.circle",
                        tint: Palette.green,
                        title: title,
                        subtitle: "\(project.name) · \(session.branch)",
                        kindLabel: "SESSION"
                    ))
                }
            }
        }
        return Array(out.prefix(50))
    }

    private func activateFirst() {
        if let first = matches().first {
            activate(first)
        }
    }

    private func activate(_ item: PaletteItem) {
        switch item.kind {
        case .session(let s):
            selectedSession = s
        case .project:
            break
        }
        dismiss()
    }
}

struct PaletteItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case project(String)
        case session(Session)
    }
    let id: String
    let kind: Kind
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?
    let kindLabel: String

    static func == (lhs: PaletteItem, rhs: PaletteItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
