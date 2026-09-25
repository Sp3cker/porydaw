import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore

let drawerVelocityPaintID = "swiftcore/VelocityPaintDetent::paintCommitsOnce"
let drawerVelocityRampID = "swiftcore/VelocityPaintDetent::rampCommitsOnce"
let drawerVelocityRulerUnlockID = "swiftcore/VelocityPaintDetent::rulerUnlockKeepsRawVelocity"
let drawerVelocityLockedPaintID = "swiftcore/VelocityPaintDetent::lockedPaintUsesDetents"
let drawerVelocityUnlockedPaintID = "swiftcore/VelocityPaintDetent::unlockedPaintKeepsRawVelocities"
let drawerVelocityLateUnlockID = "swiftcore/VelocityPaintDetent::lateUnlockKeepsGestureSnapped"
let drawerVelocityUnlockedRelativeID = "swiftcore/VelocityPaintDetent::unlockedRelativeKeepsOffsets"
let drawerVelocityUnlockedRampID = "swiftcore/VelocityPaintDetent::unlockedRampInterpolates"

@MainActor
private func drawerVelocityPaintAddNote(_ report: CheckReport, cppID: String, document: SongDocument, page: VelocityPage, tick: Tick, pitch: UInt8, duration: Tick, velocity: UInt8) -> Note? {
    do {
        let ids = try document.addNotes([NewNote(track: 0, tick: tick, pitch: pitch, duration: duration, velocity: velocity)])
        guard let id = ids.first, let note = document.note(id) else {
            report.fail(cppID, "the added note published no identity")
            return nil
        }
        page.refreshFromDocument()
        return note
    } catch {
        report.fail(cppID, "the added note was rejected")
        return nil
    }
}

@MainActor
private func drawerVelocityPaintSetOrigins(_ document: SongDocument, _ page: VelocityPage, _ first: Note, _ firstVelocity: UInt8, _ second: Note, _ secondVelocity: UInt8) {
    _ = document.setVelocities([NoteVelocity(noteID: first.id, velocity: Int(firstVelocity)), NoteVelocity(noteID: second.id, velocity: Int(secondVelocity))], expectedRevision: document.revision)
    page.refreshFromDocument()
}

@MainActor
func drawerVelocityPaintCommitsOnce(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityPaintID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[2].id])
    page.refreshFromDocument()
    page.setUseDetents(enabled: false)
    report.expectEqual(expected: VelocityAxisModel.Mode.continuous.rawValue, actual: page.axisMode, cppID: drawerVelocityPaintID, what: "the mixed square and noise selection presents the continuous ruler")
    guard let firstHandle = fixture.handle(notes[0]), let lastHandle = fixture.handle(notes[2]) else {
        report.fail(drawerVelocityPaintID, "the mixed pair published no handles")
        return
    }
    let pressX = firstHandle.x
    let pressY = page.axisModel.velocityToY(37)
    let endX = lastHandle.x
    let endY = page.axisModel.velocityToY(91)
    report.expect(pressX != endX, cppID: drawerVelocityPaintID, message: "the paint endpoints span two note columns")
    let baseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: pressX, y: pressY, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: endX, y: endY, buttons: 1)
    report.expectEqual(expected: 37, actual: Int(page.frozenPreview[notes[0].id] ?? 0), cppID: drawerVelocityPaintID, what: "the press column previews its literal paint velocity")
    report.expectEqual(expected: 91, actual: Int(page.frozenPreview[notes[2].id] ?? 0), cppID: drawerVelocityPaintID, what: "the release column previews its literal paint velocity")
    report.expect(page.frozenPreview[notes[1].id] == nil, cppID: drawerVelocityPaintID, message: "the unselected note previews nothing")
    report.expectEqual(expected: baseline.revision, actual: document.revision, cppID: drawerVelocityPaintID, what: "the deferred paint stages no revision before release")
    report.expectEqual(expected: baseline.identity, actual: document.history.currentIdentity, cppID: drawerVelocityPaintID, what: "the deferred paint stages no history entry before release")
    report.expectEqual(expected: Int(notes[0].velocity), actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityPaintID, what: "the document keeps the first velocity during preview")
    report.expectEqual(expected: Int(notes[2].velocity), actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityPaintID, what: "the document keeps the last velocity during preview")
    report.expectEqual(expected: Int(notes[1].velocity), actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityPaintID, what: "the document keeps the unselected velocity during preview")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id], cppID: drawerVelocityPaintID, message: "the preview keeps the paint selection")
    _ = page.pointerRelease(x: endX, y: endY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityPaintID, what: "one paint release commits one revision")
    report.expect(document.history.currentIdentity != baseline.identity, cppID: drawerVelocityPaintID, message: "one paint release makes one history entry")
    report.expect(document.history.canUndo, cppID: drawerVelocityPaintID, message: "the paint entry is undoable")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityPaintID, message: "the paint release clears its preview")
    report.expectEqual(expected: 37, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityPaintID, what: "the release commits the first literal velocity")
    report.expectEqual(expected: 91, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityPaintID, what: "the release commits the last literal velocity")
    report.expectEqual(expected: Int(notes[1].velocity), actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityPaintID, what: "the release leaves the unselected note alone")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id], cppID: drawerVelocityPaintID, message: "the release keeps the paint selection")
}

