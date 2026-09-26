import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

private func pitchBendFixtureSnap(_ tick: Double, fine: Bool) -> Int {
    let stride = Double(fine ? 1 : 12)
    let lower = (max(0, tick) / stride).rounded(.down) * stride
    return Int(tick - lower <= stride / 2 ? lower : lower + stride)
}

private func pitchBendFixtureSnapUp(_ tick: Double, fine: Bool) -> Int {
    let stride = Double(fine ? 1 : 12)
    return Int(((max(0, tick) + 0.5) / stride).rounded(.up) * stride)
}

@MainActor
func runPitchBendChecks(_ report: CheckReport, session: DocumentSession) {
    let geometry = PitchBendGeometry(fontPx: 14, lineSpacing: 17, dpr: 2)
    let origin = [96: 0, 192: 0]
    var curve = PitchBendKernel(lane: .pitch, geometry: geometry,
                                startTick: 96, endTick: 192,
                                fineTicks: 1, snap: pitchBendFixtureSnap,
                                snapUp: pitchBendFixtureSnapUp,
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
                                     fineTicks: 1, snap: pitchBendFixtureSnap,
                                     snapUp: pitchBendFixtureSnapUp,
                                     points: origin, endValue: 0)
    modulation.begin(x: modulation.x(at: 144), y: geometry.canvasY, line: false)
    modulation.finish()
    report.expect(modulation.points[144] == 126 && modulation.value(atY: geometry.canvasY
                  + geometry.canvasHeight) == 0,
                  cppID: "swiftcore/PitchBendEditingTest::vertexCreation",
                  message: "modulation uses the oracle's QRect-height scaling at the top pixel and clamps below zero")
    pitchBendSharedGridPredicates(report, session: session)
    pitchBendReadoutPredicates(report, session: session)
    pitchBendDocumentPredicates(report, session: session)
    pitchBendOwnerLifetimePredicates(report, suite: session)
    pitchBendExternalPreviewPredicates(report, suite: session)
    pitchBendUnterminatedPredicates(report, suite: session)
    pitchBendParityPredicates(report, suite: session)
    pitchBendControllerPredicates(report, session: session)
    pitchBendResetPredicates(report, session: session)
    pitchBendSetterPredicates(report, session: session)
    pitchBendFineRampPredicates(report, session: session)
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
private func pitchBendSharedGridPredicates(_ report: CheckReport, session: DocumentSession) {
    let gridID = "swiftcore/PitchBendEditingTest::sharedGridSnap"
    let previous = session.grid.selection
    session.grid.setSelection(.clock)
    defer { session.grid.setSelection(previous) }
    guard let scene = pitchBendCheckScene(report, cppID: gridID, session: session) else { return }
    defer { scene.presenter.cancelAndClose() }
    var kernel = scene.presenter.pitchGraph().kernel
    let interiorTick = Int(scene.note.tick) + 1
    kernel.begin(x: kernel.x(at: interiorTick), y: kernel.y(at: 4096), line: false)
    kernel.finish()
    report.expect(kernel.points[interiorTick] != nil
                  && kernel.snapTicks == Int(session.grid.snapTicksAt(scene.note.tick,
                                                                       camera: session.camera)),
                  cppID: gridID,
                  message: "clock grid selection permits a pitch-bend point one tick inside the selected note")
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
private func pitchBendReadoutPredicates(_ report: CheckReport, session: DocumentSession) {
    let readoutID = "swiftcore/PitchBendEditingTest::liveValueReadout"
    if let scene = pitchBendCheckScene(report, cppID: readoutID, session: session) {
        defer { scene.presenter.cancelAndClose() }
        let roles = Typography(baseFontPx: 13)
        func matches(_ key: String, _ expected: [String: QVariantSettable]) -> Bool {
            guard let map = scene.presenter.appearance[key] as? [String: QVariantSettable] else {
                return false
            }
            return map["family"] as? String == expected["family"] as? String &&
                map["pixelSize"] as? Int == expected["pixelSize"] as? Int &&
                map["weight"] as? Int == expected["weight"] as? Int
        }
        report.expect(matches("titleFont", roles.bodyBold.map) &&
                      matches("captionFont", roles.caption.map) &&
                      matches("monospaceFont", roles.bodyMono.map),
                      cppID: readoutID,
                      message: "the popup title, caption, and readout publish bold body, caption, and body mono faces")
        let drag = scene.presenter.appearance["dragInput"] as? [String: QVariantSettable]
        let dragFont = drag?["font"] as? [String: QVariantSettable]
        report.expect(dragFont?["family"] as? String == roles.body.family &&
                      dragFont?["pixelSize"] as? Int == roles.body.pixelSize &&
                      dragFont?["weight"] as? Int == roles.body.weight,
                      cppID: readoutID,
                      message: "pitch drag inputs use the published body font face")
        let resized = Typography(baseFontPx: 26)
        scene.presenter.configure(fontPx: 26, lineSpacing: 29, dpr: 2)
        let resizedDrag = scene.presenter.appearance["dragInput"] as? [String: QVariantSettable]
        let resizedFont = resizedDrag?["font"] as? [String: QVariantSettable]
        report.expect(matches("titleFont", resized.bodyBold.map) &&
                      matches("captionFont", resized.caption.map) &&
                      matches("monospaceFont", resized.bodyMono.map) &&
                      resizedFont?["family"] as? String == resized.body.family &&
                      resizedFont?["pixelSize"] as? Int == resized.body.pixelSize &&
                      resizedDrag?["horizontalPadding"] as? Double == Double(resized.space(.one)),
                      cppID: readoutID,
                      message: "resizing the pitch popup republishes the title, caption, readout, and input roles")
        scene.presenter.configure(fontPx: 13, lineSpacing: 13, dpr: 2)
        report.expectEqual(expected: "0 st", actual: scene.presenter.pitchGraph().liveValueText,
                           cppID: readoutID,
                           what: "the pitch readout at rest is 0 st")
        report.expectEqual(expected: "0", actual: scene.presenter.modGraph().liveValueText,
                           cppID: readoutID,
                           what: "the modulation readout at rest is the plain decimal")
    }

    let geometry = PitchBendGeometry(fontPx: 14, lineSpacing: 17, dpr: 2)
    let pitch = PitchBendLane(
        kernel: PitchBendKernel(lane: .pitch, geometry: geometry,
                                startTick: 96, endTick: 192,
                                fineTicks: 1, snap: pitchBendFixtureSnap,
                                snapUp: pitchBendFixtureSnapUp,
                                points: [96: 4096, 192: 0], endValue: 0),
        palette: GridPalette(), track: 0)
    pitch.bendRange = 5
    pitch.rebuild()
    report.expectEqual(expected: "+2.50 st", actual: pitch.liveValueText,
                       cppID: readoutID,
                       what: "the pitch readout formats liveValue 4096 at bendRange 5 "
                           + "as +2.50 st")
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

@MainActor
private func pitchBendSyntheticSession(_ suite: DocumentSession, service: ProjectService,
                                       file: MidiFile = makeMidiFixture()) -> DocumentSession {
    let document = SongDocument(file: file, config: suite.document.state.config,
                                source: suite.document.source, trackBudget: suite.document.trackBudget)
    return DocumentSession(document: document, service: service,
                           lease: suite.bankLease, slots: suite.bankSlots,
                           dirty: false, loadName: suite.bankLoadName, sampleRate: 48_000)
}

@MainActor
private func pitchBendObserveDocument(_ session: DocumentSession,
                                      presenter: PitchBendPresenter) {
    session.onChange = { [weak presenter] change in
        if change.domains.contains(.document) { presenter?.documentDidChange() }
        if change.domains.contains(.selection) { presenter?.cancelAndClose() }
    }
}

@MainActor
private func pitchBendOwnerLifetimePredicates(_ report: CheckReport, suite: DocumentSession) {
    let id = "swiftcore/PitchBendEditingTest::duplicateNoteAtSameTickDoesNotReanchor"
    let service = ProjectService()
    let session = pitchBendSyntheticSession(suite, service: service)
    defer { withExtendedLifetime(service) {} }
    let document = session.document
    guard let ids = try? document.addNotes([
        NewNote(track: 0, tick: 240, pitch: 67, duration: 72, velocity: 91),
        NewNote(track: 0, tick: 240, pitch: 67, duration: 72, velocity: 73)
    ]), ids.count == 2,
          let original = document.note(ids[0]),
          let impostor = document.note(ids[1]) else {
        report.fail(id, "the duplicate-note fixture must provide both distinct note identities")
        return
    }
    report.expect(impostor.id != original.id, cppID: id,
                  message: "the duplicate note retains an independent identity")
    report.expect(impostor.tick == original.tick, cppID: id,
                  message: "the impostor shares the anchor note's tick")
    report.expect(impostor.pitch == original.pitch, cppID: id,
                  message: "the impostor shares the anchor note's key")
    report.expect(impostor.endTick == original.endTick, cppID: id,
                  message: "the impostor shares the anchor note's editing span")
    let before = coreTimeBytes(document)
    let index = document.history.undoIndex
    guard let scene = pitchBendCheckScene(report, cppID: id, session: session) else { return }
    pitchBendObserveDocument(session, presenter: scene.presenter)
    report.expect(scene.note.id == original.id, cppID: id,
                  message: "the editor opens on the original note rather than its impostor")
    report.expect(original.endTick == UInt64(scene.presenter.pitchGraph().kernel.endTick),
                  cppID: id, message: "the open editor's graph spans exactly the selected note")
    document.deleteNotes([original.id])
    report.expect(!scene.presenter.isOpen, cppID: id,
                  message: "deleting the anchored note closes the editor")
    report.expect(document.note(ids[1]) != nil, cppID: id,
                  message: "the same-tick impostor survives deletion of the anchor")
    report.expect(document.note(original.id) == nil, cppID: id,
                  message: "the anchored note's span is gone after deletion")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "undo restores the anchored note and the exact prior song bytes")
    report.expectEqual(expected: index, actual: document.history.undoIndex, cppID: id,
                       what: "undo restores the anchored note's history index")
    report.expectEqual(expected: before, actual: coreTimeBytes(document), cppID: id,
                       what: "undo restores the anchored note and the exact prior song bytes")
    report.expect(pitchBendSpanAlive(session, note: original, noteEnd: scene.noteEnd),
                  cppID: id, message: "undo restores the anchored note")
    report.expect(!scene.presenter.isOpen, cppID: id,
                  message: "undo leaves the dismissed anchored editor closed")
    let moveID = "swiftcore/PitchBendEditingTest::externalMoveClosesAnchor"
    session.selectPrimaryTrack(0)
    session.setSelectedNotes([original.id])
    report.expect(scene.presenter.openSelected(), cppID: moveID,
                  message: "the restored anchor note reopens for an external move")
    document.moveNotes([original.id], byTicks: 1, byKeys: 0)
    report.expect(!scene.presenter.isOpen, cppID: moveID,
                  message: "moving the anchored note closes the editor")
    report.expect(document.note(ids[1]) != nil, cppID: moveID,
                  message: "moving the anchor does not rebind the same-tick impostor")
}

@MainActor
private func pitchBendExternalPreviewPredicates(_ report: CheckReport, suite: DocumentSession) {
    let id = "swiftcore/PitchBendEditingTest::externalEditPreservesLivePreview"
    let service = ProjectService()
    let session = pitchBendSyntheticSession(suite, service: service)
    defer { withExtendedLifetime(service) {} }
    guard let scene = pitchBendCheckScene(report, cppID: id, session: session) else { return }
    let presenter = scene.presenter
    defer { presenter.cancelAndClose() }
    pitchBendObserveDocument(session, presenter: presenter)
    let graph = presenter.pitchGraph()
    let start = pitchBendCanvasPoint(graph, xFraction: 0.25, yFraction: 0.70)
    let finish = pitchBendCanvasPoint(graph, xFraction: 0.75, yFraction: 0.30)
    graph.press(x: start.x, y: start.y, modifiers: 0)
    graph.drag(x: finish.x, y: finish.y, modifiers: 0)
    let preview = graph.kernel.points
    let endValue = graph.kernel.endValue
    report.expect(graph.kernel.hasGesture, cppID: id,
                  message: "an unfinished stroke keeps its live gesture")
    let document = session.document
    let before = coreTimeBytes(document)
    let index = document.history.undoIndex
    document.writeLane(track: 0, lane: .controller(0x15),
                       from: scene.note.tick, through: scene.noteEnd,
                       points: [LaneWrite(tick: scene.note.tick, value: 23),
                                LaneWrite(tick: scene.noteEnd, value: 22)])
    report.expectEqual(expected: index + 1, actual: document.history.undoIndex, cppID: id,
                       what: "an external lane edit pushes exactly one history entry under the open gesture")
    report.expect(coreTimeBytes(document) != before, cppID: id,
                  message: "the external lane edit changes the serialized song")
    report.expect(graph.kernel.points == preview && graph.kernel.endValue == endValue,
                  cppID: id, message: "the live preview survives the external edit")
    report.expect(graph.kernel.hasGesture, cppID: id,
                  message: "the gesture survives the external edit")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "undoing the external edit restores the history entry")
    report.expectEqual(expected: index, actual: document.history.undoIndex, cppID: id,
                       what: "undoing the external edit restores the history index")
    report.expectEqual(expected: before, actual: coreTimeBytes(document), cppID: id,
                       what: "undoing the external edit restores the exact prior song bytes")
    report.expect(graph.kernel.points == preview && graph.kernel.endValue == endValue,
                  cppID: id, message: "the live preview survives undo of the external edit")
    report.expect(graph.kernel.hasGesture, cppID: id,
                  message: "the gesture survives undo of the external edit")
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "redo reapplies the external edit as one entry")
    report.expectEqual(expected: index + 1, actual: document.history.undoIndex, cppID: id,
                       what: "redo reapplies the external edit at the next history index")
    report.expect(coreTimeBytes(document) != before, cppID: id,
                  message: "redo reapplies the external lane edit to the serialized song")
    report.expect(graph.kernel.points == preview && graph.kernel.endValue == endValue,
                  cppID: id, message: "the live preview survives redo of the external edit")
    report.expect(graph.kernel.hasGesture, cppID: id,
                  message: "the gesture survives redo of the external edit")
    presenter.cancelAndClose()
    report.expect(!presenter.isOpen, cppID: id,
                  message: "Escape closes the editor after the external-edit cycle")
}

