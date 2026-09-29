import Foundation
import PorydawApp
import PorydawCore
import PorydawProject

private struct ImportFixture {
    let root: String
    func path(_ name: String) -> String { root + "/" + name }
    func read(_ name: String) throws -> Data { try ProjectFileStore.read(path(name)) }
    func write(_ name: String, _ bytes: Data) throws { try ProjectFileStore.write(path(name), data: bytes) }
    func exists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: path(name)) }
}

private func importFixture(_ root: String, _ name: String) -> ImportFixture {
    ImportFixture(root: stageTestProject(in: root, projectName: "swiftcore-import-" + name))
}

private func importRequest(_ label: String, createVoicegroup: Bool = false) -> SongImportRequest {
    SongImportRequest(
        label: label, constant: label.uppercased(), player: "MUSIC_PLAYER_BGM",
        config: SongConfig(
            rawFlags: [],
            voicegroupArgument: createVoicegroup ? "_" + label : "_test_vg",
            masterVolume: 100, reverb: 50, exactGate: true),
        createVoicegroup: createVoicegroup, midi: makeMidiFixture(division: 96))
}

@MainActor
private func importFailure(_ service: ProjectService, _ request: SongImportRequest) -> String {
    do {
        _ = try runBlocking { try await service.importSong(request) }
        return "<succeeded>"
    } catch ProjectServiceError.operationFailed(let message) {
        return message
    } catch {
        return "<unexpected error: \(error)>"
    }
}

private let importCfg = "sound/songs/midi/midi.cfg"
private let importHub = "sound/voice_groups.inc"
private let importTable = "sound/song_table.inc"
private let importHeader = "include/constants/songs.h"

@MainActor
private func importWithBlockedHeader(
    _ service: ProjectService, _ request: SongImportRequest,
    fixture: ImportFixture
) throws -> String {
    let path = fixture.path(importHeader)
    let original = try fixture.read(importHeader)
    try FileManager.default.removeItem(atPath: path)
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    let failure = importFailure(service, request)
    try FileManager.default.removeItem(atPath: path)
    try fixture.write(importHeader, original)
    return failure
}

