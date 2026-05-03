import Foundation
import Observation
import SessionCore
import PersistenceKit

@MainActor
@Observable
public final class RunningSessionRegistry {
    public private(set) var specs: [String: SessionSpec] = [:]
    public private(set) var foregroundSessionId: String?

    public init() {}

    public func register(_ spec: SessionSpec) {
        specs[spec.id] = spec
    }

    public func remove(id: String) {
        specs.removeValue(forKey: id)
        if foregroundSessionId == id { foregroundSessionId = nil }
    }

    public func setForeground(_ id: String?) {
        foregroundSessionId = id
    }

    public func spec(for id: String) -> SessionSpec? {
        specs[id]
    }
}
