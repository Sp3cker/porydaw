import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore
@testable import PorydawDocument
import QtBridge

@MainActor
private func establishVelocityLatch(
    _ report: CheckReport, id: String,
    session: DocumentSession, grid: PianoGrid,
    seed: (ids: [NoteID], rects: [SceneRect])
) {
    let control = 0x0400_0000
    let x = seed.rects[1].x + seed.rects[1].width / 2
    let y = seed.rects[1].y + seed.rects[1].height / 2
    session.setSelectedNotes([seed.ids[1]])
    grid.beginPointer(x: x, y: y, modifiers: control)
    grid.updatePointer(x: x, y: y + 27)
    grid.endPointer(x: x, y: y + 27)
    report.expect(
        session.selectedNoteOrder == [seed.ids[1]], cppID: id,
        message: "velocity drag on a single selected note leaves only its anchor selected")
    report.expect(
        session.document.note(seed.ids[1])?.velocity == 73, cppID: id,
        message: "the modifier drag first lowers note B to velocity 73")
    grid.beginPointer(x: x, y: y, modifiers: control)
    grid.updatePointer(x: x, y: y - 20)
    grid.endPointer(x: x, y: y - 20)
    report.expect(
        session.document.note(seed.ids[1])?.velocity == 93
            && grid.lastVelocity == 93, cppID: id,
        message: "the modifier velocity drag raises note B from 73 to 93 and latches the pencil")
    let beforeToggle = session.document.history.undoCount
    grid.beginPointer(x: x, y: y, modifiers: control)
    grid.endPointer(x: x, y: y)
    report.expect(
        session.selectedNoteOrder.isEmpty, cppID: id,
        message: "Ctrl click after the velocity drag toggles its sole selection off")
    grid.beginPointer(x: x, y: y, modifiers: control)
    grid.updatePointer(x: x, y: y + grid.dragDistance - 1)
    grid.endPointer(x: x, y: y + grid.dragDistance - 1)
    report.expect(
        session.selectedNoteOrder == [seed.ids[1]]
            && session.document.note(seed.ids[1])?.velocity == 93
            && session.document.history.undoCount == beforeToggle,
        cppID: id, message: "subthreshold Ctrl jitter toggles the note on without editing velocity")
}

