import PorydawCore

private func twoTrackFile() -> MidiFile {
    MidiFile(division: 24, chunks: [
        MidiChunk(events: [.meta(type: 0x01, data: Array("contract fixture".utf8))],
                  endTick: 48),
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 1),
            .channel(status: 0x90, data0: 60, data1: 100),
            .channel(status: 0x90, data0: 60, data1: 90),
            .channel(tick: 12, status: 0x80, data0: 60),
            .channel(tick: 24, status: 0x80, data0: 60),
        ], endTick: 48),
        MidiChunk(events: [.channel(status: 0xC1, data0: 2)], endTick: 48),
    ])
}

@MainActor
func documentHistoryContracts(_ report: CheckReport) {
    documentLoadPublicationContract(report)
    do { try documentSavedIdentityContract(report) }
    catch { report.fail("editcheck/EditCheckTest::documentSavedIdentity", "save history failed: \(error)") }
    do { try documentPublicationNetZeroContract(report) }
    catch { report.fail("editcheck/EditCheckTest::documentPublicationNetZero", "net-zero history failed: \(error)") }
    do { try documentCrossingIdentitiesContract(report) }
    catch { report.fail("editcheck/EditCheckTest::documentCrossingIdentities", "crossing history failed: \(error)") }
    do { try documentMergedOverlapContract(report) }
    catch { report.fail("editcheck/EditCheckTest::documentMergedOverlapPublication", "overlap history failed: \(error)") }
}

@MainActor
private func documentLoadPublicationContract(_ report: CheckReport) {
    let id = "editcheck/EditCheckTest::documentLoadPublication"
    let document = SongDocument(file: twoTrackFile())
    // C++ observes the remap-then-change signals during stage(); Swift has no
    // post-construction load ingress or observer attachment before init finishes.
    report.expectEqual(expected: UInt64(1), actual: document.revision, cppID: id,
                       what: "A002 constructed document starts at revision one")
    report.expectEqual(expected: 3, actual: document.state.file.chunks.count, cppID: id,
                       what: "A008 constructed document retains three MIDI chunks")
    report.expectEqual(expected: 2, actual: document.engineTracks.usedTrackCount, cppID: id,
                       what: "A009 constructed document exposes two engine tracks")
}

@MainActor
private func documentSavedIdentityContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::documentSavedIdentity"
    let document = SongDocument(file: twoTrackFile())
    let saved = try document.captureSave()
    document.didSave(saved)
    report.expect(!document.isDirty, cppID: id, message: "A102 saving current identity is clean")
    document.editTempo(TempoEdit(add: [TempoPoint(tick: 96,
                                                 microsecondsPerQuarterNote: 60_000_000 / 140)]))
    report.expect(document.isDirty, cppID: id, message: "A103 tempo edit dirties saved identity")
    let edited = try document.captureSave()
    report.expect(edited.bytes != saved.bytes && edited.identity != saved.identity,
                  cppID: id, message: "A104 edited snapshot differs from the saved snapshot")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "saved tempo edit can be undone")
    report.expect(!document.isDirty, cppID: id, message: "A105 undo returns to saved identity")
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "saved tempo edit can be redone")
    report.expect(document.isDirty, cppID: id, message: "A106 redo leaves initial save point")
    document.didSave(try document.captureSave())
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "new save point can be left by undo")
    report.expect(document.isDirty, cppID: id, message: "A107 undo away from new save is dirty")
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "new save point can be restored by redo")
    report.expect(!document.isDirty, cppID: id, message: "A108 redo back to new save is clean")
}

