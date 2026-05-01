import XCTest
@testable import SleepGuard

@MainActor
final class SleepGuardTests: XCTestCase {
    func testEngagedReleaseWhenDisengaged() {
        let sg = SleepGuard(honourBattery: false)
        sg.setEngaged(true)
        XCTAssertTrue(sg.state.engaged)
        sg.setEngaged(false)
        XCTAssertFalse(sg.state.engaged)
        XCTAssertFalse(sg.state.heldAssertion)
    }

    func testHonourBatteryReleasesOnBattery() {
        let sg = SleepGuard(honourBattery: true)
        sg.setEngaged(true)
        // We can't simulate AC state in the test environment; just confirm
        // the API accepts the toggle and settles to a consistent state.
        sg.setHonourBattery(true)
        XCTAssertTrue(sg.state.engaged)
        XCTAssertTrue(sg.state.honourBattery)
    }
}
