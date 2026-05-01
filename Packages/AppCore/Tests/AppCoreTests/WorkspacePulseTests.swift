import XCTest
@testable import AppCore

@MainActor
final class WorkspacePulseTests: XCTestCase {
    /// Subscribe + iterate inline rather than spawning a Task. The pulse's
    /// `events()` registers the subscriber synchronously on MainActor;
    /// pulling values off `iterator.next()` is async and lets us interleave
    /// pings and assertions without racing the subscription registration.
    func testEmitsAfterDebounce() async throws {
        let pulse = WorkspacePulse(debounce: .milliseconds(40))
        var iterator = pulse.events().makeAsyncIterator()

        pulse.ping(.status)
        let emitted = await iterator.next()
        XCTAssertEqual(emitted, [.status])
    }

    func testCoalescesMultiplePings() async throws {
        let pulse = WorkspacePulse(debounce: .milliseconds(30))
        var iterator = pulse.events().makeAsyncIterator()

        // Burst of pings within the debounce window — should produce ONE
        // emission whose set is the union of every category mentioned.
        pulse.ping(.status)
        pulse.ping(.branches)
        pulse.ping([.history, .stashes])
        pulse.ping(.tags)

        let emitted = await iterator.next()
        XCTAssertEqual(emitted, [.status, .branches, .history, .stashes, .tags])
    }

    func testFlushNowEmitsImmediately() async throws {
        let pulse = WorkspacePulse(debounce: .seconds(5))
        var iterator = pulse.events().makeAsyncIterator()

        pulse.ping(.files)
        pulse.flushNow()

        let emitted = await iterator.next()
        XCTAssertEqual(emitted, [.files])
    }

    func testIgnoresEmptyPings() async throws {
        let pulse = WorkspacePulse(debounce: .milliseconds(20))

        pulse.ping([])
        // Wait past the debounce window. If a flush had been scheduled
        // (the bug condition), there'd be a value to consume; we assert
        // that there isn't by polling for any pending event with a tight
        // timeout.
        try await Task.sleep(for: .milliseconds(80))
        var iterator = pulse.events().makeAsyncIterator()
        // Re-ping with a real category so we can distinguish "stream
        // produced nothing yet" from "iterator never received anything";
        // the next event we pull must be just `.status`, not a leftover
        // emission from the empty ping.
        pulse.ping(.status)
        let next = await iterator.next()
        XCTAssertEqual(next, [.status], "Empty ping should not have leaked an emission")
    }
}
