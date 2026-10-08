import Foundation
@testable import PorydawApp
@testable import PorydawAppPresentation
import PorydawCore
@testable import PorydawDocument
import PorydawAppCommands

@MainActor
func checkRulerLoopSetAndUndo(_ report: CheckReport, viewport: DocumentViewport) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuSetAndTwoStepUndo"
    let document = rulerMenuDocument(viewport.session)
    guard let note = document.notes(in: 0).first else {
        report.fail(id, "resize fixture note is absent")
        return
    }
    report.expect(
        document.notes(in: 0).contains {
            $0.tick == rulerSeedTick && $0.duration == 6 && $0.pitch == 60
                && $0.velocity == 100
        }, cppID: id, message: "the ruler fixture seeds its snap-aligned range")
    let snapCell: Tick = 6
    let startTick = note.tick + note.duration
    let endTick = startTick + snapCell
    let grid = PianoGrid(viewport: viewport)
    report.expect(
        Tick(grid.snapTickDown(Double(startTick))) == startTick
            && Tick(grid.snapTickDown(Double(endTick))) == endTick,
        cppID: id, message: "the loop start and end sit exactly on the snap lattice")
    // The legacy fixture begins with both loop markers removed.
    document.setLoop(end: false, tick: nil)
    document.setLoop(end: true, tick: nil)
    let before = coreTimeBytes(document)
    let initialIndex = document.history.undoIndex
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(
        timeline.loopStartTick == TimeDefaults.noTick && timeline.loopEndTick == TimeDefaults.noTick,
        cppID: id, message: "A004: both markers begin absent")

    document.setLoop(end: false, tick: Int64(startTick))
    report.expect(
        document.history.undoIndex == initialIndex + 1,
        cppID: id, message: "Set Loop Start writes exactly one undo entry")
    report.expect(
        PlaybackTimeline.build(state: document.state, sampleRate: 48_000).loopStartTick == startTick,
        cppID: id, message: "A009: setting loop start moves its marker to the cell edge")
    let afterStart = document.history.currentIdentity
    document.setLoop(end: true, tick: Int64(endTick))
    report.expect(
        document.history.undoIndex == initialIndex + 2,
        cppID: id, message: "Set Loop End advances the undo index by exactly one")
    let afterSets = coreTimeBytes(document)
    report.expect(
        PlaybackTimeline.build(state: document.state, sampleRate: 48_000).loopEndTick == endTick
            && document.history.currentIdentity != afterStart && afterSets != before,
        cppID: id, message: "A015/A017: the end marker is one snap cell later and changes the song")

    // Production removal performs two commands: start first, end second.
    document.setLoop(end: false, tick: nil)
    document.setLoop(end: true, tick: nil)
    report.expect(
        document.history.undoIndex == initialIndex + 4,
        cppID: id, message: "Remove Loop Markers advances the undo index by exactly two")
    let afterRemoval = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(
        afterRemoval.loopStartTick == TimeDefaults.noTick && afterRemoval.loopEndTick == TimeDefaults.noTick,
        cppID: id, message: "A022: removal clears both markers")
    report.expect(
        document.history.undoDocument(), cppID: id,
        message: "removing the end marker is undoable")
    let firstUndo = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(
        firstUndo.loopStartTick == TimeDefaults.noTick && firstUndo.loopEndTick == endTick,
        cppID: id, message: "A024: first undo restores only the end marker")
    report.expect(
        document.history.undoDocument(), cppID: id,
        message: "removing the start marker is separately undoable")
    let secondUndo = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(
        secondUndo.loopStartTick == startTick && secondUndo.loopEndTick == endTick
            && coreTimeBytes(document) == afterSets,
        cppID: id, message: "A025/A026: second undo restores both markers and song bytes")

    let selectionStart = startTick - snapCell
    let selectionIndex = document.history.undoIndex
    document.setLoop(end: false, tick: Int64(selectionStart))
    document.setLoop(end: true, tick: Int64(startTick))
    report.expect(
        document.history.undoIndex == selectionIndex + 2,
        cppID: id, message: "Loop from Selection advances the undo index by exactly two")
    let selected = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(
        selected.loopStartTick == selectionStart && selected.loopEndTick == startTick,
        cppID: id, message: "A030: the selection bounds become the loop markers")
    _ = document.history.undoDocument()
    let selectionUndo = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expect(
        selectionUndo.loopStartTick == selectionStart && selectionUndo.loopEndTick == endTick,
        cppID: id, message: "A032: first selection undo restores only the old end")
    _ = document.history.undoDocument()
    report.expect(
        coreTimeBytes(document) == afterSets, cppID: id,
        message: "A033: second selection undo restores the manual markers")
    _ = document.history.undoDocument()
    _ = document.history.undoDocument()
    report.expect(
        coreTimeBytes(document) == before, cppID: id,
        message: "the ruler loop round trip restores the exact song bytes")
}

