import PorydawApp
import PorydawCore

@MainActor
func runVelocityGestureParityChecks(_ report: CheckReport) {
    let lifecycleID = "keyboard/VelocityModelTest::gestureLifecycle"
    let atomicityID = "keyboard/VelocityModelTest::gestureAtomicity"
    let completionID = "keyboard/VelocityModelTest::gestureCompletionAndDeltaFromOriginals"
    let clampedID = "keyboard/VelocityModelTest::gestureClampedDeltaAndCancellation"
    let frozenMap = VelocityMap(voiceKind: .unresolved)
    var axisGeometry = VelocityAxisGeometry()
    axisGeometry.height = 126
    let axis = VelocityAxisModel(map: frozenMap, geometry: axisGeometry)
    let pressY = axis.velocityToY(80)
    func frozenNote(_ id: NoteID, velocity: UInt8) -> VelocityFrozenNote {
        VelocityFrozenNote(noteID: id, tick: 0, duration: 8, pitch: 60, velocity: velocity,
                           map: frozenMap, exactOrigin: velocity)
    }
    func frozenGesture(notes: [VelocityFrozenNote], revision: UInt64) -> VelocityGestureState {
        VelocityGestureState(kind: .relative, revision: revision, track: 0, notes: notes,
                             axis: axis, detentUnlock: true, activationDistance: 0,
                             pressX: 0, pressY: pressY)
    }
    @MainActor
    func gestureDocument() -> (SongDocument, NoteID, NoteID)? {
        let document = SongDocument(file: MidiFile(division: 24, chunks: [
            MidiChunk(events: [], endTick: 128),
            MidiChunk(events: [.channel(tick: 0, status: 0xC0, data0: 0)], endTick: 128),
        ]))
        guard let ids = try? document.addNotes([
            NewNote(track: 0, tick: 0, pitch: 60, duration: 8, velocity: 40),
            NewNote(track: 0, tick: 24, pitch: 64, duration: 8, velocity: 120),
        ]), ids.count == 2,
            document.note(ids[0])?.velocity == 40,
            document.note(ids[1])?.velocity == 120
        else { return nil }
        return (document, ids[0], ids[1])
    }
    var lifecycle: VelocityGestureState? = nil
    report.expect(lifecycle == nil, cppID: lifecycleID, message: "A001 fresh gesture captures nothing")
    var empty = frozenGesture(notes: [], revision: 0)
    VelocityGesturePolicy.applyRelative(&empty, y: pressY - 10)
    report.expect(empty.preview.isEmpty && !empty.relativeActivated, cppID: lifecycleID, message: "A002 relative motion with no targets previews nothing")
    report.expect(lifecycle?.preview == nil, cppID: lifecycleID, message: "A003 preview with no gesture is empty")
    report.expect(VelocityGesturePolicy.updates(empty).isEmpty, cppID: lifecycleID, message: "A004 completion with no targets carries nothing")
    lifecycle = nil
    report.expect(lifecycle == nil, cppID: lifecycleID, message: "A005 cancelling with no gesture stays empty")
    guard let probe = gestureDocument() else {
        report.fail(lifecycleID, "the lifecycle probe fixture projected no notes")
        return
    }
    let probeDocument = probe.0
    let probeFirst = probe.1
    let probeSecond = probe.2
    let probeEmpty = probeDocument.setVelocities([], expectedRevision: probeDocument.revision)
    report.expect(probeEmpty == probeDocument.revision, cppID: lifecycleID, message: "A006 empty commit is a no-op success")
    let probeUnassigned = probeDocument.setVelocities([NoteVelocity(noteID: NoteID(), velocity: 40)], expectedRevision: probeDocument.revision)
    report.expect(probeUnassigned == nil, cppID: lifecycleID, message: "A007 unassigned commit rejects")
    let probeFloor = probeDocument.setVelocities([NoteVelocity(noteID: probeFirst, velocity: 0)], expectedRevision: probeDocument.revision)
    report.expect(probeFloor == probeDocument.revision && probeDocument.note(probeFirst)?.velocity == 1, cppID: lifecycleID, message: "A008 below-floor commit clamps to the floor")
    let probeCeiling = probeDocument.setVelocities([NoteVelocity(noteID: probeFirst, velocity: 128)], expectedRevision: probeDocument.revision)
    report.expect(probeCeiling == probeDocument.revision && probeDocument.note(probeFirst)?.velocity == 127, cppID: lifecycleID, message: "A009 above-ceiling commit clamps to the ceiling")
    let probeRevision = probeDocument.revision
    let probeDuplicate = probeDocument.setVelocities([NoteVelocity(noteID: probeFirst, velocity: 127), NoteVelocity(noteID: probeFirst, velocity: 127)], expectedRevision: probeRevision)
    report.expect(probeDuplicate == probeRevision && probeDocument.revision == probeRevision, cppID: lifecycleID, message: "A010 duplicated commit keeps the last write")
    let probeLonger = probeDocument.setVelocities([NoteVelocity(noteID: probeFirst, velocity: 127), NoteVelocity(noteID: probeSecond, velocity: 120), NoteVelocity(noteID: probeSecond, velocity: 120)], expectedRevision: probeRevision)
    report.expect(probeLonger == probeRevision && probeDocument.note(probeSecond)?.velocity == 120, cppID: lifecycleID, message: "A011 duplicated longer commit changes nothing")
    let frozenProbe = frozenGesture(notes: [frozenNote(probeFirst, velocity: 127), frozenNote(probeSecond, velocity: 120)], revision: probeRevision)
    let probeRejected = probeDocument.setVelocities([NoteVelocity(noteID: NoteID(), velocity: 40)], expectedRevision: probeRevision)
    report.expect(probeRejected == nil && probeDocument.revision == probeRevision && frozenProbe.preview.isEmpty, cppID: lifecycleID, message: "A012 rejected commits leave the gesture and revision untouched")
    guard let live = gestureDocument() else {
        report.fail(lifecycleID, "the lifecycle freeze fixture projected no notes")
        return
    }
    let liveFirst = live.1
    let liveSecond = live.2
    lifecycle = frozenGesture(notes: [frozenNote(liveSecond, velocity: 120), frozenNote(liveFirst, velocity: 40)], revision: live.0.revision)
    report.expect(lifecycle?.notes.count == 2, cppID: lifecycleID, message: "A013 freeze accepts an unsorted target pair")
    report.expect(lifecycle != nil, cppID: lifecycleID, message: "A014 captured freeze reports active")
    report.expectEqual(expected: Optional(UInt8(40)), actual: lifecycle?.frozenNote(liveFirst)?.velocity, cppID: lifecycleID, what: "A015 first frozen target holds its begin value")
    report.expectEqual(expected: Optional(UInt8(120)), actual: lifecycle?.frozenNote(liveSecond)?.velocity, cppID: lifecycleID, what: "A016 second frozen target holds its begin value")
    lifecycle = frozenGesture(notes: [frozenNote(liveFirst, velocity: 40)], revision: live.0.revision)
    report.expect(lifecycle?.notes.count == 1, cppID: lifecycleID, message: "A017 re-freeze replaces the live gesture")
    report.expect(lifecycle?.preview.isEmpty ?? false, cppID: lifecycleID, message: "A018 re-freeze starts with an empty preview")
    guard let atomic = gestureDocument() else {
        report.fail(atomicityID, "the atomicity fixture projected no notes")
        return
    }
    let atomicDocument = atomic.0
    let atomicFirst = atomic.1
    let atomicSecond = atomic.2
    let atomicity = frozenGesture(notes: [frozenNote(atomicFirst, velocity: 40), frozenNote(atomicSecond, velocity: 120)], revision: atomicDocument.revision)
    report.expect(atomicity.notes.count == 2, cppID: atomicityID, message: "A019 freeze captures the atomicity pair")
    let unknownTarget = NoteID(max(atomicFirst.rawValue, atomicSecond.rawValue) + 1000)
    let atomicRevision = atomicDocument.revision
    let atomicRejected = atomicDocument.setVelocities([NoteVelocity(noteID: atomicFirst, velocity: 100), NoteVelocity(noteID: unknownTarget, velocity: 64)], expectedRevision: atomicRevision)
    report.expect(atomicRejected == nil, cppID: atomicityID, message: "A020 commit with an unknown target rejects")
    report.expect(atomicDocument.note(atomicFirst)?.velocity == 40 && atomicity.preview.isEmpty, cppID: atomicityID, message: "A021 rejected commit keeps the first value")
    report.expectEqual(expected: UInt8(120), actual: atomicDocument.note(atomicSecond)?.velocity, cppID: atomicityID, what: "A022 rejected commit keeps the second value")
    let atomicEmpty = atomicDocument.setVelocities([], expectedRevision: atomicRevision)
    report.expect(atomicEmpty == atomicRevision && atomicDocument.revision == atomicRevision, cppID: atomicityID, message: "A023 empty commit is a no-op success")
    let atomicDuplicate = atomicDocument.setVelocities([NoteVelocity(noteID: atomicFirst, velocity: 100), NoteVelocity(noteID: atomicFirst, velocity: 110)], expectedRevision: atomicRevision)
    report.expect(atomicDuplicate == atomicDocument.revision && atomicDocument.note(atomicFirst)?.velocity == 110, cppID: atomicityID, message: "A024 duplicated commit keeps the last write")
    report.expect(atomicDocument.note(atomicFirst)?.velocity == 110, cppID: atomicityID, message: "A025 duplicated commit moves the first value to the last write")
    report.expectEqual(expected: UInt8(120), actual: atomicDocument.note(atomicSecond)?.velocity, cppID: atomicityID, what: "A026 duplicated commit keeps the second value")
    guard let finishing = gestureDocument() else {
        report.fail(completionID, "the completion fixture projected no notes")
        return
    }
    let finishingDocument = finishing.0
    let finishingFirst = finishing.1
    let finishingSecond = finishing.2
    let finishingRevision = finishingDocument.revision
    var completion: VelocityGestureState? = frozenGesture(notes: [frozenNote(finishingSecond, velocity: 120), frozenNote(finishingFirst, velocity: 40)], revision: finishingRevision)
    report.expect(completion?.notes.count == 2, cppID: completionID, message: "A027 freeze captures the completion pair")
    completion!.preview[finishingFirst] = 100
    let absolute = VelocityGesturePolicy.updates(completion!)
    report.expect(absolute.contains(where: { $0.noteID == finishingFirst && $0.velocity == 100 }), cppID: completionID, message: "A028 absolute preview applies to the commit payload")
    report.expectEqual(expected: Optional(UInt8(100)), actual: completion!.preview[finishingFirst], cppID: completionID, what: "A029 first preview takes the absolute value")
    report.expect(completion!.preview[finishingSecond] == nil && completion!.frozenNote(finishingSecond)?.velocity == 120, cppID: completionID, message: "A030 untouched target keeps its frozen begin value")
    VelocityGesturePolicy.applyRelative(&completion!, y: axis.velocityToY(70))
    report.expect(completion!.relativeActivated, cppID: completionID, message: "A031 relative motion past activation arms the gesture")
    report.expectEqual(expected: Optional(UInt8(30)), actual: completion!.preview[finishingFirst], cppID: completionID, what: "A032 first preview measures the delta from its origin")
    report.expectEqual(expected: Optional(UInt8(110)), actual: completion!.preview[finishingSecond], cppID: completionID, what: "A033 second preview measures the delta from its origin")
    let payload = VelocityGesturePolicy.updates(completion!)
    report.expect(!payload.isEmpty, cppID: completionID, message: "A034 completion exists after edits")
    report.expectEqual(expected: finishingRevision, actual: completion!.revision, cppID: completionID, what: "A035 completion carries the begin revision")
    report.expectEqual(expected: 2, actual: payload.count, cppID: completionID, what: "A036 completion carries both targets")
    report.expectEqual(expected: finishingFirst, actual: payload.first?.noteID ?? NoteID(), cppID: completionID, what: "A037 completion orders the first target by note")
    report.expectEqual(expected: 30, actual: payload.first?.velocity ?? -1, cppID: completionID, what: "A038 completion carries the first delta value")
    report.expectEqual(expected: finishingSecond, actual: payload.last?.noteID ?? NoteID(), cppID: completionID, what: "A039 completion orders the second target by note")
    report.expectEqual(expected: 110, actual: payload.last?.velocity ?? -1, cppID: completionID, what: "A040 completion carries the second delta value")
    let committed = finishingDocument.setVelocities(payload, expectedRevision: finishingRevision)
    completion = nil
    report.expect(completion == nil && committed == finishingDocument.revision && finishingDocument.note(finishingFirst)?.velocity == 30 && finishingDocument.note(finishingSecond)?.velocity == 110, cppID: completionID, message: "A041 taken completion resets to inactive after one commit")
    report.expect(completion?.preview == nil, cppID: completionID, message: "A042 preview empties after completion")
    let repeated = finishingDocument.setVelocities(payload, expectedRevision: finishingDocument.revision)
    report.expect(repeated == finishingDocument.revision, cppID: completionID, message: "A043 recommitting the consumed payload changes nothing")
    guard let clamped = gestureDocument() else {
        report.fail(clampedID, "the clamped fixture projected no notes")
        return
    }
    let clampedDocument = clamped.0
    let clampedFirst = clamped.1
    let clampedSecond = clamped.2
    var cancellation: VelocityGestureState? = frozenGesture(notes: [frozenNote(clampedFirst, velocity: 40), frozenNote(clampedSecond, velocity: 120)], revision: clampedDocument.revision)
    report.expect(cancellation?.notes.count == 2, cppID: clampedID, message: "A044 freeze captures the clamped pair")
    let clampedFloor = clampedDocument.setVelocities([NoteVelocity(noteID: clampedFirst, velocity: 0)], expectedRevision: clampedDocument.revision)
    report.expect(clampedFloor == clampedDocument.revision && clampedDocument.note(clampedFirst)?.velocity == 1, cppID: clampedID, message: "A045 below-floor commit clamps and applies")
    report.expectEqual(expected: UInt8(1), actual: clampedDocument.note(clampedFirst)?.velocity, cppID: clampedID, what: "A046 committed floor value reads one")
    let clampedCeiling = clampedDocument.setVelocities([NoteVelocity(noteID: clampedFirst, velocity: 128)], expectedRevision: clampedDocument.revision)
    report.expect(clampedCeiling == clampedDocument.revision && clampedDocument.note(clampedFirst)?.velocity == 127, cppID: clampedID, message: "A047 above-ceiling commit clamps and applies")
    report.expectEqual(expected: UInt8(127), actual: clampedDocument.note(clampedFirst)?.velocity, cppID: clampedID, what: "A048 committed ceiling value reads 127")
    VelocityGesturePolicy.applyRelative(&cancellation!, y: axis.velocityToY(30))
    report.expect(cancellation!.relativeActivated, cppID: clampedID, message: "A049 clamped delta motion arms the gesture")
    report.expectEqual(expected: Optional(UInt8(1)), actual: cancellation!.preview[clampedFirst], cppID: clampedID, what: "A050 clamped delta floors the first preview")
    report.expectEqual(expected: Optional(UInt8(70)), actual: cancellation!.preview[clampedSecond], cppID: clampedID, what: "A051 clamped delta moves the second preview from its origin")
    let revisionBeforeCancel = clampedDocument.revision
    cancellation = nil
    report.expect(cancellation == nil && clampedDocument.revision == revisionBeforeCancel, cppID: clampedID, message: "A052 cancel while active clears the gesture and commits nothing")
    report.expect(cancellation?.notes.isEmpty ?? true, cppID: clampedID, message: "A053 cancelled gesture holds no targets")
    report.expect(cancellation?.preview.isEmpty ?? true, cppID: clampedID, message: "A054 preview empties after cancel")
    report.expect(VelocityGesturePolicy.updates(frozenGesture(notes: [], revision: revisionBeforeCancel)).isEmpty, cppID: clampedID, message: "A055 completion with no targets carries nothing")
    cancellation = nil
    report.expect(cancellation == nil && clampedDocument.revision == revisionBeforeCancel, cppID: clampedID, message: "A056 second cancel changes nothing")
}
