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
        var iterator = pulse.events().makeAsyncIterator()

        pulse.ping([])
        // Run a competing 60 ms timer; whichever wins, the pulse must
        // not have emitted anything.
        let raced = await withTaskGroup(of: Set<WorkspaceInvalidation>?.self) { group in
            group.addTask {
                try? await Task.sleep(for: .milliseconds(60))
                return nil
            }
            group.addTask {
                await iterator.next()
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        XCTAssertNil(raced, "Empty pings should not schedule a flush")
    }
}
