import Foundation
import PorydawCore

@MainActor
private enum NoteOracleChecks {
    private static let checkID = "editcheck/NoteOracleChecks"
    private static let seed: UInt64 = 0x4E6F_7465_4F72_6163

    private struct Row: Equatable {
        let id: NoteID
        let tick: Tick
        let duration: Tick
        let pitch: UInt8
        let velocity: UInt8
        let isUnterminated: Bool
    }

    private struct SplitMix64 {
        var state: UInt64

        mutating func next(_ upperBound: Int) -> Int {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            value ^= value >> 31
            return Int(value % UInt64(upperBound))
        }
    }

    private struct Snapshot {
        let bytes: [UInt8]
        let tracks: [[Row]]
    }

    // Deliberately quadratic: each on searches forward independently, allowing shared ends.
    private static func expectedNotes(file: MidiFile, track: EngineTrack) -> [Row] {
        guard let chunk = track.midiChunk else { return [] }
        let events = file.chunks[chunk].events
        var rows: [Row] = []
        for (index, on) in events.enumerated() {
            guard case .channel(let status, let pitch, let velocity) = on.payload,
                status == (0x90 | track.channel), velocity > 0
            else { continue }
            var endTick: Tick?
            for following in events[(index + 1)...] {
                guard case .channel(let endStatus, let endPitch, let endVelocity) = following.payload,
                    endPitch == pitch
                else { continue }
                let explicitEnd = endStatus == (0x80 | track.channel)
                let zeroVelocityEnd = endStatus == (0x90 | track.channel) && endVelocity == 0
                if explicitEnd || zeroVelocityEnd {
                    endTick = following.tick
                    break
                }
            }
            rows.append(
                Row(
                    id: on.noteID ?? NoteID(), tick: on.tick,
                    duration: endTick.map { (tick: Tick) in tick - on.tick } ?? 0,
                    pitch: pitch, velocity: velocity, isUnterminated: endTick == nil))
        }
        return rows
    }

    private static func actualNotes(_ document: SongDocument, track: Int) -> [Row] {
        document.notes(in: track).map { (note: Note) in
            Row(
                id: note.id, tick: note.tick, duration: note.duration,
                pitch: note.pitch, velocity: note.velocity, isUnterminated: note.isUnterminated)
        }
    }

    private static func expectEquivalent(_ document: SongDocument, _ report: CheckReport, _ context: String) {
        var identities: [NoteID] = []
        for track in 0..<document.engineTracks.usedTrackCount {
            let expected = expectedNotes(file: document.state.file, track: document.engineTracks.tracks[track])
            let actual = actualNotes(document, track: track)
            report.expectEqual(
                expected: expected, actual: actual, cppID: checkID,
                what: "\(context) track \(track): forward oracle equals ordered document notes")
            identities.append(contentsOf: actual.map(\.id))
        }
        report.expect(
            identities.allSatisfy { $0.isAssigned } && Set(identities).count == identities.count,
            cppID: checkID, message: "\(context): every note has a unique assigned ID")
    }

    private static func snapshot(_ document: SongDocument) throws -> Snapshot {
        Snapshot(
            bytes: try document.state.file.encoded(),
            tracks: (0..<document.engineTracks.usedTrackCount).map { (track: Int) in
                actualNotes(document, track: track)
            })
    }

    private static func expectSnapshot(
        _ document: SongDocument, _ expected: Snapshot, _ report: CheckReport, _ context: String
    ) throws {
        let actual = try snapshot(document)
        report.expectEqual(
            expected: expected.bytes, actual: actual.bytes, cppID: checkID,
            what: "\(context): exact forward MIDI bytes")
        report.expectEqual(
            expected: expected.tracks, actual: actual.tracks, cppID: checkID,
            what: "\(context): exact ordered note values and identities")
        expectEquivalent(document, report, context)
    }

