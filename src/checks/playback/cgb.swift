import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

func checkControllerCgbPublication(_ report: CheckReport) throws {
    for preview in [false, true] {
        let cgbRig = try AudioControllerCheckFixture(cgb: true)
        let original = cgbPublicationTimeline()
        cgbRig.renderer.bind(timeline: original, voicegroup: cgbRig.voices, settings: AudioSettings())
        if preview { cgbRig.renderer.audition.previewNote(track: 0, key: 60, velocity: 127) }
        else { cgbRig.renderer.play() }
        _ = cgbRig.render(12000)
        let id = preview ? "transportcheck/TransportTest::rebuildKeepsCgbNotePreview" :
            "transportcheck/TransportTest::rebuildKeepsSoundingCgbSongNote"
        report.expect(cgbRig.renderer.songLoaded, cppID: id, message: "original CGB note song loaded")
        report.expectEqual(1, original.usedTrackCount, cppID: id, what: "one original CGB song track")
        report.expect(cgbRig.sustaining(60), cppID: id, message: "CGB fixture must sound before replacement")
        report.expect(cgbRig.renderer.activeCgbChannels >= 1, cppID: id,
                      message: "CGB channel count confirms sounding precondition")
        let next = cgbPublicationTimeline(replacement: true, preview: preview)
        cgbRig.renderer.publish(next)
        _ = cgbRig.render(512)
        report.expect(cgbRig.renderer.timeline?.events == next.events && cgbRig.sustaining(60), cppID: id,
            message: "replacement chase must not replay destructive historical controls")
        report.expect(cgbRig.renderer.activeCgbChannels >= 1, cppID: id,
                      message: "adoption preserves active CGB channel")
        if preview {
            cgbRig.renderer.audition.previewNote(track: 0, key: 60, velocity: 0)
            _ = cgbRig.render(512)
            report.expect(!cgbRig.sustaining(60), cppID: id, message: "explicit preview release ends sustain")
        } else {
            cgbRig.renderer.stop()
            _ = cgbRig.render(cgbRig.settle + cgbRig.ramp * 3)
            report.expectEqual(UInt64(0), cgbRig.renderer.playheadSamples, cppID: id,
                              what: "stop after CGB replacement resets cursor")
        }
    }
}

private func cgbPublicationTimeline(replacement: Bool = false, preview: Bool = false) -> PlaybackTimeline {
    var events: [MidiEvent] = [.channel(tick: 0, status: 0xC0, data0: 2)]
    if replacement { events.append(.channel(tick: 0, status: 0xB0, data0: 0x78, data1: 0)) }
    events.append(.channel(tick: 0, status: 0x90, data0: 60, data1: 127))
    events.append(.channel(tick: replacement ? (preview ? 4600 : 4700) : 4800,
                           status: 0x80, data0: 60))
    return PlaybackTimeline.build(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 4800),
        MidiChunk(events: events, endTick: 4800),
    ]), sampleRate: playbackCheckSampleRate)
}

private let cgbSongReplacementID =
    "transportcheck/TransportTest::rebuildKeepsSoundingCgbSongNote"
private let cgbPreviewReplacementID =
    "transportcheck/TransportTest::rebuildKeepsCgbNotePreview"

func checkCgbReplacementRows(_ report: CheckReport) {
    let cgbOriginal = PlaybackTimeline.build(
        file: playbackCheckReplacementSong(replacement: false, program: 2), sampleRate: playbackCheckSampleRate)
    let cgbReplacement = PlaybackTimeline.build(
        file: playbackCheckReplacementSong(replacement: true, program: 2), sampleRate: playbackCheckSampleRate)
    guard let cgbSongEngine = PlaybackCheckEngine() else {
        report.fail(cgbSongReplacementID, "CGB song engine initialization failed")
        return
    }
    var cgbSong = Sequencer()
    renderPlaybackCheckFrames(&cgbSong, engine: cgbSongEngine.pointer, timeline: cgbOriginal, frames: 1)
    cgbSong.replaceTimeline(cgbSong.position, timeline: cgbReplacement)
    report.expectEqual([UInt8(60)], playbackCheckCgbKeys(cgbSongEngine.pointer),
                       cppID: cgbSongReplacementID,
                       what: "sounding CGB song notes after replacement")

    guard let cgbPreviewEngine = PlaybackCheckEngine() else {
        report.fail(cgbPreviewReplacementID, "CGB preview engine initialization failed")
        return
    }
    Sequencer.chase(engine: cgbPreviewEngine.pointer, timeline: cgbOriginal, position: 0)
    m4a_engine_note_on(cgbPreviewEngine.pointer, 0, 60, 127)
    var cgbPreview = Sequencer()
    cgbPreview.replaceTimeline(0, timeline: cgbReplacement)
    report.expectEqual([UInt8(60)], playbackCheckCgbKeys(cgbPreviewEngine.pointer),
                       cppID: cgbPreviewReplacementID,
                       what: "CGB preview notes after replacement")
    m4a_engine_note_off(cgbPreviewEngine.pointer, 0, 60)
    report.expectEqual([UInt8](), playbackCheckCgbKeys(cgbPreviewEngine.pointer),
                       cppID: cgbPreviewReplacementID, what: "released CGB preview notes")
}
