import PorydawCore
import PorydawProject

internal func runSongModelSuite(_ report: CheckReport) {
    let parseID = "swiftproject/SongModelChecks::parsesRawFlags"
    let raw = ["-Lfoo", "-G_first", "-vabc", "-G_final", "-R", "-Pbad", "-e", "-X", "-N", "-Zunknown", "-v080"]
    let parsed = SongFlags.fromRaw(raw)
    report.expectEqual(expected: raw, actual: parsed.rawFlags, cppID: parseID,
                       what: "raw flags retain spelling, order, and duplicates")
    report.expectEqual(expected: "_final", actual: parsed.voicegroupArgument, cppID: parseID,
                       what: "last voicegroup flag wins")
    report.expectEqual(expected: 80, actual: parsed.masterVolume, cppID: parseID,
                       what: "case-insensitive volume overrides invalid volume")
    report.expectEqual(expected: 0, actual: parsed.reverb, cppID: parseID,
                       what: "empty reverb argument clamps to zero")
    report.expectEqual(expected: 0, actual: parsed.priority, cppID: parseID,
                       what: "invalid priority parses as zero")
    report.expect(parsed.exactGate && parsed.extendedClocks && parsed.noCompression,
                  cppID: parseID, message: "known boolean letters parse case-insensitively")
    report.expectEqual(expected: 0, actual: SongFlags.fromRaw(["-Vabc"]).masterVolume, cppID: parseID,
                       what: "invalid volume clamps to zero")
    report.expect(SongFlags.fromRaw(["-V080"]).reverb == nil, cppID: parseID,
                  message: "absent reverb remains nil")
    report.expectEqual(expected: "", actual: SongFlags.fromRaw(["-V080"]).voicegroupArgument,
                       cppID: parseID, what: "absent voicegroup does not insert a flag")

    let mergeID = "swiftproject/SongModelChecks::mergesFlags"
    let stable = ["-E", "-R50", "-G_abandoned_ship", "-V080"]
    report.expectEqual(expected: stable, actual: SongFlags.merge(SongFlags.fromRaw(stable)), cppID: mergeID,
                       what: "known flags round-trip in original order")
    let unknown = ["-Lfoo", "-E", "-Zother", "-R50", "-V080"]
    report.expectEqual(expected: unknown, actual: SongFlags.merge(SongFlags.fromRaw(unknown)), cppID: mergeID,
                       what: "unknown flags retain their positions on merge")
    report.expectEqual(expected: ["-V080"], actual: SongFlags.merge(SongFlags.fromRaw(["-v080"])),
                       cppID: mergeID, what: "lowercase match is replaced in place with uppercase")

    var changed = SongFlags.fromRaw(["-R50", "-G_old", "-V080", "-Lfoo", "-P3", "-E"])
    changed.reverb = nil
    changed.voicegroupArgument = ""
    changed.masterVolume = 5
    changed.priority = 0
    changed.exactGate = false
    report.expectEqual(expected: ["-V005", "-Lfoo"], actual: SongFlags.merge(changed), cppID: mergeID,
                       what: "nil reverb, empty voicegroup and absent values remove flags; volume is padded")
    report.expectEqual(expected: ["-V005"], actual: SongFlags.merge(SongConfig(voicegroupArgument: "", masterVolume: 5)),
                       cppID: mergeID, what: "missing volume is appended with three digits")
}