@MainActor
func drawerVelocityRampCommitsOnce(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let shift = 0x0200_0000
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityRampID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    guard let middle = drawerVelocityPaintAddNote(report, cppID: drawerVelocityRampID, document: document, page: page, tick: 48, pitch: 60, duration: 12, velocity: 56) else {
        return
    }
    report.expectEqual(expected: 48, actual: Int(middle.tick), cppID: drawerVelocityRampID, what: "the added middle note resolves at its placed tick")
    report.expectEqual(expected: 60, actual: Int(middle.pitch), cppID: drawerVelocityRampID, what: "the added middle note resolves at its placed pitch")
    fixture.session.setSelectedNotes([notes[0].id, middle.id, notes[2].id])
    page.setUseDetents(enabled: false)
    page.refreshFromDocument()
    report.expectEqual(expected: VelocityAxisModel.Mode.continuous.rawValue, actual: page.axisMode, cppID: drawerVelocityRampID, what: "the mixed ramp selection presents the continuous ruler")
    guard let firstHandle = fixture.handle(notes[0]), let middleHandle = fixture.handle(middle), let lastHandle = fixture.handle(notes[2]) else {
        report.fail(drawerVelocityRampID, "the ramp triple published no handles")
        return
    }
    let pressX = firstHandle.x
    let pressY = page.axisModel.velocityToY(37)
    let endX = lastHandle.x
    let endY = page.axisModel.velocityToY(93)
    report.expect(pressX != endX, cppID: drawerVelocityRampID, message: "the ramp endpoints span two note columns")
    report.expect(middleHandle.x > min(pressX, endX) && middleHandle.x < max(pressX, endX), cppID: drawerVelocityRampID, message: "the middle note sits inside the swept span")
    let baseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: pressX, y: pressY, surface: 1, button: 1, modifiers: shift)
    let middleExpected = page.axisModel.yToVelocity(velocityRampValue(at: middleHandle.x, x0: pressX, y0: pressY, x1: endX, y1: endY))
    _ = page.pointerMove(x: endX, y: endY, buttons: 1)
    report.expectEqual(expected: 37, actual: Int(page.frozenPreview[notes[0].id] ?? 0), cppID: drawerVelocityRampID, what: "the ramp press endpoint previews its literal velocity")
    report.expectEqual(expected: middleExpected, actual: Int(page.frozenPreview[middle.id] ?? 0), cppID: drawerVelocityRampID, what: "the halfway middle note previews the interpolated velocity")
    report.expectEqual(expected: 93, actual: Int(page.frozenPreview[notes[2].id] ?? 0), cppID: drawerVelocityRampID, what: "the ramp release endpoint previews its literal velocity")
    report.expect(page.frozenPreview[notes[1].id] == nil, cppID: drawerVelocityRampID, message: "the note outside the selection previews nothing")
    report.expectEqual(expected: baseline.revision, actual: document.revision, cppID: drawerVelocityRampID, what: "the deferred ramp stages no revision before release")
    report.expectEqual(expected: baseline.identity, actual: document.history.currentIdentity, cppID: drawerVelocityRampID, what: "the deferred ramp stages no history entry before release")
    report.expectEqual(expected: Int(notes[0].velocity), actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the document keeps the first velocity during preview")
    report.expectEqual(expected: 56, actual: Int(document.note(middle.id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the document keeps the middle velocity during preview")
    report.expectEqual(expected: Int(notes[1].velocity), actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the document keeps the outside velocity during preview")
    report.expectEqual(expected: Int(notes[2].velocity), actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the document keeps the last velocity during preview")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, middle.id, notes[2].id], cppID: drawerVelocityRampID, message: "the preview keeps the ramp selection")
    _ = page.pointerRelease(x: endX, y: endY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityRampID, what: "one ramp release commits one revision")
    report.expect(document.history.currentIdentity != baseline.identity, cppID: drawerVelocityRampID, message: "one ramp release makes one history entry")
    report.expect(document.history.canUndo, cppID: drawerVelocityRampID, message: "the ramp entry is undoable")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityRampID, message: "the ramp release clears its preview")
    report.expectEqual(expected: 37, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the release commits the first ramp velocity")
    report.expectEqual(expected: middleExpected, actual: Int(document.note(middle.id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the release commits the interpolated middle velocity")
    report.expectEqual(expected: 93, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the release commits the last ramp velocity")
    report.expectEqual(expected: Int(notes[1].velocity), actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the release leaves the outside note alone")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, middle.id, notes[2].id], cppID: drawerVelocityRampID, message: "the release keeps the ramp selection")
}

@MainActor
func drawerVelocityRulerUnlockKeepsRaw(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let unlock = KeybindingRegistry().modifierBinding("velocity.detent_unlock")
    guard unlock != 0 else {
        report.fail(drawerVelocityRulerUnlockID, "the detent unlock hold resolved to no modifier")
        return
    }
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityRulerUnlockID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    let rulerX = 10.0
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    report.expectEqual(expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode, cppID: drawerVelocityRulerUnlockID, what: "the square pair presents the intrinsic ruler")
    report.expect(page.detentsAvailable && page.detentsEnabled, cppID: drawerVelocityRulerUnlockID, message: "the square context offers the enabled detent control")
    let rulerY = page.axisModel.velocityToY(73)
    drawerVelocityPaintSetOrigins(document, page, notes[0], 33, notes[1], 87)
    var baseline = DocumentSnapshot(document)
    report.expect(page.pointerPress(x: rulerX, y: rulerY, surface: 0, button: 1, modifiers: unlock), cppID: drawerVelocityRulerUnlockID, message: "the unlocked ruler consumes its own press")
    _ = page.pointerRelease(x: rulerX, y: rulerY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityRulerUnlockID, what: "one unlocked ruler click makes one revision")
    report.expect(document.history.currentIdentity != baseline.identity, cppID: drawerVelocityRulerUnlockID, message: "one unlocked ruler click makes one history entry")
    report.expectEqual(expected: 73, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRulerUnlockID, what: "the modifier-unlocked square click keeps the raw velocity")
    report.expectEqual(expected: 73, actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRulerUnlockID, what: "the modifier-unlocked square click sets every selected note raw")
    report.expectEqual(expected: Int(notes[2].velocity), actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRulerUnlockID, what: "the ruler click leaves the unselected note alone")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityRulerUnlockID, message: "the ruler click keeps its selection")
    _ = page.pointerRelease(x: rulerX, y: rulerY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityRulerUnlockID, what: "the bare release after the captured unlock writes nothing more")
    page.setUseDetents(enabled: false)
    drawerVelocityPaintSetOrigins(document, page, notes[0], 33, notes[1], 87)
    baseline = DocumentSnapshot(document)
    report.expect(page.pointerPress(x: rulerX, y: rulerY, surface: 0, button: 1, modifiers: 0), cppID: drawerVelocityRulerUnlockID, message: "the detents-disabled ruler consumes its own press")
    _ = page.pointerRelease(x: rulerX, y: rulerY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityRulerUnlockID, what: "one detents-disabled ruler click makes one revision")
    report.expectEqual(expected: 73, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRulerUnlockID, what: "the detents-disabled square click keeps the raw velocity")
    report.expectEqual(expected: 73, actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRulerUnlockID, what: "the detents-disabled square click sets every selected note raw")
    page.setUseDetents(enabled: true)
    guard let secondNoise = drawerVelocityPaintAddNote(report, cppID: drawerVelocityRulerUnlockID, document: document, page: page, tick: 120, pitch: 60, duration: 12, velocity: 50) else {
        return
    }
    fixture.session.setSelectedNotes([notes[2].id, secondNoise.id])
    page.refreshFromDocument()
    report.expectEqual(expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode, cppID: drawerVelocityRulerUnlockID, what: "the noise pair presents the intrinsic ruler")
    drawerVelocityPaintSetOrigins(document, page, notes[2], 33, secondNoise, 87)
    baseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: rulerX, y: rulerY, surface: 0, button: 1, modifiers: unlock)
    _ = page.pointerRelease(x: rulerX, y: rulerY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityRulerUnlockID, what: "one unlocked noise ruler click makes one revision")
    report.expectEqual(expected: 73, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRulerUnlockID, what: "the modifier-unlocked noise click keeps the raw velocity")
    report.expectEqual(expected: 73, actual: Int(document.note(secondNoise.id)?.velocity ?? 0), cppID: drawerVelocityRulerUnlockID, what: "the modifier-unlocked noise click sets every selected note raw")
    page.setUseDetents(enabled: false)
    drawerVelocityPaintSetOrigins(document, page, notes[2], 33, secondNoise, 87)
    baseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: rulerX, y: rulerY, surface: 0, button: 1, modifiers: 0)
    _ = page.pointerRelease(x: rulerX, y: rulerY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityRulerUnlockID, what: "one detents-disabled noise ruler click makes one revision")
    report.expectEqual(expected: 73, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRulerUnlockID, what: "the detents-disabled noise click keeps the raw velocity")
    report.expectEqual(expected: 73, actual: Int(document.note(secondNoise.id)?.velocity ?? 0), cppID: drawerVelocityRulerUnlockID, what: "the detents-disabled noise click sets every selected note raw")
    page.setUseDetents(enabled: true)
    let waveMap = VelocityMap(voiceKind: .wave)
    let waveAxis = VelocityAxisModel(map: waveMap, geometry: page.axisModel.geometry)
    report.expect(Int(VelocityGesturePolicy.resolvedVelocity(axis: waveAxis, noteMap: waveMap, detentUnlock: true, y: waveAxis.velocityToY(73))) == 73 && Int(VelocityGesturePolicy.resolvedVelocity(axis: waveAxis, noteMap: waveMap, detentUnlock: false, y: waveAxis.velocityToY(73))) == 64, cppID: drawerVelocityRulerUnlockID, message: "the unlock bypasses the wave detent the locked ruler canonicalizes onto")
}

@MainActor
func drawerVelocityLockedPaintUsesDetents(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityLockedPaintID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    report.expectEqual(expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode, cppID: drawerVelocityLockedPaintID, what: "the square pair presents the intrinsic ruler")
    guard let firstHandle = fixture.handle(notes[0]), let secondHandle = fixture.handle(notes[1]) else {
        report.fail(drawerVelocityLockedPaintID, "the square pair published no handles")
        return
    }
    let pressY = page.axisModel.velocityToY(73)
    var baseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: firstHandle.x, y: pressY, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: secondHandle.x, y: pressY, buttons: 1)
    report.expectEqual(expected: 76, actual: Int(page.frozenPreview[notes[0].id] ?? 0), cppID: drawerVelocityLockedPaintID, what: "the locked square sweep previews the detent above raw 73")
    report.expectEqual(expected: 76, actual: Int(page.frozenPreview[notes[1].id] ?? 0), cppID: drawerVelocityLockedPaintID, what: "the locked square sweep snaps every selected note")
    report.expect(page.frozenPreview[notes[2].id] == nil, cppID: drawerVelocityLockedPaintID, message: "the unselected note previews nothing")
    report.expectEqual(expected: baseline.revision, actual: document.revision, cppID: drawerVelocityLockedPaintID, what: "the deferred locked paint stages no revision before release")
    report.expectEqual(expected: baseline.identity, actual: document.history.currentIdentity, cppID: drawerVelocityLockedPaintID, what: "the deferred locked paint stages no history entry before release")
    _ = page.pointerRelease(x: secondHandle.x, y: pressY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityLockedPaintID, what: "one locked paint release commits one revision")
    report.expectEqual(expected: 76, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityLockedPaintID, what: "the release commits the square detent")
    report.expectEqual(expected: 76, actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityLockedPaintID, what: "the release commits the detent on every selected note")
    report.expectEqual(expected: Int(notes[2].velocity), actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityLockedPaintID, what: "the release leaves the unselected note alone")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityLockedPaintID, message: "the release keeps the paint selection")
    guard let secondNoise = drawerVelocityPaintAddNote(report, cppID: drawerVelocityLockedPaintID, document: document, page: page, tick: 120, pitch: 60, duration: 12, velocity: 50) else {
        return
    }
    fixture.session.setSelectedNotes([notes[2].id, secondNoise.id])
    page.refreshFromDocument()
    report.expectEqual(expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode, cppID: drawerVelocityLockedPaintID, what: "the noise pair presents the intrinsic ruler")
    guard let noiseHandle = fixture.handle(notes[2]), let noiseSecondHandle = fixture.handle(secondNoise) else {
        report.fail(drawerVelocityLockedPaintID, "the noise pair published no handles")
        return
    }
    baseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: noiseHandle.x, y: pressY, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: noiseSecondHandle.x, y: pressY, buttons: 1)
    report.expectEqual(expected: 76, actual: Int(page.frozenPreview[notes[2].id] ?? 0), cppID: drawerVelocityLockedPaintID, what: "the locked noise sweep previews the detent above raw 73")
    report.expectEqual(expected: 76, actual: Int(page.frozenPreview[secondNoise.id] ?? 0), cppID: drawerVelocityLockedPaintID, what: "the locked noise sweep snaps every selected note")
    report.expectEqual(expected: baseline.revision, actual: document.revision, cppID: drawerVelocityLockedPaintID, what: "the deferred noise paint stages no revision before release")
    _ = page.pointerRelease(x: noiseSecondHandle.x, y: pressY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityLockedPaintID, what: "one locked noise release commits one revision")
    report.expectEqual(expected: 76, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityLockedPaintID, what: "the release commits the noise detent")
    report.expectEqual(expected: 76, actual: Int(document.note(secondNoise.id)?.velocity ?? 0), cppID: drawerVelocityLockedPaintID, what: "the release commits the detent on every noise note")
    let waveMap = VelocityMap(voiceKind: .wave)
    let waveAxis = VelocityAxisModel(map: waveMap, geometry: page.axisModel.geometry)
    let waveFirst = VelocityFrozenNote(noteID: NoteID(101), tick: 0, duration: 24, pitch: 60, velocity: 60, map: waveMap, exactOrigin: 60)
    let waveSecond = VelocityFrozenNote(noteID: NoteID(102), tick: 24, duration: 24, pitch: 67, velocity: 76, map: waveMap, exactOrigin: 76)
    let painted = VelocityGesturePolicy.paint(axis: waveAxis, detentUnlock: false, candidates: [(note: waveFirst, x: 10), (note: waveSecond, x: 90)], from: (x: 10, y: waveAxis.velocityToY(73)), to: (x: 90, y: waveAxis.velocityToY(73)), hitRadius: 5)
    report.expectEqual(expected: 2, actual: painted.count, cppID: drawerVelocityLockedPaintID, what: "the locked wave sweep covers both columns")
    report.expect(painted.allSatisfy { $0.velocity == 64 }, cppID: drawerVelocityLockedPaintID, message: "the locked wave paint canonicalizes raw 73 onto its detent")
}

@MainActor
func drawerVelocityUnlockedPaintKeepsRaw(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let unlock = KeybindingRegistry().modifierBinding("velocity.detent_unlock")
    guard unlock != 0 else {
        report.fail(drawerVelocityUnlockedPaintID, "the detent unlock hold resolved to no modifier")
        return
    }
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityUnlockedPaintID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    report.expectEqual(expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode, cppID: drawerVelocityUnlockedPaintID, what: "the square pair presents the intrinsic ruler")
    guard let firstHandle = fixture.handle(notes[0]), let secondHandle = fixture.handle(notes[1]) else {
        report.fail(drawerVelocityUnlockedPaintID, "the square pair published no handles")
        return
    }
    let firstY = page.axisModel.velocityToY(37)
    let lastY = page.axisModel.velocityToY(91)
    var baseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: firstHandle.x, y: firstY, surface: 1, button: 1, modifiers: unlock)
    _ = page.pointerMove(x: secondHandle.x, y: lastY, buttons: 1)
    report.expectEqual(expected: 37, actual: Int(page.frozenPreview[notes[0].id] ?? 0), cppID: drawerVelocityUnlockedPaintID, what: "the unlocked square sweep previews the first raw velocity")
    report.expectEqual(expected: 91, actual: Int(page.frozenPreview[notes[1].id] ?? 0), cppID: drawerVelocityUnlockedPaintID, what: "the unlocked square sweep previews the last raw velocity")
    report.expect(page.frozenPreview[notes[2].id] == nil, cppID: drawerVelocityUnlockedPaintID, message: "the unselected note previews nothing")
    report.expectEqual(expected: baseline.revision, actual: document.revision, cppID: drawerVelocityUnlockedPaintID, what: "the deferred unlocked paint stages no revision before release")
    _ = page.pointerRelease(x: secondHandle.x, y: lastY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityUnlockedPaintID, what: "one unlocked paint release commits one revision")
    report.expect(document.history.canUndo, cppID: drawerVelocityUnlockedPaintID, message: "the unlocked paint entry is undoable")
    report.expectEqual(expected: 37, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedPaintID, what: "the release commits the first raw velocity")
    report.expectEqual(expected: 91, actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedPaintID, what: "the release commits the last raw velocity")
    report.expectEqual(expected: Int(notes[2].velocity), actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedPaintID, what: "the release leaves the unselected note alone")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityUnlockedPaintID, message: "the release keeps the paint selection")
    guard let secondNoise = drawerVelocityPaintAddNote(report, cppID: drawerVelocityUnlockedPaintID, document: document, page: page, tick: 120, pitch: 60, duration: 12, velocity: 50) else {
        return
    }
    fixture.session.setSelectedNotes([notes[2].id, secondNoise.id])
    page.refreshFromDocument()
    guard let noiseHandle = fixture.handle(notes[2]), let noiseSecondHandle = fixture.handle(secondNoise) else {
        report.fail(drawerVelocityUnlockedPaintID, "the noise pair published no handles")
        return
    }
    baseline = DocumentSnapshot(document)
    let noisePressX = noiseHandle.x - 40
    let noiseSlope = (lastY - firstY) / (noiseSecondHandle.x - noiseHandle.x)
    let noisePressY = firstY - noiseSlope * 40
    _ = page.pointerPress(x: noisePressX, y: noisePressY, surface: 1, button: 1, modifiers: unlock)
    _ = page.pointerMove(x: noiseSecondHandle.x, y: lastY, buttons: 1)
    report.expectEqual(expected: 37, actual: Int(page.frozenPreview[notes[2].id] ?? 0), cppID: drawerVelocityUnlockedPaintID, what: "the unlocked noise sweep previews the first raw velocity")
    report.expectEqual(expected: 91, actual: Int(page.frozenPreview[secondNoise.id] ?? 0), cppID: drawerVelocityUnlockedPaintID, what: "the unlocked noise sweep previews the last raw velocity")
    report.expectEqual(expected: baseline.revision, actual: document.revision, cppID: drawerVelocityUnlockedPaintID, what: "the deferred noise paint stages no revision before release")
    _ = page.pointerRelease(x: noiseSecondHandle.x, y: lastY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityUnlockedPaintID, what: "one unlocked noise release commits one revision")
    report.expectEqual(expected: 37, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedPaintID, what: "the release commits the first noise raw velocity")
    report.expectEqual(expected: 91, actual: Int(document.note(secondNoise.id)?.velocity ?? 0), cppID: drawerVelocityUnlockedPaintID, what: "the release commits the last noise raw velocity")
    let waveMap = VelocityMap(voiceKind: .wave)
    let waveAxis = VelocityAxisModel(map: waveMap, geometry: page.axisModel.geometry)
    let waveFirst = VelocityFrozenNote(noteID: NoteID(103), tick: 0, duration: 24, pitch: 60, velocity: 60, map: waveMap, exactOrigin: 60)
    let waveSecond = VelocityFrozenNote(noteID: NoteID(104), tick: 24, duration: 24, pitch: 67, velocity: 76, map: waveMap, exactOrigin: 76)
    let painted = VelocityGesturePolicy.paint(axis: waveAxis, detentUnlock: true, candidates: [(note: waveFirst, x: 10), (note: waveSecond, x: 90)], from: (x: 10, y: waveAxis.velocityToY(37)), to: (x: 90, y: waveAxis.velocityToY(91)), hitRadius: 5)
    report.expectEqual(expected: 2, actual: painted.count, cppID: drawerVelocityUnlockedPaintID, what: "the unlocked wave sweep covers both columns")
    report.expect(painted.contains { $0.noteID == waveFirst.noteID && $0.velocity == 37 } && painted.contains { $0.noteID == waveSecond.noteID && $0.velocity == 91 }, cppID: drawerVelocityUnlockedPaintID, message: "the unlocked wave paint keeps both raw velocities")
}

@MainActor
func drawerVelocityLateUnlockKeepsSnapped(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityLateUnlockID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    drawerVelocityPaintSetOrigins(document, page, notes[0], 33, notes[1], 87)
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    report.expectEqual(expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode, cppID: drawerVelocityLateUnlockID, what: "the square pair presents the intrinsic ruler")
    guard let firstHandle = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityLateUnlockID, "the square pair published no handles")
        return
    }
    let baseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: firstHandle.x, y: firstHandle.y, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: firstHandle.x, y: page.axisModel.levelToY(5), buttons: 1)
    report.expectEqual(expected: 44, actual: Int(page.frozenPreview[notes[0].id] ?? 0), cppID: drawerVelocityLateUnlockID, what: "the press-locked quiet note previews its snapped level")
    report.expectEqual(expected: 92, actual: Int(page.frozenPreview[notes[1].id] ?? 0), cppID: drawerVelocityLateUnlockID, what: "the press-locked later note keeps its own snapped offset")
    report.expect(page.frozenPreview[notes[2].id] == nil, cppID: drawerVelocityLateUnlockID, message: "the unselected note previews nothing")
    report.expectEqual(expected: baseline.revision, actual: document.revision, cppID: drawerVelocityLateUnlockID, what: "the locked drag stages no revision before release")
    report.expectEqual(expected: 33, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityLateUnlockID, what: "the document keeps the quiet origin during preview")
    report.expectEqual(expected: 87, actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityLateUnlockID, what: "the document keeps the later origin during preview")
    _ = page.pointerRelease(x: firstHandle.x, y: page.axisModel.levelToY(5), button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityLateUnlockID, what: "one locked drag release commits one revision")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityLateUnlockID, message: "the release clears its preview")
    report.expectEqual(expected: 44, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityLateUnlockID, what: "the release commits the snapped quiet level")
    report.expectEqual(expected: 92, actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityLateUnlockID, what: "the release commits the snapped later level")
    report.expectEqual(expected: Int(notes[2].velocity), actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityLateUnlockID, what: "the release leaves the unselected note alone")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityLateUnlockID, message: "the release keeps the drag selection")
    guard let secondNoise = drawerVelocityPaintAddNote(report, cppID: drawerVelocityLateUnlockID, document: document, page: page, tick: 120, pitch: 60, duration: 12, velocity: 50) else {
        return
    }
    drawerVelocityPaintSetOrigins(document, page, notes[2], 33, secondNoise, 87)
    fixture.session.setSelectedNotes([notes[2].id, secondNoise.id])
    page.refreshFromDocument()
    guard let noiseHandle = fixture.handle(notes[2]) else {
        report.fail(drawerVelocityLateUnlockID, "the noise pair published no handles")
        return
    }
    let noiseBaseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: noiseHandle.x, y: noiseHandle.y, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: noiseHandle.x, y: page.axisModel.levelToY(5), buttons: 1)
    report.expectEqual(expected: 44, actual: Int(page.frozenPreview[notes[2].id] ?? 0), cppID: drawerVelocityLateUnlockID, what: "the press-locked noise note previews its snapped level")
    report.expectEqual(expected: 92, actual: Int(page.frozenPreview[secondNoise.id] ?? 0), cppID: drawerVelocityLateUnlockID, what: "the press-locked second noise note keeps its own snapped offset")
    report.expectEqual(expected: noiseBaseline.revision, actual: document.revision, cppID: drawerVelocityLateUnlockID, what: "the locked noise drag stages no revision before release")
    _ = page.pointerRelease(x: noiseHandle.x, y: page.axisModel.levelToY(5), button: 1)
    report.expectEqual(expected: noiseBaseline.revision + 1, actual: document.revision, cppID: drawerVelocityLateUnlockID, what: "one locked noise release commits one revision")
    report.expectEqual(expected: 44, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityLateUnlockID, what: "the release commits the snapped noise level")
    report.expectEqual(expected: 92, actual: Int(document.note(secondNoise.id)?.velocity ?? 0), cppID: drawerVelocityLateUnlockID, what: "the release commits the snapped second noise level")
    let waveMap = VelocityMap(voiceKind: .wave)
    let waveAxis = VelocityAxisModel(map: waveMap, geometry: page.axisModel.geometry)
    var waveGesture = VelocityGestureState(kind: .relative, revision: 1, track: 0, notes: [VelocityFrozenNote(noteID: NoteID(105), tick: 0, duration: 24, pitch: 60, velocity: 33, map: waveMap, exactOrigin: 33), VelocityFrozenNote(noteID: NoteID(106), tick: 24, duration: 24, pitch: 67, velocity: 87, map: waveMap, exactOrigin: 87)], axis: waveAxis, detentUnlock: false, activationDistance: 1, pressX: 10, pressY: waveAxis.levelToY(1))
    VelocityGesturePolicy.applyRelative(&waveGesture, y: waveAxis.levelToY(2))
    report.expectEqual(expected: 64, actual: Int(waveGesture.preview[NoteID(105)] ?? 0), cppID: drawerVelocityLateUnlockID, what: "the press-locked wave quiet note previews its snapped level")
    report.expectEqual(expected: 127, actual: Int(waveGesture.preview[NoteID(106)] ?? 0), cppID: drawerVelocityLateUnlockID, what: "the press-locked wave later note keeps its own snapped offset")
}

