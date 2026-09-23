import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Synchronous Concurrency Helper

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
    return try outcome!.get()
}

internal func operationFailureMessage(_ error: Error) -> String? {
    guard let serviceError = error as? ProjectServiceError,
          case let .operationFailed(message) = serviceError else {
        return nil
    }
    return message
}

internal func noteOffSample(_ timeline: PlaybackTimeline, key: UInt8) -> UInt64? {
    timeline.events.first { $0.type == 0x8 && $0.data0 == key }?.sample
}

internal func bytes(at path: String) -> Data? {
    try? Data(contentsOf: URL(fileURLWithPath: path))
}

internal func configLineBytes(at path: String, label: String) -> Data? {
    guard let contents = bytes(at: path) else { return nil }
    let prefix = Data("\(label).mid:".utf8)
    var lineStart = contents.startIndex

    while lineStart != contents.endIndex {
        let lineEnd = contents[lineStart...].firstIndex(of: 0x0A) ?? contents.endIndex
        let line = contents[lineStart..<lineEnd]
        if line.starts(with: prefix) {
            return Data(line)
        }
        guard lineEnd != contents.endIndex else { return nil }
        lineStart = contents.index(after: lineEnd)
    }

    return nil
}
