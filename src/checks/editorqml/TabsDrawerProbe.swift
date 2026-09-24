import Foundation
import QtBridge

@MainActor
@QtBridgeable
public final class TabsDrawerProbe: QmlInstantiableStatus {
    public init() {}

    public func componentComplete() {}

    public func fileFingerprint(path: String) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return "\(data.count):\(String(hash, radix: 16))"
    }

    public func songPath(projectRoot: String, label: String) -> String {
        projectRoot + "/sound/songs/midi/" + label + ".mid"
    }
}
