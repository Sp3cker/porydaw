import Foundation
import PorydawProject

private struct RegionFixture {
    let root: String
    let linker: Data

    func read(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: root + "/" + name))
    }

    func write(_ name: String, _ bytes: String) throws {
        try Data(bytes.utf8).write(to: URL(fileURLWithPath: root + "/" + name))
    }

    func debugEntry(_ constant: String, inSe: Bool) throws -> Bool {
        let debug = String(decoding: try read("src/debug.c"), as: UTF8.self)
        guard let bgm = debug.range(of: "#define SOUND_LIST_BGM"),
            let se = debug.range(of: "#define SOUND_LIST_SE"),
            let entry = debug.range(of: "X(\(constant))")
        else { return false }
        return inSe
            ? entry.lowerBound > se.lowerBound
            : entry.lowerBound > bgm.lowerBound && entry.lowerBound < se.lowerBound
    }
}

private enum RegionImages {
    static let linker = "SECTIONS {\n\t*(.rodata)\n}\n"
    static let table =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let charmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nPH_ONE = 07 00\nPH_TWO = 08 00\n"
    static let numericHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define END_MUS             6\n#define PH_ONE              7\n#define PH_TWO              8\n#define MUS_NONE            0xFFFF\n"
    static let aliasHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define END_SE              SE_LAST\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define END_MUS             MUS_LAST\n#define PH_ONE              7\n#define PH_TWO              8\n#define MUS_NONE            0xFFFF\n"
    static let numericDebug =
        "#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST)\n"
    static let aliasDebug =
        "static const u8 *const sBGMNames[END_MUS - START_MUS + 1];\n#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST)\n"
    static let numericMusicTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_valcheck, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let numericMusicHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define MUS_VALCHECK        7\n#define END_MUS             7\n#define PH_ONE              8\n#define PH_TWO              9\n#define MUS_NONE            0xFFFF\n"
    static let numericMusicCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_VALCHECK = 07 00\nPH_ONE = 08 00\nPH_TWO = 09 00\n"
    // Fork songregistry.cpp:313-321,382-385,1055-1058 aligns replaced final lines to each list's slash column.
    static let numericMusicDebug =
        "#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST)  \\\n    X(MUS_VALCHECK)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST)\n"
    static let numericRemovedTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let numericRemovedHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define END_MUS             6\n#define PH_ONE              8\n#define PH_TWO              9\n#define MUS_NONE            0xFFFF\n"
    static let numericRemovedCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nPH_ONE = 08 00\nPH_TWO = 09 00\n"
    static let numericReuseTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_reuse, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let numericReuseHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define MUS_REUSE           7\n#define END_MUS             7\n#define PH_ONE              8\n#define PH_TWO              9\n#define MUS_NONE            0xFFFF\n"
    static let numericReuseCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_REUSE = 07 00\nPH_ONE = 08 00\nPH_TWO = 09 00\n"
    static let numericReuseDebug =
        "#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST)  \\\n    X(MUS_REUSE)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST)\n"
    static let numericSeTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong se_valcheck, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let numericSeHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define SE_VALCHECK         3\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define END_MUS             6\n#define PH_ONE              7\n#define PH_TWO              8\n#define MUS_NONE            0xFFFF\n"
    static let numericSeCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nSE_VALCHECK = 03 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nPH_ONE = 07 00\nPH_TWO = 08 00\n"
    static let aliasMusicTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_oldcheck, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let aliasMusicHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define END_SE              SE_LAST\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define MUS_OLDCHECK        7\n#define END_MUS             MUS_OLDCHECK\n#define PH_ONE              8\n#define PH_TWO              9\n#define MUS_NONE            0xFFFF\n"
    static let aliasMusicCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nPH_ONE = 08 00\nPH_TWO = 09 00\n"
    static let aliasMusicDebug =
        "static const u8 *const sBGMNames[END_MUS - START_MUS + 1];\n#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST)  \\\n    X(MUS_OLDCHECK)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST)\n"
    static let aliasSeTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong se_oldcheck, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_oldcheck, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let aliasSeHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define SE_OLDCHECK         3\n#define END_SE              SE_OLDCHECK\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define MUS_OLDCHECK        7\n#define END_MUS             MUS_OLDCHECK\n#define PH_ONE              8\n#define PH_TWO              9\n#define MUS_NONE            0xFFFF\n"
    static let aliasSeCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nSE_OLDCHECK = 03 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nPH_ONE = 08 00\nPH_TWO = 09 00\n"
    static let aliasSeDebug =
        "static const u8 *const sBGMNames[END_MUS - START_MUS + 1];\n#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST)  \\\n    X(MUS_OLDCHECK)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST)     \\\n    X(SE_OLDCHECK)\n"
}

