import Foundation
import PorydawApp
import PorydawProject

private struct DeletionFixture {
    let root: String

    func path(_ relative: String) -> String { root + "/" + relative }
    func read(_ relative: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path(relative)))
    }
    func write(_ relative: String, _ text: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: path(relative)))
    }
    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: path(relative)) }
}

private let deletionFiles = [
    "sound/song_table.inc", "include/constants/songs.h", "ld_script.ld",
    "charmap.txt", "sound/songs/midi/midi.cfg", "src/debug.c", "songs.mk"
]
private let deletionBaselineImages = [
    Data("gSongTable::\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n\tsong mus_original, MUSIC_PLAYER_BGM, 0\n".utf8),
    Data("#define MUS_ZERO 0\n#define MUS_ORIGINAL 1\n#define MUS_NONE 0xFFFF\n".utf8),
    Data("SECTIONS {\n\tsound/songs/midi/mus_zero.o(.rodata);\n}\n".utf8),
    Data("MUS_ZERO = 00 00\nMUS_ORIGINAL = 01 00\n".utf8),
    Data("mus_zero.mid: -R50 -G_test_vg -V100\nmus_original.mid: -R50 -G_test_vg -V100\n".utf8),
    Data("#define SOUND_LIST_BGM \\\n    X(MUS_ZERO) \\\n    X(MUS_ORIGINAL)\n".utf8),
    Data("$(MID_SUBDIR)/mus_original.s: $(MID_SUBDIR)/mus_original.mid\n\t$(MID2AGB) $< -o $@\n".utf8)
]


private func deletionFixture(_ fixtureRoot: String, name: String) throws -> DeletionFixture {
    let fixture = DeletionFixture(root: stageTestProject(in: fixtureRoot, projectName: "deletion-" + name))
    try fixture.write("sound/song_table.inc", "gSongTable::\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n\tsong mus_original, MUSIC_PLAYER_BGM, 0\n")
    try fixture.write("include/constants/songs.h", "#define MUS_ZERO 0\n#define MUS_ORIGINAL 1\n#define MUS_NONE 0xFFFF\n")
    try fixture.write("ld_script.ld", "SECTIONS {\n\tsound/songs/midi/mus_zero.o(.rodata);\n}\n")
    try fixture.write("charmap.txt", "MUS_ZERO = 00 00\nMUS_ORIGINAL = 01 00\n")
    try fixture.write("sound/songs/midi/midi.cfg", "mus_zero.mid: -R50 -G_test_vg -V100\n" +
                      "mus_original.mid: -R50 -G_test_vg -V100\n")
    try FileManager.default.createDirectory(atPath: fixture.path("src"), withIntermediateDirectories: true)
    try fixture.write("src/debug.c", "#define SOUND_LIST_BGM \\\n    X(MUS_ZERO) \\\n    X(MUS_ORIGINAL)\n")
    try fixture.write("songs.mk", "$(MID_SUBDIR)/mus_original.s: $(MID_SUBDIR)/mus_original.mid\n\t$(MID2AGB) $< -o $@\n")
    let midi = try fixture.read("sound/songs/midi/mus_session_test.mid")
    try midi.write(to: URL(fileURLWithPath: fixture.path("sound/songs/midi/mus_zero.mid")))
    try midi.write(to: URL(fileURLWithPath: fixture.path("sound/songs/midi/mus_original.mid")))
    return fixture
}

private func deletionImages(_ fixture: DeletionFixture) throws -> [Data] {
    try deletionFiles.map { try fixture.read($0) }
}

private func seedDeletionSong(_ fixture: DeletionFixture, label: String) throws {
    let midi = try fixture.read("sound/songs/midi/mus_session_test.mid")
    try midi.write(to: URL(fileURLWithPath: fixture.path("sound/songs/midi/\(label).mid")))
    let cfg = try fixture.read("sound/songs/midi/midi.cfg")
    var bytes = cfg
    bytes.append(Data("\(label).mid: -R50 -G_test_vg -V100\n".utf8))
    try bytes.write(to: URL(fileURLWithPath: fixture.path("sound/songs/midi/midi.cfg")))
}

