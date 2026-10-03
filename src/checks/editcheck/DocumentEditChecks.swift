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
func documentEditContracts(_ report: CheckReport) {
    do { try documentVelocityAtomicContract(report) }
    catch {
        report.fail("editcheck/EditCheckTest::documentVelocityAtomic",
                    "velocity history failed: \(error)")
    }
    do { try documentVelocityRejectsContract(report) }
    catch {
        report.fail("editcheck/EditCheckTest::documentVelocityRejects",
                    "velocity rejection failed: \(error)")
    }
    documentDuplicateIdentitiesContract(report)
    do { try documentTempoEmptyContract(report) }
    catch {
        report.fail("editcheck/EditCheckTest::documentTempoEmpty",
                    "tempo save failed: \(error)")
    }
}

@MainActor
private func documentVelocityAtomicContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::documentVelocityAtomic"
    let document = SongDocument(file: twoTrackFile())
    let notes = document.notes(in: 0)
    guard notes.count == 2, notes.allSatisfy({ $0.id.isAssigned }),
          notes[0].id != notes[1].id else {
        report.fail(id, "fixture must have two distinct assigned note IDs")
        return
    }
    let first = notes[0].id
    let second = notes[1].id
    let beforeDepth = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    var changes: [DocumentChange] = []
    document.onChange = { changes.append($0) }
    defer { document.onChange = nil }

    let before = document.revision
    let result = document.setVelocities([
        NoteVelocity(noteID: first, velocity: 0),
        NoteVelocity(noteID: second, velocity: 200),
        NoteVelocity(noteID: first, velocity: 99),
    ], expectedRevision: before)
    report.expectEqual(expected: before + 1, actual: result, cppID: id,
                       what: "A027-A028 batch returns the next revision")
    report.expectEqual(expected: before + 1, actual: document.revision, cppID: id,
                       what: "A029 atomic batch advances revision once")
    report.expect(document.note(first)?.velocity == 99 && document.note(second)?.velocity == 127,
                  cppID: id, message: "A033-A034 last write wins and upper velocity clamps to 127")
    report.expect(changes.count == 1 && changes.last?.trackRemap == nil, cppID: id,
                  message: "A035-A036 atomic batch publishes once without remapping tracks")
    document.onChange = nil
    report.expectEqual(expected: beforeDepth + 1,
                       actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A030 atomic batch adds exactly one undo entry")
    document.onChange = { changes.append($0) }

    let changed = document.revision
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "atomic batch can be undone in one step")
    report.expectEqual(expected: changed + 1, actual: document.revision, cppID: id,
                       what: "A037 undo advances revision")
    report.expect(document.note(first)?.velocity == 100 && document.note(second)?.velocity == 90,
                  cppID: id, message: "A040-A041 one undo restores both original velocities")
    report.expect(changes.count == 2 && changes.last?.trackRemap == nil, cppID: id,
                  message: "A042 one undo publishes once without a track remap")
    let undone = document.revision
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "atomic batch can be redone in one step")
    report.expectEqual(expected: undone + 1, actual: document.revision, cppID: id,
                       what: "A043 redo advances revision")
    report.expect(document.note(first)?.velocity == 99 && document.note(second)?.velocity == 127,
                  cppID: id, message: "A045 redo restores both batch velocities")
    report.expect(changes.count == 3 && changes.last?.trackRemap == nil, cppID: id,
                  message: "one redo publishes once without a track remap")

    let lowerBefore = document.revision
    let lower = document.setVelocities([NoteVelocity(noteID: first, velocity: 0)],
                                       expectedRevision: lowerBefore)
    report.expectEqual(expected: lowerBefore + 1, actual: lower, cppID: id,
                       what: "A046-A047 lower-clamp edit returns the next revision")
    report.expectEqual(expected: lowerBefore + 1, actual: document.revision, cppID: id,
                       what: "A048 lower-clamp edit advances revision once")
    report.expectEqual(expected: UInt8(1), actual: document.note(first)?.velocity, cppID: id,
                       what: "A051 zero velocity clamps to the domain floor of one")
    report.expect(changes.count == 4 && changes.last?.trackRemap == nil, cppID: id,
                  message: "A052 lower-clamp edit publishes once without a track remap")
    document.onChange = nil
    report.expectEqual(expected: beforeDepth + 2,
                       actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A049 lower-clamp edit adds exactly one undo entry")
}

