import PorydawCore

// Corpus scenarios corresponding to A070-A111 in proof.tst_songdocument_songnotes.txt.
@MainActor
internal func coreNoteCorpusChecks(_ report: CheckReport) {
    do {
        var rows = 0
        for loaded in try coreEditCorpusSongs(report) {
            let classified = SongDocument(file: try MidiFile.decode(loaded.midiBytes),
                                          config: loaded.config, source: loaded.source)
            guard firstNoteTrack(classified) != nil else { continue }
            rows += 1
            for (method, pathSite, loadSite, trackSite) in [
                ("noteEditingBasic", "A070", "A071", "A072"),
                ("noteEditingBatch", "A093", "A094", "A095"),
                ("noteEditingAbutting", "A103", "A104", "A105"),
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
                    case "noteEditingBasic":
                        try basicNoteRow(document, track, base, step, report, id)
                    case "noteEditingBatch":
                        try batchNoteRow(document, track, base, step, report, id)
                    default:
                        try abuttingNoteRow(document, track, base, step, report, id)
                    }
                } catch {
                    report.fail(id, "corpus note operation failed: \(error)")
                }
            }
        }
        report.expect(rows > 0, cppID: "editcheck/EditCheckTest::addSongRows",
                      message: "note corpus contains an EditableTrack row")
    } catch {
        report.fail("editcheck/EditCheckTest::initTestCase", "note corpus loading failed: \(error)")
    }
}

@MainActor
internal func firstNoteTrack(_ document: SongDocument) -> Int? {
    (0..<document.engineTracks.usedTrackCount).first { !document.notes(in: $0).isEmpty }
}

@MainActor
internal func corpusNote(_ document: SongDocument, _ track: Int, _ tick: Tick,
                        _ pitch: UInt8) -> Note? {
    document.notes(in: track).first { $0.tick == tick && $0.pitch == pitch }
}

@MainActor
internal func requireCorpusNote(_ document: SongDocument, _ track: Int, _ tick: Tick,
                               _ pitch: UInt8, _ report: CheckReport, _ id: String,
                               _ site: String) -> Note? {
    let note = corpusNote(document, track, tick, pitch)
    report.expect(note != nil, cppID: id,
                  message: "\(site) note exists at track \(track), tick \(tick), pitch \(pitch)")
    return note
}

@MainActor
internal func corpusTracksSorted(_ document: SongDocument) -> Bool {
    document.rawChunks.allSatisfy { chunk in
        zip(chunk.events, chunk.events.dropFirst()).allSatisfy { $0.tick <= $1.tick }
    }
}

@MainActor
private func basicNoteRow(_ document: SongDocument, _ track: Int, _ base: Tick, _ step: Tick,
                          _ report: CheckReport, _ id: String) throws {
    _ = try document.addNotes([
        NewNote(track: track, tick: base, pitch: 60, duration: step * 4, velocity: 100),
    ])
    report.expect(corpusTracksSorted(document), cppID: id, message: "A073 insertion keeps all tracks sorted")
    guard let inserted = requireCorpusNote(document, track, base, 60, report, id, "A074") else { return }
    document.moveNotes([inserted.id], byTicks: Int64(step) * 8, byKeys: 3)
    report.expect(corpusTracksSorted(document), cppID: id, message: "A075 movement keeps all tracks sorted")
    guard let moved = requireCorpusNote(document, track, base + step * 8, 63, report, id, "A076")
    else { return }
    document.resizeNotes([moved.id], edge: .trailing, byTicks: Int64(step) * 2)
    guard let extended = requireCorpusNote(document, track, base + step * 8, 63, report, id, "A077")
    else { return }
    report.expectEqual(expected: step * 6, actual: extended.duration, cppID: id, what: "A078 trailing resize adds two steps")
    document.resizeNotes([extended.id], edge: .leading, byTicks: -Int64(step) * 2)
    guard let leading = requireCorpusNote(document, track, base + step * 6, 63, report, id, "A079")
    else { return }
    report.expectEqual(expected: step * 8, actual: leading.duration, cppID: id, what: "A080 leading resize preserves the end")
    document.resizeNotes([leading.id], edge: .leading, byTicks: Int64(step) * 100)
    guard let clamped = requireCorpusNote(document, track, base + step * 14 - 1, 63, report, id, "A081")
    else { return }
    report.expectEqual(expected: Tick(1), actual: clamped.duration, cppID: id, what: "A082 leading resize clamps to one tick")
    document.resizeNotes([clamped.id], edge: .leading, byTicks: -Int64(step) * 8 + 1)
    guard let restored = requireCorpusNote(document, track, base + step * 6, 63, report, id, "A083")
    else { return }
    report.expectEqual(expected: step * 8, actual: restored.duration, cppID: id, what: "A084 leading resize restores eight steps")
    _ = document.setVelocities([NoteVelocity(noteID: restored.id, velocity: 88)],
                               expectedRevision: document.revision)
    guard let set = requireCorpusNote(document, track, base + step * 6, 63, report, id, "A085")
    else { return }
    report.expectEqual(expected: UInt8(88), actual: set.velocity, cppID: id, what: "A086 velocity is set to 88")
    document.nudgeVelocities([set.id], by: -30)
    guard let lowered = requireCorpusNote(document, track, base + step * 6, 63, report, id, "A087")
    else { return }
    report.expectEqual(expected: UInt8(58), actual: lowered.velocity, cppID: id, what: "A088 negative nudge yields 58")
    document.nudgeVelocities([lowered.id], by: 200)
    guard let raised = requireCorpusNote(document, track, base + step * 6, 63, report, id, "A089")
    else { return }
    report.expectEqual(expected: UInt8(127), actual: raised.velocity, cppID: id, what: "A090 positive nudge clamps to 127")
    document.deleteNotes([raised.id])
    report.expect(corpusNote(document, track, base + step * 6, 63) == nil, cppID: id,
                  message: "A091 deleted note is absent")
    report.expect(corpusTracksSorted(document), cppID: id, message: "A092 deletion keeps all tracks sorted")
}