@MainActor
private func pitchBendUnterminatedPredicates(_ report: CheckReport, suite: DocumentSession) {
    let id = "swiftcore/PitchBendEditingTest::unterminatedNoteRefusesEditing"
    var file = makeMidiFixture()
    file.chunks[1].events.append(.channel(tick: 168, status: 0x90, data0: 70, data1: 90))
    let service = ProjectService()
    let session = pitchBendSyntheticSession(suite, service: service, file: file)
    defer { withExtendedLifetime(service) {} }
    let document = session.document
    guard let note = document.notes(in: 0).first(where: { $0.tick == 168 && $0.pitch == 70 }) else {
        report.fail(id, "the unterminated note fixture is absent")
        return
    }
    report.expect(note.isUnterminated, cppID: id,
                  message: "the fixture contains an unterminated note")
    report.expect(note.endTick == nil, cppID: id,
                  message: "the unterminated note has no editable span endpoint")
    session.selectPrimaryTrack(0)
    session.setSelectedNotes([note.id])
    let grid = PianoGrid(session: session)
    let presenter = PitchBendPresenter(session: session, grid: grid, palette: grid.palette)
    pitchBendObserveDocument(session, presenter: presenter)
    let before = coreTimeBytes(document)
    report.expect(!presenter.openSelected(), cppID: id,
                  message: "the G route refuses an unterminated note without opening the editor")
    report.expect(!presenter.isOpen, cppID: id,
                  message: "an unterminated note leaves the editor closed")
    report.expectEqual(expected: before, actual: coreTimeBytes(document), cppID: id,
                       what: "refusing the unterminated note leaves the song bytes unchanged")
}

