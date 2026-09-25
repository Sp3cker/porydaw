import Foundation
import PorydawApp
import PorydawCore

// The original resize seed requests a free cell near tick 88. The synthetic
// document has no competing notes, so its six-tick grid cell starts at 84.
private let rulerSeedTick: Tick = 88 - (88 % 6)

@MainActor
func runRulerLoopMenuChecks(_ report: CheckReport, session: DocumentSession) {
    checkRulerLoopSetAndUndo(report, session: session)
    checkRulerSignatureRemoval(report, session: session)
    checkRulerInsertTime(report, session: session)
    checkRenderedRulerMenuCommands(report, session: session)
    checkRulerInsertTimePrompt(report, session: session)
    checkRulerSweepScopeTapAndChip(report, session: session)
    checkRulerSeekEmission(report, session: session)
}

@MainActor
private func rulerMenuDocument(_ session: DocumentSession) -> SongDocument {
    // As in makeResizeSeed, the requested cell has velocity 100. The loop
    // endpoints are its right edge and one snap cell beyond that edge.
    return SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [], endTick: 200),
        MidiChunk(events: [
            .channel(tick: 0, status: 0xC0, data0: 0),
            .channel(tick: rulerSeedTick, status: 0x90, data0: 60, data1: 100),
            .channel(tick: rulerSeedTick + 6, status: 0x80, data0: 60),
        ], endTick: 200),
    ]), config: session.document.state.config, source: session.document.source,
        trackBudget: session.document.trackBudget)
}

@MainActor
private func checkRulerLoopSetAndUndo(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuSetAndTwoStepUndo"
    let document = rulerMenuDocument(session)
    guard let note = document.notes(in: 0).first else {
        report.fail(id, "resize fixture note is absent")
        return
    }
    let snapCell: Tick = 6
    let startTick = note.tick + note.duration
    let endTick = startTick + snapCell
    // The legacy fixture begins with both loop markers removed.
    document.setLoop(end: false, tick: nil)
    document.setLoop(end: true, tick: nil)
    let before = coreTimeBytes(document)
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(timeline.loopStartTick == TimeDefaults.noTick &&
                  timeline.loopEndTick == TimeDefaults.noTick,
                  cppID: id, message: "A004: both markers begin absent")

    document.setLoop(end: false, tick: Int64(startTick))
    report.expect(PlaybackTimeline.build(state: document.state, sampleRate: 48_000).loopStartTick == startTick,
                  cppID: id, message: "A009: setting loop start moves its marker to the cell edge")
    let afterStart = document.history.currentIdentity
    document.setLoop(end: true, tick: Int64(endTick))
    let afterSets = coreTimeBytes(document)
    report.expect(PlaybackTimeline.build(state: document.state, sampleRate: 48_000).loopEndTick == endTick &&
                  document.history.currentIdentity != afterStart && afterSets != before,
                  cppID: id, message: "A015/A017: the end marker is one snap cell later and changes the song")

    // Production removal performs two commands: start first, end second.
    document.setLoop(end: false, tick: nil)
    document.setLoop(end: true, tick: nil)
    let afterRemoval = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(afterRemoval.loopStartTick == TimeDefaults.noTick &&
                  afterRemoval.loopEndTick == TimeDefaults.noTick,
                  cppID: id, message: "A022: removal clears both markers")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "removing the end marker is undoable")
    let firstUndo = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(firstUndo.loopStartTick == TimeDefaults.noTick && firstUndo.loopEndTick == endTick,
                  cppID: id, message: "A024: first undo restores only the end marker")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "removing the start marker is separately undoable")
    let secondUndo = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(secondUndo.loopStartTick == startTick && secondUndo.loopEndTick == endTick &&
                  coreTimeBytes(document) == afterSets,
                  cppID: id, message: "A025/A026: second undo restores both markers and song bytes")

    let selectionStart = startTick - snapCell
    document.setLoop(end: false, tick: Int64(selectionStart))
    document.setLoop(end: true, tick: Int64(startTick))
    let selected = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(selected.loopStartTick == selectionStart && selected.loopEndTick == startTick,
                  cppID: id, message: "A030: the selection bounds become the loop markers")
    _ = document.history.undoDocument()
    let selectionUndo = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(selectionUndo.loopStartTick == selectionStart && selectionUndo.loopEndTick == endTick,
                  cppID: id, message: "A032: first selection undo restores only the old end")
    _ = document.history.undoDocument()
    report.expect(coreTimeBytes(document) == afterSets, cppID: id,
                  message: "A033: second selection undo restores the manual markers")
}

