import Foundation
import WrikeKit

/// Translates session lifecycle events into Wrike status transitions. Quiet
/// no-op when no token is configured or no Wrike folder is mapped.
public actor WrikeBridge {
    public let mapper: WrikeStatusMapper
    private let client: WrikeClient

    public init(client: WrikeClient) {
        self.client = client
        self.mapper = WrikeStatusMapper(client: client)
    }

    public func transition(taskId: String, to t: WrikeTransition) async {
        guard !taskId.isEmpty else { return }
        guard await client.hasToken() else { return }
        _ = try? await mapper.transition(taskId: taskId, to: t)
    }
}
