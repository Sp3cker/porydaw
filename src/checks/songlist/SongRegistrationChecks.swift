import Foundation
import PorydawApp
import PorydawProject

private struct RegistrationFixture {
    let root: String
    let table: String
    let header: String
    let charmap: String
    let linker: String

    func path(_ relative: String) -> String { root + "/" + relative }
    func read(_ relative: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path(relative)))
    }
    func write(_ relative: String, _ text: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: path(relative)))
    }
    func bytes(_ text: String) -> Data { Data(text.utf8) }
}

private func registrationFixture(
    _ fixtureRoot: String, name: String,
    aligned: Bool = false, crlf: Bool = false
) throws -> RegistrationFixture {
    let root = stageTestProject(in: fixtureRoot, projectName: name)
    let table =
        "gSongTable::\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n"
    let header = "#define MUS_ZERO 0\n#define MUS_FIRST 1\n#define MUS_LAST 2\n#define MUS_NONE 0xFFFF\n"
    let charmap =
        aligned
        ? "MUS_ZERO                  = 00 00\nMUS_FIRST                 = 01 00\nMUS_LAST                  = 02 00\n"
        : "MUS_ZERO = 00 00\nMUS_FIRST = 01 00\nMUS_LAST = 02 00\n"
    let linker = "SECTIONS {\n\tsound/songs/midi/mus_zero.o(.rodata);\n\tsound/songs/midi/mus_first.o(.rodata);\n}\n"
    let fixture = RegistrationFixture(
        root: root, table: table, header: header,
        charmap: charmap, linker: linker)
    let lineEnding = crlf ? "\r\n" : "\n"
    func staged(_ text: String) -> String {
        crlf ? text.replacingOccurrences(of: "\n", with: lineEnding) : text
    }
    try fixture.write("sound/song_table.inc", staged(table))
    try fixture.write("include/constants/songs.h", staged(header))
    try fixture.write("charmap.txt", staged(charmap))
    try fixture.write("ld_script.ld", staged(linker))
    let original = try fixture.read("sound/songs/midi/mus_session_test.mid")
    try original.write(to: URL(fileURLWithPath: fixture.path("sound/songs/midi/mus_onboardcheck.mid")))
    try original.write(to: URL(fileURLWithPath: fixture.path("sound/songs/midi/mus_first.mid")))
    try fixture.write(
        "sound/songs/midi/midi.cfg",
        "mus_onboardcheck.mid: -R50 -G_test_vg -V100\n" + "mus_first.mid: -R50 -G_test_vg -V100\n")
    return RegistrationFixture(
        root: root, table: staged(table), header: staged(header),
        charmap: staged(charmap), linker: staged(linker))
}

private func registrationExpected(_ fixture: RegistrationFixture, _ text: String) -> Data {
    fixture.bytes(fixture.table.contains("\r\n") ? text.replacingOccurrences(of: "\n", with: "\r\n") : text)
}