@MainActor
private func checkRulerSignatureRemoval(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuEnablementSelectionContext"
    let document = rulerMenuDocument(session)
    let snapCell: Tick = 6
    let chipTick = rulerSeedTick + snapCell
    document.setTimeSignature(tick: chipTick, numerator: 5, denominatorPower: 2)
    report.expect(PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
        .timeSignatures.contains { $0.tick == chipTick }, cppID: id,
                  message: "A037: the explicit 5/4 signature exists at the snap cell")
    let before = coreTimeBytes(document)
    document.deleteTimeSignature(at: chipTick)
    report.expect(!PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
        .timeSignatures.contains { $0.tick == chipTick }, cppID: id,
                  message: "A050: removing the chip deletes the exact event")
    _ = document.history.undoDocument()
    report.expect(coreTimeBytes(document) == before, cppID: id,
                  message: "one undo restores the explicit signature")
}

@MainActor
private func checkRulerInsertTime(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuInsertTimeAndStaleNoOp"
    let document = rulerMenuDocument(session)
    let snapCell: Tick = 6
    let insertStart = rulerSeedTick + snapCell
    let insertEnd = insertStart + snapCell
    guard let note = document.notes(in: 0).first else {
        report.fail(id, "resize fixture note is absent")
        return
    }
    document.nudgeNotes([note.id], byTicks: Int64(snapCell), byKeys: 0)
    guard document.notes(in: 0).contains(where: { $0.tick == insertStart && $0.pitch == note.pitch }) else {
        report.fail(id, "the moved fixture note did not land at the selected seam")
        return
    }
    let before = coreTimeBytes(document)
    let identity = document.history.currentIdentity
    let range = TimeRange(startTick: insertStart, endTick: insertEnd)
    report.expect(document.insertBlankTime(range, scope: TimeScope(tracks: [0])),
                  cppID: id, message: "the selected span inserts blank time")
    report.expect(document.notes(in: 0).contains {
        $0.tick == insertEnd && $0.pitch == note.pitch && $0.velocity == note.velocity
    } && document.history.currentIdentity != identity && coreTimeBytes(document) != before,
    cppID: id, message: "A104/A108: the note shifts by exactly one span and the song bytes change")
    _ = document.history.undoDocument()
    report.expect(coreTimeBytes(document) == before, cppID: id,
                  message: "A109: one undo restores the song before ruler insertion")
}

@MainActor
private func checkRenderedRulerMenuCommands(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rulerMenuSwiftRowsAndTwoStepUndo"
    let palette = GridPalette()
    let grid = PianoGrid(session: session, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    let previousTrack = session.selectedTrack
    if previousTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = previousTrack }
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor }

    let start: Tick = session.timeline.loopStartTick == 72 ? 48 : 72
    let end: Tick = session.timeline.loopEndTick == 96 ? 120 : 96
    let atStart = session.camera.contentX(tick: Double(start))
    let atEnd = session.camera.contentX(tick: Double(end))
    menu.openRuler(contentX: atStart)
    report.expect(menu.isOpen && menu.rows.count > 0
                  && (0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 2 && menu.rows[$0].enabled }),
                  cppID: id, message: "the ruler opens a typed, enabled Set Loop Start row")
    _ = menu.activate(actionId: 2)
    let writtenStart = session.timeline.loopStartTick
    report.expect(!menu.isOpen && writtenStart == Tick(grid.snapTickDown(Double(start))),
                  cppID: id, message: "the clicked start row closes and writes the loop marker")

    menu.openRuler(contentX: atEnd)
    _ = menu.activate(actionId: 3)
    let writtenEnd = session.timeline.loopEndTick
    report.expect(writtenEnd == Tick(grid.snapTickDown(Double(end))), cppID: id,
                  message: "the clicked end row writes a second undoable marker")

    menu.openRuler(contentX: atEnd)
    report.expect((0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 4 && menu.rows[$0].enabled }),
                  cppID: id, message: "Remove Loop becomes enabled when a marker exists")
    _ = menu.activate(actionId: 4)
    report.expect(session.timeline.loopStartTick == TimeDefaults.noTick
                  && session.timeline.loopEndTick == TimeDefaults.noTick, cppID: id,
                  message: "Remove Loop clears both marker events")
    _ = session.document.history.undoDocument()
    report.expect(session.timeline.loopStartTick == TimeDefaults.noTick
                  && session.timeline.loopEndTick == writtenEnd, cppID: id,
                  message: "the first undo restores only the end marker")
    _ = session.document.history.undoDocument()
    report.expect(session.timeline.loopStartTick == writtenStart
                  && session.timeline.loopEndTick == writtenEnd, cppID: id,
                  message: "the second undo restores both markers")
    _ = session.document.history.undoDocument()
    _ = session.document.history.undoDocument()

    menu.beginSweep(contentX: atStart)
    menu.updateSweep(contentX: atEnd)
    menu.endSweep(contentX: atEnd)
    menu.openRuler(contentX: session.camera.contentX(tick: Double((start + end) / 2)))
    report.expect((0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 5 && menu.rows[$0].enabled })
                  && !(0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 2 }), cppID: id,
                  message: "a swept range replaces positional rows with selection rows")
    automation.clearTimeSelection()
    let identity = session.document.history.currentIdentity
    _ = menu.activate(actionId: 5)
    report.expect(identity == session.document.history.currentIdentity && !menu.isOpen,
                  cppID: id, message: "a stale selection click dismisses without a document write")
}

