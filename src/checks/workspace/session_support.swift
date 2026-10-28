import Foundation
import PorydawCore
import PorydawCoreCheckNative
import PorydawDocument
import PorydawPlayback

public func operationFailureMessage(_ error: Error) -> String? {
    guard let serviceError = error as? ProjectServiceError else { return nil }
    switch serviceError {
    case .serviceClosed, .bankConflict: return nil
    case .operationFailed(let message): return message
    case .songNotPlayable(let label): return "No playable song named \(label)."
    case .songMidiUnavailable(_, let path): return "Cannot read \(path)"
    case .songBankUnavailable(_, _, let reason): return reason
    case .songSaveUnavailable(_, let path): return "Cannot write \(path)"
    }
}

public func noteOffSample(_ timeline: PlaybackTimeline, key: UInt8) -> UInt64? {
    timeline.events.first { $0.type == 0x8 && $0.data0 == key }?.sample
}

public func bytes(at path: String) -> Data? {
    try? Data(contentsOf: URL(fileURLWithPath: path))
}

public func configLineBytes(at path: String, label: String) -> Data? {
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
