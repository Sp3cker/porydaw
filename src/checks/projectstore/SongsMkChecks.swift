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

        report.expectEqual(expected: mkFile, actual: root.appendingPathComponent("songs.mk"), cppID: cppID,
                           what: "path appends songs.mk to the root")
        let parsed = SongsMk.parseFlags(mkFile: mkFile)
        report.expectEqual(expected: ["-E", "-R50", "-G_group", "-V080"], actual: parsed[target], cppID: cppID,
                           what: "A007: recipe variables expand into concrete option values")
        report.expect(parsed[target]?.allSatisfy { !$0.contains("$") } == true,
                      cppID: cppID, message: "A007: expanded options contain no variable references")
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
                      cppID: cppID, message: "A009: routing does not create midi.cfg")
        report.expectEqual(expected: oldLines.count, actual: newLines.count, cppID: cppID,
                           what: "A010: replacing flags retains the line count")
        if oldLines.count == newLines.count {
            let changed = oldLines.indices.filter { oldLines[$0] != newLines[$0] }
            report.expectEqual(expected: [3], actual: changed, cppID: cppID,
                               what: "A014: exactly one recipe line changes")
            if changed == [3] {
                let rewritten = String(decoding: newLines[3], as: UTF8.self)
                report.expect(changed[0] > 0, cppID: cppID,
                              message: "A011: changed recipe follows a rule")
                report.expect(String(decoding: oldLines[2], as: UTF8.self).contains("/\(target).s"),
                              cppID: cppID, message: "A012: changed recipe directly follows target rule")
                report.expect(rewritten.hasPrefix("\t$(MID) $< $@"), cppID: cppID,
                              message: "A013: changed line retains the tabbed MID invocation")
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
                      cppID: cppID, message: "A025: variable spelling survives the -V099 rewrite")

        let appended = ["-E", "-R50", "-G_new", "-V100"]
        try SongsMk.writeRule(mkFile: mkFile, label: "mus_mkcheck_new", flags: appended)
        let appendedBytes = try Data(contentsOf: mkFile)
        report.expect(String(decoding: appendedBytes, as: UTF8.self)
                          .contains("\r\n\r\n$(MID_SUBDIR)/mus_mkcheck_new.s: %.s: %.mid\r\n\t$(MID)"),
                      cppID: cppID, message: "A030: new rule appends with blank CRLF separator and tabbed recipe")
        report.expectEqual(expected: appended, actual: SongsMk.parseFlags(mkFile: mkFile)["mus_mkcheck_new"],
                           cppID: cppID, what: "A031: appended rule parses back to the written options")

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