@MainActor
internal func runSongRegistrationChecks(_ report: CheckReport, fixtureRoot: String) {
    for (name, aligned, crlf) in [("ordinary", false, false), ("aligned-crlf", true, true)] {
        let id = "swiftcore/SongRegistration::\(name)"
        do {
            let fixture = try registrationFixture(
                fixtureRoot, name: "registration-\(name)",
                aligned: aligned, crlf: crlf)
            let service = ProjectService()
            defer { try? runBlocking { await service.close() } }
            try runBlocking { try await service.open(root: fixture.root) }
            let before = try runBlocking { try await service.songs() }
            let stray = before.first { $0.label == "mus_onboardcheck" }
            report.expectEqual(
                expected: false, actual: stray?.registered, cppID: id,
                what: "A009 staged song is not registered")
            report.expectEqual(
                expected: true, actual: stray?.isPlayable, cppID: id,
                what: "A010 staged song is playable")
            report.expectEqual(
                expected: true, actual: stray?.hasCfg, cppID: id,
                what: "A011 staged song has config")
            report.expectEqual(
                expected: "MUS_ONBOARDCHECK",
                actual: SongCatalog.constantForLabel("mus_onboardcheck"), cppID: id,
                what: "A004 label derives the registration constant directly")
            report.expectEqual(
                expected: "MUS_ONBOARDCHECK", actual: stray?.constant, cppID: id,
                what: "A013 staged constant derives from label")
            report.expectEqual(
                expected: "MUSIC_PLAYER_BGM", actual: stray?.player, cppID: id,
                what: "A014 staged song uses BGM player")
            let freshStore = ProjectStore(projectRoot: URL(filePath: fixture.root))
            let project = try runBlocking { try await freshStore.open() }
            report.expectEqual(
                expected: "_test_vg",
                actual: project.songs.first { $0.label == "mus_onboardcheck" }?.cfg.voicegroupArgument,
                cppID: id, what: "A012 fresh project reload retains the staged voicegroup argument")
            let status = SongRegistration.status(
                root: fixture.root, label: "mus_onboardcheck",
                constant: "MUS_ONBOARDCHECK")
            report.expectEqual(
                expected: ["song_table.inc", "songs.h", "ld_script.ld", "charmap.txt"],
                actual: status.missingFiles, cppID: id,
                what: "A016 all four registration locations are missing before registration")
            let plan = SongRegistration.plan(
                root: fixture.root, label: "mus_onboardcheck",
                constant: "MUS_ONBOARDCHECK", player: "MUSIC_PLAYER_BGM")
            report.expectEqual(
                expected: 3, actual: plan.songId, cppID: id,
                what: "A017 next song ID equals original table count")
            report.expectEqual(
                expected: "\tsong mus_onboardcheck, MUSIC_PLAYER_BGM, 0",
                actual: plan.songTableLine, cppID: id,
                what: "A018 planned table entry keeps exact player and flags")
            report.expectEqual(
                expected: "#define MUS_ONBOARDCHECK 3", actual: plan.songsHLine,
                cppID: id, what: "A019 A020 planned header defines the chosen ID")
            let expectedCharmap = aligned ? "MUS_ONBOARDCHECK          = 03 00" : "MUS_ONBOARDCHECK = 03 00"
            if aligned {
                report.expectEqual(
                    expected: expectedCharmap, actual: plan.charmapLine, cppID: id,
                    what: "A025 aligned charmap uses the 26-column equals position")
            } else {
                report.expectEqual(
                    expected: expectedCharmap, actual: plan.charmapLine, cppID: id,
                    what: "A023 ordinary charmap encodes the little-endian ID")
            }
            report.expectEqual(
                expected: true, actual: plan.charmapApplicable, cppID: id,
                what: "A022 charmap applies to this fixture")
            let servicePlan = try runBlocking {
                try await service.songRegistrationPlan(label: "mus_onboardcheck")
            }
            report.expectEqual(
                expected: 3, actual: servicePlan.songId, cppID: id,
                what: "A017 service plan proposes original table count")
            let registeredId = try runBlocking { try await service.registerSong(servicePlan) }
            report.expectEqual(
                expected: 3, actual: registeredId, cppID: id,
                what: "A028 registration returns the original table count")
            let table =
                "gSongTable::\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_onboardcheck, MUSIC_PLAYER_BGM, 0\n"
            let header =
                "#define MUS_ZERO 0\n#define MUS_FIRST 1\n#define MUS_LAST 2\n#define MUS_ONBOARDCHECK 3\n#define MUS_NONE 0xFFFF\n"
            let charmap =
                aligned
                ? "MUS_ZERO                  = 00 00\nMUS_FIRST                 = 01 00\nMUS_LAST                  = 02 00\nMUS_ONBOARDCHECK          = 03 00\n"
                : "MUS_ZERO = 00 00\nMUS_FIRST = 01 00\nMUS_LAST = 02 00\nMUS_ONBOARDCHECK = 03 00\n"
            let linker =
                "SECTIONS {\n\tsound/songs/midi/mus_zero.o(.rodata);\n\tsound/songs/midi/mus_first.o(.rodata);\n\tsound/songs/midi/mus_onboardcheck.o(.rodata);\n}\n"
            report.expectEqual(
                expected: registrationExpected(fixture, table),
                actual: try fixture.read("sound/song_table.inc"), cppID: id,
                what: "A018 first registration writes the entire table without disturbing rows")
            report.expectEqual(
                expected: registrationExpected(fixture, header),
                actual: try fixture.read("include/constants/songs.h"), cppID: id,
                what: "A019 first registration writes the entire header without disturbing rows")
            report.expectEqual(
                expected: registrationExpected(fixture, charmap),
                actual: try fixture.read("charmap.txt"), cppID: id,
                what: "A033 first registration writes the entire charmap without disturbing rows")
            report.expectEqual(
                expected: registrationExpected(fixture, linker),
                actual: try fixture.read("ld_script.ld"), cppID: id,
                what: "A031 first registration writes the entire linker without disturbing rows")
            let reloaded = try runBlocking { try await service.songs() }
            let fresh = reloaded.first { $0.label == "mus_onboardcheck" }
            report.expectEqual(
                expected: 3, actual: fresh?.id, cppID: id,
                what: "A056 refreshed listing retains assigned ID")
            report.expectEqual(
                expected: true, actual: fresh?.registered, cppID: id,
                what: "A055 refreshed listing marks the song registered")
            report.expectEqual(
                expected: "MUS_ONBOARDCHECK", actual: fresh?.constant, cppID: id,
                what: "A057 refreshed listing resolves the registered constant")
            report.expectEqual(
                expected: [String](), actual: fresh?.registrationGaps, cppID: id,
                what: "A029 refreshed status is complete after registration")
            for damage in ["songs.h", "charmap", "reregister"] {
                let relative = damage == "songs.h" ? "include/constants/songs.h" : "charmap.txt"
                if damage == "songs.h" {
                    try fixture.write(
                        relative,
                        String(decoding: registrationExpected(fixture, header), as: UTF8.self)
                            .replacingOccurrences(
                                of: "#define MUS_ONBOARDCHECK 3",
                                with: "#define MUS_ONBOARDCHECK 9999"))
                    let damaged = SongRegistration.status(
                        root: fixture.root, label: "mus_onboardcheck",
                        constant: "MUS_ONBOARDCHECK")
                    report.expectEqual(
                        expected: false, actual: damaged.inSongsH, cppID: id,
                        what: "A040 wrong header ID is incomplete before repair")
                } else if damage == "charmap" {
                    try fixture.write(
                        relative,
                        String(decoding: registrationExpected(fixture, charmap), as: UTF8.self)
                            .replacingOccurrences(of: "03 00", with: "FF 7F"))
                    let damaged = SongRegistration.status(
                        root: fixture.root, label: "mus_onboardcheck",
                        constant: "MUS_ONBOARDCHECK")
                    report.expectEqual(
                        expected: false, actual: damaged.inCharmap, cppID: id,
                        what: "A043 wrong charmap ID is incomplete before repair")
                }
                let repairPlan = try runBlocking {
                    try await service.songRegistrationPlan(label: "mus_onboardcheck")
                }
                let repairId = try runBlocking { try await service.registerSong(repairPlan) }
                report.expectEqual(
                    expected: 3, actual: repairId, cppID: id,
                    what: "A045 repeated registration keeps its original ID")
                report.expectEqual(
                    expected: registrationExpected(fixture, table),
                    actual: try fixture.read("sound/song_table.inc"), cppID: id,
                    what: "A046 repeated registration preserves the entire table")
                report.expectEqual(
                    expected: registrationExpected(fixture, header),
                    actual: try fixture.read("include/constants/songs.h"), cppID: id,
                    what: "A048 repeated registration restores the exact header")
                report.expectEqual(
                    expected: registrationExpected(fixture, charmap),
                    actual: try fixture.read("charmap.txt"), cppID: id,
                    what: "A052 repeated registration restores the exact charmap")
                report.expectEqual(
                    expected: registrationExpected(fixture, linker),
                    actual: try fixture.read("ld_script.ld"), cppID: id,
                    what: "A050 repeated registration preserves the entire linker")
                let repaired = try runBlocking { try await service.songs() }
                    .first { $0.label == "mus_onboardcheck" }
                report.expectEqual(
                    expected: 3, actual: repaired?.id, cppID: id,
                    what: "A045 every repaired listing retains the first registered ID")
                report.expectEqual(
                    expected: [String](), actual: repaired?.registrationGaps, cppID: id,
                    what: "A029 every repaired listing has no registration gaps")
            }
        } catch {
            report.fail(id, "registration scenario failed: \(error)")
        }
    }
    runSongRegistrationBackfillChecks(report, fixtureRoot: fixtureRoot)
    runSongRegistrationAliasChecks(report, fixtureRoot: fixtureRoot)
}

