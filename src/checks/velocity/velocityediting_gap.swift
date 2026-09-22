import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

private func drawerVelocityLegacyMidi(includeOverlap: Bool = false,
                                      loudVelocity: Int = 70) -> MidiFile {
    let conductor: [MidiEvent] = [
        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
    ]
    var notes: [MidiEvent] = [
        .channel(tick: 0, status: 0xC0, data0: 0),
        .channel(tick: 12, status: 0x90, data0: 60, data1: 20),
        .channel(tick: 12, status: 0x90, data0: 60, data1: UInt8(loudVelocity)),
    ]
    if includeOverlap {
        notes.append(.channel(tick: 20, status: 0x90, data0: 60, data1: 20))
    }
    notes.append(contentsOf: [
        .channel(tick: 36, status: 0x80, data0: 60),
        .channel(tick: 36, status: 0x80, data0: 60),
    ])
    if includeOverlap {
        notes.append(.channel(tick: 44, status: 0x80, data0: 60))
    }
    notes.append(contentsOf: [
        .channel(tick: 60, status: 0x90, data0: 64, data1: 70),
        .channel(tick: 84, status: 0x80, data0: 64),
    ])
    return MidiFile(division: 24, chunks: [
        MidiChunk(events: conductor, endTick: 84),
        MidiChunk(events: notes, endTick: 84),
    ])
}

@MainActor
struct drawerVelocityLegacyFixture {
    let session: DocumentSession
    let page: VelocityPage
    let document: SongDocument
    let notes: [Note]

    init(session suite: DocumentSession, service: ProjectService,
         includeOverlap: Bool = false, loudVelocity: Int = 70) {
        let document = SongDocument(
            file: drawerVelocityLegacyMidi(includeOverlap: includeOverlap,
                                           loudVelocity: loudVelocity),
            config: suite.document.state.config,
            source: SongSource(label: "velocity-editing",
                               midiPath: suite.document.source.midiPath,
                               hasConfig: suite.document.source.hasConfig),
            trackBudget: suite.document.trackBudget)
        let session = DocumentSession(document: document, service: service,
                                      lease: suite.bankLease, slots: suite.bankSlots,
                                      dirty: false, loadName: suite.bankLoadName,
                                      sampleRate: 48_000)
        session.selectedTrack = 0
        session.clearSelectedNotes()
        page = VelocityPage(baseFontPx: 13)
        self.session = session
        self.document = document
        notes = document.notes(in: 0)
        page.attach(session: session, palette: GridPalette())
        page.configureBody(width: 400, height: 120, rulerWidth: 56,
                           devicePixelRatio: 1, baseFontPx: 13, dragDistance: 10)
    }

    func handle(_ note: Note) -> VelocityHandleValue? {
        page.publishedHandlesSnapshot.first { $0.noteID == note.id }
    }
}


@MainActor
private func velocityGapRows(_ report: CheckReport, _ cppID: String,
                             _ rows: [(String, Bool)]) {
    for (row, predicate) in rows {
        report.expect(predicate, cppID: cppID, message: row)
    }
}

@MainActor
private func velocityTimelineValue(_ session: DocumentSession, _ id: NoteID) -> Int? {
    session.timeline.events.first { $0.noteID == id && $0.data1 > 0 }.map { Int($0.data1) }
}

 

