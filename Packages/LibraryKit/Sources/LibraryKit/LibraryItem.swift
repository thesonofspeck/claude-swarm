import Foundation

public enum LibraryItemKind: String, Codable, CaseIterable, Sendable, Hashable {
    case agent
    case skill
    case command
    case mcp
    case hook
    case claudeMd

    public var displayName: String {
        switch self {
        case .agent: return "Agent"
        case .skill: return "Skill"
        case .command: return "Slash command"
        case .mcp: return "MCP server"
        case .hook: return "Hook"
        case .claudeMd: return "CLAUDE.md"
        }
    }

    public var systemImage: String {
        switch self {
        case .agent: return "person.3"
        case .skill: return "lightbulb"
        case .command: return "command"
        case .mcp: return "server.rack"
        case .hook: return "hook"
        case .claudeMd: return "doc.text"
        }
    }
}

public enum LibrarySource: Equatable, Sendable {
    case builtIn
    case team
    case project
    case userOverride
}

/// One installable thing in the library — an agent file, MCP entry, slash
/// command, hook, etc. Same shape across kinds; payload-specific bits live
/// in the underlying file the manifest points to.
public struct LibraryItem: Codable, Equatable, Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: LibraryItemKind
    public let name: String
    public let description: String?
    public let path: String          // path relative to the library root
    public let version: String?
    public let tags: [String]

    public init(
        id: String, kind: LibraryItemKind, name: String,
        description: String?, path: String, version: String?, tags: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.description = description
        self.path = path
        self.version = version
        self.tags = tags
    }
}

public struct LibraryManifest: Codable, Equatable, Sendable {
    public let version: Int
    public let name: String
    public let description: String?
    public let items: [LibraryItem]

    public init(version: Int = 1, name: String, description: String? = nil, items: [LibraryItem]) {
        self.version = version
        self.name = name
        self.description = description
        self.items = items
    }
}

/// Tracks what's installed into a project. Hashes lets the UI flag "team
/// has updated this — sync."
public struct LibraryLock: Codable, Equatable, Sendable {
    public var installed: [String: Entry]

    public struct Entry: Codable, Equatable, Sendable {
        public var version: String?
        public var sha256: String      // hash of the source file when installed
        public var installedAt: Date

        public init(version: String?, sha256: String, installedAt: Date = Date()) {
            self.version = version
            self.sha256 = sha256
            self.installedAt = installedAt
        }
    }

    public init(installed: [String: Entry] = [:]) {
        self.installed = installed
    }
}
