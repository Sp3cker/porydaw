import Foundation
import PorydawApp
import PorydawCore
import PorydawDocument
import PorydawProject

// Open the vanilla fixture, edit one velocity, and prove the saved event streams
// preserve every event except that velocity. The locator never uses the codec.

// A nonzero 0x9x event found by the independent raw-SMF scan, with the exact
// file offset of its velocity (second data) byte.
private struct RawSMFNoteOn {
    var tick: UInt64
    var channel: UInt8
    var pitch: UInt8
    var velocity: UInt8
    var velocityOffset: Int
}

private func readSMFVLQ(_ bytes: [UInt8], index: inout Int, limit: Int) -> UInt64? {
    var value: UInt64 = 0
    for _ in 0..<4 {
        guard index < limit else { return nil }
        let byte = bytes[index]
        index += 1
        value = (value << 7) | UInt64(byte & 0x7F)
        if byte & 0x80 == 0 { return value }
    }
    return nil
}

private func firstRawNoteOnInTrack(_ bytes: [UInt8], lower: Int, upper: Int) -> RawSMFNoteOn? {
    var index = lower
    var tick: UInt64 = 0
    var running: UInt8?
    while index < upper {
        guard let delta = readSMFVLQ(bytes, index: &index, limit: upper) else { return nil }
        tick &+= delta
        guard index < upper else { return nil }
        let byte = bytes[index]
        if byte == 0xFF {
            index += 1
            guard index < upper else { return nil }
            index += 1
            guard let length = readSMFVLQ(bytes, index: &index, limit: upper),
                length <= UInt64(upper - index)
            else { return nil }
            index += Int(length)
            running = nil
            continue
        }
        if byte == 0xF0 || byte == 0xF7 {
            index += 1
            guard let length = readSMFVLQ(bytes, index: &index, limit: upper),
                length <= UInt64(upper - index)
            else { return nil }
            index += Int(length)
            running = nil
            continue
        }
        let status: UInt8
        if byte & 0x80 != 0 {
            status = byte
            index += 1
        } else if let active = running {
            status = active
        } else {
            return nil
        }
        let kind = status >> 4
        if kind == 0xC || kind == 0xD {
            guard index < upper else { return nil }
            index += 1
            running = status
        } else if kind >= 0x8 && kind <= 0xE {
            guard index + 1 < upper else { return nil }
            let data0 = bytes[index]
            let data1 = bytes[index + 1]
            let velocityOffset = index + 1
            index += 2
            running = status
            if kind == 0x9, data1 != 0 {
                return RawSMFNoteOn(
                    tick: tick, channel: status & 0x0F,
                    pitch: data0, velocity: data1,
                    velocityOffset: velocityOffset)
            }
        } else {
            return nil
        }
    }
    return nil
}

private func firstRawNoteOn(in bytes: [UInt8]) -> RawSMFNoteOn? {
    guard bytes.count >= 8, bytes[0] == 0x4D, bytes[1] == 0x54,
        bytes[2] == 0x68, bytes[3] == 0x64
    else { return nil }
    let headerLength =
        Int(bytes[4]) << 24 | Int(bytes[5]) << 16
        | Int(bytes[6]) << 8 | Int(bytes[7])
    guard headerLength >= 0 else { return nil }
    var cursor = 8 + headerLength
    while cursor + 8 <= bytes.count {
        let length =
            Int(bytes[cursor + 4]) << 24 | Int(bytes[cursor + 5]) << 16
            | Int(bytes[cursor + 6]) << 8 | Int(bytes[cursor + 7])
        guard length >= 0, cursor + 8 + length <= bytes.count else { return nil }
        let isTrack =
            bytes[cursor] == 0x4D && bytes[cursor + 1] == 0x54
            && bytes[cursor + 2] == 0x72 && bytes[cursor + 3] == 0x6B
        if isTrack,
            let found = firstRawNoteOnInTrack(
                bytes, lower: cursor + 8,
                upper: cursor + 8 + length)
        {
            return found
        }
        cursor += 8 + length
    }
    return nil
}

