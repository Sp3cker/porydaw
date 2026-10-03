import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func pitchBendParityPredicates(_ report: CheckReport, suite: DocumentSession) {
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

/// An off-grid note's popup rules follow the shared lattice, not its offset from the note.
@MainActor
func pitchBendGridRulePredicates(_ report: CheckReport, suite: DocumentSession) {
    let id = "swiftcore/PitchBendEditingTest::sharedGridSnap"
    let service = ProjectService()
    let session = pitchBendSyntheticSession(suite, service: service)
    defer { withExtendedLifetime(service) {} }
    session.grid.setSelection(.musical(4))
    guard
        let notes = try? session.document.addNotes([
            NewNote(track: 0, tick: 290, pitch: 61, duration: 200, velocity: 100)
        ]), let note = notes.first
    else {
        report.fail(id, "the off-grid note fixture exists")
        return
    }
    session.selectPrimaryTrack(0)
    session.setSelectedNotes([note])
    let grid = PianoGrid(session: session)
    let presenter = PitchBendPresenter(session: session, grid: grid, palette: grid.palette)
    guard presenter.openSelected() else {
        report.fail(id, "an off-grid note opens its editor")
        return
    }
    defer { presenter.cancelAndClose() }
    let step = Int(session.grid.snapTicksAt(290, camera: session.camera))
    let expected = Array(stride(from: (290 / step + 1) * step, to: 490, by: step))
    report.expect(
        expected.count > 1, cppID: id,
        message: "the off-grid note spans several snap steps")
    report.expectEqual(
        expected: expected, actual: presenter.pitchGraph().kernel.gridTicks,
        cppID: id,
        what: "an off-grid note's popup rules sit on every shared snap step")
}

@MainActor
func pitchBendControllerPredicates(_ report: CheckReport, session: DocumentSession) {
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
func pitchBendResetPredicates(_ report: CheckReport, session: DocumentSession) {
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
func pitchBendFineRampPredicates(_ report: CheckReport, session: DocumentSession) {
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
func pitchBendSetterPredicates(_ report: CheckReport, session: DocumentSession) {
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
