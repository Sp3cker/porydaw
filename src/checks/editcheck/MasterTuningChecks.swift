import Foundation
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback
import PorydawPlaybackNative
import PorydawProject

private let masterTuningID = "no-row/core/master-tuning"

private func tuningAtNotes(_ timeline: PlaybackTimeline) -> [Int] {
    var state = InlineArray<16, Int>(repeating: 0)
    var result: [Int] = []
    for event in timeline.events {
        let track = Int(event.track)
        if event.type == 0xB, event.data0 == 24 {
            state[track] = Int(event.data1) - 64
        } else if event.type == 0x9 {
            result.append(state[track])
        }
    }
    return result
}

private func tuningValues(_ file: MidiFile, chunk: Int) -> [UInt8] {
    file.chunks[chunk].events.compactMap { event in
        guard case .channel(let status, let controller, let value) = event.payload,
            status >> 4 == 0xB, controller == 24
        else { return nil }
        return value
    }
}

private func tuningFixture() -> MidiFile {
    MidiFile(chunks: [
        MidiChunk(
            events: [
                .meta(type: 0x7F, data: [0x7D, 0x01, 0x02]),
                .meta(type: 0x06, data: [0x5B]),
                .meta(tick: 96, type: 0x06, data: [0x5D]),
            ], endTick: 96),
        MidiChunk(
            events: [
                .channel(status: 0xC3, data0: 0),
                .channel(status: 0xB3, data0: 24, data1: 60),
                .channel(status: 0xB3, data0: 24, data1: 62),
                .channel(status: 0x93, data0: 60, data1: 90),
                .channel(tick: 12, status: 0xE3, data0: 17, data1: 70),
                .channel(tick: 24, status: 0xB3, data0: 24, data1: 70),
                .channel(tick: 48, status: 0x83, data0: 60),
            ], endTick: 96),
        // Same channel, independent source chunk. Also exercise a second channel in that chunk.
        MidiChunk(
            events: [
                .channel(status: 0xC3, data0: 0),
                .channel(status: 0x97, data0: 67, data1: 80),
                .channel(status: 0x93, data0: 64, data1: 80),
                .channel(tick: 12, status: 0xB3, data0: 24, data1: 66),
                .channel(tick: 24, status: 0xB7, data0: 24, data1: 67),
                .channel(tick: 48, status: 0x87, data0: 67),
                .channel(tick: 48, status: 0x83, data0: 64),
            ], endTick: 96),
        // This channel exists only in old TUNE events and must survive replacement.
        MidiChunk(
            events: [
                .channel(tick: 17, status: 0xB9, data0: 24, data1: 0),
                .channel(tick: 17, status: 0xB9, data0: 24, data1: 127),
            ], endTick: 96),
    ])
}

