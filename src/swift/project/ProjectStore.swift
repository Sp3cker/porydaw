import Foundation

/// Serializes project-store operations; native blocking work belongs on ProjectContext's worker.
public actor ProjectStore {
    let projectRoot: String
    var openedSnapshot: ProjectSnapshot?
    var projectContext: ProjectContext?

    /// Creates a store rooted at a lexically normalized project path.
    /// - Parameter projectRoot: The project directory URL.
    public init(projectRoot: URL) {
        self.projectRoot = ProjectFileStore.cleanPath(projectRoot.path)
    }

    /// Runs an operation under the store's actor isolation.
    /// Blocking native calls must be delegated to ProjectContext's worker thread so the
    /// cooperative pool never blocks.
    /// - Parameter op: The asynchronous operation to execute.
    /// - Returns: The operation's result.
    /// - Throws: Any error thrown by the operation.
    public func run<T: Sendable>(_ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await op()
    }
}
