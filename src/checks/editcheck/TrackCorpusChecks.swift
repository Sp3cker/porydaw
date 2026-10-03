import PorydawCore

// Corpus rows for tst_songdocument_songtracks.cpp; each eligible family reloads its own document.
@MainActor
internal func coreTrackCorpusChecks(_ report: CheckReport) {
    let families: [(method: String, path: String?, load: String)] = [
        ("trackCreateDelete", "A001", "A002"),
        ("trackDuplicate", "A011", "A012"),
        ("trackMove", "A019", "A020"),
        ("trackDeleteRescue", "A050", "A051"),
        ("trackRename", "A057", "A058"),
        ("songTimeSignature", "A071", "A072"),
        ("loopCfgUndoRedo", nil, "A084"),
    ]
    var rows = Array(repeating: 0, count: families.count)
    do {
        for song in try coreEditCorpusSongs(report) {
            let classified = SongDocument(file: try MidiFile.decode(song.midiBytes),
                                          config: song.config, source: song.source)
            let editable = firstNoteTrack(classified) != nil
            let addable = classified.engineTracks.usedTrackCount < classified.trackBudget
            let reorderable = editable && classified.engineTracks.usedTrackCount >= 2
            for (index, family) in families.enumerated() {
                let eligible: Bool
                switch family.method {
                case "trackCreateDelete": eligible = addable
                case "trackDuplicate": eligible = editable && addable
                case "trackMove": eligible = reorderable
                case "trackDeleteRescue", "trackRename": eligible = editable
                default: eligible = true // Playable: signature and loop/config include every staged song.
                }
                guard eligible else { continue }
                rows[index] += 1
                let id = "editcheck/EditCheckTest::\(family.method)[\(song.label)]"
                report.expect(!song.midiPath.isEmpty, cppID: id,
                              message: "\(family.path ?? "corpus") row has a MIDI path")
                do {
                    let document = SongDocument(file: try MidiFile.decode(song.midiBytes),
                                                config: song.config, source: song.source)
                    report.pass(id, row: "\(family.load) staged MIDI decoded and loaded")
                    switch family.method {
                    case "trackCreateDelete":
                        let canAdd = document.engineTracks.usedTrackCount < document.trackBudget
                            && document.canAddTrack
                        report.expect(canAdd, cppID: id,
                                      message: "A003 reloaded song can add a track within budget")
                        guard canAdd else { continue }
                        try coreTrackCreateDeleteRow(report, document, id)
                    case "trackDuplicate":
                        let track = firstNoteTrack(document)
                        report.expect(track != nil, cppID: id,
                                      message: "A013 reloaded song has a first editable track")
                        guard let track else { continue }
                        let canAdd = document.engineTracks.usedTrackCount < document.trackBudget
                            && document.canAddTrack
                        report.expect(canAdd, cppID: id,
                                      message: "A014 reloaded song can add a duplicate within budget")
                        guard canAdd else { continue }
                        try coreTrackDuplicateRow(report, document, track, id)
                    case "trackMove":
                        let track = firstNoteTrack(document)
                        report.expect(track != nil, cppID: id,
                                      message: "A021 reloaded song has a first editable track")
                        guard track != nil else { continue }
                        let canReorder = document.engineTracks.usedTrackCount >= 2
                        report.expect(canReorder, cppID: id,
                                      message: "A022 reloaded song has at least two tracks to reorder")
                        guard canReorder else { continue }
                        try coreTrackMoveRow(report, document, id)
                    case "trackDeleteRescue":
                        let track = firstNoteTrack(document)
                        report.expect(track != nil, cppID: id,
                                      message: "A052 reloaded song has a first editable track")
                        guard let track else { continue }
                        try coreTrackDeleteRescueRow(report, document, track, id)
                    case "trackRename":
                        let track = firstNoteTrack(document)
                        report.expect(track != nil, cppID: id,
                                      message: "A059 reloaded song has a first editable track")
                        guard let track else { continue }
                        try coreTrackRenameRow(report, document, track, id)
                    case "songTimeSignature":
                        try coreSongTimeSignatureRow(report, document, id)
                    default:
                        try coreLoopCfgUndoRedoRow(report, document, id)
                    }
                } catch {
                    report.fail(id, "track corpus row failed: \(error)")
                }
            }
        }
        for (index, family) in families.enumerated() {
            report.expect(rows[index] > 0, cppID: "editcheck/EditCheckTest::addSongRows",
                          message: "\(family.method) corpus contains an eligible row")
        }
    } catch {
        report.fail("editcheck/EditCheckTest::initTestCase", "track corpus loading failed: \(error)")
    }
}

