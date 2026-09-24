import Foundation
import PorydawCore

@MainActor
func runEventViewsEditsParityChecks(_ report: CheckReport) {
    eventViewsChannelAndDataConversions(report)
    eventViewsRawTempoAtomic(report)
    eventViewsSameTickReorder(report)
}

@MainActor
private func eventViewsChannelAndDataConversions(_ report: CheckReport) {
    let id = "eventviews/EventViewsEditsTest::channelAndDataConversions"
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(type: 0x06, data: Array("marker".utf8)),
            .channel(tick: 12, status: 0x90, data0: 60, data1: 90),
        ], endTick: 12),
    ]))
    guard let noteIndex = document.rawChunks[0].events.firstIndex(where: {
        $0.tick == 12 && $0.isNoteOn
    }) else {
        report.fail(id, "fixture note-on at tick 12 is absent")
        return
    }
    guard let blobIndex = document.rawChunks[0].events.firstIndex(where: {
        $0.tick == 0 && $0.isMeta
    }) else {
        report.fail(id, "fixture tick-zero meta is absent")
        return
    }
    guard let noteID = document.rawChunks[0].events[noteIndex].noteID else {
        report.fail(id, "fixture note-on carries no identity")
        return
    }
    let before = document.history.undoIndex
    var channel = document.rawChunks[0].events[noteIndex]
    channel.payload = .channel(status: 0x94, data0: 60, data1: 90)
    document.modifyRawEvent(chunk: 0, index: noteIndex, event: channel)
    report.expectEqual(before + 1, document.history.undoIndex, cppID: id,
                       what: "channel edit pushes one undo step")
    report.expectEqual(UInt8(0x04), document.rawChunks[0].events[noteIndex].status & 0x0F,
                       cppID: id, what: "one-based channel value converts to the status nibble")
    report.expectEqual(Optional(noteID), document.rawChunks[0].events[noteIndex].noteID,
                       cppID: id, what: "channel edit preserves the note identity")
    report.expect(document.note(noteID) != nil, cppID: id,
                  message: "channel-edited note still resolves by identity")
    document.modifyRawEvent(chunk: 0, index: noteIndex,
                            event: .channel(tick: 12, status: 0x94, data0: 100, data1: 90))
    document.modifyRawEvent(chunk: 0, index: noteIndex,
                            event: .channel(tick: 12, status: 0x94, data0: 100, data1: 33))
    report.expectEqual(before + 3, document.history.undoIndex, cppID: id,
                       what: "data-byte edits push one undo step each")
    guard case let .channel(_, data0, data1) = document.rawChunks[0].events[noteIndex].payload
    else {
        report.fail(id, "edited event left the channel domain")
        return
    }
    report.expectEqual(UInt8(100), data0, cppID: id,
                       what: "first data byte stores the edited value")
    report.expectEqual(UInt8(33), data1, cppID: id,
                       what: "second data byte stores the edited value")
    report.expectEqual(Optional(noteID), document.rawChunks[0].events[noteIndex].noteID,
                       cppID: id, what: "data-byte edits preserve the note identity")
    document.modifyRawEvent(chunk: 0, index: blobIndex,
                            event: .meta(type: 0x06, data: Array("room".utf8)))
    report.expectEqual(before + 4, document.history.undoIndex, cppID: id,
                       what: "blob edit pushes one undo step")
    report.expectEqual(Optional(Array("room".utf8)), document.rawChunks[0].events[blobIndex].blob,
                       cppID: id, what: "blob edit stores the quoted payload bytes")
    while document.history.undoIndex > before {
        _ = document.history.undoDocument()
    }
    report.expectEqual(UInt8(0x00), document.rawChunks[0].events[noteIndex].status & 0x0F,
                       cppID: id, what: "undo restores the original channel nibble")
    guard case let .channel(_, restored0, restored1) =
        document.rawChunks[0].events[noteIndex].payload else {
        report.fail(id, "undone event left the channel domain")
        return
    }
    report.expectEqual(UInt8(60), restored0, cppID: id,
                       what: "undo restores the original first data byte")
    report.expectEqual(UInt8(90), restored1, cppID: id,
                       what: "undo restores the original second data byte")
    report.expectEqual(Optional(noteID), document.rawChunks[0].events[noteIndex].noteID,
                       cppID: id, what: "undo restores the note identity")
    report.expectEqual(Optional(Array("marker".utf8)),
                       document.rawChunks[0].events[blobIndex].blob,
                       cppID: id, what: "undo restores the original blob bytes")
    document.modifyRawEvent(chunk: 0, index: noteIndex,
                            event: .channel(tick: 99, status: 0xB0, data0: 7, data1: 10))
    report.expect(document.rawChunks[0].events[noteIndex].noteID == nil, cppID: id,
                  message: "note-on to controller conversion clears the identity")
    document.modifyRawEvent(chunk: 0, index: noteIndex,
                            event: .channel(tick: 99, status: 0x90, data0: 61, data1: 70))
    guard let convertedID = document.rawChunks[0].events[noteIndex].noteID else {
        report.fail(id, "controller to note-on conversion mints no identity")
        return
    }
    report.expect(convertedID != noteID, cppID: id,
                  message: "converted note-on mints a fresh identity")
    report.expect(document.note(convertedID) != nil, cppID: id,
                  message: "converted note-on resolves by its minted identity")
}

