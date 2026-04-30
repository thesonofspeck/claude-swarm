import SwiftUI
import AppKit
import QuickLook

/// Minimal QuickLook bridge — shows the panel for a single URL when set,
/// hides it when nil. Use as a `.background` view on a tab.
struct QuickLookPreview: View {
    @Binding var url: URL?

    var body: some View {
        QLPanelBridge(url: $url)
            .frame(width: 0, height: 0)
    }
}

private struct QLPanelBridge: NSViewRepresentable {
    @Binding var url: URL?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.url = url
        context.coordinator.refresh()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var url: URL?
        private weak var panel: QLPreviewPanel?

        func attach() {}

        func refresh() {
            guard let url else {
                QLPreviewPanel.shared().orderOut(nil)
                return
            }
            let panel = QLPreviewPanel.shared()!
            panel.dataSource = self
            panel.delegate = self
            self.panel = panel
            if !panel.isVisible {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.reloadData()
            }
            _ = url
        }

        // MARK: QLPreviewPanelDataSource
        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { url == nil ? 0 : 1 }
        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            url as NSURL?
        }
    }
}