@MainActor
private func pitchBendParityPredicates(_ report: CheckReport, suite: DocumentSession) {
    let id = "swiftcore/PitchBendEditingTest::dynamicSignatureSnap"
    let service = ProjectService()
    let session = pitchBendSyntheticSession(suite, service: service)
    defer { withExtendedLifetime(service) {} }
    guard let notes = try? session.document.addNotes([
        NewNote(track: 0, tick: 288, pitch: 61, duration: 384, velocity: 100)
    ]), let note = notes.first else {
        report.fail(id, "the signature-seam note fixture exists")
        return
    }
    session.document.setTimeSignature(tick: 480, numerator: 8, denominatorPower: 3)
    session.selectPrimaryTrack(0)
    session.setSelectedNotes([note])
    let grid = PianoGrid(session: session)
    let presenter = PitchBendPresenter(session: session, grid: grid, palette: grid.palette)
    guard presenter.openSelected() else {
        report.fail(id, "a note across a signature seam opens its editor")
        return
    }
    defer { presenter.cancelAndClose() }
    let graph = presenter.pitchGraph()
    report.expect(graph.kernel.endTick == 672, cppID: id,
                  message: "a note across a signature seam opens its editor")
    pitchBendStroke(graph, x0f: 0.10, y0f: 0.80, x1f: 0.90, y1f: 0.20)
    let interior = session.document.lanePoints(track: 0, lane: .pitchBend)
        .filter { $0.tick > 288 && $0.tick < 672 }
    report.expect(!interior.isEmpty && interior.allSatisfy {
        session.grid.snapTick(Double($0.tick), camera: session.camera) == $0.tick
    }, cppID: id, message: "every committed point sits on the dynamic snap lattice")
    report.expect(interior.contains { $0.tick < 480 } && interior.contains { $0.tick >= 480 },
                  cppID: id, message: "committed points straddle the signature seam")
    session.grid.setSelection(.musical(4))
    presenter.resetPitchCurve()
    pitchBendStroke(graph, x0f: 0.12, y0f: 0.75, x1f: 0.88, y1f: 0.30)
    let resnapped = session.document.lanePoints(track: 0, lane: .pitchBend)
        .filter { $0.tick > 288 && $0.tick < 672 }
    report.expect(!resnapped.isEmpty && resnapped.allSatisfy {
        session.grid.snapTick(Double($0.tick), camera: session.camera) == $0.tick
    }, cppID: id, message: "every committed point sits on the dynamic snap lattice after a grid change")
    session.grid.setSelection(.auto)
    let beforeZoomStride = session.grid.snapTicksAt(288, camera: session.camera)
    _ = session.mutateCamera { _ = $0.setTimeZoom(140) }
    let afterZoomStride = session.grid.snapTicksAt(288, camera: session.camera)
    presenter.resetPitchCurve()
    pitchBendStroke(graph, x0f: 0.14, y0f: 0.70, x1f: 0.86, y1f: 0.35)
    let zoomed = session.document.lanePoints(track: 0, lane: .pitchBend)
        .filter { $0.tick > 288 && $0.tick < 672 }
    report.expect(!zoomed.isEmpty && zoomed.allSatisfy {
        session.grid.snapTick(Double($0.tick), camera: session.camera) == $0.tick
    }, cppID: id, message: "every committed point sits on the live snap lattice after a zoom change")
    let zoomTicks = Set(zoomed.map(\.tick))
    var zoomCoverage = !zoomed.isEmpty
    if let firstPoint = zoomed.first?.tick, let lastPoint = zoomed.last?.tick {
        var tick = firstPoint
        while tick < lastPoint {
            let next = session.grid.snapTickUp(Double(tick) + 0.5, camera: session.camera)
            if next <= tick { zoomCoverage = false; break }
            zoomCoverage = zoomCoverage && zoomTicks.contains(next)
            tick = next
        }
    }
    report.expect(afterZoomStride < beforeZoomStride && zoomCoverage, cppID: id,
                  message: "the zoomed stroke samples every live grid cell")

    let keyID = "swiftcore/PitchBendEditorTest::popupKeyArbitration"
    let bytes = coreTimeBytes(session.document)
    let index = session.document.history.undoIndex
    var auditions: [Tick] = []
    var soloCount = 0
    presenter.onAuditionFromTick = { auditions.append($0) }
    presenter.onSoloTracksRequested = { soloCount += 1 }
    report.expect(presenter.routeUnclaimedKey(key: 0x20, modifiers: 0, autoRepeat: false)
                  && auditions == [288],
                  cppID: keyID, message: "Space auditions from the note's start tick")
    report.expect(!presenter.routeUnclaimedKey(key: 0x20, modifiers: 0, autoRepeat: true)
                  && auditions.count == 1,
                  cppID: keyID, message: "held Space does not repeat the note audition")
    report.expect(presenter.routeUnclaimedKey(key: 0x53, modifiers: 0, autoRepeat: false)
                  && soloCount == 1,
                  cppID: keyID, message: "S toggles solo exactly once while the popup is open")
    report.expect(!presenter.routeUnclaimedKey(key: 0x4d, modifiers: 0, autoRepeat: false)
                  && soloCount == 1, cppID: keyID,
                  message: "M stays absorbed while the popup has focus")
    report.expect(session.document.history.undoIndex == index
                  && coreTimeBytes(session.document) == bytes && presenter.isOpen,
                  cppID: keyID, message: "auditioning from the popup changes no document bytes with the editor open")
}

