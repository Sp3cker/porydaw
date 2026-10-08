import PorydawCore

private func twoTrackFile() -> MidiFile {
    MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [.meta(type: 0x01, data: Array("contract fixture".utf8))],
                endTick: 48),
            MidiChunk(
                events: [
                    .channel(status: 0xC0, data0: 1),
                    .channel(status: 0x90, data0: 60, data1: 100),
                    .channel(status: 0x90, data0: 60, data1: 90),
                    .channel(tick: 12, status: 0x80, data0: 60),
                    .channel(tick: 24, status: 0x80, data0: 60),
                ], endTick: 48),
            MidiChunk(events: [.channel(status: 0xC1, data0: 2)], endTick: 48),
        ])
}

private func historyGestureFile() -> MidiFile {
    MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .channel(status: 0xC0, data0: 1),
                    .channel(status: 0x90, data0: 60, data1: 100),
                    .channel(status: 0x90, data0: 64, data1: 90),
                    .channel(tick: 12, status: 0x80, data0: 60),
                    .channel(tick: 24, status: 0x80, data0: 64),
                ], endTick: 48)
        ])
}

@MainActor
func documentHistoryContracts(_ report: CheckReport) {
    documentLoadPublicationContract(report)
    do { try documentSavedIdentityContract(report) } catch {
        report.fail("editcheck/EditCheckTest::documentSavedIdentity", "save history failed: \(error)")
    }
    do { try documentPublicationNetZeroContract(report) } catch {
        report.fail("editcheck/EditCheckTest::documentPublicationNetZero", "net-zero history failed: \(error)")
    }
    do { try documentCrossingIdentitiesContract(report) } catch {
        report.fail("editcheck/EditCheckTest::documentCrossingIdentities", "crossing history failed: \(error)")
    }
    do { try documentMergedOverlapContract(report) } catch {
        report.fail("editcheck/EditCheckTest::documentMergedOverlapPublication", "overlap history failed: \(error)")
    }
    do { try historyEvictionProjectionContract(report) } catch {
        report.fail("editcheck/EditCheckTest::historyEvictionProjection", "eviction projection failed: \(error)")
    }
    do { try historySavedProjectionContract(report) } catch {
        report.fail("editcheck/EditCheckTest::historySavedProjection", "saved projection failed: \(error)")
    }
    do { try historyLabelProjectionContract(report) } catch {
        report.fail("editcheck/EditCheckTest::historyLabelProjection", "label projection failed: \(error)")
    }
    do { try historyRevisionProjectionContract(report) } catch {
        report.fail("editcheck/EditCheckTest::historyRevisionProjection", "revision projection failed: \(error)")
    }
}

@MainActor
private func documentLoadPublicationContract(_ report: CheckReport) {
    let id = "editcheck/EditCheckTest::documentLoadPublication"
    let document = SongDocument(file: twoTrackFile())
    // C++ observes the remap-then-change signals during stage(); Swift has no
    // post-construction load ingress or observer attachment before init finishes.
    report.expectEqual(
        expected: UInt64(1), actual: document.revision, cppID: id,
        what: "A002 constructed document starts at revision one")
    report.expectEqual(
        expected: 3, actual: document.state.file.chunks.count, cppID: id,
        what: "A008 constructed document retains three MIDI chunks")
    report.expectEqual(
        expected: 2, actual: document.engineTracks.usedTrackCount, cppID: id,
        what: "A009 constructed document exposes two engine tracks")
}

@MainActor
private func documentSavedIdentityContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::documentSavedIdentity"
    let document = SongDocument(file: twoTrackFile())
    let saved = try document.captureSave()
    document.didSave(saved)
    report.expect(!document.isDirty, cppID: id, message: "A102 saving current identity is clean")
    document.editTempo(
        TempoEdit(add: [
            TempoPoint(
                tick: 96,
                microsecondsPerQuarterNote: 60_000_000 / 140)
        ]))
    report.expect(document.isDirty, cppID: id, message: "A103 tempo edit dirties saved identity")
    let edited = try document.captureSave()
    report.expect(
        edited.bytes != saved.bytes && edited.identity != saved.identity,
        cppID: id, message: "A104 edited snapshot differs from the saved snapshot")
    report.expect(
        document.history.undoDocument(), cppID: id,
        message: "saved tempo edit can be undone")
    report.expect(!document.isDirty, cppID: id, message: "A105 undo returns to saved identity")
    report.expect(
        document.history.redoDocument(), cppID: id,
        message: "saved tempo edit can be redone")
    report.expect(document.isDirty, cppID: id, message: "A106 redo leaves initial save point")
    document.didSave(try document.captureSave())
    report.expect(
        document.history.undoDocument(), cppID: id,
        message: "new save point can be left by undo")
    report.expect(document.isDirty, cppID: id, message: "A107 undo away from new save is dirty")
    report.expect(
        document.history.redoDocument(), cppID: id,
        message: "new save point can be restored by redo")
    report.expect(!document.isDirty, cppID: id, message: "A108 redo back to new save is clean")
}

