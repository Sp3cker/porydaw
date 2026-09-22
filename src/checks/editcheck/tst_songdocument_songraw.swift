import Foundation
import PorydawCore

@MainActor
internal func runRawEventOriginalChecks(_ report: CheckReport) {
    do {
        for loaded in try coreEditCorpusSongs(report) {
            try coreRawMutationRow(report, loaded: loaded)
            try coreRawReorderRow(report, loaded: loaded)
        }
    } catch {
        report.fail("editcheck/EditCheckTest::rawEventMutate", "corpus loading or encoding failed: \(error)")
    }
}

@MainActor
private func coreRawChunk(_ document: SongDocument) -> Int? {
    if let mapped = document.engineTracks.tracks.first?.midiChunk { return mapped }
    if let nonempty = document.rawChunks.firstIndex(where: { !$0.events.isEmpty }) { return nonempty }
    return document.rawChunks.isEmpty ? nil : 0
}

@MainActor
private func coreRawTracksSorted(_ document: SongDocument) -> Bool {
    document.rawChunks.allSatisfy { chunk in
        zip(chunk.events, chunk.events.dropFirst()).allSatisfy { $0.tick <= $1.tick }
    }
}

@MainActor
private func coreRawMutationRow(_ report: CheckReport, loaded: CoreEditCorpusSong) throws {
    let cppID = "editcheck/EditCheckTest::rawEventMutate[\(loaded.label)]"
    report.expect(!loaded.midiPath.isEmpty, cppID: cppID, message: "row has a playable MIDI path")
    let document = SongDocument(file: try MidiFile.decode(loaded.midiBytes),
                                config: loaded.config, source: loaded.source)
    guard let chunk = coreRawChunk(document) else {
        report.fail(cppID, "loaded song has no SMF chunk")
        return
    }
    let baseline = try document.state.file.encoded()
    let channel = document.rawChunks[chunk].events.first(where: \.isChannel)?.channel ?? 0
    let base = coreEditDistantBase(document) + 100
    let before = document.rawChunks[chunk].events.count
    var event = MidiEvent.channel(tick: base, status: 0xB0 | channel, data0: 7, data1: 64)
    document.insertRawEvent(chunk: chunk, event: event)
    report.expectEqual(before + 1, document.rawChunks[chunk].events.count, cppID: cppID,
                       what: "insert increments the raw event count")
    report.expectEqual(1, document.rawChunks[chunk].events.filter { $0 == event }.count,
                       cppID: cppID, what: "inserted event occurs exactly once")
    report.expectEqual(base, document.rawChunks[chunk].endTick, cppID: cppID,
                       what: "insert extends chunk end")
    report.expect(coreRawTracksSorted(document), cppID: cppID, message: "insert keeps all tracks sorted")

    guard let sameTickIndex = document.rawChunks[chunk].events.firstIndex(of: event) else {
        report.fail(cppID, "inserted event is absent")
        return
    }
    event = .channel(tick: base, status: 0xB0 | channel, data0: 7, data1: 99)
    document.modifyRawEvent(chunk: chunk, index: sameTickIndex, event: event)
    report.expectEqual(sameTickIndex, document.rawChunks[chunk].events.firstIndex(of: event),
                       cppID: cppID, what: "same-tick modification retains index")
    report.expect(coreRawTracksSorted(document), cppID: cppID, message: "same-tick modification keeps sorting")

    guard let movingIndex = document.rawChunks[chunk].events.firstIndex(of: event) else {
        report.fail(cppID, "modified event is absent")
        return
    }
    event.tick = 0
    let countBeforeMove = document.rawChunks[chunk].events.filter { $0 == event }.count
    document.modifyRawEvent(chunk: chunk, index: movingIndex, event: event)
    report.expectEqual(countBeforeMove + 1, document.rawChunks[chunk].events.filter { $0 == event }.count,
                       cppID: cppID, what: "tick change creates the destination event")
    report.expectEqual(before + 1, document.rawChunks[chunk].events.count, cppID: cppID,
                       what: "tick change retains event count")
    report.expect(coreRawTracksSorted(document), cppID: cppID, message: "tick change keeps sorting")
    guard let deleteIndex = document.rawChunks[chunk].events.firstIndex(of: event) else {
        report.fail(cppID, "moved event is absent")
        return
    }
    document.deleteRawEvents(chunk: chunk, indices: [deleteIndex])
    report.expectEqual(before, document.rawChunks[chunk].events.count, cppID: cppID,
                       what: "delete restores initial event count")
    document.setChunkEnd(chunk, tick: base + 500)
    report.expectEqual(base + 500, document.rawChunks[chunk].endTick, cppID: cppID,
                       what: "explicit chunk-end extension")
    let lastTick = document.rawChunks[chunk].events.last?.tick ?? 0
    document.setChunkEnd(chunk, tick: 0)
    report.expectEqual(lastTick, document.rawChunks[chunk].endTick, cppID: cppID,
                       what: "chunk end clamps to the last event")
    while document.history.undoDocument() {}
    report.expectEqual(baseline, try document.state.file.encoded(), cppID: cppID,
                       what: "all mutations undo to exact MIDI bytes")
}

