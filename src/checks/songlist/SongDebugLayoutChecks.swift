import Foundation
import PorydawApp
import PorydawProject

private enum DebugImages {
    static let table = "gSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong mus_littleroot_test, MUSIC_PLAYER_BGM, 0\n\tsong mus_gsc_route38, MUSIC_PLAYER_BGM, 0\n\tsong mus_caught, MUSIC_PLAYER_BGM, 0\n\tsong mus_victory_wild, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_BGM, 0\n\tsong se_pc_login, MUSIC_PLAYER_BGM, 0\n\tsong mus_onboardcheck, MUSIC_PLAYER_BGM, 0\n\tsong se_onboardcheck, MUSIC_PLAYER_BGM, 0\n"
    static let header = "#define MUS_DUMMY 0\n#define MUS_LITTLEROOT_TEST 1\n#define MUS_GSC_ROUTE38 2\n#define MUS_CAUGHT 3\n#define MUS_VICTORY_WILD 4\n#define SE_USE_ITEM 5\n#define SE_PC_LOGIN 6\n#define MUS_ONBOARDCHECK 7\n#define SE_ONBOARDCHECK 8\n"
    static let charmap = "MUS_DUMMY = 00 00\nMUS_LITTLEROOT_TEST = 01 00\nMUS_GSC_ROUTE38 = 02 00\nMUS_CAUGHT = 03 00\nMUS_VICTORY_WILD = 04 00\nSE_USE_ITEM = 05 00\nSE_PC_LOGIN = 06 00\nMUS_ONBOARDCHECK = 07 00\nSE_ONBOARDCHECK = 08 00\n"
    static let linker = "SECTIONS {\n\tsound/songs/midi/mus_dummy.o(.rodata);\n\tsound/songs/midi/mus_littleroot_test.o(.rodata);\n\tsound/songs/midi/mus_gsc_route38.o(.rodata);\n\tsound/songs/midi/mus_caught.o(.rodata);\n\tsound/songs/midi/mus_victory_wild.o(.rodata);\n\tsound/songs/midi/se_use_item.o(.rodata);\n\tsound/songs/midi/se_pc_login.o(.rodata);\n\tsound/songs/midi/mus_onboardcheck.o(.rodata);\n\tsound/songs/midi/se_onboardcheck.o(.rodata);\n}\n"
    static let seTable = "gSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong mus_littleroot_test, MUSIC_PLAYER_BGM, 0\n\tsong mus_gsc_route38, MUSIC_PLAYER_BGM, 0\n\tsong mus_caught, MUSIC_PLAYER_BGM, 0\n\tsong mus_victory_wild, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_BGM, 0\n\tsong se_pc_login, MUSIC_PLAYER_BGM, 0\n\tsong mus_onboardcheck, MUSIC_PLAYER_BGM, 0\n"
    static let seHeader = "#define MUS_DUMMY 0\n#define MUS_LITTLEROOT_TEST 1\n#define MUS_GSC_ROUTE38 2\n#define MUS_CAUGHT 3\n#define MUS_VICTORY_WILD 4\n#define SE_USE_ITEM 5\n#define SE_PC_LOGIN 6\n#define MUS_ONBOARDCHECK 7\n"
    static let seCharmap = "MUS_DUMMY = 00 00\nMUS_LITTLEROOT_TEST = 01 00\nMUS_GSC_ROUTE38 = 02 00\nMUS_CAUGHT = 03 00\nMUS_VICTORY_WILD = 04 00\nSE_USE_ITEM = 05 00\nSE_PC_LOGIN = 06 00\nMUS_ONBOARDCHECK = 07 00\n"
    static let seLinker = "SECTIONS {\n\tsound/songs/midi/mus_dummy.o(.rodata);\n\tsound/songs/midi/mus_littleroot_test.o(.rodata);\n\tsound/songs/midi/mus_gsc_route38.o(.rodata);\n\tsound/songs/midi/mus_caught.o(.rodata);\n\tsound/songs/midi/mus_victory_wild.o(.rodata);\n\tsound/songs/midi/se_use_item.o(.rodata);\n\tsound/songs/midi/se_pc_login.o(.rodata);\n\tsound/songs/midi/mus_onboardcheck.o(.rodata);\n}\n"
    static let base = "#define SOUND_LIST_BGM              \\\n    X(MUS_GSC_ROUTE38)              \\\n    X(MUS_CAUGHT)                   \\\n    X(MUS_VICTORY_WILD)\n\n#define SOUND_LIST_SE               \\\n    X(SE_USE_ITEM)                  \\\n    X(SE_PC_LOGIN)\n"
    static let append = "#define SOUND_LIST_BGM              \\\n    X(MUS_GSC_ROUTE38)              \\\n    X(MUS_CAUGHT)                   \\\n    X(MUS_VICTORY_WILD)             \\\n    X(MUS_ONBOARDCHECK)\n\n#define SOUND_LIST_SE               \\\n    X(SE_USE_ITEM)                  \\\n    X(SE_PC_LOGIN)\n"
    static let seRoute = "#define SOUND_LIST_BGM              \\\n    X(MUS_GSC_ROUTE38)              \\\n    X(MUS_CAUGHT)                   \\\n    X(MUS_VICTORY_WILD)\n\n#define SOUND_LIST_SE               \\\n    X(SE_USE_ITEM)                  \\\n    X(SE_PC_LOGIN)                  \\\n    X(SE_ONBOARDCHECK)\n"
    static let stripped = "#define SOUND_LIST_BGM              \\\n    X(MUS_GSC_ROUTE38)              \\\n    X(MUS_VICTORY_WILD)\n\n#define SOUND_LIST_SE               \\\n    X(SE_USE_ITEM)                  \\\n    X(SE_PC_LOGIN)\n"
    static let beforeFirst = "#define SOUND_LIST_BGM              \\\n    X(MUS_LITTLEROOT_TEST)          \\\n    X(MUS_GSC_ROUTE38)              \\\n    X(MUS_CAUGHT)                   \\\n    X(MUS_VICTORY_WILD)\n\n#define SOUND_LIST_SE               \\\n    X(SE_USE_ITEM)                  \\\n    X(SE_PC_LOGIN)\n"
    static let sole = "#define SOUND_LIST_BGM\n#define SOUND_LIST_SE \\\n    X(SE_ONBOARDCHECK_GHOST)\n"
    static let empty = "#define SOUND_LIST_BGM\n#define SOUND_LIST_SE\n"
    static let reinserted = "#define SOUND_LIST_BGM \\\n    X(MUS_CAUGHT)\n#define SOUND_LIST_SE\n"
    static let namedBase = "#define SOUND_LIST_BGM \\\n    X(MUS_GSC_ROUTE38             , \"MUS-GSC-ROUTE38\"       ) \\\n    X(MUS_VICTORY_WILD            , \"MUS-VICTORY-WILD\"      ) \\\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM           , \"SE-USE-ITEM\"       ) \\\n\n"
    static let namedAppend = "#define SOUND_LIST_BGM \\\n    X(MUS_GSC_ROUTE38             , \"MUS-GSC-ROUTE38\"       ) \\\n    X(MUS_VICTORY_WILD            , \"MUS-VICTORY-WILD\"      ) \\\n    X(MUS_ONBOARDCHECK            , \"MUS-ONBOARDCHECK\"      ) \\\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM           , \"SE-USE-ITEM\"       ) \\\n\n"
    static let namedCaught = "#define SOUND_LIST_BGM \\\n    X(MUS_GSC_ROUTE38             , \"MUS-GSC-ROUTE38\"       ) \\\n    X(MUS_CAUGHT                  , \"MUS-CAUGHT\"            ) \\\n    X(MUS_VICTORY_WILD            , \"MUS-VICTORY-WILD\"      ) \\\n    X(MUS_ONBOARDCHECK            , \"MUS-ONBOARDCHECK\"      ) \\\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM           , \"SE-USE-ITEM\"       ) \\\n\n"
    static let namedSe = "#define SOUND_LIST_BGM \\\n    X(MUS_GSC_ROUTE38             , \"MUS-GSC-ROUTE38\"       ) \\\n    X(MUS_CAUGHT                  , \"MUS-CAUGHT\"            ) \\\n    X(MUS_VICTORY_WILD            , \"MUS-VICTORY-WILD\"      ) \\\n    X(MUS_ONBOARDCHECK            , \"MUS-ONBOARDCHECK\"      ) \\\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM           , \"SE-USE-ITEM\"       ) \\\n    X(SE_ONBOARDCHECK       , \"SE-ONBOARDCHECK\"   ) \\\n\n"
}