@MainActor
private func checkRulerInsertTimePrompt(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rulerInsertTimePromptWholeSong"
    let palette = GridPalette()
    let grid = PianoGrid(session: session, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor }
    guard let note = session.document.notes(in: 0).first else {
        report.fail(id, "the ruler check fixture needs a note on track zero")
        return
    }
    let before = coreTimeBytes(session.document)
    let priorIdentity = session.document.history.currentIdentity
    let axis = TimeAxis(map: TimeMap(
        ticksPerBeat: UInt32(max(1, session.document.ticksPerBeat)),
        timeSigs: session.document.timeSignatures.map {
            TimeSigPoint(tick: $0.tick, numerator: $0.numerator,
                         denomPow2: $0.denominatorPower)
        }))
    let segment = axis.segmentAt(0)
    let barTicks = Tick(segment.beatTicks) * Tick(segment.beatsPerBar)
    session.editCursor = 0
    menu.openRuler(contentX: session.camera.contentX(tick: 0))
    _ = menu.activate(actionId: 1)
    report.expect(menu.insertTimePromptOpen && !menu.isOpen
                  && menu.insertTimePromptMaximumBeats == Int(segment.beatsPerBar - 1)
                  && session.document.history.currentIdentity == priorIdentity,
                  cppID: id, message: "A042: choosing Insert Time opens the bar/beat form without inserting")
    menu.acceptInsertTimePrompt(bars: 1, beats: 0, fractions: 0)
    report.expect(!menu.insertTimePromptOpen
                  && session.document.notes(in: 0).contains {
                      $0.pitch == note.pitch && $0.velocity == note.velocity
                          && $0.tick == note.tick + barTicks
                  }
                  && session.document.history.currentIdentity != priorIdentity,
                  cppID: id, message: "the accepted bar shifts whole-song events by the local signature length")
    _ = session.document.history.undoDocument()
    report.expect(coreTimeBytes(session.document) == before, cppID: id,
                  message: "one undo restores the song before prompted insertion")
    menu.openRuler(contentX: session.camera.contentX(tick: 0))
    _ = menu.activate(actionId: 1)
    menu.cancelInsertTimePrompt()
    report.expect(!menu.insertTimePromptOpen && coreTimeBytes(session.document) == before,
                  cppID: id, message: "cancelling the prompt never writes time")
}

@MainActor
private struct RulerCheckFixture {
    let session: DocumentSession
    let grid: PianoGrid
    let automation: AutomationPage
    let menu: RulerMenuPresenter
    let primary: Int
    let cell: Int
    let anchor: Tick
    let farTick: Tick
    let atAnchor: Double
    let atFar: Double
}