// Compare tempo events separately while preserving their ticks and precedence.
// All other events retain exact order; equality excludes generated note identities.
private func semanticEventDiff(expected: MidiFile, actual: MidiFile) -> String? {
    guard expected.division == actual.division else {
        return "division \(expected.division) vs \(actual.division)"
    }
    guard expected.chunks.count == actual.chunks.count else {
        return "track count \(expected.chunks.count) vs \(actual.chunks.count)"
    }
    for chunk in expected.chunks.indices {
        let want = expected.chunks[chunk]
        let got = actual.chunks[chunk]
        guard want.endTick == got.endTick else {
            return "track \(chunk) endTick \(want.endTick) vs \(got.endTick)"
        }
        let wantTempo = want.events.filter { event -> Bool in
            guard let type = event.metaType else { return false }
            return type == UInt8(0x51)
        }
        let gotTempo = got.events.filter { event -> Bool in
            guard let type = event.metaType else { return false }
            return type == UInt8(0x51)
        }
        guard wantTempo == gotTempo else {
            return
                "track \(chunk) tempo stream differs (\(wantTempo.count) vs \(gotTempo.count) events)"
        }
        let wantRest = want.events.filter { $0.metaType != 0x51 }
        let gotRest = got.events.filter { $0.metaType != 0x51 }
        guard wantRest.count == gotRest.count else {
            return "track \(chunk) non-tempo event count \(wantRest.count) vs \(gotRest.count)"
        }
        for offset in wantRest.indices where wantRest[offset] != gotRest[offset] {
            return "track \(chunk) non-tempo event \(offset) differs"
        }
    }
    return nil
}

@MainActor
private func vanillaVelocityOracleEdges(_ report: CheckReport, cppID id: String) {
    let firstControl = MidiEvent.channel(tick: 0, status: 0xB0, data0: 7, data1: 32)
    let secondControl = MidiEvent.channel(tick: 0, status: 0xB0, data0: 7, data1: 96)
    let ordered = MidiFile(
        division: 24, chunks: [MidiChunk(events: [firstControl, secondControl], endTick: 48)])
    let swapped = MidiFile(
        division: 24, chunks: [MidiChunk(events: [secondControl, firstControl], endTick: 48)])
    report.expect(
        semanticEventDiff(expected: ordered, actual: swapped) != nil, cppID: id,
        message: "oracle rejects swapped channel-event order")
    let slow = MidiEvent.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])
    let fast = MidiEvent.meta(tick: 0, type: 0x51, data: [0x06, 0xEF, 0x91])
    let tempoOrder = MidiFile(
        division: 24, chunks: [MidiChunk(events: [slow, fast], endTick: 0)])
    let tempoSwapped = MidiFile(
        division: 24, chunks: [MidiChunk(events: [fast, slow], endTick: 0)])
    report.expect(
        semanticEventDiff(expected: tempoOrder, actual: tempoSwapped) != nil,
        cppID: id,
        message: "oracle rejects swapped duplicate-tempo order")
    let name = MidiEvent.meta(tick: 0, type: 0x03, data: Array("lead".utf8))
    let nameFirst = MidiFile(
        division: 24, chunks: [MidiChunk(events: [name, slow], endTick: 0)])
    let tempoFirst = MidiFile(
        division: 24, chunks: [MidiChunk(events: [slow, name], endTick: 0)])
    report.expect(
        semanticEventDiff(expected: nameFirst, actual: tempoFirst) == nil,
        cppID: id,
        message: "oracle accepts same-tick tempo/name reorder")
}

