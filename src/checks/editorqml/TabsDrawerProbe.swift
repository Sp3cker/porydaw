import Foundation
import PorydawApp
import QtBridge

@MainActor
@QtBridgeable
public final class TabsDrawerProbe: QmlInstantiableStatus {
    public init() {}

    public func componentComplete() {}

    public func stageCompleteState() {
        var state = EditorViewState()
        state.chrome.velocity = .init(visible: true, height: 173)
        state.chrome.automation = .init(visible: true, height: 44)
        state.chrome.voiceChanges = .init(visible: true, height: 55)
        state.chrome.activePage = .automation
        let floor = Int((AutomationPagePolicy.seedBaseFontPx * 7 / 3).rounded())
        let ceiling = Int((AutomationPagePolicy.seedBaseFontPx * 32 / 3).rounded())
        state.lanes.laneHeight = (floor + ceiling) / 2
        state.lanes.laneHeights = ["cc:0:74": floor + 3, "cc:1:7": floor + 5]
        state.lanes.laneRanges = ["cc:0:74": 90, "tempo": 100]
        state.lanes.emptyLanes = [.init(track: 0, controller: 74)]
        state.lanes.hiddenLanes = [.init(track: 1, controller: 7),
                                   .init(track: 0, controller: 80)]
        EditorViewStateCodec.save(state, store: PreferencesStore())
    }

    public func savedLaneRange(track: Int, controller: Int) -> Int {
        EditorViewStateCodec.loadLanes(store: PreferencesStore())
            .laneRanges["cc:\(track):\(controller)"] ?? -1
    }

    public func savedHiddenOrder() -> String {
        EditorViewStateCodec.loadLanes(store: PreferencesStore()).hiddenLanes.map {
            "\($0.track):\($0.controller)"
        }.joined(separator: ",")
    }

    public func fileFingerprint(path: String) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return "\(data.count):\(String(hash, radix: 16))"
    }

    public func fileBytesBase64(path: String) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return "" }
        return data.base64EncodedString()
    }

    public func songPath(projectRoot: String, label: String) -> String {
        projectRoot + "/sound/songs/midi/" + label + ".mid"
    }

    public func moveSongAside(projectRoot: String, label: String) -> Bool {
        guard !projectRoot.isEmpty, projectRoot == ShellQmlBootstrap().projectRoot,
              label == "mus_route101" || label == "mus_route102" else { return false }
        let song = URL(fileURLWithPath: songPath(projectRoot: projectRoot, label: label))
        let aside = song.appendingPathExtension("reload-check")
        guard !FileManager.default.fileExists(atPath: aside.path) else { return false }
        do {
            try FileManager.default.moveItem(at: song, to: aside)
            return true
        } catch {
            return false
        }
    }

    public func restoreSong(projectRoot: String, label: String) -> Bool {
        guard !projectRoot.isEmpty, projectRoot == ShellQmlBootstrap().projectRoot,
              label == "mus_route101" || label == "mus_route102" else { return false }
        let song = URL(fileURLWithPath: songPath(projectRoot: projectRoot, label: label))
        let aside = song.appendingPathExtension("reload-check")
        guard !FileManager.default.fileExists(atPath: song.path) else { return false }
        do {
            try FileManager.default.moveItem(at: aside, to: song)
            return true
        } catch {
            return false
        }
    }
}
