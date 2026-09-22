import PorydawCore

// Corpus scenarios corresponding to A023-A138 in proof.tst_songdocument_songmoves.txt.
@MainActor
internal func coreNoteMoveCorpusChecks(_ report: CheckReport) {
    do {
        var rows = 0
        for loaded in try coreEditCorpusSongs(report) {
            let classified = SongDocument(file: try MidiFile.decode(loaded.midiBytes),
                                          config: loaded.config, source: loaded.source)
            guard firstNoteTrack(classified) != nil else { continue }
            rows += 1
            for (method, pathSite, loadSite, trackSite) in [
                ("noteMoveOverlap", "A023", "A024", "A025"),
                ("noteMoveMerge", "A042", "A043", "A044"),
                ("noteMoveBatch", "A059", "A060", "A061"),
                ("noteMoveCollision", "A097", "A098", "A099"),
                ("noteMoveRejects", "A127", "A128", "A129"),
            ] {
                let id = "editcheck/EditCheckTest::\(method)[\(loaded.label)]"
                report.expect(!loaded.midiPath.isEmpty, cppID: id,
                              message: "\(pathSite) corpus row has a MIDI path")
                do {
                    let document = SongDocument(file: try MidiFile.decode(loaded.midiBytes),
                                                config: loaded.config, source: loaded.source)
                    report.pass(id, row: "\(loadSite) staged MIDI decoded and loaded")
                    let track = firstNoteTrack(document)
                    report.expect(track != nil, cppID: id,
                                  message: "\(trackSite) classified row reloads with an editable track")
                    guard let track else { continue }
                    let base = coreEditDistantBase(document)
                    let step = Tick(max(1, document.ticksPerBeat /
                        (24 * (document.state.config.extendedClocks ? 2 : 1))))
                    switch method {
                    case "noteMoveOverlap":
                        try coreNoteMoveOverlapRow(document, track, base, step, report, id)
                    case "noteMoveMerge":
                        try coreNoteMoveMergeRow(document, track, base, step, report, id)
                    case "noteMoveBatch":
                        try coreNoteMoveBatchRow(document, track, base, step, report, id)
                    case "noteMoveCollision":
                        try coreNoteMoveCollisionRow(document, track, base, step, report, id)
                    default:
                        try coreNoteMoveRejectsRow(document, track, base, step, report, id)
                    }
                } catch {
                    report.fail(id, "corpus note movement failed: \(error)")
                }
            }
        }
        report.expect(rows > 0, cppID: "editcheck/EditCheckTest::addSongRows",
                      message: "movement corpus contains an EditableTrack row")
    } catch {
        report.fail("editcheck/EditCheckTest::initTestCase",
                    "note-movement corpus loading failed: \(error)")
    }
}

