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
    @State private var loading = false
    @State private var error: String?
    @State private var selection: String?

    enum Scope: String, CaseIterable, Identifiable {
        case project, session, global, all
        var id: Self { self }
        var label: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            if let error {
                ContentUnavailableView(
                    "Memory error", systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    list
                    detail
                }
            }
        }
        .task(id: refreshKey) { await load() }
    }

    private var refreshKey: String {
        "\(project?.id ?? "")|\(session?.id ?? "")|\(scope.rawValue)|\(query)"
    }

    private var controls: some View {
        HStack(spacing: 8) {
            TextField("Search memory…", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await load() } }
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { s in
                    Text(s.label).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            Button {
                Task { await load() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
        }
        .padding(12)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.namespace).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.updatedAt.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.key ?? entry.content.prefix(80).description)
                        .lineLimit(2)
                }
                .tag(entry.id)
            }
            .onDelete { indices in
                Task { await delete(indices) }
            }
        }
        .frame(minWidth: 320)
    }

    private var detail: some View {
        Group {
            if let id = selection, let entry = entries.first(where: { $0.id == id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let key = entry.key {
                            Text(key).font(.headline)
                        }
                        Text("Namespace: \(entry.namespace)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(entry.content)
                            .textSelection(.enabled)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !entry.tagsArray.isEmpty {
                            HStack {
                                ForEach(entry.tagsArray, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.regularMaterial, in: Capsule())
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView(
                    "No entry selected",
                    systemImage: "brain",
                    description: Text("Select an entry to view its content.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        await MainActor.run { loading = true; error = nil }
        do {
            let namespaces = scopesToNamespaces()
            let q = query
            let memory = env.memory
            let collected = try await withThrowingTaskGroup(of: [MemoryEntry].self) { group in
                for ns in namespaces {
                    group.addTask {
                        if q.isEmpty {
                            return try await memory.list(namespace: ns, limit: 100)
                        } else {
                            return try await memory.search(q, namespace: ns, limit: 50)
                        }
                    }
                }
                var out: [MemoryEntry] = []
                for try await chunk in group { out.append(contentsOf: chunk) }
                return out
            }
            await MainActor.run {
                entries = collected.sorted { $0.updatedAt > $1.updatedAt }
                loading = false
            }
        } catch {
            await MainActor.run {
                self.error = "\(error)"
                loading = false
            }
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
        for idx in indices {
            let id = entries[idx].id
            try? await env.memory.delete(id: id)
        }
        await load()
    }
}