@MainActor
private func coreRawReorderRow(_ report: CheckReport, loaded: CoreEditCorpusSong) throws {
    let cppID = "editcheck/EditCheckTest::rawEventReorder[\(loaded.label)]"
    report.expect(!loaded.midiPath.isEmpty, cppID: cppID, message: "row has a playable MIDI path")
    let document = SongDocument(file: try MidiFile.decode(loaded.midiBytes),
                                config: loaded.config, source: loaded.source)
    guard let chunk = coreRawChunk(document) else {
        report.fail(cppID, "loaded song has no SMF chunk")
        return
    }
    let baseline = try document.state.file.encoded()
    let channel = document.rawChunks[chunk].events.first(where: \.isChannel)?.channel ?? 0
    let group = coreEditDistantBase(document) + 1_100
    let first = MidiEvent.channel(tick: group, status: 0xB0 | channel, data0: 7, data1: 1)
    let second = MidiEvent.channel(tick: group, status: 0xB0 | channel, data0: 10, data1: 2)
    let noteOn = MidiEvent.channel(tick: group, status: 0x90 | channel, data0: 60, data1: 100)
    document.insertRawEvent(chunk: chunk, event: first)
    document.insertRawEvent(chunk: chunk, event: second)
    document.insertRawEvent(chunk: chunk, event: noteOn)
    guard let firstIndex = document.rawChunks[chunk].events.firstIndex(of: first) else {
        report.fail(cppID, "first inserted controller is absent")
        return
    }
    let secondIndex = firstIndex + 1
    let noteIndex = firstIndex + 2
    report.expectEqual(secondIndex, document.rawChunks[chunk].events.firstIndex(of: second),
                       cppID: cppID, what: "second controller follows first")
    report.expectEqual(noteIndex, document.rawChunks[chunk].events.firstIndex(of: noteOn),
                       cppID: cppID, what: "note follows controllers")
    let firstBounds = document.rawMoveBounds(chunk: chunk, index: firstIndex)
    report.expect(firstBounds != nil, cppID: cppID, message: "controller move bounds exist")
    report.expectEqual(firstIndex, firstBounds?.lowerBound, cppID: cppID, what: "controller lower bound")
    report.expectEqual(secondIndex, firstBounds?.upperBound, cppID: cppID, what: "controller upper bound")
    let noteBounds = document.rawMoveBounds(chunk: chunk, index: noteIndex)
    report.expect(noteBounds != nil, cppID: cppID, message: "note move bounds exist")
    report.expectEqual(noteIndex, noteBounds?.lowerBound, cppID: cppID, what: "note lower bound")
    report.expectEqual(noteIndex, noteBounds?.upperBound, cppID: cppID, what: "note upper bound")

    document.moveRawEvent(chunk: chunk, index: firstIndex, to: secondIndex)
    report.expectEqual(firstIndex, document.rawChunks[chunk].events.firstIndex(of: second),
                       cppID: cppID, what: "reorder moves second controller before first")
    report.expectEqual(secondIndex, document.rawChunks[chunk].events.firstIndex(of: first),
                       cppID: cppID, what: "reorder moves first controller after second")
    report.expect(coreRawTracksSorted(document), cppID: cppID, message: "reordering keeps sorting")
    let undoCount = try coreEditHistoryCountAtTip(document, report: report, cppID: cppID)
    document.moveRawEvent(chunk: chunk, index: secondIndex, to: noteIndex)
    document.moveRawEvent(chunk: chunk, index: firstIndex, to: 0)
    report.expectEqual(undoCount, try coreEditHistoryCountAtTip(document, report: report, cppID: cppID),
                       cppID: cppID, what: "both forbidden moves leave history entry count unchanged")
    report.expectEqual(secondIndex, document.rawChunks[chunk].events.firstIndex(of: first),
                       cppID: cppID, what: "forbidden moves retain first controller position")
    report.expectEqual(firstIndex, document.rawChunks[chunk].events.firstIndex(of: second),
                       cppID: cppID, what: "forbidden moves retain second controller position")
    _ = document.history.undoDocument()
    report.expectEqual(firstIndex, document.rawChunks[chunk].events.firstIndex(of: first),
                       cppID: cppID, what: "undo restores first controller position")
    report.expectEqual(secondIndex, document.rawChunks[chunk].events.firstIndex(of: second),
                       cppID: cppID, what: "undo restores second controller position")
    _ = document.history.redoDocument()
    report.expectEqual(secondIndex, document.rawChunks[chunk].events.firstIndex(of: first),
                       cppID: cppID, what: "redo restores reordered first controller")
    report.expectEqual(firstIndex, document.rawChunks[chunk].events.firstIndex(of: second),
                       cppID: cppID, what: "redo restores reordered second controller")
    let edited = try document.state.file.encoded()
    while document.history.undoDocument() {}
    report.expectEqual(baseline, try document.state.file.encoded(), cppID: cppID,
                       what: "undo all restores exact baseline bytes")
    while document.history.redoDocument() {}
    report.expectEqual(edited, try document.state.file.encoded(), cppID: cppID,
                       what: "redo all restores exact edited bytes")
}