@MainActor
private func coreNoteMoveOverlapRow(_ document: SongDocument, _ track: Int,
                                    _ base: Tick, _ step: Tick,
                                    _ report: CheckReport, _ id: String) throws {
    _ = try document.addNotes([
        NewNote(track: track, tick: base + step * 90, pitch: 71,
                duration: step * 4, velocity: 100),
    ])
    _ = try document.addNotes([
        NewNote(track: track, tick: base + step * 88, pitch: 70,
                duration: step * 4, velocity: 100),
    ])
    guard let source = requireCorpusNote(document, track, base + step * 88, 70,
                                         report, id, "A026") else { return }
    document.moveNotes([source.id], byTicks: 0, byKeys: 1)
    guard let moving = requireCorpusNote(document, track, base + step * 88, 71,
                                         report, id, "A027") else { return }
    report.expectEqual(step * 4, moving.duration, cppID: id,
                       what: "A028 moved note retains its duration")
    guard let trimmed = requireCorpusNote(document, track, base + step * 92, 71,
                                          report, id, "A029") else { return }
    report.expectEqual(step * 2, trimmed.duration, cppID: id,
                       what: "A030 stationary overlap keeps its tail")

    document.resizeNotes([moving.id], edge: .trailing, byTicks: Int64(step) * 4)
    guard let extended = requireCorpusNote(document, track, base + step * 88, 71,
                                           report, id, "A031") else { return }
    report.expectEqual(step * 8, extended.duration, cppID: id,
                       what: "A032 trailing resize extends by four steps")
    report.expect(corpusNote(document, track, base + step * 92, 71) == nil,
                  cppID: id, message: "A033 resize swallows the covered note")

    _ = try document.addNotes([
        NewNote(track: track, tick: base + step * 94, pitch: 71,
                duration: step * 4, velocity: 100),
    ])
    guard let retrimmed = requireCorpusNote(document, track, base + step * 88, 71,
                                            report, id, "A034") else { return }
    report.expectEqual(step * 6, retrimmed.duration, cppID: id,
                       what: "A035 insertion trims the extended note")
    guard let stationary = requireCorpusNote(document, track, base + step * 94, 71,
                                              report, id, "A036") else { return }
    report.expectEqual(step * 4, stationary.duration, cppID: id,
                       what: "A037 inserted stationary note keeps its duration")

    _ = document.history.undoDocument()
    guard let restored = requireCorpusNote(document, track, base + step * 88, 71,
                                            report, id, "A038") else { return }
    report.expectEqual(step * 8, restored.duration, cppID: id,
                       what: "A039 undo restores the extended duration")
    report.expect(corpusNote(document, track, base + step * 94, 71) == nil,
                  cppID: id, message: "A040 undo removes the inserted note")
    _ = document.history.redoDocument()
    report.expect(corpusTracksSorted(document), cppID: id,
                  message: "A041 redo keeps every raw track sorted")
}

