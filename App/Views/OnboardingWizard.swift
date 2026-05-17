import SwiftUI
import AppCore
import PersistenceKit
import GitKit
import GitHubKit
import WrikeKit

/// Three-step project onboarding:
///   1. Pick the source — open an existing local folder, clone an
///      existing GitHub repo, or create a new one.
///   2. Source-specific input (path picker / repo search / new-repo form).
///   3. Configure & link integrations (Wrike folder, kubectl context).
///
/// Replaces the previous flat "Add Project" form. The same struct is the
/// entry point — sidebar/drag-drop callers continue to instantiate
/// `AddProjectSheet` and pass an optional initial path.
struct OnboardingWizard: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(ProjectListViewModel.self) private var projectList
    @Environment(\.dismiss) private var dismiss

    var initialPath: String?

    @State private var step: Step = .source
    @State private var source: SourceKind?
    @State private var resolvedPath: String = ""
    @State private var name: String = ""
    @State private var baseBranch: String = "main"
    @State private var githubOwner: String = ""
    @State private var githubRepo: String = ""
    @State private var wrikeFolderId: String = ""
    @State private var kubeContext: String = ""
    @State private var kubeNamespace: String = ""
    @State private var working = false
    @State private var error: String?

    enum Step: Int, CaseIterable {
        case source, fetch, configure
        var title: String {
            switch self {
            case .source: return "How would you like to start?"
            case .fetch: return "Get the code"
            case .configure: return "Configure"
            }
        }
    }

    enum SourceKind: String, Hashable {
        case local, clone, create
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            Divider().background(Palette.divider)
            ScrollView {
                content.padding(Metrics.Space.lg)
            }
            Divider().background(Palette.divider)
            footer
        }
        .frame(width: 720, height: 620)
        .background(Palette.bgBase)
        .onAppear {
            if let initialPath, !initialPath.isEmpty {
                source = .local
                applyResolvedPath(initialPath)
                step = .configure
            }
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: Metrics.Space.sm) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .foregroundStyle(Palette.purple)
                .imageScale(.large)
            Text(step.title)
                .font(Type.heading)
                .foregroundStyle(Palette.fgBright)
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Palette.purple : Palette.divider)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(Metrics.Space.md)
    }

    // MARK: - Content per step

    @ViewBuilder
    private var content: some View {
        switch step {
        case .source: sourceStep
        case .fetch: fetchStep
        case .configure: configureStep
        }
    }

    // MARK: - Step 1: source picker

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text("Pick a source. You can always change Wrike or Kubernetes settings later.")
                .font(Type.body)
                .foregroundStyle(Palette.fgMuted)
            sourceCard(
                kind: .local,
                title: "I have a local folder",
                description: "Use an existing folder on your Mac. Auto-detects the GitHub remote.",
                systemImage: "folder.fill"
            )
            sourceCard(
                kind: .clone,
                title: "Clone an existing GitHub repo",
                description: "Search your repos and clone into a folder of your choice.",
                systemImage: "arrow.down.circle.fill"
            )
            sourceCard(
                kind: .create,
                title: "Create a new GitHub repo",
                description: "Spin up a fresh repo with a README and clone it locally.",
                systemImage: "plus.circle.fill"
            )
        }
    }

    private func sourceCard(
        kind: SourceKind,
        title: String,
        description: String,
        systemImage: String
    ) -> some View {
        let selected = source == kind
        return Button {
            source = kind
        } label: {
            HStack(alignment: .top, spacing: Metrics.Space.md) {
                ZStack {
                    Circle()
                        .fill((selected ? Palette.purple : Palette.fgMuted).opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: systemImage)
                        .foregroundStyle(selected ? Palette.purple : Palette.fgMuted)
                        .imageScale(.large)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Type.body.weight(.semibold))
                        .foregroundStyle(Palette.fgBright)
                    Text(description)
                        .font(Type.caption)
                        .foregroundStyle(Palette.fgMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.purple)
                }
            }
            .padding(Metrics.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .fill(selected ? Palette.purple.opacity(0.06) : Palette.bgRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.Radius.md)
                    .stroke(
                        selected ? Palette.purple : Palette.divider,
                        lineWidth: selected ? Metrics.Stroke.regular : Metrics.Stroke.hairline
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: source-specific fetcher

    @ViewBuilder
    private var fetchStep: some View {
        switch source {
        case .local: localFetch
        case .clone: cloneFetch
        case .create: createFetch
        case nil: EmptyView()
        }
    }

    private var localFetch: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text("Pick the project folder. We'll auto-detect the GitHub remote and default branch.")
                .font(Type.body)
                .foregroundStyle(Palette.fgMuted)
            HStack {
                TextField("Local path", text: $resolvedPath)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: resolvedPath) { _, value in applyResolvedPath(value) }
                Button("Choose…") { chooseDirectory() }
            }
            if !resolvedPath.isEmpty {
                projectSummary
            }
        }
    }

    private var cloneFetch: some View {
        CloneRepoView(
            destinationParent: defaultParent(),
            onCloned: { url, owner, repo in
                applyResolvedPath(url.path)
                githubOwner = owner
                githubRepo = repo
                step = .configure
            }
        )
    }

    private var createFetch: some View {
        CreateRepoView(
            destinationParent: defaultParent(),
            onCreated: { url, owner, repo in
                applyResolvedPath(url.path)
                githubOwner = owner
                githubRepo = repo
                step = .configure
            }
        )
    }

    // MARK: - Step 3: configure + integrations

    private var configureStep: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.lg) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title: "Project")
                Card {
                    VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                        HStack {
                            Text("Name").frame(width: 110, alignment: .leading)
                                .foregroundStyle(Palette.fgMuted)
                            TextField("Project name", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Path").frame(width: 110, alignment: .leading)
                                .foregroundStyle(Palette.fgMuted)
                            Text(resolvedPath)
                                .font(Type.monoCaption)
                                .foregroundStyle(Palette.fg)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        HStack {
                            Text("Base branch").frame(width: 110, alignment: .leading)
                                .foregroundStyle(Palette.fgMuted)
                            TextField("main", text: $baseBranch)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 200, alignment: .leading)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title: "GitHub")
                Card {
                    HStack(spacing: Metrics.Space.sm) {
                        TextField("owner", text: $githubOwner).textFieldStyle(.roundedBorder)
                        Text("/").foregroundStyle(Palette.fgMuted)
                        TextField("repo", text: $githubRepo).textFieldStyle(.roundedBorder)
                    }
                }
            }
            WrikeFolderPicker(folderId: $wrikeFolderId)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title: "Kubernetes (optional)")
                Card {
                    VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                        TextField("kubectl context", text: $kubeContext, prompt: Text("e.g. arn:aws:eks:us-east-1:…:cluster/prod"))
                            .textFieldStyle(.roundedBorder)
                        TextField("Namespace", text: $kubeNamespace, prompt: Text("default"))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.red)
            }
        }
    }

    private var projectSummary: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                if !name.isEmpty {
                    Text(name).font(Type.body.weight(.semibold))
                        .foregroundStyle(Palette.fgBright)
                }
                if !githubOwner.isEmpty || !githubRepo.isEmpty {
                    Pill(
                        text: "\(githubOwner)/\(githubRepo)",
                        systemImage: "checkmark.seal",
                        tint: Palette.green
                    )
                }
                Text(resolvedPath)
                    .font(Type.monoCaption)
                    .foregroundStyle(Palette.fgMuted)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Footer / navigation

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(working)
            Spacer()
            if step != .source {
                Button("Back") {
                    withAnimation { step = previousStep() }
                }
                .disabled(working)
            }
            if showPrimary {
                Button(action: primaryAction) {
                    if working {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(workingTitle)
                        }
                    } else {
                        Text(primaryTitle)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed || working)
            }
        }
        .padding(Metrics.Space.md)
    }

    /// Step 2 for clone/create has its own inline "Clone" / "Create"
    /// button — hide the wizard's primary so the footer doesn't carry
    /// a permanently-disabled "Continue".
    private var showPrimary: Bool {
        if step == .fetch && (source == .clone || source == .create) {
            return false
        }
        return true
    }

    private var primaryTitle: String {
        switch step {
        case .source: return "Continue"
        case .fetch: return "Continue"
        case .configure: return "Add project"
        }
    }

    private var workingTitle: String {
        step == .configure ? "Adding…" : "Working…"
    }

    private var canProceed: Bool {
        switch step {
        case .source:
            return source != nil
        case .fetch:
            return source == .local ? !resolvedPath.isEmpty : false
        case .configure:
            return !name.isEmpty && !resolvedPath.isEmpty
        }
    }

    private func primaryAction() {
        switch step {
        case .source:
            withAnimation { step = .fetch }
        case .fetch:
            // Local just validates and continues; clone/create advance
            // their own flow when their inner button completes.
            if source == .local { withAnimation { step = .configure } }
        case .configure:
            Task { await register() }
        }
    }

    private func previousStep() -> Step {
        switch step {
        case .source: return .source
        case .fetch: return .source
        case .configure: return source == .local ? .fetch : .source
        }
    }

    // MARK: - Actions

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            applyResolvedPath(url.path)
        }
    }

    private func applyResolvedPath(_ path: String) {
        resolvedPath = path
        guard !path.isEmpty else { return }
        if name.isEmpty {
            name = (path as NSString).lastPathComponent
        }
        if let origin = GitConfigParser.origin(in: URL(fileURLWithPath: path)) {
            if let owner = origin.owner, githubOwner.isEmpty { githubOwner = owner }
            if let repo = origin.repo, githubRepo.isEmpty { githubRepo = repo }
        }
    }

    private func defaultParent() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Code")
    }

    private func register() async {
        working = true
        error = nil
        await projectList.register(
            name: name,
            path: resolvedPath,
            baseBranch: baseBranch.isEmpty ? "main" : baseBranch,
            wrikeFolder: wrikeFolderId.isEmpty ? nil : wrikeFolderId,
            githubOwner: githubOwner.isEmpty ? nil : githubOwner,
            githubRepo: githubRepo.isEmpty ? nil : githubRepo,
            kubeContext: kubeContext.isEmpty ? nil : kubeContext,
            kubeNamespace: kubeNamespace.isEmpty ? nil : kubeNamespace
        )
        working = false
        if let err = projectList.error {
            error = err
        } else {
            dismiss()
        }
    }
}