@MainActor
private func documentPublicationNetZeroContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::documentPublicationNetZero"
    let document = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(
                    events: [
                        .channel(status: 0xC0, data0: 1),
                        .channel(status: 0x90, data0: 70, data1: 100),
                        .channel(status: 0x90, data0: 69, data1: 100),
                        .channel(tick: 2, status: 0x80, data0: 69),
                        .channel(tick: 4, status: 0x80, data0: 70),
                    ], endTick: 8)
            ]))
    guard let movedID = document.notes(in: 0).first(where: { $0.pitch == 69 })?.id else {
        report.fail(id, "initial pitch-69 note is missing")
        return
    }
    let baseline = try document.state.file.encoded()
    let beforeDepth = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    var publications: [DocumentChange] = []
    document.onChange = { publications.append($0) }
    defer { document.onChange = nil }
    let group = HistoryGroup()
    let firstRevision = document.revision
    document.moveNotes([movedID], byTicks: 0, byKeys: 1, group: group)
    report.expectEqual(
        expected: firstRevision + 1, actual: document.revision, cppID: id,
        what: "A195 first move advances revision")
    report.expect(
        publications.count == 1 && publications.last?.revision == document.revision,
        cppID: id, message: "A196 first move publishes exactly once")
    report.expect(
        publications.last != nil && publications.last?.trackRemap == nil, cppID: id,
        message: "A197 note-only move publishes no track remap")
    report.expect(
        document.note(movedID)?.pitch == 70, cppID: id,
        message: "moved note remains findable at pitch 70")
    report.expectEqual(
        expected: beforeDepth + 1,
        actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
        cppID: id, what: "A194 first move adds one history entry")

    let inverseRevision = document.revision
    let inversePublications = publications.count
    // Reused groups take the cumulative offset from the gesture origin.
    document.moveNotes([movedID], byTicks: 0, byKeys: 0, group: group)
    report.expectEqual(
        expected: inverseRevision + 1, actual: document.revision, cppID: id,
        what: "A199 inverse move advances revision")
    report.expect(
        publications.count == inversePublications + 1 && publications.last?.revision == document.revision,
        cppID: id, message: "A200 inverse move publishes exactly once")
    report.expect(
        publications.last != nil && publications.last?.trackRemap == nil, cppID: id,
        message: "inverse note move publishes no track remap")
    report.expectEqual(
        expected: beforeDepth,
        actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
        cppID: id, what: "A201 return to origin drops the entry")
    report.expect(
        !document.history.canUndo && !document.history.canRedo, cppID: id,
        message: "A202-A203 return to origin leaves no undo or redo")
    report.expectEqual(
        expected: baseline, actual: try document.state.file.encoded(), cppID: id,
        what: "A204 return to origin restores exact MIDI bytes")
    let frozenRevision = document.revision
    let frozenPublications = publications.count
    let rejectedUndo = !document.history.undoDocument()
    let rejectedRedo = !document.history.redoDocument()
    report.expect(
        rejectedUndo && rejectedRedo, cppID: id,
        message: "empty history rejects undo and redo")
    report.expectEqual(
        expected: baseline, actual: try document.state.file.encoded(), cppID: id,
        what: "A205 rejected undo and redo preserve bytes")
    report.expectEqual(
        expected: frozenRevision, actual: document.revision, cppID: id,
        what: "A206 rejected undo and redo preserve revision")
    report.expectEqual(
        expected: frozenPublications, actual: publications.count, cppID: id,
        what: "A207-A208 rejected undo and redo publish neither change nor remap")
}