@MainActor
private func batchNoteRow(_ document: SongDocument, _ track: Int, _ base: Tick, _ step: Tick,
                          _ report: CheckReport, _ id: String) throws {
    let before = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    _ = try document.addNotes([
        NewNote(track: track, tick: base + step * 20, pitch: 64, duration: step * 2, velocity: 96),
        NewNote(track: track, tick: base + step * 22, pitch: 67, duration: step * 2, velocity: 96),
    ])
    guard requireCorpusNote(document, track, base + step * 20, 64, report, id, "A096") != nil,
          requireCorpusNote(document, track, base + step * 22, 67, report, id, "A097") != nil else { return }
    report.expectEqual(expected: before + 1, actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A098 batch adds exactly one undo entry")
    _ = document.history.undoDocument()
    report.expect(corpusNote(document, track, base + step * 20, 64) == nil, cppID: id,
                  message: "A099 one undo removes first batch note")
    report.expect(corpusNote(document, track, base + step * 22, 67) == nil, cppID: id,
                  message: "A100 one undo removes second batch note")
    _ = document.history.redoDocument()
    _ = requireCorpusNote(document, track, base + step * 20, 64, report, id, "A101")
    _ = requireCorpusNote(document, track, base + step * 22, 67, report, id, "A102")
}

@MainActor
private func abuttingNoteRow(_ document: SongDocument, _ track: Int, _ base: Tick, _ step: Tick,
                             _ report: CheckReport, _ id: String) throws {
    let seam = base + step * 30
    _ = try document.addNotes([
        NewNote(track: track, tick: seam, pitch: 60, duration: step * 2, velocity: 100),
    ])
    _ = try document.addNotes([
        NewNote(track: track, tick: seam - step * 2, pitch: 60, duration: step * 2, velocity: 100),
    ])
    guard let left = requireCorpusNote(document, track, seam - step * 2, 60, report, id, "A106"),
          let right = requireCorpusNote(document, track, seam, 60, report, id, "A107") else { return }
    report.expectEqual(expected: step * 2, actual: left.duration, cppID: id, what: "A108 left note ends at the seam")
    report.expectEqual(expected: step * 2, actual: right.duration, cppID: id, what: "A109 right note retains its full duration")
    report.expect(left.endIndex != right.endIndex, cppID: id, message: "A110 abutting notes have distinct ends")
    document.deleteNotes([left.id, right.id])
    guard let chunk = document.engineTracks.tracks[track].midiChunk else {
        report.fail(id, "A111 edited track lost its MIDI chunk"); return
    }
    for event in document.rawChunks[chunk].events {
        report.expect(!(event.isChannel && event.tick >= seam - step * 2 &&
                        (event.isNoteOn || event.isNoteEnd)), cppID: id,
                      message: "A111 deleting both notes leaves no note endpoints at or beyond the seam")
    }
}
