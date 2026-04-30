import SwiftUI
import AppCore
import PersistenceKit
import GitHubKit

struct PRTab: View {
    @EnvironmentObject var env: AppEnvironment
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
    @State private var replyDrafts: [Int64: String] = [:]
    @State private var posting: Set<Int64> = []
    @State private var resolvedRoots: Set<Int64> = []

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
        await MainActor.run { _ = posting.insert(comment.id) }
        do {
            let owner = project.githubOwner ?? (try await env.github.currentRepo(in: URL(fileURLWithPath: session.worktreePath)).owner)
            let repo = project.githubRepo ?? (try await env.github.currentRepo(in: URL(fileURLWithPath: session.worktreePath)).repo)
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
            await MainActor.run { self.error = "Could not resolve: \(error.localizedDescription)" }
        }
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
        await MainActor.run { loading = true; error = nil }
        let dir = URL(fileURLWithPath: session.worktreePath)
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
                        Task { await env.wrikeBridge.transitionDone(taskId: id) }
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
        await MainActor.run { creating = true; error = nil }
        let dir = URL(fileURLWithPath: session.worktreePath)
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
                await env.wrikeBridge.transitionInReview(taskId: id)
            }
            await load()
            await MainActor.run { creating = false }
        } catch {
            await MainActor.run {
                self.error = "\(error.localizedDescription)"
                creating = false
            }
        }
    }
}