private func stageRegionFixture(_ fixtureRoot: String, name: String, alias: Bool) throws -> RegionFixture {
    let root = stageTestProject(in: fixtureRoot, projectName: "region-" + name)
    try FileManager.default.createDirectory(atPath: root + "/src", withIntermediateDirectories: true)
    let fixture = RegionFixture(root: root, linker: Data(RegionImages.linker.utf8))
    try fixture.write("sound/song_table.inc", RegionImages.table)
    try fixture.write("include/constants/songs.h", alias ? RegionImages.aliasHeader : RegionImages.numericHeader)
    try fixture.write("charmap.txt", RegionImages.charmap)
    try fixture.write("ld_script.ld", RegionImages.linker)
    try fixture.write("src/debug.c", alias ? RegionImages.aliasDebug : RegionImages.numericDebug)
    return fixture
}

@MainActor
internal func runSongRegionRegistrationChecks(_ report: CheckReport, fixtureRoot: String) {
    runNumericRegionChecks(report, fixtureRoot: fixtureRoot)
    runAliasRegionChecks(report, fixtureRoot: fixtureRoot)
}

@MainActor
private func runNumericRegionChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/SongRegion::numeric"
    do {
        let markerless = try stageRegionFixture(fixtureRoot, name: "markerless", alias: false)
        try markerless.write(
            "include/constants/songs.h",
            "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define PH_ONE              7\n#define PH_TWO              8\n#define MUS_NONE            0xFFFF\n"
        )
        report.expectEqual(
            expected: 9,
            actual: SongRegistration.plan(
                root: markerless.root,
                label: "mus_markerless", constant: "MUS_MARKERLESS",
                player: "MUSIC_PLAYER_BGM"
            ).songId, cppID: id,
            what: "A006 markerless music planning appends at ID nine")
        report.expectEqual(
            expected: Data(RegionImages.table.utf8),
            actual: try markerless.read("sound/song_table.inc"), cppID: id,
            what: "Markerless planning leaves the full song table intact")

        let se = try stageRegionFixture(fixtureRoot, name: "numeric-se", alias: false)
        report.expectEqual(
            expected: 3,
            actual: try SongRegistration.register(
                root: se.root,
                label: "se_valcheck", constant: "SE_VALCHECK", player: "MUSIC_PLAYER_SE1"),
            cppID: id, what: "A008 numeric SE registration fills ID three")
        report.expectEqual(
            expected: Data(RegionImages.numericSeTable.utf8),
            actual: try se.read("sound/song_table.inc"), cppID: id,
            what: "A010 numeric SE table preserves player number and all surrounding rows")
        report.expectEqual(
            expected: Data(RegionImages.numericSeHeader.utf8),
            actual: try se.read("include/constants/songs.h"), cppID: id,
            what: "A011 numeric SE header inserts the ID before START_MUS")
        report.expectEqual(
            expected: Data(RegionImages.numericSeCharmap.utf8),
            actual: try se.read("charmap.txt"), cppID: id,
            what: "Numeric SE charmap contains the precise slot bytes")
        report.expectEqual(
            expected: true, actual: try se.debugEntry("SE_VALCHECK", inSe: true),
            cppID: id, what: "A014 numeric SE debug entry belongs in SOUND_LIST_SE")
        report.expectEqual(
            expected: se.linker, actual: try se.read("ld_script.ld"), cppID: id,
            what: "Numeric SE registration preserves the linker image")

        let music = try stageRegionFixture(fixtureRoot, name: "numeric-music", alias: false)
        report.expectEqual(
            expected: 7,
            actual: try SongRegistration.register(
                root: music.root,
                label: "mus_valcheck", constant: "MUS_VALCHECK", player: "MUSIC_PLAYER_BGM"),
            cppID: id, what: "A016 numeric music insertion allocates ID seven")
        report.expectEqual(
            expected: Data(RegionImages.numericMusicTable.utf8),
            actual: try music.read("sound/song_table.inc"), cppID: id,
            what: "Numeric music insertion preserves all table rows")
        report.expectEqual(
            expected: Data(RegionImages.numericMusicHeader.utf8),
            actual: try music.read("include/constants/songs.h"), cppID: id,
            what: "A017 numeric END_MUS advances to seven while phoneme IDs shift")
        report.expectEqual(
            expected: Data(RegionImages.numericMusicCharmap.utf8),
            actual: try music.read("charmap.txt"), cppID: id,
            what: "Numeric music insertion shifts the exact phoneme charmap bytes")
        report.expectEqual(
            expected: Data(RegionImages.numericMusicDebug.utf8),
            actual: try music.read("src/debug.c"), cppID: id,
            what: "Numeric music debug entry lands in SOUND_LIST_BGM")
        report.expectEqual(
            expected: music.linker, actual: try music.read("ld_script.ld"), cppID: id,
            what: "Numeric music insertion leaves linker bytes untouched")
        try SongRegistration.unregister(root: music.root, label: "mus_valcheck", constant: "MUS_VALCHECK")
        let removedStatus = SongRegistration.status(
            root: music.root, label: "mus_valcheck",
            constant: "MUS_VALCHECK")
        report.expectEqual(
            expected: false, actual: removedStatus.inSongTable, cppID: id,
            what: "A019 numeric removal unregisters the music table entry")
        report.expectEqual(
            expected: Data(RegionImages.numericRemovedTable.utf8),
            actual: try music.read("sound/song_table.inc"), cppID: id,
            what: "A022 removal restores the fallback table slot before phonemes")
        report.expectEqual(
            expected: Data(RegionImages.numericRemovedHeader.utf8),
            actual: try music.read("include/constants/songs.h"), cppID: id,
            what: "A024 numeric END_MUS returns to six without undoing shifted phonemes")
        report.expectEqual(
            expected: Data(RegionImages.numericRemovedCharmap.utf8),
            actual: try music.read("charmap.txt"), cppID: id,
            what: "A026 removal retains the independently expected phoneme charmap")
        report.expectEqual(
            expected: Data(RegionImages.numericDebug.utf8),
            actual: try music.read("src/debug.c"), cppID: id,
            what: "A028 removal returns the complete original debug image")
        report.expectEqual(
            expected: music.linker, actual: try music.read("ld_script.ld"), cppID: id,
            what: "A030 removal keeps the complete original linker image")
        let reusePlan = SongRegistration.plan(
            root: music.root, label: "mus_reuse",
            constant: "MUS_REUSE", player: "MUSIC_PLAYER_BGM")
        report.expectEqual(
            expected: true, actual: reusePlan.repointEndMus, cppID: id,
            what: "A020 numeric removal leaves END_MUS ready to advance on reuse")
        report.expectEqual(
            expected: 7, actual: reusePlan.songId, cppID: id,
            what: "A032 next music registration reuses the removed ID seven")
        report.expectEqual(
            expected: 7,
            actual: try SongRegistration.register(
                root: music.root,
                label: "mus_reuse", constant: "MUS_REUSE", player: "MUSIC_PLAYER_BGM"),
            cppID: id, what: "Music re-registration restores ID seven")
        report.expectEqual(
            expected: Data(RegionImages.numericReuseTable.utf8),
            actual: try music.read("sound/song_table.inc"), cppID: id,
            what: "Music re-registration restores the full table image")
        report.expectEqual(
            expected: Data(RegionImages.numericReuseHeader.utf8),
            actual: try music.read("include/constants/songs.h"), cppID: id,
            what: "Music re-registration restores numeric marker adjacency")
        report.expectEqual(
            expected: Data(RegionImages.numericReuseCharmap.utf8),
            actual: try music.read("charmap.txt"), cppID: id,
            what: "Music re-registration preserves all charmap entries")
        report.expectEqual(
            expected: Data(RegionImages.numericReuseDebug.utf8),
            actual: try music.read("src/debug.c"), cppID: id,
            what: "Music re-registration restores BGM debug-list placement")
        report.expectEqual(
            expected: music.linker, actual: try music.read("ld_script.ld"), cppID: id,
            what: "Music re-registration leaves the full linker image intact")
    } catch { report.fail(id, "numeric region scenario failed: \(error)") }
}

