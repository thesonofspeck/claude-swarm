import Foundation

/// Single funnel for every git mutation the app performs. The UI subscribes
/// to `events` for toolbar status, the inspector activity feed, and error
/// banners. Anything that calls `git` and the user can see should go through
/// this so the experience stays consistent (one spinner, one error surface,
/// one cancel control).
public actor GitOperationCenter {
    public let runner: GitRunner

    private var continuations: [UUID: AsyncStream<GitOperationEvent>.Continuation] = [:]
    private(set) public var inFlight: [UUID: GitOperationKind] = [:]

    public init(runner: GitRunner = GitRunner()) {
        self.runner = runner
    }

    /// Multicast event stream. Each subscriber gets every event from
    /// subscription onward; historical events are not replayed.
    public func events() -> AsyncStream<GitOperationEvent> {
        let id = UUID()
        let (stream, cont) = AsyncStream<GitOperationEvent>.makeStream()
        register(id: id, continuation: cont)
        cont.onTermination = { [weak self] _ in
            Task { await self?.unregister(id: id) }
        }
        return stream
    }

    public func run<T: Sendable>(
        _ kind: GitOperationKind,
        detail: String? = nil,
        _ body: @Sendable (GitRunner) async throws -> T
    ) async throws -> T {
        let id = UUID()
        inFlight[id] = kind
        emit(GitOperationEvent(id: id, kind: kind, detail: detail, phase: .started))
        do {
            let value = try await body(runner)
            inFlight.removeValue(forKey: id)
            emit(GitOperationEvent(id: id, kind: kind, detail: detail, phase: .succeeded))
            return value
        } catch {
            inFlight.removeValue(forKey: id)
            let msg = (error as? GitError)?.errorDescription ?? "\(error)"
            emit(GitOperationEvent(id: id, kind: kind, detail: detail, phase: .failed(msg)))
            throw error
        }
    }

    public var isBusy: Bool { !inFlight.isEmpty }

    private func register(id: UUID, continuation: AsyncStream<GitOperationEvent>.Continuation) {
        continuations[id] = continuation
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func emit(_ event: GitOperationEvent) {
        for cont in continuations.values { cont.yield(event) }
    }
}
