import SwiftUI
import AppCore
import PersistenceKit
import MemoryService

struct MemoryTab: View {
    @EnvironmentObject var env: AppEnvironment
    let project: Project?
    let session: Session?

    @State private var entries: [MemoryEntry] = []
    @State private var query = ""
    @State private var scope: Scope = .project
    @State private var ops = AsyncTracker()
    @State private var selection: String?

    enum Scope: String, CaseIterable, Identifiable {
        case project, session, global, all
        var id: Self { self }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider().background(Palette.divider)
            if let error = ops.error {
                EmptyState(
                    title: "Memory error",
                    systemImage: "exclamationmark.triangle",
                    description: error,
                    tint: Palette.red
                )
            } else if ops.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                EmptyState(
                    title: "No memory yet",
                    systemImage: "brain",
                    description: "Agents persist key decisions here. Run a session and check back.",
                    tint: Palette.purple
                )
            } else {
                HSplitView {
                    list
                    detail
                }
            }
        }
        .background(Palette.bgBase)
        .task(id: refreshKey) { await load() }
    }

    private var refreshKey: String {
        "\(project?.id ?? "")|\(session?.id ?? "")|\(scope.rawValue)|\(query)"
    }

    private var controls: some View {
        HStack(spacing: Metrics.Space.sm) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.fgMuted)
                TextField("Search memory…", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await load() } }
            }
            .padding(.horizontal, Metrics.Space.sm)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .fill(Palette.bgRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .stroke(Palette.divider, lineWidth: Metrics.Stroke.hairline)
            )
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            IconButton(systemImage: "arrow.clockwise", help: "Refresh") {
                Task { await load() }
            }
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Pill(text: entry.namespace, tint: namespaceTint(entry.namespace))
                        Spacer()
                        Text(entry.updatedAt.formatted(.relative(presentation: .named)))
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                    }
                    Text(entry.key ?? entry.content.prefix(80).description)
                        .font(Type.body)
                        .foregroundStyle(Palette.fg)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
                .tag(entry.id)
            }
            .onDelete { indices in
                Task { await delete(indices) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bgBase)
        .frame(minWidth: 340)
    }

    private func namespaceTint(_ ns: String) -> Color {
        if ns == "global" { return Palette.cyan }
        if ns.hasPrefix("session:") { return Palette.purple }
        return Palette.green
    }

    private var detail: some View {
        Group {
            if let id = selection, let entry = entries.first(where: { $0.id == id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.Space.md) {
                        if let key = entry.key {
                            Text(key)
                                .font(Type.heading)
                                .foregroundStyle(Palette.fgBright)
                        }
                        Pill(text: entry.namespace, systemImage: "tray", tint: namespaceTint(entry.namespace))
                        Card {
                            Text(entry.content)
                                .textSelection(.enabled)
                                .font(Type.mono)
                                .foregroundStyle(Palette.fg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !entry.tagsArray.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(entry.tagsArray, id: \.self) { tag in
                                    Pill(text: tag, tint: Palette.fgMuted)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(Metrics.Space.lg)
                }
                .background(Palette.bgBase)
            } else {
                EmptyState(
                    title: "No entry selected",
                    systemImage: "brain",
                    description: "Select an entry on the left to view its content.",
                    tint: Palette.purple
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        let namespaces = scopesToNamespaces()
        let q = query
        let scopedProject = project
        let collected = await ops.run {
            let store = try env.memoryStore(for: scopedProject)
            return try await withThrowingTaskGroup(of: [MemoryEntry].self) { group in
                for ns in namespaces {
                    group.addTask {
                        q.isEmpty
                            ? try await store.list(namespace: ns, limit: 100)
                            : try await store.search(q, namespace: ns, limit: 50)
                    }
                }
                var out: [MemoryEntry] = []
                for try await chunk in group { out.append(contentsOf: chunk) }
                return out
            }
        }
        if let collected {
            entries = collected.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    private func scopesToNamespaces() -> [MemoryNamespace?] {
        switch scope {
        case .global: return [.global]
        case .project: return [project.map { .project($0.id) } ?? nil]
        case .session: return [session.map { .session($0.id) } ?? nil]
        case .all:
            return [
                .global,
                project.map { .project($0.id) } ?? nil,
                session.map { .session($0.id) } ?? nil
            ]
        }
    }

    private func delete(_ indices: IndexSet) async {
        guard let store = try? env.memoryStore(for: project) else { return }
        for idx in indices {
            let id = entries[idx].id
            try? await store.delete(id: id)
        }
        await load()
    }
}