@MainActor
func checkGroupedVelocityDrag(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::selectionModifierVelocity"
    let initialSelection = session.selectedNoteOrder
    let grid = makeCameraGrid(viewport: viewport)
    guard let baseline = try? session.document.captureSave() else {
        report.fail(id, "could not capture the pre-drag MIDI bytes")
        return
    }
    defer {
        selectionRestore(
            report, id: id, session: session, baseline: baseline,
            selection: initialSelection,
            message: "velocity drags unwind to the pre-seed MIDI bytes and history")
    }
    guard let seed = velocityPairSeed(session: session, grid: grid) else {
        report.fail(id, "could not seed the velocity-drag note pair")
        return
    }
    establishVelocityLatch(report, id: id, session: session, grid: grid, seed: seed)
    guard let plantedBytes = try? session.document.captureSave().bytes else {
        report.fail(id, "could not capture the planted MIDI bytes")
        return
    }
    let plantedIdentity = session.document.history.currentIdentity
    let control = 0x0400_0000
    let aX = seed.rects[0].x + seed.rects[0].width / 2
    guard let originalA = session.document.note(seed.ids[0]),
        let originalB = session.document.note(seed.ids[1])
    else {
        report.fail(id, "velocity-drag seed notes disappeared")
        return
    }
    let aY = seed.rects[0].y + seed.rects[0].height / 2
    session.setSelectedNotes(seed.ids)
    var noteAuditions: [(pitch: Int, velocity: Int)] = []
    grid.onAudition = { _, pitch, velocity in
        noteAuditions.append((pitch, velocity))
    }
    let platformSlop = grid.dragDistance
    grid.dragDistance = 15 + grid.drawThreshold
    grid.beginPointer(x: aX, y: aY, modifiers: control)
    report.expect(
        Set(session.selectedNoteOrder) == Set(seed.ids), cppID: id,
        message: "Ctrl press on a grouped anchor preserves the selection")
    report.expect(
        session.document.note(seed.ids[0]).map { grid.hoverKey == Int($0.pitch) } == true,
        cppID: id, message: "the modifier press pins the hover mark to the anchor row")
    report.expect(
        noteAuditions.first.map {
            $0.pitch == (session.document.note(seed.ids[0]).map { Int($0.pitch) } ?? -1)
                && $0.velocity == 93
        } == true
            && grid.lastVelocity == 93, cppID: id,
        message: "Ctrl note press auditions its own velocity and latches the drawing velocity")
    let preCount = session.document.history.undoCount
    grid.updatePointer(x: aX, y: aY + 15)
    report.expect(
        grid.previewVelocity(seed.ids[0]) == nil, cppID: id,
        message: "Ctrl jitter below the published platform slop remains a selection click")
    grid.updatePointer(x: aX, y: aY + grid.dragDistance)
    report.expect(
        grid.previewVelocity(seed.ids[0]) != nil, cppID: id,
        message: "Ctrl vertical travel at the published platform slop starts velocity")
    grid.updatePointer(x: aX, y: aY + 15)
    report.expect(
        grid.previewVelocity(seed.ids[0]) == 78, cppID: id,
        message: "the drag previews 78 before release")
    report.expect(
        grid.statusText.contains("Changing velocity"), cppID: id,
        message: "the velocity drag publishes its preview status")
    report.expect(
        session.document.note(seed.ids[0]).map { Int($0.velocity) } == 93, cppID: id,
        message: "the velocity preview commits nothing before release")
    grid.endPointer(x: aX, y: aY + 15)
    grid.dragDistance = platformSlop
    report.expect(
        session.document.note(seed.ids[0]).map { Int($0.velocity) } == 78, cppID: id,
        message: "a 15px modifier drag lands the anchor at 78 from 93")
    report.expect(
        noteAuditions.last.map { $0.velocity == 0 } == true
            && grid.lastVelocity == 78, cppID: id,
        message: "velocity release stops the note audition and latches the committed anchor velocity")
    report.expect(
        session.document.note(seed.ids[1]).map { Int($0.velocity) } == 78, cppID: id,
        message: "the grouped drag applies the same delta to the other selected note")
    report.expect(
        Set(session.selectedNoteOrder) == Set(seed.ids), cppID: id,
        message: "a grouped velocity drag preserves the selected notes")
    report.expect(
        session.document.history.undoCount == preCount + 1, cppID: id,
        message: "one grouped velocity drag commits one undo entry")
    report.expect(
        session.document.history.undoDocument()
            && session.document.history.currentIdentity == plantedIdentity
            && (try? session.document.captureSave().bytes) == plantedBytes, cppID: id,
        message: "undo restores both fixture velocities at once")
    session.setSelectedNotes(seed.ids)
    let repeatIndex = session.document.history.undoIndex
    grid.beginPointer(x: aX, y: aY, modifiers: control)
    grid.updatePointer(x: aX, y: aY + 15)
    grid.endPointer(x: aX, y: aY + 15)
    report.expect(
        session.document.note(seed.ids[0]).map { Int($0.velocity) } == 78
            && session.document.note(seed.ids[1]).map { Int($0.velocity) } == 78, cppID: id,
        message: "dragging down again reaches the same grouped velocities")
    report.expect(
        session.document.history.undoIndex == repeatIndex + 1, cppID: id,
        message: "repeated grouped velocity drag pushes exactly one undo command")
    let oppositeCount = session.document.history.undoCount
    grid.beginPointer(x: aX, y: aY, modifiers: control)
    grid.updatePointer(x: aX, y: aY - 15)
    grid.endPointer(x: aX, y: aY - 15)
    report.expect(
        session.document.history.undoCount == oppositeCount + 1, cppID: id,
        message: "repeated reverse drag adds one command to grouped velocity history")
    report.expect(
        session.document.note(seed.ids[0]) == originalA, cppID: id,
        message: "repeating the grouped velocity drag restores the anchor's complete note record")
    report.expect(
        session.document.note(seed.ids[1]) == originalB, cppID: id,
        message: "repeating the grouped velocity drag restores the other note's complete record")
    report.expect(
        session.document.note(seed.ids[0]).map { Int($0.velocity) } == 93
            && session.document.note(seed.ids[1]).map { Int($0.velocity) } == 93, cppID: id,
        message: "repeating the grouped drag the other way restores both velocities")
    report.expect(
        Set(session.selectedNoteOrder) == Set(seed.ids), cppID: id,
        message: "the repeated grouped drag preserves the selected notes")
    let chordCount = session.document.history.undoCount
    let priorNote = session.document.note(seed.ids[1])
    session.setSelectedNotes([seed.ids[1]])
    grid.beginPointer(x: aX, y: aY, modifiers: control)
    grid.updatePointer(x: aX, y: aY + 15)
    report.expect(
        session.selectedNoteOrder == [seed.ids[0]], cppID: id,
        message: "threshold velocity drag re-anchors to only the grabbed note")
    grid.endPointer(x: aX, y: aY + 15)
    report.expect(
        session.selectedNoteOrder == [seed.ids[0]], cppID: id,
        message: "a chord-held drag on another note re-anchors the selection to the grabbed note")
    report.expect(
        session.document.note(seed.ids[0]).map { Int($0.velocity) } == 78, cppID: id,
        message: "the chord-held drag adjusts the grabbed note")
    report.expect(
        session.document.note(seed.ids[1]) == priorNote, cppID: id,
        message: "the chord-held drag leaves the prior note untouched")
    report.expect(
        session.document.history.undoCount == chordCount + 1, cppID: id,
        message: "the chord-held drag commits one undo entry")
}

