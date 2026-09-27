import Foundation
import PorydawCore
import PorydawProject

internal func runSongsMkSuite(_ report: CheckReport) {
    let cppID = "swiftproject/SongsMkChecks::songsMkRoundTrip"
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("porydaw-songsmk-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let midiDir = root.appendingPathComponent("sound/songs/midi", isDirectory: true)
    let mkFile = SongsMk.path(root: root)
    let target = "mus_mkcheck"
    let other = "mus_other"
    let recipe = "\t$(MID) $< $@ -E -R$(STD_REVERB) -G_group -V080"
    let fixture = "STD_REVERB := 50 # comment\r\n"
        + "# Header with trailing spaces   \r\n"
        + "$(MID_SUBDIR)/\(target).s: %.s: %.mid\r\n"
        + recipe + "\r\n"
        + "\t@echo preparing\r\n"
        + "sound/songs/midi/\(other).s: %.s: %.mid\r\n"
        + "\t$(MID) $< $@ -V077\r\n"
        + "$(MID_SUBDIR)/mus.dotted.s: %.s: %.mid\r\n"
        + "\t$(MID) $< $@ -V061\r\n"
        + "sound/songs/midi/mus-dashed.s: %.s: %.mid\r\n"
        + "\t$(MID) $< $@ -V062\r\n"
    do {
        try FileManager.default.createDirectory(at: midiDir, withIntermediateDirectories: true)
        try Data(fixture.utf8).write(to: mkFile)

        let parsed = SongsMk.parseFlags(mkFile: mkFile)
        report.expectEqual(expected: ["-E", "-R50", "-G_group", "-V080"], actual: parsed[target], cppID: cppID,
                           what: "synthetic CRLF recipe variables expand into concrete option values")
        report.expect(parsed[target]?.allSatisfy { !$0.contains("$") } == true,
                      cppID: cppID, message: "synthetic CRLF options contain no variable references")
        report.expectEqual(expected: ["-V077"], actual: parsed[other], cppID: cppID,
                           what: "literal midi directory rule parses")
        report.expect(parsed["mus.dotted"] == nil && parsed["mus-dashed"] == nil,
                      cppID: cppID, message: "rule labels containing dots or dashes do not match")

        let before = try Data(contentsOf: mkFile)
        var cfg = SongFlags.fromRaw(parsed[target] ?? [])
        cfg.masterVolume = 111
        try MidiCfg.writeSongFlags(midiDir: midiDir, label: target, flags: SongFlags.merge(cfg))
        let after = try Data(contentsOf: mkFile)
        let oldLines = ProjectFileStore.splitLines(before).lines
        let newLines = ProjectFileStore.splitLines(after).lines
        report.expect(!FileManager.default.fileExists(atPath: midiDir.appendingPathComponent("midi.cfg").path),
                      cppID: cppID, message: "synthetic CRLF routing does not create midi.cfg")
        report.expectEqual(expected: oldLines.count, actual: newLines.count, cppID: cppID,
                           what: "synthetic CRLF flag replacement retains the line count")
        if oldLines.count == newLines.count {
            let changed = oldLines.indices.filter { oldLines[$0] != newLines[$0] }
            report.expectEqual(expected: [3], actual: changed, cppID: cppID,
                               what: "synthetic CRLF rewrite changes exactly one recipe line")
            if changed == [3] {
                let rewritten = String(decoding: newLines[3], as: UTF8.self)
                report.expect(rewritten.hasPrefix("\t$(MID) $< $@"), cppID: cppID,
                              message: "synthetic CRLF changed line retains the tabbed MID invocation")
                report.expect(rewritten.contains("-V111") && rewritten.contains("-R$(STD_REVERB)"),
                              cppID: cppID,
                              message: "volume rewrite retains unchanged variable spelling")
                report.expect(newLines[3].last == 13, cppID: cppID,
                              message: "target recipe keeps CRLF line ending")
            }
            report.expect(oldLines.indices.allSatisfy { $0 == 3 || oldLines[$0] == newLines[$0] },
                          cppID: cppID, message: "all non-target lines stay byte-identical")
        }

        // A spelling with different letter case still occupies the same option slot.
        let caseFlags = ["-E", "-r50", "-G_group", "-v111"]
        try SongsMk.writeRule(mkFile: mkFile, label: target, flags: caseFlags)
        report.expectEqual(expected: ["-E", "-R50", "-G_group", "-V111"],
                           actual: SongsMk.parseFlags(mkFile: mkFile)[target], cppID: cppID,
                           what: "case-insensitive value matching retains variable spelling")
        let caseLine = String(decoding: ProjectFileStore.splitLines(try Data(contentsOf: mkFile)).lines[3], as: UTF8.self)
        report.expect(caseLine.contains("-R$(STD_REVERB)") && !caseLine.contains("-R$(STD_REVERB) -r50"),
                      cppID: cppID, message: "case drift does not duplicate a flag letter")

        cfg.masterVolume = 99
        try SongsMk.writeRule(mkFile: mkFile, label: target, flags: SongFlags.merge(cfg))
        let reverbLine = String(decoding: ProjectFileStore.splitLines(try Data(contentsOf: mkFile)).lines[3], as: UTF8.self)
        report.expect(reverbLine.contains("-R$(STD_REVERB)") && reverbLine.contains("-V099"),
                      cppID: cppID, message: "synthetic CRLF variable spelling survives the -V099 rewrite")

        let appended = ["-E", "-R50", "-G_new", "-V100"]
        try SongsMk.writeRule(mkFile: mkFile, label: "mus_mkcheck_new", flags: appended)
        let appendedBytes = try Data(contentsOf: mkFile)
        report.expect(String(decoding: appendedBytes, as: UTF8.self)
                          .contains("\r\n\r\n$(MID_SUBDIR)/mus_mkcheck_new.s: %.s: %.mid\r\n\t$(MID)"),
                      cppID: cppID, message: "synthetic CRLF rule appends with blank separator and tabbed recipe")
        report.expectEqual(expected: appended, actual: SongsMk.parseFlags(mkFile: mkFile)["mus_mkcheck_new"],
                           cppID: cppID, what: "synthetic CRLF appended rule parses back to written options")

        let noRecipe = "$(MID_SUBDIR)/mus_recipe_less.s: %.s: %.mid\r\n\t@echo build\r\n"
        try Data(noRecipe.utf8).write(to: mkFile)
        try SongsMk.writeRule(mkFile: mkFile, label: "mus_recipe_less", flags: ["-V090"])
        report.expectEqual(expected: ["-V090"], actual: SongsMk.parseFlags(mkFile: mkFile)["mus_recipe_less"],
                           cppID: cppID, what: "existing rule without MID recipe receives one")
        let updatedNoRecipe = String(decoding: try Data(contentsOf: mkFile), as: UTF8.self)
        report.expect(updatedNoRecipe.contains("\r\n\t$(MID) $< $@ -V090\r\n\t@echo build\r\n"),
                      cppID: cppID, message: "inserted recipe precedes existing commands without changing them")
    } catch {
        report.fail(cppID, "songs.mk fixture operation failed: \(error)")
    }

    do {
        try withTempProjectCopy(prefix: "projectstore-songsmk", stagedFile: "sound/song_table.inc") { copy in
            let copiedMidiDir = copy.appendingPathComponent("sound/songs/midi", isDirectory: true)
            let copiedCfg = copiedMidiDir.appendingPathComponent("midi.cfg")
            let copiedMk = SongsMk.path(root: copy)
            try FileManager.default.removeItem(at: copiedCfg)
            let original = """
                MID_SUBDIR := sound/songs/midi
                MID := $(MID2AGB)
                STD_REVERB = 50
                GYM_VOICEGROUP = _fixture_rich
                # Retain this neighboring comment.

                $(MID_SUBDIR)/mus_gym.s: %.s: %.mid
                \t$(MID) $< $@ -E -R45 -G$(GYM_VOICEGROUP) -V080

                $(MID_SUBDIR)/mus_oldale.s: %.s: %.mid
                \t$(MID) $< $@ -E -R$(STD_REVERB) -G_fixture_rich -V090

                """
            let expected111 = """
                MID_SUBDIR := sound/songs/midi
                MID := $(MID2AGB)
                STD_REVERB = 50
                GYM_VOICEGROUP = _fixture_rich
                # Retain this neighboring comment.

                $(MID_SUBDIR)/mus_gym.s: %.s: %.mid
                \t$(MID) $< $@ -E -R45 -G$(GYM_VOICEGROUP) -V111

                $(MID_SUBDIR)/mus_oldale.s: %.s: %.mid
                \t$(MID) $< $@ -E -R$(STD_REVERB) -G_fixture_rich -V090

                """
            let expected99 = """
                MID_SUBDIR := sound/songs/midi
                MID := $(MID2AGB)
                STD_REVERB = 50
                GYM_VOICEGROUP = _fixture_rich
                # Retain this neighboring comment.

                $(MID_SUBDIR)/mus_gym.s: %.s: %.mid
                \t$(MID) $< $@ -E -R45 -G$(GYM_VOICEGROUP) -V111

                $(MID_SUBDIR)/mus_oldale.s: %.s: %.mid
                \t$(MID) $< $@ -E -R$(STD_REVERB) -G_fixture_rich -V099

                """
            try Data(original.utf8).write(to: copiedMk)
            let opened = awaitValue { try await ProjectStore(projectRoot: copy).open() }
            guard case .success(let first) = opened,
                  let gym = first.songs.first(where: { $0.label == "mus_gym" }),
                  let oldale = first.songs.first(where: { $0.label == "mus_oldale" }) else {
                report.fail(cppID, "copied mk-only project setup cannot open its registered songs")
                return
            }
            report.expect(gym.hasCfg, cppID: cppID,
                          message: "A005: copied gym recipe supplies a song configuration")
            report.expect(!gym.cfg.voicegroupArgument.isEmpty, cppID: cppID,
                          message: "A006: copied gym recipe supplies a nonempty voicegroup")
            report.expect(!gym.cfg.rawFlags.contains(where: { $0.contains("$") }), cppID: cppID,
                          message: "A007: copied gym options have no unexpanded variable references")
            report.expectEqual(expected: ["-E", "-R45", "-G_fixture_rich", "-V080"],
                               actual: gym.cfg.rawFlags, cppID: cppID,
                               what: "copied gym recipe loads exactly the concrete fork options")
            report.expect(oldale.hasCfg, cppID: cppID,
                          message: "copied oldale variable-reverb recipe supplies a song configuration")
            report.expectEqual(expected: ["-E", "-R50", "-G_fixture_rich", "-V090"],
                               actual: oldale.cfg.rawFlags, cppID: cppID,
                               what: "copied oldale variable-reverb recipe loads expanded options")

            let before111 = try Data(contentsOf: copiedMk)
            var changedGym = gym.cfg
            changedGym.masterVolume = 111
            try MidiCfg.writeSongFlags(midiDir: copiedMidiDir, label: gym.label,
                                       flags: SongFlags.merge(changedGym))
            let after111 = try Data(contentsOf: copiedMk)
            report.expectEqual(expected: Data(expected111.utf8), actual: after111,
                               cppID: cppID, what: "A008: volume 111 write produces the complete expected recipe image")
            let beforeLines = ProjectFileStore.splitLines(before111).lines
            let afterLines = ProjectFileStore.splitLines(after111).lines
            report.expectEqual(expected: beforeLines.count, actual: afterLines.count, cppID: cppID,
                               what: "A010: copied project volume rewrite retains the line count")
            report.expect(beforeLines.indices.contains(7) && afterLines.indices.contains(7)
                              && beforeLines[7] != afterLines[7] && afterLines[6] == beforeLines[6]
                              && String(decoding: afterLines[6], as: UTF8.self).contains("/mus_gym.s"),
                          cppID: cppID, message: "A012: changed gym recipe directly follows its retained target rule")
            report.expect(afterLines.indices.contains(7)
                              && String(decoding: afterLines[7], as: UTF8.self).contains("$(MID)"),
                          cppID: cppID, message: "A013: changed gym recipe retains the MID invocation")
            let changedRecipeLines = zip(beforeLines, afterLines).enumerated()
                .compactMap { index, pair in pair.0 == pair.1 ? nil : index }
            report.expectEqual(expected: [7], actual: changedRecipeLines, cppID: cppID,
                               what: "A014: copied project changes exactly the gym recipe line")
            report.expect(!FileManager.default.fileExists(atPath: copiedCfg.path), cppID: cppID,
                          message: "A009: copied mk-only settings write never creates midi.cfg")
            let reopened111 = awaitValue { try await ProjectStore(projectRoot: copy).open() }
            if case .success(let snapshot) = reopened111 {
                report.expect(snapshot.isOpen && snapshot.root == copy.path, cppID: cppID,
                              message: "A015: reopened project publishes the copied mk-only root")
                let song = snapshot.songs.first(where: { $0.label == gym.label })
                report.expect(song?.hasCfg == true, cppID: cppID,
                              message: "A016: reopened project contains the configured gym song")
                report.expectEqual(expected: 111, actual: song?.cfg.masterVolume, cppID: cppID,
                                   what: "A017: reopened gym volume is 111")
                report.expectEqual(expected: "_fixture_rich", actual: song?.cfg.voicegroupArgument, cppID: cppID,
                                   what: "A018: reopened gym voicegroup remains fixture rich")
                report.expectEqual(expected: 45, actual: song?.cfg.reverb, cppID: cppID,
                                   what: "A019: reopened gym reverb remains 45")
            } else {
                report.fail(cppID, "copied mk-only project cannot reopen after volume 111 write")
            }

            var changedOldale = oldale.cfg
            changedOldale.masterVolume = 99
            try MidiCfg.writeSongFlags(midiDir: copiedMidiDir, label: oldale.label,
                                       flags: SongFlags.merge(changedOldale))
            let after99 = try Data(contentsOf: copiedMk)
            report.expectEqual(expected: Data(expected99.utf8), actual: after99,
                               cppID: cppID, what: "A024: volume 99 write produces the complete expected recipe image")
            report.expect(String(decoding: after99, as: UTF8.self)
                              .contains("\t$(MID) $< $@ -E -R$(STD_REVERB) -G_fixture_rich -V099\n"),
                          cppID: cppID, message: "A025: volume 99 retains the unchanged STD_REVERB spelling")
            let reopened99 = awaitValue { try await ProjectStore(projectRoot: copy).open() }
            if case .success(let snapshot) = reopened99,
               let song = snapshot.songs.first(where: { $0.label == oldale.label }) {
                report.expectEqual(expected: 99, actual: song.cfg.masterVolume, cppID: cppID,
                                   what: "reopened oldale volume remains 99")
                report.expectEqual(expected: "_fixture_rich", actual: song.cfg.voicegroupArgument, cppID: cppID,
                                   what: "reopened oldale voicegroup remains fixture rich")
                report.expectEqual(expected: 50, actual: song.cfg.reverb, cppID: cppID,
                                   what: "reopened oldale reverb remains 50")
            } else {
                report.fail(cppID, "reopened oldale is missing after volume 99 write")
            }

            let newLabel = "mus_mkcheck_new"
            let newFlags = ["-E", "-R50", "-G_fixture_rich", "-V100"]
            try MidiCfg.writeSongFlags(midiDir: copiedMidiDir, label: newLabel, flags: newFlags)
            let expectedAppend = """
                MID_SUBDIR := sound/songs/midi
                MID := $(MID2AGB)
                STD_REVERB = 50
                GYM_VOICEGROUP = _fixture_rich
                # Retain this neighboring comment.

                $(MID_SUBDIR)/mus_gym.s: %.s: %.mid
                \t$(MID) $< $@ -E -R45 -G$(GYM_VOICEGROUP) -V111

                $(MID_SUBDIR)/mus_oldale.s: %.s: %.mid
                \t$(MID) $< $@ -E -R$(STD_REVERB) -G_fixture_rich -V099

                $(MID_SUBDIR)/mus_mkcheck_new.s: %.s: %.mid
                \t$(MID) $< $@ -E -R50 -G_fixture_rich -V100

                """
            let restored = """
                MID_SUBDIR := sound/songs/midi
                MID := $(MID2AGB)
                STD_REVERB = 50
                GYM_VOICEGROUP = _fixture_rich
                # Retain this neighboring comment.

                $(MID_SUBDIR)/mus_gym.s: %.s: %.mid
                \t$(MID) $< $@ -E -R45 -G$(GYM_VOICEGROUP) -V111

                $(MID_SUBDIR)/mus_oldale.s: %.s: %.mid
                \t$(MID) $< $@ -E -R$(STD_REVERB) -G_fixture_rich -V099

                """
            report.expectEqual(expected: Data(expectedAppend.utf8), actual: try Data(contentsOf: copiedMk),
                               cppID: cppID, what: "A030: append preserves the original file and adds the exact rule")
            report.expectEqual(expected: newFlags, actual: SongsMk.parseFlags(mkFile: copiedMk)[newLabel],
                               cppID: cppID, what: "A031: appended rule reads back its exact flags")
            let appendedOpen = awaitValue { try await ProjectStore(projectRoot: copy).open() }
            if case .success(let snapshot) = appendedOpen {
                report.expectEqual(expected: 111,
                                   actual: snapshot.songs.first(where: { $0.label == "mus_gym" })?.cfg.masterVolume,
                                   cppID: cppID, what: "reopened gym volume remains 111 after rule append")
                report.expectEqual(expected: 99,
                                   actual: snapshot.songs.first(where: { $0.label == "mus_oldale" })?.cfg.masterVolume,
                                   cppID: cppID, what: "reopened oldale volume remains 99 after rule append")
            } else {
                report.fail(cppID, "project cannot reopen after rule append")
            }
            try SongRegistration.removeFlags(root: copy.path, label: newLabel)
            let afterRemoval = try Data(contentsOf: copiedMk)
            report.expect(afterRemoval != Data(expectedAppend.utf8), cppID: cppID,
                          message: "A032: removal changes the file containing the appended rule")
            report.expect(SongsMk.parseFlags(mkFile: copiedMk)[newLabel] == nil, cppID: cppID,
                          message: "A033: removed rule no longer parses")
            report.expectEqual(expected: Data(restored.utf8), actual: afterRemoval,
                               cppID: cppID, what: "A034: removing appended rule restores the complete original image")
            let removedOpen = awaitValue { try await ProjectStore(projectRoot: copy).open() }
            if case .success(let snapshot) = removedOpen {
                report.expectEqual(expected: 111,
                                   actual: snapshot.songs.first(where: { $0.label == "mus_gym" })?.cfg.masterVolume,
                                   cppID: cppID, what: "reopened gym volume remains 111 after rule removal")
                report.expectEqual(expected: 99,
                                   actual: snapshot.songs.first(where: { $0.label == "mus_oldale" })?.cfg.masterVolume,
                                   cppID: cppID, what: "reopened oldale volume remains 99 after rule removal")
            } else {
                report.fail(cppID, "project cannot reopen after rule removal")
            }
            try SongRegistration.removeFlags(root: copy.path, label: newLabel)
            let afterSecondRemoval = SongsMk.parseFlags(mkFile: copiedMk)
            report.expect(afterSecondRemoval[newLabel] == nil
                              && afterSecondRemoval["mus_gym"] == ["-E", "-R45", "-G_fixture_rich", "-V111"]
                              && afterSecondRemoval["mus_oldale"] == ["-E", "-R50", "-G_fixture_rich", "-V099"],
                          cppID: cppID, message: "A035: repeated removal retains only the original song flags")
            report.expectEqual(expected: Data(restored.utf8), actual: try Data(contentsOf: copiedMk),
                               cppID: cppID, what: "A036: repeated removal leaves the complete original image")
            report.expect(!FileManager.default.fileExists(atPath: copiedCfg.path), cppID: cppID,
                          message: "append and removal never create midi.cfg")
        }
    } catch {
        report.fail(cppID, "copied songs.mk project operation failed")
    }

    let missing = SongsMk.path(root: root.appendingPathComponent("missing"))
    report.expect(SongsMk.parseFlags(mkFile: missing).isEmpty, cppID: cppID,
                  message: "missing songs.mk parses as an empty map")
    do {
        try SongsMk.writeRule(mkFile: missing, label: "missing", flags: ["-V100"])
        report.fail(cppID, "writing missing songs.mk unexpectedly succeeded")
    } catch {
        report.expect(!FileManager.default.fileExists(atPath: missing.path), cppID: cppID,
                      message: "missing songs.mk throws instead of creating a file")
    }
}