@MainActor
private func checkRulerSweepScopeTapAndChip(_ report: CheckReport, session: DocumentSession) {
    let palette = GridPalette()
    let grid = PianoGrid(session: session, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    let previousTrack = session.selectedTrack
    if previousTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = previousTrack }
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor }
    defer { automation.clearTimeSelection(); menu.close(); menu.cancelSweep() }
    automation.clearTimeSelection()
    menu.close()

    let cell = max(1, grid.snapTicks)
    let anchor = Tick(grid.snapTickDown(Double(72)))
    var farTick = anchor + Tick(cell * 4)
    var alignSteps = 0
    while Tick(grid.snapTickDown(Double(farTick))) != farTick && alignSteps < 1024 {
        farTick = farTick + 1
        alignSteps += 1
    }
    let fixture = RulerCheckFixture(
        session: session, grid: grid, automation: automation, menu: menu,
        primary: session.selectedTrack ?? 0, cell: cell, anchor: anchor, farTick: farTick,
        atAnchor: session.camera.contentX(tick: Double(anchor)),
        atFar: session.camera.contentX(tick: Double(farTick)))
    guard let endTick = checkRulerSweepScope(report, fixture: fixture) else { return }
    guard checkRulerTapAndCancel(report, fixture: fixture, endTick: endTick) else { return }
    checkRulerPressPolicy(report, fixture: fixture, endTick: endTick)
    checkRulerChip(report, fixture: fixture, endTick: endTick)
}

@MainActor
private func checkRulerSweepScope(_ report: CheckReport, fixture: RulerCheckFixture) -> Tick? {
    let id = "swiftcore/PianoRoll::timelineRulerScope"
    let session = fixture.session
    let menu = fixture.menu
    let automation = fixture.automation
    menu.beginSweep(contentX: fixture.atAnchor)
    menu.updateSweep(contentX: fixture.atFar)
    guard let swept = automation.selection, swept.isActive else {
        report.fail(id, "a plain ruler sweep published no time selection")
        return nil
    }
    report.expect(swept.range == TimeRange(startTick: fixture.anchor, endTick: fixture.farTick)
                  && swept.scope == .tracks([fixture.primary]),
                  cppID: id,
                  message: "A025: a plain ruler drag sweeps the exact range with primary-only scope")
    menu.endSweep(contentX: fixture.atFar)
    report.expect(automation.selection?.isActive == true
                  && automation.selection?.range == swept.range,
                  cppID: id,
                  message: "releasing a swept range retains the time selection")

    let docBytes = coreTimeBytes(session.document)
    guard session.document.canAddTrack, let other = session.document.addTrack(voice: 0),
          other != fixture.primary else {
        report.fail(id, "the fixture cannot provision a second engine track")
        return nil
    }
    guard let overlapIDs = try? session.document.addNotes([NewNote(
        track: other, tick: fixture.anchor, pitch: 60,
        duration: Tick(fixture.cell * 4), velocity: 90)]), !overlapIDs.isEmpty else {
        report.fail(id, "the fixture cannot seed the intersecting track note")
        return nil
    }
    automation.clearTimeSelection()
    menu.beginSweep(contentX: fixture.atAnchor, modifiers: 0x0400_0000)
    menu.updateSweep(contentX: fixture.atFar)
    guard let modified = automation.selection, modified.isActive else {
        report.fail(id, "a modified ruler sweep published no time selection")
        return nil
    }
    guard case let .tracks(scope) = modified.scope else {
        report.fail(id, "a modified ruler sweep published a non-track scope")
        return nil
    }
    report.expect(modified.range == TimeRange(startTick: fixture.anchor, endTick: fixture.farTick)
                  && scope.contains(fixture.primary) && scope.contains(other),
                  cppID: id,
                  message: "A026: a Control ruler drag sweeps the exact range with intersecting-track scope")
    menu.endSweep(contentX: fixture.atFar)
    report.expect(session.document.history.undoDocument(), cppID: id,
                  message: "the intersecting note insertion is undoable")
    report.expect(session.document.history.undoDocument()
                  && coreTimeBytes(session.document) == docBytes, cppID: id,
                  message: "undoing the note and track restores the fixture bytes")
    return modified.range.endTick
}