@MainActor
private func runAliasRegionChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/SongRegion::alias"
    do {
        let fixture = try stageRegionFixture(fixtureRoot, name: "alias-insert", alias: true)
        report.expectEqual(
            expected: 7,
            actual: try SongRegistration.register(
                root: fixture.root,
                label: "mus_oldcheck", constant: "MUS_OLDCHECK", player: "MUSIC_PLAYER_BGM"),
            cppID: id, what: "A036 symbolic music registration allocates ID seven")
        report.expectEqual(
            expected: true,
            actual: SongRegistration.status(
                root: fixture.root,
                label: "mus_oldcheck", constant: "MUS_OLDCHECK"
            ).inSongTable,
            cppID: id, what: "A035 symbolic registration occupies a music table slot")
        report.expectEqual(
            expected: Data(RegionImages.aliasMusicTable.utf8),
            actual: try fixture.read("sound/song_table.inc"), cppID: id,
            what: "Symbolic music registration preserves exact table bytes")
        report.expectEqual(
            expected: Data(RegionImages.aliasMusicHeader.utf8),
            actual: try fixture.read("include/constants/songs.h"), cppID: id,
            what: "A038 symbolic END_MUS refers to MUS_OLDCHECK")
        report.expectEqual(
            expected: Data(RegionImages.aliasMusicCharmap.utf8),
            actual: try fixture.read("charmap.txt"), cppID: id,
            what: "A039 MUS_OLDCHECK charmap entry encodes 07 00")
        report.expectEqual(
            expected: Data(RegionImages.aliasMusicDebug.utf8),
            actual: try fixture.read("src/debug.c"), cppID: id,
            what: "Symbolic music debug entry lands in the BGM list")
        report.expectEqual(
            expected: fixture.linker, actual: try fixture.read("ld_script.ld"), cppID: id,
            what: "Symbolic music insertion preserves linker image")
        let status = SongRegistration.status(root: fixture.root, label: "mus_oldcheck", constant: "MUS_OLDCHECK")
        report.expectEqual(
            expected: [String](), actual: status.missingFiles, cppID: id,
            what: "A041 symbolic music registration is complete")
        report.expectEqual(
            expected: 3,
            actual: try SongRegistration.register(
                root: fixture.root,
                label: "se_oldcheck", constant: "SE_OLDCHECK", player: "MUSIC_PLAYER_SE1"),
            cppID: id, what: "A043 symbolic SE registration fills ID three")
        report.expectEqual(
            expected: Data(RegionImages.aliasSeTable.utf8),
            actual: try fixture.read("sound/song_table.inc"), cppID: id,
            what: "Symbolic SE player number and table bytes are exact")
        report.expectEqual(
            expected: Data(RegionImages.aliasSeHeader.utf8),
            actual: try fixture.read("include/constants/songs.h"), cppID: id,
            what: "Symbolic END_SE advances to SE_OLDCHECK")
        report.expectEqual(
            expected: Data(RegionImages.aliasSeCharmap.utf8),
            actual: try fixture.read("charmap.txt"), cppID: id,
            what: "Symbolic SE charmap preserves region adjacency")
        report.expectEqual(
            expected: Data(RegionImages.aliasSeDebug.utf8),
            actual: try fixture.read("src/debug.c"), cppID: id,
            what: "A044 symbolic SE debug entry lands after SOUND_LIST_SE")
        report.expectEqual(
            expected: 3,
            actual: try SongRegistration.register(
                root: fixture.root,
                label: "se_oldcheck", constant: "SE_OLDCHECK", player: "MUSIC_PLAYER_SE1"),
            cppID: id, what: "A046 re-registering symbolic SE keeps the original ID")
        report.expectEqual(
            expected: Data(RegionImages.aliasSeTable.utf8),
            actual: try fixture.read("sound/song_table.inc"), cppID: id,
            what: "Re-registering symbolic SE leaves the entire table intact")
        report.expectEqual(
            expected: Data(RegionImages.aliasSeHeader.utf8),
            actual: try fixture.read("include/constants/songs.h"), cppID: id,
            what: "Re-registering symbolic SE leaves the entire header intact")
        report.expectEqual(
            expected: Data(RegionImages.aliasSeCharmap.utf8),
            actual: try fixture.read("charmap.txt"), cppID: id,
            what: "Re-registering symbolic SE leaves the entire charmap intact")
        report.expectEqual(
            expected: Data(RegionImages.aliasSeDebug.utf8),
            actual: try fixture.read("src/debug.c"), cppID: id,
            what: "Re-registering symbolic SE leaves exactly one debug entry")
        report.expectEqual(
            expected: fixture.linker, actual: try fixture.read("ld_script.ld"), cppID: id,
            what: "Re-registering symbolic SE leaves linker bytes intact")
        runStrandedRegionChecks(report, fixtureRoot: fixtureRoot)
        runOverflowRegionChecks(report, fixtureRoot: fixtureRoot)
    } catch { report.fail(id, "alias region scenario failed: \(error)") }
}