@MainActor
func drawerVelocityUnlockedRelativeKeepsOffsets(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let unlock = KeybindingRegistry().modifierBinding("velocity.detent_unlock")
    guard unlock != 0 else {
        report.fail(drawerVelocityUnlockedRelativeID, "the detent unlock hold resolved to no modifier")
        return
    }
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityUnlockedRelativeID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    drawerVelocityPaintSetOrigins(document, page, notes[0], 33, notes[1], 87)
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    guard let firstHandle = fixture.handle(notes[0]) else {
        report.fail(drawerVelocityUnlockedRelativeID, "the square pair published no handles")
        return
    }
    let moveY = firstHandle.y - 24
    let moveDelta = page.axisModel.yToVelocity(moveY) - page.axisModel.yToVelocity(firstHandle.y)
    let baseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: firstHandle.x, y: firstHandle.y, surface: 1, button: 1, modifiers: unlock)
    _ = page.pointerMove(x: firstHandle.x, y: moveY, buttons: 1)
    report.expectEqual(expected: 33 + moveDelta, actual: Int(page.frozenPreview[notes[0].id] ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the unlocked quiet note takes the shared raw delta")
    report.expectEqual(expected: 87 + moveDelta, actual: Int(page.frozenPreview[notes[1].id] ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the unlocked later note takes the same raw delta")
    report.expect(page.frozenPreview[notes[2].id] == nil, cppID: drawerVelocityUnlockedRelativeID, message: "the unselected note previews nothing")
    report.expectEqual(expected: baseline.revision, actual: document.revision, cppID: drawerVelocityUnlockedRelativeID, what: "the unlocked drag stages no revision before release")
    report.expectEqual(expected: 33, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the document keeps the quiet origin during preview")
    report.expectEqual(expected: 87, actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the document keeps the later origin during preview")
    _ = page.pointerRelease(x: firstHandle.x, y: moveY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityUnlockedRelativeID, what: "one unlocked drag release commits one revision")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityUnlockedRelativeID, message: "the release clears its preview")
    report.expectEqual(expected: 33 + moveDelta, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the release commits the shared raw delta")
    report.expectEqual(expected: 87 + moveDelta, actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the release commits the same raw delta on every target")
    report.expectEqual(expected: Int(notes[2].velocity), actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the release leaves the unselected note alone")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id], cppID: drawerVelocityUnlockedRelativeID, message: "the release keeps the drag selection")
    guard let secondNoise = drawerVelocityPaintAddNote(report, cppID: drawerVelocityUnlockedRelativeID, document: document, page: page, tick: 120, pitch: 60, duration: 12, velocity: 50) else {
        return
    }
    drawerVelocityPaintSetOrigins(document, page, notes[2], 33, secondNoise, 87)
    fixture.session.setSelectedNotes([notes[2].id, secondNoise.id])
    page.refreshFromDocument()
    guard let noiseHandle = fixture.handle(notes[2]) else {
        report.fail(drawerVelocityUnlockedRelativeID, "the noise pair published no handles")
        return
    }
    let noiseMoveY = noiseHandle.y - 24
    let noiseMoveDelta = page.axisModel.yToVelocity(noiseMoveY) - page.axisModel.yToVelocity(noiseHandle.y)
    let noiseBaseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: noiseHandle.x, y: noiseHandle.y, surface: 1, button: 1, modifiers: unlock)
    _ = page.pointerMove(x: noiseHandle.x, y: noiseMoveY, buttons: 1)
    report.expectEqual(expected: 33 + noiseMoveDelta, actual: Int(page.frozenPreview[notes[2].id] ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the unlocked noise note takes the shared raw delta")
    report.expectEqual(expected: 87 + noiseMoveDelta, actual: Int(page.frozenPreview[secondNoise.id] ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the unlocked second noise note takes the same raw delta")
    report.expect(page.frozenPreview[notes[0].id] == nil, cppID: drawerVelocityUnlockedRelativeID, message: "the outside note previews nothing")
    report.expectEqual(expected: noiseBaseline.revision, actual: document.revision, cppID: drawerVelocityUnlockedRelativeID, what: "the unlocked noise drag stages no revision before release")
    _ = page.pointerRelease(x: noiseHandle.x, y: noiseMoveY, button: 1)
    report.expectEqual(expected: noiseBaseline.revision + 1, actual: document.revision, cppID: drawerVelocityUnlockedRelativeID, what: "one unlocked noise release commits one revision")
    report.expectEqual(expected: 33 + noiseMoveDelta, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the release commits the shared noise delta")
    report.expectEqual(expected: 87 + noiseMoveDelta, actual: Int(document.note(secondNoise.id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the release commits the same noise delta on every target")
    let waveMap = VelocityMap(voiceKind: .wave)
    let waveAxis = VelocityAxisModel(map: waveMap, geometry: page.axisModel.geometry)
    let pressWaveY = waveAxis.velocityToY(40)
    var waveGesture = VelocityGestureState(kind: .relative, revision: 1, track: 0, notes: [VelocityFrozenNote(noteID: NoteID(107), tick: 0, duration: 24, pitch: 60, velocity: 33, map: waveMap, exactOrigin: 33), VelocityFrozenNote(noteID: NoteID(108), tick: 24, duration: 24, pitch: 67, velocity: 87, map: waveMap, exactOrigin: 87)], axis: waveAxis, detentUnlock: true, activationDistance: 1, pressX: 10, pressY: pressWaveY)
    VelocityGesturePolicy.applyRelative(&waveGesture, y: waveAxis.velocityToY(47))
    report.expectEqual(expected: 40, actual: Int(waveGesture.preview[NoteID(107)] ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the unlocked wave quiet note previews its raw offset")
    report.expectEqual(expected: 94, actual: Int(waveGesture.preview[NoteID(108)] ?? 0), cppID: drawerVelocityUnlockedRelativeID, what: "the unlocked wave later note keeps its own raw offset")
}

@MainActor
func drawerVelocityUnlockedRampInterpolates(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let unlock = KeybindingRegistry().modifierBinding("velocity.detent_unlock")
    guard unlock != 0 else {
        report.fail(drawerVelocityUnlockedRampID, "the detent unlock hold resolved to no modifier")
        return
    }
    let shift = 0x0200_0000
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(drawerVelocityUnlockedRampID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document
    guard let middle = drawerVelocityPaintAddNote(report, cppID: drawerVelocityUnlockedRampID, document: document, page: page, tick: 12, pitch: 72, duration: 6, velocity: 56) else {
        return
    }
    fixture.session.setSelectedNotes([notes[0].id, middle.id, notes[1].id])
    page.refreshFromDocument()
    report.expectEqual(expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode, cppID: drawerVelocityUnlockedRampID, what: "the square triple presents the intrinsic ruler")
    guard let firstHandle = fixture.handle(notes[0]), let middleHandle = fixture.handle(middle), let lastHandle = fixture.handle(notes[1]) else {
        report.fail(drawerVelocityUnlockedRampID, "the square triple published no handles")
        return
    }
    let pressY = page.axisModel.velocityToY(37)
    let endY = page.axisModel.velocityToY(93)
    report.expect(middleHandle.x > min(firstHandle.x, lastHandle.x) && middleHandle.x < max(firstHandle.x, lastHandle.x), cppID: drawerVelocityUnlockedRampID, message: "the square middle note sits inside the swept span")
    var baseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: firstHandle.x, y: pressY, surface: 1, button: 1, modifiers: unlock | shift)
    _ = page.pointerMove(x: lastHandle.x, y: endY, buttons: 1)
    let squareMiddleExpected = page.axisModel.yToVelocity(velocityRampValue(at: middleHandle.x, x0: firstHandle.x, y0: pressY, x1: lastHandle.x, y1: endY))
    report.expectEqual(expected: 37, actual: Int(page.frozenPreview[notes[0].id] ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the unlocked square ramp starts raw")
    report.expectEqual(expected: squareMiddleExpected, actual: Int(page.frozenPreview[middle.id] ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the unlocked square middle interpolates raw")
    report.expectEqual(expected: 93, actual: Int(page.frozenPreview[notes[1].id] ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the unlocked square ramp ends raw")
    report.expect(page.frozenPreview[notes[2].id] == nil, cppID: drawerVelocityUnlockedRampID, message: "the note outside the triple previews nothing")
    report.expectEqual(expected: baseline.revision, actual: document.revision, cppID: drawerVelocityUnlockedRampID, what: "the deferred unlocked ramp stages no revision before release")
    _ = page.pointerRelease(x: lastHandle.x, y: endY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityUnlockedRampID, what: "one unlocked ramp release commits one revision")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityUnlockedRampID, message: "the release clears its preview")
    report.expectEqual(expected: 37, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the release commits the first raw ramp velocity")
    report.expectEqual(expected: squareMiddleExpected, actual: Int(document.note(middle.id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the release commits the interpolated raw velocity")
    report.expectEqual(expected: 93, actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the release commits the last raw ramp velocity")
    report.expectEqual(expected: Int(notes[2].velocity), actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the release leaves the outside note alone")
    guard let noiseMiddle = drawerVelocityPaintAddNote(report, cppID: drawerVelocityUnlockedRampID, document: document, page: page, tick: 102, pitch: 60, duration: 6, velocity: 56) else {
        return
    }
    guard let noiseLast = drawerVelocityPaintAddNote(report, cppID: drawerVelocityUnlockedRampID, document: document, page: page, tick: 108, pitch: 60, duration: 12, velocity: 60) else {
        return
    }
    fixture.session.setSelectedNotes([notes[2].id, noiseMiddle.id, noiseLast.id])
    page.refreshFromDocument()
    report.expectEqual(expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode, cppID: drawerVelocityUnlockedRampID, what: "the noise triple presents the intrinsic ruler")
    guard let noiseFirstHandle = fixture.handle(notes[2]), let noiseMiddleHandle = fixture.handle(noiseMiddle), let noiseLastHandle = fixture.handle(noiseLast) else {
        report.fail(drawerVelocityUnlockedRampID, "the noise triple published no handles")
        return
    }
    report.expect(noiseMiddleHandle.x > min(noiseFirstHandle.x, noiseLastHandle.x) && noiseMiddleHandle.x < max(noiseFirstHandle.x, noiseLastHandle.x), cppID: drawerVelocityUnlockedRampID, message: "the noise middle note sits inside the swept span")
    baseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: noiseFirstHandle.x, y: pressY, surface: 1, button: 1, modifiers: unlock | shift)
    _ = page.pointerMove(x: noiseLastHandle.x, y: endY, buttons: 1)
    report.expectEqual(expected: 37, actual: Int(page.frozenPreview[notes[2].id] ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the unlocked noise ramp starts raw")
    let noiseMiddleExpected = page.axisModel.yToVelocity(velocityRampValue(at: noiseMiddleHandle.x, x0: noiseFirstHandle.x, y0: pressY, x1: noiseLastHandle.x, y1: endY))
    report.expectEqual(expected: noiseMiddleExpected, actual: Int(page.frozenPreview[noiseMiddle.id] ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the unlocked noise middle interpolates raw")
    report.expectEqual(expected: 93, actual: Int(page.frozenPreview[noiseLast.id] ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the unlocked noise ramp ends raw")
    report.expectEqual(expected: baseline.revision, actual: document.revision, cppID: drawerVelocityUnlockedRampID, what: "the deferred noise ramp stages no revision before release")
    _ = page.pointerRelease(x: noiseLastHandle.x, y: endY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityUnlockedRampID, what: "one unlocked noise release commits one revision")
    report.expectEqual(expected: 37, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the release commits the first noise raw velocity")
    report.expectEqual(expected: noiseMiddleExpected, actual: Int(document.note(noiseMiddle.id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the release commits the interpolated noise velocity")
    report.expectEqual(expected: 93, actual: Int(document.note(noiseLast.id)?.velocity ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the release commits the last noise raw velocity")
    let waveMap = VelocityMap(voiceKind: .wave)
    let waveAxis = VelocityAxisModel(map: waveMap, geometry: page.axisModel.geometry)
    var waveGesture = VelocityGestureState(kind: .ramp, revision: 1, track: 0, notes: [VelocityFrozenNote(noteID: NoteID(109), tick: 0, duration: 24, pitch: 60, velocity: 42, map: waveMap, exactOrigin: 42), VelocityFrozenNote(noteID: NoteID(110), tick: 24, duration: 24, pitch: 60, velocity: 56, map: waveMap, exactOrigin: 56), VelocityFrozenNote(noteID: NoteID(111), tick: 48, duration: 24, pitch: 60, velocity: 80, map: waveMap, exactOrigin: 80)], axis: waveAxis, detentUnlock: true, activationDistance: 1, pressX: 10, pressY: waveAxis.velocityToY(37))
    VelocityGesturePolicy.applyRamp(&waveGesture, x: 90, y: waveAxis.velocityToY(93), hitRadius: 5) { note in
        note.tick == 0 ? 10 : note.tick == 24 ? 50 : 90
    }
    report.expectEqual(expected: 37, actual: Int(waveGesture.preview[NoteID(109)] ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the unlocked wave ramp starts raw")
    report.expectEqual(expected: 65, actual: Int(waveGesture.preview[NoteID(110)] ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the unlocked wave middle interpolates raw")
    report.expectEqual(expected: 93, actual: Int(waveGesture.preview[NoteID(111)] ?? 0), cppID: drawerVelocityUnlockedRampID, what: "the unlocked wave ramp ends raw")
}