@MainActor
private func checkRulerTapAndCancel(
    _ report: CheckReport, fixture: RulerCheckFixture, endTick: Tick
) -> Bool {
    let id = "swiftcore/PianoRoll::timelineRulerScope"
    let session = fixture.session
    let menu = fixture.menu
    let automation = fixture.automation
    var outside = endTick + Tick(fixture.cell)
    var steps = 0
    while Tick(fixture.grid.snapTickDown(Double(outside))) != outside && steps < 1024 {
        outside = outside + 1
        steps += 1
    }
    automation.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: fixture.anchor, endTick: endTick),
        scope: .tracks([fixture.primary])))
    let priorTapChange = session.onChange
    var tapPublications: [SessionChangeDomains] = []
    session.onChange = { change in
        tapPublications.append(change.domains)
        priorTapChange?(change)
    }
    session.editCursor = fixture.anchor
    let atOutside = session.camera.contentX(tick: Double(outside))
    menu.beginSweep(contentX: atOutside)
    menu.endSweep(contentX: atOutside)
    session.onChange = priorTapChange
    report.expect(automation.selection == AutomationTimeSelection(
                      range: TimeRange(startTick: fixture.anchor, endTick: endTick),
                      scope: .tracks([fixture.primary]))
                  && session.editCursor == outside,
                  cppID: id,
                  message: "A035: tapping the ruler outside the selection commits the cursor without clearing it")
    report.expect(tapPublications.contains(where: { $0.contains(.cursor) }), cppID: id,
                  message: "A035: the tap commit publishes the cursor through the session observer")

    menu.beginSweep(contentX: fixture.atAnchor)
    menu.updateSweep(contentX: fixture.atFar)
    guard let live = automation.selection, live.isActive else {
        report.fail(id, "the cancellation fixture published no time selection")
        return false
    }
    let cursorBeforeCancel = session.editCursor
    menu.cancelSweep()
    report.expect(automation.selection == live && session.editCursor == cursorBeforeCancel,
                  cppID: id,
                  message: "cancelling a sweep keeps the selection and cursor without committing")
    menu.updateSweep(contentX: fixture.atAnchor)
    report.expect(automation.selection == live,
                  cppID: id,
                  message: "a cancelled sweep ignores further movement")
    return true
}

@MainActor
private func checkRulerPressPolicy(
    _ report: CheckReport, fixture: RulerCheckFixture, endTick: Tick
) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuInsertTimeAndStaleNoOp"
    let session = fixture.session
    let menu = fixture.menu
    let automation = fixture.automation
    automation.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: fixture.anchor, endTick: endTick),
        scope: .tracks([fixture.primary])))
    session.editCursor = fixture.anchor
    menu.openRuler(contentX: session.camera.contentX(tick: Double(endTick - 1)))
    report.expect(menu.isOpen && menu.menuKind == 1
                  && automation.selection?.range.startTick == fixture.anchor
                  && automation.selection?.range.endTick == endTick
                  && session.editCursor == fixture.anchor
                  && (0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 5 }),
                  cppID: id,
                  message: "A098/A099: a press inside the interval keeps the selection and cursor")
    menu.close()

    automation.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: fixture.anchor, endTick: endTick),
        scope: .tracks([fixture.primary])))
    let priorEndChange = session.onChange
    var endPublications: [SessionChangeDomains] = []
    session.onChange = { change in
        endPublications.append(change.domains)
        priorEndChange?(change)
    }
    menu.openRuler(contentX: session.camera.contentX(tick: Double(endTick) + 0.5))
    session.onChange = priorEndChange
    report.expect(menu.isOpen && menu.menuKind == 1
                  && automation.selection?.isActive != true
                  && session.editCursor == endTick
                  && !(0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 5 })
                  && (0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 2 }),
                  cppID: id,
                  message: "A110-A113: the exact-end press clears, commits the end tick, opens cursor rows")
    report.expect(endPublications.contains(where: { $0.contains(.cursor) }), cppID: id,
                  message: "A112: the outside press publishes the committed cursor through the session observer")
    menu.close()
}