private enum RegionJourneyImages {
    static let strandedTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong se_oldcheck, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_oldcheck, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n\tsong mus_straggler, MUSIC_PLAYER_BGM, 0\n"
    static let strandedHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define SE_OLDCHECK         3\n#define END_SE              SE_OLDCHECK\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define MUS_OLDCHECK        7\n#define MUS_STRAGGLER       9\n#define END_MUS             MUS_OLDCHECK\n#define PH_ONE              8\n#define PH_TWO              9\n#define MUS_NONE            0xFFFF\n"
    static let strandedCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nSE_OLDCHECK = 03 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nPH_ONE = 08 00\nPH_TWO = 09 00\nMUS_STRAGGLER = 09 00\n"
    static let strandedDebug =
        "static const u8 *const sBGMNames[END_MUS - START_MUS + 1];\n#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST) \\\n    X(MUS_OLDCHECK) \\\n    X(MUS_STRAGGLER)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST) \\\n    X(SE_OLDCHECK)\n"
    static let migratedTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong se_oldcheck, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_oldcheck, MUSIC_PLAYER_BGM, 0\n\tsong mus_straggler, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let migratedHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define SE_OLDCHECK         3\n#define END_SE              SE_OLDCHECK\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define MUS_OLDCHECK        7\n#define MUS_STRAGGLER       8\n#define END_MUS             MUS_STRAGGLER\n#define PH_ONE              9\n#define PH_TWO              10\n#define MUS_NONE            0xFFFF\n"
    static let migratedCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nSE_OLDCHECK = 03 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nMUS_STRAGGLER = 08 00\nPH_ONE = 09 00\nPH_TWO = 0A 00\n"
    static let vacatedTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong se_oldcheck, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_oldcheck, MUSIC_PLAYER_BGM, 0\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let vacatedHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define SE_OLDCHECK         3\n#define END_SE              SE_OLDCHECK\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define MUS_OLDCHECK        7\n#define END_MUS             MUS_OLDCHECK\n#define PH_ONE              9\n#define PH_TWO              10\n#define MUS_NONE            0xFFFF\n"
    static let vacatedCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nSE_OLDCHECK = 03 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nPH_ONE = 09 00\nPH_TWO = 0A 00\n"
    // The stranded input is hand-staged with one-space continuations; fork songregistry.cpp:1254-1255 strips only the removed final entry.
    static let vacatedDebug =
        "static const u8 *const sBGMNames[END_MUS - START_MUS + 1];\n#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST) \\\n    X(MUS_OLDCHECK)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST) \\\n    X(SE_OLDCHECK)\n"
    static let refillTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong se_oldcheck, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_oldcheck, MUSIC_PLAYER_BGM, 0\n\tsong mus_refill, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let refillHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define SE_OLDCHECK         3\n#define END_SE              SE_OLDCHECK\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define MUS_OLDCHECK        7\n#define MUS_REFILL          8\n#define END_MUS             MUS_REFILL\n#define PH_ONE              9\n#define PH_TWO              10\n#define MUS_NONE            0xFFFF\n"
    static let refillCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nSE_OLDCHECK = 03 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nMUS_REFILL = 08 00\nPH_ONE = 09 00\nPH_TWO = 0A 00\n"
    static let refillDebug =
        "static const u8 *const sBGMNames[END_MUS - START_MUS + 1];\n#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST) \\\n    X(MUS_OLDCHECK) \\\n    X(MUS_REFILL)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST) \\\n    X(SE_OLDCHECK)\n"
    static let reuseSourceTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong se_oldcheck, MUSIC_PLAYER_SE1, 1\n\tsong dummy_song_header, MUSIC_PLAYER_BGM, 0\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_oldcheck, MUSIC_PLAYER_BGM, 0\n\tsong mus_reuse_source, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let reuseSourceHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define SE_OLDCHECK         3\n#define END_SE              SE_OLDCHECK\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define MUS_OLDCHECK        7\n#define MUS_REUSE_SOURCE    8\n#define END_MUS             MUS_REUSE_SOURCE\n#define PH_ONE              9\n#define PH_TWO              10\n#define MUS_NONE            0xFFFF\n"
    static let reuseSourceCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nSE_OLDCHECK = 03 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nMUS_REUSE_SOURCE = 08 00\nPH_ONE = 09 00\nPH_TWO = 0A 00\n"
    // Unlike the staged image above, these entries were generated by the fork writer's slash-column rule.
    static let reuseSourceDebug =
        "static const u8 *const sBGMNames[END_MUS - START_MUS + 1];\n#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST)  \\\n    X(MUS_OLDCHECK) \\\n    X(MUS_REUSE_SOURCE)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST)     \\\n    X(SE_OLDCHECK)\n"
    static let vacatedProductionDebug =
        "static const u8 *const sBGMNames[END_MUS - START_MUS + 1];\n#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST)  \\\n    X(MUS_OLDCHECK)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST)     \\\n    X(SE_OLDCHECK)\n"
    static let refillProductionDebug =
        "static const u8 *const sBGMNames[END_MUS - START_MUS + 1];\n#define SOUND_LIST_BGM \\\n    X(MUS_FIRST) \\\n    X(MUS_LAST)  \\\n    X(MUS_OLDCHECK) \\\n    X(MUS_REFILL)\n\n#define SOUND_LIST_SE \\\n    X(SE_USE_ITEM) \\\n    X(SE_LAST)     \\\n    X(SE_OLDCHECK)\n"
    static let extraTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong se_oldcheck, MUSIC_PLAYER_SE1, 1\n\tsong se_extra, MUSIC_PLAYER_SE1, 1\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_oldcheck, MUSIC_PLAYER_BGM, 0\n\tsong mus_refill, MUSIC_PLAYER_BGM, 0\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let extraHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define SE_OLDCHECK         3\n#define SE_EXTRA            4\n#define END_SE              SE_EXTRA\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define MUS_OLDCHECK        7\n#define MUS_REFILL          8\n#define END_MUS             MUS_REFILL\n#define PH_ONE              9\n#define PH_TWO              10\n#define MUS_NONE            0xFFFF\n"
    static let extraCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nSE_OLDCHECK = 03 00\nSE_EXTRA = 04 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nMUS_REFILL = 08 00\nPH_ONE = 09 00\nPH_TWO = 0A 00\n"
    static let overflowTable =
        "\t.equiv MUSIC_PLAYER_BGM, 0\n\t.equiv MUSIC_PLAYER_SE1, 1\n\ngSongTable::\n\tsong mus_dummy, MUSIC_PLAYER_BGM, 0\n\tsong se_use_item, MUSIC_PLAYER_SE1, 1\n\tsong se_last, MUSIC_PLAYER_SE1, 1\n\tsong se_oldcheck, MUSIC_PLAYER_SE1, 1\n\tsong se_extra, MUSIC_PLAYER_SE1, 1\n\tsong mus_first, MUSIC_PLAYER_BGM, 0\n\tsong mus_last, MUSIC_PLAYER_BGM, 0\n\tsong mus_oldcheck, MUSIC_PLAYER_BGM, 0\n\tsong mus_refill, MUSIC_PLAYER_BGM, 0\n\tsong se_over, MUSIC_PLAYER_SE1, 1\n\tsong ph_one, MUSIC_PLAYER_SE1, 1\n\tsong ph_two, MUSIC_PLAYER_SE1, 1\n"
    static let overflowHeader =
        "#define MUS_DUMMY           0\n#define SE_USE_ITEM         1\n#define SE_LAST             2\n#define SE_OLDCHECK         3\n#define SE_EXTRA            4\n#define END_SE              SE_EXTRA\n#define START_MUS           5\n#define MUS_FIRST           5\n#define MUS_LAST            6\n#define MUS_OLDCHECK        7\n#define MUS_REFILL          8\n#define SE_OVER             9\n#define END_MUS             SE_OVER\n#define PH_ONE              10\n#define PH_TWO              11\n#define MUS_NONE            0xFFFF\n"
    static let overflowCharmap =
        "MUS_DUMMY = 00 00\nSE_USE_ITEM = 01 00\nSE_LAST = 02 00\nSE_OLDCHECK = 03 00\nSE_EXTRA = 04 00\nMUS_FIRST = 05 00\nMUS_LAST = 06 00\nMUS_OLDCHECK = 07 00\nMUS_REFILL = 08 00\nSE_OVER = 09 00\nPH_ONE = 0A 00\nPH_TWO = 0B 00\n"
}