@MainActor
private func documentCrossingIdentitiesContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::documentCrossingIdentities"
    let document = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(
                    events: [
                        .channel(status: 0xC0, data0: 1),
                        .channel(status: 0x90, data0: 60, data1: 100),
                        .channel(status: 0x90, data0: 61, data1: 100),
                    ], endTick: 8)
            ]))
    guard let idA = document.notes(in: 0).first(where: { $0.pitch == 60 })?.id,
        let idB = document.notes(in: 0).first(where: { $0.pitch == 61 })?.id
    else {
        report.fail(id, "initial pitch-60 and pitch-61 identities are missing")
        return
    }
    report.expect(
        document.note(idA)?.isUnterminated == true && document.note(idB)?.isUnterminated == true, cppID: id,
        message: "A162-A163 both original notes are unterminated")
    let beforeDepth = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    var before = document.revision
    document.moveNotes([idA], byTicks: 0, byKeys: 1)
    report.expectEqual(
        expected: before + 1, actual: document.revision, cppID: id,
        what: "A165 first crossing move advances revision")
    report.expect(
        document.note(idA)?.pitch == 61 && document.note(idB)?.pitch == 61,
        cppID: id, message: "A166-A169 both IDs remain findable at pitch 61")
    report.expectEqual(
        expected: beforeDepth + 1,
        actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
        cppID: id, what: "A164 first move adds one history entry")
    before = document.revision
    document.moveNotes([idB], byTicks: 0, byKeys: -1)
    report.expectEqual(
        expected: before + 1, actual: document.revision, cppID: id,
        what: "A171 second crossing move advances revision")
    report.expect(
        document.note(idA)?.pitch == 61 && document.note(idB)?.pitch == 60,
        cppID: id, message: "A172-A175 IDs survive the crossed pitches")
    report.expectEqual(
        expected: beforeDepth + 2,
        actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
        cppID: id, what: "A170 second move adds another history entry")
    before = document.revision
    report.expect(document.history.undoDocument(), cppID: id, message: "first crossing undo succeeds")
    report.expectEqual(
        expected: before + 1, actual: document.revision, cppID: id,
        what: "A176 first crossing undo advances revision")
    report.expect(
        document.note(idA)?.pitch == 61 && document.note(idB)?.pitch == 61,
        cppID: id, message: "A177-A180 first undo restores both IDs at pitch 61")
    before = document.revision
    report.expect(document.history.undoDocument(), cppID: id, message: "second crossing undo succeeds")
    report.expectEqual(
        expected: before + 1, actual: document.revision, cppID: id,
        what: "A181 second crossing undo advances revision")
    report.expect(
        document.note(idA)?.pitch == 60 && document.note(idB)?.pitch == 61,
        cppID: id, message: "A182-A185 second undo restores original pitches and IDs")
    before = document.revision
    report.expect(document.history.redoDocument(), cppID: id, message: "first crossing redo succeeds")
    report.expectEqual(
        expected: before + 1, actual: document.revision, cppID: id,
        what: "A186 first crossing redo advances revision")
    report.expect(
        document.note(idA)?.pitch == 61 && document.note(idB)?.pitch == 61,
        cppID: id, message: "first redo restores intermediate IDs and pitches")
    before = document.revision
    report.expect(document.history.redoDocument(), cppID: id, message: "second crossing redo succeeds")
    report.expectEqual(
        expected: before + 1, actual: document.revision, cppID: id,
        what: "A187 second crossing redo advances revision")
    report.expect(
        document.note(idA)?.pitch == 61 && document.note(idB)?.pitch == 60,
        cppID: id, message: "A188-A191 redo restores crossed pitches and original IDs")
}

