import Foundation
import PorydawApp
import PorydawCoreCheckNative

@MainActor
func runSessionViewStateChecks(_ report: CheckReport, store: PreferencesStore,
                               fixtureRoot: String) {
    let id = "swiftcore/ApplicationSession::editorViewState"
    defer { _ = store.resetPreferences() }
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-view-state")
    var seed = EditorDrawerChromeState()
    seed.velocity = .init(visible: true, height: 173)
    seed.automation.visible = false
    seed.activePage = .velocity
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
    let firstID = first.tabId
    app.openSong(label: "mus_session_test2")
    guard until({ app.songTabs.tabCount == 2 || !app.lastSaveError.isEmpty }),
          let second = app.songTabs.selectedPage, second !== first else {
        report.fail(id, "second fixture workspace failed to open: \(app.lastSaveError)")
        return
    }
    report.expectEqual(expected: seed, actual: second.drawerPresenter().chromeState, cppID: id,
                       what: "the shared view state starts identically on two song tabs")
    let automation = DrawerSectionKind.automation.rawValue
    second.drawerPresenter().toggleSection(kind: automation, drawerOwnsFocus: false)
    let changed = second.drawerPresenter().chromeState
    report.expect(changed.automation.visible && first.drawerPresenter().chromeState == changed,
                  cppID: id, message: "one automation key shows the section on every open tab")
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
    report.expectEqual(expected: backgroundChange, actual: EditorViewStateCodec.loadChrome(store: store),
                       cppID: id, what: "background drawer changes persist without selecting that tab")
}
