import SwiftUI
import PersistenceKit

struct InspectorView: View {
    let session: Session?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let session {
                content(session)
            } else {
                ContentUnavailableView(
                    "No session",
                    systemImage: "info.circle",
                    description: Text("Select a session to see its details.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func content(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Task")
            row("Title", session.taskTitle ?? "—")
            row("Wrike ID", session.taskId ?? "—")

            sectionHeader("Branch")
            row("Branch", session.branch)
            row("Status", session.status.rawValue)

            sectionHeader("Pull Request")
            row("Number", session.prNumber.map { "#\($0)" } ?? "—")

            Spacer()
        }
        .padding(16)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).lineLimit(2).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}