    private static func handcrafted(_ report: CheckReport) {
        let document = SongDocument(
            file: baseFile(events: [
                .channel(tick: 4, status: 0x90, data0: 60, data1: 70),
                .channel(tick: 6, status: 0x90, data0: 60, data1: 80),
                .channel(tick: 7, status: 0x91, data0: 60, data1: 99),
                .channel(tick: 8, status: 0x81, data0: 60),
                .channel(tick: 12, status: 0x80, data0: 60, data1: 47),
                .channel(tick: 14, status: 0x90, data0: 62, data1: 90),
                .channel(tick: 14, status: 0x90, data0: 62, data1: 0),
                .channel(tick: 16, status: 0x90, data0: 61, data1: 100),
            ]))
        expectEquivalent(document, report, "handcrafted shared ends, overlap, channels and unterminated")
        let notes = document.notes(in: 0)
        report.expectEqual(
            expected: [Tick(8), 6, 0, 0], actual: notes.map(\.duration), cppID: checkID,
            what: "handcrafted golden durations include shared ends and same-tick end")
        report.expectEqual(
            expected: [false, false, false, true], actual: notes.map(\.isUnterminated), cppID: checkID,
            what: "handcrafted zero duration distinguishes terminated from unterminated")
        let rawEvents: [MidiEvent] = document.state.file.chunks.flatMap(\.events)
        let offChannelOns = rawEvents.filter { (event: MidiEvent) in
            guard case .channel(let status, _, let velocity) = event.payload else { return false }
            return status == 0x91 && velocity > 0
        }
        report.expectEqual(
            expected: 1, actual: offChannelOns.count, cppID: checkID,
            what: "off-channel on remains stored but is excluded from four projected notes")
        report.expectEqual(
            expected: [UInt8(70), 80, 90, 100], actual: notes.map(\.velocity), cppID: checkID,
            what: "handcrafted golden event order and velocities")
    }

