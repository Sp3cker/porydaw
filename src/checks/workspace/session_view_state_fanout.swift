import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawCoreCheckNative

@MainActor
func runCompleteEditorViewStateChecks(
    report: CheckReport, store: PreferencesStore,
    fixtureRoot: String
) {
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-complete-editor-state")
    let song = URL(fileURLWithPath: root)
        .appendingPathComponent("sound/songs/midi/mus_session_test2.mid")
    do {
        var file = try MidiFile.decode(Array(Data(contentsOf: song)))
        file.chunks.append(
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0xC1, data0: 1),
                    .channel(tick: 48, status: 0x91, data0: 72, data1: 95),
                    .channel(tick: 72, status: 0x81, data0: 72),
                ], endTick: 192))
        try Data(file.encoded()).write(to: song)
    } catch {
        report.fail(
            "mainwindowrouting/MainWindowRoutingStateTest::completeEditorViewState",
            "could not stage copied two-track MIDI")
        return
    }
    let id = "mainwindowrouting/MainWindowRoutingStateTest::completeEditorViewState"
    var seed = EditorViewState()
    seed.chrome.velocity = .init(visible: true, height: 173)
    seed.chrome.automation = .init(visible: true, height: 44)
    seed.chrome.voiceChanges = .init(visible: true, height: 55)
    seed.chrome.activePage = .automation
    let floor = Int((AutomationPagePolicy.seedBaseFontPx * 7 / 3).rounded())
    let ceiling = Int((AutomationPagePolicy.seedBaseFontPx * 32 / 3).rounded())
    seed.lanes.laneHeight = (floor + ceiling) / 2
    seed.lanes.laneHeights = ["cc:0:74": floor + 3, "cc:1:7": floor + 5]
    seed.lanes.laneRanges = ["cc:0:74": 90, "tempo": 100]
    seed.lanes.emptyLanes = [.init(track: 0, controller: 74)]
    seed.lanes.hiddenLanes = [
        .init(track: 1, controller: 7),
        .init(track: 0, controller: 80),
    ]
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
    guard until({ app.songTabs.tabCount == 1 || !app.lastSaveError.isEmpty }),
        let first = app.selectedDocument
    else {
        report.fail(id, "complete state first copied song failed to open")
        return
    }
    let firstID = app.songTabs.selectedId
    app.openSong(label: "mus_session_test2")
    guard until({ app.songTabs.tabCount == 2 || !app.lastSaveError.isEmpty }),
        let second = app.selectedDocument, second !== first
    else {
        report.fail(id, "complete state second copied song failed to open")
        return
    }
    let secondID = app.songTabs.selectedId
    app.songTabs.selectTab(tabId: firstID)
    let freshSecondDepth = second.document.history.undoCount
    var originCount = 0
    var siblingCount = 0
    let firstCallback = first.onEditorViewStateChanged
    let secondCallback = second.onEditorViewStateChanged
    first.onEditorViewStateChanged = { state in
        siblingCount += 1
        firstCallback?(state)
    }
    second.onEditorViewStateChanged = { state in
        originCount += 1
        secondCallback?(state)
    }
    var hubCount = 0
    var persistedCount = 0
    app.onEditorViewStateChanged = { _ in hubCount += 1 }
    app.onEditorViewStatePersisted = { _ in persistedCount += 1 }
    guard second.setEditorViewState(seed) else {
        report.fail(id, "background tab could not accept complete editor seed")
        return
    }
    report.expect(
        originCount == 1, cppID: id,
        message: "initial complete seed publishes exactly one origin notification")
    report.expect(
        siblingCount == 0, cppID: id,
        message: "initial complete seed never republishes from the sibling")
    report.expect(
        hubCount == 1, cppID: id,
        message: "A103 initial complete seed publishes exactly one workspace notification")
    report.expect(
        persistedCount == 1, cppID: id,
        message: "initial complete seed finishes exactly one preference write")
    report.expect(
        first.editorViewState == seed, cppID: id,
        message: "A105 selected sibling holds every member of the complete editor seed")
    report.expect(
        second.editorViewState == seed, cppID: id,
        message: "A106 background origin holds every member of the complete editor seed")
    report.expect(
        EditorViewStateCodec.load(store: PreferencesStore()) == seed, cppID: id,
        message: "A107 synchronized preferences hold every member of the complete editor seed")
    report.expect(
        second.editorViewState.lanes.hiddenLanes.count == 2, cppID: id,
        message: "A108 seeded background state holds two ordered hidden lanes")
    report.expect(
        second.editorViewState.lanes.hiddenLanes.first == .init(track: 1, controller: 7),
        cppID: id, message: "A109 first hidden lane remains CC7 on engine track one")
    report.expect(
        second.editorViewState.lanes.hiddenLanes.last == .init(track: 0, controller: 80),
        cppID: id, message: "A110 last hidden lane remains CC80 on engine track zero")

    var changed = seed
    changed.lanes.laneRanges["cc:0:74"] = 80
    guard second.setEditorViewState(changed) else {
        report.fail(id, "background tab could not change CC74 range")
        return
    }
    report.expect(
        originCount == 2, cppID: id,
        message: "A111 changing background CC74 range publishes one more origin notification")
    report.expect(
        hubCount == 2, cppID: id,
        message: "A112 changing background CC74 range publishes one more workspace notification")
    report.expect(
        persistedCount == 2, cppID: id,
        message: "A113 changing background CC74 range finishes one more preference write")
    report.expect(
        siblingCount == 0, cppID: id,
        message: "A114 changing background CC74 range never originates from selected sibling")
    report.expect(
        first.editorViewState.lanes.laneRanges["cc:0:74"] == 80, cppID: id,
        message: "A115 selected sibling adopts the independent CC74 range 80")
    report.expect(
        second.editorViewState.lanes.laneRanges["cc:0:74"] == 80, cppID: id,
        message: "A116 background origin retains the independent CC74 range 80")
    let sameRange = !second.setEditorViewState(changed)
    var noOp = second.editorViewState
    let sameInsert = !noOp.lanes.emptyLanes.insert(.init(track: 0, controller: 74)).inserted
    let missingErase = noOp.lanes.emptyLanes.remove(.init(track: 3, controller: 99)) == nil
    let sameValue = !second.setEditorViewState(noOp)
    report.expect(
        sameRange, cppID: id,
        message: "setting the same CC74 range leaves the complete editor value unchanged")
    report.expect(
        sameInsert, cppID: id,
        message: "inserting an existing empty CC74 lane leaves the lane set unchanged")
    report.expect(
        missingErase, cppID: id,
        message: "erasing a nonexistent CC99 lane leaves the lane set unchanged")
    report.expect(
        sameValue, cppID: id,
        message: "setting unchanged complete editor value rejects another publication")
    report.expect(
        originCount == 2, cppID: id,
        message: "A117 identical range and empty lane noops emit no origin notification")
    report.expect(
        siblingCount == 0, cppID: id,
        message: "A118 identical range and empty lane noops emit no sibling notification")
    report.expect(
        hubCount == 2, cppID: id,
        message: "A119 identical range and empty lane noops emit no workspace notification")
    report.expect(
        persistedCount == 2, cppID: id,
        message: "identical range and empty lane noops finish no preference write")

    let source = 1
    let trackCount = second.document.engineTracks.usedTrackCount
    guard trackCount == 2, let original = try? second.document.state.file.encoded() else {
        report.fail(id, "the copied second song needs exactly two engine tracks and encodable MIDI")
        return
    }
    let target = 0
    let before = second.editorViewState
    var expected = before
    expected.lanes.laneHeights = ["cc:1:74": floor + 3, "cc:0:7": floor + 5]
    expected.lanes.laneRanges = ["cc:1:74": 80, "tempo": 100]
    expected.lanes.emptyLanes = [.init(track: 1, controller: 74)]
    expected.lanes.hiddenLanes = [
        .init(track: 0, controller: 7),
        .init(track: 1, controller: 80),
    ]
    guard second.document.moveTrack(source, to: target) else {
        report.fail(id, "real document could not move engine track one to zero")
        return
    }
    let remapped = second.editorViewState
    report.expect(
        originCount == 3, cppID: id,
        message: "A124 real track move emits exactly one more origin notification")
    report.expect(
        hubCount == 3, cppID: id,
        message: "A125 real track move emits exactly one more workspace notification")
    report.expect(
        persistedCount == 3, cppID: id,
        message: "A126 real track move finishes exactly one more preference write")
    report.expect(
        remapped != before, cppID: id,
        message: "A127 real track move changes the owned complete editor value")
    report.expect(
        siblingCount == 0, cppID: id,
        message: "A128 real track move never originates from the sibling")
    report.expect(
        !remapped.lanes.hiddenLanes.contains(.init(track: 1, controller: 7)), cppID: id,
        message: "A129 real track move removes the old hidden CC7 identity")
    report.expect(
        remapped.lanes.hiddenLanes.count == 2, cppID: id,
        message: "A130 real track move retains both ordered hidden lanes")
    report.expect(
        remapped.lanes.hiddenLanes.first?.controller == 7, cppID: id,
        message: "A131 first remapped hidden lane remains CC7")
    report.expect(
        remapped.lanes.hiddenLanes.first?.track == 0, cppID: id,
        message: "A132 first remapped hidden CC7 moves off engine track one onto zero")
    report.expect(
        remapped.lanes.hiddenLanes.last?.controller == 80, cppID: id,
        message: "A133 last remapped hidden lane remains CC80")
    report.expect(
        remapped.lanes.laneRanges["tempo"] == 100, cppID: id,
        message: "A134 real engine-track move preserves Tempo range 100")
    report.expect(
        remapped == expected, cppID: id,
        message: "real track move remaps CC lane heights ranges empty and hidden identities exactly")
    report.expect(
        first.editorViewState == expected, cppID: id,
        message: "A135 selected sibling receives the independently expected full remapped editor value")
    report.expect(
        EditorViewStateCodec.load(store: PreferencesStore()) == expected, cppID: id,
        message: "A136 preferences receive the independently expected full remapped editor value")

    guard second.document.history.undoDocument() else {
        report.fail(id, "document could not Undo the first engine-track move")
        return
    }
    report.expect(
        originCount == 4, cppID: id,
        message: "A137 Undo emits exactly one more origin notification")
    report.expect(
        hubCount == 4, cppID: id,
        message: "A138 Undo emits exactly one more workspace notification")
    report.expect(
        persistedCount == 4, cppID: id,
        message: "A139 Undo finishes exactly one more preference write")
    report.expect(
        first.editorViewState == before, cppID: id,
        message: "A140 Undo restores the sibling complete editor value")
    report.expect(
        second.editorViewState == before, cppID: id,
        message: "A141 Undo restores the background origin complete editor value")
    report.expect(
        (try? second.document.state.file.encoded()) == original, cppID: id,
        message: "A142 Undo restores the complete original MIDI bytes")
    report.expect(
        !second.document.isDirty, cppID: id,
        message: "A143 Undo returns the document to a clean state")
    report.expect(
        siblingCount == 0, cppID: id,
        message: "A144 Undo never publishes a sibling-origin notification")

    var reduced = EditorViewState()
    reduced.chrome = seed.chrome
    guard second.setEditorViewState(reduced) else {
        report.fail(id, "background tab could not accept chrome-only editor value")
        return
    }
    hubCount = 0
    persistedCount = 0
    originCount = 0
    siblingCount = 0
    guard let quietMidi = try? second.document.state.file.encoded() else {
        report.fail(id, "the unchanged second MIDI must remain encodable before quiet move")
        return
    }
    guard second.document.moveTrack(source, to: target) else {
        report.fail(id, "document could not move with chrome-only editor value")
        return
    }
    report.expect(
        originCount == 0, cppID: id,
        message: "A146 quiet track move emits no editor-origin notification")
    report.expect(
        hubCount == 0, cppID: id,
        message: "A147 quiet track move emits no workspace editor notification")
    report.expect(
        persistedCount == 0, cppID: id,
        message: "A148 quiet track move finishes no editor preference write")
    report.expect(
        second.editorViewState == reduced, cppID: id,
        message: "quiet track move leaves chrome-only editor value unchanged")
    guard second.document.history.undoDocument() else {
        report.fail(id, "document could not Undo the quiet engine-track move")
        return
    }
    report.expect(
        originCount == 0, cppID: id,
        message: "A149 quiet Undo emits no editor-origin notification")
    report.expect(
        siblingCount == 0, cppID: id,
        message: "A150 quiet Undo emits no sibling-origin notification")
    report.expect(
        hubCount == 0, cppID: id,
        message: "A151 quiet Undo emits no workspace editor notification")
    report.expect(
        persistedCount == 0, cppID: id,
        message: "A152 quiet Undo finishes no editor preference write")
    report.expect(
        (try? second.document.state.file.encoded()) == quietMidi, cppID: id,
        message: "A153 quiet Undo restores original MIDI bytes")
    report.expect(
        !second.document.isDirty, cppID: id,
        message: "A154 quiet Undo restores clean document state")
    report.expect(
        first.editorViewState == reduced, cppID: id,
        message: "quiet move and Undo preserve the sibling chrome-only editor value")

    guard second.setEditorViewState(seed) else {
        report.fail(id, "background tab could not restore complete seed before view-only mutation")
        return
    }
    hubCount = 0
    persistedCount = 0
    originCount = 0
    siblingCount = 0
    let revision = second.document.revision
    let historyCount = second.document.history.undoCount
    var withEmpty = seed
    withEmpty.lanes.emptyLanes.insert(.init(track: 2, controller: 40))
    guard second.setEditorViewState(withEmpty) else {
        report.fail(id, "background tab could not insert the view-only CC40 empty lane")
        return
    }
    report.expect(
        originCount == 1, cppID: id,
        message: "A156 empty lane insertion emits exactly one origin notification")
    report.expect(
        hubCount == 1, cppID: id,
        message: "A157 empty lane insertion emits exactly one workspace notification")
    report.expect(
        persistedCount == 1, cppID: id,
        message: "A158 empty lane insertion finishes exactly one preference write")
    report.expect(
        first.editorViewState == second.editorViewState, cppID: id,
        message: "A159 empty lane insertion projects origin value to selected sibling")
    report.expect(
        first.editorViewState == withEmpty, cppID: id,
        message: "empty lane insertion matches the independently specified complete state")
    report.expect(
        EditorViewStateCodec.load(store: PreferencesStore()) == second.editorViewState,
        cppID: id, message: "A160 empty lane insertion stores the live origin complete state")
    report.expect(
        EditorViewStateCodec.load(store: PreferencesStore()) == withEmpty, cppID: id,
        message: "empty lane insertion preferences match the independently specified value")
    report.expect(
        (try? second.document.state.file.encoded()) == original, cppID: id,
        message: "A161 view-only insertion leaves all MIDI bytes unchanged")
    report.expect(
        second.document.revision == revision, cppID: id,
        message: "A162 view-only insertion leaves document revision unchanged")
    report.expect(
        second.document.history.undoCount == historyCount, cppID: id,
        message: "A163 view-only insertion leaves document history count unchanged")
    report.expect(
        siblingCount == 0, cppID: id,
        message: "view-only insertion never originates from selected sibling")
    guard second.setEditorViewState(seed) else {
        report.fail(id, "background tab could not remove the view-only CC40 empty lane")
        return
    }
    report.expect(
        originCount == 2, cppID: id,
        message: "A165 empty lane removal emits exactly one more origin notification")
    report.expect(
        hubCount == 2, cppID: id,
        message: "A166 empty lane removal emits exactly one more workspace notification")
    report.expect(
        persistedCount == 2, cppID: id,
        message: "A167 empty lane removal finishes exactly one more preference write")
    report.expect(
        (try? second.document.state.file.encoded()) == original, cppID: id,
        message: "A168 view-only removal leaves all MIDI bytes unchanged")
    report.expect(
        second.document.revision == revision, cppID: id,
        message: "A169 view-only removal leaves document revision unchanged")
    report.expect(
        second.document.history.undoCount == historyCount, cppID: id,
        message: "A170 view-only removal leaves document history count unchanged")
    report.expect(
        first.editorViewState == seed, cppID: id,
        message: "view-only removal restores selected sibling complete value")
    report.expect(
        EditorViewStateCodec.load(store: PreferencesStore()) == seed, cppID: id,
        message: "view-only removal restores synchronized complete preferences")
    let beforeA = first.editorViewState
    let beforeB = second.editorViewState
    guard let rejectedMidi = try? second.document.state.file.encoded() else {
        report.fail(id, "the live second MIDI must remain encodable before the rejected remap")
        return
    }
    let rejectedRevision = second.document.revision
    let rejectedSettings = EditorViewStateCodec.load(store: PreferencesStore())
    originCount = 0
    siblingCount = 0
    hubCount = 0
    persistedCount = 0
    let chunkCount = second.document.state.file.chunks.count
    let rejected = TrackRemap(
        chunkMap: chunkCount > 0 ? Array(0..<chunkCount).map(Optional.some) : [],
        engineTrackMap: [0, 0], newChunkCount: chunkCount, newEngineTrackCount: 2)
    second.document.onChange?(DocumentChange(revision: rejectedRevision, trackRemap: rejected))
    report.expect(
        first.editorViewState == beforeA, cppID: id,
        message: "A173 rejected live remap leaves the selected sibling view state unchanged")
    report.expect(
        second.editorViewState == beforeB, cppID: id,
        message: "A174 rejected live remap leaves the background origin view state unchanged")
    report.expect(
        (try? second.document.state.file.encoded()) == rejectedMidi, cppID: id,
        message: "A175 rejected live remap leaves all MIDI bytes unchanged")
    report.expect(
        second.document.revision == rejectedRevision, cppID: id,
        message: "A176 rejected live remap leaves document revision unchanged")
    report.expect(
        EditorViewStateCodec.load(store: PreferencesStore()) == rejectedSettings, cppID: id,
        message: "A177 rejected live remap leaves persisted preferences unchanged")
    report.expect(
        originCount == 0, cppID: id,
        message: "A179 rejected live remap emits no origin notification")
    report.expect(
        hubCount == 0, cppID: id,
        message: "A180 rejected live remap emits no workspace notification")
    report.expect(
        persistedCount == 0, cppID: id,
        message: "A181 rejected live remap finishes no preference write")
    let isolationID = "host/HostIntegrationTest::nonSelectedEditorStateFansOutWithoutTouchingSongBytes"
    guard let firstBytes = try? first.document.state.file.encoded(),
        let secondBytes = try? second.document.state.file.encoded()
    else {
        report.fail(isolationID, "both song baselines must be encodable before background fanout")
        return
    }
    let firstRevision = first.document.revision
    let secondRevision = second.document.revision
    let firstDepth = first.document.history.undoCount
    let secondDepth = second.document.history.undoCount
    var isolated = seed
    isolated.chrome.automation = .init(visible: false, height: 44)
    isolated.chrome.voiceChanges = .init(visible: true, height: 149)
    isolated.chrome.activePage = .voiceChanges
    isolated.lanes.laneRanges["cc:0:74"] = 96
    originCount = 0
    siblingCount = 0
    hubCount = 0
    persistedCount = 0
    guard second.setEditorViewState(isolated) else {
        report.fail(isolationID, "background origin refused the fork-literal editor state")
        return
    }
    report.expect(
        hubCount == 1, cppID: isolationID,
        message: "A150 background editor state publishes exactly once")
    report.expect(
        persistedCount == 1, cppID: isolationID,
        message: "A151 background editor state persists exactly once")
    report.expect(
        second.editorViewState == isolated, cppID: isolationID,
        message: "A152 background origin reads back the fork-literal editor state")
    report.expect(
        first.editorViewState == isolated, cppID: isolationID,
        message: "A153 selected sibling reads back the fork-literal editor state")
    report.expect(
        EditorViewStateCodec.load(store: PreferencesStore()) == isolated,
        cppID: isolationID, message: "synchronized preferences retain the literal background state")
    report.expect(
        (try? first.document.state.file.encoded()) == firstBytes, cppID: isolationID,
        message: "A155 selected sibling song bytes survive background fanout")
    report.expect(
        (try? second.document.state.file.encoded()) == secondBytes, cppID: isolationID,
        message: "A156 background origin song bytes survive background fanout")
    report.expect(
        first.document.revision == firstRevision, cppID: isolationID,
        message: "A157 selected sibling revision survives background fanout")
    report.expect(
        second.document.revision == secondRevision, cppID: isolationID,
        message: "A158 background origin revision survives background fanout")
    report.expect(
        first.document.history.undoCount == firstDepth, cppID: isolationID,
        message: "A159 selected sibling history depth survives background fanout")
    report.expect(
        second.document.history.undoCount == secondDepth, cppID: isolationID,
        message: "A160 background origin history depth survives background fanout")
    report.expect(
        originCount == 1 && siblingCount == 0, cppID: isolationID,
        message: "background origin alone emits its local editor notification")

    let seamsID = "host/HostSeamsTest::documentChangedPreservesCosmetics"
    var cosmetics = EditorViewState()
    cosmetics.chrome.velocity = .init(visible: true, height: 180)
    cosmetics.chrome.activePage = .velocity
    guard first.setEditorViewState(cosmetics) else {
        report.fail(seamsID, "selected document must accept cosmetic state")
        return
    }
    app.automationPage().refreshFromDocument()
    app.velocityPage().refreshFromDocument()
    app.voiceChangesPage().refreshFromDocument()
    report.expect(
        first.editorViewState == cosmetics, cppID: seamsID,
        message: "A028 three drawer document-changed deliveries preserve exact cosmetic state")

    let freshID = "host/HostIntegrationTest::documentMutationUndoRedoAndReloadPreemptPreview"
    let depthID = "host/HostIntegrationTest::projectSwitchAndClosePreserveProjectBoundaries"
    guard let selected = second.document.notes(in: 0).first else {
        report.fail(freshID, "second song must contain a selectable note")
        return
    }
    app.songTabs.selectTab(tabId: secondID)
    guard let oldTab = app.songTabs.selectedPage, app.selectedDocument === second else {
        report.fail(freshID, "second song must be the selected ready tab")
        return
    }
    second.setSelectedNotes([selected.id])
    app.songTabs.requestClose(tabId: oldTab.tabId)
    guard until({ app.songTabs.tabCount == 1 }) else {
        report.fail(freshID, "clean second tab did not close before fresh binding")
        return
    }
    app.openSong(label: "mus_session_test2")
    guard until({ app.songTabs.tabCount == 2 || !app.lastSaveError.isEmpty }),
        let reopened = app.selectedDocument, reopened !== second,
        let reopenedTab = app.songTabs.selectedPage, reopenedTab.tabId != oldTab.tabId
    else {
        report.fail(freshID, "same song did not reopen through a fresh tab binding")
        return
    }
    report.expect(
        reopened.document.history.undoCount == freshSecondDepth, cppID: depthID,
        message: "A172 second song fresh open restores its independently recorded history depth")
    report.expect(
        reopened.document.history.undoCount == 0, cppID: freshID,
        message: "A135 fresh same-song tab has zero undo history")
    report.expect(
        reopened.selectedNotes.isEmpty, cppID: freshID,
        message: "A136 fresh same-song tab has no selected notes")

    var invalidCopy = seed
    report.expect(
        !invalidCopy.remapEngineTracks([0, 0]), cppID: id,
        message: "A182 duplicate track destinations reject the pure complete-value remap")
    report.expect(
        invalidCopy == seed, cppID: id,
        message: "A183 rejected pure remap preserves every original editor-value member")
}