@MainActor
private func coreNoteMoveMergeRow(_ document: SongDocument, _ track: Int,
                                  _ base: Tick, _ step: Tick,
                                  _ report: CheckReport, _ id: String) throws {
    let tick = base + step * 100
    _ = try document.addNotes([
        NewNote(track: track, tick: tick, pitch: 70, duration: step * 4, velocity: 100),
    ])
    _ = try document.addNotes([
        NewNote(track: track, tick: tick, pitch: 69, duration: step * 2, velocity: 100),
    ])
    let before = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    guard let source = requireCorpusNote(document, track, tick, 69, report, id, "A045") else {
        return
    }

    document.nudgeNotes([source.id], byTicks: 0, byKeys: 1)
    guard let tail = requireCorpusNote(document, track, tick + step * 2, 70,
                                       report, id, "A046") else { return }
    report.expectEqual(step * 2, tail.duration, cppID: id,
                       what: "A047 first nudge retains the stationary tail")
    guard let moving = requireCorpusNote(document, track, tick, 70,
                                         report, id, "A048") else { return }
    document.nudgeNotes([moving.id], byTicks: 0, byKeys: 1)
    report.expectEqual(before + 1,
                       try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A049 compatible nudges merge into one entry")
    guard let twiceMoved = requireCorpusNote(document, track, tick, 71,
                                              report, id, "A050") else { return }
    report.expectEqual(step * 2, twiceMoved.duration, cppID: id,
                       what: "A051 second nudge retains moving duration")
    guard let stationary = requireCorpusNote(document, track, tick, 70,
                                              report, id, "A052") else { return }
    report.expectEqual(step * 4, stationary.duration, cppID: id,
                       what: "A053 second nudge rebuilds the stationary note")

    _ = document.history.undoDocument()
    _ = requireCorpusNote(document, track, tick, 69, report, id, "A054")
    guard let undoneStationary = requireCorpusNote(document, track, tick, 70,
                                                    report, id, "A055") else { return }
    report.expectEqual(step * 4, undoneStationary.duration, cppID: id,
                       what: "A056 undo restores stationary duration")
    _ = document.history.redoDocument()
    guard let redone = requireCorpusNote(document, track, tick, 71,
                                         report, id, "A057") else { return }
    document.didSave(try document.captureSave())
    document.nudgeNotes([redone.id], byTicks: 0, byKeys: 1)
    report.expectEqual(before + 2,
                       try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A058 save boundary splits the next nudge")
}

@MainActor
private func coreNoteMoveBatchRow(_ document: SongDocument, _ track: Int,
                                  _ base: Tick, _ step: Tick,
                                  _ report: CheckReport, _ id: String) throws {
    let firstTick = base + step * 110
    _ = try document.addNotes([
        NewNote(track: track, tick: firstTick, pitch: 115,
                duration: step * 4, velocity: 100),
    ])
    _ = try document.addNotes([
        NewNote(track: track, tick: firstTick + step * 20, pitch: 117,
                duration: step * 2, velocity: 90),
    ])
    guard let originalFirst = requireCorpusNote(document, track, firstTick, 115,
                                                 report, id, "A062"),
          let originalSecond = requireCorpusNote(document, track, firstTick + step * 20, 117,
                                                  report, id, "A063") else { return }
    let ids = [originalFirst.id, originalSecond.id]
    let before = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    let beforeBytes = try document.state.file.encoded()

    report.expect(document.moveNotes(ids, toPitches: [118, 114], byTicks: 0),
                  cppID: id, message: "A064 absolute-pitch batch is admitted")
    report.expectEqual(before + 1,
                       try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A065 batch adds one history entry")
    guard let first = requireCorpusNote(document, track, firstTick, 118,
                                        report, id, "A066") else { return }
    report.expectEqual(step * 4, first.duration, cppID: id,
                       what: "A067 first duration is preserved")
    report.expectEqual(UInt8(100), first.velocity, cppID: id,
                       what: "A068 first velocity is preserved")
    report.expect(corpusNote(document, track, firstTick, 115) == nil,
                  cppID: id, message: "A069 first source pitch is vacated")
    guard let second = requireCorpusNote(document, track, firstTick + step * 20, 114,
                                         report, id, "A070") else { return }
    report.expectEqual(step * 2, second.duration, cppID: id,
                       what: "A071 second duration is preserved")
    report.expectEqual(UInt8(90), second.velocity, cppID: id,
                       what: "A072 second velocity is preserved")
    report.expect(corpusNote(document, track, firstTick + step * 20, 117) == nil,
                  cppID: id, message: "A073 second source pitch is vacated")

    let movedBytes = try document.state.file.encoded()
    _ = document.history.undoDocument()
    report.expectEqual(beforeBytes, try document.state.file.encoded(), cppID: id,
                       what: "A074 undo restores exact pre-move bytes")
    _ = requireCorpusNote(document, track, firstTick, 115, report, id, "A075")
    _ = requireCorpusNote(document, track, firstTick + step * 20, 117, report, id, "A076")
    _ = document.history.redoDocument()
    report.expectEqual(movedBytes, try document.state.file.encoded(), cppID: id,
                       what: "A077 redo restores exact moved bytes")
    _ = requireCorpusNote(document, track, firstTick, 118, report, id, "A078")
    _ = requireCorpusNote(document, track, firstTick + step * 20, 114, report, id, "A079")

    let nudgeBefore = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    let nudgeStart = try document.state.file.encoded()
    report.expect(document.nudgeNotes(ids, toPitches: [119, 115], byTicks: 0),
                  cppID: id, message: "A080 first absolute-pitch nudge is admitted")
    _ = requireCorpusNote(document, track, firstTick, 119, report, id, "A081")
    _ = requireCorpusNote(document, track, firstTick + step * 20, 115, report, id, "A082")
    report.expect(document.nudgeNotes(ids, toPitches: [120, 116], byTicks: 0),
                  cppID: id, message: "A083 second absolute-pitch nudge is admitted")
    report.expectEqual(nudgeBefore + 1,
                       try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A084 compatible nudges merge into one entry")
    _ = requireCorpusNote(document, track, firstTick, 120, report, id, "A085")
    _ = requireCorpusNote(document, track, firstTick + step * 20, 116, report, id, "A086")
    _ = document.history.undoDocument()
    report.expectEqual(nudgeStart, try document.state.file.encoded(), cppID: id,
                       what: "A087 one undo restores pre-nudge bytes")
    _ = requireCorpusNote(document, track, firstTick, 118, report, id, "A088")
    _ = requireCorpusNote(document, track, firstTick + step * 20, 114, report, id, "A089")

    document.didSave(try document.captureSave())
    let inverseStart = try document.state.file.encoded()
    report.expect(document.nudgeNotes(ids, toPitches: [119, 115], byTicks: 0),
                  cppID: id, message: "A090 inverse-pair up nudge is admitted")
    let afterUp = coreRangeHistoryPosition(document, report, id)[1]
    _ = requireCorpusNote(document, track, firstTick, 119, report, id, "A091")
    _ = requireCorpusNote(document, track, firstTick + step * 20, 115, report, id, "A092")
    report.expect(document.nudgeNotes(ids, toPitches: [118, 114], byTicks: 0),
                  cppID: id, message: "A093 inverse-pair return nudge is admitted")
    report.expectEqual(afterUp, coreRangeHistoryPosition(document, report, id)[1],
                       cppID: id, what: "A094 inverse pair retains the post-up history index")
    _ = requireCorpusNote(document, track, firstTick, 118, report, id, "A095")
    _ = document.history.undoDocument()
    report.expectEqual(inverseStart, try document.state.file.encoded(), cppID: id,
                       what: "A096 undo after inverse pair restores exact start bytes")
}

@MainActor
private func coreNoteMoveCollisionRow(_ document: SongDocument, _ track: Int,
                                      _ base: Tick, _ step: Tick,
                                      _ report: CheckReport, _ id: String) throws {
    _ = try document.addNotes([
        NewNote(track: track, tick: base + step * 140, pitch: 119,
                duration: step * 4, velocity: 100),
    ])
    _ = try document.addNotes([
        NewNote(track: track, tick: base + step * 138, pitch: 118,
                duration: step * 4, velocity: 100),
    ])
    report.expect(corpusTracksSorted(document), cppID: id,
                  message: "A100 insertion keeps every raw track sorted")
    guard let source = requireCorpusNote(document, track, base + step * 138, 118,
                                         report, id, "A101"),
          let originalStationary = requireCorpusNote(document, track, base + step * 140, 119,
                                                       report, id, "A102") else { return }
    let stationaryID = originalStationary.id
    let collisionStart = try document.state.file.encoded()
    let collisionStartIndex = coreRangeHistoryPosition(document, report, id)[1]

    report.expect(document.moveNotes([source.id], toPitches: [119], byTicks: 0),
                  cppID: id, message: "A103 colliding pitch move is admitted")
    report.expect(corpusTracksSorted(document), cppID: id,
                  message: "A104 collision trim keeps every raw track sorted")
    guard let moving = requireCorpusNote(document, track, base + step * 138, 119,
                                         report, id, "A105") else { return }
    report.expectEqual(step * 4, moving.duration, cppID: id,
                       what: "A106 moved note retains its duration")
    guard let stationary = requireCorpusNote(document, track, base + step * 142, 119,
                                              report, id, "A107") else { return }
    report.expectEqual(stationaryID, stationary.id, cppID: id,
                       what: "A108 trimmed stationary note retains identity")
    report.expectEqual(step * 2, stationary.duration, cppID: id,
                       what: "A109 stationary tail has two-step duration")
    report.expect(corpusNote(document, track, base + step * 138, 118) == nil,
                  cppID: id, message: "A110 source pitch is vacated")
    report.expect(corpusNote(document, track, base + step * 140, 119) == nil,
                  cppID: id, message: "A111 covered stationary head is absent")

    _ = document.history.undoDocument()
    guard let undoneMoving = requireCorpusNote(document, track, base + step * 138, 118,
                                                report, id, "A112") else { return }
    report.expectEqual(step * 4, undoneMoving.duration, cppID: id,
                       what: "A113 undo restores moving duration")
    guard let undoneStationary = requireCorpusNote(document, track, base + step * 140, 119,
                                                    report, id, "A114") else { return }
    report.expectEqual(stationaryID, undoneStationary.id, cppID: id,
                       what: "A115 undo preserves stationary identity")
    report.expectEqual(step * 4, undoneStationary.duration, cppID: id,
                       what: "A116 undo restores stationary duration")
    _ = document.history.redoDocument()

    guard let redoneMoving = requireCorpusNote(document, track, base + step * 138, 119,
                                                report, id, "A117") else { return }
    report.expect(document.moveNotes([redoneMoving.id], toPitches: [119],
                                     byTicks: Int64(step) * 2),
                  cppID: id, message: "A118 forward absolute-pitch move is admitted")
    report.expect(corpusTracksSorted(document), cppID: id,
                  message: "A119 full collision keeps every raw track sorted")
    guard let finalMoving = requireCorpusNote(document, track, base + step * 140, 119,
                                               report, id, "A120") else { return }
    report.expectEqual(step * 4, finalMoving.duration, cppID: id,
                       what: "A121 forward move retains duration")
    let collisionEnd = try document.state.file.encoded()
    let collisionEndIndex = coreRangeHistoryPosition(document, report, id)[1]

    if collisionEndIndex > collisionStartIndex {
        for _ in collisionStartIndex..<collisionEndIndex { _ = document.history.undoDocument() }
    }
    report.expectEqual(collisionStart, try document.state.file.encoded(), cppID: id,
                       what: "A122 undo-to-start restores exact bytes")
    guard let restoredStationary = requireCorpusNote(document, track, base + step * 140, 119,
                                                      report, id, "A123") else { return }
    report.expectEqual(stationaryID, restoredStationary.id, cppID: id,
                       what: "A124 undo-to-start restores stationary identity")
    if collisionEndIndex > collisionStartIndex {
        for _ in collisionStartIndex..<collisionEndIndex { _ = document.history.redoDocument() }
    }
    report.expectEqual(collisionEnd, try document.state.file.encoded(), cppID: id,
                       what: "A125 redo-to-end restores exact bytes")
    report.expect(corpusNote(document, track, base + step * 142, 119) == nil,
                  cppID: id, message: "A126 fully covered stationary note remains absent")
}

@MainActor
private func coreNoteMoveRejectsRow(_ document: SongDocument, _ track: Int,
                                    _ base: Tick, _ step: Tick,
                                    _ report: CheckReport, _ id: String) throws {
    let firstTick = base + step * 110
    _ = try document.addNotes([
        NewNote(track: track, tick: firstTick, pitch: 115,
                duration: step * 4, velocity: 100),
    ])
    _ = try document.addNotes([
        NewNote(track: track, tick: firstTick + step * 20, pitch: 117,
                duration: step * 2, velocity: 90),
    ])
    guard let first = requireCorpusNote(document, track, firstTick, 115,
                                        report, id, "A130"),
          requireCorpusNote(document, track, firstTick + step * 20, 117,
                            report, id, "A131") != nil else { return }
    let baseline = try document.state.file.encoded()
    let before = try coreEditHistoryCountAtTip(document, report: report, cppID: id)

    report.expect(!document.moveNotes([first.id], toPitches: [130], byTicks: 0),
                  cppID: id, message: "A132 out-of-range pitch is rejected")
    report.expect(!document.moveNotes([first.id], toPitches: [], byTicks: 0),
                  cppID: id, message: "A133 empty pitch list is rejected")
    report.expect(!document.moveNotes([], toPitches: [118], byTicks: 0),
                  cppID: id, message: "A134 empty note list is rejected")
    report.expectEqual(before,
                       try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A135 rejected requests add no history entries")
    report.expectEqual(baseline, try document.state.file.encoded(), cppID: id,
                       what: "A136 rejected requests preserve exact bytes")
    _ = requireCorpusNote(document, track, firstTick, 115, report, id, "A137")
    _ = requireCorpusNote(document, track, firstTick + step * 20, 117, report, id, "A138")
}
