import CoreFoundation
import Foundation
@testable import PorydawApp
@testable import PorydawAppPresentation
import PorydawCore
import PorydawCoreCheckNative
@testable import PorydawDocument

private func sameSessionPreference(_ lhs: Any?, _ rhs: Any?) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    if let lhs = lhs as? NSNumber, let rhs = rhs as? NSNumber {
        let lhsIsBool = CFGetTypeID(lhs) == CFBooleanGetTypeID()
        let rhsIsBool = CFGetTypeID(rhs) == CFBooleanGetTypeID()
        return lhsIsBool == rhsIsBool && lhs.compare(rhs) == .orderedSame
    }
    if let lhs = lhs as? String, let rhs = rhs as? String { return lhs == rhs }
    if let lhs = lhs as? Data, let rhs = rhs as? Data { return lhs == rhs }
    if let lhs = lhs as? [String], let rhs = rhs as? [String] { return lhs == rhs }
    return (lhs as? NSObject)?.isEqual(rhs) ?? false
}

@MainActor
func runSessionViewStateChecks(
    _ report: CheckReport, store: PreferencesStore,
    fixtureRoot: String
) {
    let id = "swiftcore/ApplicationSession::editorViewState"
    defer { _ = store.resetPreferences() }
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-view-state")
    let recipeID = "workspace/WorkspaceSessionTest::restoreProjectOnly"
    _ = store.resetPreferences()
    store.setString(key: "lastProjectDir", value: root)
    store.setString(key: "lastSongLabel", value: "mus_session_test")
    store.setString(key: "songFilterText", value: "filterme")
    store.setInt(key: "songFilterSort", value: 1)
    var restoredChrome = EditorDrawerChromeState()
    restoredChrome.velocity = .init(visible: true, height: 173)
    restoredChrome.activePage = .velocity
    EditorViewStatePreferences.saveChrome(restoredChrome, store: store)
    var restoredLanes = EditorLaneState()
    restoredLanes.hiddenLanes = [.init(track: 1, controller: 7)]
    EditorViewStatePreferences.saveLanes(restoredLanes, store: store)
    store.synchronize()
    let legacy = EditorViewStatePreferences.loadTabs(store: store)
    report.expectEqual(
        expected: ["mus_session_test"], actual: legacy.orderedSongs,
        cppID: recipeID, what: "a legacy selected-song-only recipe yields one ordered song")
    let sessionKeys = [
        "lastProjectDir", "lastSongLabel", "lastOpenSongs",
        "songFilterText", "songFilterSort", "songFilterCategory",
        "editorDrawer.velocityVisible", "editorDrawer.velocityHeight",
        "editorDrawer.automationVisible", "editorDrawer.automationHeight",
        "editorDrawer.voiceChangesVisible", "editorDrawer.voiceChangesHeight",
        "editorDrawer.activePage", "editorDrawer.automationLanes",
        "windowGeometry", "windowState",
    ]
    func storedSessionKeys() -> [String: Any] {
        var values: [String: Any] = [:]
        for key in sessionKeys {
            guard let value = store.storedObject(key: key) else { continue }
            values[key] = value
        }
        return values
    }
    let beforeRestore = storedSessionKeys()
    report.expect(
        beforeRestore.keys.contains("lastProjectDir")
            && beforeRestore.keys.contains("lastSongLabel")
            && beforeRestore.keys.contains("songFilterText")
            && beforeRestore.keys.contains("songFilterSort")
            && beforeRestore.keys.contains("editorDrawer.activePage")
            && beforeRestore.keys.contains("editorDrawer.automationLanes"),
        cppID: recipeID, message: "the staged preferences contain the recipe, filter and editor keys")
    let restoredShell = ShellPresenter()
    restoredShell.configureSettings(applicationName: "porydaw")
    restoredShell.openStartup()
    let deadline = Date().addingTimeInterval(25)
    while !restoredShell.session.songOpen && restoredShell.session.lastSaveError.isEmpty
        && Date() < deadline
    {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    report.expect(
        restoredShell.session.songOpen && restoredShell.session.songTabs.tabCount == 1,
        cppID: recipeID, message: "startup opens the one legacy selected song as a ready tab")
    report.expectEqual(
        expected: "mus_session_test",
        actual: restoredShell.session.songTabs.selectedPage?.title,
        cppID: recipeID, what: "startup selects the restored legacy song")
    store.synchronize()
    let afterRestore = storedSessionKeys()
    let changedKeys = Set(beforeRestore.keys).union(afterRestore.keys).filter {
        !sameSessionPreference(beforeRestore[$0], afterRestore[$0])
    }.sorted()
    report.expect(
        changedKeys.isEmpty, cppID: recipeID,
        message: "successful live-project restore leaves preferences unchanged; changed: \(changedKeys)")
    restoredShell.session.requestCloseAll()
    let closeDeadline = Date().addingTimeInterval(25)
    while restoredShell.session.songTabs.tabCount > 0 && Date() < closeDeadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    let savedRecipe = EditorViewStatePreferences.loadTabs(store: store)
    report.expectEqual(
        expected: root, actual: savedRecipe.projectPath,
        cppID: recipeID, what: "host close saves the live project path")
    report.expectEqual(
        expected: "mus_session_test", actual: savedRecipe.selectedSong,
        cppID: recipeID, what: "host close saves the selected song label")
    report.expect(
        store.hasValue(key: "lastOpenSongs")
            && savedRecipe.orderedSongs == ["mus_session_test"],
        cppID: recipeID, message: "host close saves the explicit ordered-song key")
    restoredShell.session.hostClosing()
    restoredShell.session.acknowledgeGridDetached()
    EditorViewStatePreferences.saveTabs(
        WorkspaceTabRecipe(
            projectPath: root,
            orderedSongs: ["missing-song", "mus_session_test", "mus_session_test"],
            selectedSong: "other-song"), store: store)
    let ordered = EditorViewStatePreferences.loadTabs(store: store)
    // fceecd88:src/checks/project/identity.cpp:142-155 deduplicates saved labels.
    report.expectEqual(
        expected: ["missing-song", "mus_session_test"],
        actual: ordered.orderedSongs, cppID: recipeID,
        what: "a present ordered recipe is not extended by its selected label")
    let available = ordered.normalized(available: ["mus_session_test"])
    report.expectEqual(
        expected: ["mus_session_test"], actual: available.orderedSongs,
        cppID: recipeID, what: "normalization omits missing and duplicate songs")
    report.expectEqual(
        expected: "mus_session_test", actual: available.selectedSong,
        cppID: recipeID, what: "a missing selected song falls back to the first live tab")
    store.setStoredObject([String](), key: "lastOpenSongs")
    store.setString(key: "lastSongLabel", value: "mus_session_test")
    report.expect(
        store.hasValue(key: "lastOpenSongs"), cppID: recipeID,
        message: "the explicitly empty ordered-song key is present before load")
    // fceecd88:src/checks/project/identity.cpp:174-182 restores a lone selected label.
    report.expectEqual(
        expected: ["mus_session_test"],
        actual: EditorViewStatePreferences.loadTabs(store: store).orderedSongs,
        cppID: recipeID,
        what: "an explicitly empty ordered-song key restores its selected label")
    _ = store.resetPreferences()
    runCompleteEditorViewStateChecks(report: report, store: store, fixtureRoot: fixtureRoot)
    _ = store.resetPreferences()
    runTabReadinessChecks(report: report, store: store, fixtureRoot: fixtureRoot)
    _ = store.resetPreferences()
    var seed = EditorDrawerChromeState()
    seed.velocity = .init(visible: true, height: 173)
    seed.automation = .init(visible: false, height: 64)
    seed.voiceChanges = .init(visible: true, height: 97)
    seed.activePage = .velocity
    var lanes = EditorLaneState()
    let minimum = Int((AutomationPagePolicy.seedBaseFontPx * 7 / 3).rounded())
    lanes.laneHeight = minimum + 11
    lanes.laneHeights = ["tempo": minimum, "cc:0:74": minimum + 21]
    lanes.laneRanges = ["tempo": 90, "cc:1:7": 64]
    lanes.emptyLanes = [.init(track: 0, controller: 1), .init(track: 3, controller: 10)]
    lanes.hiddenLanes = [.init(track: 0, controller: 74), .init(track: 1, controller: 7)]
    EditorViewStatePreferences.saveLanes(lanes, store: store)
    EditorViewStatePreferences.saveChrome(seed, store: store)
    let app = ApplicationSession()
    app.configurePersistence()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    func until(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(25)
        while !predicate() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return predicate()
    }
    app.openProjectAndSong(path: root, label: "mus_session_test")
    guard until({ app.songOpen || !app.lastSaveError.isEmpty }),
        let first = app.songTabs.selectedPage
    else {
        report.fail(id, "first fixture workspace failed to open: \(app.lastSaveError)")
        return
    }
    report.expectEqual(
        expected: seed, actual: first.drawerPresenter().chromeState, cppID: id,
        what: "a fresh tab carries the shared view state before it is ready")
    report.expect(
        first.drawerPresenter().chromeState == seed
            && EditorViewStatePreferences.loadLanes(store: PreferencesStore()) == lanes,
        cppID: id, message: "startup adopts complete persisted drawer and lane state")
    let firstID = first.tabId
    app.openSong(label: "mus_session_test2")
    guard until({ app.songTabs.tabCount == 2 || !app.lastSaveError.isEmpty }),
        let second = app.songTabs.selectedPage, second !== first
    else {
        report.fail(id, "second fixture workspace failed to open: \(app.lastSaveError)")
        return
    }
    report.expectEqual(
        expected: seed, actual: second.drawerPresenter().chromeState, cppID: id,
        what: "the shared view state starts identically on two song tabs")
    report.expect(
        second.drawerPresenter().chromeState == seed
            && EditorViewStatePreferences.loadLanes(store: PreferencesStore()) == lanes,
        cppID: id, message: "second live tab adopts every shared drawer and lane member")
    let automation = DrawerSectionKind.automation.rawValue
    second.drawerPresenter().toggleSection(kind: automation, drawerOwnsFocus: false)
    let changed = second.drawerPresenter().chromeState
    report.expect(
        changed.automation.visible && first.drawerPresenter().chromeState == changed,
        cppID: id, message: "one automation key shows the section on every open tab")
    report.expectEqual(
        expected: DrawerSectionKind.automation, actual: changed.activePage,
        cppID: id, what: "Automation becomes active on the origin drawer")
    report.expectEqual(
        expected: DrawerSectionKind.automation,
        actual: first.drawerPresenter().chromeState.activePage,
        cppID: id, what: "Automation becomes active on the sibling drawer")
    report.expectEqual(
        expected: changed, actual: EditorViewStatePreferences.loadChrome(store: store),
        cppID: id, what: "the shared view state persists once per change")
    let beforeNoOp = EditorViewStatePreferences.loadChrome(store: store)
    second.drawerPresenter().setSectionVisible(
        kind: automation, visible: true,
        drawerOwnsFocus: false)
    report.expect(
        first.drawerPresenter().chromeState == changed
            && second.drawerPresenter().chromeState == changed
            && EditorViewStatePreferences.loadChrome(store: store) == beforeNoOp,
        cppID: id, message: "an unchanged view state writes nothing")
    let velocity = DrawerSectionKind.velocity.rawValue
    second.drawerPresenter().toggleSection(kind: velocity, drawerOwnsFocus: false)
    let focused = second.drawerPresenter().chromeState
    report.expect(
        focused.activePage == .velocity
            && first.drawerPresenter().chromeState == focused,
        cppID: id, message: "the velocity drawer becomes the active page on every tab")
    report.expectEqual(
        expected: DrawerSectionKind.velocity, actual: focused.activePage,
        cppID: id, what: "Velocity becomes active on the origin drawer")
    report.expectEqual(
        expected: DrawerSectionKind.velocity,
        actual: first.drawerPresenter().chromeState.activePage,
        cppID: id, what: "Velocity becomes active on the sibling drawer")
    second.drawerPresenter().setSectionVisible(
        kind: automation, visible: false,
        drawerOwnsFocus: false)
    let hidden = second.drawerPresenter().chromeState
    report.expect(
        !first.drawerPresenter().chromeState.automation.visible,
        cppID: id, message: "a hidden section stays hidden on the sibling tab")
    report.expect(
        hidden.velocity.height == 173 && hidden.activePage == .velocity,
        cppID: id, message: "hiding one section retains the other sections and the active page")
    app.songTabs.selectTab(tabId: firstID)
    second.drawerPresenter().toggleSection(
        kind: DrawerSectionKind.voiceChanges.rawValue,
        drawerOwnsFocus: false)
    let backgroundChange = second.drawerPresenter().chromeState
    report.expectEqual(
        expected: backgroundChange,
        actual: app.songTabs.selectedPage?.drawerPresenter().chromeState,
        cppID: id, what: "a non-selected tab's mutation reaches the selected tab silently")
    report.expectEqual(
        expected: DrawerSectionKind.voiceChanges,
        actual: backgroundChange.activePage,
        cppID: id, what: "Voice Changes becomes active on the origin drawer")
    report.expectEqual(
        expected: DrawerSectionKind.voiceChanges,
        actual: first.drawerPresenter().chromeState.activePage,
        cppID: id, what: "Voice Changes becomes active on the sibling drawer")
    report.expectEqual(
        expected: backgroundChange, actual: EditorViewStatePreferences.loadChrome(store: store),
        cppID: id, what: "background drawer changes persist without selecting that tab")
    let idStored = "workspace/WorkspaceEditorCodecSelfTest::livePersistenceAndFinalClose"
    app.songTabs.selectTab(tabId: second.tabId)
    guard let document = app.selectedDocument?.document else {
        report.fail(idStored, "second fixture document is unavailable")
        return
    }
    let revision = document.revision
    let history = document.history.currentIdentity
    let originalLanes = EditorViewStatePreferences.loadLanes(store: PreferencesStore())
    report.expectEqual(
        expected: lanes, actual: originalLanes, cppID: idStored,
        what: "the live session retains every seeded lane preference after drawer changes")
    let laneKey = "editorDrawer.automationLanes"
    let malformed = Data("{ not json".utf8)
    store.setStoredObject(malformed, key: laneKey)
    store.synchronize()
    report.expect(
        (store.storedObject(key: laneKey) as? Data) == malformed,
        cppID: idStored, message: "live editor poison enters the persisted preference domain")
    let poisoned = PreferencesStore()
    report.expect(
        EditorViewStatePreferences.loadChrome(store: poisoned) == backgroundChange
            && EditorViewStatePreferences.loadLanes(store: poisoned) == EditorLaneState(),
        cppID: idStored, message: "poisoned live editor reload defaults only lane members")
    report.expect(
        (store.storedObject(key: laneKey) as? Data) == malformed,
        cppID: idStored, message: "reading live poisoned lanes leaves the preference unchanged")
    second.drawerPresenter().setSectionBodyHeight(kind: DrawerSectionKind.velocity.rawValue, height: 181)
    let healed = PreferencesStore()
    let canonical = store.storedObject(key: laneKey) as? Data
    let compact = canonical.map { $0.first == 123 && !$0.contains(10) } ?? false
    report.expect(
        compact
            && EditorViewStatePreferences.loadChrome(store: healed) == second.drawerPresenter().chromeState
            && EditorViewStatePreferences.loadLanes(store: healed) == lanes,
        cppID: idStored, message: "real section resize republishes compact lanes with complete chrome")
    let drawer = second.drawerPresenter()
    drawer.setSectionVisible(
        kind: DrawerSectionKind.velocity.rawValue, visible: true,
        drawerOwnsFocus: false)
    drawer.setSectionVisible(
        kind: DrawerSectionKind.automation.rawValue, visible: false,
        drawerOwnsFocus: false)
    drawer.setSectionVisible(
        kind: DrawerSectionKind.voiceChanges.rawValue, visible: true,
        drawerOwnsFocus: false)
    drawer.setSectionBodyHeight(kind: DrawerSectionKind.velocity.rawValue, height: 173)
    drawer.setSectionBodyHeight(kind: DrawerSectionKind.automation.rawValue, height: 64)
    drawer.setSectionBodyHeight(kind: DrawerSectionKind.voiceChanges.rawValue, height: 97)
    drawer.toggleSection(kind: DrawerSectionKind.velocity.rawValue, drawerOwnsFocus: false)
    drawer.toggleSection(kind: DrawerSectionKind.velocity.rawValue, drawerOwnsFocus: false)
    report.expectEqual(
        expected: seed, actual: EditorViewStatePreferences.loadChrome(store: PreferencesStore()),
        cppID: idStored, what: "the full live chrome with all three stored heights persists")
    report.expectEqual(
        expected: seed, actual: first.drawerPresenter().chromeState,
        cppID: idStored, what: "the complete three-section chrome reaches the sibling")
    let completeStore = PreferencesStore()
    report.expect(
        EditorViewStatePreferences.loadChrome(store: completeStore) == seed
            && EditorViewStatePreferences.loadLanes(store: completeStore) == lanes
            && second.drawerPresenter().chromeState == seed
            && first.drawerPresenter().chromeState == seed,
        cppID: idStored, message: "restoring all drawer sections retains every lane member on both tabs")
    drawer.setSectionVisible(
        kind: DrawerSectionKind.automation.rawValue, visible: true,
        drawerOwnsFocus: false)
    drawer.setSectionVisible(
        kind: DrawerSectionKind.voiceChanges.rawValue, visible: false,
        drawerOwnsFocus: false)
    report.expect(
        drawer.chromeState.activePage == .velocity
            && drawer.chromeState.velocity.visible && !drawer.chromeState.voiceChanges.visible,
        cppID: id, message: "hiding Voice Changes keeps Velocity visible and active on the origin")
    report.expect(
        first.drawerPresenter().chromeState.activePage == .velocity
            && first.drawerPresenter().chromeState.velocity.visible,
        cppID: id, message: "hiding Voice Changes keeps Velocity visible and active on the sibling")
    drawer.setSectionVisible(
        kind: DrawerSectionKind.velocity.rawValue, visible: false,
        drawerOwnsFocus: false)
    report.expect(
        drawer.chromeState.activePage == .velocity
            && drawer.chromeState.automation.visible && !drawer.chromeState.velocity.visible,
        cppID: id, message: "hiding Velocity keeps Automation visible and the active page on the origin")
    report.expect(
        first.drawerPresenter().chromeState.activePage == .velocity
            && first.drawerPresenter().chromeState.automation.visible,
        cppID: id, message: "hiding Velocity keeps Automation visible and the active page on the sibling")
    report.expect(
        drawer.chromeState.velocity.height == 173
            && drawer.chromeState.voiceChanges.height == 97,
        cppID: id, message: "the origin preserves hidden Velocity and Voice Changes heights")
    report.expectEqual(
        expected: DrawerSectionKind.velocity,
        actual: first.drawerPresenter().chromeState.activePage,
        cppID: id, what: "the sibling retains Velocity as active after both sections hide")
    report.expectEqual(
        expected: 173, actual: first.drawerPresenter().chromeState.velocity.height,
        cppID: id, what: "the sibling retains hidden Velocity's stored height")
    report.expectEqual(
        expected: 97, actual: first.drawerPresenter().chromeState.voiceChanges.height,
        cppID: id, what: "the sibling retains hidden Voice Changes' stored height")
    drawer.setSectionVisible(
        kind: DrawerSectionKind.velocity.rawValue, visible: true,
        drawerOwnsFocus: false)
    drawer.setSectionVisible(
        kind: DrawerSectionKind.automation.rawValue, visible: false,
        drawerOwnsFocus: false)
    drawer.setSectionVisible(
        kind: DrawerSectionKind.voiceChanges.rawValue, visible: true,
        drawerOwnsFocus: false)
    for kind in [DrawerSectionKind.velocity, .automation, .voiceChanges] {
        drawer.setSectionBodyHeight(kind: kind.rawValue, height: 0)
    }
    drawer.toggleSection(kind: DrawerSectionKind.voiceChanges.rawValue, drawerOwnsFocus: false)
    drawer.toggleSection(kind: DrawerSectionKind.voiceChanges.rawValue, drawerOwnsFocus: false)
    var bare = seed
    bare.velocity.height = nil
    bare.automation.height = nil
    bare.voiceChanges.height = nil
    bare.activePage = .voiceChanges
    report.expectEqual(
        expected: bare, actual: first.drawerPresenter().chromeState,
        cppID: idStored, what: "the live optional-height change reaches the sibling drawer")
    report.expectEqual(
        expected: bare, actual: drawer.chromeState,
        cppID: idStored, what: "the live optional-height change retains all visibility and selects Voice Changes")
    let reopened = PreferencesStore()
    report.expectEqual(
        expected: bare, actual: EditorViewStatePreferences.loadChrome(store: reopened),
        cppID: idStored, what: "the live bare chrome persists with Voice Changes active")
    report.expectEqual(
        expected: lanes, actual: EditorViewStatePreferences.loadLanes(store: reopened),
        cppID: idStored, what: "the live bare chrome transition retains every stored lane member")
    report.expect(
        first.drawerPresenter().chromeState == bare
            && drawer.chromeState == bare
            && EditorViewStatePreferences.loadChrome(store: reopened) == bare
            && EditorViewStatePreferences.loadLanes(store: reopened) == lanes,
        cppID: idStored, message: "unset heights preserve the complete retained shared editor state")
    let unchangedRevision = document.revision == revision
    let unchangedHistory = document.history.currentIdentity == history
    let unchangedDirty = !document.isDirty
    report.expect(
        unchangedRevision && unchangedHistory && unchangedDirty, cppID: idStored,
        message: "drawer-only changes leave the song revision, history and dirty state unchanged")
    app.songTabs.requestClose(tabId: second.tabId)
    report.expect(
        app.songTabs.tabCount == 1 && app.songTabs.selectedId == firstID,
        cppID: idStored, message: "closing the active editor leaves its sibling selected")
    app.songTabs.requestClose(tabId: firstID)
    report.expect(
        app.songTabs.tabCount == 0 && app.songTabs.selectedId == -1,
        cppID: idStored, message: "closing the final editor leaves no live song tab")
    app.openSong(label: "mus_session_test")
    guard until({ app.songTabs.tabCount == 1 || !app.lastSaveError.isEmpty }),
        let returned = app.songTabs.selectedPage
    else {
        report.fail(idStored, "fixture workspace failed to reopen: \(app.lastSaveError)")
        return
    }
    let restored = PreferencesStore()
    report.expect(
        returned.tabId != firstID && returned.drawerPresenter().chromeState == bare
            && EditorViewStatePreferences.loadChrome(store: restored) == bare
            && EditorViewStatePreferences.loadLanes(store: restored) == lanes,
        cppID: idStored, message: "reopened tab restores the complete drawer and ordered hidden lanes")
    report.expect(
        EditorViewStatePreferences.loadLanes(store: restored).hiddenLanes == lanes.hiddenLanes,
        cppID: idStored, message: "reopened editor retains the hidden lane ordering")
}

@MainActor
private func runTabReadinessChecks(
    report: CheckReport, store: PreferencesStore,
    fixtureRoot: String
) {
    let id = "mainwindowrouting/MainWindowRoutingLifecycleTest::freshBind"
    let reloadID = "mainwindowrouting/MainWindowRoutingLifecycleTest::stagedReload"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-tab-readiness")
    let midiURL = URL(fileURLWithPath: root)
        .appendingPathComponent("sound/songs/midi/mus_session_test.mid")
    var seed = EditorViewState()
    seed.chrome.velocity = .init(visible: true, height: 173)
    seed.chrome.automation = .init(visible: true, height: 44)
    seed.chrome.voiceChanges = .init(visible: false, height: 55)
    seed.chrome.activePage = .automation
    seed.lanes.laneHeight = 46
    seed.lanes.laneHeights = ["cc:0:74": 49]
    seed.lanes.laneRanges = ["cc:0:74": 90, "tempo": 100]
    seed.lanes.emptyLanes = [.init(track: 0, controller: 74)]
    seed.lanes.hiddenLanes = [.init(track: 0, controller: 7)]
    EditorViewStatePreferences.save(seed, store: store)
    let app = ApplicationSession()
    app.configurePersistence()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    func until(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(25)
        while !predicate() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return predicate()
    }
    app.openProjectAndSong(path: root, label: "mus_session_test")
    report.expect(
        app.songTabs.tabCount == 0 && !app.songOpen, cppID: id,
        message: "A046 initial real song open has no command-ready tab before completion")
    // The staged fork probe never exists here: rows install only after the
    // document loads, so the whole async window is watched for a probe row.
    var freshSawUnreadyRow = false
    var freshSawExtraRow = false
    guard
        until({
            if app.songTabs.tabCount > 1 { freshSawExtraRow = true }
            if let page = app.songTabs.selectedPage, !page.isReady { freshSawUnreadyRow = true }
            return app.songTabs.tabCount == 1 || !app.lastSaveError.isEmpty
        }),
        let first = app.songTabs.selectedPage
    else {
        report.fail(id, "fresh copied song did not finish opening: \(app.lastSaveError)")
        return
    }
    guard let document = app.selectedDocument else {
        report.fail(id, "fresh tab did not publish its document")
        return
    }
    report.expect(
        !freshSawUnreadyRow && !freshSawExtraRow, cppID: id,
        message: "fresh open installs no probe row: the strip never selects an unready or extra tab")
    let firstViewport = first.workspace.viewport
    let fresh = firstViewport.camera.snapshot
    let freshScale = firstViewport.scale
    let freshMuted = document.mutedTracks
    let freshDivision = first.gridPresenter().gridSelectionMenuId
    let freshTriplet = first.gridPresenter().tripletGrid
    report.expect(
        first.isReady && first.songOpen, cppID: id,
        message: "A047 a fresh tab is published only after document and bank load")
    report.expect(
        !document.timeline.events.isEmpty && document.bankLease.id.sourceRelativePath != "",
        cppID: id, message: "A048 first visible tab has a populated playback timeline and bank lease")
    report.expect(
        firstViewport.editorViewState == seed, cppID: id,
        message: "A049 fresh tab owns the complete seeded editor state including ordered lanes")
    report.expect(
        fresh.scrollX == fresh.minHScroll && document.editCursor == 0
            && document.selectedNotes.isEmpty && document.timeSelection == nil
            && document.selectedTracks == [0], cppID: id,
        message: "A050 first ready workspace starts with canonical camera cursor and empty selection")
    report.expect(
        app.songTabs.tabCount == 1 && first.isReady, cppID: id,
        message: "A051 a fresh open publishes no intermediate command-ready tab")
    report.expect(
        first.drawerPresenter().chromeState == seed.chrome, cppID: id,
        message: "A052 initial drawer chrome is fully installed before tab publication")
    report.expect(
        firstViewport.editorViewState.lanes == seed.lanes, cppID: id,
        message: "A053 first ready tab has every seeded lane height range and visibility")
    report.expect(
        app.songTabs.tabCount == 1, cppID: id,
        message: "A054 initial successful open installs exactly one ready row")

    let original = document.timeline.events
    let oldPage = first
    let oldSession = document
    let oldID = first.tabId
    guard let note = document.document.notes(in: 0).first else {
        report.fail(reloadID, "real source must contain a selected note")
        return
    }
    document.setSelectedNotes([note.id])
    document.editCursor = 48
    firstViewport.setScale(root: 2)
    firstViewport.setScale(highlight: true)
    document.mutedTracks = [0]
    firstViewport.mutateCamera { _ = $0.setHScroll(12) }
    first.gridPresenter().openGridMenu(kind: 1)
    first.gridPresenter().activateGridMenuRow(actionId: 16)
    first.gridPresenter().openGridMenu(kind: 2)
    first.gridPresenter().activateGridMenuRow(actionId: 1)
    let priorCamera = firstViewport.camera.snapshot
    let priorNotes = document.selectedNoteOrder
    let priorEditor = firstViewport.editorViewState
    do {
        var file = try MidiFile.decode(Array(Data(contentsOf: midiURL)))
        file.chunks[1].events.insert(.channel(tick: 72, status: 0x90, data0: 74, data1: 95), at: 4)
        file.chunks[1].events.insert(.channel(tick: 84, status: 0x80, data0: 74), at: 5)
        try Data(file.encoded()).write(to: midiURL)
    } catch {
        report.fail(reloadID, "could not change the copied reload MIDI: \(error)")
        return
    }
    report.expect(
        first.isReady && original.count > 0, cppID: reloadID,
        message: "A060 the live document is ready with real events before reloading")
    app.openSong(label: "mus_session_test")
    report.expect(
        !first.isReady && app.songTabs.selectedPage === oldPage, cppID: reloadID,
        message: "A061 reload marks the old selectable tab pending exactly once")
    report.expect(
        oldSession.timeline.events == original, cppID: reloadID,
        message: "A062 pending reload retains the old rendered playback event sequence")
    report.expect(
        firstViewport.editorViewState == priorEditor
            && firstViewport.camera.snapshot == priorCamera
            && oldSession.editCursor == 48 && oldSession.selectedNoteOrder == priorNotes,
        cppID: reloadID,
        message: "A063 pending reload retains complete editor camera cursor and selection")
    report.expect(
        !first.isReady && app.songTabs.tabCount == 1, cppID: reloadID,
        message: "A064 pending reload changes readiness once without installing another row")
    var pendingSawSecondRow = false
    var pendingSawUnreadySwap = false
    var partialPublication = false
    let arrived = until {
        // The replacement swaps in place at the same identity: no second row
        // and no partially-installed page may appear while pending.
        if app.songTabs.tabCount != 1 { pendingSawSecondRow = true }
        if app.songTabs.selectedPage === oldPage {
            if oldPage.isReady || oldSession.timeline.events != original
                || firstViewport.editorViewState != priorEditor
            {
                partialPublication = true
            }
            return false
        }
        if app.songTabs.selectedPage?.isReady != true { pendingSawUnreadySwap = true }
        return app.songTabs.selectedPage?.isReady == true
    }
    report.expect(
        !pendingSawSecondRow && !pendingSawUnreadySwap, cppID: reloadID,
        message: "pending reload publishes no second row and no partially-installed page")
    report.expect(
        !partialPublication, cppID: reloadID,
        message: "A065 event-loop pending observations never expose partially replaced MIDI")
    guard arrived, let landed = app.songTabs.selectedPage else {
        report.fail(reloadID, "real changed-MIDI reload did not finish: \(app.lastSaveError)")
        return
    }
    guard let replacement = app.selectedDocument else {
        report.fail(reloadID, "ready tab did not publish its replacement document")
        return
    }
    let addedOn = replacement.timeline.events.contains {
        $0.tick == 72 && $0.track == 0 && $0.type == 0x9 && $0.data0 == 74 && $0.data1 == 95
    }
    let addedOff = replacement.timeline.events.contains {
        $0.tick == 84 && $0.track == 0 && $0.type == 0x8 && $0.data0 == 74
    }
    report.expect(
        addedOn && addedOff && replacement.timeline.events.count == original.count + 2,
        cppID: reloadID,
        message: "A066 completed reload installs the changed note-on and note-off playback events")
    report.expect(
        !partialPublication && oldSession.timeline.events == original, cppID: reloadID,
        message: "A067 the prior tab retains its complete timeline throughout pending publication")
    report.expect(
        landed.tabId == oldID && landed !== oldPage, cppID: reloadID,
        message: "A068 reload publishes one replacement at the original tab identity")
    report.expect(
        landed.isReady && replacement !== oldSession, cppID: reloadID,
        message: "A069 replacement becomes command-ready only with its new document")
    // Reload opens the song fresh in the same row. The editor view state is
    // application-wide, so the drawer and lanes match; camera, cursor, grid,
    // scale, mute and selection start over.
    let landedViewport = landed.workspace.viewport
    let landedCamera = landedViewport.camera.snapshot
    let landedScale = landedViewport.scale
    report.expect(
        landedViewport.editorViewState == priorEditor
            && landed.drawerPresenter().chromeState == seed.chrome
            && landedCamera.pixelsPerBeat == fresh.pixelsPerBeat
            && landedCamera.scrollX == landedCamera.minHScroll
            && replacement.editCursor == 0
            && landedScale.root == freshScale.root && landedScale.scale == freshScale.scale
            && landedScale.highlight == freshScale.highlight && landedScale.fold == freshScale.fold
            && landed.gridPresenter().gridSelectionMenuId == freshDivision
            && landed.gridPresenter().tripletGrid == freshTriplet
            && replacement.mutedTracks == freshMuted, cppID: reloadID,
        message:
            "A070 completed publication keeps the app-wide editor drawer and lane state and opens camera cursor grid scale and mute fresh"
    )
    report.expect(
        landed.isReady && app.songTabs.tabCount == 1
            && !partialPublication && replacement.selectedNoteOrder.isEmpty,
        cppID: reloadID,
        message: "A071 exactly one pending and one ready transition open with an empty note selection")

    let recoveryID = "mainwindowrouting/MainWindowRoutingLifecycleTest::reloadRecovery"

    let scopedSelection = AutomationTimeSelection(
        range: TimeRange(startTick: 24, endTick: 72), scope: .lanes,
        lanes: [.controlChange(track: 0, controller: 74)], tempo: true)
    replacement.applyTimeSelection(scopedSelection)
    app.openSong(label: "mus_session_test")
    report.expect(
        !landed.isReady && replacement.timeSelection == scopedSelection,
        cppID: recoveryID,
        message: "a second pending reload retains its explicit CC74 and Tempo selection scope")
    guard
        until({
            app.songTabs.selectedPage !== landed
                && app.songTabs.selectedPage?.isReady == true
        }),
        let scopedPage = app.songTabs.selectedPage,
        let scopedDocument = app.selectedDocument
    else {
        report.fail(recoveryID, "selection-scope reload did not publish a complete document")
        return
    }
    report.expect(
        scopedDocument.timeSelection == nil
            && scopedDocument.selectedNoteOrder.isEmpty
            && scopedDocument.selectedTracks == [0],
        cppID: recoveryID,
        message: "completed reload clears time and note selection as the fork's song swap does")

    // fceecd88 workspaceui_tabs.cpp handleSongFailed closes non-rebind reload failures;
    // openSongFromList enqueues MIDI reload without the bank-rebind skip marker.
    guard let preservedBytes = try? Data(contentsOf: midiURL) else {
        report.fail(recoveryID, "changed fixture cannot be preserved for failure recovery")
        return
    }
    let scopedGrid = scopedPage.gridPresenter()
    let scopedViewport = scopedPage.workspace.viewport
    let scopedCamera = scopedViewport.camera
    let sourceNotes = (0..<scopedDocument.document.engineTracks.usedTrackCount).flatMap {
        scopedDocument.document.notes(in: $0)
    }
    let visibleNotes = sourceNotes.filter { note -> Bool in
        scopedCamera.projection.row(forPitch: Int(note.pitch)) != PitchProjection.hiddenRow
    }
    if let firstNote = visibleNotes.min(by: { lhs, rhs -> Bool in lhs.tick < rhs.tick }) {
        let snap = scopedCamera.snapshot
        // Center the first note with a lead pad: MIDI middle, px offset.
        let middlePitch = 127.5
        let leadPad = 100.0
        scopedViewport.mutateCamera { camera in
            _ = camera.setHScroll(
                max(
                    camera.snapshot.minHScroll,
                    camera.contentX(tick: Double(firstNote.tick)) - leadPad))
            _ = camera.setVScroll(
                max(
                    0, (middlePitch - Double(firstNote.pitch)) * snap.keyHeight - snap.rollHeight / 2))
        }
        scopedGrid.refreshCamera()
    }
    let completeRenderCount = scopedGrid.renderedNoteCount
    report.expect(
        completeRenderCount > 0, cppID: recoveryID,
        message: "the complete source renders its notes before removal")
    do {
        try FileManager.default.removeItem(at: midiURL)
        app.openSong(label: "mus_session_test")
        var matches42: Bool = !scopedPage.isReady
        if matches42 { matches42 = scopedPage.gridPresenter().renderedNoteCount == completeRenderCount }
        let expectedEventCount: Int = original.count + 2
        if matches42 { matches42 = scopedDocument.timeline.events.count == expectedEventCount }
        report.expect(
            matches42,
            cppID: recoveryID,
            message: "missing source leaves its old complete render while pending")
        report.expect(
            until({ app.songTabs.tabCount == 0 }),
            cppID: recoveryID,
            message: "failed non-rebind MIDI reload closes its tab as the fork does")
        try preservedBytes.write(to: midiURL)
        app.openSong(label: "mus_session_test")
        report.expect(
            until({ app.songTabs.tabCount == 1 })
                && app.selectedDocument?.timeline.events == scopedDocument.timeline.events,
            cppID: recoveryID,
            message: "restoring source reopens a complete changed-MIDI workspace")
        guard let recoveredPage = app.songTabs.selectedPage,
            let recoveredDocument = app.selectedDocument
        else {
            report.fail(recoveryID, "restored source did not publish a recoverable tab")
            return
        }
        let preEditRevision = recoveredDocument.document.revision
        app.openSong(label: "mus_session_test")
        report.expect(
            !recoveredPage.isReady && app.songTabs.selectedPage === recoveredPage,
            cppID: recoveryID,
            message: "a third real reload makes the complete source tab pending before an edit")
        let editedNote = NewNote(track: 0, tick: 132, pitch: 83, duration: 12, velocity: 97)
        let inserted = try recoveredDocument.document.addNotes([editedNote])
        report.expect(
            inserted.count == 1 && recoveredDocument.document.revision > preEditRevision,
            cppID: recoveryID,
            message: "an in-flight document edit changes the original tab revision")
        report.expect(
            until({ recoveredPage.isReady }),
            cppID: recoveryID,
            message: "discarding a stale reload returns the edited original tab to ready")
        report.expect(
            app.songTabs.selectedPage === recoveredPage
                && app.selectedDocument === recoveredDocument
                && recoveredDocument.document.notes(in: 0).contains {
                    $0.tick == 132 && $0.pitch == 83 && $0.velocity == 97
                }, cppID: recoveryID,
            message: "a stale reload leaves the edited document and tab identity intact")
    } catch {
        report.fail(recoveryID, "reload recovery/abort fixture failed: \(error)")
    }
}
