import Foundation
import PorydawApp
import PorydawCore

@MainActor
func runPitchBendChecks(_ report: CheckReport, session: DocumentSession) {
    let geometry = PitchBendGeometry(fontPx: 14, lineSpacing: 17, dpr: 2)
    let origin = [96: 0, 192: 0]
    var curve = PitchBendKernel(lane: .pitch, geometry: geometry,
                                startTick: 96, endTick: 192,
                                snapTicks: 12, fineTicks: 1,
                                points: origin, endValue: 0)
    let fromX = curve.x(at: 120)
    let toX = curve.x(at: 168)
    curve.begin(x: fromX, y: curve.y(at: 4096), line: true)
    curve.update(x: toX, y: curve.y(at: -4096), fine: true)
    report.expect(curve.hasGesture && curve.points[120] != nil
                  && curve.points[144] != nil && curve.points[168] != nil
                  && curve.points[144] != curve.points[120]
                  && curve.points[144] != curve.points[168]
                  && curve.points[96] == 0 && curve.points[192] == 0,
                  cppID: "swiftcore/PitchBendEditingTest::shiftDragDrawsLinearRamp",
                  message: "a Shift stroke previews an angled interior ramp without changing endpoints")
    curve.cancelGesture()
    report.expect(!curve.hasGesture && curve.points == origin,
                  cppID: "swiftcore/PitchBendEditingTest::freehandStrokePushesSingleUndoCommand",
                  message: "cancel discards the complete uncommitted stroke")

    curve.begin(x: fromX, y: curve.y(at: 4096), line: false)
    curve.update(x: toX, y: curve.y(at: -4096), fine: false)
    curve.finish()
    report.expect(curve.points[120] != nil && curve.points[132] != nil
                  && curve.points[144] != nil && curve.points[156] != nil
                  && curve.points[168] != nil,
                  cppID: "swiftcore/PitchBendEditingTest::freehandStrokePushesSingleUndoCommand",
                  message: "freehand stroke fills each crossed snap cell")
    let chosenTick = 144
    guard let chosenValue = curve.points[chosenTick] else {
        report.fail("swiftcore/PitchBendEditingTest::vertexHitTestAndSelection",
                    "the drawn curve lacks its middle vertex")
        return
    }
    let vertex = curve.hitTest(x: curve.x(at: chosenTick), y: curve.y(at: chosenValue))
    report.expect(vertex?.tick == chosenTick,
                  cppID: "swiftcore/PitchBendEditingTest::vertexHitTestAndSelection",
                  message: "the middle vertex is hit at its painted position")
    let beforeMove = curve.points
    curve.begin(x: curve.x(at: chosenTick), y: curve.y(at: chosenValue), line: false)
    curve.update(x: curve.x(at: 180), y: curve.y(at: 8191), fine: true)
    report.expect(curve.points[180] != nil && curve.points[chosenTick] == nil
                  && curve.points[192] == 0,
                  cppID: "swiftcore/PitchBendEditingTest::vertexAltDragMovesPoint",
                  message: "dragging an interior vertex moves it but preserves the note-off endpoint")
    curve.cancelGesture()
    report.expect(curve.points == beforeMove,
                  cppID: "swiftcore/PitchBendEditingTest::vertexAltDragMovesPoint",
                  message: "cancelling a vertex move restores the original curve")
    curve.select(chosenTick)
    report.expect(curve.removeSelectedVertex() && curve.points[chosenTick] == nil
                  && curve.points[192] == 0,
                  cppID: "swiftcore/PitchBendEditingTest::vertexDeletion",
                  message: "Delete removes only the selected interior vertex")

    var modulation = PitchBendKernel(lane: .modulation, geometry: geometry,
                                     startTick: 96, endTick: 192,
                                     snapTicks: 12, fineTicks: 1,
                                     points: origin, endValue: 0)
    modulation.begin(x: modulation.x(at: 144), y: geometry.canvasY, line: false)
    modulation.finish()
    report.expect(modulation.points[144] == 126 && modulation.value(atY: geometry.canvasY
                  + geometry.canvasHeight) == 0,
                  cppID: "swiftcore/PitchBendEditingTest::vertexCreation",
                  message: "modulation uses the oracle's QRect-height scaling at the top pixel and clamps below zero")

    pitchBendDocumentPredicates(report, session: session)
}

@MainActor
private struct PitchBendCheckScene {
    let presenter: PitchBendPresenter
    let note: Note
    let noteEnd: Tick
}