@MainActor
private func selectionFreeCell(
    session: DocumentSession, grid: PianoGrid, span: Int
) -> (tick: Int, pitch: Int, y: Double)? {
    let camera = grid.viewport.camera
    let snapshot = camera.snapshot
    for pitch in stride(from: 115, through: 24, by: -1) {
        let row = camera.projection.row(forPitch: pitch)
        guard
            let top = camera.projection.rowTop(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
            let bottom = camera.projection.rowBottom(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
            top >= 0, bottom <= snapshot.rollHeight
        else { continue }
        for probe in stride(from: 40, to: Int(snapshot.viewportWidth) - 80, by: 24) {
            let tick = grid.snapTickDown(camera.tickAtContentX(Double(probe)))
            let occupied = session.document.notes(in: grid.trackIndex).contains {
                Int($0.pitch) == pitch && Int($0.tick) < tick + span
                    && Int($0.tick) + Int($0.duration) > tick
            }
            if !occupied {
                return (tick, pitch, (top + bottom) / 2)
            }
        }
    }
    return nil
}

@MainActor
func checkThresholdDrawCell(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::selectionMinimumDrawDistance"
    let initialSelection = session.selectedNoteOrder
    let oldCamera = viewport.camera
    let grid = makeCameraGrid(viewport: viewport)
    _ = viewport.mutateCamera { _ = $0.setTimeZoom(140) }
    let oldGridSelection = viewport.grid.selection
    grid.openGridMenu(kind: 1)
    grid.activateGridMenuRow(actionId: 8)
    defer {
        grid.openGridMenu(kind: 1)
        grid.activateGridMenuRow(actionId: oldGridSelection.toMenuId())
        viewport.mutateCamera { $0 = oldCamera }
    }
    grid.refreshCamera()
    guard let baseline = try? session.document.captureSave() else {
        report.fail(id, "could not capture the pre-draw MIDI bytes")
        return
    }
    defer {
        selectionRestore(
            report, id: id, session: session, baseline: baseline,
            selection: initialSelection,
            message: "threshold draws unwind to the pre-seed MIDI bytes and history")
    }
    guard let seed = velocityPairSeed(session: session, grid: grid) else {
        report.fail(id, "could not seed the velocity-latch note pair")
        return
    }
    establishVelocityLatch(report, id: id, session: session, grid: grid, seed: seed)
    let plantedIdentity = session.document.history.currentIdentity
    guard let plantedBytes = try? session.document.captureSave().bytes else {
        report.fail(id, "could not capture the pre-draw planted MIDI bytes")
        return
    }
    let snap = grid.snapTicks
    guard snap >= 8 else {
        report.fail(id, "the fixed eighth grid is not drawable (snap=\(snap))")
        return
    }
    guard let cell = selectionFreeCell(session: session, grid: grid, span: snap) else {
        report.fail(id, "no free grid cell for the threshold draw")
        return
    }
    let pressX =
        viewport.camera.viewX(
            tick: Double(cell.tick),
            dpr: grid.devicePixelRatio) + 2
    let dragX = pressX + 8
    guard pressX >= 4,
        dragX <= viewport.camera.snapshot.viewportWidth - 4,
        viewport.camera.tickAtContentX(dragX) < Double(cell.tick + snap)
    else {
        report.fail(id, "the threshold drag escapes its snap cell at this zoom")
        return
    }
    var auditions: [(pitch: Int, velocity: Int)] = []
    grid.onAudition = { _, pitch, velocity in
        auditions.append((pitch, velocity))
    }
    let beforeClick = session.document.history.undoCount
    let beforeNotes = session.document.notes(in: grid.trackIndex)
    if let selected = beforeNotes.first?.id {
        session.setSelectedNotes([selected])
    }
    grid.beginPointer(x: pressX, y: cell.y, modifiers: 0x0400_0000)
    report.expect(
        session.selectedNoteOrder.isEmpty
            && auditions.first.map { $0.pitch == cell.pitch && $0.velocity == grid.lastVelocity } == true,
        cppID: id, message: "empty Ctrl press clears note selection and auditions its row")
    let otherY = cell.y + grid.rowHeight
    grid.updatePointer(x: pressX, y: otherY)
    grid.updatePointer(x: pressX + grid.drawThreshold - 0.5, y: cell.y)
    report.expect(
        auditions.count == 5 && auditions[1].velocity == 0
            && auditions[2].pitch != cell.pitch && auditions[2].velocity > 0
            && auditions[3].velocity == 0 && auditions[4].pitch == cell.pitch,
        cppID: id, message: "pending-draw row changes glissando before horizontal draw slop")
    grid.endPointer(x: pressX + grid.drawThreshold - 0.5, y: cell.y)
    report.expect(
        session.document.notes(in: grid.trackIndex).map(\.id) == beforeNotes.map(\.id)
            && session.document.history.undoCount == beforeClick
            && session.document.history.currentIdentity == plantedIdentity,
        cppID: id, message: "below the font-derived draw slop a click adds no note or undo entry")
    report.expect(
        session.editCursor
            == Tick(
                viewport.grid.snapTick(
                    viewport.camera.tickAtContentX(pressX), camera: viewport.camera))
            && auditions.last.map { $0.pitch == cell.pitch && $0.velocity == 0 } == true,
        cppID: id, message: "within-slop release parks the nearest snapped edit cursor and stops audition")
    session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: Tick(cell.tick), endTick: Tick(cell.tick + snap)),
            scope: .tracks([grid.trackIndex])))
    grid.beginPointer(x: pressX, y: cell.y, modifiers: 0)
    grid.endPointer(x: pressX, y: cell.y)
    report.expect(
        session.timeSelection == nil,
        cppID: "swiftcore/PianoRollTest::keyboardTimeSelectionShortcuts",
        message: "A056 clicking inside the primary time selection clears its active span")
    auditions.removeAll()
    grid.beginPointer(x: pressX, y: cell.y, modifiers: 0)
    grid.updatePointer(x: dragX, y: cell.y)
    report.expect(
        auditions.count == 1 && auditions[0].velocity == grid.lastVelocity,
        cppID: id, message: "crossing draw slop does not re-attack the sounding press key")
    report.expect(
        grid.statusText.contains("Drawing"), cppID: id,
        message: "crossing the draw threshold enters the draw gesture")
    let pendingFace = RollContentProbe(grid).drawPreview
    guard pendingFace.active else {
        report.fail(id, "pending draw has no rendered preview face")
        grid.endPointer(x: dragX, y: cell.y)
        return
    }
    grid.setNoteNameMode(enabled: true)
    let namedFace = RollContentProbe(grid).drawPreview
    report.expect(
        namedFace.active && namedFace.tick == pendingFace.tick
            && namedFace.duration == pendingFace.duration
            && namedFace.pitch == pendingFace.pitch,
        cppID: id,
        message: "toggling note-name mode while drawing leaves the pending note face unchanged")
    grid.endPointer(x: dragX, y: cell.y)
    let drawn = session.document.notes(in: grid.trackIndex).filter {
        Int($0.tick) == cell.tick && Int($0.pitch) == cell.pitch
    }
    report.expect(
        drawn.count == 1 && drawn.first.map { Int($0.duration) == snap } == true,
        cppID: id, message: "a threshold drag draws one snap cell")
    report.expect(
        session.document.history.undoDocument()
            && (try? session.document.captureSave().bytes) == plantedBytes,
        cppID: id, message: "undoing the press-grown draw restores exact MIDI bytes")
    grid.refreshFromSession()
    grid.setNoteNameMode(enabled: false)
    let nextDrawIndex = session.document.history.undoIndex
    grid.beginPointer(x: pressX, y: cell.y, modifiers: 0)
    grid.updatePointer(x: dragX, y: cell.y)
    grid.setNoteNameMode(enabled: true)
    grid.endPointer(x: dragX, y: cell.y)
    report.expect(
        session.document.history.undoIndex == nextDrawIndex + 1
            && session.document.notes(in: grid.trackIndex).contains {
                Int($0.tick) == cell.tick && Int($0.pitch) == cell.pitch
            }, cppID: id, message: "note-name readout draw commits one note")
    report.expect(
        session.document.history.undoDocument()
            && (try? session.document.captureSave().bytes) == plantedBytes,
        cppID: id, message: "undoing the note-name readout draw restores exact MIDI bytes")
    grid.setNoteNameMode(enabled: false)
}