@MainActor
internal func runSongImportChecks(_ report: CheckReport, fixtureRoot: String) {
    let successID = "swiftcore/SongImport::existingVoicegroup"
    do {
        let fixture = importFixture(fixtureRoot, "existing")
        let request = importRequest("mus_import_existing")
        let planned = SongRegistration.plan(
            root: fixture.root, label: request.label,
            constant: request.constant, player: request.player)
        let service = ProjectService()
        defer { try? runBlocking { await service.close() } }
        try runBlocking { try await service.open(root: fixture.root) }
        let id = try runBlocking { try await service.importSong(request) }
        report.expectEqual(
            expected: planned.songId, actual: id, cppID: successID,
            what: "import returns the pre-import registration ID")
        let midi = try MidiFile.decode(Array(fixture.read("sound/songs/midi/\(request.label).mid")))
        report.expectEqual(
            expected: request.midi.division, actual: midi.division, cppID: successID,
            what: "imported MIDI preserves division")
        report.expectEqual(
            expected: request.midi.chunks.count, actual: midi.chunks.count, cppID: successID,
            what: "imported MIDI preserves chunk count")
        let cfg = String(decoding: try fixture.read(importCfg), as: UTF8.self)
        report.expect(
            cfg.components(separatedBy: .newlines).contains(
                "\(request.label).mid: -E -R50 -G_test_vg -V100"), cppID: successID,
            message: "imported config merges all chosen flags")
        let song = try runBlocking { try await service.songs() }.first { $0.label == request.label }
        report.expectEqual(
            expected: true, actual: song?.registered, cppID: successID,
            what: "imported song is registered")
        report.expectEqual(
            expected: [String](), actual: song?.registrationGaps, cppID: successID,
            what: "imported song has no registration gaps")
    } catch { report.fail(successID, "import scenario failed: \(error)") }

    let newID = "swiftcore/SongImport::newVoicegroup"
    do {
        let fixture = importFixture(fixtureRoot, "voicegroup")
        let request = importRequest("mus_import_bank", createVoicegroup: true)
        let service = ProjectService()
        defer { try? runBlocking { await service.close() } }
        try runBlocking { try await service.open(root: fixture.root) }
        _ = try runBlocking { try await service.importSong(request) }
        let bank = "sound/voicegroups/\(request.label).inc"
        report.expect(fixture.exists(bank), cppID: newID, message: "new voicegroup file exists")
        let header = String(decoding: try fixture.read(bank), as: UTF8.self)
        report.expect(
            header.contains("voicegroup_\(request.label)") || header.contains("voice_group \(request.label)"),
            cppID: newID,
            message: "new voicegroup declares its header")
        let hub = String(decoding: try fixture.read(importHub), as: UTF8.self)
        report.expect(
            hub.contains("sound/voicegroups/\(request.label).inc"), cppID: newID,
            message: "new voicegroup appears in hub include")
        let args = try runBlocking { try await service.voicegroupArgs() }
        report.expect(
            args.contains("_" + request.label), cppID: newID,
            message: "reopened project exposes new voicegroup argument")
        let cfg = String(decoding: try fixture.read(importCfg), as: UTF8.self)
        report.expect(
            cfg.contains("-G_\(request.label)"), cppID: newID,
            message: "new song config refers to created voicegroup")
    } catch { report.fail(newID, "voicegroup scenario failed: \(error)") }

    for scenario in ["midi", "label", "voicegroup", "invalid"] {
        let id = "swiftcore/SongImport::refusal-\(scenario)"
        do {
            let fixture = importFixture(fixtureRoot, scenario)
            let label =
                scenario == "label"
                ? "mus_session_test"
                : scenario == "voicegroup"
                    ? "test_vg" : scenario == "invalid" ? "Invalid Label" : "mus_import_collision"
            let midiPath = "sound/songs/midi/\(label).mid"
            let foreign = Data("foreign MIDI that must survive".utf8)
            if scenario == "midi" { try fixture.write(midiPath, foreign) }
            if scenario == "label" {
                try FileManager.default.removeItem(atPath: fixture.path(midiPath))
            }
            let tracked = [importCfg, importHub, importTable, importHeader]
            let before = try tracked.map { try fixture.read($0) }
            let service = ProjectService()
            defer { try? runBlocking { await service.close() } }
            try runBlocking { try await service.open(root: fixture.root) }
            let message = importFailure(service, importRequest(label, createVoicegroup: true))
            let expected =
                scenario == "midi"
                ? "MIDI file already exists: \(fixture.path(midiPath))"
                : scenario == "label"
                    ? "A song named \(label) already exists."
                    : scenario == "invalid"
                        ? "Invalid song label: \(label)." : "A voicegroup named \(label) already exists."
            report.expectEqual(
                expected: expected, actual: message, cppID: id,
                what: "refusal reports the exact reason before a write")
            for (index, path) in tracked.enumerated() {
                report.expectEqual(
                    expected: before[index], actual: try fixture.read(path), cppID: id,
                    what: "refusal preserves \(path) bytes")
            }
            if scenario == "midi" {
                report.expectEqual(
                    expected: foreign, actual: try fixture.read(midiPath), cppID: id,
                    what: "foreign MIDI survives exactly")
            } else if scenario != "label" {
                report.expectEqual(
                    expected: false, actual: fixture.exists(midiPath), cppID: id,
                    what: "refusal does not write MIDI")
            }
            if scenario == "midi" || scenario == "invalid" {
                report.expectEqual(
                    expected: false,
                    actual: fixture.exists("sound/voicegroups/\(label).inc"), cppID: id,
                    what: "refusal precedes voicegroup creation")
            }
        } catch { report.fail(id, "refusal scenario failed: \(error)") }
    }

    for scenario in ["registration", "flags"] {
        let id = "swiftcore/SongImport::partial-\(scenario)"
        do {
            let fixture = importFixture(fixtureRoot, scenario)
            if scenario == "registration" {
                // The shared session fixture's header IDs start at one while its
                // table starts at zero. Its last define would otherwise claim the
                // new table row's ID and hide the missing-header gap.
                let defines = rejectedVoicegroupCases.enumerated().map {
                    "#define \($0.element.label.uppercased()) \($0.offset + 2)"
                }.joined(separator: "\n")
                try fixture.write(
                    importHeader,
                    Data(("#define MUS_SESSION_TEST 0\n#define MUS_SESSION_TEST2 1\n" + defines + "\n").utf8))
            }
            let request = importRequest("mus_import_\(scenario)")
            let service = ProjectService()
            defer { try? runBlocking { await service.close() } }
            try runBlocking { try await service.open(root: fixture.root) }
            let message: String
            if scenario == "registration" {
                message = try importWithBlockedHeader(service, request, fixture: fixture)
            } else {
                try FileManager.default.removeItem(atPath: fixture.path(importCfg))
                try FileManager.default.createDirectory(
                    atPath: fixture.path(importCfg),
                    withIntermediateDirectories: false)
                message = importFailure(service, request)
            }
            report.expect(
                message != "<succeeded>" && !message.hasPrefix("<unexpected"), cppID: id,
                message: "unwritable stage rejects the import")
            report.expect(
                fixture.exists("sound/songs/midi/\(request.label).mid"), cppID: id,
                message: "MIDI write survives later failure")
            if scenario == "registration" {
                let cfg = String(decoding: try fixture.read(importCfg), as: UTF8.self)
                report.expect(
                    cfg.contains("\(request.label).mid: -E -R50 -G_test_vg -V100"),
                    cppID: id, message: "flags persist before registration fails")
            } else {
                let attributes = try FileManager.default.attributesOfItem(atPath: fixture.path(importCfg))
                report.expectEqual(
                    expected: FileAttributeType.typeDirectory,
                    actual: attributes[.type] as? FileAttributeType,
                    cppID: id, what: "cfg destination remains a directory; no flags were written")
            }
            // A failed registration does not publish a snapshot; reopen to inspect
            // the durable partial files as the Register Song action does.
            try runBlocking { try await service.open(root: fixture.root) }
            let entry = try runBlocking { try await service.songs() }.first { $0.label == request.label }
            if scenario == "registration" {
                report.expectEqual(
                    expected: true, actual: entry?.registrationIncomplete, cppID: id,
                    what: "partial registration remains eligible for Register Song")
                report.expect(
                    entry?.registrationGaps.contains("songs.h") == true, cppID: id,
                    message: "partial registration exposes missing header")
            } else {
                report.expectEqual(
                    expected: false, actual: entry?.registered, cppID: id,
                    what: "flag failure leaves the MIDI unregistered")
            }
            if scenario == "registration" {
                let plan = try runBlocking { try await service.songRegistrationPlan(label: request.label) }
                let completed = try runBlocking { try await service.registerSong(plan) }
                report.expectEqual(
                    expected: plan.songId, actual: completed, cppID: id,
                    what: "Register Song resumes partial import at planned ID")
                let beforeRetry = try [importTable, importHeader].map { try fixture.read($0) }
                let repeated = try runBlocking { try await service.registerSong(plan) }
                report.expectEqual(
                    expected: completed, actual: repeated, cppID: id,
                    what: "repeat registration keeps the ID")
                report.expectEqual(
                    expected: beforeRetry,
                    actual: try [importTable, importHeader].map { try fixture.read($0) }, cppID: id,
                    what: "repeat registration preserves every present registration file")
            }
        } catch { report.fail(id, "partial import scenario failed: \(error)") }
    }

    let dataID = "swiftcore/SongImport::projectData"
    do {
        let service = ProjectService()
        defer { try? runBlocking { await service.close() } }
        try runBlocking { try await service.open(root: fixtureRoot) }
        let data = try runBlocking { try await service.importProjectData() }
        report.expectEqual(
            expected: "MUSIC_PLAYER_BGM", actual: data.players.first?.name,
            cppID: dataID, what: "first player follows table order")
        report.expectEqual(
            expected: 16, actual: data.players.first?.trackCount,
            cppID: dataID, what: "BGM has 16 tracks")
        report.expect(
            data.players.contains { $0.name == "MUSIC_PLAYER_SE_1TRK" && $0.trackCount == 1 },
            cppID: dataID, message: "single-track player is available")
        report.expectEqual(
            expected: true, actual: data.canCreateVoicegroup, cppID: dataID,
            what: "per-file voicegroup directory is available")
        report.expect(
            data.voicegroupArgs.contains("_fixture_rich"), cppID: dataID,
            message: "existing voicegroup argument is available")
    } catch { report.fail(dataID, "project-data scenario failed: \(error)") }
}
