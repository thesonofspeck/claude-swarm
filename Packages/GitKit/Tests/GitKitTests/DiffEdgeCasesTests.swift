import XCTest
@testable import GitKit

final class DiffEdgeCasesTests: XCTestCase {
    func testNewFileFromDevNull() {
        let diff = """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,1 @@
        +created
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 1)
        XCTAssertNil(files[0].oldPath)
        XCTAssertEqual(files[0].newPath, "new.txt")
    }

    func testDeletedFile() {
        let diff = """
        diff --git a/gone.txt b/gone.txt
        deleted file mode 100644
        --- a/gone.txt
        +++ /dev/null
        @@ -1,1 +0,0 @@
        -bye
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files[0].oldPath, "gone.txt")
        XCTAssertNil(files[0].newPath)
    }

    func testBinaryFileMarked() {
        let diff = """
        diff --git a/img.png b/img.png
        index 1234..5678 100644
        Binary files a/img.png and b/img.png differ
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isBinary)
    }

    func testMultipleFiles() {
        let diff = """
        diff --git a/x.swift b/x.swift
        --- a/x.swift
        +++ b/x.swift
        @@ -1,1 +1,1 @@
        -old
        +new
        diff --git a/y.swift b/y.swift
        --- a/y.swift
        +++ b/y.swift
        @@ -1,2 +1,2 @@
         keep
        -bye
        +hi
        """
        let files = DiffParser.parse(diff)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].newPath, "x.swift")
        XCTAssertEqual(files[1].newPath, "y.swift")
    }
}
