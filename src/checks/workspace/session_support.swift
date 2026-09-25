import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

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