@MainActor
private func runSongRegistrationBackfillChecks(_ report: CheckReport, fixtureRoot: String) {
    for missing in ["songs.h", "charmap"] {
        let id = "swiftcore/SongRegistration::backfill-\(missing)"
        do {
            let fixture = try registrationFixture(fixtureRoot, name: "registration-backfill-\(missing)")
            let table = fixture.table
            let header = fixture.header
            let charmap = fixture.charmap
            let path = missing == "songs.h" ? "include/constants/songs.h" : "charmap.txt"
            let original = missing == "songs.h" ? header : charmap
            let removed = missing == "songs.h" ? "#define MUS_FIRST 1\n" : "MUS_FIRST = 01 00\n"
            try fixture.write(path, original.replacingOccurrences(of: removed, with: ""))
            let service = ProjectService()
            defer { try? runBlocking { await service.close() } }
            try runBlocking { try await service.open(root: fixture.root) }
            let before = try runBlocking { try await service.songs() }
            report.expectEqual(
                expected: [missing == "songs.h" ? "songs.h" : "charmap.txt"],
                actual: before.first { $0.label == "mus_first" }?.registrationGaps,
                cppID: id, what: "A066 missing middle entry is reported before backfill")
            let plan = try runBlocking { try await service.songRegistrationPlan(label: "mus_first") }
            report.expectEqual(
                expected: 1, actual: plan.songId, cppID: id,
                what: "A068 missing middle entry retains index one")
            let actualId = try runBlocking { try await service.registerSong(plan) }
            report.expectEqual(
                expected: 1, actual: actualId, cppID: id,
                what: "A068 registration backfills index one")
            report.expectEqual(
                expected: fixture.bytes(original), actual: try fixture.read(path), cppID: id,
                what: "A069 missing middle entry is restored in its original exact position")
            report.expectEqual(
                expected: fixture.bytes(table), actual: try fixture.read("sound/song_table.inc"),
                cppID: id, what: "A069 backfill leaves the complete table byte-identical")
            let after = try runBlocking { try await service.songs() }
            report.expectEqual(
                expected: [String](), actual: after.first { $0.label == "mus_first" }?.registrationGaps,
                cppID: id, what: "A069 reloaded middle song is fully registered")
        } catch { report.fail(id, "backfill scenario failed: \(error)") }
    }
}