private struct DebugFixture {
    let root: String

    func read(_ relative: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: root + "/" + relative))
    }

    func write(_ relative: String, _ image: String) throws {
        try Data(image.utf8).write(to: URL(fileURLWithPath: root + "/" + relative))
    }
}

private func stageDebugFixture(_ directory: String, name: String) throws -> DebugFixture {
    let root = stageTestProject(in: directory, projectName: "debug-layout-" + name)
    let fixture = DebugFixture(root: root)
    try FileManager.default.createDirectory(atPath: root + "/src", withIntermediateDirectories: true)
    try fixture.write("sound/song_table.inc", name == "se-route" ? DebugImages.seTable : DebugImages.table)
    try fixture.write("include/constants/songs.h", name == "se-route" ? DebugImages.seHeader : DebugImages.header)
    try fixture.write("charmap.txt", name == "se-route" ? DebugImages.seCharmap : DebugImages.charmap)
    try fixture.write("ld_script.ld", name == "se-route" ? DebugImages.seLinker : DebugImages.linker)
    let midi = try fixture.read("sound/songs/midi/mus_session_test.mid")
    for label in ["mus_dummy", "mus_littleroot_test", "mus_gsc_route38", "mus_caught",
                  "mus_victory_wild", "se_use_item", "se_pc_login", "mus_onboardcheck",
                  "se_onboardcheck"] {
        try midi.write(to: URL(fileURLWithPath: root + "/sound/songs/midi/" + label + ".mid"))
    }
    return fixture
}

