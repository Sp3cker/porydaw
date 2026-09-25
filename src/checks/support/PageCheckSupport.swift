import Foundation
import PorydawApp
import PorydawCore

// MARK: - Synchronous concurrency helper (canonical)

// The single MainActor RunLoop-pump used by the page checks. Timeout is 25.0s:
// the pre-existing canonical value from workspace/session_support.swift, which
// the four retired per-page clones (20s each) now adopt.

internal enum RunBlockingError: Error {
    case timeout
}

@MainActor
internal func runBlocking<T>(_ operation: @escaping @MainActor () async throws -> T) throws -> T {
    var outcome: Result<T, Error>?
    Task { @MainActor in
        do {
            outcome = .success(try await operation())
        } catch {
            outcome = .failure(error)
        }
    }
    let deadline = Date().addingTimeInterval(25.0)
    while outcome == nil {
        if Date() > deadline {
            throw RunBlockingError.timeout
        }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    guard let result = outcome else {
        throw RunBlockingError.timeout
    }
    return try result.get()
}

// MARK: - Shared document snapshot

/// The document facts one transaction claim compares against: the revision,
/// the history identity (the Swift analogue of the legacy undo index) and the
/// undo/redo reachability. Merged from the three identical per-page copies.
@MainActor
internal struct DocumentSnapshot: Equatable {
    var revision: UInt64
    var identity: DocumentIdentity
    var canUndo: Bool
    var canRedo: Bool

    init(_ document: SongDocument) {
        revision = document.revision
        identity = document.history.currentIdentity
        canUndo = document.history.canUndo
        canRedo = document.history.canRedo
    }
}
