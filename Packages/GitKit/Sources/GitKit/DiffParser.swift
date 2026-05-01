import Foundation

public enum DiffLineKind: Equatable, Sendable {
    case context
    case addition
    case deletion
    case hunkHeader
    case fileHeader
}

public struct DiffLine: Equatable, Sendable {
    public let kind: DiffLineKind
    public let oldNumber: Int?
    public let newNumber: Int?
    public let text: String
}

public struct DiffHunk: Equatable, Sendable {
    public let header: String
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    public let lines: [DiffLine]
}

public struct DiffFile: Equatable, Sendable {
    public let oldPath: String?
    public let newPath: String?
    public let isBinary: Bool
    public let hunks: [DiffHunk]
}

public enum DiffParser {
    public static func parse(_ unified: String) -> [DiffFile] {
        var files: [DiffFile] = []
        var currentOldPath: String?
        var currentNewPath: String?
        var currentHunks: [DiffHunk] = []
        var hunkLines: [DiffLine] = []
        var hunkHeader: String?
        var hunkOldStart = 0, hunkOldCount = 0, hunkNewStart = 0, hunkNewCount = 0
        var oldLineNum = 0, newLineNum = 0
        var isBinary = false

        func flushHunk() {
            guard let header = hunkHeader else { return }
            currentHunks.append(DiffHunk(
                header: header,
                oldStart: hunkOldStart, oldCount: hunkOldCount,
                newStart: hunkNewStart, newCount: hunkNewCount,
                lines: hunkLines
            ))
            hunkHeader = nil
            hunkLines = []
        }

        func flushFile() {
            flushHunk()
            if currentOldPath != nil || currentNewPath != nil || isBinary {
                files.append(DiffFile(
                    oldPath: currentOldPath,
                    newPath: currentNewPath,
                    isBinary: isBinary,
                    hunks: currentHunks
                ))
            }
            currentOldPath = nil
            currentNewPath = nil
            currentHunks = []
            isBinary = false
        }

        for raw in unified.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("diff --git ") {
                flushFile()
            } else if line.hasPrefix("--- ") {
                let p = String(line.dropFirst(4))
                currentOldPath = p == "/dev/null" ? nil : stripABPrefix(p)
            } else if line.hasPrefix("+++ ") {
                let p = String(line.dropFirst(4))
                currentNewPath = p == "/dev/null" ? nil : stripABPrefix(p)
            } else if line.hasPrefix("Binary files ") {
                isBinary = true
            } else if line.hasPrefix("@@") {
                flushHunk()
                hunkHeader = line
                let parsed = parseHunkHeader(line)
                hunkOldStart = parsed.oldStart
                hunkOldCount = parsed.oldCount
                hunkNewStart = parsed.newStart
                hunkNewCount = parsed.newCount
                oldLineNum = parsed.oldStart
                newLineNum = parsed.newStart
            } else if hunkHeader != nil {
                if line.hasPrefix("+") {
                    hunkLines.append(DiffLine(kind: .addition, oldNumber: nil, newNumber: newLineNum, text: String(line.dropFirst())))
                    newLineNum += 1
                } else if line.hasPrefix("-") {
                    hunkLines.append(DiffLine(kind: .deletion, oldNumber: oldLineNum, newNumber: nil, text: String(line.dropFirst())))
                    oldLineNum += 1
                } else if line.hasPrefix(" ") || line.isEmpty {
                    let text = line.isEmpty ? "" : String(line.dropFirst())
                    hunkLines.append(DiffLine(kind: .context, oldNumber: oldLineNum, newNumber: newLineNum, text: text))
                    oldLineNum += 1
                    newLineNum += 1
                }
            }
        }
        flushFile()
        return files
    }

    private static func stripABPrefix(_ path: String) -> String {
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            return String(path.dropFirst(2))
        }
        return path
    }

    private static func parseHunkHeader(_ header: String) -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
        // @@ -oldStart,oldCount +newStart,newCount @@
        let trimmed = header.replacingOccurrences(of: "@@", with: "")
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
        var oldStart = 0, oldCount = 1, newStart = 0, newCount = 1
        for part in parts {
            if part.hasPrefix("-") {
                let nums = part.dropFirst().split(separator: ",")
                oldStart = Int(nums[0]) ?? 0
                if nums.count > 1 { oldCount = Int(nums[1]) ?? 1 }
            } else if part.hasPrefix("+") {
                let nums = part.dropFirst().split(separator: ",")
                newStart = Int(nums[0]) ?? 0
                if nums.count > 1 { newCount = Int(nums[1]) ?? 1 }
            }
        }
        return (oldStart, oldCount, newStart, newCount)
    }
}