@MainActor
internal func runSongDeletionChecks(_ report: CheckReport, fixtureRoot: String) {
    runDeletionAllocationChecks(report, fixtureRoot: fixtureRoot)
    runDeletionServiceChecks(report, fixtureRoot: fixtureRoot)
    runDeletionBankChecks(report, fixtureRoot: fixtureRoot)
}

private func deletionOperationSucceeded<Value>(_ result: Result<Value, Error>) -> Bool {
    if case .success = result { return true }
    return false
}

@MainActor
private func runDeletionAllocationChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/SongDeletion::allocation"
    do {
        let fixture = try deletionFixture(fixtureRoot, name: "allocation")
        let original = deletionBaselineImages
        let probe = SongRegistration.plan(root: fixture.root, label: "mus_new_probe",
                                          constant: "MUS_NEW_PROBE", player: "MUSIC_PLAYER_BGM")
        report.expectEqual(expected: true, actual: probe.songId != 0, cppID: id,
                           what: "A006 fresh song planning never selects protected song ID zero")
        report.expectEqual(expected: 2, actual: probe.songId, cppID: id,
                           what: "A007 fresh song planning appends at the existing two-entry table count")
        let zeroPlan = SongRegistration.removalPlan(root: fixture.root, label: "mus_zero", constant: "MUS_ZERO")
        report.expectEqual(expected: 0, actual: zeroPlan.tableIndex, cppID: id,
                           what: "Fallback deletion plan identifies protected song ID zero")
        let fallbackRemoval = Result {
            try SongRegistration.unregister(root: fixture.root, label: "mus_zero", constant: "MUS_ZERO")
        }
        report.expectEqual(expected: false, actual: deletionOperationSucceeded(fallbackRemoval), cppID: id,
                           what: "A008 unregister refuses the protected fallback song")
        if case .failure(let error) = fallbackRemoval {
            report.expectEqual(expected: "mus_zero is the first song_table.inc entry (song ID 0), the engine's fallback song — it cannot be deleted.",
                               actual: error.localizedDescription, cppID: id,
                               what: "A009 fallback refusal retains the registration diagnostic")
        } else {
            report.fail(id, "Unregister unexpectedly accepted the protected fallback song.")
        }
        report.expectEqual(expected: original, actual: try deletionImages(fixture), cppID: id,
                           what: "A010 fallback refusal preserves all seven original project file images")
        try SongRegistration.unregister(root: fixture.root, label: "mus_absent", constant: "MUS_ABSENT")
        report.expectEqual(expected: original, actual: try deletionImages(fixture), cppID: id,
                           what: "A014 unregistering an absent song leaves all original project images unchanged")
        report.expectEqual(expected: Data("gSongTable::\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n\tsong mus_original, MUSIC_PLAYER_BGM, 0\n".utf8),
                           actual: try fixture.read("sound/song_table.inc"), cppID: id,
                           what: "A015 absent unregister preserves the complete original song table")
        try seedDeletionSong(fixture, label: "mus_stray")
        try SongRegistration.removeFlags(root: fixture.root, label: "mus_stray")
        report.expectEqual(expected: Data("mus_zero.mid: -R50 -G_test_vg -V100\nmus_original.mid: -R50 -G_test_vg -V100\n".utf8),
                           actual: try fixture.read("sound/songs/midi/midi.cfg"), cppID: id,
                           what: "A017 removing stray MIDI flags restores complete original cfg bytes")
        report.expectEqual(expected: false,
                           actual: String(decoding: try fixture.read("sound/songs/midi/midi.cfg"), as: UTF8.self)
                               .contains("mus_stray.mid"), cppID: id,
                           what: "A019 removing stray flags leaves no stray MIDI label in the cfg bytes")

        try seedDeletionSong(fixture, label: "mus_del_a")
        let firstId = try SongRegistration.register(root: fixture.root, label: "mus_del_a",
                                                    constant: "MUS_DEL_A", player: "MUSIC_PLAYER_BGM")
        report.expectEqual(expected: 2, actual: firstId, cppID: id,
                           what: "A020 registering A appends it after the two original songs")
        try seedDeletionSong(fixture, label: "mus_del_b")
        let secondId = try SongRegistration.register(root: fixture.root, label: "mus_del_b",
                                                     constant: "MUS_DEL_B", player: "MUSIC_PLAYER_BGM")
        report.expectEqual(expected: Data("gSongTable::\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n\tsong mus_original, MUSIC_PLAYER_BGM, 0\n\tsong mus_del_a, MUSIC_PLAYER_BGM, 0\n\tsong mus_del_b, MUSIC_PLAYER_BGM, 0\n".utf8),
                           actual: try fixture.read("sound/song_table.inc"), cppID: id,
                           what: "A023 registering B retains A and both original song table entries")
        report.expectEqual(expected: 3, actual: secondId, cppID: id,
                           what: "A024 registering B assigns the ID immediately after A")
        try SongRegistration.unregister(root: fixture.root, label: "mus_del_a", constant: "MUS_DEL_A")
        report.expectEqual(expected: Data("gSongTable::\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n\tsong mus_original, MUSIC_PLAYER_BGM, 0\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n\tsong mus_del_b, MUSIC_PLAYER_BGM, 0\n".utf8),
                           actual: try fixture.read("sound/song_table.inc"), cppID: id,
                           what: "A025 removing middle song A replaces only its table slot with fallback")
        try SongRegistration.removeFlags(root: fixture.root, label: "mus_del_a")
        report.expectEqual(expected: Data("mus_zero.mid: -R50 -G_test_vg -V100\nmus_original.mid: -R50 -G_test_vg -V100\nmus_del_b.mid: -R50 -G_test_vg -V100\n".utf8),
                           actual: try fixture.read("sound/songs/midi/midi.cfg"), cppID: id,
                           what: "A026 removing A flags preserves the original and surviving B cfg entries")
        report.expectEqual(expected: 2,
                           actual: String(decoding: try fixture.read("sound/song_table.inc"), as: UTF8.self)
                               .components(separatedBy: "\tsong mus_zero,").count - 1,
                           cppID: id, what: "A029 middle removal increases the fallback slot count from one to two")
        let deletedConstant = Data("MUS_DEL_A".utf8)
        let absentFromOtherImages = try deletionFiles.dropFirst().allSatisfy {
            try fixture.read($0).range(of: deletedConstant) == nil
        }
        report.expectEqual(expected: true, actual: absentFromOtherImages, cppID: id,
                           what: "A032 middle deletion removes A constant from every other project snapshot file")
        let survivingStatus = SongRegistration.status(root: fixture.root, label: "mus_del_b",
                                                      constant: "MUS_DEL_B")
        report.expectEqual(expected: [] as [String], actual: survivingStatus.missingFiles, cppID: id,
                           what: "A033 middle deletion leaves B registered in every applicable project file")
        let replacement = SongRegistration.plan(root: fixture.root, label: "mus_del_c",
                                                constant: "MUS_DEL_C", player: "MUSIC_PLAYER_BGM")
        report.expectEqual(expected: 2, actual: replacement.songId, cppID: id,
                           what: "A030 next registration reuses precisely the vacated middle ID")
        try seedDeletionSong(fixture, label: "mus_del_c")
        let registeredReplacement = Result {
            try SongRegistration.register(root: fixture.root, label: "mus_del_c",
                                          constant: "MUS_DEL_C", player: "MUSIC_PLAYER_BGM")
        }
        report.expectEqual(expected: true, actual: deletionOperationSucceeded(registeredReplacement), cppID: id,
                           what: "A040 replacement C registration completes without an operation error")
        let reused = try registeredReplacement.get()
        report.expectEqual(expected: 2, actual: reused, cppID: id,
                           what: "A041 registered replacement retains the freed ID")
        report.expectEqual(expected: Data("#define MUS_ZERO 0\n#define MUS_ORIGINAL 1\n#define MUS_DEL_C 2\n#define MUS_DEL_B 3\n#define MUS_NONE 0xFFFF\n".utf8),
                           actual: try fixture.read("include/constants/songs.h"), cppID: id,
                           what: "A043 reused header definition precedes the surviving B definition")
        report.expectEqual(expected: Data("MUS_ZERO = 00 00\nMUS_ORIGINAL = 01 00\nMUS_DEL_C = 02 00\nMUS_DEL_B = 03 00\n".utf8),
                           actual: try fixture.read("charmap.txt"), cppID: id,
                           what: "A045 reused charmap definition precedes the surviving B definition")
        let removedReplacement = Result {
            try SongRegistration.unregister(root: fixture.root, label: "mus_del_c", constant: "MUS_DEL_C")
        }
        report.expectEqual(expected: true, actual: deletionOperationSucceeded(removedReplacement), cppID: id,
                           what: "A046 replacement C unregister completes without an operation error")
        try removedReplacement.get()
        try SongRegistration.removeFlags(root: fixture.root, label: "mus_del_c")
        report.expectEqual(expected: Data("mus_zero.mid: -R50 -G_test_vg -V100\nmus_original.mid: -R50 -G_test_vg -V100\nmus_del_b.mid: -R50 -G_test_vg -V100\n".utf8),
                           actual: try fixture.read("sound/songs/midi/midi.cfg"), cppID: id,
                           what: "A047 removing replacement C flags preserves original and surviving B cfg bytes")
        let removedSurvivor = Result {
            try SongRegistration.unregister(root: fixture.root, label: "mus_del_b", constant: "MUS_DEL_B")
        }
        report.expectEqual(expected: true, actual: deletionOperationSucceeded(removedSurvivor), cppID: id,
                           what: "A049 surviving B unregister completes without an operation error")
        try removedSurvivor.get()
        try SongRegistration.removeFlags(root: fixture.root, label: "mus_del_b")
        report.expectEqual(expected: Data("mus_zero.mid: -R50 -G_test_vg -V100\nmus_original.mid: -R50 -G_test_vg -V100\n".utf8),
                           actual: try fixture.read("sound/songs/midi/midi.cfg"), cppID: id,
                           what: "A050 removing B flags restores the complete original cfg bytes")
        report.expectEqual(expected: original, actual: try deletionImages(fixture), cppID: id,
                           what: "A052 full A B C deletion cycle restores every original project byte")
        try SongRegistration.unregister(root: fixture.root, label: "mus_del_b", constant: "MUS_DEL_B")
        report.expectEqual(expected: 1,
                           actual: String(decoding: try fixture.read("sound/song_table.inc"), as: UTF8.self)
                               .components(separatedBy: "\tsong mus_zero,").count - 1,
                           cppID: id, what: "A035 repeated tail unregister keeps exactly one fallback song")
        report.expectEqual(expected: original, actual: try deletionImages(fixture), cppID: id,
                           what: "A036 repeated tail unregister preserves all original project images")
    } catch { report.fail(id, "deletion allocation scenario failed: \(error)") }
}

