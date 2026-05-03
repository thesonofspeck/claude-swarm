import SwiftUI
import AppCore
import PersistenceKit

struct ClaudeMdTab: View {
    @EnvironmentObject var env: AppEnvironment
    let project: Project?

    @State private var content: String = ""
    @State private var dirty: Bool = false
    @State private var error: String?
    @State private var savedToast: Bool = false

    var body: some View {
        if let project {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider().background(Palette.divider)
                editor
                Divider().background(Palette.divider)
                snippetBar
            }
            .background(Palette.bgBase)
            .task(id: project.id) { load(project: project) }
        } else {
            EmptyState(
                title: "No project selected",
                systemImage: "doc.text",
                description: "Pick a project to edit its CLAUDE.md.",
                tint: Palette.fgMuted
            )
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "doc.text").foregroundStyle(Palette.yellow).imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text("CLAUDE.md").font(Type.heading).foregroundStyle(Palette.fgBright)
                Text("Project memory loaded into every session in this repo.")
                    .font(Type.caption).foregroundStyle(Palette.fgMuted)
            }
            if dirty { Circle().fill(Palette.orange).frame(width: 6, height: 6) }
            Spacer()
            if savedToast {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(Type.caption)
                    .foregroundStyle(Palette.green)
                    .transition(.opacity.combined(with: .scale))
            }
            Button("Save") {
                if let project { save(project: project) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!dirty)
        }
        .padding(Metrics.Space.md)
    }

    private var editor: some View {
        TextEditor(text: $content)
            .font(Type.mono)
            .scrollContentBackground(.hidden)
            .background(Palette.bgBase)
            .padding(Metrics.Space.md)
            .onChange(of: content) { _, _ in dirty = true }
    }

    private var snippetBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ClaudeMdSnippet.all, id: \.title) { snippet in
                    Button {
                        insert(snippet)
                    } label: {
                        Label(snippet.title, systemImage: snippet.icon)
                            .font(Type.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(Metrics.Space.sm)
        }
        .background(Palette.bgSidebar)
    }

    private func insert(_ snippet: ClaudeMdSnippet) {
        if !content.hasSuffix("\n") { content.append("\n") }
        content.append(snippet.body)
        if !snippet.body.hasSuffix("\n") { content.append("\n") }
        dirty = true
    }

    private func mdURL(in project: Project) -> URL {
        URL(fileURLWithPath: project.localPath).appendingPathComponent("CLAUDE.md")
    }

    private func load(project: Project) {
        let url = mdURL(in: project)
        if let data = try? Data(contentsOf: url),
           let text = String(data: data, encoding: .utf8) {
            content = text
        } else {
            content = ""
        }
        dirty = false
    }

    private func save(project: Project) {
        do {
            try Data(content.utf8).write(to: mdURL(in: project), options: .atomic)
            dirty = false
            withAnimation { savedToast = true }
            // Structured Task instead of DispatchQueue.asyncAfter so
            // the toast cancels with the view.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                withAnimation { savedToast = false }
            }
        } catch {
            self.error = "\(error)"
        }
    }
}

struct ClaudeMdSnippet {
    let title: String
    let icon: String
    let body: String

    static let all: [ClaudeMdSnippet] = [
        ClaudeMdSnippet(
            title: "Verification",
            icon: "checkmark.seal",
            body: """
            ## Verification

            How to quickly verify a change:

            ```sh
            # add the project's fastest test command here
            swift test --parallel
            ```
            """
        ),
        ClaudeMdSnippet(
            title: "Style",
            icon: "paintbrush",
            body: """
            ## Style

            - Match existing code style. Don't reformat unrelated code.
            - Don't write comments that narrate WHAT the code does — names already do that.
            - Keep diffs focused.
            """
        ),
        ClaudeMdSnippet(
            title: "Hidden constraints",
            icon: "lock.shield",
            body: """
            ## Hidden constraints

            Capture things that bit you once. Examples:
            - DB migrations must be additive — column adds only.
            - Don't import `<X>` from this directory — circular dep.
            """
        ),
        ClaudeMdSnippet(
            title: "Working agreement",
            icon: "person.2",
            body: """
            ## Working agreement

            - Default agent is `team-lead`. Delegates via the Task tool.
            - Persistent notes live as Markdown under `.claude/memory/`.
            - Use `.claude/memory/project/` for shared notes, `.claude/memory/session/<id>/` for private scratch.
            """
        ),
        ClaudeMdSnippet(
            title: "Test plan",
            icon: "checklist",
            body: """
            ## Test plan checklist

            - [ ] Unit tests cover the change
            - [ ] Smoke run in dev
            - [ ] CI green
            - [ ] PR description references the Wrike ticket
            """
        )
    ]
}
