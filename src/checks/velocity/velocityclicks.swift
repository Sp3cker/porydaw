import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

private func drawerVelocityClickMidi() -> MidiFile {
    let conductor: [MidiEvent] = [
        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
    ]
    let notes: [MidiEvent] = [
        .channel(tick: 0, status: 0xC0, data0: 0),
        .channel(tick: 12, status: 0x90, data0: 60, data1: 20),
        .channel(tick: 12, status: 0x90, data0: 60, data1: 70),
        .channel(tick: 36, status: 0x80, data0: 60),
        .channel(tick: 36, status: 0x80, data0: 60),
        .channel(tick: 60, status: 0x90, data0: 64, data1: 70),
        .channel(tick: 84, status: 0x80, data0: 64),
    ]
    return MidiFile(division: 24, chunks: [
        MidiChunk(events: conductor, endTick: 84),
        MidiChunk(events: notes, endTick: 84),
    ])
}

@MainActor
private struct drawerVelocityClickFixture {
    let session: DocumentSession
    let page: VelocityPage
    let document: SongDocument
    let quiet: Note
    let loud: Note
    let later: Note

    init?(session suite: DocumentSession, service: ProjectService) {
        let document = SongDocument(file: drawerVelocityClickMidi(),
                                    config: suite.document.state.config,
                                    source: suite.document.source,
                                    trackBudget: suite.document.trackBudget)
        let session = DocumentSession(document: document, service: service,
                                      lease: suite.bankLease, slots: suite.bankSlots,
                                      dirty: false, loadName: suite.bankLoadName,
                                      sampleRate: 48_000)
        session.selectedTrack = 0
        let notes = document.notes(in: 0)
        guard notes.count == 3 else { return nil }
        self.session = session
        self.document = document
        quiet = notes[0]
        loud = notes[1]
        later = notes[2]
        page = VelocityPage(baseFontPx: 13)
        page.attach(session: session, palette: GridPalette())
        page.configureBody(width: 400, height: 120, rulerWidth: 56,
                           devicePixelRatio: 1, baseFontPx: 13, dragDistance: 10)
    }

    func handle(_ note: Note) -> VelocityHandleValue? {
        page.publishedHandlesSnapshot.first { $0.noteID == note.id }
    }
}