@MainActor
private func coreTrackStep(_ document: SongDocument) -> Tick {
    Tick(max(1, document.ticksPerBeat /
        (24 * (document.state.config.extendedClocks ? 2 : 1))))
}

@MainActor
private func coreTrackNoteShapes(_ document: SongDocument, _ track: Int) -> [String] {
    document.notes(in: track).map { "\($0.tick):\($0.pitch):\($0.duration):\($0.velocity)" }
}

@MainActor
private func coreTrackCreateDeleteRow(_ report: CheckReport, _ document: SongDocument,
                                      _ id: String) throws {
    let base = coreEditDistantBase(document)
    let step = coreTrackStep(document)
    guard let added = document.addTrack(voice: 7) else {
        report.fail(id, "A004 addTrack rejected an eligible song")
        return
    }
    let voices = document.lanePoints(track: added, lane: .voice)
    report.expect(!voices.isEmpty, cppID: id, message: "A005 new track seeds a voice point")
    report.expectEqual(expected: Tick(0), actual: voices.first?.tick, cppID: id,
                       what: "A006 voice point starts at tick zero")
    report.expectEqual(expected: 7, actual: voices.first?.value, cppID: id,
                       what: "A007 voice point carries voice seven")
    _ = try document.addNotes([
        NewNote(track: added, tick: base, pitch: 72, duration: step * 4, velocity: 100),
    ])
    report.expect(corpusNote(document, added, base, 72) != nil, cppID: id,
                  message: "A008 inserted note is queryable")
    document.deleteTrack(added)
    report.expect(corpusNote(document, added, base, 72) == nil, cppID: id,
                  message: "A009 deleted track no longer reports the note")
    report.expect(corpusTracksSorted(document), cppID: id,
                  message: "A010 raw tracks remain tick-sorted")
}

@MainActor
private func coreTrackDuplicateRow(_ report: CheckReport, _ document: SongDocument,
                                   _ track: Int, _ id: String) throws {
    let source = coreTrackNoteShapes(document, track)
    guard let copy = document.duplicateTrack(track) else {
        report.fail(id, "A015 duplicateTrack rejected an eligible song")
        return
    }
    report.expect(copy != track, cppID: id, message: "A016 copy occupies a distinct slot")
    report.expectEqual(expected: source, actual: coreTrackNoteShapes(document, copy), cppID: id,
                       what: "A017 duplicate preserves note ticks, pitches, durations and velocities")
    document.deleteTrack(copy)
    report.expect(corpusTracksSorted(document), cppID: id,
                  message: "A018 raw tracks remain tick-sorted after deleting the copy")
}