@MainActor
private func pitchBendControllerPredicates(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PitchBendControllerTest::wheelAndControllerWrites"
    guard let scene = pitchBendCheckScene(report, cppID: id, session: session) else { return }
    defer { scene.presenter.cancelAndClose() }
    let presenter = scene.presenter
    let document = session.document
    let index = document.history.undoIndex
    let range = presenter.bendRange
    let graph = presenter.pitchGraph()
    graph.wheel(angleY: 120, pixelY: 0, momentum: false)
    report.expect(presenter.bendRange == range + 1 && document.history.undoIndex == index + 1,
                  cppID: id, message: "wheeling inside the pitch graph raises BENDR one step per notch")
    report.expect(presenter.description.contains("\(range + 1) semitones"),
                  cppID: id, message: "the description reflects the active BENDR semitones")
    report.expect(pitchBendLaneHasPoint(document, track: scene.note.track,
                                        lane: .controller(0x14), tick: scene.note.tick,
                                        value: range + 1)
                  && pitchBendLaneHasPoint(document, track: scene.note.track,
                                            lane: .controller(0x14), tick: scene.noteEnd,
                                            value: range),
                  cppID: id, message: "the wheeled BENDR write is note-bounded")
    presenter.documentDidChange()
    report.expect(presenter.isOpen && presenter.pitchGraph() === graph,
                  cppID: id, message: "internal edits and refreshes keep the same editor open")
}

