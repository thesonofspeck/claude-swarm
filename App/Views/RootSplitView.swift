import SwiftUI
import AppCore
import PersistenceKit

struct RootSplitView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var selectedSession: Session?
    @State private var inspectorVisible = true
    @State private var showOnboarding = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedSession: $selectedSession)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
                .background(Palette.bgSidebar)
        } content: {
            DetailView(session: selectedSession)
                .navigationSplitViewColumnWidth(min: 600, ideal: 800)
                .background(Palette.bgBase)
        } detail: {
            if inspectorVisible {
                InspectorView(session: selectedSession)
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
                    .background(Palette.bgSidebar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                IconButton(systemImage: "plus", help: "New session") {}
            }
            ToolbarItem(placement: .primaryAction) {
                IconButton(
                    systemImage: inspectorVisible ? "sidebar.right" : "sidebar.squares.right",
                    help: "Toggle inspector"
                ) {
                    withAnimation(Motion.spring) { inspectorVisible.toggle() }
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingSheet().environmentObject(env)
        }
        .onAppear {
            if !env.settings.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
    }
}