@MainActor
private func tuningOverwriteAndHistory(_ report: CheckReport) throws {
    let document = SongDocument(file: tuningFixture())
    let before = document.state
    let mapping = document.engineTracks
    let preserved = before.file.chunks.map { chunk in
        chunk.events.filter { event in
            guard case .channel(let status, let controller, _) = event.payload else { return true }
            return status >> 4 != 0xB || controller != 24
        }
    }
    let identities = document.notes(in: 0).map(\.id) + document.notes(in: 1).map(\.id)
    try document.setMasterTuning(units: 8)
    report.expectEqual(
        expected: [72], actual: tuningValues(document.state.file, chunk: 1),
        cppID: masterTuningID, what: "all duplicate and delayed TUNE points are replaced by one chosen initial value")
    report.expectEqual(
        expected: [72, 72], actual: tuningValues(document.state.file, chunk: 2),
        cppID: masterTuningID, what: "every source channel receives uniform tuning")
    report.expectEqual(
        expected: [72], actual: tuningValues(document.state.file, chunk: 3),
        cppID: masterTuningID, what: "TUNE-only channel survives at the chosen uniform value")
    report.expectEqual(
        expected: mapping, actual: document.engineTracks, cppID: masterTuningID,
        what: "replacement preserves all primary-channel track identities")
    for chunk in document.state.file.chunks {
        for event in chunk.events {
            if case .channel(let status, let controller, let value) = event.payload,
                status >> 4 == 0xB, controller == 24
            {
                report.expect(
                    event.tick == 0 && value == 72, cppID: masterTuningID,
                    message: "every old TUNE is replaced by uniform tick-zero tuning")
            }
        }
    }
    for index in 1..<document.state.file.chunks.count {
        let events = document.state.file.chunks[index].events.filter { event in
            guard case .channel(let status, let controller, _) = event.payload else { return true }
            return status >> 4 != 0xB || controller != 24
        }
        report.expectEqual(
            expected: preserved[index], actual: events, cppID: masterTuningID,
            what: "chunk \(index) notes, bends, program, order and ticks preserved")
    }
    let conductor = document.state.file.chunks[0].events.filter {
        $0.blob?.starts(with: [0x7D] + Array("Porydaw.MasterTuning".utf8)) != true
    }
    report.expectEqual(
        expected: preserved[0], actual: conductor, cppID: masterTuningID,
        what: "loop markers and unrelated sequencer metadata remain byte-for-byte unchanged")
    report.expectEqual(
        expected: identities,
        actual: document.notes(in: 0).map(\.id) + document.notes(in: 1).map(\.id),
        cppID: masterTuningID, what: "tuning preserves note identities")
    let tunedTimeline = PlaybackTimeline.build(state: document.state, sampleRate: playbackCheckSampleRate)
    report.expectEqual(
        expected: Array(repeating: 8, count: tuningAtNotes(tunedTimeline).count),
        actual: tuningAtNotes(tunedTimeline), cppID: masterTuningID,
        what: "every playable note uses the chosen uniform tuning")
    report.expectEqual(
        expected: 1, actual: document.history.undoCount, cppID: masterTuningID,
        what: "master adjustment is one history entry")
    let tuned = document.state
    report.expect(document.history.undoDocument(), cppID: masterTuningID, message: "master tuning undo succeeds")
    report.expectEqual(
        expected: before, actual: document.state, cppID: masterTuningID,
        what: "one undo restores metadata and every event")
    report.expect(document.history.redoDocument(), cppID: masterTuningID, message: "master tuning redo succeeds")
    report.expectEqual(
        expected: tuned, actual: document.state, cppID: masterTuningID,
        what: "one redo restores effective tuning and metadata")
    for units in [-4, 12, 0, 8] { try document.setMasterTuning(units: units) }
    report.expectEqual(
        expected: tuned, actual: document.state, cppID: masterTuningID,
        what: "repeated tuning choices produce the identical canonical state")
    let canonicalRevision = document.revision
    let canonicalHistory = document.history.revision
    let canonicalIdentity = document.history.currentIdentity
    try document.setMasterTuning(units: 8)
    report.expect(
        document.revision == canonicalRevision && document.history.revision == canonicalHistory
            && document.history.currentIdentity == canonicalIdentity && document.state == tuned,
        cppID: masterTuningID, message: "repeating an identical canonical tuning records no mutation or history")
    try tuningNativeChase(document, track: 0, values: [(1, 8), (25, 8)], report: report)
    try tuningNativeChase(document, track: 1, values: [(1, 8), (13, 8)], report: report)

    let savedState = document.state
    let savedRevision = document.revision
    let bytes = try document.captureSave().bytes
    report.expectEqual(
        expected: savedState, actual: document.state, cppID: masterTuningID,
        what: "saving never changes source")
    report.expectEqual(
        expected: savedRevision, actual: document.revision, cppID: masterTuningID,
        what: "saving never publishes an edit")
    let reopened = SongDocument(file: try MidiFile.decode(bytes))
    report.expectEqual(
        expected: 8, actual: reopened.masterTuningUnits, cppID: masterTuningID,
        what: "MIDI metadata reopens the already-applied offset")
    report.expectEqual(
        expected: bytes, actual: try reopened.captureSave().bytes, cppID: masterTuningID,
        what: "save reload save is byte stable without double application")
    try reopened.setMasterTuning(units: 9)
    report.expectEqual(
        expected: [73], actual: tuningValues(reopened.state.file, chunk: 1),
        cppID: masterTuningID, what: "post-reload choice replaces TUNE with the new uniform value")
    var imported = try MidiFile.decode(bytes)
    try MidiImport.rescaleDivision(&imported, to: 48)
    let importedDocument = SongDocument(file: imported)
    report.expectEqual(
        expected: 8, actual: importedDocument.masterTuningUnits, cppID: masterTuningID,
        what: "ordinary MIDI import rescaling preserves master metadata")
}