@MainActor
private func pitchBendCheckScene(_ report: CheckReport, cppID: String,
                                 session: DocumentSession) -> PitchBendCheckScene? {
    var host: (note: Note, track: Int)?
    for track in 0..<session.document.engineTracks.usedTrackCount {
        if let candidate = session.document.notes(in: track)
            .filter({ !$0.isUnterminated && $0.duration >= 24 })
            .max(by: { $0.duration < $1.duration }) {
            host = (candidate, track)
            break
        }
    }
    guard let host else {
        report.fail(cppID, "no terminated note spanning at least one beat is available")
        return nil
    }
    session.selectPrimaryTrack(host.track)
    session.setSelectedNotes([host.note.id])
    let grid = PianoGrid(session: session)
    let presenter = PitchBendPresenter(session: session, grid: grid, palette: grid.palette)
    presenter.configure(fontPx: grid.baseFontPx, lineSpacing: grid.baseFontPx, dpr: 2)
    let opened = presenter.openSelected()
    report.expect(opened, cppID: cppID,
                  message: "the Edit→Pitch Bend route opens the selected note's editor")
    report.expect(presenter.isOpen, cppID: cppID,
                  message: "the opened editor stays open")
    guard opened, let noteEnd = host.note.endTick, noteEnd <= UInt64(Tick.max) else {
        report.fail(cppID, "the pitch bend editor did not open")
        return nil
    }
    return PitchBendCheckScene(presenter: presenter, note: host.note,
                             noteEnd: Tick(noteEnd))
}

@MainActor
private func pitchBendCanvasPoint(_ lane: PitchBendLane, xFraction: Double,
                                  yFraction: Double) -> (x: Double, y: Double) {
    let g = lane.kernel.geometry
    return (x: (g.canvasX + g.canvasWidth * xFraction).rounded(),
            y: (g.canvasY + g.canvasHeight * yFraction).rounded())
}

@MainActor
private func pitchBendStroke(_ lane: PitchBendLane, x0f: Double, y0f: Double,
                             x1f: Double, y1f: Double, modifiers: Int = 0) {
    let start = pitchBendCanvasPoint(lane, xFraction: x0f, yFraction: y0f)
    let finish = pitchBendCanvasPoint(lane, xFraction: x1f, yFraction: y1f)
    lane.press(x: start.x, y: start.y, modifiers: modifiers)
    lane.drag(x: finish.x, y: finish.y, modifiers: modifiers)
    lane.release(x: finish.x, y: finish.y, modifiers: modifiers)
}

@MainActor
private func pitchBendDrawCurve(_ lane: PitchBendLane) {
    pitchBendStroke(lane, x0f: 0.25, y0f: 0.70, x1f: 0.75, y1f: 0.25)
}

@MainActor
private func pitchBendLaneHasPoint(_ document: SongDocument, track: Int, lane: Lane,
                                   tick: Tick, value: Int) -> Bool {
    document.lanePoints(track: track, lane: lane).contains { point in
        point.tick == tick && point.value == value
    }
}

@MainActor
private func pitchBendSpanAlive(_ session: DocumentSession, note: Note,
                                noteEnd: Tick) -> Bool {
    guard let current = session.document.note(note.id) else { return false }
    return current.track == note.track && current.tick == note.tick
        && current.endTick == UInt64(noteEnd) && current.pitch == note.pitch
}