@MainActor
internal func vanillaVelocitySavePreservesOtherEvents(_ report: CheckReport, fixtureRoot: String) {
    let id = "savecheck/ProjectSaveTest::vanillaVelocitySavePreservesOtherEvents"
    vanillaVelocityOracleEdges(report, cppID: id)
    let songLabel = "mus_route101"
    let sourceRoot = URL(fileURLWithPath: fixtureRoot, isDirectory: true)
    let privateRoot = sourceRoot.deletingLastPathComponent().appendingPathComponent(
        "\(sourceRoot.lastPathComponent)-vanilla-delta-\(UUID().uuidString)",
        isDirectory: true)
    let fileManager = FileManager.default
    do {
        try fileManager.copyItem(at: sourceRoot, to: privateRoot)
    } catch {
        report.fail(id, "private vanilla delta fixture copy failed: \(error)")
        return
    }
    defer { try? fileManager.removeItem(at: privateRoot) }
    let midiDir = privateRoot.appendingPathComponent("sound/songs/midi")
    let cfgURL = midiDir.appendingPathComponent("midi.cfg")
    let midiURL = midiDir.appendingPathComponent("\(songLabel).mid")

    let originalMidi: Data
    let cfgBefore: Data
    do {
        originalMidi = try Data(contentsOf: midiURL)
        cfgBefore = try Data(contentsOf: cfgURL)
    } catch {
        report.fail(id, "vanilla delta fixture source read failed: \(error)")
        return
    }
    let originalBytes = [UInt8](originalMidi)
    guard let target = firstRawNoteOn(in: originalBytes) else {
        report.fail(id, "raw SMF scan found no note-on in the \(originalMidi.count)-byte vanilla MIDI")
        return
    }
    guard target.velocityOffset < originalBytes.count,
        originalBytes[target.velocityOffset] == target.velocity,
        target.velocity != 0
    else {
        report.fail(id, "raw SMF scan target is inconsistent at offset \(target.velocityOffset)")
        return
    }
    // A legal distinct nonzero velocity keeps the single-byte encoding width.
    let editedVelocity: UInt8 = target.velocity == 100 ? 64 : 100
    guard target.tick <= UInt64(UInt32.max) else {
        report.fail(id, "raw SMF scan tick \(target.tick) exceeds the document tick range")
        return
    }
    let noteTick = Tick(target.tick)

    let service = ProjectService()
    do {
        try runBlocking { try await service.open(root: privateRoot.path) }
        let session = try runBlocking {
            try await DocumentSession.open(service: service, label: songLabel, sampleRate: 48_000)
        }
        defer {
            do {
                let closed = try runBlocking { await session.close() }
                report.expect(
                    closed, cppID: id,
                    message: "vanilla delta session closes after the save journey")
                try runBlocking { await service.close() }
            } catch {
                report.fail(id, "closing vanilla delta session failed: \(error)")
            }
        }
        let document = session.document
        let noteCountBefore = (0..<document.engineTracks.usedTrackCount).reduce(0) {
            $0 + document.notes(in: $1).count
        }
        var matched: Note?
        for track in 0..<document.engineTracks.usedTrackCount {
            if let note = document.notes(in: track).first(where: {
                $0.tick == noteTick && $0.pitch == target.pitch
                    && $0.velocity == target.velocity && $0.channel == target.channel
            }) {
                matched = note
                break
            }
        }
        guard let edited = matched else {
            report.fail(
                id,
                "opened vanilla song has no note matching tick \(target.tick) pitch \(target.pitch) velocity \(target.velocity) channel \(target.channel)"
            )
            return
        }
        guard
            document.setVelocities(
                [NoteVelocity(noteID: edited.id, velocity: Int(editedVelocity))],
                expectedRevision: document.revision) != nil
        else {
            report.fail(
                id, "velocity edit to \(editedVelocity) for tick \(target.tick) pitch \(target.pitch) was rejected")
            return
        }
        report.expect(
            document.note(edited.id)?.velocity == editedVelocity, cppID: id,
            message: "velocity edit to \(editedVelocity) lands in memory before save")
        try runBlocking { try await session.save() }
        let savedMidi = try Data(contentsOf: midiURL)
        var patchedBytes = originalBytes
        patchedBytes[target.velocityOffset] = editedVelocity
        let expectedFile: MidiFile
        let savedFile: MidiFile
        do {
            expectedFile = try MidiFile.decode(patchedBytes)
            savedFile = try MidiFile.decode([UInt8](savedMidi))
        } catch {
            report.fail(id, "semantic oracle decode failed: \(error)")
            return
        }
        let diff = semanticEventDiff(expected: expectedFile, actual: savedFile)
        if let diff {
            report.fail(
                id,
                "semantic MIDI delta: \(diff) (saved \(savedMidi.count) bytes from \(originalMidi.count)-byte original, velocity offset \(target.velocityOffset) \(target.velocity)->\(editedVelocity))"
            )
        }
        report.expect(
            diff == nil, cppID: id,
            message:
                "saved vanilla MIDI preserves every event except velocity offset \(target.velocityOffset) (\(target.velocity)->\(editedVelocity))"
        )
        let cfgAfter = try Data(contentsOf: cfgURL)
        if cfgAfter != cfgBefore {
            report.fail(
                id,
                "midi.cfg changed under a velocity-only save (\(cfgBefore.count) bytes before, \(cfgAfter.count) bytes after)"
            )
        }
        report.expect(
            cfgAfter == cfgBefore, cppID: id,
            message: "velocity-only save leaves all \(cfgBefore.count) midi.cfg bytes untouched")

        let reopened = try runBlocking {
            try await DocumentSession.open(service: service, label: songLabel, sampleRate: 48_000)
        }
        defer {
            do {
                let closed = try runBlocking { await reopened.close() }
                report.expect(
                    closed, cppID: id,
                    message: "reopened vanilla song closes after observing persisted bytes")
            } catch {
                report.fail(id, "closing reopened vanilla song failed: \(error)")
            }
        }
        let reopenedNotes = (0..<reopened.document.engineTracks.usedTrackCount).flatMap {
            reopened.document.notes(in: $0)
        }
        report.expect(
            reopenedNotes.contains {
                $0.tick == noteTick && $0.pitch == target.pitch && $0.velocity == editedVelocity
            }, cppID: id,
            message:
                "reopened vanilla song retains edited velocity \(editedVelocity) at tick \(target.tick) pitch \(target.pitch)"
        )
        report.expect(
            reopenedNotes.count == noteCountBefore, cppID: id,
            message: "reopened vanilla song keeps the original \(noteCountBefore)-note count")
    } catch {
        report.fail(id, "vanilla velocity save journey failed: \(error)")
        do {
            try runBlocking { await service.close() }
        } catch {
            report.fail(id, "closing failed vanilla delta service failed: \(error)")
        }
        return
    }
}
