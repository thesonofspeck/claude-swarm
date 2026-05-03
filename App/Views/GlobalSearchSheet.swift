import SwiftUI
import AppCore
import PersistenceKit

/// ⌘⇧F search across transcripts, memory, and code in every registered
/// project. Type-to-search; results stream in by source. Click a result
/// to either jump to its session (transcript hits) or open the file in
/// Finder (memory + code hits).
struct GlobalSearchSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedSession: Session?

    @State private var query: String = ""
    @State private var results: SearchService.Results = .init()
    @State private var enabled: Set<SearchService.Source> = Set(SearchService.Source.allCases)
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Palette.divider)
            list
            Divider().background(Palette.divider)
            footer
        }
        .frame(minWidth: 720, minHeight: 540)
        .background(Palette.bgBase)
    }

    private var header: some View {
        VStack(spacing: Metrics.Space.sm) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.fgMuted)
                TextField("Search transcripts, memory, code…", text: $query)
                    .textFieldStyle(.plain)
                    .font(Type.body)
                    .onSubmit { triggerSearch() }
                if searching {
                    ProgressView().controlSize(.small)
                }
                if !query.isEmpty {
                    Button { query = ""; results = .init() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.fgMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Metrics.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .fill(Palette.bgRaised)
            )

            HStack(spacing: 6) {
                ForEach(SearchService.Source.allCases, id: \.self) { source in
                    Button {
                        if enabled.contains(source) {
                            enabled.remove(source)
                        } else {
                            enabled.insert(source)
                        }
                        triggerSearch()
                    } label: {
                        Pill(
                            text: source.label,
                            tint: enabled.contains(source) ? tint(for: source) : Palette.fgMuted
                        )
                        .opacity(enabled.contains(source) ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if results.truncated {
                    Text("Showing first 50 per source")
                        .font(Type.caption)
                        .foregroundStyle(Palette.orange)
                }
            }
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
        .onChange(of: query) { _, _ in triggerSearch() }
    }

    private var list: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                EmptyState(
                    title: "Search anything",
                    systemImage: "magnifyingglass",
                    description: "Find a phrase across every transcript, memory entry, and registered code repo. ⌘⇧F.",
                    tint: Palette.cyan
                )
            } else if results.all.isEmpty && !searching {
                EmptyState(
                    title: "No matches",
                    systemImage: "tray",
                    description: "Try a shorter or fuzzier phrase, or toggle a source on.",
                    tint: Palette.fgMuted
                )
            } else {
                List {
                    if !results.transcripts.isEmpty {
                        Section("Transcripts (\(results.transcripts.count))") {
                            ForEach(results.transcripts) { hit in row(hit) }
                        }
                    }
                    if !results.memory.isEmpty {
                        Section("Memory (\(results.memory.count))") {
                            ForEach(results.memory) { hit in row(hit) }
                        }
                    }
                    if !results.code.isEmpty {
                        Section("Code (\(results.code.count))") {
                            ForEach(results.code) { hit in row(hit) }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Palette.bgBase)
            }
        }
    }

    private func row(_ hit: SearchService.Hit) -> some View {
        Button {
            handleClick(hit)
        } label: {
            HStack(alignment: .top, spacing: Metrics.Space.md) {
                Image(systemName: icon(for: hit.source))
                    .foregroundStyle(tint(for: hit.source))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(hit.title)
                            .font(Type.body)
                            .foregroundStyle(Palette.fgBright)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let line = hit.line {
                            Text(":\(line)")
                                .font(Type.monoCaption)
                                .foregroundStyle(Palette.fgMuted)
                        }
                    }
                    Text(hit.snippet)
                        .font(Type.mono)
                        .foregroundStyle(Palette.fg)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .keyboardShortcut(.defaultAction)
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private func tint(for source: SearchService.Source) -> Color {
        switch source {
        case .transcripts: return Palette.cyan
        case .memory: return Palette.purple
        case .code: return Palette.green
        }
    }

    private func icon(for source: SearchService.Source) -> String {
        switch source {
        case .transcripts: return "text.alignleft"
        case .memory: return "brain"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    private func handleClick(_ hit: SearchService.Hit) {
        if hit.source == .transcripts,
           let id = hit.sessionId,
           let session = try? env.sessionsRepo.find(id: id) {
            selectedSession = session
            dismiss()
            return
        }
        let url = URL(fileURLWithPath: hit.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func triggerSearch() {
        searchTask?.cancel()
        let q = query
        let sources = enabled
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = .init()
            searching = false
            return
        }
        searching = true
        searchTask = Task { @MainActor in
            // Lightweight debounce so per-keystroke results don't queue
            // up multiple subprocess fan-outs.
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }
            let projects = (try? env.projects.all()) ?? []
            let sessions = (try? env.sessionsRepo.allByProject().values.flatMap { $0 }) ?? []
            let r = await env.search.search(
                query: q,
                sources: sources,
                projects: projects,
                sessions: sessions
            )
            if Task.isCancelled { return }
            results = r
            searching = false
        }
    }
}
