import Foundation
import PorydawCore

@MainActor
func documentTrackContracts(_ report: CheckReport) {
    documentDuplicationOwnershipContract(report)
    trackRemapPublicationContract(report)
    documentGlobalMetadataContract(report)
}

@MainActor
private func documentDuplicationOwnershipContract(_ report: CheckReport) {
    let id = "editcheck/EditCheckTest::documentDuplicationOwnership"
    var chunks = [MidiChunk(events: [
        .meta(type: 0x01, data: Array("contract fixture".utf8)),
    ], endTick: 48)]
    chunks.append(MidiChunk(events: [
        .meta(type: 0x03, data: Array("owned channel".utf8)),
        .channel(status: 0xC1, data0: 7),
        .channel(status: 0x91, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x90, data0: 60, data1: 90),
        .channel(tick: 24, status: 0x81, data0: 60),
        .channel(tick: 48, status: 0x80, data0: 60),
    ], endTick: 48))
    for channel in UInt8(2)..<UInt8(16) {
        chunks.append(MidiChunk(events: [
            .channel(status: 0xC0 | channel, data0: channel),
        ], endTick: 48))
    }
    let document = SongDocument(file: MidiFile(division: 24, chunks: chunks))
    var changes: [DocumentChange] = []
    document.onChange = { changes.append($0) }
    report.expectEqual(UInt8(1), document.engineTracks.tracks[0].channel,
                       cppID: id, what: "A110 source owns channel one")
    let source = document.notes(in: 0)
    report.expectEqual(1, source.count, cppID: id, what: "A111 foreign channel is not a second note")
    report.expect(source.first?.tick == 0 && source.first?.pitch == 60 &&
        source.first?.duration == 24 && source.first?.velocity == 100,
        cppID: id, message: "A112-A115 only the channel-one note is projected")
    guard let sourceNote = source.first, let copy = document.duplicateTrack(0) else {
        report.fail(id, "A121 source note or duplicate missing")
        return
    }
    report.expectEqual(UInt8(0), document.engineTracks.tracks[copy].channel,
                       cppID: id, what: "A122 duplicate receives the lowest free channel")
    let copied = document.notes(in: copy)
    report.expectEqual(1, copied.count, cppID: id, what: "A123 copied track has one note")
    report.expect(copied.first?.tick == sourceNote.tick &&
        copied.first?.pitch == sourceNote.pitch &&
        copied.first?.duration == sourceNote.duration &&
        copied.first?.velocity == sourceNote.velocity &&
        copied.first?.id != sourceNote.id,
        cppID: id, message: "A124-A128 duplicate preserves the note but mints its identity")
    report.expectEqual(1, changes.count, cppID: id, what: "A129 duplication publishes once")
    report.expectEqual(TrackRemap(chunkMap: Array(0..<16).map(Optional.some),
                                  engineTrackMap: Array(0..<15).map(Optional.some),
                                  newChunkCount: 17, newEngineTrackCount: 16),
                       changes.last?.trackRemap, cppID: id,
                       what: "A130-A135 duplication publishes complete identity maps and new counts")
    guard let copiedChunk = document.engineTracks.tracks[copy].midiChunk else {
        report.fail(id, "A136 duplicate has no raw chunk")
        return
    }
    let events = document.rawChunks[copiedChunk].events
    report.expectEqual([
        MidiEvent.channel(status: 0xC0, data0: 7),
        .channel(status: 0x90, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 60),
    ], events, cppID: id, what: "A136-A139 duplicate copies only owned channel events")
    report.expectEqual(document.trackBudget, document.engineTracks.usedTrackCount,
                       cppID: id, what: "A140 duplication reaches the track budget")
    report.expect(!document.canAddTrack && document.addTrack(voice: 3) == nil &&
        document.duplicateTrack(0) == nil,
        cppID: id, message: "A141-A142 both track creation paths reject the ceiling")
    guard let copiedID = copied.first?.id else {
        report.fail(id, "A143 copied note has no identity")
        return
    }
    guard document.history.undoDocument(), document.history.redoDocument() else {
        report.fail(id, "A143-A144 duplication undo/redo failed")
        return
    }
    report.expectEqual(sourceNote.tick, document.note(copiedID)?.tick,
                       cppID: id, what: "A143-A144 copied identity remains findable at its tick")
}