@MainActor
private func checkRulerChip(
    _ report: CheckReport, fixture: RulerCheckFixture, endTick: Tick
) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuEnablementSelectionContext"
    let session = fixture.session
    let menu = fixture.menu
    let chipOff = endTick + 1
    let preSigBytes = coreTimeBytes(session.document)
    session.document.setTimeSignature(tick: chipOff, numerator: 7, denominatorPower: 2)
    fixture.automation.clearTimeSelection()
    menu.openRuler(contentX: session.camera.contentX(tick: Double(chipOff)),
                   chipTick: Double(chipOff))
    report.expect(session.editCursor == chipOff && menu.isOpen && menu.menuKind == 1,
                  cppID: id,
                  message: "A039/A059: a chip press commits the chip's exact event tick")
    menu.close()
    report.expect(session.document.history.undoDocument()
                  && coreTimeBytes(session.document) == preSigBytes, cppID: id,
                  message: "one undo restores the bytes before the chip signature")
}

@MainActor
private func checkRulerSeekEmission(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rulerSeekEmission"
    let palette = GridPalette()
    let grid = PianoGrid(session: session, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    let previousTrack = session.selectedTrack
    if previousTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = previousTrack }
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor }
    defer { automation.clearTimeSelection(); menu.close(); menu.cancelSweep(); menu.onSeek = nil }
    let primary = session.selectedTrack ?? 0
    automation.clearTimeSelection()
    menu.close()
    var emitted: [Tick] = []
    menu.onSeek = { emitted.append($0) }
    let cell = max(1, grid.snapTicks)
    let anchor = Tick(grid.snapTickDown(Double(72)))
    let farTick = anchor + Tick(cell * 4)
    let atAnchor = session.camera.contentX(tick: Double(anchor))
    let atFar = session.camera.contentX(tick: Double(farTick))
    var outside = farTick + Tick(cell)
    var steps = 0
    while Tick(grid.snapTickDown(Double(outside))) != outside && steps < 1024 {
        outside = outside + 1
        steps += 1
    }
    session.editCursor = anchor
    menu.beginSweep(contentX: session.camera.contentX(tick: Double(outside)))
    menu.endSweep(contentX: session.camera.contentX(tick: Double(outside)))
    report.expect(emitted == [outside], cppID: id,
                  message: "a ruler tap emits one seek for the exact snapped anchor")
    let start = anchor
    let end = outside
    automation.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: start, endTick: end), scope: .tracks([primary])))
    menu.openRuler(contentX: session.camera.contentX(tick: Double(end) + 0.5))
    report.expect(emitted == [outside, end]
                  && session.editCursor == end, cppID: id,
                  message: "an outside press emits one seek for the exact snapped end tick")
    let chipOff = end + 1
    automation.clearTimeSelection()
    menu.openRuler(contentX: session.camera.contentX(tick: Double(chipOff)),
                   chipTick: Double(chipOff))
    report.expect(emitted == [outside, end, chipOff], cppID: id,
                  message: "a chip press emits one seek for the exact chip tick")
    menu.close()
    automation.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: start, endTick: end), scope: .tracks([primary])))
    menu.openRuler(contentX: session.camera.contentX(tick: Double(end - 1)))
    menu.beginSweep(contentX: atAnchor)
    menu.updateSweep(contentX: atFar)
    menu.endSweep(contentX: atFar)
    menu.cancelSweep()
    automation.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: start, endTick: end), scope: .tracks([primary])))
    menu.openTimeSelection(contentX: session.camera.contentX(tick: Double((start + end) / 2)))
    automation.clearTimeSelection()
    _ = menu.activate(actionId: 6)
    report.expect(emitted == [outside, end, chipOff], cppID: id,
                  message: "inside presses, sweeps, cancels and menu commands emit no seek")
    menu.close()
    let sample = session.timeline.sample(for: end)
    report.expect(abs(session.timeline.tick(for: sample) - Double(end)) < 0.001, cppID: id,
                  message: "the timeline inverts the sought sample back to the exact tick")
    let playhead = SharedPlayheadPresenter()
    let priorCamera = session.onCameraChange
    let priorPlayback = session.onPlayback
    let priorSessionChange = session.onChange
    defer {
        session.onCameraChange = priorCamera
        session.onPlayback = priorPlayback
        session.onChange = priorSessionChange
        playhead.detach()
    }
    playhead.attach(session: session, audio: nil, grid: nil, drawer: nil)
    playhead.setFollowEnabled(false)
    _ = playhead.observe(sample: sample, transport: 0)
    report.expect(playhead.tick == Double(end), cppID: id,
                  message: "the shared playhead presents the sought tick from its sample")
}
