import CoreFoundation
import Foundation
import PorydawApp
import PorydawCoreCheckNative

@MainActor
func runSessionViewStateChecks(_ report: CheckReport, store: PreferencesStore,
                               fixtureRoot: String) {
    let id = "swiftcore/ApplicationSession::editorViewState"
    defer { _ = store.resetPreferences() }
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-view-state")
    let recipeID = "workspace/WorkspaceSessionTest::restoreProjectOnly"
    let plistPath = URL(fileURLWithPath: fixtureRoot, isDirectory: true)
        .appendingPathComponent("settings.plist").path
    let domain = plistPath.withCString {
        CFStringCreateWithCString(kCFAllocatorDefault, $0, CFStringBuiltInEncodings.UTF8.rawValue)
    }
    guard let domain else {
        report.fail(recipeID, "could not address staged preferences domain")
        return
    }
    _ = store.resetPreferences()
    store.setString(key: "lastProjectDir", value: root)
    store.setString(key: "lastSongLabel", value: "mus_session_test")
    store.setString(key: "songFilterText", value: "filterme")
    store.setInt(key: "songFilterSort", value: 1)
    var restoredChrome = EditorDrawerChromeState()
    restoredChrome.velocity = .init(visible: true, height: 173)
    restoredChrome.activePage = .velocity
    EditorViewStateCodec.saveChrome(restoredChrome, store: store)
    var restoredLanes = EditorLaneState()
    restoredLanes.hiddenLanes = [.init(track: 1, controller: 7)]
    EditorViewStateCodec.saveLanes(restoredLanes, store: store)
    store.synchronize()
    let legacy = EditorViewStateCodec.loadTabs(store: store)
    report.expectEqual(expected: ["mus_session_test"], actual: legacy.orderedSongs,
                       cppID: recipeID, what: "a legacy selected-song-only recipe yields one ordered song")
    let sessionKeys = ["lastProjectDir", "lastSongLabel", "lastOpenSongs",
                       "songFilterText", "songFilterSort", "songFilterCategory",
                       "editorDrawer.velocityVisible", "editorDrawer.velocityHeight",
                       "editorDrawer.automationVisible", "editorDrawer.automationHeight",
                       "editorDrawer.voiceChangesVisible", "editorDrawer.voiceChangesHeight",
                       "editorDrawer.activePage", "editorDrawer.automationLanes",
                       "windowGeometry", "windowState"]
    func storedSessionKeys() -> [String: Any] {
        var values: [String: Any] = [:]
        for key in sessionKeys {
            guard let name = key.withCString({
                CFStringCreateWithCString(kCFAllocatorDefault, $0, CFStringBuiltInEncodings.UTF8.rawValue)
            }), let value = CFPreferencesCopyAppValue(name, domain) else { continue }
            values[key] = value
        }
        return values
    }
    let beforeRestore = storedSessionKeys()
    report.expect(beforeRestore.keys.contains("lastProjectDir")
                  && beforeRestore.keys.contains("lastSongLabel")
                  && beforeRestore.keys.contains("songFilterText")
                  && beforeRestore.keys.contains("songFilterSort")
                  && beforeRestore.keys.contains("editorDrawer.activePage")
                  && beforeRestore.keys.contains("editorDrawer.automationLanes"),
                  cppID: recipeID, message: "the staged plist contains the recipe, filter and editor keys")
    let restoredShell = ShellPresenter()
    restoredShell.configureSettings(applicationName: "porydaw")
    restoredShell.openStartup()
    let deadline = Date().addingTimeInterval(25)
    while !restoredShell.session.songOpen && restoredShell.session.lastSaveError.isEmpty
          && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    report.expect(restoredShell.session.songOpen && restoredShell.session.songTabs.tabCount == 1,
                  cppID: recipeID, message: "startup opens the one legacy selected song as a ready tab")
    report.expectEqual(expected: "mus_session_test",
                       actual: restoredShell.session.songTabs.selectedPage?.title,
                       cppID: recipeID, what: "startup selects the restored legacy song")
    store.synchronize()
    report.expect(NSDictionary(dictionary: beforeRestore).isEqual(to: storedSessionKeys()),
                  cppID: recipeID, message: "successful live-project restore leaves every session and editor preference key unchanged")
    restoredShell.session.requestCloseAll()
    let closeDeadline = Date().addingTimeInterval(25)
    while restoredShell.session.songTabs.tabCount > 0 && Date() < closeDeadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    let savedRecipe = EditorViewStateCodec.loadTabs(store: store)
    report.expectEqual(expected: root, actual: savedRecipe.projectPath,
                       cppID: recipeID, what: "host close saves the live project path")
    report.expectEqual(expected: "mus_session_test", actual: savedRecipe.selectedSong,
                       cppID: recipeID, what: "host close saves the selected song label")
    report.expect(store.hasValue(key: "lastOpenSongs")
                  && savedRecipe.orderedSongs == ["mus_session_test"],
                  cppID: recipeID, message: "host close saves the explicit ordered-song key")
    restoredShell.session.hostClosing()
    restoredShell.session.acknowledgeGridDetached()
    EditorViewStateCodec.saveTabs(
        WorkspaceTabRecipe(projectPath: root,
                           orderedSongs: ["missing-song", "mus_session_test", "mus_session_test"],
                           selectedSong: "other-song"), store: store)
    let ordered = EditorViewStateCodec.loadTabs(store: store)
    report.expectEqual(expected: ["missing-song", "mus_session_test", "mus_session_test"],
                       actual: ordered.orderedSongs, cppID: recipeID,
                       what: "a present ordered recipe is not extended by its selected label")
    let available = ordered.normalized(available: ["mus_session_test"])
    report.expectEqual(expected: ["mus_session_test"], actual: available.orderedSongs,
                       cppID: recipeID, what: "normalization omits missing and duplicate songs")
    report.expectEqual(expected: "mus_session_test", actual: available.selectedSong,
                       cppID: recipeID, what: "a missing selected song falls back to the first live tab")
    let orderedKey = "lastOpenSongs".withCString {
        CFStringCreateWithCString(kCFAllocatorDefault, $0, CFStringBuiltInEncodings.UTF8.rawValue)
    }
    guard let orderedKey else {
        preconditionFailure("Staged preferences require UTF-8 key and domain strings")
    }
    CFPreferencesSetAppValue(orderedKey, [] as [String] as CFPropertyList, domain)
    store.setString(key: "lastSongLabel", value: "mus_session_test")
    report.expect(store.hasValue(key: "lastOpenSongs"), cppID: recipeID,
                  message: "the explicitly empty ordered-song key is present before load")
    report.expectEqual(expected: [], actual: EditorViewStateCodec.loadTabs(store: store).orderedSongs,
                       cppID: recipeID,
                       what: "an explicitly empty ordered-song key stays empty despite a selected label")
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
    EditorViewStateCodec.saveLanes(lanes, store: store)
    EditorViewStateCodec.saveChrome(seed, store: store)
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
          let first = app.songTabs.selectedPage else {
        report.fail(id, "first fixture workspace failed to open: \(app.lastSaveError)")
        return
    }
    report.expectEqual(expected: seed, actual: first.drawerPresenter().chromeState, cppID: id,
                       what: "a fresh tab carries the shared view state before it is ready")
    report.expect(first.drawerPresenter().chromeState == seed
                  && EditorViewStateCodec.loadLanes(store: PreferencesStore()) == lanes,
                  cppID: id, message: "startup adopts complete persisted drawer and lane state")
    let firstID = first.tabId
    app.openSong(label: "mus_session_test2")
    guard until({ app.songTabs.tabCount == 2 || !app.lastSaveError.isEmpty }),
          let second = app.songTabs.selectedPage, second !== first else {
        report.fail(id, "second fixture workspace failed to open: \(app.lastSaveError)")
        return
    }
    report.expectEqual(expected: seed, actual: second.drawerPresenter().chromeState, cppID: id,
                       what: "the shared view state starts identically on two song tabs")
    report.expect(second.drawerPresenter().chromeState == seed
                  && EditorViewStateCodec.loadLanes(store: PreferencesStore()) == lanes,
                  cppID: id, message: "second live tab adopts every shared drawer and lane member")
    let automation = DrawerSectionKind.automation.rawValue
    second.drawerPresenter().toggleSection(kind: automation, drawerOwnsFocus: false)
    let changed = second.drawerPresenter().chromeState
    report.expect(changed.automation.visible && first.drawerPresenter().chromeState == changed,
                  cppID: id, message: "one automation key shows the section on every open tab")
    report.expectEqual(expected: DrawerSectionKind.automation, actual: changed.activePage,
                       cppID: id, what: "Automation becomes active on the origin drawer")
    report.expectEqual(expected: DrawerSectionKind.automation,
                       actual: first.drawerPresenter().chromeState.activePage,
                       cppID: id, what: "Automation becomes active on the sibling drawer")
    report.expectEqual(expected: changed, actual: EditorViewStateCodec.loadChrome(store: store),
                       cppID: id, what: "the shared view state persists once per change")
    let beforeNoOp = EditorViewStateCodec.loadChrome(store: store)
    second.drawerPresenter().setSectionVisible(kind: automation, visible: true,
                                               drawerOwnsFocus: false)
    report.expect(first.drawerPresenter().chromeState == changed
                  && second.drawerPresenter().chromeState == changed
                  && EditorViewStateCodec.loadChrome(store: store) == beforeNoOp,
                  cppID: id, message: "an unchanged view state writes nothing")
    let velocity = DrawerSectionKind.velocity.rawValue
    second.drawerPresenter().toggleSection(kind: velocity, drawerOwnsFocus: false)
    let focused = second.drawerPresenter().chromeState
    report.expect(focused.activePage == .velocity
                  && first.drawerPresenter().chromeState == focused,
                  cppID: id, message: "the velocity drawer becomes the active page on every tab")
    report.expectEqual(expected: DrawerSectionKind.velocity, actual: focused.activePage,
                       cppID: id, what: "Velocity becomes active on the origin drawer")
    report.expectEqual(expected: DrawerSectionKind.velocity,
                       actual: first.drawerPresenter().chromeState.activePage,
                       cppID: id, what: "Velocity becomes active on the sibling drawer")
    second.drawerPresenter().setSectionVisible(kind: automation, visible: false,
                                               drawerOwnsFocus: false)
    let hidden = second.drawerPresenter().chromeState
    report.expect(!first.drawerPresenter().chromeState.automation.visible,
                  cppID: id, message: "a hidden section stays hidden on the sibling tab")
    report.expect(hidden.velocity.height == 173 && hidden.activePage == .velocity,
                  cppID: id, message: "hiding one section retains the other sections and the active page")
    app.songTabs.selectTab(tabId: firstID)
    second.drawerPresenter().toggleSection(kind: DrawerSectionKind.voiceChanges.rawValue,
                                           drawerOwnsFocus: false)
    let backgroundChange = second.drawerPresenter().chromeState
    report.expectEqual(expected: backgroundChange,
                       actual: app.songTabs.selectedPage?.drawerPresenter().chromeState,
                       cppID: id, what: "a non-selected tab's mutation reaches the selected tab silently")
    report.expectEqual(expected: DrawerSectionKind.voiceChanges,
                       actual: backgroundChange.activePage,
                       cppID: id, what: "Voice Changes becomes active on the origin drawer")
    report.expectEqual(expected: DrawerSectionKind.voiceChanges,
                       actual: first.drawerPresenter().chromeState.activePage,
                       cppID: id, what: "Voice Changes becomes active on the sibling drawer")
    report.expectEqual(expected: backgroundChange, actual: EditorViewStateCodec.loadChrome(store: store),
                       cppID: id, what: "background drawer changes persist without selecting that tab")
    let idStored = "workspace/WorkspaceEditorCodecSelfTest::livePersistenceAndFinalClose"
    app.songTabs.selectTab(tabId: second.tabId)
    guard let document = app.selectedDocument?.document else {
        report.fail(idStored, "second fixture document is unavailable")
        return
    }
    let revision = document.revision
    let history = document.history.currentIdentity
    let originalLanes = EditorViewStateCodec.loadLanes(store: PreferencesStore())
    report.expectEqual(expected: lanes, actual: originalLanes, cppID: idStored,
                       what: "the live session retains every seeded lane preference after drawer changes")
    let laneKey = "editorDrawer.automationLanes".withCString {
        CFStringCreateWithCString(kCFAllocatorDefault, $0, CFStringBuiltInEncodings.UTF8.rawValue)
    }
    guard let laneKey else {
        report.fail(idStored, "could not address stored lane key")
        return
    }
    let malformed = Data("{ not json".utf8)
    CFPreferencesSetAppValue(laneKey, malformed as CFPropertyList, domain)
    store.synchronize()
    report.expect((CFPreferencesCopyAppValue(laneKey, domain) as? Data) == malformed,
                  cppID: idStored, message: "live editor poison enters the persisted preference domain")
    let poisoned = PreferencesStore()
    report.expect(EditorViewStateCodec.loadChrome(store: poisoned) == backgroundChange
                  && EditorViewStateCodec.loadLanes(store: poisoned) == EditorLaneState(),
                  cppID: idStored, message: "poisoned live editor reload defaults only lane members")
    report.expect((CFPreferencesCopyAppValue(laneKey, domain) as? Data) == malformed,
                  cppID: idStored, message: "reading live poisoned lanes leaves the preference unchanged")
    second.drawerPresenter().setSectionBodyHeight(kind: DrawerSectionKind.velocity.rawValue, height: 181)
    let healed = PreferencesStore()
    let canonical = CFPreferencesCopyAppValue(laneKey, domain) as? Data
    let compact = canonical.map { $0.first == 123 && !$0.contains(10) } ?? false
    report.expect(compact
                  && EditorViewStateCodec.loadChrome(store: healed) == second.drawerPresenter().chromeState
                  && EditorViewStateCodec.loadLanes(store: healed) == lanes,
                  cppID: idStored, message: "real section resize republishes compact lanes with complete chrome")
    let drawer = second.drawerPresenter()
    drawer.setSectionVisible(kind: DrawerSectionKind.velocity.rawValue, visible: true,
                             drawerOwnsFocus: false)
    drawer.setSectionVisible(kind: DrawerSectionKind.automation.rawValue, visible: false,
                             drawerOwnsFocus: false)
    drawer.setSectionVisible(kind: DrawerSectionKind.voiceChanges.rawValue, visible: true,
                             drawerOwnsFocus: false)
    drawer.setSectionBodyHeight(kind: DrawerSectionKind.velocity.rawValue, height: 173)
    drawer.setSectionBodyHeight(kind: DrawerSectionKind.automation.rawValue, height: 64)
    drawer.setSectionBodyHeight(kind: DrawerSectionKind.voiceChanges.rawValue, height: 97)
    drawer.toggleSection(kind: DrawerSectionKind.velocity.rawValue, drawerOwnsFocus: false)
    drawer.toggleSection(kind: DrawerSectionKind.velocity.rawValue, drawerOwnsFocus: false)
    report.expectEqual(expected: seed, actual: EditorViewStateCodec.loadChrome(store: PreferencesStore()),
                       cppID: idStored, what: "the full live chrome with all three stored heights persists")
    report.expectEqual(expected: seed, actual: first.drawerPresenter().chromeState,
                       cppID: idStored, what: "the complete three-section chrome reaches the sibling")
    let completeStore = PreferencesStore()
    report.expect(EditorViewStateCodec.loadChrome(store: completeStore) == seed
                  && EditorViewStateCodec.loadLanes(store: completeStore) == lanes
                  && second.drawerPresenter().chromeState == seed
                  && first.drawerPresenter().chromeState == seed,
                  cppID: idStored, message: "restoring all drawer sections retains every lane member on both tabs")
    drawer.setSectionVisible(kind: DrawerSectionKind.automation.rawValue, visible: true,
                             drawerOwnsFocus: false)
    drawer.setSectionVisible(kind: DrawerSectionKind.voiceChanges.rawValue, visible: false,
                             drawerOwnsFocus: false)
    report.expect(drawer.chromeState.activePage == .velocity
                  && drawer.chromeState.velocity.visible && !drawer.chromeState.voiceChanges.visible,
                  cppID: id, message: "hiding Voice Changes keeps Velocity visible and active on the origin")
    report.expect(first.drawerPresenter().chromeState.activePage == .velocity
                  && first.drawerPresenter().chromeState.velocity.visible,
                  cppID: id, message: "hiding Voice Changes keeps Velocity visible and active on the sibling")
    drawer.setSectionVisible(kind: DrawerSectionKind.velocity.rawValue, visible: false,
                             drawerOwnsFocus: false)
    report.expect(drawer.chromeState.activePage == .velocity
                  && drawer.chromeState.automation.visible && !drawer.chromeState.velocity.visible,
                  cppID: id, message: "hiding Velocity keeps Automation visible and the active page on the origin")
    report.expect(first.drawerPresenter().chromeState.activePage == .velocity
                  && first.drawerPresenter().chromeState.automation.visible,
                  cppID: id, message: "hiding Velocity keeps Automation visible and the active page on the sibling")
    report.expect(drawer.chromeState.velocity.height == 173
                  && drawer.chromeState.voiceChanges.height == 97,
                  cppID: id, message: "the origin preserves hidden Velocity and Voice Changes heights")
    report.expectEqual(expected: DrawerSectionKind.velocity,
                       actual: first.drawerPresenter().chromeState.activePage,
                       cppID: id, what: "the sibling retains Velocity as active after both sections hide")
    report.expectEqual(expected: 173, actual: first.drawerPresenter().chromeState.velocity.height,
                       cppID: id, what: "the sibling retains hidden Velocity's stored height")
    report.expectEqual(expected: 97, actual: first.drawerPresenter().chromeState.voiceChanges.height,
                       cppID: id, what: "the sibling retains hidden Voice Changes' stored height")
    drawer.setSectionVisible(kind: DrawerSectionKind.velocity.rawValue, visible: true,
                             drawerOwnsFocus: false)
    drawer.setSectionVisible(kind: DrawerSectionKind.automation.rawValue, visible: false,
                             drawerOwnsFocus: false)
    drawer.setSectionVisible(kind: DrawerSectionKind.voiceChanges.rawValue, visible: true,
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
    report.expectEqual(expected: bare, actual: first.drawerPresenter().chromeState,
                       cppID: idStored, what: "the live optional-height change reaches the sibling drawer")
    report.expectEqual(expected: bare, actual: drawer.chromeState,
                       cppID: idStored, what: "the live optional-height change retains all visibility and selects Voice Changes")
    let reopened = PreferencesStore()
    report.expectEqual(expected: bare, actual: EditorViewStateCodec.loadChrome(store: reopened),
                       cppID: idStored, what: "the live bare chrome persists with Voice Changes active")
    report.expectEqual(expected: lanes, actual: EditorViewStateCodec.loadLanes(store: reopened),
                       cppID: idStored, what: "the live bare chrome transition retains every stored lane member")
    report.expect(first.drawerPresenter().chromeState == bare
                  && drawer.chromeState == bare
                  && EditorViewStateCodec.loadChrome(store: reopened) == bare
                  && EditorViewStateCodec.loadLanes(store: reopened) == lanes,
                  cppID: idStored, message: "unset heights preserve the complete retained shared editor state")
    let unchangedRevision = document.revision == revision
    let unchangedHistory = document.history.currentIdentity == history
    let unchangedDirty = !document.isDirty
    report.expect(unchangedRevision && unchangedHistory && unchangedDirty, cppID: idStored,
                  message: "drawer-only changes leave the song revision, history and dirty state unchanged")
    app.songTabs.requestClose(tabId: second.tabId)
    report.expect(app.songTabs.tabCount == 1 && app.songTabs.selectedId == firstID,
                  cppID: idStored, message: "closing the active editor leaves its sibling selected")
    app.songTabs.requestClose(tabId: firstID)
    report.expect(app.songTabs.tabCount == 0 && app.songTabs.selectedId == -1,
                  cppID: idStored, message: "closing the final editor leaves no live song tab")
    app.openSong(label: "mus_session_test")
    guard until({ app.songTabs.tabCount == 1 || !app.lastSaveError.isEmpty }),
          let returned = app.songTabs.selectedPage else {
        report.fail(idStored, "fixture workspace failed to reopen: \(app.lastSaveError)")
        return
    }
    let restored = PreferencesStore()
    report.expect(returned.tabId != firstID && returned.drawerPresenter().chromeState == bare
                  && EditorViewStateCodec.loadChrome(store: restored) == bare
                  && EditorViewStateCodec.loadLanes(store: restored) == lanes,
                  cppID: idStored, message: "reopened tab restores the complete drawer and ordered hidden lanes")
    report.expect(EditorViewStateCodec.loadLanes(store: restored).hiddenLanes == lanes.hiddenLanes,
                  cppID: idStored, message: "reopened editor retains the hidden lane ordering")
}
