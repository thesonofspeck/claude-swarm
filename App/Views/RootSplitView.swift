import SwiftUI
import AppCore
import PersistenceKit

struct RootSplitView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var selectedSession: Session?
    @State private var inspectorVisible = true

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedSession: $selectedSession)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } content: {
            DetailView(session: selectedSession)
                .navigationSplitViewColumnWidth(min: 600, ideal: 800)
        } detail: {
            if inspectorVisible {
                InspectorView(session: selectedSession)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {} label: {
                    Image(systemName: "plus")
                }
                .help("New session")
                .keyboardShortcut("n", modifiers: .command)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    inspectorVisible.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle inspector")
            }
        }
    }
}