@MainActor
private func tuningRejection(_ report: CheckReport) throws {
    let document = SongDocument(
        file: MidiFile(chunks: [
            MidiChunk(events: [
                .channel(status: 0xB0, data0: 24, data1: 0),
                .channel(tick: 12, status: 0xB0, data0: 24, data1: 127),
            ])
        ]))
    report.expectEqual(
        expected: -64, actual: document.masterTuningMinimumUnits, cppID: masterTuningID,
        what: "old minimum TUNE does not restrict the supported range")
    report.expectEqual(
        expected: 63, actual: document.masterTuningMaximumUnits, cppID: masterTuningID,
        what: "old maximum TUNE does not restrict the supported range")
    let original = document.state
    try document.setMasterTuning(units: -64)
    report.expectEqual(
        expected: [0], actual: tuningValues(document.state.file, chunk: 0),
        cppID: masterTuningID, what: "minimum supported choice overwrites both old extrema without clipping")
    _ = document.history.undoDocument()
    report.expectEqual(
        expected: original, actual: document.state, cppID: masterTuningID,
        what: "undo restores both original extrema exactly")
    try document.setMasterTuning(units: 63)
    report.expectEqual(
        expected: [127], actual: tuningValues(document.state.file, chunk: 0),
        cppID: masterTuningID, what: "maximum supported choice overwrites both old extrema without clipping")
    _ = document.history.undoDocument()
    try document.setMasterTuning(units: 0)
    report.expectEqual(
        expected: [64], actual: tuningValues(document.state.file, chunk: 0),
        cppID: masterTuningID, what: "explicit neutral choice clears imported automation even at default metadata zero")
    _ = document.history.undoDocument()
    report.expectEqual(
        expected: original, actual: document.state, cppID: masterTuningID,
        what: "one undo of neutral overwrite restores imported automation and absent metadata")
    document.setConfig(SongConfig(masterVolume: 100))
    _ = document.history.undoDocument()
    let state = document.state
    let revision = document.revision
    let identity = document.history.currentIdentity
    let historyRevision = document.history.revision
    let dirty = document.isDirty
    for units in [-65, 64, Int.min, Int.max] {
        do {
            try document.setMasterTuning(units: units)
            report.fail(masterTuningID, "out-of-range \(units) unexpectedly accepted")
        } catch let error as MasterTuningError {
            report.expect(
                error.errorDescription?.contains("supported range") == true,
                cppID: masterTuningID, message: "rejection explains the supported global range")
        }
        report.expect(
            document.state == state && document.revision == revision
                && document.history.currentIdentity == identity && document.history.revision == historyRevision
                && document.history.canRedo && document.isDirty == dirty,
            cppID: masterTuningID, message: "rejected \(units) preserves full state and redo history")
    }
    let reset = SongDocument(file: tuningFixture())
    try reset.setMasterTuning(units: 0)
    reset.writeLane(
        track: 0, lane: .controller(24), from: 0, through: 96,
        points: [LaneWrite(tick: 12, value: 99)])
    let customizedAtNeutral = reset.state
    try reset.setMasterTuning(units: 0)
    report.expectEqual(
        expected: [64], actual: tuningValues(reset.state.file, chunk: 1),
        cppID: masterTuningID,
        what: "explicit neutral choice also replaces automation when stored metadata is already zero")
    _ = reset.history.undoDocument()
    report.expectEqual(
        expected: customizedAtNeutral, actual: reset.state, cppID: masterTuningID,
        what: "neutral overwrite undo restores custom automation and prior zero metadata together")
    for units in -64...63 {
        report.expectEqual(
            expected: units, actual: try MasterTuning.units(frequencyHz: MasterTuning.frequencyHz(units: units)),
            cppID: masterTuningID, what: "nominal A4 round trip for unit \(units)")
    }
    report.expectEqual(
        expected: 440, actual: MasterTuning.frequencyHz(units: 0), cppID: masterTuningID,
        what: "neutral tuning is nominal A4 440 Hz")
    for frequency in [Double.nan, .infinity, -.infinity, 0, -440, 400, 480] {
        do {
            _ = try MasterTuning.units(frequencyHz: frequency)
            report.fail(masterTuningID, "invalid frequency unexpectedly accepted")
        } catch MasterTuningError.invalidFrequency {
            report.pass(masterTuningID, row: "invalid nominal A4 rejected \(frequency)")
        }
    }
}

