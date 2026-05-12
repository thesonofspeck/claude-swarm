import Foundation

/// In-memory project symbol index. Scans the worktree's source files
/// with a couple of broad regexes and builds a `name → [Symbol]` map so
/// Cmd+click lookups in the editor are O(1) instead of paying a
/// `git grep` per click. Falls back to git grep for misses (Navigator
/// orchestrates the two layers).
///
/// Storage is in-memory only — rebuilding on launch costs ~50ms per
/// 1000 source files and we'd rather pay that than persist a stale
/// index across runs.
public actor SymbolIndex {
    public struct Symbol: Sendable, Equatable, Hashable {
        public let name: String
        public let file: URL
        public let line: Int
        public let kind: String

        public init(name: String, file: URL, line: Int, kind: String) {
            self.name = name
            self.file = file
            self.line = line
            self.kind = kind
        }
    }

    public let worktreeRoot: URL

    private var byFile: [URL: (mtime: Date, symbols: [Symbol])] = [:]
    private var byName: [String: [Symbol]] = [:]
    private var refreshing: Bool = false

    public init(worktreeRoot: URL) {
        self.worktreeRoot = worktreeRoot
    }

    // MARK: - Public surface

    public var fileCount: Int { byFile.count }
    public var symbolCount: Int { byName.values.reduce(0) { $0 + $1.count } }
    public var isRefreshing: Bool { refreshing }

    public func lookup(_ name: String) -> [Symbol] {
        byName[name] ?? []
    }

    /// Walk the worktree, parse files whose mtime moved, drop entries
    /// for files that disappeared, and rebuild the `byName` map. Safe to
    /// call repeatedly — overlapping refreshes coalesce.
    public func refresh() async {
        if refreshing { return }
        refreshing = true
        defer { refreshing = false }
        let snapshot = byFile.mapValues { $0.mtime }
        let result = await Self.scan(root: worktreeRoot, existing: snapshot)
        merge(result)
    }

    private struct ScanResult: Sendable {
        var parsedByFile: [URL: (mtime: Date, symbols: [Symbol])]
        var reusedURLs: Set<URL>
    }

    private func merge(_ result: ScanResult) {
        // Keep entries for unchanged files (mtime matched), replace
        // changed ones, drop missing ones.
        var newByFile: [URL: (mtime: Date, symbols: [Symbol])] = [:]
        for url in result.reusedURLs {
            if let existing = byFile[url] {
                newByFile[url] = existing
            }
        }
        for (url, parsed) in result.parsedByFile {
            newByFile[url] = parsed
        }
        byFile = newByFile

        var newByName: [String: [Symbol]] = [:]
        for (_, value) in byFile {
            for s in value.symbols {
                newByName[s.name, default: []].append(s)
            }
        }
        byName = newByName
    }

    // MARK: - Scanner (nonisolated; runs on background)

    private static let sourceExtensions: Set<String> = [
        "swift", "py", "js", "jsx", "ts", "tsx", "mjs", "cjs",
        "go", "rs", "java", "kt", "rb", "c", "cc", "cpp", "h", "hpp",
        "m", "mm", "scala", "ex", "exs", "php", "cs", "lua", "dart"
    ]

    private static let ignoredDirs: Set<String> = [
        ".git", ".build", "node_modules", ".swiftpm", "DerivedData",
        "vendor", "target", "dist", "build", "__pycache__",
        ".next", ".cache", ".venv", "venv", ".tox", ".gradle"
    ]

    private static let declRegex: NSRegularExpression = {
        // Optional access modifiers then a keyword + identifier. Covers
        // Swift, Python, JS/TS, Go, Rust, Java/Kotlin, etc.
        let pattern = #"\b(class|struct|enum|protocol|actor|extension|func|typealias|def|function|fn|interface|trait|impl|type)\s+([A-Za-z_$][A-Za-z0-9_$]*)"#
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    private static let bindingRegex: NSRegularExpression = {
        // `const|let|var name = …` for JS/TS/Swift top-level bindings
        // (only when the line *starts* with the keyword to avoid local
        // scope noise).
        let pattern = #"^\s*(?:export\s+(?:default\s+)?)?(const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*[:=]"#
        return try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }()

    private static let maxFileBytes: Int = 500 * 1024

    private static func scan(root: URL, existing: [URL: Date]) async -> ScanResult {
        await Task.detached {
            let fm = FileManager.default
            var parsed: [URL: (mtime: Date, symbols: [Symbol])] = [:]
            var reused: Set<URL> = []

            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
            ) else {
                return ScanResult(parsedByFile: [:], reusedURLs: [])
            }

            for case let url as URL in enumerator {
                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
                let isDir = resourceValues?.isDirectory ?? false
                if isDir {
                    if ignoredDirs.contains(url.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                let ext = url.pathExtension.lowercased()
                guard sourceExtensions.contains(ext) else { continue }
                let size = resourceValues?.fileSize ?? 0
                guard size <= maxFileBytes else { continue }
                let mtime = resourceValues?.contentModificationDate ?? Date()
                if let prior = existing[url], prior == mtime {
                    reused.insert(url)
                    continue
                }
                let symbols = parseFile(at: url)
                parsed[url] = (mtime, symbols)
            }
            return ScanResult(parsedByFile: parsed, reusedURLs: reused)
        }.value
    }

    private static func parseFile(at url: URL) -> [Symbol] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        var out: [Symbol] = []
        let ns = text as NSString
        // Build a line-start table once per file so character index → line
        // is O(log N) instead of O(N) per match.
        var lineStarts: [Int] = [0]
        let length = ns.length
        var i = 0
        while i < length {
            let r = ns.range(of: "\n", options: [], range: NSRange(location: i, length: length - i))
            if r.location == NSNotFound { break }
            lineStarts.append(r.location + 1)
            i = r.location + 1
        }
        let full = NSRange(location: 0, length: length)

        let declMatches = declRegex.matches(in: text, options: [], range: full)
        for m in declMatches where m.numberOfRanges >= 3 {
            let kind = ns.substring(with: m.range(at: 1))
            let name = ns.substring(with: m.range(at: 2))
            let line = lineNumber(for: m.range.location, in: lineStarts)
            out.append(Symbol(name: name, file: url, line: line, kind: kind))
        }

        let bindingMatches = bindingRegex.matches(in: text, options: [], range: full)
        for m in bindingMatches where m.numberOfRanges >= 3 {
            let kind = ns.substring(with: m.range(at: 1))
            let name = ns.substring(with: m.range(at: 2))
            let line = lineNumber(for: m.range.location, in: lineStarts)
            out.append(Symbol(name: name, file: url, line: line, kind: kind))
        }
        return out
    }

    private static func lineNumber(for location: Int, in lineStarts: [Int]) -> Int {
        // Binary search for the largest line-start <= location.
        var lo = 0
        var hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= location { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }
}
