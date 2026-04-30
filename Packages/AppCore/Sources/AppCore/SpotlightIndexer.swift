import Foundation
#if canImport(CoreSpotlight)
import CoreSpotlight
import UniformTypeIdentifiers
#endif
import PersistenceKit
import MemoryService

/// Index sessions and memory entries into Spotlight so the user can search
/// the system-wide search field. Runs incrementally — repeated calls re-index
/// changed/new items only.
public actor SpotlightIndexer {
    public let domain = "com.claudeswarm.search"
    private let projects: ProjectRepository
    private let sessions: SessionRepository
    private let memory: MemoryStore

    public init(projects: ProjectRepository, sessions: SessionRepository, memory: MemoryStore) {
        self.projects = projects
        self.sessions = sessions
        self.memory = memory
    }

    public func reindexAll() async {
        #if canImport(CoreSpotlight)
        let index = CSSearchableIndex.default()
        var items: [CSSearchableItem] = []
        items.append(contentsOf: sessionItems())
        items.append(contentsOf: await memoryItems())
        try? await index.indexSearchableItems(items)
        #endif
    }

    public func clearAll() async {
        #if canImport(CoreSpotlight)
        try? await CSSearchableIndex.default()
            .deleteSearchableItems(withDomainIdentifiers: [domain])
        #endif
    }

    #if canImport(CoreSpotlight)
    private func sessionItems() -> [CSSearchableItem] {
        let projectMap = Dictionary(uniqueKeysWithValues: ((try? projects.all()) ?? []).map { ($0.id, $0) })
        let allSessions = (try? sessions.allByProject().values.flatMap { $0 }) ?? []
        return allSessions.map { session in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = session.taskTitle ?? session.branch
            attrs.contentDescription = projectMap[session.projectId].map { "Project: \($0.name) · \(session.branch)" }
                ?? session.branch
            attrs.keywords = ["claude", "session", session.branch]
            return CSSearchableItem(
                uniqueIdentifier: "session:\(session.id)",
                domainIdentifier: domain,
                attributeSet: attrs
            )
        }
    }

    private func memoryItems() async -> [CSSearchableItem] {
        let entries = (try? await memory.list(namespace: nil, limit: 500)) ?? []
        return entries.map { entry in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = entry.key ?? String(entry.content.prefix(60))
            attrs.contentDescription = entry.content
            attrs.keywords = ["claude", "memory", entry.namespace] + entry.tagsArray
            return CSSearchableItem(
                uniqueIdentifier: "memory:\(entry.id)",
                domainIdentifier: domain,
                attributeSet: attrs
            )
        }
    }
    #endif
}
