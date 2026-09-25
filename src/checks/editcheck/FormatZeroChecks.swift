import Foundation
import PorydawCore

// MARK: - SongDocument metadata contracts (metadata proof coverage)

private func formatZeroTrackBytes() -> [UInt8] {
    // The format-0 fixture from tst_songdocument_metadata.cpp, verbatim bytes.
    func vlq(_ value: UInt32) -> [UInt8] {
        var digits = [UInt8(value & 0x7F)]
        var rest = value >> 7
        while rest > 0 { digits.insert(UInt8((rest & 0x7F) | 0x80), at: 0); rest >>= 7 }
        return digits
    }
    var track: [UInt8] = []
    var previous: UInt32 = 0
    func emit(_ tick: UInt32, _ bytes: [UInt8]) {
        track.append(contentsOf: vlq(tick - previous))
        track.append(contentsOf: bytes)
        previous = tick
    }
    emit(0, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20])
    emit(0, [0xFF, 0x03, 0x04]) ; track.append(contentsOf: "Song".utf8)
    emit(0, [0xFF, 0x20, 0x01, 0x04])
    emit(0, [0xFF, 0x03, 0x04]) ; track.append(contentsOf: "Lead".utf8)
    emit(0, [0xFF, 0x04, 0x03]) ; track.append(contentsOf: "Gtr".utf8)
    emit(0, [0x91, 60, 100])
    emit(0, [0x94, 64, 100])
    emit(0, [0x97, 67, 100])
    emit(12, [0xFF, 0x06, 0x01, 0x5B])
    emit(12, [0xFF, 0x20, 0x01, 0x07])
    emit(12, [0xFF, 0x03, 0x01, 0x3A])
    emit(24, [0x81, 60, 0])
    emit(24, [0x84, 64, 0])
    emit(24, [0x87, 67, 0])
    emit(36, [0xFF, 0x06, 0x01, 0x5D])
    emit(36, [0xFF, 0x20, 0x01, 0x09])
    emit(36, [0xFF, 0x03, 0x07]) ; track.append(contentsOf: "Ambient".utf8)
    emit(48, [0xFF, 0x2F, 0x00])
    var bytes: [UInt8] = [0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0, 24,
                          0x4D, 0x54, 0x72, 0x6B]
    bytes.append(UInt8((track.count >> 24) & 0xFF))
    bytes.append(UInt8((track.count >> 16) & 0xFF))
    bytes.append(UInt8((track.count >> 8) & 0xFF))
    bytes.append(UInt8(track.count & 0xFF))
    bytes.append(contentsOf: track)
    return bytes
}