@MainActor
private func tuningDefaultProjection(_ report: CheckReport) throws {
    let document = SongDocument(file: MidiFile.blankSong())
    try document.setMasterTuning(units: 10)
    guard let added = document.addTrack(voice: 0) else {
        report.fail(masterTuningID, "cannot add tuned track")
        return
    }
    _ = try document.addNotes([NewNote(track: added, tick: 0, pitch: 60, duration: 48, velocity: 90)])
    document.writeLane(
        track: added, lane: .controller(24), from: 0, through: 96,
        points: [LaneWrite(tick: 12, value: 81)])
    // A local point is absolute, not 81 + master again.
    let source = document.state
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: playbackCheckSampleRate)
    let controls = timeline.events.filter { $0.type == 0xB && $0.data0 == 24 && Int($0.track) == added }
    report.expectEqual(
        expected: [74, 81], actual: controls.map(\.data1), cppID: masterTuningID,
        what: "new track playback starts at master baseline before delayed absolute TUNE")
    let saved = try MidiFile.decode(document.captureSave().bytes)
    guard let chunk = document.engineTracks.tracks[added].midiChunk else { return }
    report.expectEqual(
        expected: [74, 81], actual: tuningValues(saved, chunk: chunk), cppID: masterTuningID,
        what: "new track save projects same baseline and absolute automation")
    report.expectEqual(
        expected: source, actual: document.state, cppID: masterTuningID,
        what: "playback and save projections preserve missing source default")
    try tuningNativeChase(document, track: added, values: [(1, 10), (13, 17)], report: report)
    document.deleteLanePoints(
        track: added, lane: .controller(24), points: document.lanePoints(track: added, lane: .controller(24)))
    let cleared = PlaybackTimeline.build(state: document.state, sampleRate: playbackCheckSampleRate)
    report.expectEqual(
        expected: [74],
        actual: cleared.events.filter {
            $0.type == 0xB && $0.data0 == 24 && Int($0.track) == added
        }.map(\.data1), cppID: masterTuningID, what: "deleting all TUNE points restores master baseline")
    try tuningNativeChase(document, track: added, values: [(1, 10), (13, 10)], report: report)
    try document.setMasterTuning(units: 11)
    report.expectEqual(
        expected: [75], actual: tuningValues(document.state.file, chunk: chunk), cppID: masterTuningID,
        what: "subsequent master choice materializes one uniform source baseline")
    document.writeLane(track: added, lane: .controller(24), from: 0, through: 96, points: [])
    report.expectEqual(
        expected: [75], actual: tuningValues(try MidiFile.decode(document.captureSave().bytes), chunk: chunk),
        cppID: masterTuningID, what: "clearing automation via lane rewrite retains projected baseline")
    try document.setMasterTuning(units: 11)
    report.expectEqual(
        expected: [75], actual: tuningValues(document.state.file, chunk: chunk),
        cppID: masterTuningID, what: "explicit unchanged master choice materializes a cleared source lane")
    _ = document.moveTrack(added, to: 0)
    document.deleteTrack(0)
    report.expectEqual(
        expected: 11, actual: document.masterTuningUnits, cppID: masterTuningID,
        what: "track move and deletion preserve applied master metadata")

    let mixed = SongDocument(
        file: MidiFile(chunks: [
            MidiChunk(
                events: [
                    .channel(status: 0xB0, data0: 24, data1: 72),
                    .channel(status: 0x90, data0: 60, data1: 90),
                    .channel(status: 0x91, data0: 67, data1: 80),
                    .channel(tick: 12, status: 0xB1, data0: 24, data1: 70),
                    .channel(tick: 48, status: 0x80, data0: 60),
                    .channel(tick: 48, status: 0x81, data0: 67),
                ], endTick: 96)
        ]))
    let mapping = mixed.engineTracks
    try mixed.setMasterTuning(units: 8)
    report.expectEqual(
        expected: mapping, actual: mixed.engineTracks, cppID: masterTuningID,
        what: "secondary default initialization preserves primary channel identity")
    report.expectEqual(
        expected: [8, 8],
        actual: tuningAtNotes(PlaybackTimeline.build(state: mixed.state, sampleRate: playbackCheckSampleRate)),
        cppID: masterTuningID, what: "mixed-channel explicit and delayed TUNE are intentionally replaced")
    let initialDefaults = mixed.rawChunks[0].events.indices.filter {
        $0 < 2 && mixed.rawChunks[0].events[$0].isChannel
    }
    mixed.deleteRawEvents(chunk: 0, indices: initialDefaults)
    let mixedSave = try MidiFile.decode(mixed.captureSave().bytes)
    report.expectEqual(
        expected: mapping, actual: mixedSave.engineTracks(), cppID: masterTuningID,
        what: "secondary default save projection preserves primary channel identity")
    let mixedTimeline = PlaybackTimeline.build(state: mixed.state, sampleRate: playbackCheckSampleRate)
    report.expectEqual(
        expected: [72, 72],
        actual: mixedTimeline.events.filter {
            $0.type == 0xB && $0.data0 == 24
        }.map(\.data1), cppID: masterTuningID, what: "mixed-channel projected playback keeps save controller ordering")
    report.expectEqual(
        expected: [72, 72], actual: tuningValues(mixedSave, chunk: 0),
        cppID: masterTuningID, what: "mixed-channel save agrees with projected playback")
    report.expectEqual(
        expected: [8, 8],
        actual: tuningAtNotes(mixedTimeline), cppID: masterTuningID,
        what: "cleared mixed-channel lanes project the uniform chosen baseline")
    let reopenedMixed = SongDocument(file: mixedSave)
    report.expectEqual(
        expected: tuningAtNotes(mixedTimeline),
        actual: tuningAtNotes(PlaybackTimeline.build(state: reopenedMixed.state, sampleRate: playbackCheckSampleRate)),
        cppID: masterTuningID, what: "saved mixed-channel note tuning reopens without a baseline regression")
    try tuningNativeChase(mixed, track: 0, values: [(1, 8), (13, 8)], report: report)
    var formatZeroBytes = try mixedSave.encoded()
    formatZeroBytes[9] = 0
    let formatZero = try MidiFile.decode(formatZeroBytes)
    report.expectEqual(
        expected: 2, actual: formatZero.engineTracks().usedTrackCount,
        cppID: masterTuningID, what: "existing format-zero import splits source channels into independent chunks")
    report.expectEqual(
        expected: 8, actual: SongDocument(file: formatZero).masterTuningUnits,
        cppID: masterTuningID, what: "format-zero canonicalization preserves already-applied tuning metadata")
}

