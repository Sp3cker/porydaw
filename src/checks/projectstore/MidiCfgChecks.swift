import Foundation
import PorydawProject

internal func runMidiCfgSuite(_ report: CheckReport) {
    midiCfgParsing(report)
    midiCfgByteConservation(report)
    midiCfgCreationAndRouting(report)
}

private func midiCfgParsing(_ report: CheckReport) {
    let cppID = "swiftproject/MidiCfgChecks::parse"
    let bytes = Data(" # ignored\r\n  mus_one.MID : -V080 -R50 # old\r\n"
        .appending("mus_one.mid: -E  -V099\r\ninvalid line\r\nother.mid: -V005\r\n").utf8)
    let parsed = MidiCfg.parse(bytes)
    report.expectEqual(2, parsed.count, cppID: cppID,
                       what: "comments and lines without a colon do not create entries")
    report.expectEqual(["-E", "-V099"], parsed["mus_one"]?.rawFlags, cppID: cppID,
                       what: "last duplicate label wins after case-insensitive .mid removal")
    report.expectEqual(99, parsed["mus_one"]?.masterVolume, cppID: cppID,
                       what: "flags after a comment cut are parsed")
    report.expectEqual(5, parsed["other"]?.masterVolume, cppID: cppID,
                       what: "other song flags remain available")
}

private func midiCfgByteConservation(_ report: CheckReport) {
    let cppID = "swiftproject/MidiCfgChecks::byteConservation"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "midicfg-bytes-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("midi.cfg")
        var original = Data("# untouched\r\nmus_other.mid: -V090\r\nmus_target.mid:   -V080\r\n".utf8)
        original.append(contentsOf: [0xFF, 0x3A, 0x20, 0x78, 0x0D, 0x0A])
        try original.write(to: path)
        try MidiCfg.writeMidiCfgLine(midiDir: root, label: "mus_target", flags: ["-E", "-V111"])
        let changed = try Data(contentsOf: path)
        let before = ProjectFileStore.splitLines(original)
        let after = ProjectFileStore.splitLines(changed)
        // proof.save.txt A013/A014: direct writer round-trip; no SongDocument/undo scaffolding.
        report.expectEqual(before.lines.count, after.lines.count, cppID: cppID,
                           what: "A013: rewriting one song retains the line count")
        if before.lines.count == after.lines.count {
            for index in before.lines.indices where index != 2 {
                report.expectEqual(before.lines[index], after.lines[index], cppID: cppID,
                                   what: "A014: other line \(index) retains every byte")
            }
            report.expectEqual(Data("mus_target.mid:   -E -V111\r".utf8), after.lines[2],
                               cppID: cppID, what: "target retains name padding and CRLF")
        }
        report.expect(after.endsWithNewline && after.crlf, cppID: cppID,
                      message: "trailing newline and CRLF remain intact")

        try MidiCfg.writeMidiCfgLine(midiDir: root, label: "mus_added", flags: ["-V005"])
        let appended = ProjectFileStore.splitLines(try Data(contentsOf: path))
        report.expectEqual(Data("mus_added.mid: -V005\r".utf8), appended.lines.last,
                           cppID: cppID, what: "new line follows the file's CRLF style")
    } catch {
        report.expect(false, cppID: cppID, message: "fixture or write failed: \(error)")
    }
}

private func midiCfgCreationAndRouting(_ report: CheckReport) {
    let cppID = "swiftproject/MidiCfgChecks::creationAndRouting"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "midicfg-routing-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let midiDir = root.appendingPathComponent("sound", isDirectory: true)
        .appendingPathComponent("songs", isDirectory: true)
        .appendingPathComponent("midi", isDirectory: true)
    let cfgFile = midiDir.appendingPathComponent("midi.cfg")
    do {
        try FileManager.default.createDirectory(at: midiDir, withIntermediateDirectories: true)
        try MidiCfg.writeSongFlags(midiDir: midiDir, label: "mus_fresh", flags: ["-E", "-V100"])
        report.expectEqual(Data("mus_fresh.mid: -E -V100\n".utf8), try Data(contentsOf: cfgFile),
                           cppID: cppID, what: "missing backends create midi.cfg with flags")

        let mkFile = root.appendingPathComponent("songs.mk")
        let mkBefore = Data("$(MID_SUBDIR)/mus_other.s: %.s: %.mid\n\t$(MID) $< $@ -V080\n"
            .appending("$(MID_SUBDIR)/mus_target.s: %.s: %.mid\n\t$(MID) $< $@ -V080\n").utf8)
        try mkBefore.write(to: mkFile)
        try MidiCfg.writeSongFlags(midiDir: midiDir, label: "mus_fresh", flags: ["-V110"])
        report.expectEqual(Data("mus_fresh.mid: -V110\n".utf8), try Data(contentsOf: cfgFile),
                           cppID: cppID, what: "existing midi.cfg takes precedence over songs.mk")
        report.expectEqual(mkBefore, try Data(contentsOf: mkFile), cppID: cppID,
                           what: "midi.cfg route leaves songs.mk unchanged")

        try FileManager.default.removeItem(at: cfgFile)
        try MidiCfg.writeSongFlags(midiDir: midiDir, label: "mus_target", flags: ["-V099"])
        let mkAfter = try Data(contentsOf: mkFile)
        report.expect(!FileManager.default.fileExists(atPath: cfgFile.path), cppID: cppID,
                      message: "songs.mk route does not create midi.cfg")
        report.expectEqual(Data("$(MID_SUBDIR)/mus_other.s: %.s: %.mid\n\t$(MID) $< $@ -V080\n"
            .appending("$(MID_SUBDIR)/mus_target.s: %.s: %.mid\n\t$(MID) $< $@ -V099\n").utf8),
            mkAfter, cppID: cppID, what: "existing songs.mk recipe receives the new flags")
    } catch {
        report.expect(false, cppID: cppID, message: "fixture or route failed: \(error)")
    }
}
