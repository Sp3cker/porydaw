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
    report.expectEqual(expected: middleExpected, actual: Int(document.note(middle.id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the release commits the interpolated middle velocity")
    report.expectEqual(expected: 93, actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the release commits the last ramp velocity")
    report.expectEqual(expected: Int(notes[1].velocity), actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: drawerVelocityRampID, what: "the release leaves the outside note alone")
    report.expect(fixture.session.selectedNoteOrder == [notes[0].id, middle.id, notes[2].id], cppID: drawerVelocityRampID, message: "the release keeps the ramp selection")
    report.expectEqual(expected: [37, 64, 93, middleExpected],
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

@MainActor
func drawerVelocityProgramFlowChecks(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    let unlock = KeybindingRegistry().modifierBinding("velocity.detent_unlock")
    let shift = 0x0200_0000
    guard unlock != 0 else {
        report.fail(drawerVelocityLateUnlockID, "the detent unlock hold resolved to no modifier")
        return
    }
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(drawerVelocityLateUnlockID, "the staged wave bank fixture is unavailable")
        return
    }
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftcore-velocity-wave-\(UUID().uuidString)", isDirectory: true)
    let waveService = ProjectService()
    defer {
        do {
            try runBlocking { await waveService.close() }
        } catch {
            report.fail(drawerVelocityLateUnlockID, "could not close the wave bank fixture: \(error)")
        }
        try? FileManager.default.removeItem(at: scratch)
    }
    let waveSession: DocumentSession
    do {
        try FileManager.default.copyItem(at: URL(filePath: fixtureRoot), to: scratch)
        try runBlocking { try await waveService.open(root: scratch.path) }
        let loaded = try runBlocking { try await waveService.openSong(label: "mus_gym") }
        let waveDocument = SongDocument(file: drawerVelocityVelocityPageFixture(contextSlot: 6),
                                        config: loaded.config, source: loaded.source,
                                        trackBudget: loaded.trackBudget)
        waveSession = DocumentSession(document: waveDocument, service: waveService,
                                      lease: loaded.bank, slots: loaded.bankSlots,
                                      dirty: loaded.bankDirty, loadName: loaded.bankLoadName)
    } catch {
        report.fail(drawerVelocityLateUnlockID, "could not load the staged wave bank fixture: \(error)")
        return
    }
    for program: UInt8 in [0, 6, 2] {
        let kind: VoiceKind = program == 0 ? .square1 : program == 6 ? .wave : .noise
        let expectedSnap = program == 6 ? [64, 127] : [44, 92]
        let sourceSession = program == 6 ? waveSession : session
        let sourceService = program == 6 ? waveService : service
        do {
            let fixture = drawerVelocityVelocityFixture(session: sourceSession, service: sourceService, contextSlot: program)
            let notes = fixture.notes
            let page = fixture.page
            let document = fixture.document
            drawerVelocityPaintSetOrigins(document, page, notes[0], 33, notes[1], 87)
            fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
            page.refreshFromDocument()
            report.expect(page.contextSlot == Int(program) && page.axisModel.map == VelocityMap(voiceKind: kind),
                          cppID: drawerVelocityLateUnlockID,
                          message: "the selected program resolves its own intrinsic page context")
            if program == 6 {
                report.expect(page.detentsAvailable && page.detentsEnabled
                                  && page.axisMode == VelocityAxisModel.Mode.intrinsic.rawValue,
                              cppID: drawerVelocityLateUnlockID,
                              message: "the wave pair presents the intrinsic ruler with the enabled detent control")
            }
            page.setUseDetents(enabled: false)
            report.expect(!page.detentsEnabled && !page.axisGraduationsVisible,
                          cppID: drawerVelocityLateUnlockID,
                          message: "detents toggle between intrinsic and continuous for every program family")
            page.setUseDetents(enabled: true)
            guard let first = fixture.handle(notes[0]) else {
                report.fail(drawerVelocityLateUnlockID, "the selected program published no first handle")
                continue
            }
            let publications = drawerVelocityPublicationCounter(session: fixture.session)
            let depth = document.history.undoCount
            let before = notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) }
            _ = page.pointerPress(x: first.x, y: first.y, surface: 1, button: 1, modifiers: 0)
            let nextLevel = program == 6 ? 2 : 5
            let nextY = page.axisModel.levelToY(nextLevel)
            _ = page.pointerMove(x: first.x, y: nextY, buttons: 1)
            report.expectEqual(expected: expectedSnap,
                               actual: [notes[0], notes[1]].map { Int(page.frozenPreview[$0.id] ?? 0) },
                               cppID: drawerVelocityLateUnlockID,
                               what: "a late unlock keeps the gesture snapped to the level bands")
            report.expectEqual(expected: before, actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                               cppID: drawerVelocityLateUnlockID, what: "a drag preview holds the timeline projection at the captured velocities")
            report.expectEqual(expected: 0, actual: publications.document, cppID: drawerVelocityLateUnlockID, what: "a held drag publishes no document change")
            report.expectEqual(expected: 0, actual: publications.dirty, cppID: drawerVelocityLateUnlockID, what: "a held drag publishes no dirty change")
            _ = page.pointerRelease(x: first.x, y: nextY, button: 1)
            report.expectEqual(expected: expectedSnap + [before[2]],
                               actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                               cppID: drawerVelocityLateUnlockID,
                               what: "a released drag republishes the staged velocities into the timeline projection")
            report.expectEqual(expected: depth + 1, actual: document.history.undoCount,
                               cppID: drawerVelocityLateUnlockID, what: "one release grows the undo depth by exactly one")
            report.expectEqual(expected: 1, actual: publications.document, cppID: drawerVelocityLateUnlockID, what: "one release publishes exactly one document change")
            report.expectEqual(expected: 1, actual: publications.dirty, cppID: drawerVelocityLateUnlockID, what: "one release publishes exactly one dirty change")
            report.expect(page.frozenPreview.isEmpty && fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id],
                          cppID: drawerVelocityLateUnlockID,
                          message: "the per-program locked release clears preview and retains selection")
        }
        do {
            let fixture = drawerVelocityVelocityFixture(session: sourceSession, service: sourceService, contextSlot: program)
            let notes = fixture.notes
            let page = fixture.page
            let document = fixture.document
            drawerVelocityPaintSetOrigins(document, page, notes[0], 33, notes[1], 87)
            fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
            page.refreshFromDocument()
            guard let first = fixture.handle(notes[0]) else {
                report.fail(drawerVelocityUnlockedRelativeID, "the selected program published no first handle")
                continue
            }
            let targetY = page.axisModel.velocityToY(page.axisModel.yToVelocity(first.y) + 7)
            let publications = drawerVelocityPublicationCounter(session: fixture.session)
            let depth = document.history.undoCount
            let before = notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) }
            _ = page.pointerPress(x: first.x, y: first.y, surface: 1, button: 1, modifiers: unlock)
            _ = page.pointerMove(x: first.x, y: targetY, buttons: 1)
            report.expectEqual(expected: [40, 94], actual: [notes[0], notes[1]].map { Int(page.frozenPreview[$0.id] ?? 0) },
                               cppID: drawerVelocityUnlockedRelativeID,
                               what: "an unlocked press keeps per-note offsets under a raw delta")
            report.expectEqual(expected: before, actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                               cppID: drawerVelocityUnlockedRelativeID, what: "a drag preview holds the timeline projection at the captured velocities")
            report.expectEqual(expected: 0, actual: publications.document, cppID: drawerVelocityUnlockedRelativeID, what: "a held drag publishes no document change")
            report.expectEqual(expected: 0, actual: publications.dirty, cppID: drawerVelocityUnlockedRelativeID, what: "a held drag publishes no dirty change")
            _ = page.pointerRelease(x: first.x, y: targetY, button: 1)
            report.expectEqual(expected: [40, 94, before[2]], actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                               cppID: drawerVelocityUnlockedRelativeID,
                               what: "a released drag republishes the staged velocities into the timeline projection")
            report.expectEqual(expected: depth + 1, actual: document.history.undoCount,
                               cppID: drawerVelocityUnlockedRelativeID, what: "one release grows the undo depth by exactly one")
            report.expectEqual(expected: 1, actual: publications.document, cppID: drawerVelocityUnlockedRelativeID, what: "one release publishes exactly one document change")
            report.expectEqual(expected: 1, actual: publications.dirty, cppID: drawerVelocityUnlockedRelativeID, what: "one release publishes exactly one dirty change")
            report.expect(page.frozenPreview.isEmpty && fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id],
                          cppID: drawerVelocityUnlockedRelativeID,
                          message: "the per-program raw release clears preview and retains selection")
        }
        do {
            let fixture = drawerVelocityVelocityFixture(session: sourceSession, service: sourceService, contextSlot: program)
            let notes = fixture.notes
            let page = fixture.page
            let document = fixture.document
            guard let middle = drawerVelocityPaintAddNote(report, cppID: drawerVelocityUnlockedRampID,
                                                         document: document, page: page, tick: 36,
                                                         pitch: 72, duration: 12, velocity: 56),
                  let endpoint = drawerVelocityPaintAddNote(report, cppID: drawerVelocityUnlockedRampID,
                                                           document: document, page: page, tick: 72,
                                                           pitch: 76, duration: 12, velocity: 87) else { continue }
            fixture.session.setSelectedNotes([notes[0].id, middle.id, endpoint.id])
            page.refreshFromDocument()
            guard let first = fixture.handle(notes[0]), let last = fixture.handle(endpoint) else {
                report.fail(drawerVelocityUnlockedRampID, "the selected program published no ramp endpoints")
                continue
            }
            let pressY = page.axisModel.velocityToY(37)
            let endY = page.axisModel.velocityToY(93)
            let publications = drawerVelocityPublicationCounter(session: fixture.session)
            let depth = document.history.undoCount
            let before = [notes[0], notes[1], notes[2], middle, endpoint].map { drawerVelocityTimelineVelocity(fixture.session, $0.id) }
            _ = page.pointerPress(x: first.x, y: pressY, surface: 1, button: 1, modifiers: unlock | shift)
            _ = page.pointerMove(x: last.x, y: endY, buttons: 1)
            report.expectEqual(expected: [37, 65, 93],
                               actual: [notes[0].id, middle.id, endpoint.id].map { Int(page.frozenPreview[$0] ?? 0) },
                               cppID: drawerVelocityUnlockedRampID,
                               what: "an unlocked ramp interpolates the middle note")
            report.expectEqual(expected: before,
                               actual: [notes[0], notes[1], notes[2], middle, endpoint].map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                               cppID: drawerVelocityUnlockedRampID, what: "a drag preview holds the timeline projection at the captured velocities")
            report.expectEqual(expected: 0, actual: publications.document, cppID: drawerVelocityUnlockedRampID, what: "a held drag publishes no document change")
            report.expectEqual(expected: 0, actual: publications.dirty, cppID: drawerVelocityUnlockedRampID, what: "a held drag publishes no dirty change")
            _ = page.pointerRelease(x: last.x, y: endY, button: 1)
            report.expectEqual(expected: [37, before[1], before[2], 65, 93],
                               actual: [notes[0], notes[1], notes[2], middle, endpoint].map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                               cppID: drawerVelocityUnlockedRampID,
                               what: "a released drag republishes the staged velocities into the timeline projection")
            report.expectEqual(expected: depth + 1, actual: document.history.undoCount,
                               cppID: drawerVelocityUnlockedRampID, what: "one release grows the undo depth by exactly one")
            report.expectEqual(expected: 1, actual: publications.document, cppID: drawerVelocityUnlockedRampID, what: "one release publishes exactly one document change")
            report.expectEqual(expected: 1, actual: publications.dirty, cppID: drawerVelocityUnlockedRampID, what: "one release publishes exactly one dirty change")
            report.expect(page.frozenPreview.isEmpty && fixture.session.selectedNoteOrder == [notes[0].id, middle.id, endpoint.id],
                          cppID: drawerVelocityUnlockedRampID,
                          message: "the per-program ramp release clears preview and retains selection")
        }
        if program == 6 {
            for locked in [true, false] {
                let fixture = drawerVelocityVelocityFixture(session: sourceSession, service: sourceService, contextSlot: program)
                let notes = fixture.notes
                let page = fixture.page
                fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
                page.refreshFromDocument()
                guard let first = fixture.handle(notes[0]), let last = fixture.handle(notes[1]) else {
                    report.fail(drawerVelocityLockedPaintID, "the wave pair published no paint endpoints")
                    continue
                }
                let y = page.axisModel.velocityToY(73)
                let id = locked ? drawerVelocityLockedPaintID : drawerVelocityUnlockedPaintID
                let publications = drawerVelocityPublicationCounter(session: fixture.session)
                let depth = fixture.document.history.undoCount
                _ = page.pointerPress(x: first.x, y: y, surface: 1, button: 1, modifiers: locked ? 0 : unlock)
                _ = page.pointerMove(x: last.x, y: y, buttons: 1)
                let expected = locked ? 64 : 73
                report.expectEqual(expected: [expected, expected],
                                   actual: [notes[0], notes[1]].map { Int(page.frozenPreview[$0.id] ?? 0) },
                                   cppID: id, what: "the wave page paint stages both selected note values")
                report.expectEqual(expected: [100, 64, 32], actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                                   cppID: id, what: "a drag preview holds the timeline projection at the captured velocities")
                report.expectEqual(expected: 0, actual: publications.document, cppID: id, what: "a held drag publishes no document change")
                _ = page.pointerRelease(x: last.x, y: y, button: 1)
                report.expectEqual(expected: [expected, expected, 32],
                                   actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                                   cppID: id, what: "a released drag republishes the staged velocities into the timeline projection")
                report.expectEqual(expected: depth + 1, actual: fixture.document.history.undoCount,
                                   cppID: id, what: "one release grows the undo depth by exactly one")
                report.expectEqual(expected: 1, actual: publications.document, cppID: id, what: "one release publishes exactly one document change")
                report.expectEqual(expected: 1, actual: publications.dirty, cppID: id, what: "one release publishes exactly one dirty change")
                report.expect(page.frozenPreview.isEmpty, cppID: id, message: "the wave page paint clears its staged preview")
            }
        }
    }
}
