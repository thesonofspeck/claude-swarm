import XCTest
@testable import AnthropicClient

final class AnthropicClientTests: XCTestCase {
    func testExtractText() throws {
        let json = #"""
        {
          "id": "msg_1",
          "type": "message",
          "role": "assistant",
          "content": [
            { "type": "text", "text": "Hello" },
            { "type": "text", "text": "world" }
          ]
        }
        """#
        let text = try AnthropicClient.extractText(from: Data(json.utf8))
        XCTAssertEqual(text, "Hello\nworld")
    }

    func testExtractTextSkipsNonText() throws {
        let json = #"""
        {
          "content": [
            { "type": "tool_use", "name": "x" },
            { "type": "text", "text": "kept" }
          ]
        }
        """#
        let text = try AnthropicClient.extractText(from: Data(json.utf8))
        XCTAssertEqual(text, "kept")
    }
}