@MainActor
private func documentPublicationNetZeroContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::documentPublicationNetZero"
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 1),
            .channel(status: 0x90, data0: 70, data1: 100),
            .channel(status: 0x90, data0: 69, data1: 100),
            .channel(tick: 2, status: 0x80, data0: 69),
            .channel(tick: 4, status: 0x80, data0: 70),
        ], endTick: 8),
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
    report.expectEqual(expected: firstRevision + 1, actual: document.revision, cppID: id,
                       what: "A195 first move advances revision")
    report.expect(publications.count == 1 && publications.last?.revision == document.revision,
                  cppID: id, message: "A196 first move publishes exactly once")
    report.expect(publications.last != nil && publications.last?.trackRemap == nil, cppID: id,
                  message: "A197 note-only move publishes no track remap")
    report.expect(document.note(movedID)?.pitch == 70, cppID: id,
                  message: "moved note remains findable at pitch 70")
    report.expectEqual(expected: beforeDepth + 1,
                       actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A194 first move adds one history entry")

    let inverseRevision = document.revision
    let inversePublications = publications.count
    // Reused groups take the cumulative offset from the gesture origin.
    document.moveNotes([movedID], byTicks: 0, byKeys: 0, group: group)
    report.expectEqual(expected: inverseRevision + 1, actual: document.revision, cppID: id,
                       what: "A199 inverse move advances revision")
    report.expect(publications.count == inversePublications + 1 &&
        publications.last?.revision == document.revision,
        cppID: id, message: "A200 inverse move publishes exactly once")
    report.expect(publications.last != nil && publications.last?.trackRemap == nil, cppID: id,
                  message: "inverse note move publishes no track remap")
    report.expectEqual(expected: beforeDepth,
                       actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A201 return to origin drops the entry")
    report.expect(!document.history.canUndo && !document.history.canRedo, cppID: id,
                  message: "A202-A203 return to origin leaves no undo or redo")
    report.expectEqual(expected: baseline, actual: try document.state.file.encoded(), cppID: id,
                       what: "A204 return to origin restores exact MIDI bytes")
    let frozenRevision = document.revision
    let frozenPublications = publications.count
    let rejectedUndo = !document.history.undoDocument()
    let rejectedRedo = !document.history.redoDocument()
    report.expect(rejectedUndo && rejectedRedo, cppID: id,
                  message: "empty history rejects undo and redo")
    report.expectEqual(expected: baseline, actual: try document.state.file.encoded(), cppID: id,
                       what: "A205 rejected undo and redo preserve bytes")
    report.expectEqual(expected: frozenRevision, actual: document.revision, cppID: id,
                       what: "A206 rejected undo and redo preserve revision")
    report.expectEqual(expected: frozenPublications, actual: publications.count, cppID: id,
                       what: "A207-A208 rejected undo and redo publish neither change nor remap")
}

@MainActor
private func documentCrossingIdentitiesContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::documentCrossingIdentities"
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 1),
            .channel(status: 0x90, data0: 60, data1: 100),
            .channel(status: 0x90, data0: 61, data1: 100),
        ], endTick: 8),
    ]))
    guard let idA = document.notes(in: 0).first(where: { $0.pitch == 60 })?.id,
          let idB = document.notes(in: 0).first(where: { $0.pitch == 61 })?.id else {
        report.fail(id, "initial pitch-60 and pitch-61 identities are missing")
        return
    }
    report.expect(document.note(idA)?.isUnterminated == true &&
        document.note(idB)?.isUnterminated == true, cppID: id,
        message: "A162-A163 both original notes are unterminated")
    let beforeDepth = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    var before = document.revision
    document.moveNotes([idA], byTicks: 0, byKeys: 1)
    report.expectEqual(expected: before + 1, actual: document.revision, cppID: id,
                       what: "A165 first crossing move advances revision")
    report.expect(document.note(idA)?.pitch == 61 && document.note(idB)?.pitch == 61,
                  cppID: id, message: "A166-A169 both IDs remain findable at pitch 61")
    report.expectEqual(expected: beforeDepth + 1,
                       actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A164 first move adds one history entry")
    before = document.revision
    document.moveNotes([idB], byTicks: 0, byKeys: -1)
    report.expectEqual(expected: before + 1, actual: document.revision, cppID: id,
                       what: "A171 second crossing move advances revision")
    report.expect(document.note(idA)?.pitch == 61 && document.note(idB)?.pitch == 60,
                  cppID: id, message: "A172-A175 IDs survive the crossed pitches")
    report.expectEqual(expected: beforeDepth + 2,
                       actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A170 second move adds another history entry")
    before = document.revision
    report.expect(document.history.undoDocument(), cppID: id, message: "first crossing undo succeeds")
    report.expectEqual(expected: before + 1, actual: document.revision, cppID: id,
                       what: "A176 first crossing undo advances revision")
    report.expect(document.note(idA)?.pitch == 61 && document.note(idB)?.pitch == 61,
                  cppID: id, message: "A177-A180 first undo restores both IDs at pitch 61")
    before = document.revision
    report.expect(document.history.undoDocument(), cppID: id, message: "second crossing undo succeeds")
    report.expectEqual(expected: before + 1, actual: document.revision, cppID: id,
                       what: "A181 second crossing undo advances revision")
    report.expect(document.note(idA)?.pitch == 60 && document.note(idB)?.pitch == 61,
                  cppID: id, message: "A182-A185 second undo restores original pitches and IDs")
    before = document.revision
    report.expect(document.history.redoDocument(), cppID: id, message: "first crossing redo succeeds")
    report.expectEqual(expected: before + 1, actual: document.revision, cppID: id,
                       what: "A186 first crossing redo advances revision")
    report.expect(document.note(idA)?.pitch == 61 && document.note(idB)?.pitch == 61,
                  cppID: id, message: "first redo restores intermediate IDs and pitches")
    before = document.revision
    report.expect(document.history.redoDocument(), cppID: id, message: "second crossing redo succeeds")
    report.expectEqual(expected: before + 1, actual: document.revision, cppID: id,
                       what: "A187 second crossing redo advances revision")
    report.expect(document.note(idA)?.pitch == 61 && document.note(idB)?.pitch == 60,
                  cppID: id, message: "A188-A191 redo restores crossed pitches and original IDs")
}

@MainActor
private func documentMergedOverlapContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::documentMergedOverlapPublication"
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 1),
            .channel(status: 0x90, data0: 70, data1: 100),
            .channel(status: 0x90, data0: 69, data1: 100),
            .channel(tick: 2, status: 0x80, data0: 69),
            .channel(tick: 4, status: 0x80, data0: 70),
        ], endTick: 8),
    ]))
    guard let movedID = document.notes(in: 0).first(where: { $0.pitch == 69 })?.id,
          let survivorID = document.notes(in: 0).first(where: { $0.pitch == 70 })?.id else {
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
        report.expectEqual(expected: beforeRevision + 1, actual: document.revision, cppID: id,
                           what: "A212/A219/A226 grouped move \(step) advances revision")
        report.expect(publications.count == beforePublications + 1 &&
            publications.last?.revision == document.revision &&
            publications.last?.trackRemap == nil,
            cppID: id, message: "A213-A214/A220-A221/A227-A228 grouped move \(step) publishes change only")
        report.expect(document.note(movedID)?.tick == 0 &&
            document.note(movedID)?.pitch == UInt8(pitch), cppID: id,
            message: "A215/A222/A229 grouped move \(step) retains moved identity and pitch")
        report.expect(document.note(survivorID)?.tick == Tick(survivorTick) &&
            document.note(survivorID)?.pitch == 70 &&
            document.note(survivorID)?.duration == Tick(survivorDuration), cppID: id,
            message: "A216-A217/A223-A224/A230-A231 survivor trims then restores from origin")
        report.expectEqual(expected: beforeDepth + 1,
                           actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                           cppID: id, what: "A211/A218/A225 grouped moves keep one history entry")
    }
    var beforeRevision = document.revision
    var beforePublications = publications.count
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "one undo reverses all three grouped moves")
    report.expectEqual(expected: beforeRevision + 1, actual: document.revision, cppID: id,
                       what: "A232 grouped undo advances revision")
    report.expect(publications.count == beforePublications + 1 &&
        publications.last?.trackRemap == nil, cppID: id,
        message: "A233-A234 grouped undo publishes change only")
    report.expect(document.note(movedID)?.pitch == 69 && document.note(movedID)?.tick == 0 &&
        document.note(survivorID)?.pitch == 70 && document.note(survivorID)?.tick == 0 &&
        document.note(survivorID)?.duration == 4, cppID: id,
        message: "A235-A237 one undo restores both original notes")
    report.expectEqual(expected: baseline, actual: try document.state.file.encoded(), cppID: id,
                       what: "grouped undo restores baseline MIDI bytes")
    beforeRevision = document.revision
    beforePublications = publications.count
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "one redo restores all three grouped moves")
    report.expectEqual(expected: beforeRevision + 1, actual: document.revision, cppID: id,
                       what: "A238 grouped redo advances revision")
    report.expect(publications.count == beforePublications + 1 &&
        publications.last?.trackRemap == nil, cppID: id,
        message: "A239-A240 grouped redo publishes change only")
    report.expect(document.note(movedID)?.pitch == 72, cppID: id,
                  message: "A241 grouped redo returns to pitch 72")
    beforeRevision = document.revision
    beforePublications = publications.count
    document.moveNotes([movedID], byTicks: 0, byKeys: 1)
    report.expectEqual(expected: beforeRevision + 1, actual: document.revision, cppID: id,
                       what: "A242 ungrouped fourth move advances revision")
    report.expect(publications.count == beforePublications + 1 &&
        publications.last?.trackRemap == nil, cppID: id,
        message: "A243-A244 fourth move publishes change only")
    report.expect(document.note(movedID)?.pitch == 73, cppID: id,
                  message: "fourth move reaches pitch 73")
    report.expectEqual(expected: beforeDepth + 2,
                       actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "ungrouped fourth move adds a second history entry")
    beforeRevision = document.revision
    beforePublications = publications.count
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "fourth move undoes separately")
    report.expectEqual(expected: beforeRevision + 1, actual: document.revision, cppID: id,
                       what: "A245 fourth-move undo advances revision")
    report.expect(publications.count == beforePublications + 1 &&
        publications.last?.trackRemap == nil, cppID: id,
        message: "A246-A247 fourth-move undo publishes change only")
    report.expect(document.note(movedID)?.pitch == 72, cppID: id,
                  message: "undo fourth move returns to grouped pitch 72")
    beforeRevision = document.revision
    beforePublications = publications.count
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "fourth move redoes separately")
    report.expectEqual(expected: beforeRevision + 1, actual: document.revision, cppID: id,
                       what: "A248 fourth-move redo advances revision")
    report.expect(publications.count == beforePublications + 1 &&
        publications.last?.trackRemap == nil, cppID: id,
        message: "A249-A250 fourth-move redo publishes change only")
    report.expect(document.note(movedID)?.pitch == 73, cppID: id,
                  message: "redo fourth move returns to pitch 73")
}