@MainActor
private func runDeletionServiceChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/SongDeletion::service"
    do {
        let fixture = try deletionFixture(fixtureRoot, name: "service")
        let original = deletionBaselineImages
        let service = ProjectService()
        defer { try? runBlocking { await service.close() } }
        try runBlocking { try await service.open(root: fixture.root) }
        do {
            try runBlocking { try await service.deleteSong(label: "mus_zero") }
            report.fail(id, "Service unexpectedly accepted deletion of the protected fallback song.")
        } catch ProjectServiceError.operationFailed(let message) {
            report.expectEqual(expected: "mus_zero is the engine's fallback song (song ID 0) and cannot be deleted.",
                               actual: message, cppID: id,
                               what: "Service retains its distinct literal fallback refusal diagnostic")
            report.expectEqual(expected: original, actual: try deletionImages(fixture), cppID: id,
                               what: "Service fallback refusal preserves every original project file image")
        }
        try seedDeletionSong(fixture, label: "mus_service_del")
        try runBlocking { try await service.open(root: fixture.root) }
        let plan = try runBlocking { try await service.songRegistrationPlan(label: "mus_service_del") }
        _ = try runBlocking { try await service.registerSong(plan) }
        // MIDI is opaque fixture input; capture its full bytes before the deletion stimulus.
        let midi = try fixture.read("sound/songs/midi/mus_service_del.mid")
        try fixture.write("sound/songs/midi/midi.cfg", "mus_zero.mid: -R50 -G_test_vg -V100\n" +
                          "mus_original.mid: -R50 -G_test_vg -V100\n" +
                          "mus_service_del.mid: -R50 -G_test_vg -V100\n")
        try fixture.write("songs.mk", "$(MID_SUBDIR)/mus_original.s: $(MID_SUBDIR)/mus_original.mid\n" +
                          "\t$(MID2AGB) $< -o $@\n\n" +
                          "$(MID_SUBDIR)/mus_service_del.s: $(MID_SUBDIR)/mus_service_del.mid\n" +
                          "\t$(MID2AGB) $< -o $@\n")
        try fixture.write("sound/songs/midi/mus_service_del.s", "generated assembly\n")
        let planned = try runBlocking { try await service.songDeletionPlan(label: "mus_service_del") }
        report.expectEqual(expected: 2, actual: planned.tableIndex, cppID: id,
                           what: "Service deletion planning retains the newly registered song ID")
        report.expectEqual(expected: Data("gSongTable::\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n\tsong mus_original, MUSIC_PLAYER_BGM, 0\n\tsong mus_service_del, MUSIC_PLAYER_BGM, 0\n".utf8),
                           actual: try fixture.read("sound/song_table.inc"), cppID: id,
                           what: "Service deletion planning preserves the complete staged song table bytes")
        try runBlocking { try await service.deleteSong(label: "mus_service_del") }
        report.expectEqual(expected: false, actual: fixture.exists("sound/songs/midi/mus_service_del.mid"), cppID: id,
                           what: "A027 service deletion removes the original MIDI path")
        report.expectEqual(expected: midi, actual: try fixture.read(".porydaw/trash/mus_service_del.mid"), cppID: id,
                           what: "Service trash destination contains the complete original MIDI fixture bytes")
        report.expectEqual(expected: false, actual: fixture.exists("sound/songs/midi/mus_service_del.s"), cppID: id,
                           what: "Service deletion removes the generated song assembly file")
        report.expectEqual(expected: original, actual: try deletionImages(fixture), cppID: id,
                           what: "Service deletion restores complete registration, cfg and makefile image bytes")
        let songs = try runBlocking { try await service.songs() }
        report.expectEqual(expected: false, actual: songs.contains { $0.label == "mus_service_del" }, cppID: id,
                           what: "Refreshed service songs exclude the deleted song label")
        try seedDeletionSong(fixture, label: "mus_service_del")
        try runBlocking { try await service.open(root: fixture.root) }
        let secondPlan = try runBlocking { try await service.songRegistrationPlan(label: "mus_service_del") }
        _ = try runBlocking { try await service.registerSong(secondPlan) }
        try runBlocking { try await service.deleteSong(label: "mus_service_del") }
        report.expectEqual(expected: midi, actual: try fixture.read(".porydaw/trash/mus_service_del.mid"),
                           cppID: id, what: "A trash-name collision retains the first complete MIDI payload.")
        report.expectEqual(expected: midi, actual: try fixture.read(".porydaw/trash/mus_service_del-2.mid"),
                           cppID: id, what: "A trash-name collision moves the second complete MIDI payload to the -2 destination.")
        report.expectEqual(expected: original, actual: try deletionImages(fixture), cppID: id,
                           what: "Repeated deletion with a trash collision restores all complete project file images.")
    } catch { report.fail(id, "service deletion scenario failed: \(error)") }
}

