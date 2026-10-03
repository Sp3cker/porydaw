import Foundation
import PorydawApp
import PorydawCore

func runMidiImportWizardLawChecks(_ report: CheckReport) {
    let id = "onboardcheck/OnboardingTest::importWizardLaw"
    for (input, expected) in [
        ("Cool Song.mid", "mus_cool_song"),
        ("se_door.mid", "se_door"),
        ("Mus_Theme.v2.mid", "mus_theme_v2"),
        ("__x__.mid", "mus_x"),
    ] {
        report.expectEqual(
            expected: expected, actual: MidiImport.suggestedSongLabel(sourceFileName: input),
            cppID: id, what: "suggested label for \(input)")
    }
    for (count, expected) in [(-1, 16), (1, 1), (40, 16)] {
        report.expectEqual(
            expected: expected, actual: MidiImport.trackLimit(playerTrackCount: count),
            cppID: id, what: "track limit for \(count)")
    }

    let source = MidiFile(
        division: 12,
        chunks: [
            MidiChunk(
                events: [
                    .channel(tick: TimeDefaults.maxTick, status: 0x90, data0: 60, data1: 90)
                ], endTick: TimeDefaults.maxTick)
        ])
    do {
        _ = try MidiImport.prepareImportedSong(source, rescale: true, extendedClocks: true)
        report.fail(id, "overflowing import unexpectedly succeeded")
    } catch {
        report.expectEqual(
            expected: MidiImportError.tickOverflow(newDivision: 48),
            actual: error as? MidiImportError, cppID: id, what: "extended clock overflow")
    }
    report.expectEqual(
        expected: UInt16(12), actual: source.division, cppID: id,
        what: "overflow source division remains unchanged")
    report.expectEqual(
        expected: TimeDefaults.maxTick, actual: source.chunks[0].events[0].tick,
        cppID: id, what: "overflow source note tick remains unchanged")

    guard let externalPath = CheckEnvironment.fixturePath("test_midis/external_import.mid"),
        let duplicatePath = CheckEnvironment.fixturePath("test_midis/duplicate_setters.mid")
    else {
        report.fail(id, "missing MIDI import fixtures")
        return
    }
    do {
        let external = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: externalPath))))
        let scaled = try MidiImport.prepareImportedSong(external, rescale: true, extendedClocks: false)
        let originalTiming = try MidiImport.prepareImportedSong(
            external, rescale: false,
            extendedClocks: false)
        let extended = try MidiImport.prepareImportedSong(external, rescale: true, extendedClocks: true)
        report.expectEqual(
            expected: UInt16(24), actual: scaled.division, cppID: id,
            what: "standard clock import division")
        report.expectEqual(
            expected: UInt16(400), actual: originalTiming.division, cppID: id,
            what: "unscaled import division")
        report.expectEqual(
            expected: UInt16(48), actual: extended.division, cppID: id,
            what: "extended clock import division")
        report.expectEqual(
            expected: UInt16(400), actual: external.division, cppID: id,
            what: "pipeline preserves source division")
        let full = ImportAnalysisSummary(
            analysis: MidiImport.analyze(external, trackBudget: 16),
            trackLimit: 16, wasFormat0: false)
        report.expectEqual(
            expected: "Porydaw will import all 2 tracks.", actual: full.summary,
            cppID: id, what: "full-capacity import summary")
        report.expectEqual(
            expected: "Porydaw can import this MIDI file.", actual: full.status,
            cppID: id, what: "full-capacity import status")
        report.expect(
            full.polyphony.hasPrefix("7 notes play at the same time"), cppID: id,
            message: "sample-polyphony warning explains observed peak")
        let limited = ImportAnalysisSummary(
            analysis: MidiImport.analyze(external, trackBudget: 1),
            trackLimit: 1, wasFormat0: false)
        report.expectEqual(
            expected: "Porydaw will import all 2 tracks, but the game will mute track 2.",
            actual: limited.summary, cppID: id, what: "limited-player import summary")
        report.expectEqual(
            expected: "", actual: limited.status, cppID: id,
            what: "limited-player status hidden")
        report.expect(
            limited.trackAction.contains("move track 2 above track 1"), cppID: id,
            message: "limited-player track reorder advice")

        let duplicate = try MidiFile.decode(Array(Data(contentsOf: URL(fileURLWithPath: duplicatePath))))
        var expected = duplicate
        report.expectEqual(
            expected: 8, actual: MidiImport.removeRedundantSetters(&expected),
            cppID: id, what: "fixture has eight redundant setters")
        let prepared = try MidiImport.prepareImportedSong(
            duplicate, rescale: false,
            extendedClocks: false)
        report.expectEqual(
            expected: expected, actual: prepared, cppID: id,
            what: "pipeline removes redundant setters before optional rescale")
        report.expectEqual(
            expected: duplicate.division, actual: prepared.division, cppID: id,
            what: "dedup-only pipeline retains original timing")
    } catch {
        report.fail(id, "MIDI import fixture pipeline failed: \(error)")
    }
}