@MainActor
private func runSongRegistrationAliasChecks(_ report: CheckReport, fixtureRoot: String) {
    let cases: [(name: String, headerId: Int?)] = [
        ("complete", nil), ("drift", 9999),
        ("later-alias", 2),
    ]
    for (name, headerId) in cases {
        let id = "swiftcore/SongRegistration::alias-\(name)"
        do {
            let fixture = try registrationFixture(fixtureRoot, name: "registration-alias-\(name)")
            try fixture.write("sound/song_table.inc", "gSongTable::\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n")
            try fixture.write("include/constants/songs.h", "#define MUS_ZERO 0\n#define MUS_NONE 0xFFFF\n")
            try fixture.write("charmap.txt", "MUS_ZERO = 00 00\n")
            let service = ProjectService()
            defer { try? runBlocking { await service.close() } }
            try runBlocking { try await service.open(root: fixture.root) }
            let firstPlan = try runBlocking { try await service.songRegistrationPlan(label: "mus_first") }
            let firstId = try runBlocking { try await service.registerSong(firstPlan) }
            report.expectEqual(
                expected: 1, actual: firstId, cppID: id,
                what: "A073 first registration of the alias label allocates index one")
            let firstTable =
                "gSongTable::\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n"
            let firstHeader = "#define MUS_ZERO 0\n#define MUS_FIRST 1\n#define MUS_NONE 0xFFFF\n"
            let firstCharmap = "MUS_ZERO = 00 00\nMUS_FIRST = 01 00\n"
            report.expectEqual(
                expected: fixture.bytes(firstTable), actual: try fixture.read("sound/song_table.inc"),
                cppID: id, what: "A073 first alias registration writes the exact complete table")
            report.expectEqual(
                expected: fixture.bytes(firstHeader),
                actual: try fixture.read("include/constants/songs.h"), cppID: id,
                what: "A073 first alias registration writes the exact complete header")
            report.expectEqual(
                expected: fixture.bytes(firstCharmap), actual: try fixture.read("charmap.txt"),
                cppID: id, what: "A073 first alias registration writes the exact complete charmap")
            let duplicateTable =
                "gSongTable::\n\tsong mus_zero, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n"
            try fixture.write("sound/song_table.inc", duplicateTable)
            let laterAlias = headerId == 2
            let expectedHeader =
                laterAlias
                ? "#define MUS_ZERO 0\n#define MUS_FIRST 2\n#define MUS_NONE 0xFFFF\n"
                : firstHeader
            let expectedCharmap =
                laterAlias
                ? "MUS_ZERO = 00 00\nMUS_FIRST = 02 00\n"
                : firstCharmap
            if laterAlias {
                try fixture.write("include/constants/songs.h", expectedHeader)
                try fixture.write("charmap.txt", expectedCharmap)
            }
            let initial = try runBlocking { try await service.songs() }
            report.expectEqual(
                expected: 1, actual: initial.first { $0.label == "mus_first" }?.id,
                cppID: id, what: "A078 duplicate table label lists its first ID")
            let status = SongRegistration.status(root: fixture.root, label: "mus_first", constant: "MUS_FIRST")
            if laterAlias {
                report.expectEqual(
                    expected: true, actual: status.inSongsH, cppID: id,
                    what: "A078 later-index header remains complete")
                report.expectEqual(
                    expected: true, actual: status.inCharmap, cppID: id,
                    what: "A078 later-index charmap remains complete")
            } else {
                report.expectEqual(
                    expected: [String](), actual: status.missingFiles, cppID: id,
                    what: "A078 duplicate alias remains complete at first ID")
            }
            if headerId == 9999 {
                try fixture.write(
                    "include/constants/songs.h",
                    "#define MUS_ZERO 0\n#define MUS_FIRST 9999\n#define MUS_NONE 0xFFFF\n")
                let damaged = SongRegistration.status(root: fixture.root, label: "mus_first", constant: "MUS_FIRST")
                report.expectEqual(
                    expected: false, actual: damaged.inSongsH, cppID: id,
                    what: "A082 duplicate alias reports a header that does not name its first ID")
            }
            let plan = try runBlocking { try await service.songRegistrationPlan(label: "mus_first") }
            if laterAlias {
                report.expectEqual(
                    expected: 2, actual: plan.songId, cppID: id,
                    what: "A079 later-index header selects its existing table ID")
            } else {
                report.expectEqual(
                    expected: 1, actual: plan.songId, cppID: id,
                    what: "A079 duplicate alias plan chooses first ID")
            }
            let actualId = try runBlocking { try await service.registerSong(plan) }
            if laterAlias {
                report.expectEqual(
                    expected: 2, actual: actualId, cppID: id,
                    what: "A084 duplicate alias registration preserves the later table ID")
            } else {
                report.expectEqual(
                    expected: 1, actual: actualId, cppID: id,
                    what: "A084 duplicate alias registration returns first ID")
            }
            report.expectEqual(
                expected: fixture.bytes(duplicateTable), actual: try fixture.read("sound/song_table.inc"),
                cppID: id, what: "A084 duplicate alias does not append or alter table rows")
            if laterAlias {
                report.expectEqual(
                    expected: fixture.bytes(expectedHeader),
                    actual: try fixture.read("include/constants/songs.h"), cppID: id,
                    what: "A085 duplicate alias preserves the valid later-index header")
            } else {
                report.expectEqual(
                    expected: fixture.bytes(expectedHeader),
                    actual: try fixture.read("include/constants/songs.h"), cppID: id,
                    what: "A085 duplicate alias repairs only its header entry")
            }
            report.expectEqual(
                expected: fixture.bytes(expectedCharmap), actual: try fixture.read("charmap.txt"),
                cppID: id, what: "A087 duplicate alias preserves the entire charmap")
            let after = try runBlocking { try await service.songs() }
            if laterAlias {
                report.expectEqual(
                    expected: [String](),
                    actual: after.first { $0.label == "mus_first" }?.registrationGaps,
                    cppID: id, what: "A078 later-index alias remains complete after registration")
            } else {
                report.expectEqual(
                    expected: [String](),
                    actual: after.first { $0.label == "mus_first" }?.registrationGaps,
                    cppID: id, what: "A078 refreshed alias remains complete")
                if headerId == 9999 {
                    let repaired = SongRegistration.status(
                        root: fixture.root, label: "mus_first",
                        constant: "MUS_FIRST")
                    report.expectEqual(
                        expected: true, actual: repaired.inSongsH, cppID: id,
                        what: "A082 duplicate alias header is complete after repair")
                }
            }
        } catch { report.fail(id, "alias scenario failed: \(error)") }
    }
}