@MainActor
func drawerVelocityExactClickSequences(_ report: CheckReport, session: DocumentSession,
                                       service: ProjectService) {
    guard let blank = drawerVelocityClickFixture(session: session, service: service),
          let ruler = drawerVelocityClickFixture(session: session, service: service),
          let paint = drawerVelocityClickFixture(session: session, service: service) else {
        report.fail(drawerVelocityExactClicksID,
                    "the stacked click fixture did not produce exactly three notes")
        return
    }

    report.expect(blank.quiet.velocity == 20 && blank.loud.velocity == 70
                      && blank.later.tick == 60 && blank.later.velocity == 70,
                  cppID: drawerVelocityExactClicksID,
                  message: "the click fixture preserves the original stacked-note order")

    // Blank plot click: release clears the ordered selection, but neither edge
    // writes document history.
    blank.session.setSelectedNotes([blank.quiet.id, blank.later.id])
    blank.page.refreshFromDocument()
    report.expect(blank.session.selectedNotes == [blank.quiet.id, blank.later.id],
                  cppID: drawerVelocityExactClicksID,
                  message: "the blank sequence starts with quiet and later selected in order")
    let blankBaseline = drawerVelocityDocumentSnapshot(blank.document)
    let blankY = blank.page.axisModel.velocityToY(40)
    let stemSlop = blank.page.state.body.geometry.durationLineHorizontalSlop
    let rightmost = blank.page.publishedHandlesSnapshot.lazy
        .map { $0.endX + stemSlop }.max() ?? 0
    let blankX = min(399, rightmost + 1)
    report.expect(blankX < blank.page.state.body.plotWidth
                      && blank.page.publishedHandlesSnapshot.allSatisfy {
                          $0.endX + stemSlop < blankX
                      },
                  cppID: drawerVelocityExactClicksID,
                  message: "the blank click is in bounds and right of every note stem")
    report.expect(blank.page.pointerPress(x: blankX, y: blankY, surface: 1,
                                          button: 1, modifiers: 0),
                  cppID: drawerVelocityExactClicksID,
                  message: "the far-right blank press is consumed as a paint candidate")
    report.expect(blank.session.selectedNotes == [blank.quiet.id, blank.later.id],
                  cppID: drawerVelocityExactClicksID,
                  message: "the blank press keeps the ordered selection until release")
    _ = blank.page.pointerRelease(x: blankX, y: blankY, button: 1)
    report.expect(blank.session.selectedNotes.isEmpty, cppID: drawerVelocityExactClicksID,
                  message: "the blank release clears the ordered selection")
    report.expect(drawerVelocityDocumentSnapshot(blank.document) == blankBaseline,
                  cppID: drawerVelocityExactClicksID,
                  message: "the blank click leaves revision and history unchanged")
    report.expect(Int(blank.document.note(blank.quiet.id)?.velocity ?? 0) == 20
                      && Int(blank.document.note(blank.loud.id)?.velocity ?? 0) == 70
                      && Int(blank.document.note(blank.later.id)?.velocity ?? 0) == 70,
                  cppID: drawerVelocityExactClicksID,
                  message: "the blank click changes no document velocity")
    report.expect(blank.handle(blank.quiet)?.value == 20
                      && blank.handle(blank.loud)?.value == 70
                      && blank.handle(blank.later)?.value == 70,
                  cppID: drawerVelocityExactClicksID,
                  message: "the blank click changes no published velocity")

    // Ruler click: both stacked notes commit to 127 on press. Release is inert.
    ruler.session.setSelectedNotes([ruler.quiet.id, ruler.loud.id])
    ruler.page.refreshFromDocument()
    report.expect(ruler.session.selectedNotes == [ruler.quiet.id, ruler.loud.id],
                  cppID: drawerVelocityExactClicksID,
                  message: "the ruler sequence starts with both stacked notes selected")
    let rulerBaseline = drawerVelocityDocumentSnapshot(ruler.document)
    let maximumY = ruler.page.axisModel.velocityToY(127)
    report.expect(ruler.page.pointerPress(x: 10, y: maximumY, surface: 0,
                                          button: 1, modifiers: 0),
                  cppID: drawerVelocityExactClicksID,
                  message: "the ruler press is consumed")
    report.expect(ruler.session.selectedNotes == [ruler.quiet.id, ruler.loud.id],
                  cppID: drawerVelocityExactClicksID,
                  message: "the ruler press preserves the selected stacked pair")
    report.expect(Int(ruler.document.note(ruler.quiet.id)?.velocity ?? 0) == 127
                      && Int(ruler.document.note(ruler.loud.id)?.velocity ?? 0) == 127
                      && Int(ruler.document.note(ruler.later.id)?.velocity ?? 0) == 70,
                  cppID: drawerVelocityExactClicksID,
                  message: "the ruler press commits only the selected stacked notes")
    report.expectEqual(rulerBaseline.revision + 1, ruler.document.revision,
                       cppID: drawerVelocityExactClicksID,
                       what: "the ruler press makes one revision before release")
    let rulerIdentity = ruler.document.history.currentIdentity
    report.expect(rulerIdentity != rulerBaseline.identity,
                  cppID: drawerVelocityExactClicksID,
                  message: "the ruler press makes one history entry")
    _ = ruler.page.pointerRelease(x: 10, y: maximumY, button: 1)
    report.expect(ruler.document.revision == rulerBaseline.revision + 1
                      && ruler.document.history.currentIdentity == rulerIdentity,
                  cppID: drawerVelocityExactClicksID,
                  message: "the ruler release makes no second transaction")
    report.expect(ruler.session.selectedNotes == [ruler.quiet.id, ruler.loud.id],
                  cppID: drawerVelocityExactClicksID,
                  message: "the ruler transaction preserves selection order")
    report.expect(ruler.handle(ruler.quiet)?.value == 127
                      && ruler.handle(ruler.loud)?.value == 127
                      && ruler.handle(ruler.later)?.value == 70,
                  cppID: drawerVelocityExactClicksID,
                  message: "the ruler release leaves the published values at the press result")

    // Plot paint: the press previews 40 without writing; release commits once.
    _ = paint.document.setVelocities(
        [NoteVelocity(noteID: paint.quiet.id, velocity: 1)],
        expectedRevision: paint.document.revision)
    paint.session.setSelectedNotes([paint.loud.id])
    paint.page.refreshFromDocument()
    paint.page.setUseDetents(enabled: false)
    report.expect(Int(paint.document.note(paint.quiet.id)?.velocity ?? 0) == 1
                      && Int(paint.document.note(paint.loud.id)?.velocity ?? 0) == 70
                      && Int(paint.document.note(paint.later.id)?.velocity ?? 0) == 70
                      && paint.session.selectedNotes == [paint.loud.id],
                  cppID: drawerVelocityExactClicksID,
                  message: "the paint setup matches the original quiet/loud/later state")
    guard let loudHandle = paint.handle(paint.loud) else {
        report.fail(drawerVelocityExactClicksID, "the loud stacked handle was not published")
        return
    }
    report.expect(paint.handle(paint.quiet)?.value == 1
                      && paint.handle(paint.loud)?.value == 70
                      && paint.handle(paint.later)?.value == 70,
                  cppID: drawerVelocityExactClicksID,
                  message: "the paint setup publishes the original three velocity values")
    let paintBaseline = drawerVelocityDocumentSnapshot(paint.document)
    let paintY = paint.page.axisModel.velocityToY(40)
    report.expect(paint.page.pointerPress(x: loudHandle.x, y: paintY, surface: 1,
                                          button: 1, modifiers: 0),
                  cppID: drawerVelocityExactClicksID,
                  message: "the plot paint press is consumed")
    report.expectEqual(40, Int(paint.page.frozenPreview[paint.loud.id] ?? 0),
                       cppID: drawerVelocityExactClicksID,
                       what: "the paint press previews velocity 40")
    report.expect(Int(paint.document.note(paint.loud.id)?.velocity ?? 0) == 70
                      && drawerVelocityDocumentSnapshot(paint.document) == paintBaseline,
                  cppID: drawerVelocityExactClicksID,
                  message: "the paint preview does not mutate revision or history")
    report.expect(paint.session.selectedNotes == [paint.loud.id],
                  cppID: drawerVelocityExactClicksID,
                  message: "the paint press keeps the loud stacked note selected")
    _ = paint.page.pointerRelease(x: loudHandle.x, y: paintY, button: 1)
    report.expect(Int(paint.document.note(paint.quiet.id)?.velocity ?? 0) == 1
                      && Int(paint.document.note(paint.loud.id)?.velocity ?? 0) == 40
                      && Int(paint.document.note(paint.later.id)?.velocity ?? 0) == 70,
                  cppID: drawerVelocityExactClicksID,
                  message: "the paint release commits only the selected loud note")
    report.expect(paint.handle(paint.quiet)?.value == 1
                      && paint.handle(paint.loud)?.value == 40
                      && paint.handle(paint.later)?.value == 70,
                  cppID: drawerVelocityExactClicksID,
                  message: "the paint release republishes the committed velocities")
    report.expectEqual(paintBaseline.revision + 1, paint.document.revision,
                       cppID: drawerVelocityExactClicksID,
                       what: "the paint release makes one revision")
    report.expect(paint.document.history.currentIdentity != paintBaseline.identity,
                  cppID: drawerVelocityExactClicksID,
                  message: "the paint release makes one history entry")
    report.expect(paint.session.selectedNotes == [paint.loud.id],
                  cppID: drawerVelocityExactClicksID,
                  message: "the paint transaction preserves the selected loud note")
}
