import XCTest
@testable import WrikeKit

final class WrikeFilterTests: XCTestCase {
    private func makeTask(
        id: String = UUID().uuidString,
        title: String,
        descriptionText: String? = nil,
        status: String = "Active",
        importance: String? = "Normal"
    ) -> WrikeTask {
        WrikeTask(
            id: id,
            title: title,
            descriptionText: descriptionText,
            status: status,
            permalink: nil,
            importance: importance,
            updatedDate: nil
        )
    }

    func testEmptyFilterPassesEverything() {
        let tasks = [makeTask(title: "A"), makeTask(title: "B")]
        let result = WrikeFilter().apply(to: tasks)
        XCTAssertEqual(result.count, 2)
    }

    func testQueryMatchesTitleCaseInsensitive() {
        let tasks = [
            makeTask(title: "Fix login redirect"),
            makeTask(title: "Add dark mode toggle"),
            makeTask(title: "Refactor auth")
        ]
        var filter = WrikeFilter()
        filter.query = "LOGIN"
        XCTAssertEqual(filter.apply(to: tasks).count, 1)
    }

    func testQueryMatchesDescription() {
        let tasks = [
            makeTask(title: "Backend", descriptionText: "<p>Investigate the cookie path</p>"),
            makeTask(title: "Frontend", descriptionText: "<p>Polish the spinner</p>")
        ]
        var filter = WrikeFilter()
        filter.query = "cookie"
        XCTAssertEqual(filter.apply(to: tasks).count, 1)
    }

    func testQueryMatchesId() {
        let tasks = [
            makeTask(id: "WK-100", title: "First"),
            makeTask(id: "WK-200", title: "Second")
        ]
        var filter = WrikeFilter()
        filter.query = "wk-200"
        XCTAssertEqual(filter.apply(to: tasks).first?.title, "Second")
    }

    func testStatusFilterIntersection() {
        let tasks = [
            makeTask(title: "A", status: "Active"),
            makeTask(title: "B", status: "Completed"),
            makeTask(title: "C", status: "Deferred")
        ]
        var filter = WrikeFilter()
        filter.statuses = ["Active", "Deferred"]
        let result = filter.apply(to: tasks)
        XCTAssertEqual(result.map(\.title), ["A", "C"])
    }

    func testImportanceFilter() {
        let tasks = [
            makeTask(title: "A", importance: "High"),
            makeTask(title: "B", importance: "Normal"),
            makeTask(title: "C", importance: "Low")
        ]
        var filter = WrikeFilter()
        filter.importances = ["High"]
        XCTAssertEqual(filter.apply(to: tasks).map(\.title), ["A"])
    }

    func testHideCompletedDropsCompletedAndCancelled() {
        let tasks = [
            makeTask(title: "A", status: "Active"),
            makeTask(title: "B", status: "Completed"),
            makeTask(title: "C", status: "Cancelled"),
            makeTask(title: "D", status: "Deferred")
        ]
        var filter = WrikeFilter()
        filter.hideCompleted = true
        XCTAssertEqual(filter.apply(to: tasks).map(\.title), ["A", "D"])
    }

    func testCombinedQueryAndStatus() {
        let tasks = [
            makeTask(title: "Fix login", status: "Active"),
            makeTask(title: "Fix logout", status: "Completed"),
            makeTask(title: "Refactor auth", status: "Active")
        ]
        var filter = WrikeFilter()
        filter.query = "fix"
        filter.statuses = ["Active"]
        XCTAssertEqual(filter.apply(to: tasks).map(\.title), ["Fix login"])
    }
}
