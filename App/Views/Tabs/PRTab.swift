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
    @State private var loading = false
    @State private var error: String?
    @State private var creating = false
    @State private var prTitle: String = ""
    @State private var prBody: String = ""

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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("No pull request yet").font(.headline)
                Spacer()
                Button {
                    Task { await load() }
                } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            Text("Branch: \(session.branch)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Title").font(.caption).foregroundStyle(.secondary)
                TextField("PR title", text: $prTitle)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Description").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $prBody)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 200)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )
            }
            HStack {
                Spacer()
                Button("Push & Create PR") {
                    Task { await create() }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
                .disabled(creating || prTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
                        section("CI checks") {
                            if checks.isEmpty {
                                Text("No checks yet").font(.caption).foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(checks) { check in
                                        checkRow(check)
                                    }
                                }
                            }
                        }
                        section("Review comments") {
                            if comments.isEmpty {
                                Text("No review comments").font(.caption).foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(comments) { c in
                                        commentRow(c)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func header(_ pr: GHPullRequest) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: prIcon(pr))
                        .foregroundStyle(prColor(pr))
                    Text("#\(pr.number) — \(pr.title)").font(.headline)
                }
                Text("\(pr.headRefName ?? session.branch) → \(pr.baseRefName ?? "main")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open in browser") {
                if let url = URL(string: pr.url) { NSWorkspace.shared.open(url) }
            }
            Button {
                Task { await load() }
            } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
        }
        .padding(16)
    }

    private func checkRow(_ check: GHCheckRun) -> some View {
        HStack(spacing: 8) {
            Image(systemName: checkIcon(check))
                .foregroundStyle(checkColor(check))
            Text(check.name)
            Spacer()
            Text(check.conclusion ?? check.state)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let link = check.link, let url = URL(string: link) {
                Link("Logs", destination: url).font(.caption)
            }
        }
    }

    private func commentRow(_ c: GHReviewComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(c.user?.login ?? "?").font(.caption.weight(.semibold))
                if let path = c.path {
                    Text(path).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if let url = c.url, let u = URL(string: url) {
                    Link("Open", destination: u).font(.caption2)
                }
            }
            Text(c.body)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func prIcon(_ pr: GHPullRequest) -> String {
        if pr.merged == true { return "checkmark.seal.fill" }
        if pr.state.lowercased() == "closed" { return "xmark.seal.fill" }
        if pr.isDraft == true { return "pencil.tip" }
        return "arrow.triangle.pull"
    }
    private func prColor(_ pr: GHPullRequest) -> Color {
        if pr.merged == true { return .purple }
        if pr.state.lowercased() == "closed" { return .red }
        return .green
    }
    private func checkIcon(_ c: GHCheckRun) -> String {
        switch c.conclusion {
        case "success": return "checkmark.circle.fill"
        case "failure", "timed_out": return "xmark.circle.fill"
        case "neutral", "skipped", "cancelled": return "minus.circle"
        default: return "circle.dotted"
        }
    }
    private func checkColor(_ c: GHCheckRun) -> Color {
        switch c.conclusion {
        case "success": return .green
        case "failure", "timed_out": return .red
        case "neutral", "skipped", "cancelled": return .secondary
        default: return .accentColor
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
                let (rs, csL) = try await (runs, cs)
                await MainActor.run {
                    self.pr = pr
                    self.checks = rs
                    self.comments = csL
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