@MainActor
private func documentMergedOverlapContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::documentMergedOverlapPublication"
    let document = SongDocument(
        file: MidiFile(
            division: 24,
            chunks: [
                MidiChunk(
                    events: [
                        .channel(status: 0xC0, data0: 1),
                        .channel(status: 0x90, data0: 70, data1: 100),
                        .channel(status: 0x90, data0: 69, data1: 100),
                        .channel(tick: 2, status: 0x80, data0: 69),
                        .channel(tick: 4, status: 0x80, data0: 70),
                    ], endTick: 8)
            ]))
    guard let movedID = document.notes(in: 0).first(where: { $0.pitch == 69 })?.id,
        let survivorID = document.notes(in: 0).first(where: { $0.pitch == 70 })?.id
    else {
        report.fail(id, "initial moving and surviving notes are missing")
        return
    }
    let baseline = try document.state.file.encoded()
    let beforeDepth = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    var publications: [DocumentChange] = []
    document.onChange = { publications.append($0) }
    defer { document.onChange = nil }
    let group = HistoryGroup()
    for (step, pitch, survivorTick, survivorDuration) in [
        (1, 70, 2, 2), (2, 71, 0, 4), (3, 72, 0, 4),
    ] {
        let beforeRevision = document.revision
        let beforePublications = publications.count
        document.moveNotes([movedID], byTicks: 0, byKeys: step, group: group)
        report.expectEqual(
            expected: beforeRevision + 1, actual: document.revision, cppID: id,
            what: "A212/A219/A226 grouped move \(step) advances revision")
        report.expect(
            publications.count == beforePublications + 1 && publications.last?.revision == document.revision
                && publications.last?.trackRemap == nil,
            cppID: id, message: "A213-A214/A220-A221/A227-A228 grouped move \(step) publishes change only")
        report.expect(
            document.note(movedID)?.tick == 0 && document.note(movedID)?.pitch == UInt8(pitch), cppID: id,
            message: "A215/A222/A229 grouped move \(step) retains moved identity and pitch")
        report.expect(
            document.note(survivorID)?.tick == Tick(survivorTick) && document.note(survivorID)?.pitch == 70
                && document.note(survivorID)?.duration == Tick(survivorDuration), cppID: id,
            message: "A216-A217/A223-A224/A230-A231 survivor trims then restores from origin")
        report.expectEqual(
            expected: beforeDepth + 1,
            actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
            cppID: id, what: "A211/A218/A225 grouped moves keep one history entry")
    }
    var beforeRevision = document.revision
    var beforePublications = publications.count
    report.expect(
        document.history.undoDocument(), cppID: id,
        message: "one undo reverses all three grouped moves")
    report.expectEqual(
        expected: beforeRevision + 1, actual: document.revision, cppID: id,
        what: "A232 grouped undo advances revision")
    report.expect(
        publications.count == beforePublications + 1 && publications.last?.trackRemap == nil, cppID: id,
        message: "A233-A234 grouped undo publishes change only")
    report.expect(
        document.note(movedID)?.pitch == 69 && document.note(movedID)?.tick == 0
            && document.note(survivorID)?.pitch == 70 && document.note(survivorID)?.tick == 0
            && document.note(survivorID)?.duration == 4, cppID: id,
        message: "A235-A237 one undo restores both original notes")
    report.expectEqual(
        expected: baseline, actual: try document.state.file.encoded(), cppID: id,
        what: "grouped undo restores baseline MIDI bytes")
    beforeRevision = document.revision
    beforePublications = publications.count
    report.expect(
        document.history.redoDocument(), cppID: id,
        message: "one redo restores all three grouped moves")
    report.expectEqual(
        expected: beforeRevision + 1, actual: document.revision, cppID: id,
        what: "A238 grouped redo advances revision")
    report.expect(
        publications.count == beforePublications + 1 && publications.last?.trackRemap == nil, cppID: id,
        message: "A239-A240 grouped redo publishes change only")
    report.expect(
        document.note(movedID)?.pitch == 72, cppID: id,
        message: "A241 grouped redo returns to pitch 72")
    beforeRevision = document.revision
    beforePublications = publications.count
    document.moveNotes([movedID], byTicks: 0, byKeys: 1)
    report.expectEqual(
        expected: beforeRevision + 1, actual: document.revision, cppID: id,
        what: "A242 ungrouped fourth move advances revision")
    report.expect(
        publications.count == beforePublications + 1 && publications.last?.trackRemap == nil, cppID: id,
        message: "A243-A244 fourth move publishes change only")
    report.expect(
        document.note(movedID)?.pitch == 73, cppID: id,
        message: "fourth move reaches pitch 73")
    report.expectEqual(
        expected: beforeDepth + 2,
        actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
        cppID: id, what: "ungrouped fourth move adds a second history entry")
    beforeRevision = document.revision
    beforePublications = publications.count
    report.expect(
        document.history.undoDocument(), cppID: id,
        message: "fourth move undoes separately")
    report.expectEqual(
        expected: beforeRevision + 1, actual: document.revision, cppID: id,
        what: "A245 fourth-move undo advances revision")
    report.expect(
        publications.count == beforePublications + 1 && publications.last?.trackRemap == nil, cppID: id,
        message: "A246-A247 fourth-move undo publishes change only")
    report.expect(
        document.note(movedID)?.pitch == 72, cppID: id,
        message: "undo fourth move returns to grouped pitch 72")
    beforeRevision = document.revision
    beforePublications = publications.count
    report.expect(
        document.history.redoDocument(), cppID: id,
        message: "fourth move redoes separately")
    report.expectEqual(
        expected: beforeRevision + 1, actual: document.revision, cppID: id,
        what: "A248 fourth-move redo advances revision")
    report.expect(
        publications.count == beforePublications + 1 && publications.last?.trackRemap == nil, cppID: id,
        message: "A249-A250 fourth-move redo publishes change only")
    report.expect(
        document.note(movedID)?.pitch == 73, cppID: id,
        message: "redo fourth move returns to pitch 73")
}