@MainActor
private func expectDebugOnlyFilesUnchanged(_ report: CheckReport, fixture: DebugFixture, id: String) throws {
    report.expectEqual(expected: Data(DebugImages.table.utf8),
                       actual: try fixture.read("sound/song_table.inc"), cppID: id,
                       what: "debug-only registration retains the complete song table image")
    report.expectEqual(expected: Data(DebugImages.header.utf8),
                       actual: try fixture.read("include/constants/songs.h"), cppID: id,
                       what: "debug-only registration retains the complete songs header image")
    report.expectEqual(expected: Data(DebugImages.charmap.utf8),
                       actual: try fixture.read("charmap.txt"), cppID: id,
                       what: "debug-only registration retains the complete charmap image")
    report.expectEqual(expected: Data(DebugImages.linker.utf8),
                       actual: try fixture.read("ld_script.ld"), cppID: id,
                       what: "debug-only registration retains the complete linker image")
}

@MainActor
internal func runSongDebugLayoutChecks(_ report: CheckReport, fixtureRoot: String) {
    for scenario in ["append", "se-route", "mid-backfill", "before-first", "sole-empty", "named"] {
        let id = "swiftcore/SongDebugLayout::" + scenario
        do {
            let fixture = try stageDebugFixture(fixtureRoot, name: scenario)
            let label = scenario == "se-route" ? "se_onboardcheck" : "mus_onboardcheck"
            let constant = label.uppercased()
            let absentPlan = SongRegistration.plan(root: fixture.root, label: label,
                                                   constant: constant, player: "MUSIC_PLAYER_BGM")
            report.expectEqual(expected: false, actual: absentPlan.debugApplicable, cppID: id,
                               what: "A003 missing debug.c makes the registration plan non-applicable")
            if scenario == "append" {
                _ = try SongRegistration.register(root: fixture.root, label: label,
                                                  constant: constant, player: "MUSIC_PLAYER_BGM")
                report.expectEqual(expected: false,
                                   actual: SongRegistration.status(root: fixture.root, label: label,
                                                                   constant: constant).debugApplicable,
                                   cppID: id, what: "registration without debug.c remains non-applicable")
            }
            try fixture.write("src/debug.c", DebugImages.base)
            let service = ProjectService()
            defer { try? runBlocking { await service.close() } }
            let songs = try runBlocking {
                try await service.open(root: fixture.root)
                return try await service.songs()
            }
            guard let littleroot = songs.first(where: { $0.label == "mus_littleroot_test" }),
                  let caught = songs.first(where: { $0.label == "mus_caught" }) else {
                report.fail(id, "staged named songs are missing from the project listing")
                continue
            }
            report.expectEqual(expected: ["src/debug.c"], actual: littleroot.registrationGaps,
                               cppID: id, what: "A007 mus_littleroot_test has exactly the debug.c registration gap")
            report.expectEqual(expected: false, actual: caught.registrationGaps.contains("src/debug.c"),
                               cppID: id, what: "A008 mus_caught has no debug.c registration gap")

            if scenario == "sole-empty" {
                try fixture.write("src/debug.c", DebugImages.sole)
                try SongRegistration.unregister(root: fixture.root, label: "se_onboardcheck_ghost",
                                                constant: "SE_ONBOARDCHECK_GHOST")
                report.expectEqual(expected: Data(DebugImages.empty.utf8), actual: try fixture.read("src/debug.c"),
                                   cppID: id, what: "A011 removal of the sole SE entry leaves two empty defines")
                _ = try SongRegistration.register(root: fixture.root, label: "mus_caught",
                                                  constant: "MUS_CAUGHT", player: "MUSIC_PLAYER_BGM")
                report.expectEqual(expected: Data(DebugImages.reinserted.utf8),
                                   actual: try fixture.read("src/debug.c"), cppID: id,
                                   what: "A014 inserting into the empty music define keeps the SE define empty")
                try expectDebugOnlyFilesUnchanged(report, fixture: fixture, id: id)
                continue
            }
            if scenario == "named" {
                try fixture.write("src/debug.c", DebugImages.namedBase)
                report.expectEqual(expected: true,
                                   actual: SongRegistration.status(root: fixture.root, label: "mus_gsc_route38",
                                                                   constant: "MUS_GSC_ROUTE38").inDebugMenu,
                                   cppID: id, what: "A017 named music entry is recognized in the status")
                _ = try SongRegistration.register(root: fixture.root, label: label,
                                                  constant: constant, player: "MUSIC_PLAYER_BGM")
                report.expectEqual(expected: Data(DebugImages.namedAppend.utf8),
                                   actual: try fixture.read("src/debug.c"), cppID: id,
                                   what: "A019 named music append retains comma paren and slash alignment")
                _ = try SongRegistration.register(root: fixture.root, label: label,
                                                  constant: constant, player: "MUSIC_PLAYER_BGM")
                report.expectEqual(expected: Data(DebugImages.namedAppend.utf8),
                                   actual: try fixture.read("src/debug.c"), cppID: id,
                                   what: "A022 repeated named music registration preserves the complete image")
                _ = try SongRegistration.register(root: fixture.root, label: "mus_caught",
                                                  constant: "MUS_CAUGHT", player: "MUSIC_PLAYER_BGM")
                report.expectEqual(expected: Data(DebugImages.namedCaught.utf8),
                                   actual: try fixture.read("src/debug.c"), cppID: id,
                                   what: "A024 named middle backfill preserves each display string and alignment")
                _ = try SongRegistration.register(root: fixture.root, label: "se_onboardcheck",
                                                  constant: "SE_ONBOARDCHECK", player: "MUSIC_PLAYER_BGM")
                report.expectEqual(expected: Data(DebugImages.namedSe.utf8),
                                   actual: try fixture.read("src/debug.c"), cppID: id,
                                   what: "A026 named SE append retains SE display and alignment")
                try expectDebugOnlyFilesUnchanged(report, fixture: fixture, id: id)
                try SongRegistration.unregister(root: fixture.root, label: "se_onboardcheck",
                                                constant: "SE_ONBOARDCHECK")
                report.expectEqual(expected: Data(DebugImages.namedCaught.utf8),
                                   actual: try fixture.read("src/debug.c"), cppID: id,
                                   what: "A028 named SE removal restores the preceding complete image")
                report.expectEqual(expected: false,
                                   actual: SongRegistration.removalPlan(root: fixture.root,
                                                                        label: "se_onboardcheck",
                                                                        constant: "SE_ONBOARDCHECK").inDebugMenu,
                                   cppID: id, what: "removed named SE entry is absent from the removal plan")
                try SongRegistration.unregister(root: fixture.root, label: "mus_caught", constant: "MUS_CAUGHT")
                report.expectEqual(expected: Data(DebugImages.namedAppend.utf8),
                                   actual: try fixture.read("src/debug.c"), cppID: id,
                                   what: "A030 named music middle removal restores the appended image")
                report.expectEqual(expected: false,
                                   actual: SongRegistration.removalPlan(root: fixture.root,
                                                                        label: "mus_caught",
                                                                        constant: "MUS_CAUGHT").inDebugMenu,
                                   cppID: id, what: "removed named middle entry is absent from the removal plan")
                try SongRegistration.unregister(root: fixture.root, label: label, constant: constant)
                report.expectEqual(expected: Data(DebugImages.namedBase.utf8),
                                   actual: try fixture.read("src/debug.c"), cppID: id,
                                   what: "A032 named music removal restores the original complete image")
                report.expectEqual(expected: false,
                                   actual: SongRegistration.removalPlan(root: fixture.root,
                                                                        label: label, constant: constant).inDebugMenu,
                                   cppID: id, what: "removed named music entry is absent from the removal plan")
                continue
            }
            let before = SongRegistration.status(root: fixture.root, label: label, constant: constant)
            let expectedGaps = scenario == "se-route"
                ? ["song_table.inc", "songs.h", "ld_script.ld", "charmap.txt", "src/debug.c"]
                : ["src/debug.c"]
            report.expectEqual(expected: expectedGaps, actual: before.missingFiles,
                               cppID: id, what: "A034 present sound list includes debug.c among incomplete registration locations")
            if scenario == "mid-backfill" {
                try fixture.write("src/debug.c", DebugImages.stripped)
                _ = try SongRegistration.register(root: fixture.root, label: "mus_caught",
                                                  constant: "MUS_CAUGHT", player: "MUSIC_PLAYER_BGM")
                report.expectEqual(expected: Data(DebugImages.base.utf8), actual: try fixture.read("src/debug.c"),
                                   cppID: id, what: "A037 inserting an existing ID in the middle restores the full list")
                report.expectEqual(expected: [String](),
                                   actual: SongRegistration.status(root: fixture.root, label: "mus_caught",
                                                                   constant: "MUS_CAUGHT").missingFiles,
                                   cppID: id, what: "middle debug backfill completes the existing song")
                try expectDebugOnlyFilesUnchanged(report, fixture: fixture, id: id)
                continue
            }
            if scenario == "before-first" {
                _ = try SongRegistration.register(root: fixture.root, label: "mus_littleroot_test",
                                                  constant: "MUS_LITTLEROOT_TEST", player: "MUSIC_PLAYER_BGM")
                report.expectEqual(expected: Data(DebugImages.beforeFirst.utf8),
                                   actual: try fixture.read("src/debug.c"), cppID: id,
                                   what: "A040 insertion before the first music ID retains all other list entries")
                report.expectEqual(expected: [String](),
                                   actual: SongRegistration.status(root: fixture.root,
                                                                   label: "mus_littleroot_test",
                                                                   constant: "MUS_LITTLEROOT_TEST").missingFiles,
                                   cppID: id, what: "before-first backfill completes littleroot registration")
                try expectDebugOnlyFilesUnchanged(report, fixture: fixture, id: id)
                continue
            }
            _ = try SongRegistration.register(root: fixture.root, label: label,
                                              constant: constant, player: "MUSIC_PLAYER_BGM")
            let expected = scenario == "se-route" ? DebugImages.seRoute : DebugImages.append
            report.expectEqual(expected: Data(expected.utf8), actual: try fixture.read("src/debug.c"),
                               cppID: id, what: "A048 debug append routes the new constant into its ID-ordered list")
            if scenario == "append" {
                report.expectEqual(expected: Data(DebugImages.table.utf8),
                                   actual: try fixture.read("sound/song_table.inc"), cppID: id,
                                   what: "A049 debug-only append retains the exact song table")
                report.expectEqual(expected: Data(DebugImages.header.utf8),
                                   actual: try fixture.read("include/constants/songs.h"), cppID: id,
                                   what: "A051 debug-only append retains the exact songs header")
                report.expectEqual(expected: Data(DebugImages.charmap.utf8),
                                   actual: try fixture.read("charmap.txt"), cppID: id,
                                   what: "A053 debug-only append retains the exact charmap")
                report.expectEqual(expected: Data(DebugImages.linker.utf8),
                                   actual: try fixture.read("ld_script.ld"), cppID: id,
                                   what: "A055 debug-only append retains the exact linker")
            }
            _ = try SongRegistration.register(root: fixture.root, label: label,
                                              constant: constant, player: "MUSIC_PLAYER_BGM")
            report.expectEqual(expected: Data(expected.utf8), actual: try fixture.read("src/debug.c"),
                               cppID: id, what: "A058 repeat registration leaves the full debug list unchanged")
            let after = SongRegistration.status(root: fixture.root, label: label, constant: constant)
            report.expectEqual(expected: [], actual: after.missingFiles, cppID: id,
                               what: "A060 registered debug song has no remaining registration gaps")
            report.expectEqual(expected: true,
                               actual: SongRegistration.removalPlan(root: fixture.root, label: label,
                                                                    constant: constant).inDebugMenu,
                               cppID: id, what: "A061 removal plan locates the newly registered debug entry")
            if scenario == "se-route" {
                try SongRegistration.unregister(root: fixture.root, label: label, constant: constant)
                report.expectEqual(expected: Data(DebugImages.base.utf8), actual: try fixture.read("src/debug.c"),
                                   cppID: id, what: "A063 SE removal restores the original debug list bytes")
                report.expectEqual(expected: Data(DebugImages.seTable.utf8),
                                   actual: try fixture.read("sound/song_table.inc"), cppID: id,
                                   what: "A065 SE removal preserves the exact original song table")
                report.expectEqual(expected: Data(DebugImages.seHeader.utf8),
                                   actual: try fixture.read("include/constants/songs.h"), cppID: id,
                                   what: "A067 SE removal preserves the exact original header")
                report.expectEqual(expected: Data(DebugImages.seCharmap.utf8),
                                   actual: try fixture.read("charmap.txt"), cppID: id,
                                   what: "A069 SE removal preserves the exact original charmap")
                report.expectEqual(expected: Data(DebugImages.seLinker.utf8),
                                   actual: try fixture.read("ld_script.ld"), cppID: id,
                                   what: "A071 SE removal preserves the exact original linker")
            }
        } catch {
            report.fail(id, "debug layout " + scenario + " failed: " + String(describing: error))
        }
    }
}
