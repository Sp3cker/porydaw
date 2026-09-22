import Foundation
@testable import PorydawApp
import PorydawCore

// Existing scenarios paired with velocitydetentdragging.cpp.
// Entry order remains in VelocityPageChecks.swift.

@MainActor
func drawerVelocityFrozenGesturePolicy(_ report: CheckReport, session: DocumentSession,
                                 service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityGestureID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    report.expectEqual(3, fixture.handles.count, cppID: drawerVelocityProjectionID,
                       what: "every note of the primary track publishes one handle")
    guard let firstHandle = fixture.handle(notes[0]),
          let thirdHandle = fixture.handle(notes[2])
    else {
        report.fail(drawerVelocityProjectionID, "the fixture's notes have no published handles")
        return
    }
    let openingMap = VelocityMap(voiceKind: .square1)
    report.expect(!firstHandle.selected, cppID: drawerVelocityProjectionID,
                  message: "a fresh selection publishes no selected handle")
    report.expectEqual(openingMap.level(of: Int(notes[0].velocity)) ?? -1, firstHandle.level,
                       cppID: drawerVelocityProjectionID,
                       what: "an intrinsic handle publishes the level of its displayed value")
    report.expect(abs(firstHandle.x - page.axisModel.geometry.labelWidth - 56) < 1.0
                      || firstHandle.x <= 400, cppID: drawerVelocityProjectionID,
                  message: "the handle's x is a plot-local camera projection")
    report.expect(fixture.handle(notes[0])!.y < firstHandle.hitRadius * 2
                      || firstHandle.y > 0, cppID: drawerVelocityProjectionID,
                  message: "the handle publishes a drawn y inside the body")

    var axisGeometry = page.axisModel.geometry
    let axis = VelocityAxisModel(map: VelocityMap(voiceKind: .unresolved), geometry: axisGeometry)
    var gesture = VelocityEditGesture(
        revision: fixture.document.revision, track: 0,
        notes: [
            VelocityFrozenNote(noteID: NoteID(1), tick: 0, duration: 24, pitch: 60, velocity: 10,
                               map: VelocityMap(voiceKind: .unresolved), exactOrigin: 10),
            VelocityFrozenNote(noteID: NoteID(2), tick: 24, duration: 24, pitch: 67, velocity: 120,
                               map: VelocityMap(voiceKind: .unresolved), exactOrigin: 120),
        ],
        axis: axis, detentUnlock: false, activationDistance: 1, pressX: 0,
        pressY: axis.velocityToY(10))
    VelocityGesturePolicy.applyRelative(&gesture, y: axis.velocityToY(10) - 0.5)
    report.expect(!gesture.relativeActivated && gesture.preview.isEmpty, cppID: drawerVelocityGestureID,
                  message: "a drag inside the activation distance previews nothing")
    VelocityGesturePolicy.applyRelative(&gesture, y: axis.velocityToY(30))
    report.expect(gesture.relativeActivated, cppID: drawerVelocityGestureID,
                  message: "leaving the activation distance arms the relative drag")
    report.expectEqual(30, Int(gesture.preview[NoteID(1)] ?? 0), cppID: drawerVelocityGestureID,
                       what: "the low note takes the whole delta")
    report.expectEqual(127, Int(gesture.preview[NoteID(2)] ?? 0), cppID: drawerVelocityGestureID,
                       what: "the high note clamps to the maximum instead of wrapping")
    report.expectEqual(2, VelocityGesturePolicy.updates(gesture).count, cppID: drawerVelocityGestureID,
                       what: "the commit payload carries one update per frozen note")

    let psgMap = VelocityMap(voiceKind: .square1)
    axisGeometry.height = 120
    let psgAxis = VelocityAxisModel(map: psgMap, geometry: axisGeometry, activeValues: [60, 76])
    var psgGesture = VelocityEditGesture(
        revision: 1, track: 0,
        notes: [
            VelocityFrozenNote(noteID: NoteID(3), tick: 0, duration: 24, pitch: 60, velocity: 60,
                               map: psgMap, exactOrigin: 60),
            VelocityFrozenNote(noteID: NoteID(4), tick: 24, duration: 24, pitch: 67, velocity: 76,
                               map: psgMap, exactOrigin: 76),
        ],
        axis: psgAxis, detentUnlock: false, activationDistance: 1, pressX: 0,
        pressY: psgAxis.levelToY(7))
    VelocityGesturePolicy.applyRelative(&psgGesture, y: psgAxis.levelToY(9))
    report.expectEqual(Int(psgMap.representative(9)), Int(psgGesture.preview[NoteID(3)] ?? 0),
                       cppID: drawerVelocityGestureID, what: "the first level follows the level delta")
    report.expectEqual(Int(psgMap.representative(11)), Int(psgGesture.preview[NoteID(4)] ?? 0),
                       cppID: drawerVelocityGestureID, what: "the second level keeps its own offset")
    report.expectEqual(127,
                       Int(VelocityGesturePolicy.resolvedVelocity(axis: psgAxis, noteMap: psgMap,
                                                                  detentUnlock: true, y: 0)),
                       cppID: drawerVelocityGestureID,
                       what: "the detent unlock takes exact MIDI velocity")
    report.expectEqual(Int(psgMap.canonicalize(76)),
                       Int(VelocityGesturePolicy.resolvedVelocity(axis: psgAxis, noteMap: psgMap,
                                                                  detentUnlock: false,
                                                                  y: psgAxis.levelToY(9))),
                       cppID: drawerVelocityGestureID,
                       what: "a locked intrinsic drag canonicalizes onto the note's own map")

    let frozen = [
        VelocityFrozenNote(noteID: NoteID(5), tick: 0, duration: 24, pitch: 60, velocity: 40,
                           map: VelocityMap(voiceKind: .unresolved), exactOrigin: 40),
        VelocityFrozenNote(noteID: NoteID(6), tick: 48, duration: 24, pitch: 60, velocity: 40,
                           map: VelocityMap(voiceKind: .unresolved), exactOrigin: 40),
    ]
    let candidates = [(note: frozen[0], x: 10.0), (note: frozen[1], x: 90.0)]
    let painted = VelocityGesturePolicy.paint(
        axis: axis, detentUnlock: false, candidates: candidates, from: (0, 100), to: (95, 40),
        hitRadius: 5)
    report.expectEqual(2, painted.count, cppID: drawerVelocityGestureID,
                       what: "the sweep covers every node the column reaches")
    report.expect(painted[0].velocity < painted[1].velocity, cppID: drawerVelocityGestureID,
                  message: "the painted ramp follows the swept line's own direction")
    let partial = VelocityGesturePolicy.paint(
        axis: axis, detentUnlock: false, candidates: candidates, from: (0, 100), to: (50, 40),
        hitRadius: 5)
    report.expectEqual(1, partial.count, cppID: drawerVelocityGestureID,
                       what: "a sweep that stops short leaves the far node alone")
    let singleColumn = VelocityGesturePolicy.paint(
        axis: axis, detentUnlock: false, candidates: candidates, from: (10, 100), to: (10, 60),
        hitRadius: 5)
    report.expectEqual(1, singleColumn.count, cppID: drawerVelocityGestureID,
                       what: "a stationary paint only takes the nodes in its own column")

    let midpoint = VelocityFrozenNote(noteID: NoteID(7), tick: 24, duration: 24, pitch: 60,
                                      velocity: 40,
                                      map: VelocityMap(voiceKind: .unresolved), exactOrigin: 40)
    var ramp = VelocityEditGesture(
        revision: 1, track: 0, notes: frozen + [midpoint], axis: axis,
        detentUnlock: false, activationDistance: 1, pressX: 10, pressY: axis.velocityToY(100))
    VelocityGesturePolicy.applyRamp(&ramp, x: 50, y: axis.velocityToY(50), hitRadius: 5) { note in
        note.tick == 0 ? 10 : note.tick == 24 ? 30 : 90
    }
    report.expectEqual(100, Int(ramp.preview[NoteID(5)] ?? 0), cppID: drawerVelocityGestureID,
                       what: "the note at the press position keeps the press velocity")
    report.expectEqual(75, Int(ramp.preview[NoteID(7)] ?? 0), cppID: drawerVelocityGestureID,
                       what: "a note inside the ramp span takes the swept line's value")
    report.expectEqual(40, Int(ramp.preview[NoteID(6)] ?? 0), cppID: drawerVelocityGestureID,
                       what: "a note outside the ramp span keeps its captured velocity")
    // The commit payload is what the preview really changes: a gesture whose
    // preview resolves every note back to the value frozen at gesture start
    // makes no history entry, and a preview that moves one note commits exactly
    // that note.
    var flatState = VelocityEditGesture(
        revision: 1, track: 0, notes: frozen, axis: axis, detentUnlock: false,
        activationDistance: 1, pressX: 10, pressY: axis.velocityToY(40))
    flatState.preview = Dictionary(uniqueKeysWithValues: frozen.map { ($0.noteID, $0.velocity) })
    report.expect(VelocityGesturePolicy.updates(flatState).isEmpty, cppID: drawerVelocityGestureID,
                  message: "a preview that matches the captured values commits nothing")
    var movedState = flatState
    let movedNote = frozen[0]
    movedState.preview[movedNote.noteID] = movedNote.velocity + 7
    let moved = VelocityGesturePolicy.updates(movedState)
    report.expect(moved.count == 1 && moved[0].noteID == movedNote.noteID
                  && moved[0].velocity == Int(movedNote.velocity) + 7,
                  cppID: drawerVelocityGestureID,
                  message: "only the values that differ from the captured ones are committed")
    report.expect(abs(velocityRampValue(at: 20, x0: 0, y0: 0, x1: 40, y1: 40) - 20) < 1e-9,
                  cppID: drawerVelocityGestureID, message: "the ramp interpolates linearly")
    report.expect(abs(velocityRampValue(at: 5, x0: 10, y0: 3, x1: 10, y1: 9) - 9) < 1e-9,
                  cppID: drawerVelocityGestureID, message: "a vertical span resolves to the near endpoint")
    report.expect(thirdHandle.hitRadius > 0, cppID: drawerVelocityGestureID,
                  message: "the published hit radius is font-relative and positive")

    let decoded = DrawerPointerInput(
        x: 3, y: 4, qtButton: 8, qtButtons: 1 | 4 | 8,
        qtModifiers: DrawerModifiers.shiftBit | DrawerModifiers.controlBit,
        phase: .move)
    report.expect(decoded.changedButton == .other(8)
                      && decoded.heldButtons.contains(.primary)
                      && decoded.heldButtons.contains(.middle)
                      && decoded.heldButtons.contains(.other(8)),
                  cppID: drawerVelocityGestureID,
                  message: "the Qt seam keeps changed and held buttons distinct, including unknown bits")
    report.expect(decoded.modifiers.shift && decoded.modifiers.control
                      && decoded.modifiers.isExact(shift: true, control: true),
                  cppID: drawerVelocityGestureID,
                  message: "the Qt seam decodes exact Control+Shift membership")
    let extraQtNoise = DrawerModifiers(qtModifiers: DrawerModifiers.controlBit | 0x01)
    let disqualified = DrawerModifiers(
        qtModifiers: DrawerModifiers.controlBit | DrawerModifiers.altBit)
    report.expect(extraQtNoise.isExact(control: true)
                      && !disqualified.isExact(control: true),
                  cppID: drawerVelocityGestureID,
                  message: "non-shortcut Qt bits are ignored while Alt disqualifies exact Control")
    report.expect(!page.pointerPress(x: 10, y: 10, surface: 99, button: 1, modifiers: 0)
                      && !page.pointerPress(x: 10, y: 10, surface: 1,
                                            button: 8, modifiers: 0),
                  cppID: drawerVelocityGestureID,
                  message: "unknown surfaces and buttons remain unconsumed at the Qt adapter")
}
