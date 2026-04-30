import Foundation

public struct SessionSpec: Equatable, Sendable {
    public let id: String
    public let projectId: String
    public let projectName: String
    public let repoURL: URL
    public let worktreeURL: URL
    public let branch: String
    public let baseBranch: String
    public let taskId: String?
    public let taskTitle: String?
    public let initialPrompt: String?
    public let claudeExecutable: String
    public let claudeArguments: [String]
    public let environment: [String: String]
    public let transcriptURL: URL

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        projectName: String,
        repoURL: URL,
        worktreeURL: URL,
        branch: String,
        baseBranch: String,
        taskId: String? = nil,
        taskTitle: String? = nil,
        initialPrompt: String? = nil,
        claudeExecutable: String = "/usr/local/bin/claude",
        claudeArguments: [String] = [],
        environment: [String: String] = [:],
        transcriptURL: URL
    ) {
        self.id = id
        self.projectId = projectId
        self.projectName = projectName
        self.repoURL = repoURL
        self.worktreeURL = worktreeURL
        self.branch = branch
        self.baseBranch = baseBranch
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.initialPrompt = initialPrompt
        self.claudeExecutable = claudeExecutable
        self.claudeArguments = claudeArguments
        self.environment = environment
        self.transcriptURL = transcriptURL
    }
}

public enum BranchNamer {
    public static func slug(_ s: String) -> String {
        let lowered = s.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            return "-"
        }
        let joined = String(allowed)
        let collapsed = joined.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(40))
    }

    public static func branch(taskId: String?, title: String, prefix: String = "feat") -> String {
        let suffix = slug(title)
        if let id = taskId, !id.isEmpty {
            return "\(prefix)/\(id)-\(suffix)"
        }
        return "\(prefix)/\(suffix)"
    }
}