@MainActor
private func pitchBendResetPredicates(_ report: CheckReport, session: DocumentSession) {
    let modID = "swiftcore/PitchBendEditingTest::modWheelStrokeAndReset"
    guard let scene = pitchBendCheckScene(report, cppID: modID, session: session) else { return }
    defer { scene.presenter.cancelAndClose() }
    let presenter = scene.presenter
    let document = session.document
    let mod = presenter.modGraph()
    let baseline = coreTimeBytes(document)
    let index = document.history.undoIndex
    let endValue = mod.kernel.endValue
    pitchBendDrawCurve(mod)
    let drawn = coreTimeBytes(document)
    let interior = document.lanePoints(track: scene.note.track, lane: .controller(1))
        .filter { $0.tick > scene.note.tick && $0.tick < scene.noteEnd }
    report.expect(document.history.undoIndex == index + 1 && interior.contains { $0.value > 0 },
                  cppID: modID, message: "a mod-wheel stroke writes note-scoped CC1 with interior motion")
    report.expect(pitchBendLaneHasPoint(document, track: scene.note.track,
                                        lane: .controller(1), tick: scene.noteEnd,
                                        value: endValue),
                  cppID: modID, message: "the mod-wheel stroke preserves the note-off lane value")
    report.expect(document.history.undoDocument() && presenter.isOpen
                  && coreTimeBytes(document) == baseline, cppID: modID,
                  message: "undoing the mod-wheel stroke restores the exact prior song bytes with the editor open")
    presenter.documentDidChange()
    report.expect(presenter.isOpen, cppID: modID,
                  message: "internal edits and refreshes keep the same editor open")
    pitchBendDrawCurve(mod)
    let resetIndex = document.history.undoIndex
    presenter.resetModCurve()
    report.expect(document.history.undoIndex == resetIndex + 1, cppID: modID,
                  message: "the mod-wheel reset pushes one history entry")
    report.expect(mod.kernel.points.keys.allSatisfy {
        $0 == Int(scene.note.tick) || $0 == Int(scene.noteEnd)
    } && mod.kernel.points[Int(scene.note.tick)] == 0
        && document.lanePoints(track: scene.note.track, lane: .controller(1))
            .filter { $0.tick >= scene.note.tick && $0.tick < scene.noteEnd }
            .allSatisfy { $0.value == 0 },
    cppID: modID, message: "the mod-wheel reset zeroes the lane over the note span")
    report.expect(pitchBendLaneHasPoint(document, track: scene.note.track,
                                        lane: .controller(1), tick: scene.noteEnd,
                                        value: endValue),
                  cppID: modID, message: "the mod-wheel reset preserves the note-off lane value")
    report.expect(presenter.isOpen, cppID: modID,
                  message: "the mod-wheel reset keeps the editor open")
    let modUndone = document.history.undoDocument()
    presenter.documentDidChange()
    report.expect(modUndone && coreTimeBytes(document) == drawn
                  && presenter.isOpen && mod.kernel.points.values.contains { $0 != 0 },
                  cppID: modID, message: "undoing the mod-wheel reset restores the drawn curve bytes")

    let pitchID = "swiftcore/PitchBendEditingTest::pitchCurveReset"
    let pitch = presenter.pitchGraph()
    pitchBendDrawCurve(pitch)
    let pitchDrawn = coreTimeBytes(document)
    let pitchEnd = pitch.kernel.endValue
    let pitchIndex = document.history.undoIndex
    presenter.resetPitchCurve()
    report.expect(document.history.undoIndex == pitchIndex + 1, cppID: pitchID,
                  message: "the pitch reset pushes one history entry")
    report.expect(pitch.kernel.points.keys.allSatisfy {
        $0 == Int(scene.note.tick) || $0 == Int(scene.noteEnd)
    } && pitch.kernel.points[Int(scene.note.tick)] == 0
        && document.lanePoints(track: scene.note.track, lane: .pitchBend)
            .filter { $0.tick >= scene.note.tick && $0.tick < scene.noteEnd }
            .allSatisfy { $0.value == 0 },
    cppID: pitchID, message: "the pitch reset zeroes the curve over the note span")
    report.expect(pitchBendLaneHasPoint(document, track: scene.note.track,
                                        lane: .pitchBend, tick: scene.noteEnd,
                                        value: pitchEnd),
                  cppID: pitchID, message: "the pitch reset restores the note-off value")
    report.expect(presenter.isOpen, cppID: pitchID,
                  message: "the pitch reset keeps the editor open")
    let pitchUndone = document.history.undoDocument()
    presenter.documentDidChange()
    report.expect(pitchUndone && coreTimeBytes(document) == pitchDrawn
                  && presenter.isOpen && pitch.kernel.points.values.contains { $0 != 0 },
                  cppID: pitchID, message: "undoing the pitch reset restores the drawn curve bytes")
}

