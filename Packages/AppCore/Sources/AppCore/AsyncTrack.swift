import Foundation
import SwiftUI

/// Tiny `@Observable`-style helper for the loading + error pattern that
/// every tab in the app was repeating:
///
/// ```swift
/// @StateObject private var ops = AsyncTracker()
/// // …
/// .task { await ops.run { try await load() } }
/// // ops.isLoading and ops.error drive your UI
/// ```
@MainActor
public final class AsyncTracker: ObservableObject {
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var error: String?

    public init() {}

    /// Runs the work, flips `isLoading`, captures any thrown error into
    /// `error` as a string. Returns the work's result on success or nil
    /// on failure (or cancellation).
    @discardableResult
    public func run<T>(
        _ work: () async throws -> T
    ) async -> T? {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            return try await work()
        } catch is CancellationError {
            return nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return nil
        }
    }

    public func clearError() { error = nil }
}
