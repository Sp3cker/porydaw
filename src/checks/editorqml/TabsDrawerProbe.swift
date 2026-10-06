import Foundation
@testable import PorydawApp
@testable import PorydawAppPresentation
import PorydawDocument
import QtBridge

@MainActor
@QtBridgeable
public final class TabsDrawerProbe: QmlInstantiableStatus {
    private weak var watchedDocument: DocumentSession?

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
        state.lanes.hiddenLanes = [
            .init(track: 1, controller: 7),
            .init(track: 0, controller: 80),
        ]
        EditorViewStatePreferences.save(state, store: PreferencesStore())
    }

    public func savedLaneRange(track: Int, controller: Int) -> Int {
        EditorViewStatePreferences.loadLanes(store: PreferencesStore())
            .laneRanges["cc:\(track):\(controller)"] ?? -1
    }

    public func savedHiddenOrder() -> String {
        EditorViewStatePreferences.loadLanes(store: PreferencesStore()).hiddenLanes.map {
            "\($0.track):\($0.controller)"
        }.joined(separator: ",")
    }
    public func liveLaneCosmetics() -> String {
        guard let session = qmlChildren.compactMap({ $0 as? ShellPresenter }).first?.session,
            let lanes = session.workspace?.viewport.editorViewState.lanes,
            let encoded = EditorViewStatePreferences.encodeLanes(lanes)
        else { return "" }
        return String(decoding: encoded, as: UTF8.self)
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
    public func projectTreeFingerprint(root: String) -> String {
        let rootURL = URL(fileURLWithPath: root, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(atPath: root) else { return "" }
        var paths: [String] = []
        for case let relative as String in enumerator {
            let url = rootURL.appendingPathComponent(relative)
            guard let properties = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            else { return "" }
            guard properties.isSymbolicLink != true, properties.isRegularFile == true else { continue }
            if relative != "settings.plist" { paths.append(relative) }
        }
        guard !paths.isEmpty else { return "" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for relative in paths.sorted() {
            guard let data = try? Data(contentsOf: rootURL.appendingPathComponent(relative))
            else { return "" }
            for byte in relative.utf8 {
                hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
            }
            for byte in data {
                hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
            }
        }
        return "\(paths.count):\(String(hash, radix: 16))"
    }

    public func watchSelectedDocument() -> Bool {
        watchedDocument =
            qmlChildren.compactMap { $0 as? ShellPresenter }
            .first?.session.selectedDocument
        return watchedDocument != nil
    }

    public func watchedDocumentReleased() -> Bool {
        watchedDocument.map(\.isClosed) ?? true
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
            label == "mus_route101" || label == "mus_route102"
        else { return false }
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
            label == "mus_route101" || label == "mus_route102"
        else { return false }
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
    public func moveSoundAside(projectRoot: String) -> Bool {
        guard !projectRoot.isEmpty, projectRoot == ShellQmlBootstrap().projectRoot else { return false }
        let sound = URL(fileURLWithPath: projectRoot).appendingPathComponent("sound")
        let aside = URL(fileURLWithPath: projectRoot).appendingPathComponent("sound.catalog-outage")
        guard !FileManager.default.fileExists(atPath: aside.path) else { return false }
        do {
            try FileManager.default.moveItem(at: sound, to: aside)
            return true
        } catch {
            return false
        }
    }

    public func restoreSound(projectRoot: String) -> Bool {
        guard !projectRoot.isEmpty, projectRoot == ShellQmlBootstrap().projectRoot else { return false }
        let sound = URL(fileURLWithPath: projectRoot).appendingPathComponent("sound")
        let aside = URL(fileURLWithPath: projectRoot).appendingPathComponent("sound.catalog-outage")
        guard !FileManager.default.fileExists(atPath: sound.path) else { return false }
        do {
            try FileManager.default.moveItem(at: aside, to: sound)
            return true
        } catch {
            return false
        }
    }

    public func requestShellCatalogRefresh() -> Bool {
        let sessions = qmlChildren.compactMap { $0 as? ShellPresenter }
            .map(\.session).filter(\.projectOpen)
        guard sessions.count == 1,
            sessions[0].projectRoot == ShellQmlBootstrap().projectRoot
        else { return false }
        Task { await sessions[0].refreshVoicegroupCatalog() }
        return true
    }
}