@MainActor
private func runStrandedRegionChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/SongRegion::stranded"
    do {
        let fixture = try stageRegionFixture(fixtureRoot, name: "stranded", alias: true)
        _ = try SongRegistration.register(
            root: fixture.root, label: "mus_oldcheck",
            constant: "MUS_OLDCHECK", player: "MUSIC_PLAYER_BGM")
        _ = try SongRegistration.register(
            root: fixture.root, label: "se_oldcheck",
            constant: "SE_OLDCHECK", player: "MUSIC_PLAYER_SE1")
        try fixture.write("sound/song_table.inc", RegionJourneyImages.strandedTable)
        try fixture.write("include/constants/songs.h", RegionJourneyImages.strandedHeader)
        try fixture.write("charmap.txt", RegionJourneyImages.strandedCharmap)
        try fixture.write("src/debug.c", RegionJourneyImages.strandedDebug)
        let before = SongRegistration.status(
            root: fixture.root, label: "mus_straggler",
            constant: "MUS_STRAGGLER")
        report.expectEqual(
            expected: false, actual: before.inSongsH, cppID: id,
            what: "A055 straggler outside END_MUS is not registered before migration")
        report.expectEqual(
            expected: 8,
            actual: try SongRegistration.register(
                root: fixture.root,
                label: "mus_straggler", constant: "MUS_STRAGGLER", player: "MUSIC_PLAYER_BGM"),
            cppID: id, what: "A057 stranded song migrates into music slot eight")
        report.expectEqual(
            expected: Data(RegionJourneyImages.migratedTable.utf8),
            actual: try fixture.read("sound/song_table.inc"), cppID: id,
            what: "Migration moves the complete table row before phonemes")
        report.expectEqual(
            expected: Data(RegionJourneyImages.migratedHeader.utf8),
            actual: try fixture.read("include/constants/songs.h"), cppID: id,
            what: "Migration repairs all symbolic and numeric header IDs")
        report.expectEqual(
            expected: Data(RegionJourneyImages.migratedCharmap.utf8),
            actual: try fixture.read("charmap.txt"), cppID: id,
            what: "Migration repairs the complete charmap bytes")
        report.expectEqual(
            expected: Data(RegionJourneyImages.strandedDebug.utf8),
            actual: try fixture.read("src/debug.c"), cppID: id,
            what: "A058 migration preserves the original stranded debug image byte-for-byte")
        report.expectEqual(
            expected: fixture.linker, actual: try fixture.read("ld_script.ld"), cppID: id,
            what: "Migration preserves the untouched linker image")
        let after = SongRegistration.status(
            root: fixture.root, label: "mus_straggler",
            constant: "MUS_STRAGGLER")
        report.expectEqual(
            expected: [String](), actual: after.missingFiles, cppID: id,
            what: "A060 migrated straggler registration is complete")
        try SongRegistration.unregister(
            root: fixture.root, label: "mus_straggler",
            constant: "MUS_STRAGGLER")
        report.expectEqual(
            expected: false,
            actual: SongRegistration.status(
                root: fixture.root,
                label: "mus_straggler", constant: "MUS_STRAGGLER"
            ).inSongTable,
            cppID: id, what: "A061 migrated song removal unregisters its table entry")
        report.expectEqual(
            expected: Data(RegionJourneyImages.vacatedTable.utf8),
            actual: try fixture.read("sound/song_table.inc"), cppID: id,
            what: "Removing migrated song leaves reusable music slot eight")
        report.expectEqual(
            expected: Data(RegionJourneyImages.vacatedHeader.utf8),
            actual: try fixture.read("include/constants/songs.h"), cppID: id,
            what: "A062 removing migrated song restores END_MUS to MUS_OLDCHECK")
        report.expectEqual(
            expected: Data(RegionJourneyImages.vacatedCharmap.utf8),
            actual: try fixture.read("charmap.txt"), cppID: id,
            what: "Removing migrated song preserves phoneme IDs nine and ten")
        report.expectEqual(
            expected: Data(RegionJourneyImages.vacatedDebug.utf8),
            actual: try fixture.read("src/debug.c"), cppID: id,
            what: "Removing migrated song retains the original debug-list shape")
        report.expectEqual(
            expected: fixture.linker, actual: try fixture.read("ld_script.ld"), cppID: id,
            what: "Removing migrated song retains untouched linker bytes")
        report.expectEqual(
            expected: 8,
            actual: SongRegistration.plan(
                root: fixture.root,
                label: "mus_refill", constant: "MUS_REFILL", player: "MUSIC_PLAYER_BGM"
            ).songId,
            cppID: id, what: "A064 refill plan reuses vacated ID eight")
        report.expectEqual(
            expected: 8,
            actual: try SongRegistration.register(
                root: fixture.root,
                label: "mus_refill", constant: "MUS_REFILL", player: "MUSIC_PLAYER_BGM"),
            cppID: id, what: "A066 refill registration occupies ID eight")
        report.expectEqual(
            expected: Data(RegionJourneyImages.refillTable.utf8),
            actual: try fixture.read("sound/song_table.inc"), cppID: id,
            what: "Migrated refill restores a complete music table row")
        report.expectEqual(
            expected: Data(RegionJourneyImages.refillHeader.utf8),
            actual: try fixture.read("include/constants/songs.h"), cppID: id,
            what: "A067 migrated refill sits adjacent to symbolic END_MUS")
        report.expectEqual(
            expected: Data(RegionJourneyImages.refillCharmap.utf8),
            actual: try fixture.read("charmap.txt"), cppID: id,
            what: "Migrated refill repairs complete charmap image")
        report.expectEqual(
            expected: Data(RegionJourneyImages.refillDebug.utf8),
            actual: try fixture.read("src/debug.c"), cppID: id,
            what: "Migrated refill restores complete BGM debug image")
        report.expectEqual(
            expected: fixture.linker, actual: try fixture.read("ld_script.ld"), cppID: id,
            what: "Migrated refill leaves complete linker image unchanged")
    } catch { report.fail(id, "stranded migration scenario failed: \(error)") }
}

