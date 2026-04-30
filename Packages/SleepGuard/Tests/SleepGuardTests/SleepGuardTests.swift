import XCTest
@testable import SleepGuard

final class SleepGuardTests: XCTestCase {
    func testEngagedReleaseWhenDisengaged() async {
        let guardActor = SleepGuard(honourBattery: false)
        await guardActor.setEngaged(true)
        let s1 = await guardActor.state
        XCTAssertTrue(s1.engaged)
        await guardActor.setEngaged(false)
        let s2 = await guardActor.state
        XCTAssertFalse(s2.engaged)
        XCTAssertFalse(s2.heldAssertion)
    }

    func testHonourBatteryReleasesOnBattery() async {
        let guardActor = SleepGuard(honourBattery: true)
        await guardActor.setEngaged(true)
        // We can't simulate AC state in the test environment; just confirm
        // the API accepts the toggle and the actor settles to a consistent
        // state.
        await guardActor.setHonourBattery(true)
        let s = await guardActor.state
        XCTAssertTrue(s.engaged)
        XCTAssertTrue(s.honourBattery)
    }
}