@MainActor
private func pitchBendFineRampPredicates(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PitchBendEditingTest::fineGridRamp"
    guard let scene = pitchBendCheckScene(report, cppID: id, session: session) else { return }
    defer { scene.presenter.cancelAndClose() }
    let document = session.document
    let before = coreTimeBytes(document)
    let index = document.history.undoIndex
    pitchBendStroke(scene.presenter.pitchGraph(), x0f: 0.10, y0f: 0.85,
                    x1f: 0.90, y1f: 0.15, modifiers: 0x0800_0000)
    let interior = document.lanePoints(track: scene.note.track, lane: .pitchBend)
        .filter { $0.tick > scene.note.tick && $0.tick < scene.noteEnd }
    report.expect(document.history.undoIndex == index + 1 && interior.count >= 3,
                  cppID: id, message: "an Alt drag commits a fine-grid ramp")
    let fine = session.grid.fineGridTicks(camera: session.camera)
    report.expect(zip(interior, interior.dropFirst()).allSatisfy {
        $1.tick > $0.tick && $1.tick - $0.tick <= fine
    }, cppID: id, message: "fine-grid ramp spacing never exceeds the fine stride")
    report.expect(zip(interior, interior.dropFirst()).allSatisfy { $1.value > $0.value },
                  cppID: id, message: "the Alt ramp rises monotonically")
    report.expect(document.history.undoDocument() && coreTimeBytes(document) == before
                  && scene.presenter.isOpen, cppID: id,
                  message: "undoing the Alt ramp restores the exact prior song bytes with the editor open")

    let activeID = "swiftcore/PitchBendControllerTest::activeBendRangeDescription"
    let service = ProjectService()
    let synthetic = pitchBendSyntheticSession(session, service: service)
    defer { withExtendedLifetime(service) {} }
    guard let active = pitchBendCheckScene(report, cppID: activeID,
                                           session: synthetic) else { return }
    defer { active.presenter.cancelAndClose() }
    active.presenter.cancelAndClose()
    synthetic.document.writeLane(track: active.note.track, lane: .controller(0x14),
                                 from: active.note.tick, through: active.note.tick,
                                 points: [LaneWrite(tick: active.note.tick, value: 12)])
    report.expect(active.presenter.openSelected() && active.presenter.bendRange == 12,
                  cppID: activeID, message: "the open editor reads the active BENDR value")
    report.expect(active.presenter.description.contains("12 semitones"), cppID: activeID,
                  message: "the description reflects the active BENDR semitones")
}