@MainActor
private func trackRemapPublicationContract(_ report: CheckReport) {
    let id = "editcheck/EditCheckTest::documentRemapsAndRaw"
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(type: 0x01, data: Array("contract fixture".utf8)),
        ], endTick: 48),
        MidiChunk(events: [
            .channel(status: 0xC0, data0: 1),
            .channel(status: 0x90, data0: 60, data1: 100),
            .channel(status: 0x90, data0: 60, data1: 90),
            .channel(tick: 12, status: 0x80, data0: 60),
            .channel(tick: 24, status: 0x80, data0: 60),
        ], endTick: 48),
        MidiChunk(events: [.channel(status: 0xC1, data0: 2)], endTick: 48),
    ]))
    var changes: [DocumentChange] = []
    document.onChange = { changes.append($0) }
    func expectRemap(_ chunk: [Int?], _ engine: [Int?],
                     _ chunkCount: Int, _ engineCount: Int, _ site: String) {
        report.expectEqual(1, changes.count, cppID: id,
                           what: "\(site) publishes exactly one change")
        report.expectEqual(TrackRemap(chunkMap: chunk, engineTrackMap: engine,
                                      newChunkCount: chunkCount,
                                      newEngineTrackCount: engineCount),
                           changes.last?.trackRemap, cppID: id,
                           what: "\(site) publishes the exact track remap")
        changes.removeAll()
    }
    report.expect(document.moveTrack(0, to: 1), cppID: id, message: "A074 move succeeds")
    expectRemap([0, 2, 1], [1, 0], 3, 2, "A075 move")
    guard document.history.undoDocument() else { report.fail(id, "A076 move undo failed"); return }
    expectRemap([0, 2, 1], [1, 0], 3, 2, "A076 move undo")
    guard document.history.redoDocument() else { report.fail(id, "A077 move redo failed"); return }
    expectRemap([0, 2, 1], [1, 0], 3, 2, "A077 move redo")
    report.expectEqual(2, document.addTrack(voice: 3), cppID: id, what: "A078 added slot")
    expectRemap([0, 1, 2], [0, 1], 4, 3, "A079 add")
    guard document.history.undoDocument() else { report.fail(id, "A080 add undo failed"); return }
    expectRemap([0, 1, 2, nil], [0, 1, nil], 3, 2, "A080 add undo")
    guard document.history.redoDocument() else { report.fail(id, "A081 add redo failed"); return }
    expectRemap([0, 1, 2], [0, 1], 4, 3, "A081 add redo")
    document.deleteTrack(2)
    expectRemap([0, 1, 2, nil], [0, 1, nil], 3, 2, "A082 delete")
    guard document.history.undoDocument() else { report.fail(id, "A083 delete undo failed"); return }
    expectRemap([0, 1, 2], [0, 1], 4, 3, "A083 delete undo")
    guard document.history.redoDocument() else { report.fail(id, "A084 delete redo failed"); return }
    expectRemap([0, 1, 2, nil], [0, 1, nil], 3, 2, "A084 delete redo")
    report.expectEqual(2, document.duplicateTrack(0), cppID: id, what: "A085 duplicate slot")
    expectRemap([0, 1, 2], [0, 1], 4, 3, "A086 duplicate")
    guard document.history.undoDocument() else { report.fail(id, "A087 duplicate undo failed"); return }
    expectRemap([0, 1, 2, nil], [0, 1, nil], 3, 2, "A087 duplicate undo")
    guard document.history.redoDocument() else { report.fail(id, "A088 duplicate redo failed"); return }
    expectRemap([0, 1, 2], [0, 1], 4, 3, "A088 duplicate redo")
    document.insertRawEvent(chunk: 0, event: .meta(tick: 12, type: 0x01,
                                                    data: Array("metadata".utf8)))
    report.expect(changes.count == 1 && changes[0].trackRemap == nil,
                  cppID: id, message: "A089-A090 meta insertion publishes one change without remap")
}

