import XCTest
@testable import AppCore

@MainActor
final class WorkspacePulseTests: XCTestCase {
    func testEmitsAfterDebounce() async throws {
        let pulse = WorkspacePulse(debounce: .milliseconds(40))
        let received = Box<[Set<WorkspaceInvalidation>]>(value: [])

        let task = Task {
            for await ev in pulse.events() {
                received.value.append(ev)
            }
        }

        pulse.ping(.status)
        // Should not emit before the debounce.
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(received.value.count, 0)

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(received.value.count, 1)
        XCTAssertEqual(received.value.first, [.status])

        task.cancel()
    }

    func testCoalescesMultiplePings() async throws {
        let pulse = WorkspacePulse(debounce: .milliseconds(30))
        let received = Box<[Set<WorkspaceInvalidation>]>(value: [])

        let task = Task {
            for await ev in pulse.events() {
                received.value.append(ev)
            }
        }

        // Burst of pings within the debounce window — should produce ONE
        // emission whose set is the union of every category mentioned.
        pulse.ping(.status)
        pulse.ping(.branches)
        pulse.ping([.history, .stashes])
        try await Task.sleep(for: .milliseconds(10))
        pulse.ping(.tags)

        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(received.value.count, 1, "Burst should coalesce to a single emission")
        let emitted = received.value.first ?? []
        XCTAssertEqual(emitted, [.status, .branches, .history, .stashes, .tags])

        task.cancel()
    }

    func testFlushNowEmitsImmediately() async throws {
        let pulse = WorkspacePulse(debounce: .seconds(5))
        let received = Box<[Set<WorkspaceInvalidation>]>(value: [])

        let task = Task {
            for await ev in pulse.events() {
                received.value.append(ev)
            }
        }

        pulse.ping(.files)
        pulse.flushNow()

        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(received.value, [[.files]])

        task.cancel()
    }

    func testIgnoresEmptyPings() async throws {
        let pulse = WorkspacePulse(debounce: .milliseconds(20))
        let received = Box<Int>(value: 0)

        let task = Task {
            for await _ in pulse.events() {
                received.value += 1
            }
        }

        pulse.ping([])
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(received.value, 0, "Empty pings should not schedule a flush")

        task.cancel()
    }
}

private final class Box<T> {
    var value: T
    init(value: T) { self.value = value }
}