@MainActor
private func eventViewsRawTempoAtomic(_ report: CheckReport) {
    let id = "eventviews/EventViewsEditsTest::rawTempoAtomic"
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [
            .meta(type: 0x06, data: Array("intro".utf8)),
            .meta(type: 0x03, data: Array("Tempo".utf8)),
            .meta(type: 0x51, data: [0x07, 0xA1, 0x20]),
            .meta(tick: 4, type: 0x51, data: [0x07, 0xA1, 0x20]),
            .channel(tick: 8, status: 0x90, data0: 60, data1: 90),
        ], endTick: 8),
    ]))
    let tickZeroMeta = document.rawChunks[0].events.filter { $0.tick == 0 && $0.isMeta }
    guard !tickZeroMeta.isEmpty else {
        report.fail(id, "fixture has no tick-zero metas")
        return
    }
    guard document.state.tempo.contains(where: { $0.tick == 0 }) else {
        report.fail(id, "fixture has no tick-zero tempo")
        return
    }
    var conversionTick = document.rawChunks[0].endTick
    for event in document.rawChunks[0].events {
        conversionTick = max(conversionTick, event.tick)
    }
    for point in document.state.tempo {
        conversionTick = max(conversionTick, point.tick)
    }
    conversionTick += 1
    document.insertRawEvent(chunk: 0, event: .meta(tick: conversionTick, type: 0x06,
                                                  data: Array("eventviews conversion".utf8)))
    guard let conversionIndex = document.rawChunks[0].events.firstIndex(where: {
        $0.tick == conversionTick && $0.isMeta
    }) else {
        report.fail(id, "conversion marker is absent")
        return
    }
    let initialIndex = document.history.undoIndex
    let initialCount = document.history.undoCount
    var publications = 0
    document.onChange = { _ in publications += 1 }
    document.editRawAndTempo(chunk: 0, deleting: [conversionIndex],
        tempo: TempoEdit(add: [TempoPoint(tick: conversionTick,
                                          microsecondsPerQuarterNote: 500_000)]))
    report.expectEqual(1, publications, cppID: id,
                       what: "meta-to-tempo conversion publishes once")
    report.expectEqual(initialIndex + 1, document.history.undoIndex, cppID: id,
                       what: "meta-to-tempo conversion pushes one undo step")
    report.expectEqual(initialCount + 1, document.history.undoCount, cppID: id,
                       what: "meta-to-tempo conversion records one entry")
    report.expect(document.state.tempo.contains(where: { $0.tick == conversionTick }), cppID: id,
                  message: "converted tick carries a tempo point")
    report.expect(!document.rawChunks[0].events.contains(where: {
        $0.tick == conversionTick && $0.isMeta
    }), cppID: id, message: "converted tick carries no raw meta")
    report.expectEqual(tickZeroMeta,
                       document.rawChunks[0].events.filter { $0.tick == 0 && $0.isMeta },
                       cppID: id, what: "meta-to-tempo conversion preserves tick-zero metas")
    report.expect(document.state.tempo.contains(where: { $0.tick == 0 }), cppID: id,
                  message: "tick-zero tempo survives conversion")
    publications = 0
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "conversion undo succeeds")
    report.expectEqual(1, publications, cppID: id, what: "conversion undo publishes once")
    report.expectEqual(initialIndex, document.history.undoIndex, cppID: id,
                       what: "conversion undo restores the index")
    report.expectEqual(initialCount + 1, document.history.undoCount, cppID: id,
                       what: "conversion undo retains the entry")
    report.expectEqual(Optional(Array("eventviews conversion".utf8)),
                       document.rawChunks[0].events.first(where: {
                           $0.tick == conversionTick && $0.isMeta
                       }).flatMap(\.blob),
                       cppID: id, what: "conversion undo restores the marker bytes")
    report.expect(!document.state.tempo.contains(where: { $0.tick == conversionTick }),
                  cppID: id, message: "conversion undo removes the tempo point")
    publications = 0
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "conversion redo succeeds")
    report.expectEqual(1, publications, cppID: id, what: "conversion redo publishes once")
    report.expectEqual(initialIndex + 1, document.history.undoIndex, cppID: id,
                       what: "conversion redo restores the index")
    report.expectEqual(initialCount + 1, document.history.undoCount, cppID: id,
                       what: "conversion redo retains the entry")
    report.expect(document.state.tempo.contains(where: { $0.tick == conversionTick }), cppID: id,
                  message: "conversion redo restores the tempo point")
    report.expect(!document.rawChunks[0].events.contains(where: {
        $0.tick == conversionTick && $0.isMeta
    }), cppID: id, message: "conversion redo removes the raw meta")
    publications = 0
    document.editRawAndTempo(chunk: 0, deleting: [],
        tempo: TempoEdit(remove: [TempoPoint(tick: conversionTick,
                                             microsecondsPerQuarterNote: 500_000)]),
        inserting: .meta(tick: conversionTick, type: 0x06, data: []))
    report.expectEqual(1, publications, cppID: id,
                       what: "tempo-to-meta conversion publishes once")
    report.expectEqual(initialIndex + 2, document.history.undoIndex, cppID: id,
                       what: "tempo-to-meta conversion pushes a second undo step")
    report.expectEqual(initialCount + 2, document.history.undoCount, cppID: id,
                       what: "tempo-to-meta conversion records a second entry")
    report.expect(document.rawChunks[0].events.contains(where: {
        $0.tick == conversionTick && $0.isMeta
    }), cppID: id, message: "converted tempo returns as a raw meta")
    report.expect(!document.state.tempo.contains(where: { $0.tick == conversionTick }),
                  cppID: id, message: "tempo point is gone after conversion to meta")
    report.expectEqual(tickZeroMeta,
                       document.rawChunks[0].events.filter { $0.tick == 0 && $0.isMeta },
                       cppID: id, what: "tempo-to-meta conversion preserves tick-zero metas")
    report.expect(document.state.tempo.contains(where: { $0.tick == 0 }), cppID: id,
                  message: "tick-zero tempo survives the reverse conversion")
    publications = 0
    report.expect(document.history.undoDocument(), cppID: id,
                  message: "reverse-conversion undo succeeds")
    report.expectEqual(1, publications, cppID: id, what: "reverse-conversion undo publishes once")
    report.expectEqual(initialIndex + 1, document.history.undoIndex, cppID: id,
                       what: "reverse-conversion undo restores the index")
    report.expectEqual(initialCount + 2, document.history.undoCount, cppID: id,
                       what: "reverse-conversion undo retains both entries")
    report.expect(document.state.tempo.contains(where: { $0.tick == conversionTick }), cppID: id,
                  message: "reverse-conversion undo restores the tempo point")
    report.expect(!document.rawChunks[0].events.contains(where: {
        $0.tick == conversionTick && $0.isMeta
    }), cppID: id, message: "reverse-conversion undo removes the raw meta")
    publications = 0
    report.expect(document.history.redoDocument(), cppID: id,
                  message: "reverse-conversion redo succeeds")
    report.expectEqual(1, publications, cppID: id, what: "reverse-conversion redo publishes once")
    report.expectEqual(initialIndex + 2, document.history.undoIndex, cppID: id,
                       what: "reverse-conversion redo restores the index")
    report.expectEqual(initialCount + 2, document.history.undoCount, cppID: id,
                       what: "reverse-conversion redo retains both entries")
    report.expect(document.rawChunks[0].events.contains(where: {
        $0.tick == conversionTick && $0.isMeta
    }), cppID: id, message: "reverse-conversion redo restores the raw meta")
    report.expect(!document.state.tempo.contains(where: { $0.tick == conversionTick }),
                  cppID: id, message: "reverse-conversion redo removes the tempo point")
    report.expectEqual(tickZeroMeta,
                       document.rawChunks[0].events.filter { $0.tick == 0 && $0.isMeta },
                       cppID: id, what: "settled conversion preserves tick-zero metas")
    report.expect(document.state.tempo.contains(where: { $0.tick == 0 }), cppID: id,
                  message: "tick-zero tempo survives the settled conversion")
    document.onChange = nil
}