@MainActor
private func documentGlobalMetadataContract(_ report: CheckReport) {
    let id = "editcheck/EditCheckTest::documentGlobalMetadata"
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(type: 0x03, data: Array("lead".utf8)),
            .meta(type: 0x51, data: [0x07, 0xA1, 0x20]),
            .meta(type: 0x58, data: [4, 2, 0x18, 8]),
            .channel(status: 0xC0, data0: 6),
            .channel(status: 0x90, data0: 60, data1: 100),
            .meta(tick: 4, type: 0x01, data: Array("global annotation".utf8)),
            .meta(tick: 12, type: 0x06, data: [0x5B]),
            .meta(tick: 16, type: 0x06, data: [0x3A]),
            .channel(tick: 24, status: 0x80, data0: 60),
        ], endTick: 48),
        MidiChunk(events: [.channel(status: 0xC1, data0: 7)], endTick: 48),
    ]))
    func globalsOriginal() -> Bool {
        var tempos = 0
        var signatures = 0
        var starts = 0
        var labels = 0
        for chunk in document.rawChunks {
            for event in chunk.events {
                guard case let .meta(type, bytes) = event.payload else { continue }
                if type == 0x51 { tempos += 1 }
                if type == 0x58 && bytes.count >= 2 { signatures += 1 }
                if type == 0x06 && bytes == [0x5B] { starts += 1 }
                if type == 0x06 && bytes == [0x3A] { labels += 1 }
            }
        }
        let sigs = document.timeSignatures
        let timeline = PlaybackTimeline.build(state: document.state, sampleRate: 48_000)
        return document.state.tempo == [TempoPoint(tick: 0, microsecondsPerQuarterNote: 500_000)] &&
            sigs.count == 1 && sigs[0].tick == 0 && sigs[0].numerator == 4 &&
            sigs[0].denominatorPower == 2 && timeline.loopStartTick == 12 &&
            timeline.loopEndTick == TimeDefaults.noTick && tempos == 0 &&
            signatures == 1 && starts == 1 && labels == 1
    }
    report.expect(globalsOriginal(), cppID: id, message: "A146 original typed globals and raw counts")
    guard let copy = document.duplicateTrack(0) else {
        report.fail(id, "A147 duplicate failed")
        return
    }
    report.expectEqual(UInt8(2), document.engineTracks.tracks[copy].channel,
                       cppID: id, what: "A148 copy receives channel two")
    guard let chunk = document.engineTracks.tracks[copy].midiChunk else {
        report.fail(id, "A149 duplicate has no raw chunk")
        return
    }
    let events = document.rawChunks[chunk].events
    report.expectEqual(3, events.count, cppID: id,
                       what: "A149 copy has exactly three channel events and no globals")
    report.expectEqual(MidiEvent.channel(status: 0xC2, data0: 6), events.first,
                       cppID: id, what: "A150 rechanneled program")
    report.expectEqual(MidiEvent.channel(status: 0x92, data0: 60, data1: 100),
                       events.indices.contains(1) ? events[1] : nil,
                       cppID: id, what: "A151 rechanneled note on")
    report.expectEqual(MidiEvent.channel(tick: 24, status: 0x82, data0: 60),
                       events.indices.contains(2) ? events[2] : nil,
                       cppID: id, what: "A152 rechanneled note off")
    report.expect(globalsOriginal(), cppID: id, message: "A153 globals survive duplication")
    guard document.moveTrack(copy, to: 0) else { report.fail(id, "A154 move failed"); return }
    report.expect(globalsOriginal(), cppID: id, message: "A155 globals survive move")
    document.deleteTrack(0)
    report.expect(globalsOriginal(), cppID: id, message: "A156 globals survive delete")
    for step in 1...3 {
        guard document.history.undoDocument() else { report.fail(id, "A157 undo \(step) failed"); return }
        report.expect(globalsOriginal(), cppID: id,
                      message: "A157 globals survive undo \(step)")
    }
    for step in 1...3 {
        guard document.history.redoDocument() else { report.fail(id, "A158 redo \(step) failed"); return }
        report.expect(globalsOriginal(), cppID: id,
                      message: "A158 globals survive redo \(step)")
    }
}
