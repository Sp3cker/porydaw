import Foundation
@testable import PorydawApp
import PorydawCore

// Existing scenarios paired with voicemenus.cpp.
// Entry order remains in VoiceChangesPageChecks.swift.

@MainActor
func drawerVoiceContextMenuTransactions(_ report: CheckReport, suite: DocumentSession,
                                     service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let target = VoiceOccurrence(fixture.lanePoints()[1])

    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expect(page.hasMenu && page.menuOpen, cppID: drawerVoiceMenuID,
                  message: "a right press on a marker opens the context menu")
    report.expectEqual([VoiceChangesPagePolicy.changeVoiceAction,
                        VoiceChangesPagePolicy.deleteMarkerAction],
                       page.menuRowActions, cppID: drawerVoiceMenuID,
                       what: "a marker target publishes the change and delete rows")
    report.expectEqual(target.text, page.menuTargetIdentity, cppID: drawerVoiceMenuID,
                       what: "the menu captured the pressed occurrence")
    report.expectEqual(48, page.menuTargetTick, cppID: drawerVoiceMenuID,
                       what: "the menu captured the marker's own tick")
    report.expect(page.interactionActive, cppID: drawerVoiceMenuID,
                  message: "an open menu reports an active interaction")

    // A camera scroll after the open neither drifts the capture nor closes it.
    fixture.session.mutateCamera { $0.setHScroll($0.snapshot.scrollX + 80) }
    report.expect(page.hasMenu, cppID: drawerVoiceMenuID, message: "a camera scroll keeps the menu open")
    report.expectEqual(target.text, page.menuTargetIdentity, cppID: drawerVoiceMenuID,
                       what: "a camera scroll does not drift the captured identity")
    report.expectEqual(48, page.menuTargetTick, cppID: drawerVoiceMenuID,
                       what: "a camera scroll does not drift the captured tick")

    // Outside dismissal writes nothing.
    let baseline = fixture.snapshot
    page.dismissVoiceMenu()
    report.expect(!page.hasMenu && !page.menuOpen, cppID: drawerVoiceMenuID,
                  message: "the outside dismissal closes the menu")
    report.expect(!page.interactionActive, cppID: drawerVoiceMenuID,
                  message: "the dismissal releases the follow-scroll gate")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceMenuID,
                       what: "the dismissal writes nothing")

    // The delete row removes exactly the captured occurrence.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expect(page.activateMenuAction(actionId: VoiceChangesPagePolicy.deleteMarkerAction),
                  cppID: drawerVoiceMenuID, message: "the delete row deletes the captured marker")
    report.expect(VoiceLanePolicy.occurrence(at: 48, in: fixture.lanePoints()) == nil,
                  cppID: drawerVoiceMenuID, message: "the deleted tick no longer holds a change")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: drawerVoiceMenuID,
                       what: "the deletion is one revision")
    report.expect(fixture.snapshot.canUndo && !baseline.canUndo, cppID: drawerVoiceMenuID,
                  message: "the deletion records one history entry")
    report.expectEqual([0, 120], page.markerTicks, cppID: drawerVoiceMenuID,
                       what: "the projection drops exactly the deleted marker")

    // An empty-lane target offers the insertion row, which hands the same
    // captured target to the picker.
    _ = page.pointerPress(x: fixture.markerX(96), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expectEqual([VoiceChangesPagePolicy.insertVoiceChangeAction], page.menuRowActions,
                       cppID: drawerVoiceMenuID, what: "an empty-lane target publishes the insert row")
    report.expect(page.menuTargetIdentity == nil, cppID: drawerVoiceMenuID,
                  message: "the empty-lane target carries no occurrence")
    report.expect(page.activateMenuAction(actionId: VoiceChangesPagePolicy.insertVoiceChangeAction),
                  cppID: drawerVoiceMenuID, message: "the insert row opens the picker")
    report.expect(page.hasPicker, cppID: drawerVoiceMenuID, message: "the picker opens on the capture")
    report.expectEqual(96, page.pickerTargetTick, cppID: drawerVoiceMenuID,
                       what: "the picker inherits the menu's captured tick")
    report.expectEqual("Insert voice change", page.pickerTitle, cppID: drawerVoiceMenuID,
                       what: "the inherited empty-lane capture keeps the insertion title")
    report.expect(!page.hasMenu, cppID: drawerVoiceMenuID, message: "the activation consumed the menu")
    page.cancelPicker()

    // A stale menu — a rewrite between the open and the activation — writes
    // nothing, and its rows never fire.
    _ = page.pointerPress(x: fixture.markerX(120), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expect(page.hasMenu, cppID: drawerVoiceMenuID, message: "the menu reopened on the third marker")
    fixture.document.writeLane(track: 0, lane: .voice, from: 0, through: 0,
                               points: [LaneWrite(tick: 0, value: programs[2])])
    page.refreshFromDocument()
    report.expect(!page.hasMenu, cppID: drawerVoiceMenuID,
                  message: "a document change cancels the open menu")
    let rewritten = fixture.snapshot
    report.expect(!page.activateMenuAction(actionId: VoiceChangesPagePolicy.deleteMarkerAction),
                  cppID: drawerVoiceMenuID, message: "an activation after the cancellation writes nothing")
    report.expectEqual(rewritten, fixture.snapshot, cppID: drawerVoiceMenuID,
                       what: "the stale activation leaves the rewrite as the only change")
}

@MainActor
func drawerVoiceOriginalMenuTransactions(_ report: CheckReport, suite: DocumentSession,
                                                service: ProjectService) {
    // [f3069ef:drawerpresentation/fixtures.cpp:44-62,406] Original MIDI fixture,
    // including the undoable setup insertion of program3 at48 before snapshot.
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.meta(type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 384),
        MidiChunk(events: [.channel(status: 0xC0, data0: 0),
                           .channel(status: 0x90, data0: 60, data1: 100),
                           .channel(tick: 48, status: 0x80, data0: 60)], endTick: 384),
        MidiChunk(events: [.channel(status: 0xC1, data0: 5),
                           .channel(status: 0x91, data0: 48, data1: 100),
                           .channel(tick: 48, status: 0x81, data0: 48)], endTick: 384),
    ]), config: suite.document.state.config, source: suite.document.source,
       trackBudget: suite.document.trackBudget)
    document.writeLane(track: 0, lane: .voice, from: 48, through: 48,
                       points: [LaneWrite(tick: 48, value: 3)])
    let session = DocumentSession(document: document, service: service, lease: suite.bankLease,
                                  slots: suite.bankSlots, dirty: false,
                                  loadName: suite.bankLoadName, sampleRate: 48_000)
    session.selectedTrack = 0
    let page = VoiceChangesPage(baseFontPx: 13)
    page.attach(session: session, palette: GridPalette())
    page.configureBody(width: 1000, height: 160, gutter: 56, devicePixelRatio: 1,
                       baseFontPx: 13, dragDistance: 10)
    session.onChange = { [weak page] change in
        if !change.domains.intersection([.document, .selection, .bank]).isEmpty {
            page?.refreshFromDocument()
        }
    }
    func expect(_ condition: @autoclosure () -> Bool, _ line: Int) {
        report.expect(condition(), cppID: "drawerpresentation/DrawerPresentationTest::voiceContextMenuTransactions",
                      message: "voicemenus.cpp:\(line)")
    }
    func bytes() -> [UInt8] { try! document.captureSave().bytes }
    func value() -> Int? {
        document.lanePoints(track: 0, lane: .voice).first { $0.tick == 144 }?.value
    }
    func openMenu() {
        _ = page.pointerPress(x: session.camera.displayX(tick: 144, origin: 0, dpr: 1),
                              y: 10, surface: 1, button: 2, modifiers: 0)
    }
    let before = drawerVoiceVoiceDocumentSnapshot(document)
    let beforeBytes = bytes()
    openMenu()
    expect(page.menuOpen && page.menuTargetTick == 144, 111)
    _ = page.activateMenuAction(actionId: VoiceChangesPagePolicy.insertVoiceChangeAction)
    expect(page.pickerOpen && page.pickerTargetTick == 144, 115)
    expect(!page.menuOpen, 116)
    page.setPickerFilter(text: "007")
    expect(page.pickerRowPrograms == [7] && page.pickerIndex == 0, 119)
    _ = page.acceptPicker()
    expect(!page.pickerOpen, 121)
    expect(value() != nil, 124)
    expect(value() == 7, 125)
    expect(document.revision == before.revision + 1, 126)
    let inserted = drawerVoiceVoiceDocumentSnapshot(document)
    let insertedBytes = bytes()

    openMenu()
    expect(page.menuOpen && page.menuTargetTick == 144, 134)
    _ = page.activateMenuAction(actionId: VoiceChangesPagePolicy.changeVoiceAction)
    expect(page.pickerOpen, 137)
    expect(page.pickerIndex == 7, 138)
    page.setPickerFilter(text: "003")
    expect(page.pickerRowPrograms == [3] && page.pickerIndex == 0, 140)
    _ = page.acceptPicker()
    expect(!page.pickerOpen, 142)
    expect(value() != nil, 143)
    expect(value() == 3, 144)
    expect(document.revision == inserted.revision + 1, 145)
    let changed = drawerVoiceVoiceDocumentSnapshot(document)
    let changedBytes = bytes()

    openMenu()
    expect(page.menuOpen && page.menuTargetTick == 144, 153)
    _ = page.activateMenuAction(actionId: VoiceChangesPagePolicy.deleteMarkerAction)
    expect(!page.menuOpen, 156)
    expect(value() == nil, 157)
    expect(document.revision == changed.revision + 1, 158)

    // The original's three undo steps also prove each exact history delta:
    // every step must return the full serialized state AND checkpoint identity.
    _ = document.history.undoDocument()
    expect(bytes() == changedBytes && document.history.currentIdentity == changed.identity, 159)
    expect(value() != nil, 163)
    expect(value() == 3, 164)
    _ = document.history.undoDocument()
    expect(bytes() == insertedBytes && document.history.currentIdentity == inserted.identity, 146)
    expect(value() != nil, 166)
    expect(value() == 7, 167)
    _ = document.history.undoDocument()
    expect(bytes() == beforeBytes && document.history.currentIdentity == before.identity
        && document.history.canUndo == before.canUndo, 127)
    expect(value() == nil, 169)
    expect(bytes() == beforeBytes, 170)
}
