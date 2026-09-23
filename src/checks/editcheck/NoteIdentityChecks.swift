import PorydawCore

private let parsedIdentityID = "noteidcheck/NoteIdentityCheckTest::parsedMidiLeavesIdsUnassigned"
private let adoptedIdentityID = "noteidcheck/NoteIdentityCheckTest::adoptedSmfRemintsForeignIds"
private let equalityIdentityID = "noteidcheck/NoteIdentityCheckTest::identityDoesNotAffectEqualityOrSerialization"
private let timelineIdentityID = "noteidcheck/NoteIdentityCheckTest::timelineTransportsOnlyStampedNoteIds"

private func duplicateNoteFile() -> MidiFile {
    let noteOn = MidiEvent.channel(tick: 24, status: 0x90, data0: 60, data1: 100)
    return MidiFile(division: 24, chunks: [MidiChunk(events: [
        noteOn, noteOn,
        .channel(tick: 48, status: 0x80, data0: 60),
    ], endTick: 72)])
}

@MainActor
func noteIdentityContracts(_ report: CheckReport) {
    let source = duplicateNoteFile()
    do {
        let bytes = try source.encoded()
        let decoded = try MidiFile.decode(bytes)
        report.expectEqual(1, decoded.chunks.count, cppID: parsedIdentityID,
                           what: "decoded MIDI retains one chunk")
        if let events = decoded.chunks.first?.events {
            report.expectEqual(3, events.count, cppID: parsedIdentityID,
                               what: "decoded MIDI retains three lifecycle events")
            if events.count == 3 {
                report.expect(events[0].isNoteOn, cppID: parsedIdentityID,
                              message: "first duplicate is a note-on")
                report.expect(events[1].isNoteOn, cppID: parsedIdentityID,
                              message: "second duplicate is a note-on")
                report.expect(events[2].isNoteEnd, cppID: parsedIdentityID,
                              message: "third event is a note-end")
                report.expect(!(events[0].noteID?.isAssigned ?? false), cppID: parsedIdentityID,
                              message: "first parsed note-on has no identity")
                report.expect(!(events[1].noteID?.isAssigned ?? false), cppID: parsedIdentityID,
                              message: "second parsed note-on has no identity")
                report.expect(!(events[2].noteID?.isAssigned ?? false), cppID: parsedIdentityID,
                              message: "parsed note-end has no identity")
            }
        }

        let timeline = PlaybackTimeline.build(
            state: SongState(file: decoded, tempo: [], config: SongConfig()),
            sampleRate: 48_000)
        let rawOns = timeline.events.filter { $0.type == 0x9 && $0.tick == 24 }
        let rawEnds = timeline.events.filter { $0.type == 0x8 && $0.tick == 48 }
        report.expectEqual(2, rawOns.count, cppID: parsedIdentityID,
                           what: "two raw note-ons reach playback")
        report.expect(rawOns.allSatisfy { !$0.noteID.isAssigned }, cppID: parsedIdentityID,
                      message: "raw playback does not mint note-on identities")
        report.expect(rawEnds.count == 1 && !rawEnds[0].noteID.isAssigned,
                      cppID: parsedIdentityID,
                      message: "raw playback note-end remains unassigned")
    } catch {
        report.fail(parsedIdentityID, "MIDI encode/decode failed: \(error)")
    }

    let firstDocument = SongDocument(file: source)
    let original = firstDocument.notes(in: 0).map(\.id)
    report.expect(original.count == 2 && original.allSatisfy(\.isAssigned)
                  && Set(original).count == 2, cppID: adoptedIdentityID,
                  message: "initial adoption projects two assigned, distinct note-ons")
    // SongDocument identities are scoped to each document; a new document remints
    // its incoming events, but may reuse numeric values from the old document.
    let readopted = SongDocument(file: firstDocument.state.file)
    do {
        _ = try readopted.addNotes([
            NewNote(track: 0, tick: 96, pitch: 64, duration: 24, velocity: 80),
        ])
        let ids = readopted.notes(in: 0).map(\.id)
        report.expectEqual(3, ids.count, cppID: adoptedIdentityID,
                           what: "readoption followed by insertion produces three notes")
        report.expect(ids.allSatisfy(\.isAssigned), cppID: adoptedIdentityID,
                      message: "every readopted and newly inserted identity is assigned")
        report.expectEqual(ids.count, Set(ids).count, cppID: adoptedIdentityID,
                           what: "readopted and newly inserted identities are pairwise distinct")
    } catch {
        report.fail(adoptedIdentityID, "adding a note after readoption failed: \(error)")
    }

    let firstID = NoteID(1)
    let secondID = NoteID(2)
    report.expect(firstID.isAssigned, cppID: equalityIdentityID,
                  message: "first synthetic identity is assigned")
    report.expect(secondID.isAssigned, cppID: equalityIdentityID,
                  message: "second synthetic identity is assigned")
    report.expect(firstID != secondID, cppID: equalityIdentityID,
                  message: "synthetic identities differ")
    var stamped = source
    stamped.chunks[0].events[0].noteID = firstID
    stamped.chunks[0].events[1].noteID = secondID
    report.expect(stamped.chunks[0].events[0] == stamped.chunks[0].events[1],
                  cppID: equalityIdentityID,
                  message: "otherwise identical MIDI events compare equal despite different IDs")
    do {
        report.expectEqual(try source.encoded(), try stamped.encoded(),
                           cppID: equalityIdentityID,
                           what: "stamped and unstamped MIDI serialize identically")
    } catch {
        report.fail(equalityIdentityID, "MIDI serialization failed: \(error)")
    }

    let stampedTimeline = PlaybackTimeline.build(
        state: SongState(file: stamped, tempo: [], config: SongConfig()),
        sampleRate: 48_000)
    let stampedOns = stampedTimeline.events.filter { $0.type == 0x9 && $0.tick == 24 }
    let stampedEnds = stampedTimeline.events.filter { $0.type == 0x8 && $0.tick == 48 }
    report.expectEqual(2, stampedOns.count, cppID: timelineIdentityID,
                       what: "both stamped note-ons reach playback")
    report.expect(stampedOns.contains { $0.noteID == firstID }, cppID: timelineIdentityID,
                  message: "first stamped identity reaches playback")
    report.expect(stampedOns.contains { $0.noteID == secondID }, cppID: timelineIdentityID,
                  message: "second stamped identity reaches playback")
    report.expect(stampedEnds.count == 1 && !stampedEnds[0].noteID.isAssigned,
                  cppID: timelineIdentityID,
                  message: "playback note-end stays unassigned")
}
