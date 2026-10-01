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
        guard let gesture = VelocityGestureState(kind: notes.isEmpty ? .paint : .relative,
                                                revision: revision, track: 0, notes: notes,
                                                axis: axis, detentUnlock: true, activationDistance: 0,
                                                pressX: 0, pressY: pressY) else {
            preconditionFailure("valid gesture fixture")
        }
        return gesture
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
    var empty = frozenGesture(notes: [], revision: 0)
    VelocityGesturePolicy.applyRelative(&empty, y: pressY - 10)
    report.expect(empty.preview.isEmpty && !empty.relativeActivated, cppID: lifecycleID, message: "A002 relative motion with no targets previews nothing")
    report.expect(VelocityGesturePolicy.updates(empty).isEmpty, cppID: lifecycleID, message: "A004 completion with no targets carries nothing")
    guard let probe = gestureDocument() else {
        report.fail(lifecycleID, "the lifecycle probe fixture projected no notes")
        return
    }
    let probeDocument = probe.0
    let probeFirst = probe.1
    let probeSecond = probe.2
    let probeUnassigned = probeDocument.setVelocities([NoteVelocity(noteID: NoteID(), velocity: 40)], expectedRevision: probeDocument.revision)
    report.expect(probeUnassigned == nil, cppID: lifecycleID, message: "A007 unassigned commit rejects")
    let rejectedBaseline = DocumentSnapshot(probeDocument)
    func candidate(_ notes: [VelocityFrozenNote]) -> VelocityGestureState? {
        VelocityGestureState(kind: .relative, revision: probeDocument.revision, track: 0,
                             notes: notes, axis: axis, detentUnlock: true,
                             activationDistance: 0, pressX: 0, pressY: pressY)
    }
    let first = frozenNote(probeFirst, velocity: 40)
    let second = frozenNote(probeSecond, velocity: 120)
    report.expect(candidate([]) == nil, cppID: lifecycleID, message: "A006 empty relative target rejects")
    report.expect(candidate([frozenNote(NoteID(), velocity: 40)]) == nil
                      && DocumentSnapshot(probeDocument) == rejectedBaseline,
                  cppID: lifecycleID, message: "A012 unassigned freeze leaves no transaction")
    report.expect(candidate([frozenNote(probeFirst, velocity: 0)]) == nil, cppID: lifecycleID, message: "A008 below-floor frozen target rejects")
    report.expect(candidate([frozenNote(probeFirst, velocity: 128)]) == nil, cppID: lifecycleID, message: "A009 above-ceiling frozen target rejects")
    report.expect(candidate([first, first]) == nil, cppID: lifecycleID, message: "A010 duplicate frozen target rejects")
    report.expect(candidate([first, second, second]) == nil, cppID: lifecycleID, message: "A011 longer duplicate frozen target rejects")
    guard let live = gestureDocument() else {
        report.fail(lifecycleID, "the lifecycle freeze fixture projected no notes")
        return
    }
    let liveFirst = live.1
    let liveSecond = live.2
    let lifecycle = frozenGesture(notes: [frozenNote(liveSecond, velocity: 120),
                                          frozenNote(liveFirst, velocity: 40)], revision: live.0.revision)
    report.expect(lifecycle.notes.count == 2, cppID: lifecycleID, message: "A013 freeze accepts an unsorted target pair")
    report.expectEqual(expected: Optional(UInt8(40)), actual: lifecycle.previewVelocity(liveFirst), cppID: lifecycleID, what: "A015 first frozen target holds its begin value")
    report.expectEqual(expected: Optional(UInt8(120)), actual: lifecycle.previewVelocity(liveSecond), cppID: lifecycleID, what: "A016 second frozen target holds its begin value")
    guard let atomic = gestureDocument() else {
        report.fail(atomicityID, "the atomicity fixture projected no notes")
        return
    }
    let atomicDocument = atomic.0
    let atomicFirst = atomic.1
    let atomicSecond = atomic.2
    var atomicity = frozenGesture(notes: [frozenNote(atomicFirst, velocity: 40), frozenNote(atomicSecond, velocity: 120)], revision: atomicDocument.revision)
    report.expect(atomicity.notes.count == 2, cppID: atomicityID, message: "A019 freeze captures the atomicity pair")
    let unknownTarget = NoteID(max(atomicFirst.rawValue, atomicSecond.rawValue) + 1000)
    report.expect(!atomicity.updatePreview([NoteVelocity(noteID: atomicFirst, velocity: 100),
                                            NoteVelocity(noteID: unknownTarget, velocity: 64)]),
                  cppID: atomicityID, message: "A020 unknown preview target rejects atomically")
    report.expect(atomicity.previewVelocity(atomicFirst) == 40 && atomicity.preview.isEmpty, cppID: atomicityID, message: "A021 rejected preview retains first original")
    report.expectEqual(expected: Optional(UInt8(120)), actual: atomicity.previewVelocity(atomicSecond), cppID: atomicityID, what: "A022 rejected preview retains second original")
    report.expect(!atomicity.updatePreview([]), cppID: atomicityID, message: "A023 empty preview update rejects")
    report.expect(!atomicity.updatePreview([NoteVelocity(noteID: atomicFirst, velocity: 100),
                                            NoteVelocity(noteID: atomicFirst, velocity: 110)]),
                  cppID: atomicityID, message: "A024 duplicate preview update rejects")
    report.expect(atomicity.previewVelocity(atomicFirst) == 40 && atomicity.preview.isEmpty, cppID: atomicityID, message: "A025 duplicate rejection retains first original")
    report.expectEqual(expected: Optional(UInt8(120)), actual: atomicity.previewVelocity(atomicSecond), cppID: atomicityID, what: "A026 duplicate rejection retains second original")
    report.expect(atomicity.updatePreview([NoteVelocity(noteID: atomicFirst, velocity: 70)]),
                  cppID: atomicityID, message: "a valid update stages one frozen target at 70")
    let rejectedAfterStaging = !atomicity.updatePreview([
        NoteVelocity(noteID: atomicFirst, velocity: 80),
        NoteVelocity(noteID: unknownTarget, velocity: 90),
    ]) && !atomicity.updatePreview([
        NoteVelocity(noteID: atomicFirst, velocity: 80),
        NoteVelocity(noteID: atomicFirst, velocity: 90),
    ]) && !atomicity.updatePreview([
        NoteVelocity(noteID: atomicFirst, velocity: 80),
        NoteVelocity(noteID: unknownTarget, velocity: 128),
    ])
    report.expect(rejectedAfterStaging && atomicity.previewVelocity(atomicFirst) == 70
                      && atomicity.previewVelocity(atomicSecond) == 120
                      && atomicity.preview.count == 1,
                  cppID: atomicityID,
                  message: "rejected mixed batches retain the previous draft and untouched original")
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
    report.expect(completion?.updatePreview([NoteVelocity(noteID: finishingFirst, velocity: 100)]) == true,
                  cppID: completionID, message: "A028 absolute preview applies to the commit payload")
    let absolute = VelocityGesturePolicy.updates(completion!)
    report.expect(absolute.contains(where: { $0.noteID == finishingFirst && $0.velocity == 100 }),
                  cppID: completionID, message: "A029 first preview takes the absolute value")
    report.expect(completion?.previewVelocity(finishingSecond) == 120 && completion?.preview[finishingSecond] == nil,
                  cppID: completionID, message: "A030 untouched target keeps its frozen begin value")
    VelocityGesturePolicy.applyRelative(&completion!, y: axis.velocityToY(70))
    report.expect(completion!.relativeActivated, cppID: completionID, message: "A031 relative motion past activation arms the gesture")
    report.expectEqual(expected: Optional(UInt8(30)), actual: completion!.preview[finishingFirst], cppID: completionID, what: "A032 first preview measures the delta from its origin")
    report.expectEqual(expected: Optional(UInt8(110)), actual: completion!.preview[finishingSecond], cppID: completionID, what: "A033 second preview measures the delta from its origin")
    let payload = VelocityGesturePolicy.updates(completion!)
    report.expectEqual(expected: finishingRevision, actual: completion!.revision, cppID: completionID, what: "A035 completion carries the begin revision")
    report.expectEqual(expected: 2, actual: payload.count, cppID: completionID, what: "A036 completion carries both targets")
    report.expectEqual(expected: finishingFirst, actual: payload.first?.noteID ?? NoteID(), cppID: completionID, what: "A037 completion orders the first target by note")
    report.expectEqual(expected: 30, actual: payload.first?.velocity ?? -1, cppID: completionID, what: "A038 completion carries the first delta value")
    report.expectEqual(expected: finishingSecond, actual: payload.last?.noteID ?? NoteID(), cppID: completionID, what: "A039 completion orders the second target by note")
    report.expectEqual(expected: 110, actual: payload.last?.velocity ?? -1, cppID: completionID, what: "A040 completion carries the second delta value")
    let committed = finishingDocument.setVelocities(payload, expectedRevision: finishingRevision)
    completion = nil
    report.expect(completion == nil && committed == finishingDocument.revision && finishingDocument.note(finishingFirst)?.velocity == 30 && finishingDocument.note(finishingSecond)?.velocity == 110, cppID: completionID, message: "A041 taken completion resets to inactive after one commit")
    guard let clamped = gestureDocument() else {
        report.fail(clampedID, "the clamped fixture projected no notes")
        return
    }
    let clampedDocument = clamped.0
    let clampedFirst = clamped.1
    let clampedSecond = clamped.2
    var cancellation: VelocityGestureState? = frozenGesture(notes: [frozenNote(clampedFirst, velocity: 40), frozenNote(clampedSecond, velocity: 120)], revision: clampedDocument.revision)
    report.expect(cancellation?.notes.count == 2, cppID: clampedID, message: "A044 freeze captures the clamped pair")
    report.expect(cancellation?.updatePreview([NoteVelocity(noteID: clampedFirst, velocity: 0)]) == true,
                  cppID: clampedID, message: "A045 below-floor preview clamps to one")
    report.expectEqual(expected: Optional(UInt8(1)), actual: cancellation?.previewVelocity(clampedFirst),
                       cppID: clampedID, what: "A046 clamped floor reads one")
    report.expect(cancellation?.updatePreview([NoteVelocity(noteID: clampedFirst, velocity: 128)]) == true,
                  cppID: clampedID, message: "A047 above-ceiling preview clamps to 127")
    report.expectEqual(expected: Optional(UInt8(127)), actual: cancellation?.previewVelocity(clampedFirst),
                       cppID: clampedID, what: "A048 clamped ceiling reads 127")
    VelocityGesturePolicy.applyRelative(&cancellation!, y: axis.velocityToY(30))
    report.expect(cancellation!.relativeActivated, cppID: clampedID, message: "A049 clamped delta motion arms the gesture")
    report.expectEqual(expected: Optional(UInt8(1)), actual: cancellation!.preview[clampedFirst], cppID: clampedID, what: "A050 clamped delta floors the first preview")
    report.expectEqual(expected: Optional(UInt8(70)), actual: cancellation!.preview[clampedSecond], cppID: clampedID, what: "A051 clamped delta moves the second preview from its origin")
    let revisionBeforeCancel = clampedDocument.revision
    cancellation = nil
    report.expect(cancellation == nil && clampedDocument.revision == revisionBeforeCancel, cppID: clampedID, message: "A052 cancel while active clears the gesture and commits nothing")
}
