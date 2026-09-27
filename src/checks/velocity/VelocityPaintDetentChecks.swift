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
internal func drawerVelocityPaintAddNote(_ report: CheckReport, cppID: String, document: SongDocument, page: VelocityPage, tick: Tick, pitch: UInt8, duration: Tick, velocity: UInt8) -> Note? {
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
internal func drawerVelocityPaintSetOrigins(_ document: SongDocument, _ page: VelocityPage, _ first: Note, _ firstVelocity: UInt8, _ second: Note, _ secondVelocity: UInt8) {
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
    let depth = document.history.undoCount
    let publications = drawerVelocityPublicationCounter(session: fixture.session)
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
    report.expectEqual(expected: [100, 64, 32], actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                       cppID: drawerVelocityPaintID, what: "a drag preview holds the timeline projection at the captured velocities")
    report.expectEqual(expected: 0, actual: publications.document, cppID: drawerVelocityPaintID, what: "a held drag publishes no document change")
    report.expectEqual(expected: 0, actual: publications.dirty, cppID: drawerVelocityPaintID, what: "a held drag publishes no dirty change")
    _ = page.pointerRelease(x: endX, y: endY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityPaintID, what: "one paint release commits one revision")
    report.expect(document.history.currentIdentity != baseline.identity, cppID: drawerVelocityPaintID, message: "one paint release makes one history entry")
    report.expect(document.history.canUndo, cppID: drawerVelocityPaintID, message: "the paint entry is undoable")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityPaintID, message: "the paint release clears its preview")
    report.expectEqual(expected: 37, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityPaintID, what: "the release commits the first literal velocity")
    report.expectEqual(expected: 91, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityPaintID, what: "the release commits the last literal velocity")
    report.expectEqual(expected: Int(notes[1].velocity), actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityPaintID, what: "the release leaves the unselected note alone")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, notes[2].id], cppID: drawerVelocityPaintID, message: "the release keeps the paint selection")
    report.expectEqual(expected: [37, 64, 91], actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                       cppID: drawerVelocityPaintID, what: "a released drag republishes the staged velocities into the timeline projection")
    report.expectEqual(expected: depth + 1, actual: document.history.undoCount,
                       cppID: drawerVelocityPaintID, what: "one release grows the undo depth by exactly one")
    report.expectEqual(expected: 1, actual: publications.document, cppID: drawerVelocityPaintID, what: "one release publishes exactly one document change")
    report.expectEqual(expected: 1, actual: publications.dirty, cppID: drawerVelocityPaintID, what: "one release publishes exactly one dirty change")
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
    let depth = document.history.undoCount
    let publications = drawerVelocityPublicationCounter(session: fixture.session)
    _ = page.pointerPress(x: pressX, y: pressY, surface: 1, button: 1, modifiers: shift)
    _ = page.pointerMove(x: endX, y: endY, buttons: 1)
    report.expectEqual(expected: 37, actual: Int(page.frozenPreview[notes[0].id] ?? 0), cppID: drawerVelocityRampID, what: "the ramp press endpoint previews its literal velocity")
    report.expectEqual(expected: 65, actual: Int(page.frozenPreview[middle.id] ?? 0), cppID: drawerVelocityRampID, what: "the halfway middle note previews the interpolated velocity")
    report.expectEqual(expected: 93, actual: Int(page.frozenPreview[notes[2].id] ?? 0), cppID: drawerVelocityRampID, what: "the ramp release endpoint previews its literal velocity")
    report.expect(page.frozenPreview[notes[1].id] == nil, cppID: drawerVelocityRampID, message: "the note outside the selection previews nothing")
    report.expectEqual(expected: baseline.revision, actual: document.revision, cppID: drawerVelocityRampID, what: "the deferred ramp stages no revision before release")
    report.expectEqual(expected: baseline.identity, actual: document.history.currentIdentity, cppID: drawerVelocityRampID, what: "the deferred ramp stages no history entry before release")
    report.expectEqual(expected: Int(notes[0].velocity), actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the document keeps the first velocity during preview")
    report.expectEqual(expected: 56, actual: Int(document.note(middle.id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the document keeps the middle velocity during preview")
    report.expectEqual(expected: Int(notes[1].velocity), actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the document keeps the outside velocity during preview")
    report.expectEqual(expected: Int(notes[2].velocity), actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the document keeps the last velocity during preview")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, middle.id, notes[2].id], cppID: drawerVelocityRampID, message: "the preview keeps the ramp selection")
    report.expectEqual(expected: [100, 64, 32, 56],
                       actual: (notes + [middle]).map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                       cppID: drawerVelocityRampID, what: "a drag preview holds the timeline projection at the captured velocities")
    report.expectEqual(expected: 0, actual: publications.document, cppID: drawerVelocityRampID, what: "a held drag publishes no document change")
    report.expectEqual(expected: 0, actual: publications.dirty, cppID: drawerVelocityRampID, what: "a held drag publishes no dirty change")
    _ = page.pointerRelease(x: endX, y: endY, button: 1)
    report.expectEqual(expected: baseline.revision + 1, actual: document.revision, cppID: drawerVelocityRampID, what: "one ramp release commits one revision")
    report.expect(document.history.currentIdentity != baseline.identity, cppID: drawerVelocityRampID, message: "one ramp release makes one history entry")
    report.expect(document.history.canUndo, cppID: drawerVelocityRampID, message: "the ramp entry is undoable")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: drawerVelocityRampID, message: "the ramp release clears its preview")
    report.expectEqual(expected: 37, actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the release commits the first ramp velocity")
    report.expectEqual(expected: 65, actual: Int(document.note(middle.id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the release commits the interpolated middle velocity")
    report.expectEqual(expected: 93, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the release commits the last ramp velocity")
    report.expectEqual(expected: Int(notes[1].velocity), actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the release leaves the outside note alone")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, middle.id, notes[2].id], cppID: drawerVelocityRampID, message: "the release keeps the ramp selection")
    report.expectEqual(expected: [37, 64, 93, 65],
                       actual: (notes + [middle]).map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                       cppID: drawerVelocityRampID, what: "a released drag republishes the staged velocities into the timeline projection")
    report.expectEqual(expected: depth + 1, actual: document.history.undoCount,
                       cppID: drawerVelocityRampID, what: "one release grows the undo depth by exactly one")
    report.expectEqual(expected: 1, actual: publications.document, cppID: drawerVelocityRampID, what: "one release publishes exactly one document change")
    report.expectEqual(expected: 1, actual: publications.dirty, cppID: drawerVelocityRampID, what: "one release publishes exactly one dirty change")
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