    private static func corpus(_ report: CheckReport) throws {
        let songs = try coreEditCorpusSongs(report)
        report.expect(!songs.isEmpty, cppID: checkID, message: "oracle corpus is nonempty")
        for song in songs {
            let document = SongDocument(
                file: try MidiFile.decode(song.midiBytes), config: song.config, source: song.source)
            expectEquivalent(document, report, "corpus \(song.label)")
        }
        for fixture in ["note_lifecycle", "vlq_running_status", "opaque_sysex"] {
            guard let path = CheckEnvironment.fixturePath("test_midis/smf/valid/\(fixture).mid") else {
                report.fail(checkID, "missing staged fixture root for \(fixture)")
                continue
            }
            let file = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: path))))
            expectEquivalent(SongDocument(file: file), report, "fixture \(fixture)")
        }
    }

    private static func randomFile(_ random: inout SplitMix64) -> MidiFile {
        var chunks = [MidiChunk(endTick: 240)]
        for channel in [UInt8(0), 3] {
            var events: [MidiEvent] = []
            for group in 0..<8 {
                let tick = Tick(group * 24)
                let pitch = UInt8(48 + random.next(16))
                events.append(
                    .channel(tick: tick, status: 0x90 | channel, data0: pitch, data1: UInt8(1 + random.next(127))))
                events.append(
                    .channel(tick: tick + 2, status: 0x90 | channel, data0: pitch, data1: UInt8(1 + random.next(127))))
                events.append(
                    .channel(
                        tick: tick + 4, status: 0x90 | channel, data0: pitch + 1, data1: UInt8(1 + random.next(127))))
                events.append(.channel(tick: tick + 10, status: 0x90 | channel, data0: pitch + 1, data1: 0))
                events.append(
                    .channel(tick: tick + 12, status: 0x80 | channel, data0: pitch, data1: UInt8(random.next(128))))
            }
            events.append(.channel(tick: 200, status: 0x90 | channel, data0: 90, data1: 80))
            events.append(.channel(tick: 201, status: 0x90 | (channel ^ 1), data0: 90, data1: 70))
            chunks.append(MidiChunk(events: events, endTick: 240))
        }
        return MidiFile(division: 24, chunks: chunks)
    }

    private static func seededHistory(_ report: CheckReport) throws {
        var random = SplitMix64(state: seed)
        let document = SongDocument(file: randomFile(&random))
        expectEquivalent(document, report, "seed \(seed) initial")
        var snapshots = [try snapshot(document)]
        var changedOperations = [Int](repeating: 0, count: 4)
        for step in 0..<80 {
            let operation = random.next(4)
            let track = random.next(document.engineTracks.usedTrackCount)
            let notes = document.notes(in: track)
            let before = document.history.currentIdentity
            switch operation {
            case 0:
                _ = try document.addNotes([
                    NewNote(
                        track: track, tick: Tick(random.next(300)), pitch: UInt8(48 + random.next(36)),
                        duration: Tick(1 + random.next(24)), velocity: UInt8(1 + random.next(127)))
                ])
            case 1:
                if !notes.isEmpty {
                    let note = notes[random.next(notes.count)]
                    let ticks = Int64(random.next(25)) - 12
                    document.moveNotes([note.id], byTicks: ticks == 0 ? 1 : ticks, byKeys: random.next(7) - 3)
                }
            case 2:
                if !notes.isEmpty {
                    let note = notes[random.next(notes.count)]
                    let ticks = Int64(random.next(19)) - 6
                    document.resizeNotes([note.id], edge: .trailing, byTicks: ticks == 0 ? 1 : ticks)
                }
            default:
                if !notes.isEmpty {
                    document.deleteNotes([notes[random.next(notes.count)].id])
                }
            }
            expectEquivalent(document, report, "seed \(seed) forward step \(step) operation \(operation)")
            if document.history.currentIdentity != before {
                snapshots.append(try snapshot(document))
                changedOperations[operation] += 1
            }
        }
        report.expect(
            changedOperations.allSatisfy { $0 > 0 }, cppID: checkID,
            message: "seeded run records real add, move, resize and delete edits: \(changedOperations)")
        for index in stride(from: snapshots.count - 2, through: 0, by: -1) {
            report.expect(document.history.canUndo, cppID: checkID, message: "undo \(index): history entry exists")
            document.history.undoDocument()
            try expectSnapshot(document, snapshots[index], report, "undo \(index)")
        }
        report.expect(!document.history.canUndo, cppID: checkID, message: "all seeded edits undone to history origin")
        for index in 1..<snapshots.count {
            report.expect(document.history.canRedo, cppID: checkID, message: "redo \(index): history entry exists")
            document.history.redoDocument()
            try expectSnapshot(document, snapshots[index], report, "redo \(index)")
        }
        report.expect(!document.history.canRedo, cppID: checkID, message: "all seeded edits redone to history tip")
        let originalIDs = Set(snapshots[0].tracks.flatMap { $0.map(\.id) })
        let finalIDs = Set(snapshots[snapshots.count - 1].tracks.flatMap { $0.map(\.id) })
        let survivors = originalIDs.intersection(finalIDs)
        report.expect(!survivors.isEmpty, cppID: checkID, message: "seeded edits retain original surviving notes")
        report.expect(
            survivors.allSatisfy { document.note($0)?.id == $0 }, cppID: checkID,
            message: "original surviving NoteIDs remain identical after the complete undo-redo cycle")
    }

    private static func slotResurrection(_ report: CheckReport) throws {
        let document = SongDocument(
            file: baseFile(events: [
                .channel(tick: 4, status: 0x90, data0: 60, data1: 70),
                .channel(tick: 12, status: 0x80, data0: 60),
                .channel(tick: 24, status: 0x90, data0: 62, data1: 80),
                .channel(tick: 32, status: 0x80, data0: 62),
            ]))
        let notes = document.notes(in: 0)
        guard notes.count == 2,
            let originalLocation = document.location(of: notes[0].id),
            let survivingLocation = document.location(of: notes[1].id)
        else {
            report.fail(checkID, "slot resurrection fixture requires two notes in one track")
            return
        }
        let deletedID = notes[0].id
        let survivingID = notes[1].id
        let initial = try snapshot(document)
        report.expect(
            originalLocation.chunk == survivingLocation.chunk
                && document.note(deletedID)?.id == deletedID
                && document.note(survivingID)?.id == survivingID,
            cppID: checkID, message: "slot resurrection: both original handles resolve in the same chunk")
        expectEquivalent(document, report, "slot resurrection initial")

        document.deleteNotes([deletedID])
        report.expect(
            document.note(deletedID) == nil && document.note(survivingID)?.id == survivingID,
            cppID: checkID, message: "slot resurrection delete: only the deleted handle stops resolving")
        let afterDelete = try snapshot(document)
        expectEquivalent(document, report, "slot resurrection after delete")

        let insertedIDs = try document.addNotes([
            NewNote(track: 0, tick: 48, pitch: 64, duration: 8, velocity: 90)
        ])
        guard insertedIDs.count == 1, let insertedID = insertedIDs.first else {
            report.fail(checkID, "slot resurrection add requires one inserted note")
            return
        }
        report.expect(
            insertedID != deletedID && insertedID != survivingID
                && document.location(of: insertedID)?.chunk == originalLocation.chunk
                && document.note(insertedID)?.tick == 48 && document.note(insertedID)?.pitch == 64
                && document.note(survivingID)?.id == survivingID && document.note(deletedID) == nil,
            cppID: checkID,
            message: "slot resurrection add: a distinct new handle and the survivor resolve without aliasing")
        let afterAdd = try snapshot(document)
        expectEquivalent(document, report, "slot resurrection after add")

        report.expect(document.history.undoDocument(), cppID: checkID, message: "slot resurrection: undo add succeeds")
        report.expect(
            document.note(insertedID) == nil && document.note(deletedID) == nil,
            cppID: checkID, message: "slot resurrection undo add: neither removed handle resolves")
        try expectSnapshot(document, afterDelete, report, "slot resurrection undo add")

        report.expect(
            document.history.undoDocument(), cppID: checkID, message: "slot resurrection: undo delete succeeds")
        report.expect(
            document.note(deletedID)?.id == deletedID && document.note(insertedID) == nil,
            cppID: checkID,
            message: "slot resurrection undo delete: the original exact handle returns without the new note")
        try expectSnapshot(document, initial, report, "slot resurrection undo delete")

        report.expect(
            document.history.redoDocument(), cppID: checkID, message: "slot resurrection: redo delete succeeds")
        report.expect(
            document.note(deletedID) == nil && document.note(insertedID) == nil,
            cppID: checkID, message: "slot resurrection redo delete: neither removed handle resolves")
        try expectSnapshot(document, afterDelete, report, "slot resurrection redo delete")

        report.expect(document.history.redoDocument(), cppID: checkID, message: "slot resurrection: redo add succeeds")
        report.expect(
            document.note(insertedID)?.id == insertedID && document.note(deletedID) == nil,
            cppID: checkID,
            message: "slot resurrection redo add: the new exact handle returns and the original stays absent")
        try expectSnapshot(document, afterAdd, report, "slot resurrection redo add")
    }

    private static func duplicateTrackKeyIsolation(_ report: CheckReport) throws {
        let document = SongDocument(
            file: baseFile(events: [
                .channel(tick: 4, status: 0x90, data0: 60, data1: 70),
                .channel(tick: 12, status: 0x80, data0: 60),
                .channel(tick: 24, status: 0x90, data0: 62, data1: 80),
                .channel(tick: 32, status: 0x80, data0: 62),
            ]))
        let originalNotes = document.notes(in: 0)
        guard originalNotes.count == 2 else {
            report.fail(checkID, "duplicate-track key isolation fixture requires two original notes")
            return
        }
        let originalIDs = Set(originalNotes.map(\.id))
        let initial = try snapshot(document)
        expectEquivalent(document, report, "duplicate-track key isolation initial")
        guard let duplicatedTrack = document.duplicateTrack(0) else {
            report.fail(checkID, "duplicate-track key isolation requires successful track duplication")
            return
        }
        let duplicatedNotes = document.notes(in: duplicatedTrack)
        let duplicatedIDs = Set(duplicatedNotes.map(\.id))
        report.expect(
            duplicatedNotes.count == originalNotes.count && originalIDs.isDisjoint(with: duplicatedIDs),
            cppID: checkID,
            message: "duplicate-track key isolation: every copied note has an identity distinct from the originals")
        report.expect(
            originalNotes.allSatisfy { document.note($0.id) == $0 }
                && duplicatedNotes.allSatisfy { document.note($0.id) == $0 },
            cppID: checkID,
            message: "duplicate-track key isolation: both original and duplicate handles resolve to their own notes")
        let afterDuplicate = try snapshot(document)
        expectEquivalent(document, report, "duplicate-track key isolation after duplicate")

        report.expect(
            document.history.undoDocument(), cppID: checkID, message: "duplicate-track key isolation: undo succeeds")
        report.expect(
            duplicatedIDs.allSatisfy { document.note($0) == nil }
                && originalNotes.allSatisfy { document.note($0.id) == $0 },
            cppID: checkID,
            message: "duplicate-track key isolation undo: copied handles disappear while originals still resolve")
        try expectSnapshot(document, initial, report, "duplicate-track key isolation undo")

        report.expect(
            document.history.redoDocument(), cppID: checkID, message: "duplicate-track key isolation: redo succeeds")
        report.expect(
            document.notes(in: duplicatedTrack).map(\.id) == duplicatedNotes.map(\.id)
                && duplicatedNotes.allSatisfy { document.note($0.id) == $0 }
                && originalNotes.allSatisfy { document.note($0.id) == $0 },
            cppID: checkID,
            message: "duplicate-track key isolation redo: copied handles return unchanged and both sets resolve")
        try expectSnapshot(document, afterDuplicate, report, "duplicate-track key isolation redo")
    }

    static func run(_ report: CheckReport) {
        handcrafted(report)
        do {
            try corpus(report)
            try seededHistory(report)
            try slotResurrection(report)
            try duplicateTrackKeyIsolation(report)
        } catch {
            report.fail(checkID, "oracle fixture, edit or encoding failed: \(error)")
        }
    }
}

@MainActor
public func runNoteOracleSuite(_ report: CheckReport) {
    NoteOracleChecks.run(report)
}
