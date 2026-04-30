import XCTest
@testable import GitKit

final class DiffParserTests: XCTestCase {
    func testParsesSimpleDiff() {
        let unified = """
        diff --git a/foo.txt b/foo.txt
        index e69de29..d95f3ad 100644
        --- a/foo.txt
        +++ b/foo.txt
        @@ -0,0 +1,2 @@
        +hello
        +world
        """
        let files = DiffParser.parse(unified)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].newPath, "foo.txt")
        XCTAssertEqual(files[0].hunks.count, 1)
        XCTAssertEqual(files[0].hunks[0].lines.count, 2)
        XCTAssertEqual(files[0].hunks[0].lines.allSatisfy { $0.kind == .addition }, true)
    }

    func testParsesDeletionAndContext() {
        let unified = """
        diff --git a/x.swift b/x.swift
        --- a/x.swift
        +++ b/x.swift
        @@ -1,3 +1,3 @@
         keep
        -bye
        +hi
         tail
        """
        let files = DiffParser.parse(unified)
        XCTAssertEqual(files.count, 1)
        let lines = files[0].hunks[0].lines
        XCTAssertEqual(lines.map(\.kind), [.context, .deletion, .addition, .context])
        XCTAssertEqual(lines[1].text, "bye")
        XCTAssertEqual(lines[2].text, "hi")
    }
}