@MainActor
private func historyEvictionProjectionContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::historyEvictionProjection"
    let document = SongDocument(file: twoTrackFile())
    let history = document.history
    let opened = history.currentIdentity
    document.didSave(try document.captureSave())
    document.setChunkEnd(1, tick: 49)
    let first = history.currentIdentity
    for offset in 2...513 { document.setChunkEnd(1, tick: Tick(48 + offset)) }
    let tip = history.currentIdentity
    report.expect(
        SongHistory.stepLimit == 512 && history.undoCount == 512 && history.undoIndex == 512,
        cppID: id, message: "513 appends retain 512 applied entries")
    report.expect(
        history.hasEvictedSteps && document.isDirty && !history.baseIsSaved,
        cppID: id, message: "eviction advances the base beyond the on-open save")
    report.expectEqual(
        expected: 514, actual: history.revision, cppID: id,
        what: "save plus 513 appends includes eviction in a single append bump")
    report.expect(
        !history.contains(opened) && history.contains(first) && history.contains(tip),
        cppID: id, message: "identity lookup retains the advanced base and live tip, not opened")
    report.expect(
        history.step(at: -1) == nil && history.step(at: 512) == nil,
        cppID: id, message: "projection rejects offsets outside the retained log")
    for _ in 0..<512 { _ = history.undoDocument() }
    report.expect(
        history.undoIndex == 0 && history.undoCount == 512 && history.canRedo,
        cppID: id, message: "undo-to-base preserves the full redo tail after eviction")
    report.expect(
        history.currentIdentity == first && document.isDirty,
        cppID: id, message: "undo-to-zero stays dirty against an evicted on-open save")
    report.expect(
        history.step(at: 0)?.applied == false && history.step(at: 0)?.isCurrent == false,
        cppID: id, message: "no retained row is current or applied at the base")
    for _ in 0..<512 { _ = history.redoDocument() }
    report.expect(
        history.currentIdentity == tip && history.undoIndex == 512,
        cppID: id, message: "redo restores the exact retained tip without further eviction")
    _ = history.undoDocument()
    _ = history.undoDocument()
    document.setChunkEnd(1, tick: 900)
    report.expect(
        history.undoCount == 511 && history.undoIndex == 511 && !history.canRedo,
        cppID: id, message: "record after undo discards only the redo tail")
    let bankHistory = SongHistory()
    for value in 1...513 {
        bankHistory.recordConfirmedBank(ProjectionBankAction(before: -1, after: value))
    }
    report.expect(
        bankHistory.undoCount == 512 && bankHistory.undoIndex == 512
            && bankHistory.revision == 513 && bankHistory.hasEvictedSteps,
        cppID: id, message: "nonmerged bank appends share the cap and single revision bump")
}

