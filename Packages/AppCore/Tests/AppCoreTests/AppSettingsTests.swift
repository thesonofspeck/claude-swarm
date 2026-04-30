import XCTest
@testable import AppCore

final class AppSettingsTests: XCTestCase {
    func testQuietHoursDailyWindow() {
        var s = AppSettings()
        s.quietHoursEnabled = true
        s.quietHoursStartMinute = 9 * 60   // 09:00
        s.quietHoursEndMinute = 17 * 60    // 17:00
        XCTAssertTrue(s.isInQuietHours(now: at(hour: 12, minute: 0)))
        XCTAssertFalse(s.isInQuietHours(now: at(hour: 18, minute: 0)))
        XCTAssertFalse(s.isInQuietHours(now: at(hour: 8, minute: 59)))
    }

    func testQuietHoursOvernight() {
        var s = AppSettings()
        s.quietHoursEnabled = true
        s.quietHoursStartMinute = 19 * 60   // 19:00
        s.quietHoursEndMinute = 8 * 60      // 08:00 next day
        XCTAssertTrue(s.isInQuietHours(now: at(hour: 22, minute: 30)))
        XCTAssertTrue(s.isInQuietHours(now: at(hour: 3, minute: 0)))
        XCTAssertFalse(s.isInQuietHours(now: at(hour: 9, minute: 0)))
        XCTAssertFalse(s.isInQuietHours(now: at(hour: 18, minute: 59)))
    }

    func testQuietHoursDisabled() {
        var s = AppSettings()
        s.quietHoursEnabled = false
        s.quietHoursStartMinute = 0
        s.quietHoursEndMinute = 24 * 60
        XCTAssertFalse(s.isInQuietHours(now: at(hour: 12, minute: 0)))
    }

    private func at(hour: Int, minute: Int) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = 1; c.day = 15
        c.hour = hour; c.minute = minute
        return Calendar(identifier: .gregorian).date(from: c)!
    }
}