@MainActor
func checkRulerSignatureRemoval(_ report: CheckReport, viewport: DocumentViewport) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuEnablementSelectionContext"
    let document = rulerMenuDocument(viewport.session)
    let snapCell: Tick = 6
    let chipTick = rulerSeedTick + snapCell
    let grid = PianoGrid(viewport: viewport)
    report.expect(
        Tick(grid.snapTickDown(Double(chipTick))) == chipTick,
        cppID: id, message: "the signature chip sits exactly on the snap lattice")
    document.setTimeSignature(tick: chipTick, numerator: 5, denominatorPower: 2)
    report.expect(
        PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
            .timeSignatures.contains { $0.tick == chipTick }, cppID: id,
        message: "A037: the explicit 5/4 signature exists at the snap cell")
    let before = coreTimeBytes(document)
    let undoIndex = document.history.undoIndex
    document.deleteTimeSignature(at: chipTick)
    report.expect(
        document.history.undoIndex == undoIndex + 1, cppID: id,
        message: "removing an explicit time signature writes exactly one undo entry")
    report.expect(
        !PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
            .timeSignatures.contains { $0.tick == chipTick }, cppID: id,
        message: "A050: removing the chip deletes the exact event")
    _ = document.history.undoDocument()
    report.expect(
        coreTimeBytes(document) == before, cppID: id,
        message: "one undo restores the explicit signature")
}

@MainActor
func checkRulerInsertTime(_ report: CheckReport, viewport: DocumentViewport) {
    let id = "swiftcore/PianoRoll::rulerLoopMenuInsertTimeAndStaleNoOp"
    let document = rulerMenuDocument(viewport.session)
    let snapCell: Tick = 6
    let insertStart = rulerSeedTick + snapCell
    let insertEnd = insertStart + snapCell
    let grid = PianoGrid(viewport: viewport)
    report.expect(
        Tick(grid.snapTickDown(Double(insertStart))) == insertStart
            && Tick(grid.snapTickDown(Double(insertEnd))) == insertEnd,
        cppID: id, message: "the ruler insert seams sit exactly on the snap lattice")
    guard let note = document.notes(in: 0).first else {
        report.fail(id, "resize fixture note is absent")
        return
    }
    document.nudgeNotes([note.id], byTicks: Int64(snapCell), byKeys: 0)
    report.expect(
        document.notes(in: 0).contains {
            $0.tick == insertStart && $0.pitch == note.pitch
        }, cppID: id, message: "the ruler insert fixture seeds its shifted note")
    guard document.notes(in: 0).contains(where: { $0.tick == insertStart && $0.pitch == note.pitch }) else {
        report.fail(id, "the moved fixture note did not land at the selected seam")
        return
    }
    let before = coreTimeBytes(document)
    let identity = document.history.currentIdentity
    let undoIndex = document.history.undoIndex
    let undoCount = document.history.undoCount
    let range = TimeRange(startTick: insertStart, endTick: insertEnd)
    report.expect(
        document.insertBlankTime(range, scope: TimeScope(tracks: [0])),
        cppID: id, message: "the selected span inserts blank time")
    report.expect(
        document.notes(in: 0).contains {
            $0.tick == insertEnd && $0.pitch == note.pitch && $0.velocity == note.velocity
        } && document.history.currentIdentity != identity && coreTimeBytes(document) != before,
        cppID: id, message: "A104/A108: the note shifts by exactly one span and the song bytes change")
    report.expect(
        document.history.undoIndex == undoIndex + 1
            && document.history.undoCount == undoCount + 1
            && document.notes(in: 0).contains {
                $0.tick == insertEnd && $0.pitch == note.pitch
            }, cppID: id, message: "ruler insertion shifts the note to the end in exactly one undo step")
    _ = document.history.undoDocument()
    report.expect(
        coreTimeBytes(document) == before, cppID: id,
        message: "A109: one undo restores the song before ruler insertion")
}

