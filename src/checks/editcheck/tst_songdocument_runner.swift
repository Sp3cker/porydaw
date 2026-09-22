import Foundation
import PorydawCore

internal struct CoreEditCorpusSong {
    let label: String
    let midiPath: String
    let midiBytes: [UInt8]
    let config: SongConfig

    var source: SongSource { SongSource(label: label, midiPath: midiPath, hasConfig: true) }
}

@MainActor
internal func coreEditCorpusSongs(_ report: CheckReport) throws -> [CoreEditCorpusSong] {
    guard let root = CheckEnvironment.fixtureRoot, !root.isEmpty else {
        report.fail("editcheck/EditCheckTest::initTestCase", "missing staged project root")
        return []
    }
    let directory = URL(fileURLWithPath: root).appendingPathComponent("sound/songs/midi")
    let filenames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        .filter { $0.hasSuffix(".mid") }.sorted()
    report.expect(!filenames.isEmpty, cppID: "editcheck/EditCheckTest::initTestCase",
                  message: "edit corpus has playable songs")
    let configText = try String(contentsOf: directory.appendingPathComponent("midi.cfg"),
                                encoding: .utf8)
    var songs: [CoreEditCorpusSong] = []
    for filename in filenames {
        let rows = configText.split(separator: "\n").filter { $0.hasPrefix(filename + ":") }
        guard rows.count == 1 else {
            report.fail("editcheck/EditCheckTest::initTestCase", "expected one fixture config for \(filename)")
            return []
        }
        let flags = rows[0].dropFirst(filename.count + 1).split(whereSeparator: \.isWhitespace).map(String.init)
        // All checked-in corpus rows use this exact flag shape. Reject fixture
        // drift instead of silently interpreting unrelated production flags.
        guard flags.count == 4, flags[0] == "-E", flags[1] == "-R50",
              flags[2].hasPrefix("-G"), flags[2].count > 2, flags[3] == "-V100" else {
            report.fail("editcheck/EditCheckTest::initTestCase", "fixture flags changed for \(filename): \(flags)")
            return []
        }
        let midiURL = directory.appendingPathComponent(filename)
        let loaded = CoreEditCorpusSong(
            label: String(filename.dropLast(4)), midiPath: midiURL.path,
            midiBytes: Array(try Data(contentsOf: midiURL)),
            config: SongConfig(rawFlags: flags, voicegroupArgument: String(flags[2].dropFirst(2)),
                               masterVolume: 100, reverb: 50, exactGate: true))
        songs.append(loaded)
    }
    return songs
}

@MainActor
internal func coreEditDistantBase(_ document: SongDocument) -> Tick {
    let clocksPerBeat = 24 * (document.state.config.extendedClocks ? 2 : 1)
    let ticksPerClock = max(1, document.ticksPerBeat / clocksPerBeat)
    return (document.rawChunks.map(\.endTick).max() ?? 0) + Tick(ticksPerClock * 100)
}

@MainActor
internal func coreEditHistoryCountAtTip(_ document: SongDocument, report: CheckReport,
                                      cppID: String) throws -> Int {
    let restoredState = document.state
    let restoredIdentity = document.history.currentIdentity
    var count = 0
    while document.history.undoDocument() { count += 1 }
    var replayed = 0
    while document.history.redoDocument() { replayed += 1 }
    report.expect(count == replayed && document.state == restoredState &&
        document.history.currentIdentity == restoredIdentity, cppID: cppID,
        message: "counting public undo entries restores the exact state and identity")
    return count
}
