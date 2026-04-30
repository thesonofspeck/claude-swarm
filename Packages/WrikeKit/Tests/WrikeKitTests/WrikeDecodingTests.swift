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

    func testCommentDecode() throws {
        let json = """
        {"kind":"comments","data":[
            {"id":"C1","authorId":"U1","text":"<p>nice</p>","taskId":"T1"}
        ]}
        """
        let env = try JSONDecoder().decode(WrikeEnvelope<WrikeComment>.self, from: Data(json.utf8))
        XCTAssertEqual(env.data.first?.text, "<p>nice</p>")
    }

    func testUserDecode() throws {
        let json = """
        {"kind":"contacts","data":[
            {"id":"U1","firstName":"Ada","lastName":"Lovelace","primaryEmail":"ada@x.com"}
        ]}
        """
        let env = try JSONDecoder().decode(WrikeEnvelope<WrikeUser>.self, from: Data(json.utf8))
        XCTAssertEqual(env.data.first?.displayName, "Ada Lovelace")
    }

    func testTaskMutationEncodes() throws {
        let mutation = WrikeTaskMutation(
            title: "Fix login",
            description: "<p>html</p>",
            importance: "High",
            dates: WrikeTaskMutation.Dates(type: "Planned", duration: 8, start: "2025-01-15T10:00:00", due: "2025-01-16T10:00:00"),
            responsibles: ["U1"],
            customFields: [WrikeCustomField(id: "F1", value: "Engineering")]
        )
        let data = try JSONEncoder().encode(mutation)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(parsed["title"] as? String, "Fix login")
        XCTAssertEqual(parsed["importance"] as? String, "High")
        let dates = parsed["dates"] as? [String: Any]
        XCTAssertEqual(dates?["type"] as? String, "Planned")
        XCTAssertEqual(dates?["duration"] as? Int, 8)
    }
}