@MainActor
private func eventViewsSameTickReorder(_ report: CheckReport) {
    let id = "eventviews/EventViewsEditsTest::sameTickReorder"
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.channel(tick: 12, status: 0x90, data0: 60, data1: 90)],
                  endTick: 12),
    ]))
    guard let chunkEnd = document.rawChunks.first?.endTick else {
        report.fail(id, "fixture chunk is absent")
        return
    }
    let tick = chunkEnd + 100
    let ccA = MidiEvent.channel(tick: tick, status: 0xB0, data0: 7, data1: 1)
    let ccB = MidiEvent.channel(tick: tick, status: 0xB0, data0: 10, data1: 2)
    let noteOn = MidiEvent.channel(tick: tick, status: 0x90, data0: 60, data1: 90)
    document.insertRawEvent(chunk: 0, event: ccA)
    document.insertRawEvent(chunk: 0, event: ccB)
    document.insertRawEvent(chunk: 0, event: noteOn)
    guard let noteOnIndex = document.rawChunks[0].events.firstIndex(where: {
        $0.tick == tick && $0.isNoteOn
    }) else {
        report.fail(id, "inserted note-on is absent")
        return
    }
    guard let mintedID = document.rawChunks[0].events[noteOnIndex].noteID else {
        report.fail(id, "inserted note-on carries no minted identity")
        return
    }
    report.expect(document.note(mintedID) != nil, cppID: id,
                  message: "inserted note-on resolves by its minted identity")
    let preset = NoteID(UInt64.max)
    let presetTick = tick + 50
    let presetOn = MidiEvent.channel(tick: presetTick, status: 0x90, data0: 62, data1: 90, noteID: preset)
    document.insertRawEvent(chunk: 0, event: presetOn)
    guard let presetIndex = document.rawChunks[0].events.firstIndex(where: {
        $0.tick == presetTick && $0.isNoteOn
    }) else {
        report.fail(id, "inserted preset note-on is absent")
        return
    }
    guard let fresh = document.rawChunks[0].events[presetIndex].noteID else {
        report.fail(id, "inserted preset note-on carries no minted identity")
        return
    }
    report.expect(fresh != preset, cppID: id,
                  message: "inserted preset note-on mints a fresh identity")
    report.expect(document.note(fresh) != nil, cppID: id,
                  message: "preset insert resolves by its fresh identity")
    guard let first = document.rawChunks[0].events.firstIndex(of: ccA) else {
        report.fail(id, "first controller is absent")
        return
    }
    report.expectEqual(first + 1, document.rawChunks[0].events.firstIndex(of: ccB), cppID: id,
                       what: "second controller follows first")
    report.expectEqual(first + 2, document.rawChunks[0].events.firstIndex(of: noteOn),
                       cppID: id, what: "note follows controllers")
    let second = first + 1
    let note = first + 2
    let swapBase = document.history.undoIndex
    document.moveRawEvent(chunk: 0, index: first, to: second)
    report.expectEqual(first, document.rawChunks[0].events.firstIndex(of: ccB), cppID: id,
                       what: "legal in-run swap moves the second controller first")
    report.expectEqual(second, document.rawChunks[0].events.firstIndex(of: ccA), cppID: id,
                       what: "legal in-run swap moves the first controller second")
    report.expectEqual(swapBase + 1, document.history.undoIndex, cppID: id,
                       what: "legal in-run swap pushes one undo step")
    let orderAfterDrop = document.history.undoIndex
    document.moveRawEvent(chunk: 0, index: second, to: note + 10)
    report.expectEqual(second, document.rawChunks[0].events.firstIndex(of: ccA), cppID: id,
                       what: "past-run destination cannot displace the event")
    report.expectEqual(orderAfterDrop, document.history.undoIndex, cppID: id,
                       what: "past-run destination pushes no undo step")
    document.moveRawEvent(chunk: 0, index: note, to: 0)
    report.expectEqual(note, document.rawChunks[0].events.firstIndex(of: noteOn), cppID: id,
                       what: "cross-run destination cannot displace the note")
    report.expectEqual(orderAfterDrop, document.history.undoIndex, cppID: id,
                       what: "cross-run destination pushes no undo step")
    guard let runEnd = document.rawChunks.first?.endTick else {
        report.fail(id, "fixture chunk vanished")
        return
    }
    let pinnedTick = runEnd + 200
    let pinnedOn = MidiEvent.channel(tick: pinnedTick, status: 0x90, data0: 61, data1: 88)
    let pinnedOff = MidiEvent.channel(tick: pinnedTick, status: 0x80, data0: 61)
    document.insertRawEvent(chunk: 0, event: pinnedOn)
    document.insertRawEvent(chunk: 0, event: pinnedOff)
    guard let offIndex = document.rawChunks[0].events.firstIndex(of: pinnedOff) else {
        report.fail(id, "pinned note-end is absent")
        return
    }
    report.expectEqual(offIndex + 1, document.rawChunks[0].events.firstIndex(of: pinnedOn),
                       cppID: id, what: "note-end pins ahead of its note-on")
    guard let onIndex = document.rawChunks[0].events.firstIndex(of: pinnedOn) else {
        report.fail(id, "pinned note-on is absent")
        return
    }
    let orderBeforePin = document.history.undoIndex
    document.moveRawEvent(chunk: 0, index: offIndex, to: onIndex)
    report.expectEqual(offIndex, document.rawChunks[0].events.firstIndex(of: pinnedOff),
                       cppID: id, what: "pinned note-end stays ahead of its note-on")
    report.expectEqual(onIndex, document.rawChunks[0].events.firstIndex(of: pinnedOn), cppID: id,
                       what: "pinned note-on stays after its note-end")
    report.expectEqual(orderBeforePin, document.history.undoIndex, cppID: id,
                       what: "pinned reorder pushes no undo step")
    let undoBeforeMenuMove = document.history.undoIndex
    document.moveRawEvent(chunk: 0, index: first, to: second)
    report.expectEqual(first, document.rawChunks[0].events.firstIndex(of: ccA), cppID: id,
                       what: "row move down restores the first controller")
    report.expectEqual(second, document.rawChunks[0].events.firstIndex(of: ccB), cppID: id,
                       what: "row move down advances the second controller")
    report.expectEqual(note, document.rawChunks[0].events.firstIndex(of: noteOn), cppID: id,
                       what: "row move down keeps the note in place")
    report.expectEqual(undoBeforeMenuMove + 1, document.history.undoIndex, cppID: id,
                       what: "row move down pushes one undo step")
    _ = document.history.undoDocument()
    report.expectEqual(second, document.rawChunks[0].events.firstIndex(of: ccA), cppID: id,
                       what: "undo restores the swapped first controller")
    report.expectEqual(first, document.rawChunks[0].events.firstIndex(of: ccB), cppID: id,
                       what: "undo restores the swapped second controller")
    let undoBeforeKeyMove = document.history.undoIndex
    document.moveRawEvent(chunk: 0, index: first, to: second)
    report.expectEqual(first, document.rawChunks[0].events.firstIndex(of: ccA), cppID: id,
                       what: "key move down restores the first controller")
    report.expectEqual(second, document.rawChunks[0].events.firstIndex(of: ccB), cppID: id,
                       what: "key move down advances the second controller")
    report.expectEqual(undoBeforeKeyMove + 1, document.history.undoIndex, cppID: id,
                       what: "key move down pushes one undo step")
    _ = document.history.undoDocument()
    report.expectEqual(second, document.rawChunks[0].events.firstIndex(of: ccA), cppID: id,
                       what: "undo restores the key-moved first controller")
    let orderBeforeBoundaryMove = document.history.undoIndex
    document.moveRawEvent(chunk: 0, index: first, to: 0)
    report.expectEqual(second, document.rawChunks[0].events.firstIndex(of: ccA), cppID: id,
                       what: "boundary move cannot displace into the earlier run")
    report.expectEqual(orderBeforeBoundaryMove, document.history.undoIndex, cppID: id,
                       what: "boundary move pushes no undo step")
}