@MainActor
func drawerVelocityEditingGapPredicates(_ report: CheckReport, session: DocumentSession,
                                        service: ProjectService) {
    let id = "velocity/tst_velocityediting.cpp"

    let setup = drawerVelocityLegacyFixture(session: session, service: service)
    let setupPage = setup.page
    setupPage.setUseDetents(enabled: false)
    let setupNotes = setup.notes
    let setupHandles = setupPage.publishedHandlesSnapshot
    velocityGapRows(report, id, [
        ("A001", setup.document.source.label == "velocity-editing"),
        ("A002", setup.session.bankLease === session.bankLease
            && !setup.session.bankSlots.isEmpty),
        ("A003", setupPage.contextDiagnostic.isEmpty),
        ("A004", setupPage.session === setup.session && setupPage.publishedNoteCount == 3),
        ("A005", setup.session.bankLease === session.bankLease),
        ("A006", setupNotes.count == 3),
        ("A007", setupNotes.count == 3 && setupNotes[0].id != setupNotes[1].id
            && setupNotes[0].velocity == 20 && setupNotes[1].velocity == 70
            && setupNotes[2].tick == 60 && setupNotes[2].velocity == 70),
        ("A008", setupPage.plotWidth > 0 && setupPage.plotHeight > 0),
        ("A009", setupPage.session === setup.session),
        ("A010", setupPage.session != nil && setupPage.plotWidth == 400),
        ("A011", setupPage.axisModel.drawableSpan > 0),
        ("A012", setupHandles.count == 3 && setupPage.publishedNoteCount == 3),
        ("A013", setup.session.camera.pixelsPerTick > 0),
        ("A015", setupPage.plotWidth > 0 && setupPage.plotHeight > 0),
        ("A017", setupPage.axisModel.drawableSpan > 0),
        ("A018", !setupPage.axisGraduationsVisible),
        ("A019", setupHandles.allSatisfy { $0.x >= 0 && $0.x <= setupPage.plotWidth
            && $0.y >= 0 && $0.y <= setupPage.plotHeight }),
    ])

    let drag = drawerVelocityLegacyFixture(session: session, service: service)
    let dragPage = drag.page
    dragPage.setUseDetents(enabled: false)
    let dragDocument = drag.document
    let dragNotes = drag.notes
    guard dragNotes.count == 3, let dragHandle = drag.handle(dragNotes[0]) else {
        report.fail(id, "drag fixture admission failed")
        return
    }
    drag.session.setSelectedNotes([dragNotes[0].id, dragNotes[2].id])
    dragPage.refreshFromDocument()
    let sessionBridge = dragDocument.onChange
    var documentChangeCount = 0
    dragDocument.onChange = { change in
        documentChangeCount += 1
        sessionBridge?(change)
    }
    var editedCount = 0
    drag.session.onChange = { change in
        if change.domains.contains(.document) { editedCount += 1 }
    }
    let dragBaseline = drawerVelocityDocumentSnapshot(dragDocument)
    velocityGapRows(report, id, [
        ("A021", dragDocument.onChange != nil),
        ("A022", drag.session.onChange != nil),
    ])
    _ = dragPage.pointerPress(x: dragHandle.x, y: dragHandle.y, surface: 1,
                              button: 1, modifiers: 0)
    _ = dragPage.pointerMove(x: dragHandle.x, y: dragPage.axisModel.velocityToY(48), buttons: 1)
    velocityGapRows(report, id, [
        ("A023", dragDocument.revision == dragBaseline.revision),
        ("A024", dragDocument.history.currentIdentity == dragBaseline.identity),
        ("A025", documentChangeCount == 0),
        ("A026", editedCount == 0),
        ("A027", dragDocument.note(dragNotes[0].id)?.velocity == 20),
        ("A028", dragDocument.note(dragNotes[2].id)?.velocity == 70),
        ("A029", dragDocument.note(dragNotes[1].id)?.velocity == 70),
        ("A030", velocityTimelineValue(drag.session, dragNotes[0].id) == 20),
        ("A031", velocityTimelineValue(drag.session, dragNotes[2].id) == 70),
        ("A032", velocityTimelineValue(drag.session, dragNotes[1].id) == 70),
        ("A033", dragPage.frozenPreview[dragNotes[0].id] != nil),
        ("A034", dragPage.frozenPreview[dragNotes[2].id] != nil),
        ("A035", dragPage.frozenPreview[dragNotes[0].id] == 48),
        ("A036", dragPage.frozenPreview[dragNotes[2].id] == 98),
        ("A037", dragPage.frozenPreview[dragNotes[1].id] == nil),
        ("A038", drag.session.selectedNoteOrder == [dragNotes[0].id, dragNotes[2].id]),
    ])
    _ = dragPage.pointerMove(x: dragHandle.x, y: dragPage.axisModel.velocityToY(16), buttons: 1)
    velocityGapRows(report, id, [
        ("A039", dragDocument.revision == dragBaseline.revision),
        ("A040", dragDocument.history.currentIdentity == dragBaseline.identity),
        ("A041", documentChangeCount == 0),
        ("A042", dragDocument.note(dragNotes[0].id)?.velocity == 20),
        ("A043", dragDocument.note(dragNotes[2].id)?.velocity == 70),
        ("A044", dragDocument.note(dragNotes[1].id)?.velocity == 70),
        ("A045", velocityTimelineValue(drag.session, dragNotes[0].id) == 20),
        ("A046", velocityTimelineValue(drag.session, dragNotes[2].id) == 70),
        ("A047", velocityTimelineValue(drag.session, dragNotes[1].id) == 70),
        ("A048", dragPage.frozenPreview[dragNotes[0].id] != nil),
        ("A049", dragPage.frozenPreview[dragNotes[2].id] != nil),
        ("A050", dragPage.frozenPreview[dragNotes[0].id] == 16),
        ("A051", dragPage.frozenPreview[dragNotes[2].id] == 66),
    ])
    _ = dragPage.pointerRelease(x: dragHandle.x, y: dragPage.axisModel.velocityToY(16), button: 1)
    let dragCommitted = drawerVelocityDocumentSnapshot(dragDocument)
    velocityGapRows(report, id, [
        ("A052", documentChangeCount == 1),
        ("A053", editedCount == 1),
        ("A054", dragCommitted.revision == dragBaseline.revision + 1),
        ("A055", dragDocument.history.canUndo && !dragDocument.history.canRedo),
        ("A056", dragPage.frozenPreview[dragNotes[0].id] == nil),
        ("A057", dragPage.frozenPreview[dragNotes[2].id] == nil),
        ("A058", dragPage.frozenPreview[dragNotes[1].id] == nil),
        ("A059", dragDocument.note(dragNotes[0].id)?.velocity == 16),
        ("A060", dragDocument.note(dragNotes[2].id)?.velocity == 66),
        ("A061", dragDocument.note(dragNotes[1].id)?.velocity == 70),
        ("A062", drag.session.selectedNoteOrder == [dragNotes[0].id, dragNotes[2].id]),
        ("A063", velocityTimelineValue(drag.session, dragNotes[0].id) == 16),
        ("A064", velocityTimelineValue(drag.session, dragNotes[2].id) == 66),
        ("A065", velocityTimelineValue(drag.session, dragNotes[1].id) == 70),
        ("A066", dragDocument.history.canUndo),
    ])
    let didUndo = dragDocument.history.undoDocument()
    velocityGapRows(report, id, [
        ("A067", didUndo),
        ("A068", dragDocument.note(dragNotes[0].id)?.velocity == 20),
        ("A069", dragDocument.note(dragNotes[2].id)?.velocity == 70),
        ("A070", dragDocument.note(dragNotes[1].id)?.velocity == 70),
        ("A071", drag.session.selectedNoteOrder == [dragNotes[0].id, dragNotes[2].id]),
        ("A072", velocityTimelineValue(drag.session, dragNotes[0].id) == 20),
        ("A073", velocityTimelineValue(drag.session, dragNotes[2].id) == 70),
        ("A074", velocityTimelineValue(drag.session, dragNotes[1].id) == 70),
        ("A075", dragDocument.history.canRedo),
    ])
    let didRedo = dragDocument.history.redoDocument()
    velocityGapRows(report, id, [
        ("A076", didRedo),
        ("A077", dragDocument.note(dragNotes[0].id)?.velocity == 16),
        ("A078", dragDocument.note(dragNotes[2].id)?.velocity == 66),
        ("A079", dragDocument.note(dragNotes[1].id)?.velocity == 70),
        ("A080", velocityTimelineValue(drag.session, dragNotes[0].id) == 16),
        ("A081", velocityTimelineValue(drag.session, dragNotes[2].id) == 66),
        ("A082", velocityTimelineValue(drag.session, dragNotes[1].id) == 70),
    ])

    let cancel = drawerVelocityLegacyFixture(session: session, service: service)
    let cancelPage = cancel.page
    cancelPage.setUseDetents(enabled: false)
    let cancelDocument = cancel.document
    let cancelNotes = cancel.notes
    guard cancelNotes.count == 3, let cancelHandle = cancel.handle(cancelNotes[0]) else {
        report.fail(id, "cancel fixture admission failed")
        return
    }
    cancel.session.setSelectedNotes([cancelNotes[0].id, cancelNotes[2].id])
    cancelPage.refreshFromDocument()
    let cancelBaseline = drawerVelocityDocumentSnapshot(cancelDocument)
    _ = cancelPage.pointerPress(x: cancelHandle.x, y: cancelHandle.y, surface: 1,
                                button: 1, modifiers: 0)
    _ = cancelPage.pointerMove(x: cancelHandle.x, y: cancelPage.axisModel.velocityToY(48),
                               buttons: 1)
    velocityGapRows(report, id, [
        ("A083", cancelPage.frozenPreview[cancelNotes[0].id] != nil),
        ("A084", cancelPage.frozenPreview[cancelNotes[2].id] != nil),
        ("A085", cancelPage.frozenPreview[cancelNotes[0].id] == 48),
        ("A086", cancelPage.frozenPreview[cancelNotes[2].id] == 98),
    ])
    _ = cancelPage.pointerMove(x: cancelHandle.x, y: cancelPage.axisModel.velocityToY(16),
                               buttons: 1)
    velocityGapRows(report, id, [
        ("A087", cancelPage.frozenPreview[cancelNotes[0].id] != nil),
        ("A088", cancelPage.frozenPreview[cancelNotes[2].id] != nil),
        ("A089", cancelPage.frozenPreview[cancelNotes[0].id] == 16),
        ("A090", cancelPage.frozenPreview[cancelNotes[2].id] == 66),
    ])
    _ = cancelPage.handleEscape()
    velocityGapRows(report, id, [
        ("A091", cancelPage.frozenPreview[cancelNotes[0].id] == nil),
        ("A092", cancelPage.frozenPreview[cancelNotes[2].id] == nil),
        ("A093", cancelDocument.revision == cancelBaseline.revision),
        ("A094", cancelDocument.history.currentIdentity == cancelBaseline.identity),
        ("A095", cancel.session.selectedNoteOrder == [cancelNotes[0].id, cancelNotes[2].id]),
        ("A096", cancelDocument.note(cancelNotes[0].id)?.velocity == 20),
        ("A097", cancelDocument.note(cancelNotes[2].id)?.velocity == 70),
        ("A098", cancelDocument.note(cancelNotes[1].id)?.velocity == 70),
        ("A099", velocityTimelineValue(cancel.session, cancelNotes[0].id) == 20),
        ("A100", velocityTimelineValue(cancel.session, cancelNotes[2].id) == 70),
        ("A101", velocityTimelineValue(cancel.session, cancelNotes[1].id) == 70),
    ])
    _ = cancelPage.pointerMove(x: cancelHandle.x, y: cancelPage.axisModel.velocityToY(48),
                               buttons: 1)
    _ = cancelPage.pointerRelease(x: cancelHandle.x, y: cancelPage.axisModel.velocityToY(48),
                                  button: 1)
    velocityGapRows(report, id, [
        ("A102", cancelPage.frozenPreview[cancelNotes[0].id] == nil),
        ("A103", cancelPage.frozenPreview[cancelNotes[2].id] == nil),
        ("A104", cancelDocument.revision == cancelBaseline.revision),
        ("A105", cancelDocument.history.currentIdentity == cancelBaseline.identity),
        ("A106", cancelDocument.note(cancelNotes[0].id)?.velocity == 20),
        ("A107", cancelDocument.note(cancelNotes[2].id)?.velocity == 70),
        ("A108", cancelDocument.note(cancelNotes[1].id)?.velocity == 70),
        ("A109", velocityTimelineValue(cancel.session, cancelNotes[0].id) == 20),
        ("A110", velocityTimelineValue(cancel.session, cancelNotes[2].id) == 70),
        ("A111", velocityTimelineValue(cancel.session, cancelNotes[1].id) == 70),
    ])

    let click = drawerVelocityLegacyFixture(session: session, service: service)
    let clickPage = click.page
    clickPage.setUseDetents(enabled: false)
    let clickDocument = click.document
    let clickNotes = click.notes
    guard clickNotes.count == 3, let clickHandle = click.handle(clickNotes[0]) else {
        report.fail(id, "stationary-click fixture admission failed")
        return
    }
    let clickBaseline = drawerVelocityDocumentSnapshot(clickDocument)
    velocityGapRows(report, id, [("A112", click.session.selectedNotes.isEmpty)])
    _ = clickPage.pointerPress(x: clickHandle.x, y: clickHandle.y, surface: 1,
                               button: 1, modifiers: 0)
    velocityGapRows(report, id, [
        ("A113", clickPage.frozenPreview[clickNotes[0].id] == nil
            || clickPage.frozenPreview[clickNotes[0].id] == 20),
    ])
    _ = clickPage.pointerRelease(x: clickHandle.x, y: clickHandle.y, button: 1)
    velocityGapRows(report, id, [
        ("A114", clickDocument.revision == clickBaseline.revision),
        ("A115", clickDocument.history.currentIdentity == clickBaseline.identity),
        ("A116", clickPage.frozenPreview[clickNotes[0].id] == nil),
        ("A117", clickPage.frozenPreview[clickNotes[2].id] == nil),
        ("A118", clickDocument.note(clickNotes[0].id)?.velocity == 20),
        ("A119", clickDocument.note(clickNotes[1].id)?.velocity == 70),
        ("A120", clickDocument.note(clickNotes[2].id)?.velocity == 70),
        ("A121", velocityTimelineValue(click.session, clickNotes[0].id) == 20),
        ("A122", velocityTimelineValue(click.session, clickNotes[1].id) == 70),
        ("A123", velocityTimelineValue(click.session, clickNotes[2].id) == 70),
        ("A124", click.session.selectedNoteOrder == [clickNotes[0].id]),
        ("A125", drag.session.selectedNoteOrder == [dragNotes[0].id, dragNotes[2].id]),
    ])

    let focus = drawerVelocityLegacyFixture(session: session, service: service)
    guard let focusNote = focus.notes.first, let focusHandle = focus.handle(focusNote) else {
        report.fail(id, "focus fixture admission failed")
        return
    }
    let focusConsumed = focus.page.pointerPress(x: focusHandle.x, y: focusHandle.y, surface: 1,
                                                button: 1, modifiers: 0)
    velocityGapRows(report, id, [
        ("A126", focusConsumed),
        ("A127", focus.page.observation.gestureKind == .relative
            && focus.page.observation.targetNoteID == focusNote.id),
    ])
    focus.page.cancelSectionInteraction()
}