@MainActor
internal func coreRawEventEditing(_ report: CheckReport, document: SongDocument) {
    let rawBaseline = try? document.captureSave().bytes
    report.expectEqual(Optional(0...1), document.rawMoveBounds(chunk: 0, index: 0),
                       cppID: "editcheck/EditCheckTest::rawEventReorder",
                       what: "setup events reorder only before the note")
    report.expectEqual(Optional(2...2), document.rawMoveBounds(chunk: 0, index: 2),
                       cppID: "editcheck/EditCheckTest::rawEventReorder",
                       what: "note cannot cross pinned setup events")
    document.moveRawEvent(chunk: 0, index: 0, to: 1)
    let firstController: UInt8? = {
        guard case let .channel(_, controller, _) = document.rawChunks[0].events[0].payload else {
            return nil
        }
        return controller
    }()
    report.expectEqual(UInt8(10), firstController,
                       cppID: "editcheck/EditCheckTest::rawEventReorder",
                       what: "same-tick raw order changes")
    _ = document.history.undoDocument()
    let undoControllers = document.rawChunks[0].events.prefix(2).compactMap { event -> UInt8? in
        guard case let .channel(_, controller, _) = event.payload else { return nil }
        return controller
    }
    _ = document.history.redoDocument()
    let redoControllers = document.rawChunks[0].events.prefix(2).compactMap { event -> UInt8? in
        guard case let .channel(_, controller, _) = event.payload else { return nil }
        return controller
    }
    report.expect(undoControllers == [7, 10] && redoControllers == [10, 7],
        cppID: "editcheck/EditCheckTest::rawEventReorder",
        message: "raw reorder undo and redo reproduce the exact event order")

    document.insertRawEvent(chunk: 0,
        event: .systemExclusive(tick: 11, status: 0xF0, data: [0x7D, 1, 2, 0xF7]))
    report.expectEqual([UInt8(0x7D), 1, 2, 0xF7], document.rawChunks[0].events
        .first(where: { $0.isSystemExclusive })?.blob,
        cppID: "editcheck/EditCheckTest::rawEventMutate",
        what: "opaque bytes are stored without normalization")
    if let opaqueIndex = document.rawChunks[0].events.firstIndex(where: { $0.isSystemExclusive }) {
        document.modifyRawEvent(
            chunk: 0, index: opaqueIndex,
            event: .systemExclusive(tick: 11, status: 0xF0, data: [0x7D, 9, 8, 0xF7]))
    }
    let disposable = MidiEvent.channel(tick: 11, status: 0xB0, data0: 11, data1: 77)
    document.insertRawEvent(chunk: 0, event: disposable)
    if let disposableIndex = document.rawChunks[0].events.firstIndex(of: disposable) {
        document.deleteRawEvents(chunk: 0, indices: [disposableIndex])
    }
    report.expectEqual([UInt8(0x7D), 9, 8, 0xF7], document.rawChunks[0].events
        .first(where: { $0.isSystemExclusive })?.blob,
        cppID: "editcheck/EditCheckTest::rawEventMutate",
        what: "modify and delete retain the intended opaque mutation")
    document.setChunkEnd(0, tick: 1)
    report.expectEqual(Tick(11), document.rawChunks[0].endTick,
                       cppID: "editcheck/EditCheckTest::rawEventMutate",
                       what: "chunk end clamps to its last event tick")
    let rawEdited = try? document.captureSave().bytes
    while document.history.undoDocument() {}
    let rawRewound = try? document.captureSave().bytes
    while document.history.redoDocument() {}
    let rawReplayed = try? document.captureSave().bytes
    report.expect(rawRewound == rawBaseline && rawReplayed == rawEdited,
        cppID: "editcheck/EditCheckTest::rawEventMutate",
        message: "raw mutation history fully rewinds to encoded baseline and replays exactly")
}
