import Foundation

public enum GitConfigParser {
    public struct Remote: Equatable, Sendable {
        public let name: String
        public let url: String
        public let owner: String?
        public let repo: String?
    }

    public static func remotes(in repoURL: URL, remoteName: String? = nil) -> [Remote] {
        let configPath = repoURL.appendingPathComponent(".git/config")
        guard let contents = try? String(contentsOf: configPath, encoding: .utf8) else { return [] }
        return parse(contents).filter { remoteName == nil || $0.name == remoteName }
    }

    public static func origin(in repoURL: URL) -> Remote? {
        remotes(in: repoURL, remoteName: "origin").first
    }

    public static func parse(_ text: String) -> [Remote] {
        var out: [Remote] = []
        var currentName: String?
        var currentURL: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[remote "), let name = sectionName(line) {
                if let n = currentName, let u = currentURL {
                    out.append(makeRemote(name: n, url: u))
                }
                currentName = name
                currentURL = nil
            } else if line.hasPrefix("[") {
                if let n = currentName, let u = currentURL {
                    out.append(makeRemote(name: n, url: u))
                }
                currentName = nil
                currentURL = nil
            } else if let value = parseURL(line) {
                currentURL = value
            }
        }
        if let n = currentName, let u = currentURL {
            out.append(makeRemote(name: n, url: u))
        }
        return out
    }

    private static func sectionName(_ line: String) -> String? {
        // [remote "origin"]
        guard let openQuote = line.firstIndex(of: "\""),
              let closeQuote = line.lastIndex(of: "\""),
              openQuote < closeQuote else { return nil }
        return String(line[line.index(after: openQuote)..<closeQuote])
    }

    private static func parseURL(_ line: String) -> String? {
        guard line.hasPrefix("url"), let eq = line.firstIndex(of: "=") else { return nil }
        return String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func makeRemote(name: String, url: String) -> Remote {
        let (owner, repo) = parseGitHubURL(url)
        return Remote(name: name, url: url, owner: owner, repo: repo)
    }

    /// Pulls owner/repo out of common GitHub URL shapes — both
    /// `git@github.com:owner/repo.git` and `https://github.com/owner/repo(.git)`.
    /// The leading anchor `(://|@)` prevents matches on hostnames like
    /// `github.com.evil.com:owner/repo`.
    static func parseGitHubURL(_ url: String) -> (owner: String?, repo: String?) {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        if let range = trimmed.range(of: "(://|@)github\\.com[:/]", options: .regularExpression) {
            let suffix = String(trimmed[range.upperBound...])
                .replacingOccurrences(of: ".git", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parts = suffix.split(separator: "/", maxSplits: 1).map(String.init)
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        return (nil, nil)
    }
}