@MainActor
private func runDeletionBankChecks(_ report: CheckReport, fixtureRoot: String) {
    for gate in ["sole", "shared", "c-reference", "header-reference", "keysplit", "drumkit", "late-reference"] {
        let id = "swiftcore/SongDeletion::bank-" + gate
        do {
            let fixture = try deletionFixture(fixtureRoot, name: "bank-" + gate)
            let bank = "\tvoice_group onboardcheckvg\n\tvoice_square_1 60, 0, 2, 2, 2, 3, 12, 4\n"
            let hub = ".include \"sound/voicegroups/test_vg.inc\"\n" +
                      ".include \"sound/voicegroups/onboardcheckvg.inc\"\n"
            try fixture.write("sound/voicegroups/onboardcheckvg.inc", bank)
            try fixture.write("sound/voice_groups.inc", hub)
            try seedDeletionSong(fixture, label: "mus_vg_user")
            try fixture.write("sound/songs/midi/midi.cfg", "mus_zero.mid: -R50 -G_test_vg -V100\n" +
                              "mus_original.mid: -R50 -G_test_vg -V100\n" +
                              "mus_vg_user.mid: -R50 -G_onboardcheckvg -V100\n")
            if gate == "shared" {
                try seedDeletionSong(fixture, label: "mus_vg_user_2")
                try fixture.write("sound/songs/midi/midi.cfg", "mus_zero.mid: -R50 -G_test_vg -V100\n" +
                                  "mus_original.mid: -R50 -G_test_vg -V100\n" +
                                  "mus_vg_user.mid: -R50 -G_onboardcheckvg -V100\n" +
                                  "mus_vg_user_2.mid: -R50 -G_onboardcheckvg -V100\n")
            }
            if gate == "c-reference" || gate == "header-reference" {
                let ext = gate == "c-reference" ? "c" : "h"
                let folder = ext == "c" ? "src" : "include"
                try fixture.write("\(folder)/onboardcheck_ref.\(ext)",
                                  "extern int voicegroup_onboardcheckvg[];\n")
            }
            if gate == "keysplit" || gate == "drumkit" {
                try fixture.write("sound/voicegroups/host.inc", gate == "keysplit"
                                  ? "\tvoice_keysplit voicegroup_onboardcheckvg, KeySplitTable1\n"
                                  : "\tvoice_keysplit_all voicegroup_onboardcheckvg\n")
                try fixture.write("sound/voice_groups.inc", hub +
                                  ".include \"sound/voicegroups/host.inc\"\n")
            }
            let service = ProjectService()
            defer { try? runBlocking { await service.close() } }
            try runBlocking { try await service.open(root: fixture.root) }
            let candidate = try runBlocking { try await service.songDeletionPlan(label: "mus_vg_user") }
            if gate == "late-reference" {
                report.expectEqual(expected: "onboardcheckvg", actual: candidate.deletableVoicegroupName,
                                   cppID: id, what: "A bank candidate is valid before a late external header reference")
                try fixture.write("include/onboardcheck_late_ref.h",
                                  "extern int voicegroup_onboardcheckvg[];\n")
            }
            if gate == "sole" {
                report.expectEqual(expected: "onboardcheckvg", actual: candidate.deletableVoicegroupName,
                                   cppID: id, what: "A066 unused bank query returns the exact per-file bank name")
                let targetHub = Data(".include \"sound/voicegroups/test_vg.inc\"\n".utf8)
                let removedUnusedBank = Result {
                    try runBlocking {
                        try await service.deleteSong(label: "mus_vg_user", voicegroupName: "onboardcheckvg")
                    }
                }
                report.expectEqual(expected: true, actual: deletionOperationSucceeded(removedUnusedBank), cppID: id,
                                   what: "A067 checked deletion accepts the requested unreferenced bank")
                try removedUnusedBank.get()
                report.expectEqual(expected: false, actual: fixture.exists("sound/voicegroups/onboardcheckvg.inc"),
                                   cppID: id, what: "A068 accepted unused-bank deletion removes only its bank file")
                report.expectEqual(expected: targetHub, actual: try fixture.read("sound/voice_groups.inc"),
                                   cppID: id, what: "A069 unused-bank deletion restores exact original hub bytes")
                try runBlocking { try await service.deleteSong(label: "mus_vg_user") }
                report.expectEqual(expected: targetHub, actual: try fixture.read("sound/voice_groups.inc"),
                                   cppID: id, what: "A071 repeated service deletion leaves the original bank hub untouched")
            } else {
                switch gate {
                case "shared":
                    report.expectEqual(expected: nil as String?, actual: candidate.deletableVoicegroupName,
                                       cppID: id, what: "A058 a second song using this bank blocks the deletion candidate")
                case "c-reference":
                    report.expectEqual(expected: nil as String?, actual: candidate.deletableVoicegroupName,
                                       cppID: id, what: "A060 an external C symbol reference blocks the deletion candidate")
                case "header-reference":
                    report.expectEqual(expected: nil as String?, actual: candidate.deletableVoicegroupName,
                                       cppID: id, what: "An external header symbol reference blocks the bank deletion candidate")
                case "keysplit":
                    report.expectEqual(expected: nil as String?, actual: candidate.deletableVoicegroupName,
                                       cppID: id, what: "A065 a keysplit host blocks the deletion candidate")
                case "drumkit":
                    report.expectEqual(expected: nil as String?, actual: candidate.deletableVoicegroupName,
                                       cppID: id, what: "A drumkit host blocks the bank deletion candidate")
                case "late-reference":
                    break
                default:
                    report.fail(id, "An unrecognized bank reference gate cannot pass the deletion matrix.")
                    continue
                }
                if gate == "late-reference" {
                    do {
                        try runBlocking {
                            try await service.deleteSong(label: "mus_vg_user", voicegroupName: "onboardcheckvg")
                        }
                        report.fail(id, "A stale bank selection unexpectedly succeeded without a warning.")
                    } catch ProjectServiceError.operationFailed(let message) {
                        report.expectEqual(expected: "Voicegroup onboardcheckvg is no longer unused; it was kept.",
                                           actual: message, cppID: id,
                                           what: "A late external reference is revalidated before bank deletion")
                    }
                } else {
                    try runBlocking { try await service.deleteSong(label: "mus_vg_user") }
                }
                let expectedHub = gate == "keysplit" || gate == "drumkit"
                    ? Data(".include \"sound/voicegroups/test_vg.inc\"\n.include \"sound/voicegroups/onboardcheckvg.inc\"\n.include \"sound/voicegroups/host.inc\"\n".utf8)
                    : Data(".include \"sound/voicegroups/test_vg.inc\"\n.include \"sound/voicegroups/onboardcheckvg.inc\"\n".utf8)
                let expectedImages = [
                    Data("\tvoice_group onboardcheckvg\n\tvoice_square_1 60, 0, 2, 2, 2, 3, 12, 4\n".utf8),
                    expectedHub
                ]
                let actualImages = [try fixture.read("sound/voicegroups/onboardcheckvg.inc"),
                                    try fixture.read("sound/voice_groups.inc")]
                switch gate {
                case "shared":
                    report.expectEqual(expected: expectedImages, actual: actualImages, cppID: id,
                                       what: "A shared-song reference preserves the complete bank and hub bytes")
                case "c-reference":
                    report.expectEqual(expected: expectedImages, actual: actualImages, cppID: id,
                                       what: "An external C reference preserves the complete bank and hub bytes")
                case "header-reference":
                    report.expectEqual(expected: expectedImages, actual: actualImages, cppID: id,
                                       what: "An external header reference preserves the complete bank and hub bytes")
                case "keysplit":
                    report.expectEqual(expected: expectedImages, actual: actualImages, cppID: id,
                                       what: "A keysplit host preserves the complete bank and hub bytes")
                case "drumkit":
                    report.expectEqual(expected: expectedImages, actual: actualImages, cppID: id,
                                       what: "A drumkit host preserves the complete bank and hub bytes")
                case "late-reference":
                    report.expectEqual(expected: expectedImages, actual: actualImages, cppID: id,
                                       what: "Late reference revalidation preserves the complete bank and hub bytes")
                default:
                    report.fail(id, "An unrecognized bank reference gate cannot pass the preservation matrix.")
                }
            }
        } catch { report.fail(id, "bank reference scenario failed: \(error)") }
    }
}
