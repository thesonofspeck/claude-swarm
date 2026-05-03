import SwiftUI
import AppCore
import PersistenceKit
import WrikeKit

/// Lets the user create a Wrike task in a project's mapped folder, with a
/// ✨ button that drafts title + description from a one-line hint.
struct NewWrikeTaskSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    let project: Project

    @State private var hint = ""
    @State private var title = ""
    @State private var body_ = ""
    @State private var importance: String = "Normal"
    @State private var drafting = false
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: "checklist.checked")
                    .foregroundStyle(Palette.cyan)
                    .imageScale(.large)
                Text("New Wrike task")
                    .font(Type.title)
                    .foregroundStyle(Palette.fgBright)
            }
            Text("Creates a task in this project's Wrike folder. Use ✨ to draft title + description from a one-liner.")
                .font(Type.caption)
                .foregroundStyle(Palette.fgMuted)

            HStack {
                TextField("One-line hint to draft from…", text: $hint)
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await draft() }
                } label: {
                    if drafting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!env.llm.isUsable || drafting || hint.trimmingCharacters(in: .whitespaces).isEmpty)
                .help(env.llm.isUsable ? "Draft title + description from the hint" : "Configure the Anthropic API key in Settings → AI to enable")
            }

            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Description") {
                    TextEditor(text: $body_)
                        .font(Type.mono)
                        .frame(minHeight: 200)
                }
                Section("Importance") {
                    Picker("Importance", selection: $importance) {
                        Text("High").tag("High")
                        Text("Normal").tag("Normal")
                        Text("Low").tag("Low")
                    }
                    .pickerStyle(.segmented)
                }
                if let error {
                    Section { Text(error).foregroundStyle(Palette.red) }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(creating ? "Creating…" : "Create task") {
                    Task { await create() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(creating || project.wrikeFolderId == nil ||
                          title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Metrics.Space.lg)
        .frame(width: 620, height: 560)
        .background(Palette.bgSidebar)
    }

    private func draft() async {
        drafting = true; error = nil        do {
            let result = try await env.llm.draftWrikeTask(
                from: hint,
                projectContext: project.name
            )
            await MainActor.run {
                title = result.title
                body_ = result.description
                drafting = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                drafting = false
            }
        }
    }

    private func create() async {
        guard let folderId = project.wrikeFolderId else {
            error = "No Wrike folder mapped on this project."
            return
        }
        creating = true; error = nil        do {
            let mutation = WrikeTaskMutation(
                title: title,
                description: body_,
                importance: importance
            )
            _ = try await env.wrike.createTask(in: folderId, mutation: mutation)
            creating = false; dismiss()        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                creating = false
            }
        }
    }
}
