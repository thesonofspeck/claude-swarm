import Foundation

/// Resolves an identifier name to one or more declaration sites.
/// Consults `SymbolIndex` first (fast in-memory lookup); only falls
/// back to `git grep -nE` when the index has no entry — which happens
/// during the initial warmup window or for symbols in languages the
/// indexer doesn't yet understand.
public struct SymbolNavigator: Sendable {
    public struct Match: Sendable, Equatable {
        public let path: String      // relative to worktree root
        public let line: Int
        public let snippet: String
        public let source: Source

        public enum Source: String, Sendable {
            case index
            case grep
        }
    }

    public let worktreeRoot: URL
    public let gitExecutable: String
    public let index: SymbolIndex?

    public init(
        worktreeRoot: URL,
        gitExecutable: String = "/usr/bin/git",
        index: SymbolIndex? = nil
    ) {
        self.worktreeRoot = worktreeRoot
        self.gitExecutable = gitExecutable
        self.index = index
    }

    /// Returns up to `limit` declarations of `name`. Empty if none.
    public func definitions(of name: String, limit: Int = 20) async -> [Match] {
        guard isValidIdentifier(name) else { return [] }
        // Index lookup first — O(1) hash hit + a slice.
        if let index {
            let indexed = await index.lookup(name)
            if !indexed.isEmpty {
                // Sort before truncating — `lookup` returns dictionary
                // iteration order, which would make the "first match"
                // nondeterministic across runs.
                return indexed
                    .sorted { ($0.file.path, $0.line) < ($1.file.path, $1.line) }
                    .prefix(limit)
                    .map { Match(symbol: $0, root: worktreeRoot) }
            }
        }

        // git grep fallback. Word-boundary match anchored after a known
        // definition keyword; second pass catches JS/TS/Swift bindings.
        let keywords = "class|struct|enum|protocol|actor|extension|func|typealias|def|function|fn|interface|trait"
        let escaped = name.replacingOccurrences(of: "$", with: "\\$")
        let primary = "\\b(\(keywords))\\s+\(escaped)\\b"
        let matches = await runGitGrep(pattern: primary, limit: limit)
        if !matches.isEmpty { return matches }
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
                    snippet: String(parts[2]).trimmingCharacters(in: .whitespaces),
                    source: .grep
                ))
                if hits.count >= limit { break }
            }
            return hits
        }.value
    }
}

extension SymbolNavigator.Match {
    init(symbol: SymbolIndex.Symbol, root: URL) {
        let rootPath = root.standardizedFileURL.path
        let abs = symbol.file.standardizedFileURL.path
        let rel: String
        if abs == rootPath {
            rel = abs
        } else if abs.hasPrefix(rootPath + "/") {
            rel = String(abs.dropFirst(rootPath.count + 1))
        } else {
            rel = abs
        }
        self.init(path: rel, line: symbol.line, snippet: symbol.kind + " " + symbol.name, source: .index)
    }
}