@MainActor
private func tuningNativeChase(
    _ document: SongDocument, track: Int, values: [(Tick, Int)], report: CheckReport
) throws {
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: playbackCheckSampleRate)
    guard let engine = PlaybackCheckEngine(), let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(masterTuningID, "missing native engine or fixture root")
        return
    }
    let path = URL(filePath: fixtureRoot).appendingPathComponent("master-tuning-chase.mid")
    try Data(document.captureSave().bytes).write(to: path)
    var native: UnsafeMutablePointer<PdPlaybackData>?
    var error = [CChar](repeating: 0, count: 512)
    let loaded = path.path.withCString { filePath in
        error.withUnsafeMutableBufferPointer {
            pdPlaybackDataLoadFile(filePath, playbackCheckSampleRate, &native, $0.baseAddress, $0.count)
        }
    }
    guard loaded, let native else {
        report.fail(masterTuningID, "native tuned MIDI loading failed")
        return
    }
    defer { pdPlaybackDataRelease(native) }
    for (tick, expected) in values {
        let position = timeline.sample(for: tick)
        Sequencer.chase(engine: engine.pointer, timeline: timeline, position: position)
        report.expectEqual(
            expected: expected, actual: Int(playbackPairEngineTrack(engine.pointer, index: track).tune),
            cppID: masterTuningID, what: "Swift engine chase TUNE at tick \(tick) is \(expected)")
        pdPlayerChase(engine.pointer, native, position)
        report.expectEqual(
            expected: expected, actual: Int(playbackPairEngineTrack(engine.pointer, index: track).tune),
            cppID: masterTuningID, what: "saved MIDI native chase TUNE at tick \(tick) is \(expected)")
    }
}

