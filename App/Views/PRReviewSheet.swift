import SwiftUI
import AppCore
import GitHubKit
import PersistenceKit

/// Human-in-the-loop draft-review editor. The agent generated the
/// initial verdict + summary + per-line comments; the user can edit
/// any of it (or delete individual comments) before submitting.
///
/// Submit posts to GitHub as a single review via
/// `POST /repos/.../pulls/.../reviews`. We never auto-approve — even on
/// `verdict == .approve` the user has to click Submit.
struct PRReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let prNumber: Int
    let prTitle: String
    let owner: String
    let repo: String
    /// Submits a fully-edited draft to GitHub. The PRTab owns the
    /// GitHubClient call; the sheet stays focused on UI.
    let onSubmit: (LLMHelper.PRReviewDraft) async throws -> Void

    @State private var draft: LLMHelper.PRReviewDraft
    @State private var submitting = false
    @State private var error: String?

    init(
        prNumber: Int,
        prTitle: String,
        owner: String,
        repo: String,
        initial: LLMHelper.PRReviewDraft,
        onSubmit: @escaping (LLMHelper.PRReviewDraft) async throws -> Void
    ) {
        self.prNumber = prNumber
        self.prTitle = prTitle
        self.owner = owner
        self.repo = repo
        self.onSubmit = onSubmit
        self._draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(Palette.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.Space.lg) {
                    verdictSection
                    summarySection
                    commentsSection
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.red)
                            .padding(Metrics.Space.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                                    .fill(Palette.red.opacity(0.08))
                            )
                    }
                }
                .padding(Metrics.Space.lg)
            }
            Divider().background(Palette.divider)
            footer
        }
        .frame(width: 720, height: 640)
        .background(Palette.bgBase)
    }

    private var header: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "eyes")
                .foregroundStyle(Palette.purple)
                .imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review #\(prNumber)")
                    .font(Type.heading)
                    .foregroundStyle(Palette.fgBright)
                Text(prTitle)
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Pill(text: "\(owner)/\(repo)", systemImage: "tag", tint: Palette.fgMuted)
        }
        .padding(Metrics.Space.md)
    }

    private var verdictSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Verdict")
            Picker("Verdict", selection: $draft.verdict) {
                Label("Comment", systemImage: "text.bubble")
                    .tag(LLMHelper.PRReviewVerdict.comment)
                Label("Request changes", systemImage: "exclamationmark.bubble")
                    .tag(LLMHelper.PRReviewVerdict.requestChanges)
                Label("Approve", systemImage: "checkmark.seal")
                    .tag(LLMHelper.PRReviewVerdict.approve)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(verdictHelpText)
                .font(Type.caption)
                .foregroundStyle(Palette.fgMuted)
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "Summary")
            TextEditor(text: $draft.summary)
                .font(Type.body)
                .scrollContentBackground(.hidden)
                .padding(Metrics.Space.sm)
                .frame(minHeight: 120, maxHeight: 220)
                .background(Palette.bgRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.Radius.md)
                        .stroke(Palette.divider, lineWidth: Metrics.Stroke.regular)
                )
        }
    }

    @ViewBuilder
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(title: "Inline comments (\(draft.comments.count))")
                Spacer()
            }
            if draft.comments.isEmpty {
                Card {
                    Text("No inline comments. The agent thought the change was self-contained.")
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                }
            } else {
                ForEach($draft.comments) { $comment in
                    commentEditor($comment)
                }
            }
        }
    }

    private func commentEditor(_ binding: Binding<LLMHelper.PRReviewComment>) -> some View {
        let comment = binding.wrappedValue
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: Metrics.Space.sm) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(Palette.fgMuted)
                    Text(comment.file)
                        .font(Type.monoCaption)
                        .foregroundStyle(Palette.fgBright)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Pill(text: "L\(comment.line)", tint: Palette.fgMuted)
                    Pill(text: comment.severity.rawValue, tint: severityTint(comment.severity))
                    Spacer()
                    Button(role: .destructive) {
                        draft.comments.removeAll { $0.id == comment.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.red)
                    .help("Drop this comment")
                }
                TextEditor(text: binding.body)
                    .font(Type.body)
                    .scrollContentBackground(.hidden)
                    .padding(Metrics.Space.sm)
                    .frame(minHeight: 60, maxHeight: 160)
                    .background(Palette.bgBase)
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.Radius.md)
                            .stroke(Palette.divider, lineWidth: Metrics.Stroke.regular)
                    )
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(submitButtonHint)
                .font(Type.caption)
                .foregroundStyle(Palette.fgMuted)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(submitting)
            Button {
                Task { await submit() }
            } label: {
                if submitting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Submitting…")
                    }
                } else {
                    Label(submitButtonTitle, systemImage: submitButtonIcon)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .tint(submitButtonTint)
            .disabled(submitting || !canSubmit)
        }
        .padding(Metrics.Space.md)
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        let trimmed = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.verdict {
        case .approve, .requestChanges:
            return !trimmed.isEmpty
        case .comment:
            return !trimmed.isEmpty || !draft.comments.isEmpty
        }
    }

    private var verdictHelpText: String {
        switch draft.verdict {
        case .approve: return "Marks the PR approved. Use only if you'd ship it as-is."
        case .requestChanges: return "Blocks the PR until the author addresses your comments."
        case .comment: return "Posts feedback without affecting approval status."
        }
    }

    private var submitButtonTitle: String {
        switch draft.verdict {
        case .approve: return "Submit approval"
        case .requestChanges: return "Submit request changes"
        case .comment: return "Submit comments"
        }
    }

    private var submitButtonIcon: String {
        switch draft.verdict {
        case .approve: return "checkmark.seal.fill"
        case .requestChanges: return "exclamationmark.bubble.fill"
        case .comment: return "paperplane.fill"
        }
    }

    private var submitButtonTint: Color {
        switch draft.verdict {
        case .approve: return Palette.green
        case .requestChanges: return Palette.orange
        case .comment: return Palette.blue
        }
    }

    private var submitButtonHint: String {
        let trimmed = draft.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && draft.comments.isEmpty {
            return "Add a summary or at least one comment to submit."
        }
        switch draft.verdict {
        case .approve: return "Will submit a real approval to GitHub."
        case .requestChanges: return "Will block the PR until comments are addressed."
        case .comment: return "Posts as comment-only — no approval state change."
        }
    }

    private func severityTint(_ s: LLMHelper.PRCommentSeverity) -> Color {
        switch s {
        case .block: return Palette.red
        case .major: return Palette.orange
        case .minor: return Palette.cyan
        case .nit: return Palette.fgMuted
        }
    }

    private func submit() async {
        submitting = true
        error = nil
        do {
            try await onSubmit(draft)
            submitting = false
            dismiss()
        } catch {
            self.error = "Could not submit: \(error.localizedDescription)"
            submitting = false
        }
    }
}
