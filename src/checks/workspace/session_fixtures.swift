import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

internal let rejectedVoicegroupCases: [(name: String, label: String, argument: String?)] = [
    ("absolute", "mus_vgid_absolute", "/abs/perc.vg"),
    ("empty", "mus_vgid_empty", nil),
    ("nested-parent", "mus_vgid_nested_parent", "drums/../../escape.vg"),
    ("normalizes-to-root", "mus_vgid_normalizes_root", "drums/.."),
    ("parent-file", "mus_vgid_parent_file", "../escape.vg"),
    ("parent", "mus_vgid_parent", ".."),
    ("project-root", "mus_vgid_project_root", "."),
]

// MARK: - Synthetic Fixture Helpers

internal func makeMidiFixture(division: UInt16 = 24, bpmMicroseconds: UInt32 = 500_000,
                             loopStart: Tick? = 48, loopEnd: Tick? = 144) -> MidiFile {
    var conductorEvents: [MidiEvent] = [
        .meta(tick: 0, type: 0x51, data: [
            UInt8((bpmMicroseconds >> 16) & 0xFF),
            UInt8((bpmMicroseconds >> 8) & 0xFF),
            UInt8(bpmMicroseconds & 0xFF),
        ])
    ]
    if let loopStart {
        conductorEvents.append(.meta(tick: loopStart, type: 0x01, data: Array("[".utf8)))
    }
    if let loopEnd {
        conductorEvents.append(.meta(tick: loopEnd, type: 0x01, data: Array("]".utf8)))
    }
    let noteTrack = MidiChunk(events: [
        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
        .channel(tick: 25, status: 0x80, data0: 60),
        .channel(tick: 48, status: 0x90, data0: 64, data1: 100),
        .channel(tick: 61, status: 0x80, data0: 64),
        .channel(tick: 96, status: 0x90, data0: 67, data1: 100),
        .channel(tick: 144, status: 0x80, data0: 67),
    ], endTick: 192)
    return MidiFile(division: division, chunks: [
        MidiChunk(events: conductorEvents, endTick: 192),
        noteTrack,
    ])
}

internal func stageTestProject(in rootDirectory: String, projectName: String) -> String {
    let projectDir = URL(fileURLWithPath: rootDirectory).appendingPathComponent(projectName).path
    let soundDir = URL(fileURLWithPath: projectDir).appendingPathComponent("sound").path
    let songsDir = URL(fileURLWithPath: soundDir).appendingPathComponent("songs/midi").path
    let vgDir = URL(fileURLWithPath: soundDir).appendingPathComponent("voicegroups").path
    let incDir = URL(fileURLWithPath: projectDir).appendingPathComponent("include/constants").path
    let fm = FileManager.default

    try? fm.removeItem(atPath: projectDir)
    try! fm.createDirectory(atPath: songsDir, withIntermediateDirectories: true)
    try! fm.createDirectory(atPath: vgDir, withIntermediateDirectories: true)
    try! fm.createDirectory(atPath: incDir, withIntermediateDirectories: true)

    let rejectedSongRows = rejectedVoicegroupCases.map {
        "    song \($0.label), MUSIC_PLAYER_BGM, 0"
    }.joined(separator: "\n")
    let songTable = """
    .equiv MUSIC_PLAYER_BGM, 0
    .align 2
    gSongTable::
        song mus_session_test, MUSIC_PLAYER_BGM, 0
        song mus_session_test2, MUSIC_PLAYER_BGM, 0
    \(rejectedSongRows)
    """
    try! songTable.write(toFile: URL(fileURLWithPath: soundDir).appendingPathComponent("song_table.inc").path,
                         atomically: true, encoding: .utf8)

    let rejectedCfgRows = rejectedVoicegroupCases.map {
        let voicegroupFlag = $0.argument.map { "-G\($0) " } ?? ""
        return "\($0.label).mid: -R50 \(voicegroupFlag)-V100"
    }.joined(separator: "\n")
    let midiCfg = """
    mus_session_test.mid: -R50 -G_test_vg -V100
    mus_session_test2.mid: -R50 -G_test_vg -V100
    \(rejectedCfgRows)
    """
    try! midiCfg.write(toFile: URL(fileURLWithPath: songsDir).appendingPathComponent("midi.cfg").path,
                       atomically: true, encoding: .utf8)

    let voicegroup = """
    .align 2
    voice_group test_vg
        voice_square_1 60, 0, 2, 2, 2, 3, 12, 4
        voice_square_2 60, 0, 1, 3, 2, 11, 4
        voice_noise 60, 0, 1, 2, 2, 10, 3
    """
    try! voicegroup.write(toFile: URL(fileURLWithPath: vgDir).appendingPathComponent("test_vg.inc").path,
                          atomically: true, encoding: .utf8)

    let voicegroupHub = """
    .include "sound/voicegroups/test_vg.inc"
    """
    try! voicegroupHub.write(
        toFile: URL(fileURLWithPath: soundDir).appendingPathComponent("voice_groups.inc").path,
        atomically: true, encoding: .utf8)

    let rejectedDefines = rejectedVoicegroupCases.enumerated().map {
        "#define \($0.element.label.uppercased()) \($0.offset + 3)"
    }.joined(separator: "\n")
    let songsH = """
    #define MUS_SESSION_TEST 1
    #define MUS_SESSION_TEST2 2
    \(rejectedDefines)
    """
    try! songsH.write(toFile: URL(fileURLWithPath: incDir).appendingPathComponent("songs.h").path,
                      atomically: true, encoding: .utf8)

    let midi1 = makeMidiFixture()
    let midi1Bytes = try! midi1.encoded()
    try! Data(midi1Bytes).write(to: URL(fileURLWithPath: songsDir).appendingPathComponent("mus_session_test.mid"))
    for fixture in rejectedVoicegroupCases {
        try! Data(midi1Bytes).write(
            to: URL(fileURLWithPath: songsDir).appendingPathComponent("\(fixture.label).mid"))
    }

    let midi2 = makeMidiFixture(division: 24, bpmMicroseconds: 600_000)
    let midi2Bytes = try! midi2.encoded()
    try! Data(midi2Bytes).write(to: URL(fileURLWithPath: songsDir).appendingPathComponent("mus_session_test2.mid"))

    let legacyJson = """
    {"legacy": true, "author": "porydaw", "protected": true}
    """
    try! legacyJson.write(toFile: URL(fileURLWithPath: songsDir).appendingPathComponent("mus_session_test.mid.json").path,
                          atomically: true, encoding: .utf8)

    return projectDir
}