@MainActor
private func pitchBendSetterPredicates(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PitchBendControllerTest::directControllerSetters"
    guard let scene = pitchBendCheckScene(report, cppID: id, session: session) else { return }
    defer { scene.presenter.cancelAndClose() }
    let presenter = scene.presenter
    let document = session.document
    let baseline = coreTimeBytes(document)
    let index = document.history.undoIndex
    let oldRange = presenter.bendRange
    let oldSpeed = presenter.lfoSpeed
    let graph = presenter.pitchGraph()
    let oldBendEnd = document.lanePoints(track: scene.note.track, lane: .controller(0x14))
        .last(where: { $0.tick <= scene.noteEnd })?.value ?? oldRange
    let oldSpeedEnd = document.lanePoints(track: scene.note.track, lane: .controller(0x15))
        .last(where: { $0.tick <= scene.noteEnd })?.value ?? oldSpeed
    presenter.setBendRange(value: oldRange + 1)
    report.expect(document.history.undoIndex == index + 1,
                  cppID: id, message: "scrubbing the bend range pushes exactly one history entry")
    report.expect(presenter.bendRange == oldRange + 1
                  && pitchBendLaneHasPoint(document, track: scene.note.track,
                                            lane: .controller(0x14), tick: scene.note.tick,
                                            value: oldRange + 1),
                  cppID: id, message: "a pointer scrub raises BENDR by one")
    report.expect(pitchBendLaneHasPoint(document, track: scene.note.track,
                                        lane: .controller(0x14), tick: scene.noteEnd,
                                        value: oldBendEnd),
                  cppID: id, message: "the scrubbed BENDR write is note-bounded")
    let afterBend = coreTimeBytes(document)
    presenter.setLfoSpeed(value: oldSpeed + 1)
    report.expect(document.history.undoIndex == index + 2,
                  cppID: id, message: "shift-scrubbing the LFO field pushes exactly one history entry")
    report.expect(presenter.lfoSpeed == oldSpeed + 1
                  && pitchBendLaneHasPoint(document, track: scene.note.track,
                                            lane: .controller(0x15), tick: scene.note.tick,
                                            value: oldSpeed + 1),
                  cppID: id, message: "a shift scrub raises LFO speed by one")
    report.expect(pitchBendLaneHasPoint(document, track: scene.note.track,
                                        lane: .controller(0x15), tick: scene.noteEnd,
                                        value: oldSpeedEnd),
                  cppID: id, message: "the scrubbed LFO write is note-bounded")
    presenter.documentDidChange()
    report.expect(presenter.isOpen && presenter.pitchGraph() === graph,
                  cppID: id, message: "controller edits and refresh keep the same editor open")
    let firstUndone = document.history.undoDocument()
    presenter.documentDidChange()
    report.expect(firstUndone && document.history.undoIndex == index + 1
                  && coreTimeBytes(document) == afterBend && presenter.isOpen,
                  cppID: id, message: "the first controller undo restores the bend-only bytes with the editor open")
    let secondUndone = document.history.undoDocument()
    presenter.documentDidChange()
    report.expect(secondUndone && document.history.undoIndex == index
                  && coreTimeBytes(document) == baseline && presenter.isOpen,
                  cppID: id, message: "the second controller undo restores the baseline bytes with the editor open")
}