@MainActor
func checkRenderedRulerMenuCommands(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::rulerMenuSwiftRowsAndTwoStepUndo"
    let palette = GridPalette()
    let grid = PianoGrid(viewport: viewport, palette: palette)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(viewport: viewport, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(viewport: viewport, grid: grid, automation: automation)
    let previousTrack = session.selectedTrack
    if previousTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = previousTrack }
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor }

    let start: Tick = session.timeline.loopStartTick == 72 ? 48 : 72
    let end: Tick = session.timeline.loopEndTick == 96 ? 120 : 96
    let atStart = viewport.camera.contentX(tick: Double(start))
    let atEnd = viewport.camera.contentX(tick: Double(end))
    openRulerMenu(menu, at: atStart)
    report.expect(
        menu.isOpen && menu.rows.count > 0
            && (0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 2 && menu.rows[$0].enabled }),
        cppID: id, message: "the ruler opens a typed, enabled Set Loop Start row")
    _ = menu.activate(actionId: 2)
    let writtenStart = session.timeline.loopStartTick
    report.expect(
        !menu.isOpen && writtenStart == Tick(grid.snapTickDown(Double(start))),
        cppID: id, message: "the clicked start row closes and writes the loop marker")

    openRulerMenu(menu, at: atEnd)
    _ = menu.activate(actionId: 3)
    let writtenEnd = session.timeline.loopEndTick
    report.expect(
        writtenEnd == Tick(grid.snapTickDown(Double(end))), cppID: id,
        message: "the clicked end row writes a second undoable marker")
    grid.refreshFromSession()
    let loopProbe = RollContentProbe(grid)
    let noTick = Int(TimeDefaults.noTick)
    report.expect(
        loopProbe.loopStartTick == Int(writtenStart) && loopProbe.loopStartTick != noTick,
        cppID: id, message: "the roll content publishes the written loop start tick")
    report.expect(
        loopProbe.loopEndTick == Int(writtenEnd) && loopProbe.loopEndTick != noTick,
        cppID: id, message: "the roll content publishes the written loop end tick")
    report.expect(
        loopProbe.loopStartTick < loopProbe.loopEndTick, cppID: id,
        message: "the published loop start tick precedes the published loop end tick")
    let glowSlot = Int(RollPaletteSlot.loopGlow.rawValue)
    let edgeSlot = Int(RollPaletteSlot.loopEdge.rawValue)
    let ring = RollContentProbe.argb(palette.selectionRing)
    report.expect(
        loopProbe.palette.indices.contains(glowSlot) && loopProbe.palette[glowSlot] == ring,
        cppID: id, message: "the roll content publishes the selection ring ink as the loop glow color")
    report.expect(
        loopProbe.palette.indices.contains(edgeSlot) && loopProbe.palette[edgeSlot] == ring,
        cppID: id, message: "the roll content publishes the selection ring ink as the loop edge color")

    openRulerMenu(menu, at: atEnd)
    report.expect(
        (0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 4 && menu.rows[$0].enabled }),
        cppID: id, message: "Remove Loop becomes enabled when a marker exists")
    _ = menu.activate(actionId: 4)
    report.expect(
        session.timeline.loopStartTick == TimeDefaults.noTick
            && session.timeline.loopEndTick == TimeDefaults.noTick, cppID: id,
        message: "Remove Loop clears both marker events")
    grid.refreshFromSession()
    let removedProbe = RollContentProbe(grid)
    report.expect(
        removedProbe.loopStartTick == noTick && removedProbe.loopEndTick == noTick,
        cppID: id, message: "removing both loop markers publishes no loop tick in the roll content")
    _ = session.document.history.undoDocument()
    report.expect(
        session.timeline.loopStartTick == TimeDefaults.noTick
            && session.timeline.loopEndTick == writtenEnd, cppID: id,
        message: "the first undo restores only the end marker")
    grid.refreshFromSession()
    let openProbe = RollContentProbe(grid)
    report.expect(
        openProbe.loopEndTick == Int(writtenEnd) && openProbe.loopStartTick == noTick,
        cppID: id, message: "an open loop start publishes only the loop end tick")
    _ = session.document.history.undoDocument()
    report.expect(
        session.timeline.loopStartTick == writtenStart
            && session.timeline.loopEndTick == writtenEnd, cppID: id,
        message: "the second undo restores both markers")
    _ = session.document.history.undoDocument()
    _ = session.document.history.undoDocument()

    menu.beginSweep(contentX: atStart, pointerY: 0)
    menu.updateSweep(contentX: atEnd)
    menu.endSweep(contentX: atEnd)
    openRulerMenu(menu, at: viewport.camera.contentX(tick: Double((start + end) / 2)))
    report.expect(
        (0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 5 && menu.rows[$0].enabled })
            && !(0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 2 }), cppID: id,
        message: "a swept range replaces positional rows with selection rows")
    report.expect(
        (0..<menu.rows.count).contains(where: {
            menu.rows[$0].actionId == 8 && menu.rows[$0].enabled
        }), cppID: id, message: "a swept ruler menu resolves an enabled Clear row by action id")
    _ = menu.activate(actionId: 8)
    report.expect(
        !menu.isOpen && session.timeSelection == nil,
        cppID: id, message: "clicking the ruler Clear row closes the menu and drops the range")
    openRulerMenu(menu, at: viewport.camera.contentX(tick: Double((start + end) / 2)))
    report.expect(
        !(0..<menu.rows.count).contains(where: { menu.rows[$0].actionId == 8 }),
        cppID: id, message: "reopening the ruler menu after Clear loses its scoped rows")
    menu.close()
    menu.beginSweep(contentX: atStart, pointerY: 0)
    menu.updateSweep(contentX: atEnd)
    menu.endSweep(contentX: atEnd)
    openRulerMenu(menu, at: viewport.camera.contentX(tick: Double((start + end) / 2)))
    let staleBytes = coreTimeBytes(session.document)
    let staleIndex = session.document.history.undoIndex
    let staleCount = session.document.history.undoCount
    automation.clearTimeSelection()
    let identity = session.document.history.currentIdentity
    _ = menu.activate(actionId: 5)
    report.expect(
        identity == session.document.history.currentIdentity && !menu.isOpen,
        cppID: id, message: "a stale selection click dismisses without a document write")
    report.expect(
        coreTimeBytes(session.document) == staleBytes
            && session.document.history.undoIndex == staleIndex
            && session.document.history.undoCount == staleCount,
        cppID: id, message: "dismissing the ruler menu preserves the exact song bytes and history depth")
}