// MARK: - Clone repo step

private struct CloneRepoView: View {
    @Environment(AppEnvironment.self) private var env

    let destinationParent: URL
    let onCloned: (URL, String, String) -> Void

    @State private var query: String = ""
    @State private var results: [GHRepoSummary] = []
    @State private var searching = false
    @State private var loadingMine = true
    @State private var selected: GHRepoSummary?
    @State private var parentPath: String
    @State private var cloning = false
    @State private var error: String?

    init(destinationParent: URL, onCloned: @escaping (URL, String, String) -> Void) {
        self.destinationParent = destinationParent
        self.onCloned = onCloned
        self._parentPath = State(initialValue: destinationParent.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text("Pick a repo to clone. Searches your repos by default; full GitHub search activates when you type.")
                .font(Type.body)
                .foregroundStyle(Palette.fgMuted)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.fgMuted)
                TextField("Search GitHub (e.g. owner/repo or keyword)", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await runSearch() } }
                if searching || loadingMine { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, Metrics.Space.sm)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Metrics.Radius.md).fill(Palette.bgRaised))
            .overlay(RoundedRectangle(cornerRadius: Metrics.Radius.md).stroke(Palette.divider, lineWidth: Metrics.Stroke.hairline))

            repoList

            HStack {
                Text("Clone into").foregroundStyle(Palette.fgMuted)
                TextField("Parent directory", text: $parentPath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseParent() }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.red)
            }

            HStack {
                Spacer()
                Button {
                    Task { await clone() }
                } label: {
                    if cloning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Cloning…")
                        }
                    } else {
                        Label("Clone", systemImage: "arrow.down.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected == nil || parentPath.isEmpty || cloning)
            }
        }
        .task { await loadMine() }
        .onChange(of: query) { _, value in
            if value.isEmpty {
                Task { await loadMine() }
            }
        }
    }

    private var repoList: some View {
        Card(padding: 0) {
            if results.isEmpty && !searching && !loadingMine {
                Text("No repos found.").foregroundStyle(Palette.fgMuted)
                    .padding(Metrics.Space.md)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { repo in
                            repoRow(repo)
                            if repo.id != results.last?.id {
                                Divider().background(Palette.divider)
                            }
                        }
                    }
                }
                .frame(minHeight: 240, maxHeight: 280)
            }
        }
    }

    private func repoRow(_ repo: GHRepoSummary) -> some View {
        let isSelected = selected?.id == repo.id
        return Button {
            selected = repo
        } label: {
            HStack(alignment: .top, spacing: Metrics.Space.sm) {
                Image(systemName: repo.isPrivate == true ? "lock.fill" : "book.closed")
                    .foregroundStyle(isSelected ? Palette.purple : Palette.fgMuted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.nameWithOwner)
                        .font(Type.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(Palette.fgBright)
                    if let d = repo.description, !d.isEmpty {
                        Text(d).font(Type.caption).foregroundStyle(Palette.fgMuted)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.purple)
                }
            }
            .padding(Metrics.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? Palette.purple.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            parentPath = url.path
        }
    }

    private func loadMine() async {
        loadingMine = true
        defer { loadingMine = false }
        do {
            results = try await env.github.listRepos(limit: 100)
        } catch {
            self.error = "Couldn't list your repos: \(error.localizedDescription)"
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { await loadMine(); return }
        searching = true
        defer { searching = false }
        do {
            results = try await env.github.searchRepos(query: q, limit: 50)
        } catch {
            self.error = "\(error.localizedDescription)"
        }
    }

    private func clone() async {
        guard let selected else { return }
        cloning = true
        error = nil
        defer { cloning = false }
        let parts = selected.nameWithOwner.split(separator: "/")
        guard parts.count == 2 else {
            error = "Unexpected repo identifier: \(selected.nameWithOwner)"
            return
        }
        let owner = String(parts[0])
        let repo = String(parts[1])
        do {
            let parent = URL(fileURLWithPath: parentPath)
            let cloned = try await env.github.cloneRepo(owner: owner, repo: repo, intoParent: parent)
            onCloned(cloned, owner, repo)
        } catch {
            self.error = "\(error.localizedDescription)"
        }
    }
}

// MARK: - Create repo step

private struct CreateRepoView: View {
    @Environment(AppEnvironment.self) private var env

    let destinationParent: URL
    let onCreated: (URL, String, String) -> Void

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var visibility: GitHubClient.RepoVisibility = .private
    @State private var parentPath: String
    @State private var creating = false
    @State private var owner: String = ""
    @State private var loadingUser = true
    @State private var error: String?

    init(destinationParent: URL, onCreated: @escaping (URL, String, String) -> Void) {
        self.destinationParent = destinationParent
        self.onCreated = onCreated
        self._parentPath = State(initialValue: destinationParent.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Space.md) {
            Text("Creates the repo under your authenticated GitHub account, adds a README, and clones it locally.")
                .font(Type.body)
                .foregroundStyle(Palette.fgMuted)

            Card {
                VStack(alignment: .leading, spacing: Metrics.Space.sm) {
                    HStack {
                        Text("Owner").frame(width: 100, alignment: .leading)
                            .foregroundStyle(Palette.fgMuted)
                        if loadingUser {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(owner.isEmpty ? "(unknown)" : owner)
                                .font(Type.mono)
                                .foregroundStyle(Palette.fgBright)
                        }
                    }
                    HStack {
                        Text("Name").frame(width: 100, alignment: .leading)
                            .foregroundStyle(Palette.fgMuted)
                        TextField("repo-name", text: $name).textFieldStyle(.roundedBorder)
                    }
                    HStack(alignment: .top) {
                        Text("Description").frame(width: 100, alignment: .leading)
                            .foregroundStyle(Palette.fgMuted)
                        TextField("Optional", text: $description).textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("Visibility").frame(width: 100, alignment: .leading)
                            .foregroundStyle(Palette.fgMuted)
                        Picker("", selection: $visibility) {
                            Text("Private").tag(GitHubClient.RepoVisibility.private)
                            Text("Public").tag(GitHubClient.RepoVisibility.public)
                            Text("Internal").tag(GitHubClient.RepoVisibility.internal)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }

            HStack {
                Text("Clone into").foregroundStyle(Palette.fgMuted)
                TextField("Parent directory", text: $parentPath)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseParent() }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.red)
            }

            HStack {
                Spacer()
                Button {
                    Task { await create() }
                } label: {
                    if creating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Creating…")
                        }
                    } else {
                        Label("Create & clone", systemImage: "plus.circle.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || parentPath.isEmpty || creating || owner.isEmpty)
            }
        }
        .task { await loadOwner() }
    }

    private func chooseParent() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            parentPath = url.path
        }
    }

    private func loadOwner() async {
        loadingUser = true
        defer { loadingUser = false }
        let status = await env.github.authStatus()
        owner = status.user ?? ""
        if !status.authenticated {
            error = "GitHub not authenticated. Run `gh auth login` and try again."
        }
    }

    private func create() async {
        creating = true
        error = nil
        defer { creating = false }
        do {
            let parent = URL(fileURLWithPath: parentPath)
            let url = try await env.github.createRepo(
                name: name,
                visibility: visibility,
                description: description,
                intoParent: parent
            )
            onCreated(url, owner, name)
        } catch {
            self.error = "\(error.localizedDescription)"
        }
    }
}

// MARK: - Wrike folder picker

private struct WrikeFolderPicker: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var folderId: String

    @State private var folders: [WrikeFolder] = []
    @State private var loading = false
    @State private var query: String = ""
    @State private var hasToken = true

    var filtered: [WrikeFolder] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return folders }
        return folders.filter { $0.title.lowercased().contains(q) || $0.id.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(title: "Wrike folder (optional)")
                Spacer()
                if !folderId.isEmpty {
                    Button("Clear") { folderId = "" }
                        .buttonStyle(.plain)
                        .font(Type.label)
                        .foregroundStyle(Palette.fgMuted)
                }
            }
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if !hasToken {
                        Text("Add a Wrike token in Settings → Integrations to map projects to folders.")
                            .font(Type.caption)
                            .foregroundStyle(Palette.fgMuted)
                            .padding(Metrics.Space.md)
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Palette.fgMuted)
                            TextField("Search Wrike folders", text: $query)
                                .textFieldStyle(.plain)
                            if loading { ProgressView().controlSize(.small) }
                        }
                        .padding(Metrics.Space.sm)
                        Divider().background(Palette.divider)

                        if filtered.isEmpty && !loading {
                            Text("No folders match.")
                                .foregroundStyle(Palette.fgMuted)
                                .padding(Metrics.Space.md)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(filtered) { folder in
                                        folderRow(folder)
                                        if folder.id != filtered.last?.id {
                                            Divider().background(Palette.divider)
                                        }
                                    }
                                }
                            }
                            .frame(minHeight: 120, maxHeight: 200)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func folderRow(_ folder: WrikeFolder) -> some View {
        let selected = folderId == folder.id
        return Button {
            folderId = selected ? "" : folder.id
        } label: {
            HStack {
                Image(systemName: selected ? "checkmark.circle.fill" : "folder")
                    .foregroundStyle(selected ? Palette.purple : Palette.fgMuted)
                Text(folder.title).foregroundStyle(Palette.fgBright)
                Spacer()
                Text(folder.id)
                    .font(Type.monoCaption)
                    .foregroundStyle(Palette.fgMuted)
            }
            .padding(.horizontal, Metrics.Space.md)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selected ? Palette.purple.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        let has = await env.wrike.hasToken()
        hasToken = has
        guard has else { return }
        loading = true
        defer { loading = false }
        do {
            let f = try await env.wrike.folders()
            folders = f.sorted { $0.title.lowercased() < $1.title.lowercased() }
        } catch {
            // Silent — sheet has plenty of other things to show.
        }
    }
}
