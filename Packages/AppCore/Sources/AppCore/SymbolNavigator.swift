import Foundation

/// Resolves an identifier name to one or more declaration sites in the
/// worktree using `git grep -nE`. Cheap enough to run on every Cmd+click;
/// no persistent index needed. Catches Swift/Go/Rust/Python/JS/TS
/// declarations via a broad keyword regex — preferring correctness over
/// completeness on languages we don't know well yet.
public struct SymbolNavigator: Sendable {
    public struct Match: Sendable, Equatable {
        public let path: String      // relative to worktree root
        public let line: Int
        public let snippet: String
    }

    public let worktreeRoot: URL
    public let gitExecutable: String

    public init(worktreeRoot: URL, gitExecutable: String = "/usr/bin/git") {
        self.worktreeRoot = worktreeRoot
        self.gitExecutable = gitExecutable
    }

    /// Returns up to `limit` declarations of `name`. Empty if none.
    public func definitions(of name: String, limit: Int = 20) async -> [Match] {
        guard isValidIdentifier(name) else { return [] }
        // Word-boundary match for the identifier, anchored after a known
        // definition keyword. Allows optional access modifiers.
        let keywords = "class|struct|enum|protocol|actor|extension|func|typealias|def|function|fn|interface|trait"
        let escaped = name.replacingOccurrences(of: "$", with: "\\$")
        let pattern = "\\b(\(keywords))\\s+\(escaped)\\b"
        let matches = await runGitGrep(pattern: pattern, limit: limit)
        if !matches.isEmpty { return matches }
        // Fallback: `const|let|var name =` for JS/TS/Swift top-level
        // bindings that aren't preceded by a definition keyword.
        let assign = "\\b(const|let|var)\\s+\(escaped)\\b"
        return await runGitGrep(pattern: assign, limit: limit)
    }

    private func isValidIdentifier(_ s: String) -> Bool {
        guard !s.isEmpty, s.count < 200 else { return false }
        let allowed = CharacterSet(charactersIn: "_$").union(.alphanumerics)
        guard s.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        guard let first = s.first else { return false }
        return !first.isNumber
    }

    private func runGitGrep(pattern: String, limit: Int) async -> [Match] {
        let directory = worktreeRoot
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) else {
            return []
        }
        let executable = gitExecutable
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = [
                "grep", "-nE", "-I",
                "--max-count=\(limit)",
                "--", pattern
            ]
            process.currentDirectoryURL = directory
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            do { try process.run() } catch { return [] }
            process.waitUntilExit()
            let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
            let text = String(decoding: data, as: UTF8.self)
            var hits: [Match] = []
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count == 3, let lineNumber = Int(parts[1]) else { continue }
                hits.append(Match(
                    path: String(parts[0]),
                    line: lineNumber,
                    snippet: String(parts[2]).trimmingCharacters(in: .whitespaces)
                ))
                if hits.count >= limit { break }
            }
            return hits
        }.value
    }
}