@MainActor
private func tuningMetadataAndExport(_ report: CheckReport) throws {
    let document = SongDocument(file: tuningFixture())
    try document.setMasterTuning(units: 8)
    let bytes = try document.captureSave().bytes
    let decoded = try MidiFile.decode(bytes)
    let metadata = decoded.chunks[0].events.first { event in
        guard case .meta(let type, let data) = event.payload else { return false }
        return type == 0x7F && data.count > 3
    }
    guard let metadata, let blob = metadata.blob else {
        report.fail(masterTuningID, "missing versioned sequencer-specific metadata")
        return
    }
    var invalid = decoded
    var unsupported = blob
    unsupported[unsupported.count - 2] = 2
    invalid.chunks[0].events.append(.meta(type: 0x7F, data: unsupported))
    invalid.chunks[0].events.sort { $0.tick < $1.tick }
    do {
        _ = try MidiFile.decode(invalid.encoded())
        report.fail(masterTuningID, "unsupported master metadata unexpectedly decoded")
    } catch MasterTuningError.unsupportedMetadata {
        report.pass(masterTuningID, row: "unsupported metadata rejected before double application")
    }
    let index = document.rawChunks[0].events.firstIndex { $0 == metadata }
    if let index { document.deleteRawEvents(chunk: 0, indices: [index]) }
    report.expectEqual(
        expected: 8, actual: document.masterTuningUnits, cppID: masterTuningID,
        what: "raw deletion cannot erase applied tuning provenance")
    try withTempProjectCopy(prefix: "master-tuning-export") { root in
        let midi = root.appendingPathComponent("sound/songs/midi/mus_route101.mid")
        try Data(bytes).write(to: midi)
        let compiled = root.path.withCString { path in
            "mus_route101".withCString { pdc_check_compile_saved_midi(path, $0) }
        }
        report.expectEqual(
            expected: 1, actual: compiled, cppID: masterTuningID,
            what: "ordinary unmodified mid2agb accepts tuned feature save bytes")
        guard compiled == 1 else { return }
        // The normal compressed build above is the production contract. Disable only opcode
        // elision for the second real conversion so every emitted TUNE operand is inspectable.
        try MidiCfg.writeMidiCfgLine(
            midiDir: midi.deletingLastPathComponent(), label: "mus_route101",
            flags: ["-E", "-R50", "-G_fixture_rich", "-V100", "-N"])
        let uncompressed = root.path.withCString { path in
            "mus_route101".withCString { pdc_check_compile_saved_midi(path, $0) }
        }
        report.expectEqual(
            expected: 1, actual: uncompressed, cppID: masterTuningID,
            what: "real converter also produces inspectable uncompressed opcodes")
        guard uncompressed == 1 else { return }
        let assembly = try String(contentsOf: midi.deletingPathExtension().appendingPathExtension("s"), encoding: .utf8)
        let tunes = assembly.components(separatedBy: .newlines).filter { $0.contains("TUNE") }
        report.expectEqual(
            expected: 3, actual: tunes.count, cppID: masterTuningID,
            what: "real converter emits one uniform initial TUNE for each note-bearing chunk/channel")
        report.expect(
            tunes.allSatisfy { $0.contains("c_v+8") }, cppID: masterTuningID,
            message: "every real converter TUNE command uses the selected uniform value")
        report.expect(
            assembly.contains("GOTO"), cppID: masterTuningID,
            message: "real converter retains the missing-initial-TUNE fixture's loop control flow")
    }
}