@MainActor
private func historySavedProjectionContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::historySavedProjection"
    let document = SongDocument(file: twoTrackFile())
    let history = document.history
    document.didSave(try document.captureSave())
    report.expect(
        history.baseIsSaved && !history.hasEvictedSteps && history.undoCount == 0,
        cppID: id, message: "save at open marks the unevicted base")
    document.setChunkEnd(1, tick: 49)
    document.didSave(try document.captureSave())
    let saved = history.currentIdentity
    report.expect(
        history.step(at: 0)?.isSaved == true && !history.baseIsSaved,
        cppID: id, message: "save marks the document step rather than the base")
    history.recordConfirmedBank(ProjectionBankAction(before: 0, after: 1))
    report.expect(
        history.step(at: 0)?.isSaved == true && history.step(at: 1)?.isSaved == false,
        cppID: id, message: "a bank step sharing the saved identity never carries its marker")
    _ = try runBlocking { try await history.undo() }
    _ = history.undoDocument()
    report.expect(
        history.step(at: 0)?.isSaved == true && !history.baseIsSaved && document.isDirty,
        cppID: id, message: "save-then-undo keeps the marker on the unapplied document step")
    document.didSave(try document.captureSave())
    report.expect(
        history.baseIsSaved && history.step(at: 0)?.isSaved == false,
        cppID: id, message: "saving after undo moves the marker back to the base")
    _ = history.redoDocument()
    document.didSave(try document.captureSave())
    for offset in 2...513 { document.setChunkEnd(1, tick: Tick(48 + offset)) }
    report.expect(
        history.baseIsSaved && history.contains(saved),
        cppID: id, message: "the last evicted saved state can still be the kept base")
    document.setChunkEnd(1, tick: 800)
    var anySaved = history.baseIsSaved
    for offset in 0..<history.undoCount {
        anySaved = anySaved || history.step(at: offset)?.isSaved == true
    }
    report.expect(
        !history.contains(saved) && !anySaved && document.isDirty,
        cppID: id, message: "a save older than the kept base leaves no saved marker anywhere")
}

@MainActor
private func historyLabelProjectionContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::historyLabelProjection"
    let document = SongDocument(file: twoTrackFile())
    let history = document.history
    document.renameTrack(0, to: "Lead")
    report.expectEqual(
        expected: "Rename track", actual: history.step(at: 0)?.label, cppID: id,
        what: "track-management steps use their fixed phrase")
    let added = try document.addNotes([
        NewNote(track: 0, tick: 30, pitch: 65, duration: 4, velocity: 80)
    ])
    report.expectEqual(
        expected: "Track Lead - edited 1 note", actual: history.step(at: 1)?.label, cppID: id,
        what: "single-track note insertion captures a singular note label")
    document.renameTrack(0, to: "Renamed")
    report.expectEqual(
        expected: "Track Lead - edited 1 note", actual: history.step(at: 1)?.label, cppID: id,
        what: "later rename cannot rewrite an earlier captured label")
    let pair = try document.addNotes([
        NewNote(track: 0, tick: 36, pitch: 66, duration: 4, velocity: 80),
        NewNote(track: 0, tick: 36, pitch: 67, duration: 4, velocity: 80),
    ])
    report.expectEqual(
        expected: "Track Renamed - edited 2 notes", actual: history.step(at: 3)?.label, cppID: id,
        what: "two note insertions count note-ons, not their note ends")
    _ = document.setVelocities(
        pair.map { NoteVelocity(noteID: $0, velocity: 75) },
        expectedRevision: document.revision)
    report.expectEqual(
        expected: "Track Renamed - edited 2 notes", actual: history.step(at: 4)?.label, cppID: id,
        what: "replacement note-ons count each identity only once")
    document.moveNotes(added, byTicks: 1, byKeys: 0)
    report.expectEqual(
        expected: "Track Renamed - edited 1 note", actual: history.step(at: 5)?.label, cppID: id,
        what: "note movement uses its ID payload count")
    let group = HistoryGroup()
    document.deleteNotes(pair)
    _ = try document.addNotes([
        NewNote(track: 1, tick: 30, pitch: 70, duration: 4, velocity: 80)
    ])
    report.expectEqual(
        expected: "Track 2 - edited 1 note", actual: history.step(at: 7)?.label, cppID: id,
        what: "unnamed tracks use their one-based engine position")
    _ = try document.addNotes([
        NewNote(track: 0, tick: 42, pitch: 72, duration: 4, velocity: 80),
        NewNote(track: 1, tick: 42, pitch: 73, duration: 4, velocity: 80),
    ])
    report.expectEqual(
        expected: "Edited 2 notes", actual: history.step(at: 8)?.label, cppID: id,
        what: "multi-track changes omit the track prefix")
    document.insertRawEvent(chunk: 1, event: .channel(tick: 40, status: 0xB0, data0: 7, data1: 80))
    report.expectEqual(
        expected: "Track Renamed - edited 1 event", actual: history.step(at: 9)?.label, cppID: id,
        what: "raw event insertion uses singular event")
    guard let eventIndex = document.rawChunks[1].events.firstIndex(where: { $0.typeNibble == 0xB }),
        let programIndex = document.rawChunks[1].events.firstIndex(where: { $0.typeNibble == 0xC })
    else {
        report.fail(id, "inserted controller event is missing")
        return
    }
    document.modifyRawEvent(
        chunk: 1, index: eventIndex,
        event: .channel(tick: 40, status: 0xB0, data0: 7, data1: 81))
    report.expectEqual(
        expected: "Track Renamed - edited 1 event", actual: history.step(at: 10)?.label, cppID: id,
        what: "raw event replacement counts once, not remove plus insert")
    document.deleteRawEvents(chunk: 1, indices: [programIndex, eventIndex])
    report.expectEqual(
        expected: "Track Renamed - edited 2 events", actual: history.step(at: 11)?.label, cppID: id,
        what: "multiple removed events use the plural event label")
    let gesture = SongDocument(file: historyGestureFile())
    let gestureIDs = gesture.notes(in: 0).map(\.id)
    gesture.moveNotes(gestureIDs, byTicks: 1, byKeys: 0, group: group)
    gesture.renameTrack(0, to: "Later")
    let mergedGroup = HistoryGroup()
    gesture.moveNotes(gestureIDs, byTicks: 1, byKeys: 0, group: mergedGroup)
    gesture.moveNotes(gestureIDs, byTicks: 2, byKeys: 0, group: mergedGroup)
    report.expect(
        gesture.history.undoCount == 3
            && gesture.history.step(at: 2)?.label == "Track Later - edited 2 notes",
        cppID: id, message: "merged gesture refreshes its captured label and payload count")
    history.recordConfirmedBank(ProjectionBankAction(before: 0, after: 1))
    report.expectEqual(
        expected: "Edit probe slot 1", actual: history.step(at: 12)?.label, cppID: id,
        what: "bank projection reads the explicit action label")
    history.recordConfirmedBank(ProjectionBankAction(before: 1, after: 2))
    report.expectEqual(
        expected: "Edit probe slot 2", actual: history.step(at: 12)?.label, cppID: id,
        what: "bank merge projects the replacement action's own label")
}