@MainActor
private func documentVelocityRejectsContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::documentVelocityRejects"
    let document = SongDocument(file: twoTrackFile())
    let notes = document.notes(in: 0)
    guard notes.count == 2 else {
        report.fail(id, "fixture must have two notes")
        return
    }
    let revision = document.revision
    let bytes = try document.state.file.encoded()
    let depth = try coreEditHistoryCountAtTip(document, report: report, cppID: id)
    var changes = 0
    document.onChange = { _ in changes += 1 }
    defer { document.onChange = nil }

    report.expect(document.setVelocities([NoteVelocity(noteID: notes[0].id, velocity: 42)],
                                         expectedRevision: revision - 1) == nil,
                  cppID: id, message: "A054 stale single-note velocity request rejects")
    report.expect(document.setVelocities([
        NoteVelocity(noteID: notes[0].id, velocity: 42),
        NoteVelocity(noteID: notes[1].id, velocity: 77),
    ], expectedRevision: revision - 1) == nil,
                  cppID: id, message: "A055 stale multi-note velocity request rejects atomically")
    report.expect(document.setVelocities([
        NoteVelocity(noteID: notes[0].id, velocity: 42),
        NoteVelocity(noteID: NoteID(), velocity: 77),
    ], expectedRevision: revision) == nil,
                  cppID: id, message: "A056 an invalid participant rejects the entire batch")
    let result = document.setVelocities([
        NoteVelocity(noteID: notes[0].id, velocity: 100),
        NoteVelocity(noteID: notes[1].id, velocity: 90),
    ], expectedRevision: revision)
    report.expectEqual(expected: revision, actual: result, cppID: id,
                       what: "A057-A058 same-value commit returns the current revision")
    report.expectEqual(expected: revision, actual: document.revision, cppID: id,
                       what: "A060 rejected and same-value edits do not advance revision")
    report.expectEqual(expected: bytes, actual: try document.state.file.encoded(), cppID: id,
                       what: "A059 rejected and same-value edits leave MIDI bytes unchanged")
    report.expectEqual(expected: 0, actual: changes, cppID: id,
                       what: "A062 rejected and same-value edits publish no changes")
    document.onChange = nil
    report.expectEqual(expected: depth, actual: try coreEditHistoryCountAtTip(document, report: report, cppID: id),
                       cppID: id, what: "A061 unchanged history depth after rejected and same-value edits")
}

@MainActor
private func documentDuplicateIdentitiesContract(_ report: CheckReport) {
    let id = "editcheck/EditCheckTest::documentDuplicateIdentities"
    let document = SongDocument(file: twoTrackFile())
    let original = document.notes(in: 0)
    guard original.count == 2, let copy = document.duplicateTrack(0) else {
        report.fail(id, "fixture source notes must duplicate into another track")
        return
    }
    let copied = document.notes(in: copy)
    report.expectEqual(expected: original.count, actual: copied.count, cppID: id,
                       what: "A065 duplication preserves note count")
    for (source, duplicate) in zip(original, copied) {
        report.expect(source.tick == duplicate.tick && source.pitch == duplicate.pitch &&
            source.duration == duplicate.duration && source.velocity == duplicate.velocity,
            cppID: id, message: "A066-A069 copied notes preserve tick, pitch, duration, and velocity")
        report.expect(duplicate.id.isAssigned && !original.contains(where: { $0.id == duplicate.id }),
                      cppID: id, message: "A070 copied note receives a fresh assigned identity")
    }
    let minted = copied.map(\.id)
    report.expectEqual(expected: minted.count, actual: Set(minted).count, cppID: id,
                       what: "duplicated notes have distinct new identities")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "duplicated track can be undone")
    report.expect(document.notes(in: copy).isEmpty &&
        document.engineTracks.usedTrackCount == 2, cppID: id,
        message: "undo removes the copied track")
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "duplicated track can be redone")
    let redone = document.notes(in: copy)
    report.expectEqual(expected: minted.count, actual: redone.count, cppID: id,
                       what: "A071 redo restores the copied note count")
    report.expectEqual(expected: minted, actual: redone.map(\.id), cppID: id,
                       what: "A072 redo restores exactly the minted note identities")
}

@MainActor
private func documentTempoEmptyContract(_ report: CheckReport) throws {
    let id = "editcheck/EditCheckTest::documentTempoEmpty"
    let document = SongDocument(file: twoTrackFile())
    report.expect(document.state.tempo.isEmpty, cppID: id,
                  message: "A011 empty fixture has no typed tempo points")
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: 1, actual: timeline.tempoMap.count, cppID: id,
                       what: "A013 empty typed tempo projects one default tempo")
    report.expectEqual(expected: Tick(0), actual: timeline.tempoMap.first?.tick, cppID: id,
                       what: "A014 default playback tempo starts at tick zero")
    report.expectEqual(expected: 120.0, actual: timeline.tempoMap.first?.beatsPerMinute, cppID: id,
                       what: "A015 default playback tempo is 120 BPM")
    let point = TempoPoint(tick: 24, microsecondsPerQuarterNote: 60_000_000 / 150)
    document.editTempo(TempoEdit(add: [point]))
    report.expectEqual(expected: [point], actual: document.state.tempo, cppID: id,
                       what: "tempo edit installs 150 BPM at tick 24")
    document.editTempo(TempoEdit(remove: [point]))
    report.expect(document.state.tempo.isEmpty, cppID: id,
                  message: "A016 removing the only tempo restores empty typed tempo")
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "tempo removal can be undone")
    report.expectEqual(expected: [point], actual: document.state.tempo, cppID: id,
                       what: "A017 undo restores the 150 BPM point")
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "tempo removal can be redone")
    report.expect(document.state.tempo.isEmpty, cppID: id,
                  message: "A018 redo restores empty typed tempo")
    let saved = try MidiFile.decode(document.captureSave().bytes)
    report.expect(saved.chunks.allSatisfy { chunk in
        chunk.events.allSatisfy { $0.metaType != 0x51 }
    }, cppID: id, message: "A019-A021 saved MIDI contains no tempo meta events in any chunk")
}