@MainActor
private func runOverflowRegionChecks(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/SongRegion::overflow"
    do {
        let fixture = try stageRegionFixture(fixtureRoot, name: "overflow", alias: true)
        _ = try SongRegistration.register(
            root: fixture.root, label: "mus_oldcheck",
            constant: "MUS_OLDCHECK", player: "MUSIC_PLAYER_BGM")
        _ = try SongRegistration.register(
            root: fixture.root, label: "se_oldcheck",
            constant: "SE_OLDCHECK", player: "MUSIC_PLAYER_SE1")
        report.expectEqual(
            expected: 8,
            actual: try SongRegistration.register(
                root: fixture.root,
                label: "mus_reuse_source", constant: "MUS_REUSE_SOURCE",
                player: "MUSIC_PLAYER_BGM"), cppID: id,
            what: "A070 reuse-source music registration occupies ID eight")
        report.expectEqual(
            expected: Data(RegionJourneyImages.reuseSourceTable.utf8),
            actual: try fixture.read("sound/song_table.inc"), cppID: id,
            what: "Reuse-source table has exact shifted phoneme rows")
        report.expectEqual(
            expected: Data(RegionJourneyImages.reuseSourceHeader.utf8),
            actual: try fixture.read("include/constants/songs.h"), cppID: id,
            what: "Reuse-source header repoints symbolic END_MUS")
        report.expectEqual(
            expected: Data(RegionJourneyImages.reuseSourceCharmap.utf8),
            actual: try fixture.read("charmap.txt"), cppID: id,
            what: "Reuse-source charmap shifts phoneme IDs")
        report.expectEqual(
            expected: Data(RegionJourneyImages.reuseSourceDebug.utf8),
            actual: try fixture.read("src/debug.c"), cppID: id,
            what: "Reuse-source debug entry belongs in the BGM list")
        report.expectEqual(
            expected: fixture.linker, actual: try fixture.read("ld_script.ld"), cppID: id,
            what: "Reuse-source does not alter linker image")
        try SongRegistration.unregister(
            root: fixture.root, label: "mus_reuse_source",
            constant: "MUS_REUSE_SOURCE")
        report.expectEqual(
            expected: Data(RegionJourneyImages.vacatedTable.utf8),
            actual: try fixture.read("sound/song_table.inc"), cppID: id,
            what: "A071 source removal leaves a music-region fallback slot")
        report.expectEqual(
            expected: Data(RegionJourneyImages.vacatedHeader.utf8),
            actual: try fixture.read("include/constants/songs.h"), cppID: id,
            what: "Source removal restores the symbolic marker")
        report.expectEqual(
            expected: Data(RegionJourneyImages.vacatedCharmap.utf8),
            actual: try fixture.read("charmap.txt"), cppID: id,
            what: "Source removal preserves all shifted charmap IDs")
        report.expectEqual(
            expected: Data(RegionJourneyImages.vacatedProductionDebug.utf8),
            actual: try fixture.read("src/debug.c"), cppID: id,
            what: "Source removal erases the retired debug entry")
        report.expectEqual(
            expected: fixture.linker, actual: try fixture.read("ld_script.ld"), cppID: id,
            what: "Source removal preserves linker bytes")
        report.expectEqual(
            expected: 8,
            actual: SongRegistration.plan(
                root: fixture.root,
                label: "mus_refill", constant: "MUS_REFILL", player: "MUSIC_PLAYER_BGM"
            ).songId,
            cppID: id, what: "A072 refill plan selects vacated ID eight")
        report.expectEqual(
            expected: 8,
            actual: try SongRegistration.register(
                root: fixture.root,
                label: "mus_refill", constant: "MUS_REFILL", player: "MUSIC_PLAYER_BGM"),
            cppID: id, what: "A074 refill registration reuses ID eight")
        report.expectEqual(
            expected: Data(RegionJourneyImages.refillTable.utf8),
            actual: try fixture.read("sound/song_table.inc"), cppID: id,
            what: "Refill writes exact table image")
        report.expectEqual(
            expected: Data(RegionJourneyImages.refillHeader.utf8),
            actual: try fixture.read("include/constants/songs.h"), cppID: id,
            what: "Refill keeps marker next to its referent")
        report.expectEqual(
            expected: Data(RegionJourneyImages.refillCharmap.utf8),
            actual: try fixture.read("charmap.txt"), cppID: id,
            what: "Refill retains exact charmap image")
        report.expectEqual(
            expected: Data(RegionJourneyImages.refillProductionDebug.utf8),
            actual: try fixture.read("src/debug.c"), cppID: id,
            what: "Refill adds its debug entry to SOUND_LIST_BGM")
        report.expectEqual(
            expected: fixture.linker, actual: try fixture.read("ld_script.ld"), cppID: id,
            what: "Refill does not alter linker bytes")
        report.expectEqual(
            expected: 4,
            actual: try SongRegistration.register(
                root: fixture.root,
                label: "se_extra", constant: "SE_EXTRA", player: "MUSIC_PLAYER_SE1"),
            cppID: id, what: "A076 remaining SE slot receives ID four")
        report.expectEqual(
            expected: Data(RegionJourneyImages.extraTable.utf8),
            actual: try fixture.read("sound/song_table.inc"), cppID: id,
            what: "Remaining SE slot retains every table row and player number")
        report.expectEqual(
            expected: Data(RegionJourneyImages.extraHeader.utf8),
            actual: try fixture.read("include/constants/songs.h"), cppID: id,
            what: "END_SE advances to SE_EXTRA without moving START_MUS")
        report.expectEqual(
            expected: Data(RegionJourneyImages.extraCharmap.utf8),
            actual: try fixture.read("charmap.txt"), cppID: id,
            what: "Remaining SE slot writes exact charmap image")
        report.expectEqual(
            expected: true, actual: try fixture.debugEntry("SE_EXTRA", inSe: true),
            cppID: id, what: "Remaining SE slot extends SOUND_LIST_SE only")
        report.expectEqual(
            expected: fixture.linker, actual: try fixture.read("ld_script.ld"), cppID: id,
            what: "Remaining SE slot leaves linker bytes unchanged")
        report.expectEqual(
            expected: 9,
            actual: try SongRegistration.register(
                root: fixture.root,
                label: "se_over", constant: "SE_OVER", player: "MUSIC_PLAYER_SE1"),
            cppID: id, what: "A078 overflowing SE allocates music ID nine")
        report.expectEqual(
            expected: Data(RegionJourneyImages.overflowTable.utf8),
            actual: try fixture.read("sound/song_table.inc"), cppID: id,
            what: "SE overflow inserts full row before phonemes with SE player one")
        report.expectEqual(
            expected: Data(RegionJourneyImages.overflowHeader.utf8),
            actual: try fixture.read("include/constants/songs.h"), cppID: id,
            what: "A082 SE overflow repoints END_MUS to SE_OVER at ID nine")
        report.expectEqual(
            expected: Data(RegionJourneyImages.overflowCharmap.utf8),
            actual: try fixture.read("charmap.txt"), cppID: id,
            what: "SE overflow updates the entire charmap and phoneme IDs")
        report.expectEqual(
            expected: true, actual: try fixture.debugEntry("SE_OVER", inSe: false),
            cppID: id, what: "A080 SE overflow appears before SOUND_LIST_SE in BGM")
        report.expectEqual(
            expected: fixture.linker, actual: try fixture.read("ld_script.ld"), cppID: id,
            what: "SE overflow preserves untouched linker image")
    } catch { report.fail(id, "region overflow scenario failed: \(error)") }
}
