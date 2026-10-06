import Foundation
@testable import PorydawApp
@testable import PorydawAppPresentation
import PorydawCoreCheckNative
@testable import PorydawDocument

@MainActor
func runEditorViewStateChecks(_ report: CheckReport, store: PreferencesStore) {
    let codec = "workspace/EditorViewStatePreferences::laneBlob"
    let defaults = EditorViewStatePreferences.decodeLanes(Data())
    report.expectEqual(
        expected: EditorLaneState(), actual: defaults, cppID: codec,
        what: "empty lane blob defaults without touching drawer chrome")
    for malformed in ["not JSON", "[]", "null", "\"text\""] {
        report.expectEqual(
            expected: EditorLaneState(),
            actual: EditorViewStatePreferences.decodeLanes(Data(malformed.utf8)),
            cppID: codec, what: "non-object or invalid JSON defaults lane fields")
    }

    let minimum = Int((AutomationPagePolicy.seedBaseFontPx * 7 / 3).rounded())
    let maximum = Int((AutomationPagePolicy.seedBaseFontPx * 32 / 3).rounded())
    let source = """
        {"laneHeight":5,"laneHeights":{"tempo":\(minimum + 2),"cc:0:74":5,"cc:0:80":99999999,
         "cc:00:7":12,"voice:0:5":12,"cc:16:7":12,"cc:0:300":12},
         "laneRanges":{"tempo":90,"cc:1:7":64,"cc:2:3":128,"cc:3:4":-1},
         "emptyLanes":[{"track":0,"cc":1},{"track":16,"cc":1},{"track":2,"cc":300},"bad"],
         "hiddenLanes":[{"track":1,"cc":7},{"track":0,"cc":74},{"track":1,"cc":7}],
         "unheardOf":true}
        """
    let decoded = EditorViewStatePreferences.decodeLanes(Data(source.utf8))
    report.expectEqual(
        expected: minimum, actual: decoded.laneHeight, cppID: codec,
        what: "stored lane height clamps to font-derived floor")
    report.expectEqual(
        expected: ["tempo": minimum + 2, "cc:0:74": minimum, "cc:0:80": maximum],
        actual: decoded.laneHeights, cppID: codec,
        what: "row heights clamp at both bounds and reject bad grammar")
    report.expectEqual(
        expected: ["tempo": 90, "cc:1:7": 64], actual: decoded.laneRanges,
        cppID: codec, what: "valid ranges survive and out-of-range values drop")
    report.expectEqual(
        expected: 0,
        actual: EditorViewStatePreferences.decodeLanes(Data("{\"laneHeight\":0}".utf8)).laneHeight,
        cppID: codec, what: "zero lane height keeps the layout default")
    report.expectEqual(
        expected: maximum,
        actual: EditorViewStatePreferences.decodeLanes(Data("{\"laneHeight\":99999999}".utf8))
            .laneHeight, cppID: codec,
        what: "large lane height clamps to font-derived ceiling")
    report.expectEqual(
        expected: Set([EditorLaneState.Lane(track: 0, controller: 1)]),
        actual: decoded.emptyLanes, cppID: codec,
        what: "invalid and repeated empty lanes do not create extra lanes")
    report.expectEqual(
        expected: [.init(track: 1, controller: 7), .init(track: 0, controller: 74)],
        actual: decoded.hiddenLanes, cppID: codec,
        what: "hidden-lane order survives without duplicates")
    if let encoded = EditorViewStatePreferences.encodeLanes(decoded) {
        report.expectEqual(
            expected: decoded, actual: EditorViewStatePreferences.decodeLanes(encoded), cppID: codec,
            what: "canonical lane blob round-trips every supported member")
    } else {
        report.fail(codec, "valid lane state must encode")
    }

    let order = "workspace/WorkspaceTabRecipe::restore"
    let recipe = WorkspaceTabRecipe(
        projectPath: "/music", orderedSongs: ["A", "gone", "B", "A"],
        selectedSong: "gone")
    report.expectEqual(
        expected: ["A", "B"], actual: recipe.normalized(available: ["A", "B"]).orderedSongs,
        cppID: order, what: "missing and repeated songs are skipped in strip order")
    report.expectEqual(
        expected: "A", actual: recipe.normalized(available: ["A", "B"]).selectedSong,
        cppID: order, what: "missing selection chooses first restored song")

    let restored = recipe.normalized(available: ["A", "B"])
    EditorViewStatePreferences.saveTabs(restored, store: store)
    report.expectEqual(
        expected: restored, actual: EditorViewStatePreferences.loadTabs(store: store),
        cppID: order, what: "application preferences retain tab order and selection")
    EditorViewStatePreferences.saveLanes(decoded, store: store)
    report.expectEqual(
        expected: decoded, actual: EditorViewStatePreferences.loadLanes(store: store),
        cppID: codec, what: "application preferences retain one lane blob")
    let stagedLanes = CheckEnvironment.fixturePath("settings.plist").flatMap {
        stagedPlist($0)["editorDrawer.automationLanes"] as? Data
    }
    report.expectEqual(
        expected: decoded,
        actual: stagedLanes.map(EditorViewStatePreferences.decodeLanes) ?? EditorLaneState(),
        cppID: codec,
        what: "the staged scratch domain persists the exact lane blob independently of the model")

    let chrome = "workspace/EditorViewStatePreferences::chrome"
    var seededChrome = EditorDrawerChromeState()
    seededChrome.velocity = DrawerChromeSection(visible: true, height: 173)
    seededChrome.automation = DrawerChromeSection(visible: false, height: 197)
    seededChrome.voiceChanges.height = 201
    seededChrome.activePage = .velocity
    EditorViewStatePreferences.saveChrome(seededChrome, store: store)
    report.expectEqual(
        expected: seededChrome,
        actual: EditorViewStatePreferences.loadChrome(store: store),
        cppID: chrome, what: "the combined chrome and lane state round-trips through preferences")
    report.expectEqual(
        expected: decoded, actual: EditorViewStatePreferences.loadLanes(store: store),
        cppID: chrome, what: "saving chrome leaves the lane members unchanged")
    report.expectEqual(
        expected: DrawerSectionKind.velocity,
        actual: EditorViewStatePreferences.loadChrome(store: store).activePage,
        cppID: chrome, what: "the active page string round-trips")
    store.remove(key: "editorDrawer.velocityVisible")
    store.setString(key: "editorDrawer.automationHeight", value: "wrong")
    let partialChrome = EditorViewStatePreferences.loadChrome(store: store)
    report.expectEqual(
        expected: false, actual: partialChrome.velocity.visible, cppID: chrome,
        what: "missing drawer members default without losing the lane members")
    report.expectEqual(
        expected: nil as Int?, actual: partialChrome.automation.height, cppID: chrome,
        what: "a wrong-typed height defaults to the layout default")
    report.expectEqual(
        expected: decoded, actual: EditorViewStatePreferences.loadLanes(store: store),
        cppID: chrome, what: "the lane members survive missing chrome fields")
    EditorViewStatePreferences.saveChrome(seededChrome, store: store)
    let stored = "workspace/EditorViewStatePreferences::persistedState"
    guard let plistPath = CheckEnvironment.fixturePath("settings.plist") else {
        report.fail(stored, "missing staged settings plist")
        return
    }
    let laneKey = "editorDrawer.automationLanes"
    var full = EditorLaneState()
    full.laneHeight = minimum + 11
    full.laneHeights = ["tempo": minimum, "cc:0:74": maximum]
    full.laneRanges = ["tempo": 90, "cc:1:7": 64]
    full.emptyLanes = [.init(track: 0, controller: 1), .init(track: 3, controller: 10)]
    full.hiddenLanes = [.init(track: 0, controller: 74), .init(track: 1, controller: 7)]
    var fullChrome = EditorDrawerChromeState()
    fullChrome.velocity = .init(visible: true, height: 173)
    fullChrome.automation = .init(visible: false, height: 64)
    fullChrome.voiceChanges = .init(visible: true, height: 97)
    for page in [DrawerSectionKind.velocity, .voiceChanges, .automation] {
        fullChrome.activePage = page
        EditorViewStatePreferences.saveChrome(fullChrome, store: store)
        EditorViewStatePreferences.saveLanes(full, store: store)
        let fresh = PreferencesStore()
        let reloadedChrome = EditorViewStatePreferences.loadChrome(store: fresh)
        report.expectEqual(
            expected: fullChrome.velocity.visible, actual: reloadedChrome.velocity.visible,
            cppID: stored, what: "stored Velocity visibility restores for \(page.name)")
        report.expectEqual(
            expected: fullChrome.automation.visible, actual: reloadedChrome.automation.visible,
            cppID: stored, what: "stored Automation visibility restores for \(page.name)")
        report.expectEqual(
            expected: fullChrome.voiceChanges.visible, actual: reloadedChrome.voiceChanges.visible,
            cppID: stored, what: "stored Voice Changes visibility restores for \(page.name)")
        report.expectEqual(
            expected: fullChrome.velocity.height, actual: reloadedChrome.velocity.height,
            cppID: stored, what: "stored Velocity height restores for \(page.name)")
        report.expectEqual(
            expected: fullChrome.automation.height, actual: reloadedChrome.automation.height,
            cppID: stored, what: "stored Automation height restores for \(page.name)")
        report.expectEqual(
            expected: fullChrome.voiceChanges.height, actual: reloadedChrome.voiceChanges.height,
            cppID: stored, what: "stored Voice Changes height restores for \(page.name)")
        report.expectEqual(
            expected: page, actual: reloadedChrome.activePage,
            cppID: stored, what: "the stored active page restores as \(page.name)")
        let reloadedLanes = EditorViewStatePreferences.loadLanes(store: fresh)
        report.expectEqual(
            expected: full.laneHeight, actual: reloadedLanes.laneHeight,
            cppID: stored, what: "the stored lane height restores for \(page.name)")
        report.expectEqual(
            expected: full.laneHeights, actual: reloadedLanes.laneHeights,
            cppID: stored, what: "the stored lane heights restore for \(page.name)")
        report.expectEqual(
            expected: full.laneRanges, actual: reloadedLanes.laneRanges,
            cppID: stored, what: "the stored lane ranges restore for \(page.name)")
        report.expectEqual(
            expected: full.emptyLanes, actual: reloadedLanes.emptyLanes,
            cppID: stored, what: "the stored empty lanes restore for \(page.name)")
        report.expectEqual(
            expected: full.hiddenLanes, actual: reloadedLanes.hiddenLanes,
            cppID: stored, what: "the ordered hidden lanes restore for \(page.name)")
    }
    fullChrome.velocity.height = nil
    fullChrome.automation.height = nil
    fullChrome.voiceChanges.height = nil
    fullChrome.activePage = .voiceChanges
    EditorViewStatePreferences.saveChrome(fullChrome, store: store)
    let bareStore = PreferencesStore()
    let bareChrome = EditorViewStatePreferences.loadChrome(store: bareStore)
    report.expectEqual(
        expected: fullChrome, actual: bareChrome, cppID: stored,
        what: "all unset heights and the voice page restore from saved preferences")
    report.expectEqual(
        expected: nil, actual: bareChrome.velocity.height, cppID: stored,
        what: "the optional Velocity height restores unset")
    report.expectEqual(
        expected: nil, actual: bareChrome.automation.height, cppID: stored,
        what: "the optional Automation height restores unset")
    report.expectEqual(
        expected: nil, actual: bareChrome.voiceChanges.height, cppID: stored,
        what: "the optional Voice Changes height restores unset")
    report.expectEqual(
        expected: full, actual: EditorViewStatePreferences.loadLanes(store: bareStore),
        cppID: stored, what: "optional drawer heights leave every stored lane member intact")

    EditorViewStatePreferences.saveChrome(seededChrome, store: store)
    enum LanePoison {
        case bytes(Data)
        case text(String)
    }
    let poisonCases: [(String, LanePoison, EditorLaneState)] = [
        ("invalid JSON", .bytes(Data("{ not json".utf8)), EditorLaneState()),
        ("empty bytes", .bytes(Data()), EditorLaneState()),
        ("array JSON", .bytes(Data("[1,2]".utf8)), EditorLaneState()),
        ("wrong type", .text("seventy-four"), EditorLaneState()),
        ("grammar", .bytes(Data(source.utf8)), decoded),
        ("zero height", .bytes(Data("{\"laneHeight\":0}".utf8)), EditorLaneState()),
        (
            "clamped height", .bytes(Data("{\"laneHeight\":99999999}".utf8)),
            {
                var state = EditorLaneState()
                state.laneHeight = maximum
                return state
            }()
        ),
    ]
    for (name, poison, expected) in poisonCases {
        EditorViewStatePreferences.saveLanes(full, store: store)
        switch poison {
        case .bytes(let value):
            store.setStoredObject(value, key: laneKey)
        case .text(let value):
            store.setStoredObject(value, key: laneKey)
        }
        store.synchronize()
        let persisted = stagedPlist(plistPath)[laneKey]
        let staged: Bool
        switch poison {
        case .bytes(let value): staged = (persisted as? Data) == value
        case .text(let value): staged = (persisted as? String) == value
        }
        report.expect(staged, cppID: stored, message: "the staged \(name) lane poison reaches disk")
        let fresh = PreferencesStore()
        fresh.synchronize()
        let reloadedChrome = EditorViewStatePreferences.loadChrome(store: fresh)
        report.expectEqual(
            expected: seededChrome, actual: reloadedChrome,
            cppID: stored, what: "stored chrome survives \(name) lane data")
        let loaded = EditorViewStatePreferences.loadLanes(store: fresh)
        report.expectEqual(
            expected: expected, actual: loaded,
            cppID: stored, what: "stored \(name) defaults or clamps only lane members")
        fresh.synchronize()
        let after = store.storedObject(key: laneKey)
        let unchanged: Bool
        switch poison {
        case .bytes(let value): unchanged = (after as? Data) == value
        case .text(let value): unchanged = (after as? String) == value
        }
        report.expect(
            unchanged, cppID: stored,
            message: "reading stored \(name) does not rewrite poisoned lane data")
    }
    EditorViewStatePreferences.saveLanes(full, store: store)

    let reset = "swiftcore/PreferencesStore::reset"
    store.setString(key: "windowState", value: "debugger")
    store.setInt(key: "songFilterSort", value: 1)
    store.setBool(key: "followPlayhead", value: false)
    store.synchronize()
    let keys = [
        "lastProjectDir", "lastOpenSongs", "lastSongLabel",
        "editorDrawer.automationLanes", "editorDrawer.velocityVisible",
        "editorDrawer.velocityHeight", "editorDrawer.automationVisible",
        "editorDrawer.automationHeight", "editorDrawer.voiceChangesVisible",
        "editorDrawer.voiceChangesHeight", "editorDrawer.activePage",
        "windowState", "songFilterSort",
        "followPlayhead",
    ]
    let seeded = keys.allSatisfy { store.hasValue(key: $0) }
    let resetSucceeded = store.resetPreferences()
    let cleared = keys.allSatisfy { !store.hasValue(key: $0) }
    report.expect(
        seeded && resetSucceeded && cleared, cppID: reset,
        message: "resetPreferences clears every stored key")
    let clearedStore = PreferencesStore()
    report.expectEqual(
        expected: EditorDrawerChromeState(),
        actual: EditorViewStatePreferences.loadChrome(store: clearedStore),
        cppID: stored, what: "an empty preference domain restores default drawer chrome")
    report.expectEqual(
        expected: EditorLaneState(), actual: EditorViewStatePreferences.loadLanes(store: clearedStore),
        cppID: stored, what: "an empty preference domain restores default lane preferences")
}

/// The staged settings plist as written to disk.
private func stagedPlist(_ path: String) -> [String: Any] {
    guard let data = FileManager.default.contents(atPath: path),
        // ReadOptions is Int on macOS (C++ interop) and an OptionSet on Linux.
        let plist = try? PropertyListSerialization.propertyList(
            from: data, options: .init(), format: nil) as? [String: Any]
    else { return [:] }
    return plist
}
