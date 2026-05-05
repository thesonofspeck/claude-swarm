import SwiftUI
import AppCore
import PersistenceKit
import GitHubKit
import GitKit

struct PRTab: View {
    @Environment(AppEnvironment.self) private var env
    let session: Session
    let project: Project?

    @State private var pr: GHPullRequest?
    @State private var checks: [GHCheckRun] = []
    @State private var comments: [GHReviewComment] = []
    @State private var threads: [GHReviewThread] = []
    @State private var loading = false
    @State private var error: String?
    @State private var creating = false
    @State private var prTitle: String = ""
    @State private var prBody: String = ""
    @State private var drafting: Bool = false
    @State private var replyDrafts: [Int64: String] = [:]
    @State private var posting: Set<Int64> = []
    @State private var resolvedRoots: Set<Int64> = []
    @State private var reviewing: Bool = false
    @State private var reviewDraft: LLMHelper.PRReviewDraft?
    @State private var reviewOwner: String?
    @State private var reviewRepo: String?
    @State private var reviewSheetPresented: Bool = false
    @State private var reviewStreamText: String = ""
    @State private var reviewTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let pr {
                prDetail(pr)
            } else {
                createView
            }
        }
        .task(id: session.id) { await load() }
    }

    @ViewBuilder
    private var createView: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.lg) {
            HStack(spacing: Metrics.Space.sm) {
                Image(systemName: "arrow.triangle.pull")
                    .foregroundStyle(Palette.blue)
                    .imageScale(.large)
                Text("New pull request")
                    .font(Type.title)
                    .foregroundStyle(Palette.fgBright)
                Spacer()
                Button {
                    Task { await draftFromDiff() }
                } label: {
                    if drafting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Draft", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!env.llm.isUsable || drafting)
                .help(env.llm.isUsable ? "Draft title + body from the working-tree diff" : "Configure the Anthropic API key in Settings → AI to enable")
                IconButton(systemImage: "arrow.clockwise", help: "Refresh") {
                    Task { await load() }
                }
            }
            HStack(spacing: Metrics.Space.sm) {
                Pill(text: session.branch, systemImage: "arrow.branch", tint: Palette.purple)
                Image(systemName: "arrow.right")
                    .foregroundStyle(Palette.fgMuted)
                    .imageScale(.small)
                Pill(text: project?.defaultBaseBranch ?? "main", systemImage: "arrow.branch", tint: Palette.fgMuted)
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Palette.orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title: "Title")
                TextField("PR title", text: $prTitle)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title: "Description")
                TextEditor(text: $prBody)
                    .font(Type.mono)
                    .scrollContentBackground(.hidden)
                    .padding(Metrics.Space.sm)
                    .background(Palette.bgBase)
                    .frame(minHeight: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: Metrics.Radius.md)
                            .stroke(Palette.divider, lineWidth: Metrics.Stroke.regular)
                    )
            }
            HStack {
                Spacer()
                Button {
                    Task { await create() }
                } label: {
                    Label(creating ? "Pushing…" : "Push & Create PR", systemImage: "arrow.up.circle.fill")
                }
                .controlSize(.large)
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
                .disabled(creating || prTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Metrics.Space.xl)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.bgBase)
        .onAppear {
            if prTitle.isEmpty {
                prTitle = session.taskTitle ?? session.branch
            }
            if prBody.isEmpty {
                let task = session.taskId.map { "Wrike task: \($0)\n\n" } ?? ""
                prBody = task + (session.taskTitle ?? "")
            }
        }
    }

    @ViewBuilder
    private func prDetail(_ pr: GHPullRequest) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(pr)
            Divider()
            if reviewing {
                reviewStreamBanner
                Divider().background(Palette.divider)
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sectionView(title: "CI checks", isEmpty: checks.isEmpty, emptyText: "No checks yet") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(checks) { check in checkRow(check) }
                            }
                        }
                        sectionView(title: "Review comments", isEmpty: comments.isEmpty, emptyText: "No review comments") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(comments) { c in commentRow(c) }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .sheet(isPresented: $reviewSheetPresented, onDismiss: {
            reviewDraft = nil
            reviewOwner = nil
            reviewRepo = nil
        }) {
            if let draft = reviewDraft, let owner = reviewOwner, let repo = reviewRepo {
                PRReviewSheet(
                    prNumber: pr.number,
                    prTitle: pr.title,
                    owner: owner,
                    repo: repo,
                    initial: draft
                ) { edited in
                    try await submitReview(edited, pr: pr, owner: owner, repo: repo)
                }
            }
        }
    }

    private func header(_ pr: GHPullRequest) -> some View {
        HStack(alignment: .top, spacing: Metrics.Space.md) {
            ZStack {
                Circle()
                    .fill(prColor(pr).opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: prIcon(pr))
                    .foregroundStyle(prColor(pr))
                    .imageScale(.large)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(pr.number) — \(pr.title)")
                    .font(Type.heading)
                    .foregroundStyle(Palette.fgBright)
                HStack(spacing: 6) {
                    Pill(text: pr.headRefName ?? session.branch, systemImage: "arrow.branch", tint: Palette.purple)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(Palette.fgMuted)
                        .imageScale(.small)
                    Pill(text: pr.baseRefName ?? "main", systemImage: "arrow.branch", tint: Palette.fgMuted)
                }
            }
            Spacer()
            Button {
                Task { await startReview(pr) }
            } label: {
                if reviewing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Drafting review…")
                    }
                } else {
                    Label("Review with Claude", systemImage: "eyes")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!env.llm.isUsable || reviewing)
            .help(env.llm.isUsable
                ? "Generate a draft review — you'll edit and approve before it's submitted."
                : "Configure Claude in Settings → AI to enable")
            Button("Open in browser") {
                if let url = URL(string: pr.url) { NSWorkspace.shared.open(url) }
            }
            IconButton(systemImage: "arrow.clockwise", help: "Refresh") {
                Task { await load() }
            }
        }
        .padding(Metrics.Space.lg)
        .background(Palette.bgSidebar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.divider).frame(height: Metrics.Stroke.hairline)
        }
    }

    private func checkRow(_ check: GHCheckRun) -> some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: checkIcon(check))
                .foregroundStyle(checkColor(check))
            Text(check.name)
                .font(Type.body)
                .foregroundStyle(Palette.fg)
            Spacer()
            Pill(
                text: check.conclusion?.rawValue ?? check.state,
                tint: checkColor(check)
            )
            if let link = check.link, let url = URL(string: link) {
                Link(destination: url) {
                    Pill(text: "Logs", systemImage: "arrow.up.right.square", tint: Palette.fgMuted)
                }
            }
        }
        .padding(.horizontal, Metrics.Space.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Metrics.Radius.md).fill(Palette.bgRaised)
        )
    }

    private func commentRow(_ c: GHReviewComment) -> some View {
        let thread = threads.first { $0.firstCommentId == c.id }
        let isResolved = thread?.isResolved == true || (thread.map { resolvedRoots.contains($0.firstCommentId ?? 0) } ?? false)
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: Metrics.Space.sm) {
                    Text(c.user?.login ?? "?")
                        .font(Type.caption.weight(.semibold))
                        .foregroundStyle(Palette.blue)
                    if let path = c.path {
                        Text(path)
                            .font(Type.monoCaption)
                            .foregroundStyle(Palette.fgMuted)
                    }
                    if isResolved {
                        Pill(text: "Resolved", systemImage: "checkmark.circle.fill", tint: Palette.green)
                    }
                    Spacer()
                    if let url = c.url, let u = URL(string: url) {
                        Link(destination: u) {
                            Image(systemName: "arrow.up.right.square")
                                .imageScale(.small)
                                .foregroundStyle(Palette.fgMuted)
                        }
                    }
                }
                Text(c.body)
                    .font(Type.body)
                    .foregroundStyle(Palette.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !isResolved {
                    HStack(alignment: .top, spacing: Metrics.Space.sm) {
                        TextField("Reply…", text: Binding(
                            get: { replyDrafts[c.id] ?? "" },
                            set: { replyDrafts[c.id] = $0 }
                        ), axis: .vertical)
                        .lineLimit(1...4)
                        .textFieldStyle(.roundedBorder)
                        .disabled(posting.contains(c.id))

                        Button {
                            Task { await reply(to: c) }
                        } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(posting.contains(c.id) || (replyDrafts[c.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Reply")

                        if let thread {
                            Button {
                                Task { await resolve(thread: thread) }
                            } label: {
                                Image(systemName: "checkmark.circle")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Resolve thread")
                        }
                    }
                }
            }
        }
    }

    private func reply(to comment: GHReviewComment) async {
        guard let project, let pr else { return }
        let body = (replyDrafts[comment.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        _ = posting.insert(comment.id)        do {
            // ?? uses an autoclosure that can't carry try/await; resolve
            // the remote once and fall back to its owner/repo if either
            // project field is missing.
            let resolved: (owner: String, repo: String)
            if project.githubOwner != nil && project.githubRepo != nil {
                resolved = (project.githubOwner!, project.githubRepo!)
            } else {
                let detected = try await env.github.currentRepo(in: URL(fileURLWithPath: session.worktreePath))
                resolved = (project.githubOwner ?? detected.owner,
                            project.githubRepo ?? detected.repo)
            }
            let owner = resolved.owner
            let repo = resolved.repo
            try await env.github.replyToReviewComment(
                owner: owner, repo: repo, number: pr.number,
                commentId: comment.id, body: body
            )
            await MainActor.run {
                replyDrafts[comment.id] = ""
                posting.remove(comment.id)
            }
            await load()
        } catch {
            await MainActor.run {
                self.error = "Could not post reply: \(error.localizedDescription)"
                posting.remove(comment.id)
            }
        }
    }

    private func resolve(thread: GHReviewThread) async {
        do {
            try await env.github.resolveReviewThread(threadId: thread.id)
            await MainActor.run {
                if let rootId = thread.firstCommentId { resolvedRoots.insert(rootId) }
            }
            await load()
        } catch {
            self.error = "Could not resolve: \(error.localizedDescription)"        }
    }

    @ViewBuilder
    private func sectionView<Content: View>(
        title: String,
        isEmpty: Bool,
        emptyText: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if isEmpty {
                Text(emptyText).font(.caption).foregroundStyle(.secondary)
            } else {
                content()
            }
        }
    }

    private func prIcon(_ pr: GHPullRequest) -> String {
        if pr.merged == true { return "checkmark.seal.fill" }
        switch pr.state {
        case .closed: return "xmark.seal.fill"
        case .merged: return "checkmark.seal.fill"
        case .open: return pr.isDraft == true ? "pencil.tip" : "arrow.triangle.pull"
        }
    }
    private func prColor(_ pr: GHPullRequest) -> Color {
        if pr.merged == true { return .purple }
        switch pr.state {
        case .closed: return .red
        case .merged: return .purple
        case .open: return .green
        }
    }
    private func checkIcon(_ c: GHCheckRun) -> String {
        switch c.conclusion {
        case .success: return "checkmark.circle.fill"
        case .failure, .timedOut: return "xmark.circle.fill"
        case .neutral, .skipped, .cancelled: return "minus.circle"
        case .actionRequired: return "exclamationmark.circle"
        case .stale: return "clock.badge.exclamationmark"
        case .none: return "circle.dotted"
        }
    }
    private func checkColor(_ c: GHCheckRun) -> Color {
        switch c.conclusion {
        case .success: return .green
        case .failure, .timedOut: return .red
        case .neutral, .skipped, .cancelled: return .secondary
        case .actionRequired: return .orange
        case .stale: return .yellow
        case .none: return .accentColor
        }
    }

    private func load() async {
        guard let project else { return }
        loading = true; error = nil        let dir = URL(fileURLWithPath: session.worktreePath)
        do {
            if let pr = try await env.github.pullRequestForBranch(in: dir, branch: session.branch) {
                let owner: String
                let repo: String
                if let o = project.githubOwner, let r = project.githubRepo {
                    owner = o
                    repo = r
                } else {
                    let resolved = try await env.github.currentRepo(in: dir)
                    owner = resolved.owner
                    repo = resolved.repo
                }
                async let runs = env.github.checks(owner: owner, repo: repo, number: pr.number)
                async let cs = env.github.reviewComments(owner: owner, repo: repo, number: pr.number)
                async let ths = (try? await env.github.reviewThreads(owner: owner, repo: repo, number: pr.number)) ?? []
                let (rs, csL, thsL) = try await (runs, cs, ths)
                await MainActor.run {
                    self.pr = pr
                    self.checks = rs
                    self.comments = csL
                    self.threads = thsL
                    if pr.merged == true, let id = session.taskId {
                        Task { await env.wrikeBridge.transition(taskId: id, to: .done) }
                    }
                    loading = false
                }
            } else {
                await MainActor.run {
                    self.pr = nil
                    self.checks = []
                    self.comments = []
                    loading = false
                }
            }
        } catch {
            await MainActor.run {
                self.error = "\(error.localizedDescription)"
                loading = false
            }
        }
    }

    private func create() async {
        guard let project else { return }
        creating = true; error = nil        let dir = URL(fileURLWithPath: session.worktreePath)
        do {
            try await env.github.pushBranch(in: dir, branch: session.branch)
            let result = try await env.github.createPullRequest(
                in: dir,
                title: prTitle,
                body: prBody,
                base: project.defaultBaseBranch,
                head: nil
            )
            try env.sessionsRepo.upsert({
                var s = session
                s.prNumber = result.number
                s.status = .prOpen
                return s
            }())
            if let id = session.taskId {
                await env.wrikeBridge.transition(taskId: id, to: .inReview)
            }
            await load()
            creating = false        } catch {
            await MainActor.run {
                self.error = "\(error.localizedDescription)"
                creating = false
            }
        }
    }

    private func draftFromDiff() async {
        drafting = true; error = nil        do {
            let dir = URL(fileURLWithPath: session.worktreePath)
            let files = (try? await env.diff.workingTreeDiff(in: dir)) ?? []
            let diffText = renderDiff(files)
            let draft = try await env.llm.draftPR(
                diff: diffText,
                taskTitle: session.taskTitle,
                taskBody: nil
            )
            await MainActor.run {
                prTitle = draft.title
                prBody = draft.body
                drafting = false
            }
        } catch {
            await MainActor.run {
                self.error = "Couldn't draft: \(error.localizedDescription)"
                drafting = false
            }
        }
    }

    /// Inline live preview shown while the agent streams its review.
    /// Auto-scrolls to bottom; Cancel terminates the underlying
    /// `claude -p` subprocess via task cancellation.
    private var reviewStreamBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Palette.purple)
                    .symbolEffect(.pulse, options: .repeating)
                Text("Drafting review…")
                    .font(Type.label)
                    .foregroundStyle(Palette.fgBright)
                Spacer()
                Text("\(reviewStreamText.count) chars")
                    .font(Type.caption)
                    .foregroundStyle(Palette.fgMuted)
                Button("Cancel") {
                    cancelReview()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(reviewStreamText.isEmpty ? "Waiting for first tokens…" : reviewStreamText)
                        .font(Type.mono)
                        .foregroundStyle(reviewStreamText.isEmpty ? Palette.fgMuted : Palette.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(Metrics.Space.sm)
                        .id("__bottom__")
                }
                .frame(maxHeight: 200)
                .background(Palette.bgRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.Radius.md)
                        .stroke(Palette.divider, lineWidth: Metrics.Stroke.hairline)
                )
                .onChange(of: reviewStreamText) { _, _ in
                    withAnimation(.linear(duration: 0.05)) {
                        proxy.scrollTo("__bottom__", anchor: .bottom)
                    }
                }
            }
        }
        .padding(Metrics.Space.md)
        .background(Palette.bgSidebar)
    }

    private func cancelReview() {
        reviewTask?.cancel()
        reviewTask = nil
        reviewing = false
        reviewStreamText = ""
    }

    private func startReview(_ pr: GHPullRequest) async {
        guard env.llm.isUsable else { return }
        reviewing = true
        reviewStreamText = ""
        error = nil
        let resolved: (owner: String, repo: String)
        do {
            resolved = try await resolveOwnerRepo()
        } catch {
            self.error = "Couldn't resolve repo: \(error.localizedDescription)"
            reviewing = false
            return
        }
        let diff: String
        do {
            diff = try await env.github.prDiff(
                owner: resolved.owner, repo: resolved.repo, number: pr.number
            )
        } catch {
            self.error = "Couldn't fetch diff: \(error.localizedDescription)"
            reviewing = false
            return
        }
        let stream: AsyncThrowingStream<String, Error>
        do {
            stream = try env.llm.streamReviewPR(
                diff: diff,
                prTitle: pr.title,
                prBody: pr.body,
                prAuthor: pr.author?.login,
                baseRef: pr.baseRefName ?? project?.defaultBaseBranch ?? "main",
                headRef: pr.headRefName ?? session.branch
            )
        } catch {
            self.error = "Couldn't start review: \(error.localizedDescription)"
            reviewing = false
            return
        }
        reviewTask = Task { @MainActor in
            var accumulator = ""
            do {
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    accumulator += chunk
                    reviewStreamText = accumulator
                }
                if Task.isCancelled { return }
                let draft = env.llm.parseReviewDraft(accumulator)
                self.reviewOwner = resolved.owner
                self.reviewRepo = resolved.repo
                self.reviewDraft = draft
                self.reviewing = false
                self.reviewStreamText = ""
                self.reviewTask = nil
                self.reviewSheetPresented = true
            } catch {
                self.error = "Review failed: \(error.localizedDescription)"
                self.reviewing = false
                self.reviewStreamText = ""
                self.reviewTask = nil
            }
        }
    }

    private func submitReview(
        _ draft: LLMHelper.PRReviewDraft,
        pr: GHPullRequest,
        owner: String,
        repo: String
    ) async throws {
        let event: GitHubClient.ReviewEvent = {
            switch draft.verdict {
            case .approve: return .approve
            case .requestChanges: return .requestChanges
            case .comment: return .comment
            }
        }()
        let lineComments = draft.comments.map {
            GitHubClient.ReviewLineComment(path: $0.file, line: $0.line, body: $0.body)
        }
        try await env.github.submitReview(
            owner: owner, repo: repo, number: pr.number,
            event: event,
            summary: draft.summary,
            comments: lineComments
        )
        await load()
    }

    private func resolveOwnerRepo() async throws -> (owner: String, repo: String) {
        if let p = project, let o = p.githubOwner, let r = p.githubRepo {
            return (o, r)
        }
        return try await env.github.currentRepo(in: URL(fileURLWithPath: session.worktreePath))
    }

    /// Render parsed diff back into a unified-diff-ish string the LLM can
    /// reason about. Truncated at 8000 chars later by the helper.
    private func renderDiff(_ files: [DiffFile]) -> String {
        var out = ""
        for file in files {
            out += "diff --git a/\(file.oldPath ?? "") b/\(file.newPath ?? "")\n"
            for hunk in file.hunks {
                out += "\(hunk.header)\n"
                for line in hunk.lines {
                    let prefix: String
                    switch line.kind {
                    case .addition: prefix = "+"
                    case .deletion: prefix = "-"
                    default: prefix = " "
                    }
                    out += "\(prefix)\(line.text)\n"
                }
            }
        }
        return out
    }
}
