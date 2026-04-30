import XCTest
@testable import WrikeKit

final class WrikeDecodingTests: XCTestCase {
    func testTaskDecodesDescriptionField() throws {
        let json = """
        {"kind":"tasks","data":[
            {"id":"X1","title":"Fix login","description":"<p>HTML body</p>","status":"Active","permalink":"https://w.com/X1"}
        ]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(WrikeEnvelope<WrikeTask>.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.data.count, 1)
        XCTAssertEqual(envelope.data[0].descriptionText, "<p>HTML body</p>")
        XCTAssertEqual(envelope.data[0].title, "Fix login")
    }

    func testFoldersDecode() throws {
        let json = """
        {"kind":"folders","data":[{"id":"F1","title":"Engineering","scope":"WsFolder","permalink":"https://w.com/F1"}]}
        """
        let envelope = try JSONDecoder().decode(WrikeEnvelope<WrikeFolder>.self, from: Data(json.utf8))
        XCTAssertEqual(envelope.data.first?.title, "Engineering")
    }
}