@MainActor
private func coreTrackMoveRow(_ report: CheckReport, _ document: SongDocument,
                              _ id: String) throws {
    let base = coreEditDistantBase(document)
    let step = coreTrackStep(document)
    let tempo = TempoPoint(tick: base + step * 110,
                           microsecondsPerQuarterNote: 413_793) // 145 BPM
    document.editTempo(TempoEdit(add: [tempo]))
    document.setTimeSignature(tick: base + step * 112, numerator: 5, denominatorPower: 2)
    let originalTimeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    let source = coreTrackNoteShapes(document, 0)
    let sourceChannel = document.engineTracks.tracks[0].channel
    let last = document.engineTracks.usedTrackCount - 1
    let before = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    report.expect(!document.moveTrack(0, to: 0), cppID: id,
                  message: "A023 same-slot move is rejected")
    report.expectEqual(expected: before, actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A024 no-op leaves complete history count unchanged")
    report.expect(document.moveTrack(0, to: last), cppID: id,
                  message: "A025 move to last slot succeeds")
    report.expectEqual(expected: before + 1,
                       actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A026 real move adds one history entry")
    report.expectEqual(expected: source, actual: coreTrackNoteShapes(document, last), cppID: id,
                       what: "A027 notes follow the moved track")
    report.expectEqual(expected: sourceChannel, actual: document.engineTracks.tracks[last].channel,
                       cppID: id, what: "A028 channel follows the moved track")
    report.expect(document.state.tempo.contains(tempo), cppID: id,
                  message: "A029 staged tempo survives the move")
    report.expect(document.timeSignatures.contains {
        $0.tick == base + step * 112 && $0.numerator == 5 && $0.denominatorPower == 2
    }, cppID: id, message: "A030 staged 5/2 signature survives the move")
    let movedTimeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: originalTimeline.loopStartTick, actual: movedTimeline.loopStartTick,
                       cppID: id, what: "A031 loop start survives the move")
    report.expectEqual(expected: originalTimeline.loopEndTick, actual: movedTimeline.loopEndTick,
                       cppID: id, what: "A032 loop end survives the move")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "move can be undone")
    report.expectEqual(expected: source, actual: coreTrackNoteShapes(document, 0), cppID: id,
                       what: "A033 undo restores track-zero notes")
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "move can be redone")
    report.expect(document.moveTrack(last, to: 0), cppID: id,
                  message: "A034 move back succeeds")
    report.expectEqual(expected: source, actual: coreTrackNoteShapes(document, 0), cppID: id,
                       what: "A035 source notes return to track zero")
    report.expect(corpusTracksSorted(document), cppID: id,
                  message: "A036 raw tracks remain tick-sorted after reordering")
}

@MainActor
private func coreTrackDeleteRescueRow(_ report: CheckReport, _ document: SongDocument,
                                      _ track: Int, _ id: String) throws {
    let original = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    document.deleteTrack(track)
    let deleted = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: original.loopStartTick, actual: deleted.loopStartTick,
                       cppID: id, what: "A053 loop start survives deleting the first editable track")
    report.expectEqual(expected: original.loopEndTick, actual: deleted.loopEndTick,
                       cppID: id, what: "A054 loop end survives deleting the first editable track")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "deleted track can be restored")
    let restored = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: original.loopStartTick, actual: restored.loopStartTick,
                       cppID: id, what: "A055 undo preserves loop start")
    report.expectEqual(expected: original.loopEndTick, actual: restored.loopEndTick,
                       cppID: id, what: "A056 undo preserves loop end")
}

@MainActor
private func coreTrackRenameRow(_ report: CheckReport, _ document: SongDocument,
                                _ track: Int, _ id: String) throws {
    guard let chunk = document.engineTracks.tracks[track].midiChunk else {
        report.fail(id, "A059 first editable track has no MIDI chunk")
        return
    }
    document.renameTrack(track, to: "editcheck name")
    report.expectEqual(expected: "editcheck name", actual: document.trackName(track), cppID: id,
                       what: "A060 rename stores the exact name")
    report.expectEqual(expected: 1, actual: bareTrackNameCount(document.rawChunks[chunk]), cppID: id,
                       what: "A061 exactly one bare track-name meta remains")
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: "editcheck name", actual: timeline.tracks[track].name, cppID: id,
                       what: "A063 timeline reports the renamed track")
    let before = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    document.renameTrack(track, to: "  editcheck name  ")
    report.expectEqual(expected: before, actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A064 trimmed same-name rename adds no history entry")
    document.renameTrack(track, to: "[")
    document.renameTrack(track, to: " ][ ")
    report.expectEqual(expected: before, actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A065 marker-shaped renames add no history entry")
    report.expectEqual(expected: "editcheck name", actual: document.trackName(track), cppID: id,
                       what: "A066 rejected names preserve the stored name")
    document.renameTrack(track, to: "")
    report.expectEqual(expected: "", actual: document.trackName(track), cppID: id,
                       what: "A067 clearing removes the stored name")
    report.expectEqual(expected: 0, actual: bareTrackNameCount(document.rawChunks[chunk]), cppID: id,
                       what: "A068 clearing removes all bare name meta events")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "name clearing can be undone")
    report.expectEqual(expected: "editcheck name", actual: document.trackName(track), cppID: id,
                       what: "A069 undo restores the name")
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "name clearing can be redone")
    report.expectEqual(expected: "", actual: document.trackName(track), cppID: id,
                       what: "A070 redo clears the name")
}