@MainActor
private func pitchBendDocumentPredicates(_ report: CheckReport, session: DocumentSession) {
    let undoPreservationID = "swiftcore/PitchBendEditingTest::bendrFixtureUndoPreservation"
    let shiftLineID = "swiftcore/PitchBendEditingTest::shiftDragDrawsLinearRamp"
    let freehandID = "swiftcore/PitchBendEditingTest::freehandStrokePushesSingleUndoCommand"
    let undoShortcutID = "swiftcore/PitchBendEditingTest::standardUndoShortcutRestoresCurve"
    let navigationID = "swiftcore/PitchBendEditingTest::navigationKeysDoNotModifyCurve"
    let stackedID = "swiftcore/PitchBendEditingTest::stackedStrokesPushIndependentUndoCommands"
    let confinementID = "swiftcore/PitchBendEditingTest::freehandStrokeConfinedToNoteSpan"
    let smfID = "swiftcore/PitchBendEditingTest::pitchWheelSerializesValidSmfEvents"

    let document = session.document

    if let scene = pitchBendCheckScene(report, cppID: undoPreservationID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let before = coreTimeBytes(document)
        let index = document.history.undoIndex
        document.writeLane(track: scene.note.track, lane: .controller(0x14),
                           from: scene.note.tick, through: scene.note.tick,
                           points: [LaneWrite(tick: scene.note.tick, value: 12)])
        report.expectEqual(expected: index + 1, actual: document.history.undoIndex,
                           cppID: undoPreservationID,
                           what: "one BENDR write pushes exactly one history entry")
        report.expect(pitchBendLaneHasPoint(document, track: scene.note.track,
                                            lane: .controller(0x14), tick: scene.note.tick,
                                            value: 12),
                      cppID: undoPreservationID,
                      message: "the written BENDR point is visible in the lane")
        report.expect(document.history.undoDocument() && document.history.undoIndex == index,
                      cppID: undoPreservationID,
                      message: "undoing the BENDR write restores the history index")
        report.expectEqual(expected: before, actual: coreTimeBytes(document),
                           cppID: undoPreservationID,
                           what: "undoing the BENDR write restores the serialized song")
        report.expect(pitchBendSpanAlive(session, note: scene.note, noteEnd: scene.noteEnd),
                      cppID: undoPreservationID,
                      message: "the note span survives its lane undo")
    }

    if let scene = pitchBendCheckScene(report, cppID: shiftLineID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        report.expect(graph.kernel.geometry.canvasWidth > 0
                      && graph.kernel.geometry.canvasHeight > 0,
                      cppID: shiftLineID,
                      message: "the pitch graph presents a real canvas")
        let index = document.history.undoIndex
        let before = coreTimeBytes(document)
        pitchBendStroke(graph, x0f: 0.15, y0f: 0.80, x1f: 0.85, y1f: 0.20,
                        modifiers: 0x0200_0000)
        report.expectEqual(expected: index + 1, actual: document.history.undoIndex,
                           cppID: shiftLineID,
                           what: "one Shift-line stroke pushes exactly one history entry")
        report.expect(scene.presenter.isOpen, cppID: shiftLineID,
                      message: "rendering the Shift line keeps the editor open")
        let interior = document.lanePoints(track: scene.note.track, lane: .pitchBend)
            .filter { $0.tick > scene.note.tick && $0.tick < scene.noteEnd }
        report.expect(interior.count >= 2, cppID: shiftLineID,
                      message: "the Shift line serializes interior lane points")
        report.expect(!interior.indices.dropFirst().contains(where: {
            interior[$0].value == interior[$0 - 1].value
        }), cppID: shiftLineID,
            message: "adjacent interior lane points never share one value")
        report.expect(document.history.undoDocument() && coreTimeBytes(document) == before,
                      cppID: shiftLineID,
                      message: "undoing the Shift line restores the serialized song")
    }

    if let scene = pitchBendCheckScene(report, cppID: freehandID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        let index = document.history.undoIndex
        pitchBendDrawCurve(graph)
        report.expectEqual(expected: index + 1, actual: document.history.undoIndex,
                           cppID: freehandID,
                           what: "one freehand stroke pushes exactly one history entry")
        report.expect(scene.presenter.isOpen, cppID: freehandID,
                      message: "a committed freehand stroke keeps the editor open")
        report.expect(document.history.undoDocument(), cppID: freehandID,
                      message: "the freehand stroke's history entry undoes")
    }

    if let scene = pitchBendCheckScene(report, cppID: undoShortcutID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        let before = coreTimeBytes(document)
        let index = document.history.undoIndex
        pitchBendDrawCurve(graph)
        report.expect(document.history.undoDocument() && document.history.undoIndex == index,
                      cppID: undoShortcutID,
                      message: "undoing the drawn curve restores the history index")
        report.expectEqual(expected: before, actual: coreTimeBytes(document),
                           cppID: undoShortcutID,
                           what: "undoing the drawn curve restores the serialized song")
        report.expect(scene.presenter.isOpen, cppID: undoShortcutID,
                      message: "the editor survives undoing its curve")
    }

    if let scene = pitchBendCheckScene(report, cppID: navigationID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let before = coreTimeBytes(document)
        let index = document.history.undoIndex
        for key in [0x01000012, 0x01000014, 0x01000010, 0x01000011, 0x01000015,
                    0x01000016, 0x01000017, 0x30] {
            let modifiers = key == 0x01000016 ? 0x0200_0000 : 0
            report.expect(!scene.presenter.routeUnclaimedKey(key: key, modifiers: modifiers,
                                                           autoRepeat: false)
                          && document.history.undoIndex == index,
                          cppID: navigationID,
                          message: "navigation key \(key) pushes no history entry")
            report.expectEqual(expected: before, actual: coreTimeBytes(document),
                               cppID: navigationID,
                               what: "navigation key \(key) leaves the serialized song")
        }
        report.expect(scene.presenter.isOpen, cppID: navigationID,
                      message: "navigation keys keep the editor open")
    }

    if let scene = pitchBendCheckScene(report, cppID: stackedID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        let baseline = coreTimeBytes(document)
        let baselineIndex = document.history.undoIndex
        pitchBendDrawCurve(graph)
        let first = coreTimeBytes(document)
        let firstIndex = document.history.undoIndex
        report.expectEqual(expected: baselineIndex + 1, actual: firstIndex,
                           cppID: stackedID,
                           what: "the first stroke pushes one independent history entry")
        pitchBendStroke(graph, x0f: 0.10, y0f: 0.25, x1f: 0.40, y1f: 0.75)
        report.expectEqual(expected: firstIndex + 1, actual: document.history.undoIndex,
                           cppID: stackedID,
                           what: "the second stroke pushes its own history entry")
        report.expect(coreTimeBytes(document) != first, cppID: stackedID,
                      message: "stacked strokes serialize different curves")
        report.expect(document.history.undoDocument() && document.history.undoIndex == firstIndex,
                      cppID: stackedID,
                      message: "the first undo returns to the first stroke's index")
        report.expectEqual(expected: first, actual: coreTimeBytes(document),
                           cppID: stackedID,
                           what: "the first undo restores the first stroke's bytes")
        report.expect(document.history.undoDocument() && document.history.undoIndex == baselineIndex,
                      cppID: stackedID,
                      message: "the second undo returns to the pre-stroke index")
        report.expectEqual(expected: baseline, actual: coreTimeBytes(document),
                           cppID: stackedID,
                           what: "the second undo restores the pre-stroke bytes")
    }

    if let scene = pitchBendCheckScene(report, cppID: confinementID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        var endValue = 0
        for point in document.lanePoints(track: scene.note.track, lane: .pitchBend) {
            if point.tick > scene.noteEnd { break }
            endValue = point.value
        }
        let before = document.lanePoints(track: scene.note.track, lane: .pitchBend)
        pitchBendDrawCurve(graph)
        let after = document.lanePoints(track: scene.note.track, lane: .pitchBend)
        var wroteInside = false
        var confined = true
        for point in after {
            let existedBefore = before.contains { $0.tick == point.tick && $0.value == point.value }
            if existedBefore { continue }
            confined = confined && point.tick >= scene.note.tick && point.tick <= scene.noteEnd
            if point.tick < scene.noteEnd && point.value != 0 { wroteInside = true }
        }
        report.expect(confined, cppID: confinementID,
                      message: "every new curve point stays inside the note span")
        report.expect(wroteInside, cppID: confinementID,
                      message: "the freehand stroke writes a nonzero interior point")
        report.expect(pitchBendLaneHasPoint(document, track: scene.note.track,
                                            lane: .pitchBend, tick: scene.noteEnd,
                                            value: endValue),
                      cppID: confinementID,
                      message: "the note-off lane point keeps its effective value")
        report.expect(document.history.undoDocument(), cppID: confinementID,
                      message: "the confined stroke's history entry undoes")
    }

    if let scene = pitchBendCheckScene(report, cppID: smfID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let graph = scene.presenter.pitchGraph()
        pitchBendDrawCurve(graph)
        let map = document.engineTracks
        report.expect(scene.note.track < map.usedTrackCount
                      && map.tracks.indices.contains(scene.note.track)
                      && map.tracks[scene.note.track].midiChunk != nil,
                      cppID: smfID,
                      message: "the note's track maps to a serialized chunk")
        var found = false
        var data0Valid = true
        var data1Valid = true
        if let chunk = map.tracks[scene.note.track].midiChunk {
            for event in document.state.file.chunks[chunk].events {
                guard event.tick >= scene.note.tick && event.tick <= scene.noteEnd,
                      case let .channel(status, data0, data1) = event.payload,
                      status >> 4 == 0xE else { continue }
                found = true
                data0Valid = data0Valid && data0 <= 0x7F
                data1Valid = data1Valid && data1 <= 0x7F
            }
        }
        report.expect(data0Valid, cppID: smfID,
                      message: "pitch-wheel data0 stays within 7 bits")
        report.expect(data1Valid, cppID: smfID,
                      message: "pitch-wheel data1 stays within 7 bits")
        report.expect(found, cppID: smfID,
                      message: "the note span serializes at least one pitch-wheel event")
        report.expect(document.history.undoDocument(), cppID: smfID,
                      message: "the serialized stroke's history entry undoes")
    }
}
