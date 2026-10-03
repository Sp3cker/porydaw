import Foundation
import QtBridge

@MainActor
@QtBridgeable
public final class SampleStudioVoiceProbe: QmlInstantiableStatus {
    public init() {}
    private var replacedPath: String?
    private var originalBytes: Data?
    public func componentComplete() {}

    public func replaceSource(from: String, to: String) -> Bool {
        do {
            let target = URL(fileURLWithPath: to)
            let original = try Data(contentsOf: target)
            let bytes = try Data(contentsOf: URL(fileURLWithPath: from))
            try bytes.write(to: target, options: .atomic)
            replacedPath = to
            originalBytes = original
            return true
        } catch {
            return false
        }
    }

    public func restoreSource() -> Bool {
        guard let replacedPath, let originalBytes else { return true }
        do {
            try originalBytes.write(to: URL(fileURLWithPath: replacedPath), options: .atomic)
            self.replacedPath = nil
            self.originalBytes = nil
            return true
        } catch {
            return false
        }
    }
}
