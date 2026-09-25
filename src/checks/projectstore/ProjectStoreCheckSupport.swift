import Foundation

/// NSCondition protects every access to state; the unchecked boundary is
/// confined to this one synchronous wait/signal box.
internal final class ConditionBox<State: Sendable>: @unchecked Sendable {
    private let condition = NSCondition()
    private var state: State

    init(_ state: State) { self.state = state }

    func update(_ body: (inout State) -> Void) {
        condition.lock()
        body(&state)
        condition.signal()
        condition.unlock()
    }

    func wait(while pending: (State) -> Bool, timeout: TimeInterval) -> State {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while pending(state) && condition.wait(until: deadline) {}
        return state
    }
}

internal func awaitValue<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
) -> Result<Value, Error>? {
    let result = ConditionBox<Result<Value, Error>?>(nil)
    Thread.detachNewThread {
        Task {
            do {
                let value = try await operation()
                result.update { $0 = .success(value) }
            } catch {
                result.update { $0 = .failure(error) }
            }
        }
    }
    return result.wait(while: { $0 == nil }, timeout: 60)
}

/// The single temp-project-copy fixture behind the projectstore suites: copies
/// the staged fixture project to a unique temporary directory, runs `body`
/// with the copy, then removes it. Consolidates editFixture,
/// loadBankFixture, saveFixture, bankLogicFixture, bankFixture,
/// serviceBankCase's copy, withExportFixture's copy, contextFixtureCopy and
/// editingRichSource's copy. The `stagedFile` guard names the staged file the
/// suite needs; suites that report their own missing-fixture errors keep their
/// guards and only route the copy through here.
internal enum TempProjectCopyError: Error {
    case missingStagedProject(String)
}

internal func withTempProjectCopy(
    prefix: String,
    stagedFile: String = "sound/voicegroups/fixture_rich.inc",
    _ body: (URL) throws -> Void
) throws {
    guard let fixtureRoot = CheckEnvironment.fixtureRoot,
          let staged = CheckEnvironment.fixturePath(stagedFile),
          FileManager.default.fileExists(atPath: staged) else {
        throw TempProjectCopyError.missingStagedProject(stagedFile)
    }
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(
        "\(prefix)-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: copy) }
    try FileManager.default.copyItem(at: URL(filePath: fixtureRoot), to: copy)
    try body(copy)
}

/// MainActor variant for suites whose fixture body awaits MainActor services
/// (ProjectService opens in ExportChecks and BankLeasesChecks).
@MainActor
internal func withTempProjectCopy(
    prefix: String,
    stagedFile: String = "sound/voicegroups/fixture_rich.inc",
    _ body: @MainActor (URL) throws -> Void
) throws {
    guard let fixtureRoot = CheckEnvironment.fixtureRoot,
          let staged = CheckEnvironment.fixturePath(stagedFile),
          FileManager.default.fileExists(atPath: staged) else {
        throw TempProjectCopyError.missingStagedProject(stagedFile)
    }
    let copy = FileManager.default.temporaryDirectory.appendingPathComponent(
        "\(prefix)-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: copy) }
    try FileManager.default.copyItem(at: URL(filePath: fixtureRoot), to: copy)
    try body(copy)
}