@MainActor
private func tuningLoopPlayback(_ report: CheckReport) throws {
    // Track 1 has no initial CC24, later automation and a tick-zero loop: the actual
    // exported-loop regression must now intentionally become uniform on every pass.
    let document = SongDocument(file: tuningFixture())
    try document.setMasterTuning(units: 25)
    let timeline = PlaybackTimeline.build(state: document.state, sampleRate: playbackCheckSampleRate)
    guard timeline.hasLoop, timeline.loopStartTick == 0, timeline.loopEndTick == 96,
        let engine = PlaybackCheckEngine()
    else {
        report.fail(masterTuningID, "missing uniform loop fixture or native playback engine")
        return
    }
    report.expect(
        tuningAtNotes(timeline).allSatisfy { $0 == 25 }, cppID: masterTuningID,
        message: "missing-initial-TUNE loop fixture has uniform chosen tuning at every note")
    var sequencer = Sequencer()
    var rendered: UInt64 = 0
    var left = [Float](repeating: 0, count: 512)
    var right = [Float](repeating: 0, count: 512)
    let loopLength = timeline.loopEndSample - timeline.loopStartSample
    for target in [UInt64(1), 25, 97, 121, 193, 217].map({ $0 * playbackCheckSamplesPerTick }) {
        while rendered < target {
            let count = Int(min(UInt64(left.count), target - rendered))
            left.withUnsafeMutableBufferPointer { leftBuffer in
                right.withUnsafeMutableBufferPointer { rightBuffer in
                    sequencer.render(
                        engine: engine.pointer, timeline: timeline,
                        left: UnsafeMutableBufferPointer(start: leftBuffer.baseAddress, count: count),
                        right: UnsafeMutableBufferPointer(start: rightBuffer.baseAddress, count: count),
                        looping: true, muteMask: 0)
                }
            }
            rendered += UInt64(count)
        }
        for track in 0..<timeline.usedTrackCount {
            report.expectEqual(
                expected: 25, actual: Int(playbackPairEngineTrack(engine.pointer, index: track).tune),
                cppID: masterTuningID, what: "uniform native track \(track) tuning after \(target) rendered samples")
        }
        report.expectEqual(
            expected: target % loopLength, actual: sequencer.position,
            cppID: masterTuningID, what: "native playback actually wraps through the retained loop at sample \(target)")
    }
    for track in 0..<timeline.usedTrackCount {
        try tuningNativeChase(document, track: track, values: [(1, 25), (25, 25), (49, 25)], report: report)
    }
}

@MainActor
public func runMasterTuningChecks(_ report: CheckReport) {
    do { try tuningOverwriteAndHistory(report) } catch { report.fail(masterTuningID, "overwrite/history: \(error)") }
    do { try tuningRejection(report) } catch { report.fail(masterTuningID, "rejection: \(error)") }
    do { try tuningDefaultProjection(report) } catch { report.fail(masterTuningID, "default projection: \(error)") }
    do { try tuningLoopPlayback(report) } catch { report.fail(masterTuningID, "uniform loop playback: \(error)") }
    do { try tuningMetadataAndExport(report) } catch { report.fail(masterTuningID, "metadata/export: \(error)") }
}