@MainActor
func formatZeroCoercionContract(_ report: CheckReport) {
    guard let file = try? MidiFile.decode(formatZeroTrackBytes()) else {
        report.fail("editcheck/EditCheckTest::formatZeroCoercion",
                    "format-0 fixture failed to decode")
        return
    }
    let document = SongDocument(file: file)
    let encodedHeader = (try? file.encoded()).map { Array($0.prefix(10)) }
    report.expectEqual(expected: [0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1], actual: encodedHeader,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "converted file encodes as format 1")
    report.expectEqual(expected: 3, actual: document.engineTracks.usedTrackCount,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "three channel streams map to engine tracks")
    report.expectEqual(expected: UInt8(1), actual: document.engineTracks.tracks[0].channel,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "first engine track keeps channel 1")
    report.expectEqual(expected: UInt8(4), actual: document.engineTracks.tracks[1].channel,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "second engine track keeps channel 4")
    report.expectEqual(expected: UInt8(7), actual: document.engineTracks.tracks[2].channel,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "third engine track keeps channel 7")
    report.expectEqual(expected: 1, actual: document.engineTracks.tracks[0].midiChunk,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "first engine track maps to chunk 1")
    report.expectEqual(expected: UInt8(60), actual: document.notes(in: 0).first?.pitch,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "first track keeps its note key")
    report.expectEqual(expected: Tick(24), actual: document.notes(in: 0).first?.duration,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "first track keeps its note duration")
    report.expectEqual(expected: UInt8(64), actual: document.notes(in: 1).first?.pitch,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "second track keeps its note key")
    report.expectEqual(expected: UInt8(67), actual: document.notes(in: 2).first?.pitch,
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "third track keeps its note key")
    report.expectEqual(expected: "Lead", actual: document.trackName(1),
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "prefixed name lands on the second track")
    report.expectEqual(expected: "", actual: document.trackName(0),
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "first track has no name")
    report.expectEqual(expected: "", actual: document.trackName(2),
                       cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                       what: "third track has no name")
    let chunks = document.rawChunks
    report.expect(chunks[2].events.contains {
        $0.metaType == 0x04 && $0.blob == Array("Gtr".utf8)
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "instrument meta lands on the Lead chunk")
    report.expect(chunks[0].events.contains {
        $0.metaType == 0x03 && $0.blob == [0x3A]
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "prefixed marker lands on the conductor chunk")
    report.expect(!chunks[3].events.contains {
        $0.metaType == 0x03 && $0.blob == [0x3A]
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "marker stays out of the channel-7 chunk")
    report.expect(chunks[4].events.contains {
        $0.metaType == 0x03 && $0.blob == Array("Ambient".utf8)
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "prefixed name lands on the Ambient chunk")
    report.expect(chunks[0].events.enumerated().contains { index, event in
        index > 0 && event.metaType == 0x03 && event.blob == [0x3A] &&
            chunks[0].events[index - 1].metaType == 0x20
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "channel prefix stays adjacent to its marker")
    report.expect(chunks.enumerated().allSatisfy { index, chunk in
        index == 0 || chunk.events.allSatisfy { $0.metaType != 0x20 }
    }, cppID: "editcheck/EditCheckTest::formatZeroCoercion",
    message: "channel prefixes stay out of non-conductor chunks")
    report.expect(document.state.file.chunks.allSatisfy { $0.endTick == 48 },
                  cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                  message: "coerced format-0 chunks close at the encoded end tick")
    report.expect(chunks[0].events.allSatisfy { !$0.isChannel },
                  cppID: "editcheck/EditCheckTest::formatZeroCoercion",
                  message: "conductor chunk holds no channel events")
}

@MainActor
func formatZeroGlobalsContract(_ report: CheckReport) {
    guard let file = try? MidiFile.decode(formatZeroTrackBytes()) else {
        report.fail("editcheck/EditCheckTest::formatZeroGlobals",
                    "format-0 fixture failed to decode")
        return
    }
    let document = SongDocument(file: file)
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
    report.expectEqual(expected: Tick(12), actual: timeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                       what: "converted loop start lands at tick 12")
    report.expectEqual(expected: Tick(36), actual: timeline.loopEndTick,
                       cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                       what: "converted loop end lands at tick 36")
    report.expectEqual(expected: 3, actual: timeline.usedTrackCount,
                       cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                       what: "timeline reports three used tracks")
    report.expectEqual(expected: "Lead", actual: timeline.tracks.count > 1 ? timeline.tracks[1].name : nil,
                       cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                       what: "timeline names the second track Lead")
    report.expectEqual(expected: Tick(12), actual: timeline.loopStartTick,
                       cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                       what: "timeline loop start matches the document")
    report.expect(chunksSortedByTick(document.state.file),
                  cppID: "editcheck/EditCheckTest::formatZeroGlobals",
                  message: "converted chunks are tick-sorted")
}

@MainActor
func formatZeroSaveRoundTripContract(_ report: CheckReport) {
    guard let file = try? MidiFile.decode(formatZeroTrackBytes()) else {
        report.fail("editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                    "format-0 fixture failed to decode")
        return
    }
    let document = SongDocument(file: file)
    let convertedLive = try? document.state.file.encoded()
    guard let snapshot = try? document.captureSave(),
          let saved = try? MidiFile.decode(snapshot.bytes) else {
        report.fail("editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                    "capture or decode failed")
        return
    }
    report.expect(file.wasFormat0,
                  cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                  message: "redecoded source retains format-0 provenance")
    report.expectEqual(expected: try? file.encoded(), actual: snapshot.bytes,
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "redecoded original encodes to the exact saved bytes")
    let tempos = document.state.tempo
    report.expectEqual(expected: 1, actual: tempos.count,
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "one typed tempo point survives conversion")
    var withoutTempos = saved
    for index in withoutTempos.chunks.indices {
        withoutTempos.chunks[index].events.removeAll { $0.metaType == 0x51 }
    }
    report.expectEqual(expected: convertedLive, actual: try? withoutTempos.encoded(),
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "saved bytes without tempo metadata match converted live bytes")
    var tempoOutsideConductor = false
    var tempoFirst = true
    var savedTempos: [TempoPoint] = []
    for (trackIndex, chunk) in saved.chunks.enumerated() {
        var tick: Tick = 0
        var haveTick = false
        var nonTempoAtTick = false
        for event in chunk.events {
            if !haveTick || event.tick != tick {
                tick = event.tick
                haveTick = true
                nonTempoAtTick = false
            }
            guard event.metaType == 0x51, let blob = event.blob else {
                nonTempoAtTick = true
                continue
            }
            tempoOutsideConductor = tempoOutsideConductor || trackIndex != 0
            tempoFirst = tempoFirst && !nonTempoAtTick
            if blob.count == 3 {
                savedTempos.append(TempoPoint(tick: event.tick,
                    microsecondsPerQuarterNote: UInt32(blob[0]) << 16 |
                        UInt32(blob[1]) << 8 | UInt32(blob[2])))
            }
        }
    }
    report.expect(!tempoOutsideConductor,
                  cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                  message: "saved tempos stay in the conductor chunk")
    report.expect(tempoFirst,
                  cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                  message: "saved tempos lead their tick group")
    report.expectEqual(expected: tempos, actual: savedTempos,
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "saved tempos match the typed state")
    report.expectEqual(expected: convertedLive, actual: try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "live bytes survive the save")
    document.renameTrack(0, to: "Bass")
    report.expect(document.moveTrack(0, to: 2),
                  cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                  message: "move to slot 2 succeeds")
    report.expectEqual(expected: "Bass", actual: document.trackName(2),
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "name follows its track across the move")
    while document.history.canUndo { _ = document.history.undoDocument() }
    report.expectEqual(expected: convertedLive, actual: try? document.state.file.encoded(),
                       cppID: "editcheck/EditCheckTest::formatZeroSaveRoundTrip",
                       what: "undo-all restores the converted bytes")
}

