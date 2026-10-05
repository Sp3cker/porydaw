import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore
import PorydawDocument

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
        let waveDocument = SongDocument(
            file: drawerVelocityVelocityPageFixture(contextSlot: 6),
            config: loaded.config, source: loaded.source,
            trackBudget: loaded.trackBudget)
        waveSession = DocumentSession(
            document: waveDocument, service: waveService,
            lease: loaded.bank, slots: loaded.bankSlots,
            dirty: loaded.bank.dirty, loadName: loaded.bank.loadName)
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
            let fixture = drawerVelocityVelocityFixture(
                session: sourceSession, service: sourceService, contextSlot: program)
            let notes = fixture.notes
            let page = fixture.page
            let document = fixture.document
            drawerVelocityPaintSetOrigins(document, page, notes[0], 33, notes[1], 87)
            fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
            page.refreshFromDocument()
            report.expect(
                page.contextSlot == Int(program) && page.axisModel.map == VelocityMap(voiceKind: kind),
                cppID: drawerVelocityLateUnlockID,
                message: "the selected program resolves its own intrinsic page context")
            report.expect(
                page.detentsAvailable, cppID: drawerVelocityLateUnlockID,
                message: "each locked PSG family offers detents in its resolved page context")
            report.expectEqual(
                expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode,
                cppID: drawerVelocityLateUnlockID, what: "each locked PSG family presents its intrinsic axis")
            if program == 6 {
                report.expect(
                    page.detentsAvailable && page.detentsEnabled
                        && page.axisMode == VelocityAxisModel.Mode.intrinsic.rawValue,
                    cppID: drawerVelocityLateUnlockID,
                    message: "the wave pair presents the intrinsic ruler with the enabled detent control")
            }
            page.setUseDetents(enabled: false)
            report.expect(
                !page.detentsEnabled && !page.axisGraduationsVisible,
                cppID: drawerVelocityLateUnlockID,
                message: "detents toggle between intrinsic and continuous for every program family")
            page.setUseDetents(enabled: true)
            report.expect(
                page.detentsAvailable && page.detentsEnabled,
                cppID: drawerVelocityLateUnlockID,
                message: "each locked PSG family enables and checks the detent preference")
            report.expect(
                page.detentsEnabled, cppID: drawerVelocityLateUnlockID,
                message: "each locked PSG family reads back its enabled detent policy")
            guard let first = fixture.handle(notes[0]) else {
                report.fail(drawerVelocityLateUnlockID, "the selected program published no first handle")
                continue
            }
            let publications = drawerVelocityPublicationCounter(session: fixture.session)
            let baseline = DocumentSnapshot(document)
            let depth = document.history.undoCount
            let selection = [notes[0].id, notes[1].id]
            let before = notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) }
            let storedBefore = notes.map { Int(document.note($0.id)?.velocity ?? 0) }
            report.expectEqual(
                expected: [33, 87, 32], actual: storedBefore,
                cppID: drawerVelocityLateUnlockID,
                what: "each locked PSG fixture stores the literal origins before press")
            _ = page.pointerPress(x: first.x, y: first.y, surface: 1, button: 1, modifiers: 0)
            let nextLevel = program == 6 ? 2 : 5
            let nextY = page.axisModel.levelToY(nextLevel)
            _ = page.pointerMove(x: first.x, y: nextY, buttons: 1)
            report.expectEqual(
                expected: expectedSnap,
                actual: [notes[0], notes[1]].map { Int(page.frozenPreview[$0.id] ?? 0) },
                cppID: drawerVelocityLateUnlockID,
                what: "a late unlock keeps the gesture snapped to the level bands")
            report.expect(
                page.frozenPreview[notes[2].id] == nil, cppID: drawerVelocityLateUnlockID,
                message: "each locked PSG family leaves the outside note without a preview")
            report.expectEqual(
                expected: baseline.revision, actual: document.revision,
                cppID: drawerVelocityLateUnlockID, what: "each locked PSG family holds its document revision")
            report.expectEqual(
                expected: depth, actual: document.history.undoCount,
                cppID: drawerVelocityLateUnlockID, what: "each locked PSG family holds its exact undo depth")
            report.expectEqual(
                expected: 33, actual: Int(document.note(notes[0].id)?.velocity ?? 0),
                cppID: drawerVelocityLateUnlockID,
                what: "each locked PSG family keeps quiet origin 33 in the held document")
            report.expectEqual(
                expected: 87, actual: Int(document.note(notes[1].id)?.velocity ?? 0),
                cppID: drawerVelocityLateUnlockID,
                what: "each locked PSG family keeps later origin 87 in the held document")
            report.expectEqual(
                expected: 32, actual: Int(document.note(notes[2].id)?.velocity ?? 0),
                cppID: drawerVelocityLateUnlockID,
                what: "each locked PSG family keeps outside origin 32 in the held document")
            report.expectEqual(
                expected: selection, actual: fixture.session.selectedNoteOrder,
                cppID: drawerVelocityLateUnlockID, what: "each locked PSG family holds its captured note selection")
            report.expectEqual(
                expected: before, actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                cppID: drawerVelocityLateUnlockID,
                what: "a drag preview holds the timeline projection at the captured velocities")
            report.expectEqual(
                expected: 0, actual: publications.document, cppID: drawerVelocityLateUnlockID,
                what: "a held drag publishes no document change")
            report.expectEqual(
                expected: 0, actual: publications.dirty, cppID: drawerVelocityLateUnlockID,
                what: "a held drag publishes no dirty change")
            _ = page.pointerRelease(x: first.x, y: nextY, button: 1)
            report.expectEqual(
                expected: baseline.revision + 1, actual: document.revision,
                cppID: drawerVelocityLateUnlockID, what: "each locked PSG family commits exactly one released revision")
            report.expectEqual(
                expected: expectedSnap[0], actual: Int(document.note(notes[0].id)?.velocity ?? 0),
                cppID: drawerVelocityLateUnlockID, what: "each locked PSG family commits its literal quiet detent")
            report.expectEqual(
                expected: expectedSnap[1], actual: Int(document.note(notes[1].id)?.velocity ?? 0),
                cppID: drawerVelocityLateUnlockID, what: "each locked PSG family commits its literal later detent")
            report.expectEqual(
                expected: 32, actual: Int(document.note(notes[2].id)?.velocity ?? 0),
                cppID: drawerVelocityLateUnlockID,
                what: "each locked PSG family preserves outside document velocity 32 on release")
            report.expectEqual(
                expected: expectedSnap + [before[2]],
                actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                cppID: drawerVelocityLateUnlockID,
                what: "a released drag republishes the staged velocities into the timeline projection")
            report.expectEqual(
                expected: depth + 1, actual: document.history.undoCount,
                cppID: drawerVelocityLateUnlockID, what: "one release grows the undo depth by exactly one")
            report.expectEqual(
                expected: 1, actual: publications.document, cppID: drawerVelocityLateUnlockID,
                what: "one release publishes exactly one document change")
            report.expectEqual(
                expected: 1, actual: publications.dirty, cppID: drawerVelocityLateUnlockID,
                what: "one release publishes exactly one dirty change")
            report.expect(
                page.frozenPreview.isEmpty && fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id],
                cppID: drawerVelocityLateUnlockID,
                message: "the per-program locked release clears preview and retains selection")
        }
        do {
            let fixture = drawerVelocityVelocityFixture(
                session: sourceSession, service: sourceService, contextSlot: program)
            let notes = fixture.notes
            let page = fixture.page
            let document = fixture.document
            drawerVelocityPaintSetOrigins(document, page, notes[0], 33, notes[1], 87)
            fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
            page.refreshFromDocument()
            report.expect(
                page.detentsAvailable, cppID: drawerVelocityUnlockedRelativeID,
                message: "each raw PSG family offers detents in its resolved page context")
            report.expectEqual(
                expected: VelocityAxisModel.Mode.intrinsic.rawValue, actual: page.axisMode,
                cppID: drawerVelocityUnlockedRelativeID,
                what: "each raw PSG family retains its intrinsic displayed axis")
            page.setUseDetents(enabled: false)
            page.setUseDetents(enabled: true)
            report.expect(
                page.detentsAvailable && page.detentsEnabled,
                cppID: drawerVelocityUnlockedRelativeID,
                message: "each raw PSG family enables and checks the detent preference")
            report.expect(
                page.detentsEnabled, cppID: drawerVelocityUnlockedRelativeID,
                message: "each raw PSG family reads back its enabled detent policy")
            guard let first = fixture.handle(notes[0]) else {
                report.fail(drawerVelocityUnlockedRelativeID, "the selected program published no first handle")
                continue
            }
            let targetY = page.axisModel.velocityToY(page.axisModel.yToVelocity(first.y) + 7)
            report.expectEqual(
                expected: 7, actual: page.axisModel.yToVelocity(targetY) - page.axisModel.yToVelocity(first.y),
                cppID: drawerVelocityUnlockedRelativeID,
                what: "the delivered raw plot displacement is exactly seven velocity steps")
            let publications = drawerVelocityPublicationCounter(session: fixture.session)
            let baseline = DocumentSnapshot(document)
            let depth = document.history.undoCount
            let selection = [notes[0].id, notes[1].id]
            let before = notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) }
            let storedBefore = notes.map { Int(document.note($0.id)?.velocity ?? 0) }
            report.expectEqual(
                expected: [33, 87, 32], actual: storedBefore,
                cppID: drawerVelocityUnlockedRelativeID,
                what: "each raw PSG fixture stores the literal origins before press")
            _ = page.pointerPress(x: first.x, y: first.y, surface: 1, button: 1, modifiers: unlock)
            _ = page.pointerMove(x: first.x, y: targetY, buttons: 1)
            report.expectEqual(
                expected: [40, 94], actual: [notes[0], notes[1]].map { Int(page.frozenPreview[$0.id] ?? 0) },
                cppID: drawerVelocityUnlockedRelativeID,
                what: "an unlocked press keeps per-note offsets under a raw delta")
            report.expect(
                page.frozenPreview[notes[2].id] == nil, cppID: drawerVelocityUnlockedRelativeID,
                message: "each raw PSG family leaves the outside note without a preview")
            report.expectEqual(
                expected: baseline.revision, actual: document.revision,
                cppID: drawerVelocityUnlockedRelativeID, what: "each raw PSG family holds its document revision")
            report.expectEqual(
                expected: depth, actual: document.history.undoCount,
                cppID: drawerVelocityUnlockedRelativeID, what: "each raw PSG family holds its exact undo depth")
            report.expectEqual(
                expected: baseline.identity, actual: document.history.currentIdentity,
                cppID: drawerVelocityUnlockedRelativeID, what: "the raw drag holds its history position until release")
            report.expectEqual(
                expected: 33, actual: Int(document.note(notes[0].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRelativeID,
                what: "each raw PSG family keeps quiet origin 33 in the held document")
            report.expectEqual(
                expected: 87, actual: Int(document.note(notes[1].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRelativeID,
                what: "each raw PSG family keeps later origin 87 in the held document")
            report.expectEqual(
                expected: 32, actual: Int(document.note(notes[2].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRelativeID,
                what: "each raw PSG family keeps outside origin 32 in the held document")
            report.expectEqual(
                expected: selection, actual: fixture.session.selectedNoteOrder,
                cppID: drawerVelocityUnlockedRelativeID, what: "each raw PSG family holds its captured note selection")
            report.expectEqual(
                expected: before, actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                cppID: drawerVelocityUnlockedRelativeID,
                what: "a drag preview holds the timeline projection at the captured velocities")
            report.expectEqual(
                expected: 0, actual: publications.document, cppID: drawerVelocityUnlockedRelativeID,
                what: "a held drag publishes no document change")
            report.expectEqual(
                expected: 0, actual: publications.dirty, cppID: drawerVelocityUnlockedRelativeID,
                what: "a held drag publishes no dirty change")
            _ = page.pointerRelease(x: first.x, y: targetY, button: 1)
            report.expectEqual(
                expected: baseline.revision + 1, actual: document.revision,
                cppID: drawerVelocityUnlockedRelativeID,
                what: "each raw PSG family commits exactly one released revision")
            report.expect(
                document.history.currentIdentity != baseline.identity, cppID: drawerVelocityUnlockedRelativeID,
                message: "the raw release advances its history position exactly once")
            report.expectEqual(
                expected: 40, actual: Int(document.note(notes[0].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRelativeID, what: "each raw PSG family commits literal quiet velocity 40")
            report.expectEqual(
                expected: 94, actual: Int(document.note(notes[1].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRelativeID, what: "each raw PSG family commits literal later velocity 94")
            report.expectEqual(
                expected: 32, actual: Int(document.note(notes[2].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRelativeID,
                what: "each raw PSG family preserves outside document velocity 32 on release")
            report.expectEqual(
                expected: [40, 94, before[2]],
                actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                cppID: drawerVelocityUnlockedRelativeID,
                what: "a released drag republishes the staged velocities into the timeline projection")
            report.expectEqual(
                expected: depth + 1, actual: document.history.undoCount,
                cppID: drawerVelocityUnlockedRelativeID, what: "one release grows the undo depth by exactly one")
            report.expectEqual(
                expected: 1, actual: publications.document, cppID: drawerVelocityUnlockedRelativeID,
                what: "one release publishes exactly one document change")
            report.expectEqual(
                expected: 1, actual: publications.dirty, cppID: drawerVelocityUnlockedRelativeID,
                what: "one release publishes exactly one dirty change")
            report.expect(
                page.frozenPreview.isEmpty && fixture.session.selectedNoteOrder == [notes[0].id, notes[1].id],
                cppID: drawerVelocityUnlockedRelativeID,
                message: "the per-program raw release clears preview and retains selection")
        }
        do {
            let fixture = drawerVelocityVelocityFixture(
                session: sourceSession, service: sourceService, contextSlot: program)
            let notes = fixture.notes
            let page = fixture.page
            let document = fixture.document
            guard
                let middle = drawerVelocityPaintAddNote(
                    report, cppID: drawerVelocityUnlockedRampID,
                    document: document, page: page, tick: 36,
                    pitch: 72, duration: 12, velocity: 56),
                let endpoint = drawerVelocityPaintAddNote(
                    report, cppID: drawerVelocityUnlockedRampID,
                    document: document, page: page, tick: 72,
                    pitch: 76, duration: 12, velocity: 87)
            else { continue }
            fixture.session.setSelectedNotes([notes[0].id, middle.id, endpoint.id])
            report.expectEqual(
                expected: 56, actual: drawerVelocityTimelineVelocity(fixture.session, middle.id),
                cppID: drawerVelocityUnlockedRampID, what: "the raw ramp middle starts at 56 in the timeline")
            page.refreshFromDocument()
            guard let first = fixture.handle(notes[0]), let last = fixture.handle(endpoint) else {
                report.fail(drawerVelocityUnlockedRampID, "the selected program published no ramp endpoints")
                continue
            }
            guard let middleHandle = fixture.handle(middle) else {
                report.fail(drawerVelocityUnlockedRampID, "the selected program published no middle ramp handle")
                continue
            }
            report.expect(
                page.detentsAvailable, cppID: drawerVelocityUnlockedRampID,
                message: "each raw ramp family resolves its own PSG context")
            report.expectEqual(
                expected: VelocityAxisModel.Mode.intrinsic.rawValue,
                actual: page.axisMode, cppID: drawerVelocityUnlockedRampID,
                what: "each raw ramp family presents its intrinsic ruler")
            report.expect(
                page.detentsEnabled, cppID: drawerVelocityUnlockedRampID,
                message: "each raw ramp family retains its enabled detent preference")
            report.expect(
                first.x < middleHandle.x && middleHandle.x < last.x
                    && abs(middleHandle.x - (first.x + last.x) / 2) <= first.hitRadius,
                cppID: drawerVelocityUnlockedRampID,
                message: "the mounted ramp midpoint is bracketed by distinct endpoint columns")
            let pressY = page.axisModel.velocityToY(37)
            let endY = page.axisModel.velocityToY(93)
            let publications = drawerVelocityPublicationCounter(session: fixture.session)
            let depth = document.history.undoCount
            let before = [notes[0], notes[1], notes[2], middle, endpoint].map {
                drawerVelocityTimelineVelocity(fixture.session, $0.id)
            }
            let baseline = DocumentSnapshot(document)
            let selected = [notes[0].id, middle.id, endpoint.id]
            _ = page.pointerPress(x: first.x, y: pressY, surface: 1, button: 1, modifiers: unlock | shift)
            _ = page.pointerMove(x: last.x, y: endY, buttons: 1)
            report.expectEqual(
                expected: [37, 65, 93],
                actual: [notes[0].id, middle.id, endpoint.id].map { Int(page.frozenPreview[$0] ?? 0) },
                cppID: drawerVelocityUnlockedRampID,
                what: "an unlocked ramp interpolates the middle note")
            report.expect(
                page.frozenPreview[notes[1].id] == nil && page.frozenPreview[notes[2].id] == nil,
                cppID: drawerVelocityUnlockedRampID, message: "the raw ramp excludes both unselected previews")
            report.expectEqual(
                expected: baseline.revision, actual: document.revision,
                cppID: drawerVelocityUnlockedRampID, what: "the raw ramp holds its revision until release")
            report.expectEqual(
                expected: baseline.identity, actual: document.history.currentIdentity,
                cppID: drawerVelocityUnlockedRampID, what: "the raw ramp holds its history position until release")
            report.expectEqual(
                expected: depth, actual: document.history.undoCount,
                cppID: drawerVelocityUnlockedRampID, what: "the raw ramp holds its undo count until release")
            report.expectEqual(
                expected: 100, actual: Int(document.note(notes[0].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRampID, what: "the held raw ramp keeps quiet origin 100")
            report.expectEqual(
                expected: 56, actual: Int(document.note(middle.id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRampID, what: "the held raw ramp keeps middle origin 56")
            report.expectEqual(
                expected: 87, actual: Int(document.note(endpoint.id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRampID, what: "the held raw ramp keeps later origin 87")
            report.expectEqual(
                expected: 64, actual: Int(document.note(notes[1].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRampID, what: "the held raw ramp keeps outside velocity 64")
            report.expectEqual(
                expected: 32, actual: Int(document.note(notes[2].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRampID, what: "the held raw ramp keeps second outside velocity 32")
            report.expectEqual(
                expected: selected, actual: fixture.session.selectedNoteOrder,
                cppID: drawerVelocityUnlockedRampID, what: "the raw ramp holds its three-note selection")
            report.expectEqual(
                expected: before,
                actual: [notes[0], notes[1], notes[2], middle, endpoint].map {
                    drawerVelocityTimelineVelocity(fixture.session, $0.id)
                },
                cppID: drawerVelocityUnlockedRampID,
                what: "a drag preview holds the timeline projection at the captured velocities")
            report.expectEqual(
                expected: 0, actual: publications.document, cppID: drawerVelocityUnlockedRampID,
                what: "a held drag publishes no document change")
            report.expectEqual(
                expected: 0, actual: publications.dirty, cppID: drawerVelocityUnlockedRampID,
                what: "a held drag publishes no dirty change")
            _ = page.pointerRelease(x: last.x, y: endY, button: 1)
            report.expectEqual(
                expected: baseline.revision + 1, actual: document.revision,
                cppID: drawerVelocityUnlockedRampID, what: "the raw ramp release advances one revision")
            report.expect(
                document.history.currentIdentity != baseline.identity, cppID: drawerVelocityUnlockedRampID,
                message: "the raw ramp release advances its history position")
            report.expectEqual(
                expected: 37, actual: Int(document.note(notes[0].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRampID, what: "the raw ramp release commits quiet literal 37")
            report.expectEqual(
                expected: 65, actual: Int(document.note(middle.id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRampID, what: "the raw ramp release commits middle literal 65")
            report.expectEqual(
                expected: 93, actual: Int(document.note(endpoint.id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRampID, what: "the raw ramp release commits later literal 93")
            report.expectEqual(
                expected: 64, actual: Int(document.note(notes[1].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRampID, what: "the raw ramp release preserves outside velocity 64")
            report.expectEqual(
                expected: 32, actual: Int(document.note(notes[2].id)?.velocity ?? 0),
                cppID: drawerVelocityUnlockedRampID, what: "the raw ramp release preserves second outside velocity 32")
            report.expectEqual(
                expected: [37, before[1], before[2], 65, 93],
                actual: [notes[0], notes[1], notes[2], middle, endpoint].map {
                    drawerVelocityTimelineVelocity(fixture.session, $0.id)
                },
                cppID: drawerVelocityUnlockedRampID,
                what: "a released drag republishes the staged velocities into the timeline projection")
            report.expectEqual(
                expected: depth + 1, actual: document.history.undoCount,
                cppID: drawerVelocityUnlockedRampID, what: "one release grows the undo depth by exactly one")
            report.expectEqual(
                expected: 1, actual: publications.document, cppID: drawerVelocityUnlockedRampID,
                what: "one release publishes exactly one document change")
            report.expectEqual(
                expected: 1, actual: publications.dirty, cppID: drawerVelocityUnlockedRampID,
                what: "one release publishes exactly one dirty change")
            report.expect(
                page.frozenPreview.isEmpty
                    && fixture.session.selectedNoteOrder == [notes[0].id, middle.id, endpoint.id],
                cppID: drawerVelocityUnlockedRampID,
                message: "the per-program ramp release clears preview and retains selection")
        }
        drawerVelocityFamilyRuler(
            report, session: sourceSession, service: sourceService,
            program: program, unlock: unlock)
        drawerVelocityFamilyPaint(
            report, session: sourceSession, service: sourceService,
            program: program, unlock: unlock, locked: true)
        drawerVelocityFamilyPaint(
            report, session: sourceSession, service: sourceService,
            program: program, unlock: unlock, locked: false)
        if program == 6 {
            for locked in [true, false] {
                let fixture = drawerVelocityVelocityFixture(
                    session: sourceSession, service: sourceService, contextSlot: program)
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
                report.expectEqual(
                    expected: [expected, expected],
                    actual: [notes[0], notes[1]].map { Int(page.frozenPreview[$0.id] ?? 0) },
                    cppID: id, what: "the wave page paint stages both selected note values")
                report.expectEqual(
                    expected: [100, 64, 32],
                    actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                    cppID: id, what: "a drag preview holds the timeline projection at the captured velocities")
                report.expectEqual(
                    expected: 0, actual: publications.document, cppID: id,
                    what: "a held drag publishes no document change")
                _ = page.pointerRelease(x: last.x, y: y, button: 1)
                report.expectEqual(
                    expected: [expected, expected, 32],
                    actual: notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) },
                    cppID: id, what: "a released drag republishes the staged velocities into the timeline projection")
                report.expectEqual(
                    expected: depth + 1, actual: fixture.document.history.undoCount,
                    cppID: id, what: "one release grows the undo depth by exactly one")
                report.expectEqual(
                    expected: 1, actual: publications.document, cppID: id,
                    what: "one release publishes exactly one document change")
                report.expectEqual(
                    expected: 1, actual: publications.dirty, cppID: id,
                    what: "one release publishes exactly one dirty change")
                report.expect(
                    page.frozenPreview.isEmpty, cppID: id, message: "the wave page paint clears its staged preview")
            }
        }
    }
}

@MainActor
private func drawerVelocityFamilyPaint(
    _ report: CheckReport, session: DocumentSession,
    service: ProjectService, program: UInt8, unlock: Int,
    locked: Bool
) {
    let id = locked ? drawerVelocityLockedPaintID : drawerVelocityUnlockedPaintID
    let fixture = drawerVelocityVelocityFixture(session: session, service: service, contextSlot: program)
    let notes = fixture.notes
    let page = fixture.page
    let document = fixture.document
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    let expectedFirst = locked ? (program == 6 ? 64 : 76) : 37
    let expectedLast = locked ? expectedFirst : 91
    if locked {
        report.expect(
            page.detentsAvailable, cppID: id, message: "paint context exposes the selected family's detent control")
        report.expect(page.detentsEnabled, cppID: id, message: "locked paint begins with the detent control enabled")
        report.expect(
            page.detentsEnabled && page.axisGraduationsVisible, cppID: id,
            message: "locked paint reads back its checked detent preference")
    } else {
        report.expect(
            page.detentsAvailable, cppID: id, message: "raw paint context exposes the selected family's detent control")
        report.expect(page.detentsEnabled, cppID: id, message: "raw paint begins with the detent control enabled")
        report.expect(
            page.detentsEnabled && page.axisGraduationsVisible, cppID: id,
            message: "raw paint reads back its checked detent preference")
    }
    guard let first = fixture.handle(notes[0]), let last = fixture.handle(notes[1]) else {
        report.fail(id, "the selected family published no paint columns")
        return
    }
    let startY = page.axisModel.velocityToY(locked ? 73 : 37)
    let endY = page.axisModel.velocityToY(locked ? 73 : 91)
    let before = notes.map { Int(document.note($0.id)?.velocity ?? 0) }
    let timelineBefore = notes.map { drawerVelocityTimelineVelocity(fixture.session, $0.id) }
    let baseline = DocumentSnapshot(document)
    let depth = document.history.undoCount
    let publications = drawerVelocityPublicationCounter(session: fixture.session)
    let pressX = first.x + first.hitRadius * 2
    let startSlope = (endY - startY) / (last.x - first.x)
    let pressY = startY + startSlope * (pressX - first.x)
    _ = page.pointerPress(x: pressX, y: pressY, surface: 1, button: 1, modifiers: locked ? 0 : unlock)
    _ = page.pointerMove(x: first.x, y: startY, buttons: 1)
    _ = page.pointerMove(x: last.x, y: endY, buttons: 1)
    if locked {
        report.expectEqual(
            expected: depth, actual: document.history.undoCount, cppID: id,
            what: "locked paint holds exact undo depth until release")
        report.expectEqual(
            expected: 0, actual: publications.document, cppID: id,
            what: "locked paint publishes no document change before release")
        report.expectEqual(
            expected: 0, actual: publications.dirty, cppID: id,
            what: "locked paint publishes no dirty transition before release")
        report.expectEqual(
            expected: before[0], actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: id,
            what: "locked paint holds the first document origin")
        report.expectEqual(
            expected: before[1], actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: id,
            what: "locked paint holds the later document origin")
        report.expectEqual(
            expected: before[2], actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: id,
            what: "locked paint holds the outside document origin")
        report.expectEqual(
            expected: timelineBefore[0], actual: drawerVelocityTimelineVelocity(fixture.session, notes[0].id),
            cppID: id, what: "locked paint holds the first timeline origin")
        report.expectEqual(
            expected: timelineBefore[1], actual: drawerVelocityTimelineVelocity(fixture.session, notes[1].id),
            cppID: id, what: "locked paint holds the later timeline origin")
        report.expectEqual(
            expected: timelineBefore[2], actual: drawerVelocityTimelineVelocity(fixture.session, notes[2].id),
            cppID: id, what: "locked paint holds the outside timeline origin")
    } else {
        report.expectEqual(
            expected: depth, actual: document.history.undoCount, cppID: id,
            what: "raw paint holds exact undo depth until release")
        report.expectEqual(
            expected: 0, actual: publications.document, cppID: id,
            what: "raw paint publishes no document change before release")
        report.expectEqual(
            expected: 0, actual: publications.dirty, cppID: id,
            what: "raw paint publishes no dirty transition before release")
        report.expectEqual(
            expected: before[0], actual: Int(document.note(notes[0].id)?.velocity ?? 0), cppID: id,
            what: "raw paint holds the first document origin")
        report.expectEqual(
            expected: before[1], actual: Int(document.note(notes[1].id)?.velocity ?? 0), cppID: id,
            what: "raw paint holds the later document origin")
        report.expectEqual(
            expected: before[2], actual: Int(document.note(notes[2].id)?.velocity ?? 0), cppID: id,
            what: "raw paint holds the outside document origin")
        report.expectEqual(
            expected: timelineBefore[0], actual: drawerVelocityTimelineVelocity(fixture.session, notes[0].id),
            cppID: id, what: "raw paint holds the first timeline origin")
        report.expectEqual(
            expected: timelineBefore[1], actual: drawerVelocityTimelineVelocity(fixture.session, notes[1].id),
            cppID: id, what: "raw paint holds the later timeline origin")
        report.expectEqual(
            expected: timelineBefore[2], actual: drawerVelocityTimelineVelocity(fixture.session, notes[2].id),
            cppID: id, what: "raw paint holds the outside timeline origin")
    }
    report.expectEqual(
        expected: baseline.revision, actual: document.revision, cppID: id,
        what: "family paint stages no revision before release")
    report.expectEqual(
        expected: expectedFirst, actual: Int(page.frozenPreview[notes[0].id] ?? 0), cppID: id,
        what: "family paint previews the first literal detent or raw value")
    report.expectEqual(
        expected: expectedLast, actual: Int(page.frozenPreview[notes[1].id] ?? 0), cppID: id,
        what: "family paint previews the later literal detent or raw value")
    _ = page.pointerRelease(x: last.x, y: endY, button: 1)
    if locked {
        report.expectEqual(
            expected: 1, actual: publications.document, cppID: id,
            what: "locked paint release publishes exactly one document change")
        report.expectEqual(
            expected: 1, actual: publications.dirty, cppID: id,
            what: "locked paint release publishes exactly one dirty transition")
        report.expectEqual(
            expected: depth + 1, actual: document.history.undoCount, cppID: id,
            what: "locked paint release grows exact undo depth by one")
        report.expect(document.history.canUndo, cppID: id, message: "locked paint release enables undo")
        report.expect(
            page.frozenPreview[notes[0].id] == nil, cppID: id,
            message: "locked paint clears its first preview on release")
        report.expect(
            page.frozenPreview[notes[1].id] == nil, cppID: id,
            message: "locked paint clears its later preview on release")
        report.expect(
            page.frozenPreview[notes[2].id] == nil, cppID: id,
            message: "locked paint clears its outside preview on release")
        report.expectEqual(
            expected: expectedFirst, actual: drawerVelocityTimelineVelocity(fixture.session, notes[0].id), cppID: id,
            what: "locked paint publishes the first detent to the timeline")
        report.expectEqual(
            expected: expectedLast, actual: drawerVelocityTimelineVelocity(fixture.session, notes[1].id), cppID: id,
            what: "locked paint publishes the later detent to the timeline")
        report.expectEqual(
            expected: timelineBefore[2], actual: drawerVelocityTimelineVelocity(fixture.session, notes[2].id),
            cppID: id, what: "locked paint preserves the outside timeline velocity")
    } else {
        report.expectEqual(
            expected: 1, actual: publications.document, cppID: id,
            what: "raw paint release publishes exactly one document change")
        report.expectEqual(
            expected: 1, actual: publications.dirty, cppID: id,
            what: "raw paint release publishes exactly one dirty transition")
        report.expectEqual(
            expected: depth + 1, actual: document.history.undoCount, cppID: id,
            what: "raw paint release grows exact undo depth by one")
        report.expect(
            page.frozenPreview[notes[0].id] == nil, cppID: id, message: "raw paint clears its first preview on release")
        report.expect(
            page.frozenPreview[notes[1].id] == nil, cppID: id, message: "raw paint clears its later preview on release")
        report.expect(
            page.frozenPreview[notes[2].id] == nil, cppID: id,
            message: "raw paint clears its outside preview on release")
        report.expectEqual(
            expected: expectedFirst, actual: drawerVelocityTimelineVelocity(fixture.session, notes[0].id), cppID: id,
            what: "raw paint publishes the first velocity to the timeline")
        report.expectEqual(
            expected: expectedLast, actual: drawerVelocityTimelineVelocity(fixture.session, notes[1].id), cppID: id,
            what: "raw paint publishes the later velocity to the timeline")
        report.expectEqual(
            expected: timelineBefore[2], actual: drawerVelocityTimelineVelocity(fixture.session, notes[2].id),
            cppID: id, what: "raw paint preserves the outside timeline velocity")
    }
    report.expectEqual(
        expected: baseline.revision + 1, actual: document.revision, cppID: id,
        what: "family paint release commits one revision")
    report.expectEqual(
        expected: [expectedFirst, expectedLast, before[2]],
        actual: notes.map { Int(document.note($0.id)?.velocity ?? 0) },
        cppID: id, what: "family paint commits exact selected values and preserves the outside note")
}