@MainActor
private func coreSongTimeSignatureRow(_ report: CheckReport, _ document: SongDocument,
                                      _ id: String) throws {
    let base = coreEditDistantBase(document)
    let step = coreTrackStep(document)
    let before = document.timeSignatures.count
    document.setTimeSignature(tick: base, numerator: 3, denominatorPower: 3)
    let inserted = document.timeSignatures.first { $0.tick == base }
    report.expect(inserted != nil, cppID: id, message: "A073 3/3 signature exists")
    report.expectEqual(expected: UInt8(3), actual: inserted?.numerator, cppID: id,
                       what: "A074 staged numerator is three")
    report.expectEqual(expected: UInt8(3), actual: inserted?.denominatorPower, cppID: id,
                       what: "A075 staged denominator power is three")
    document.setTimeSignature(tick: base, numerator: 7, denominatorPower: 2)
    let replaced = document.timeSignatures.first { $0.tick == base }
    report.expect(replaced != nil, cppID: id, message: "A076 replacement exists")
    report.expectEqual(expected: UInt8(7), actual: replaced?.numerator, cppID: id,
                       what: "A077 replacement numerator is seven")
    report.expectEqual(expected: UInt8(2), actual: replaced?.denominatorPower, cppID: id,
                       what: "A078 replacement denominator power is two")
    report.expectEqual(expected: before + 1, actual: document.timeSignatures.count, cppID: id,
                       what: "A079 total time-signature entry count grows by one")
    document.moveTimeSignature(from: base, to: base + step * 4)
    report.expect(!document.timeSignatures.contains { $0.tick == base }, cppID: id,
                  message: "A080 source tick loses its signature")
    let moved = document.timeSignatures.first { $0.tick == base + step * 4 }
    report.expect(moved != nil, cppID: id, message: "A081 destination has a signature")
    report.expectEqual(expected: UInt8(7), actual: moved?.numerator, cppID: id,
                       what: "A082 moved signature keeps numerator seven")
    document.deleteTimeSignature(at: base + step * 4)
    report.expect(!document.timeSignatures.contains { $0.tick == base + step * 4 },
                  cppID: id, message: "A083 destination signature is deleted")
}

@MainActor
private func coreLoopCfgUndoRedoRow(_ report: CheckReport, _ document: SongDocument,
                                    _ id: String) throws {
    let baseline = try document.state.file.encoded()
    let originalVolume = document.state.config.masterVolume
    let loopStart = PlaybackTimeline.build(state: document.state, sampleRate: 48_000).loopStartTick
    let step = coreTrackStep(document)
    document.setLoop(end: false,
                     tick: loopStart == TimeDefaults.noTick ? 0 : Int64(loopStart + step))
    report.expect(corpusTracksSorted(document), cppID: id,
                  message: "A085 loop edit keeps raw tracks tick-sorted")
    var config = document.state.config
    config.masterVolume = config.masterVolume == 80 ? 90 : 80
    document.setConfig(config)
    while document.history.canUndo { _ = document.history.undoDocument() }
    report.expectEqual(expected: baseline, actual: try document.state.file.encoded(), cppID: id,
                       what: "A086 undo-all restores baseline MIDI bytes")
    report.expectEqual(expected: originalVolume, actual: document.state.config.masterVolume, cppID: id,
                       what: "A087 undo-all restores master volume")
    while document.history.canRedo { _ = document.history.redoDocument() }
    let redone = try document.state.file.encoded()
    report.expect(redone != baseline || firstNoteTrack(document) == nil, cppID: id,
                  message: "A088 redo changes MIDI bytes when the song has an editable note track")
    while document.history.canUndo { _ = document.history.undoDocument() }
    report.expectEqual(expected: baseline, actual: try document.state.file.encoded(), cppID: id,
                       what: "A089 second undo-all restores baseline MIDI bytes")
}