@MainActor
func checkRulerInsertTimePrompt(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::rulerInsertTimePromptWholeSong"
    let palette = GridPalette()
    let grid = PianoGrid(viewport: viewport, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(viewport: viewport, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(viewport: viewport, grid: grid, automation: automation)
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor }
    guard let note = session.document.notes(in: 0).first else {
        report.fail(id, "the ruler check fixture needs a note on track zero")
        return
    }
    let before = coreTimeBytes(session.document)
    let priorIdentity = session.document.history.currentIdentity
    let axis = TimeAxis(
        map: TimeMap(
            ticksPerBeat: UInt32(max(1, session.document.ticksPerBeat)),
            timeSigs: session.document.timeSignatures.map {
                TimeSigPoint(
                    tick: $0.tick, numerator: $0.numerator,
                    denomPow2: $0.denominatorPower)
            }))
    let segment = axis.segmentAt(0)
    let barTicks = Tick(segment.beatTicks) * Tick(segment.beatsPerBar)
    session.editCursor = 0
    openRulerMenu(menu, at: viewport.camera.contentX(tick: 0))
    _ = menu.activate(actionId: 1)
    report.expect(
        menu.insertTimePromptOpen && !menu.isOpen
            && menu.insertTimePromptMaximumBeats == Int(segment.beatsPerBar - 1)
            && session.document.history.currentIdentity == priorIdentity,
        cppID: id, message: "A042: choosing Insert Time opens the bar/beat form without inserting")
    menu.acceptInsertTimePrompt(bars: 1, beats: 0, fractions: 0)
    report.expect(
        !menu.insertTimePromptOpen
            && session.document.notes(in: 0).contains {
                $0.pitch == note.pitch && $0.velocity == note.velocity
                    && $0.tick == note.tick + barTicks
            }
            && session.document.history.currentIdentity != priorIdentity,
        cppID: id, message: "the accepted bar shifts whole-song events by the local signature length")
    _ = session.document.history.undoDocument()
    report.expect(
        coreTimeBytes(session.document) == before, cppID: id,
        message: "one undo restores the song before prompted insertion")
    openRulerMenu(menu, at: viewport.camera.contentX(tick: 0))
    _ = menu.activate(actionId: 1)
    menu.cancelInsertTimePrompt()
    report.expect(
        !menu.insertTimePromptOpen && coreTimeBytes(session.document) == before,
        cppID: id, message: "cancelling the prompt never writes time")
}

/// Ruler loop markers drag as one undo step, clamp past each other, and the grid glow fades per device pixel.
@MainActor
func checkRulerLoopMarkerDrag(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let document = session.document
    let id = "swiftcore/PianoRoll::rulerLoopMarkerDrag"
    let palette = GridPalette()
    let grid = PianoGrid(viewport: viewport, palette: palette)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(viewport: viewport, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(viewport: viewport, grid: grid, automation: automation)
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor }
    let cell = viewport.grid.snapTicksAt(0, camera: viewport.camera)
    let start = 4 * cell
    let end = 12 * cell
    func x(_ tick: Tick) -> Double { viewport.camera.contentX(tick: Double(tick)) }
    let row = grid.rulerMarkerRowHeight / 2
    document.setLoop(end: false, tick: Int64(start))
    document.setLoop(end: true, tick: Int64(end))
    let index = document.history.undoIndex
    let bytes = coreTimeBytes(document)
    session.editCursor = 0

    menu.updateRulerHover(contentX: x(start), pointerY: row)
    let onMarker = menu.loopMarkerHovered
    menu.updateRulerHover(contentX: x((start + end) / 2), pointerY: row)
    let betweenMarkers = menu.loopMarkerHovered
    menu.updateRulerHover(contentX: x(start), pointerY: grid.rulerMarkerRowHeight + 1)
    report.expect(
        cell > 0 && onMarker && !betweenMarkers && !menu.loopMarkerHovered,
        cppID: id, message: "only the marker row over a loop marker reports the resize hover")

    menu.beginRulerSweep(contentX: x(start), pointerY: row)
    menu.updateSweep(contentX: x(start + 2 * cell), pointerY: row)
    menu.updateSweep(contentX: x(start + 3 * cell), pointerY: row)
    let dragging = menu.loopMarkerHovered
    menu.endSweep(contentX: x(start + 3 * cell), pointerY: row)
    report.expect(
        dragging && session.timeline.loopStartTick == start + 3 * cell
            && session.timeline.loopEndTick == end && document.history.undoIndex == index + 1,
        cppID: id, message: "dragging the start marker moves it to the snapped pointer as one undo entry")
    report.expect(
        session.editCursor == 0 && session.timeSelection?.isActive != true,
        cppID: id, message: "a marker drag neither moves the edit cursor nor sweeps a time range")
    _ = document.history.undoDocument()
    report.expect(
        coreTimeBytes(document) == bytes, cppID: id,
        message: "one undo restores the dragged marker")

    menu.beginRulerSweep(contentX: x(end), pointerY: row)
    menu.updateSweep(contentX: x(start - cell), pointerY: row)
    menu.endSweep(contentX: x(start - cell), pointerY: row)
    report.expect(
        session.timeline.loopEndTick == start + cell && session.timeline.loopStartTick == start,
        cppID: id, message: "the end marker stops one snap cell after the start marker")
    _ = document.history.undoDocument()

    menu.beginRulerSweep(contentX: x(start), pointerY: row)
    menu.updateSweep(contentX: x(start + 2 * cell), pointerY: row)
    menu.updateSweep(contentX: x(start), pointerY: row)
    menu.endSweep(contentX: x(start), pointerY: row)
    menu.beginRulerSweep(contentX: x(start), pointerY: row)
    menu.updateSweep(contentX: x(start + 2 * cell), pointerY: row)
    menu.cancelSweep()
    report.expect(
        coreTimeBytes(document) == bytes && document.history.undoIndex == index
            && !menu.loopMarkerHovered,
        cppID: id, message: "returning or cancelling a marker drag leaves no edit or undo entry")

    menu.beginRulerSweep(contentX: x(start), pointerY: row)
    menu.endSweep(contentX: x(start), pointerY: row)
    report.expect(
        session.editCursor == start && coreTimeBytes(document) == bytes,
        cppID: id, message: "a click on a marker still places the edit cursor")

    grid.refreshFromSession()
    let glowInk = RollContentProbe.argb(palette.selectionRing) & 0x00FF_FFFF
    let glow = RollContentProbe(grid).plotRects
        .filter { $0.id == 0 && $0.argb & 0x00FF_FFFF == glowInk && $0.argb >> 24 < 0xFF }
        .sorted { $0.x < $1.x }
    let startGlow = glow.filter { $0.x < x((start + end) / 2) }
    func alpha(_ argb: UInt32) -> UInt32 { argb >> 24 }
    let continuous = zip(startGlow, startGlow.dropFirst()).allSatisfy {
        abs($0.x + $0.w - $1.x) < 1e-9 && $0.argbRight == $1.argb
    }
    let glowWidth = grid.metrics.spaceEight
    report.expect(
        startGlow.count == 2 && continuous
            && startGlow.allSatisfy { alpha($0.argb) > alpha($0.argbRight) }
            && alpha(startGlow[0].argb) == 150 && alpha(startGlow[0].argbRight) == 18
            && alpha(startGlow[1].argbRight) == 0
            && abs(startGlow[0].w - 0.2 * glowWidth) < 1e-9
            && abs(startGlow[1].x + startGlow[1].w - x(start) - glowWidth)
                <= 0.5 / grid.devicePixelRatio + 1e-9,
        cppID: id,
        message: "the loop glow is the C++ space(Eight) gradient: 150 to 18 over a fifth, then to 0")
    _ = document.history.undoDocument()
    _ = document.history.undoDocument()
}
