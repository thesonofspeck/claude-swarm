import SwiftUI
import AppCore
import PersistenceKit

struct RootSplitView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var selectedSession: Session?
    @SceneStorage("rootSplit.columnVisibility") private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @SceneStorage("rootSplit.inspectorVisible") private var inspectorVisible: Bool = true
    @State private var showOnboarding = false
    @State private var showCommandPalette = false
    @State private var showInbox = false
    @State private var showGlobalSearch = false
    @State private var showWorktreeJanitor = false
    @State private var newSessionProjectId: String?
    @State private var didRestoreSelection = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedSession: $selectedSession,
                newSessionProjectId: $newSessionProjectId
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
            .background(Palette.bgSidebar)
        } detail: {
            Group {
                if let session = selectedSession {
                    DetailView(session: session)
                } else {
                    WelcomeView(
                        feed: env.welcomeFeed,
                        selectedSession: $selectedSession,
                        newSessionProjectId: $newSessionProjectId
                    )
                }
            }
            .navigationSplitViewColumnWidth(min: 600, ideal: 800)
            .background(Palette.bgBase)
            .inspector(isPresented: $inspectorVisible) {
                InspectorView(session: selectedSession)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                    .background(Palette.bgSidebar)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            IconButton(
                                systemImage: inspectorVisible ? "sidebar.right" : "sidebar.squares.right",
                                help: "Toggle inspector — ⌘⌥I"
                            ) {
                                withAnimation(Motion.spring) { inspectorVisible.toggle() }
                            }
                            .keyboardShortcut("i", modifiers: [.command, .option])
                        }
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                IconButton(systemImage: "plus", help: "New session — ⌘N") {
                    newSessionProjectId = selectedSession?.projectId ?? ""
                }
            }
            ToolbarItem(placement: .principal) {
                IconButton(systemImage: "command", help: "Command palette — ⌘K") {
                    showCommandPalette = true
                }
            }
            ToolbarItem(placement: .principal) {
                IconButton(systemImage: "tray.full", help: "Inbox — ⌘⇧I") {
                    showInbox = true
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            ToolbarItem(placement: .principal) {
                IconButton(systemImage: "magnifyingglass", help: "Search everything — ⌘⇧F") {
                    showGlobalSearch = true
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
        }
        .overlay(alignment: .bottom) {
            ErrorBanner(message: env.lastError) {
                env.lastError = nil
            }
            .padding(Metrics.Space.md)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet().environment(env)
        }
        .sheet(item: Binding(
            get: { newSessionProjectId.map { NewSessionContext(projectId: $0) } },
            set: { newSessionProjectId = $0?.projectId }
        )) { ctx in
            NewSessionSheet(preselectedProjectId: ctx.projectId.isEmpty ? nil : ctx.projectId)
                .environment(env)
                .environment(env.projectList)
                .environment(env.registry)
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPalette(selectedSession: $selectedSession)
                .environment(env)
                .environment(env.projectList)
        }
        .sheet(isPresented: $showInbox) {
            NavigationStack {
                InboxView(feed: env.inboxFeed, selectedSession: $selectedSession)
                    .frame(minWidth: 640, minHeight: 540)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showInbox = false }
                                .keyboardShortcut(.cancelAction)
                                .keyboardShortcut(.defaultAction)
                        }
                    }
            }
            .environment(env)
        }
        .sheet(isPresented: $showGlobalSearch) {
            GlobalSearchSheet(selectedSession: $selectedSession)
                .environment(env)
        }
        .sheet(isPresented: $showWorktreeJanitor) {
            WorktreeJanitorSheet()
                .environment(env)
        }
        .onReceive(NotificationCenter.default.publisher(for: .swarmShowWorktreeJanitor)) { _ in
            showWorktreeJanitor = true
        }
        .onAppear {
            if !env.settings.hasCompletedOnboarding {
                showOnboarding = true
            }
            if !didRestoreSelection {
                didRestoreSelection = true
                if let id = env.settings.lastSelectedSessionId,
                   let session = try? env.sessionsRepo.find(id: id) {
                    selectedSession = session
                }
            }
        }
        .onChange(of: selectedSession?.id) { _, newId in
            // Persist for the next launch and speculatively warm the
            // workspace so opening any tab in this session is instant.
            env.settings.lastSelectedSessionId = newId
            env.saveSettings()
            if let session = selectedSession {
                let ws = env.gitWorkspace(for: session.worktreePath)
                Task { await ws.reloadAll() }
            }
        }
        .focusedSceneValue(SwarmActions.self, SwarmActions(
            newSession: { newSessionProjectId = selectedSession?.projectId ?? "" },
            addProject: { NotificationCenter.default.post(name: .swarmAddProject, object: nil) },
            commandPalette: { showCommandPalette = true },
            selectTab: { raw in
                NotificationCenter.default.post(name: .swarmSelectTab, object: raw)
            },
            refresh: { NotificationCenter.default.post(name: .swarmRefresh, object: nil) }
        ))
    }
}

struct NewSessionContext: Identifiable {
    let projectId: String
    var id: String { projectId }
}

extension Notification.Name {
    static let swarmNewSession = Notification.Name("ClaudeSwarm.NewSession")
    static let swarmCommandPalette = Notification.Name("ClaudeSwarm.CommandPalette")
    static let swarmShowWorktreeJanitor = Notification.Name("ClaudeSwarm.ShowWorktreeJanitor")
}