@MainActor
func checkOrderedSelection(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let id = "swiftcore/EditorGridCamera::orderedSelection"
    let setupGrid = makeCameraGrid(viewport: viewport)
    guard
        let pitch = viewport.camera.projection.pitch(
            atY: 160, keyHeight: viewport.camera.snapshot.keyHeight,
            scrollY: viewport.camera.snapshot.scrollY, dpr: setupGrid.devicePixelRatio),
        let added = try? session.document.addNotes([
            NewNote(
                track: setupGrid.trackIndex, tick: 24, pitch: UInt8(pitch),
                duration: 24, velocity: 40),
            NewNote(
                track: setupGrid.trackIndex, tick: 96, pitch: UInt8(pitch),
                duration: 24, velocity: 90),
            NewNote(
                track: setupGrid.trackIndex, tick: 168, pitch: UInt8(pitch),
                duration: 24, velocity: 65),
        ]), added.count == 3
    else {
        report.fail(id, "ordered-selection fixture could not create visible notes")
        return
    }
    defer { session.document.deleteNotes(added) }
    let grid = makeCameraGrid(viewport: viewport)
    let a = added[0], b = added[1], c = added[2]
    guard let aRect = selectionRect(a, grid: grid),
        let bRect = selectionRect(b, grid: grid)
    else {
        report.fail(id, "ordered-selection fixture notes are not projected")
        return
    }
    let revision = session.document.revision
    let history = session.document.history.currentIdentity
    let dirty = session.document.isDirty
    let priorChange = session.onChange
    var publications: [SessionChangeDomains] = []
    session.onChange = { publications.append($0.domains) }
    defer { session.onChange = priorChange }
    func click(_ rect: SceneRect, modifiers: Int) {
        let x = rect.x + rect.width / 2, y = rect.y + rect.height / 2
        grid.beginPointer(x: x, y: y, modifiers: modifiers)
        grid.endPointer(x: x, y: y)
    }
    session.clearSelectedNotes()
    click(bRect, modifiers: 0)
    click(aRect, modifiers: 0x0400_0000)
    report.expect(
        session.selectedNoteOrder == [b, a]
            && session.document.note(session.selectedNoteOrder[0])?.velocity == 90,
        cppID: id, message: "Ctrl-add of earlier A(v40) retains later B(v90) as first selection")
    click(bRect, modifiers: 0x0400_0000)
    click(bRect, modifiers: 0x0400_0000)
    report.expectEqual(
        expected: [a, b], actual: session.selectedNoteOrder, cppID: id,
        what: "deselecting and re-adding appends the note")
    session.setSelectedNotes([b, a, b])
    report.expectEqual(
        expected: [b, a], actual: session.selectedNoteOrder, cppID: id,
        what: "replacement preserves first occurrence and removes duplicates")
    grid.beginRightPointer(x: 0, y: 0)
    grid.updateRightPointer(x: 640, y: 320)
    report.expect(
        session.selectedNoteOrder == [b, a], cppID: id,
        message: "band preview leaves the press-order selection uncommitted")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    report.expectEqual(
        expected: [b, a], actual: session.selectedNoteOrder, cppID: id,
        what: "band cancellation restores selection order")
    grid.beginRightPointer(x: 0, y: 0)
    grid.updateRightPointer(x: 640, y: 320)
    grid.endRightPointer(x: 640, y: 320, modifiers: 0x0400_0000)
    report.expect(
        Array(session.selectedNoteOrder.prefix(2)) == [b, a]
            && session.selectedNotes.contains(c),
        cppID: id, message: "band keeps press order before newly covered notes")
    publications.removeAll()
    session.setSelectedNotes([a, b])
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: publications, cppID: id,
        what: "order-only replacement publishes the selection domain")
    publications.removeAll()
    session.withStateChanges {
        session.setSelectedNotes([b, a])
        session.addSelectedNote(c)
    }
    report.expectEqual(
        expected: [SessionChangeDomains.selection], actual: publications, cppID: id,
        what: "order-only replacement and additive selection coalesce")
    publications.removeAll()
    session.setSelectedNotes([b, a, c, b])
    session.addSelectedNote(b)
    report.expect(
        publications.isEmpty, cppID: id,
        message: "unchanged normalized selection publishes nothing")
    report.expect(
        session.document.revision == revision
            && session.document.history.currentIdentity == history
            && session.document.isDirty == dirty,
        cppID: id, message: "selection gestures never mutate document or history")
    session.setSelectedNotes([c, b, a])
    session.document.deleteNotes([b])
    report.expect(
        session.selectedNoteOrder == [c, a] && session.selectedNotes == Set([c, a]),
        cppID: id, message: "deletion prunes membership and preserves survivor order")
}