@MainActor
private func historyRevisionProjectionContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::historyRevisionProjection"
    let document = SongDocument(file: historyGestureFile())
    let history = document.history
    let ids = document.notes(in: 0).map(\.id)
    let group = HistoryGroup()
    var revision = history.revision
    document.moveNotes(ids, byTicks: 1, byKeys: 0, group: group)
    report.expectEqual(expected: revision + 1, actual: history.revision, cppID: id, what: "append bumps once")
    revision = history.revision
    document.moveNotes(ids, byTicks: 2, byKeys: 0, group: group)
    report.expectEqual(expected: revision + 1, actual: history.revision, cppID: id, what: "merge replace bumps once")
    revision = history.revision
    document.moveNotes(ids, byTicks: 0, byKeys: 0, group: group)
    report.expectEqual(expected: revision + 1, actual: history.revision, cppID: id, what: "merge removal bumps once")
    revision = history.revision
    _ = history.undoDocument()
    _ = history.redoDocument()
    document.moveNotes(ids, byTicks: 0, byKeys: 0)
    report.expectEqual(
        expected: revision, actual: history.revision, cppID: id, what: "rejected and no-op calls do not bump")
    document.moveNotes(ids, byTicks: 1, byKeys: 0, group: group)
    revision = history.revision
    document.didSave(try document.captureSave())
    report.expectEqual(expected: revision + 1, actual: history.revision, cppID: id, what: "markSaved bumps once")
    document.moveNotes(ids, byTicks: 2, byKeys: 0, group: group)
    report.expectEqual(
        expected: 2, actual: history.undoCount, cppID: id, what: "save seals the adjacent document merge")
    revision = history.revision
    _ = history.undoDocument()
    report.expectEqual(expected: revision + 1, actual: history.revision, cppID: id, what: "document undo bumps once")
    report.expect(
        history.step(at: 0)?.applied == true && history.step(at: 0)?.isCurrent == true
            && history.step(at: 1)?.applied == false && history.step(at: 1)?.isCurrent == false,
        cppID: id, message: "projection flags follow the applied cursor")
    revision = history.revision
    _ = history.redoDocument()
    report.expectEqual(expected: revision + 1, actual: history.revision, cppID: id, what: "document redo bumps once")
    revision = history.revision
    _ = try runBlocking { try await history.undo() }
    report.expectEqual(
        expected: revision + 1, actual: history.revision, cppID: id, what: "async document undo bumps once")
    revision = history.revision
    _ = try runBlocking { try await history.redo() }
    report.expectEqual(
        expected: revision + 1, actual: history.revision, cppID: id, what: "async document redo bumps once")
    _ = history.undoDocument()
    revision = history.revision
    document.setChunkEnd(0, tick: 100)
    report.expectEqual(
        expected: revision + 1, actual: history.revision, cppID: id, what: "redo discard folds into the append bump")
    revision = history.revision
    history.recordConfirmedBank(ProjectionBankAction(before: 0, after: 1))
    report.expectEqual(expected: revision + 1, actual: history.revision, cppID: id, what: "bank append bumps once")
    revision = history.revision
    history.recordConfirmedBank(ProjectionBankAction(before: 1, after: 2))
    report.expectEqual(
        expected: revision + 1, actual: history.revision, cppID: id, what: "bank merge replace bumps once")
    revision = history.revision
    history.recordConfirmedBank(ProjectionBankAction(before: 2, after: 0))
    report.expectEqual(
        expected: revision + 1, actual: history.revision, cppID: id, what: "bank merge removal bumps once")
    history.recordConfirmedBank(ProjectionBankAction(before: 0, after: 1))
    revision = history.revision
    history.sealBankMerge()
    report.expectEqual(expected: revision, actual: history.revision, cppID: id, what: "bank sealing does not bump")
    guard let token = history.beginBankTransition() else {
        report.fail(id, "bank transition did not begin")
        return
    }
    let guardedUndo = try runBlocking { try await history.undo() }
    let guardedRedo = try runBlocking { try await history.redo() }
    report.expect(
        !guardedUndo && !guardedRedo && history.revision == revision,
        cppID: id, message: "transition-guarded replay calls do not bump")
    history.endBankTransition(token)
    report.expectEqual(
        expected: revision, actual: history.revision, cppID: id, what: "transition begin and end do not bump")
    _ = try runBlocking { try await history.undo() }
    report.expectEqual(expected: revision + 1, actual: history.revision, cppID: id, what: "bank undo bumps once")
    revision = history.revision
    _ = try runBlocking { try await history.redo() }
    report.expectEqual(expected: revision + 1, actual: history.revision, cppID: id, what: "bank redo bumps once")
    history.sealBankMerge()
    let stale = ProjectionBankAction(before: 0, after: 1)
    stale.isStale = true
    history.recordConfirmedBank(stale)
    revision = history.revision
    let count = history.undoCount
    _ = try runBlocking { try await history.undo() }
    report.expect(
        history.revision == revision + 1 && history.undoCount == count - 1,
        cppID: id, message: "stale undo removal bumps once")
    let staleRedo = ProjectionBankAction(before: 0, after: 1)
    history.recordConfirmedBank(staleRedo)
    _ = try runBlocking { try await history.undo() }
    staleRedo.isStale = true
    revision = history.revision
    let cursor = history.undoIndex
    _ = try runBlocking { try await history.redo() }
    report.expect(
        history.revision == revision + 1 && history.undoIndex == cursor,
        cppID: id, message: "stale redo removal bumps once without advancing the cursor")
}

@MainActor
private final class ProjectionBankAction: BankHistoryAction {
    let before: Int
    let after: Int
    let historyLabel: String
    var isStale = false
    var isRedundant: Bool { before == after }

    init(before: Int, after: Int) {
        self.before = before
        self.after = after
        historyLabel = "Edit probe slot \(after)"
    }

    func apply(direction _: BankHistoryDirection) async throws {
        if isStale { throw BankHistoryReplayError.staleEntry }
    }

    func merged(with newer: any BankHistoryAction) -> (any BankHistoryAction)? {
        guard let newer = newer as? ProjectionBankAction, after == newer.before else { return nil }
        return ProjectionBankAction(before: before, after: newer.after)
    }
}
