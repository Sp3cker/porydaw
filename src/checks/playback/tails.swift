import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

func checkAuditionTailTransitions(_ report: CheckReport) throws {
    for scenario in 0..<4 {
        let names = ["playFromStoppedCutsAuditionTail", "pauseSilencesPlayingPreview",
                     "spacePathSeekAndPlayCutsTail", "resumeCutsCountingDownPreview"]
        let id = "transportcheck/TransportTest::\(names[scenario])"
        let rig = try AudioControllerCheckFixture(square: true, silent: true)
        for program in 0..<128 { rig.voices[program].release = 254 }
        let audio = rig.renderer
        let timeline = playbackCheckSilentTimeline()
        audio.bind(timeline: timeline, voicegroup: rig.voices, settings: AudioSettings())
        report.expectEqual(2, timeline.usedTrackCount, cppID: id, what: "both audition tracks initialized")
        report.expect(audio.songLoaded, cppID: id, message: "silent song loaded")
        if scenario != 0 {
            audio.play()
            _ = rig.render(rig.rate / 4)
            report.expect(audio.playheadSamples > 0, cppID: id, message: "playback started")
            if scenario != 1 {
                audio.pause()
                _ = rig.render(rig.rate * 3 / 10)
            }
        }
        let tail = scenario == 0 || scenario == 2
        audio.audition.previewNoteTimed(track: scenario == 3 ? 1 : 0,
            key: scenario == 3 ? 64 : 60, velocity: 127,
            durationSamples: UInt32(tail ? rig.rate * 15 / 100 : rig.rate * 60))
        _ = rig.render(512)
        report.expect(audio.activePcmChannels >= 1, cppID: id,
                      message: "timed preview sounds before transition")
        if tail {
            _ = rig.render(rig.rate * 4 / 10)
            report.expect(audio.polySnapshot().pcm.contains { $0.on && $0.releasing },
                cppID: id, message: "expired preview has a live release tail")
        }
        if scenario == 1 {
            audio.pause()
        } else {
            if scenario == 2 { audio.seek(0) }
            audio.play()
        }
        _ = rig.render(rig.rate * 2)
        report.expectEqual(0, audio.activePcmChannels, cppID: id,
                          what: "transition cuts preview and release tail within two seconds")
    }
    try checkUnloadedVoicegroupLifetime(report)
}

func checkUnloadPlayingSong(_ rig: AudioControllerCheckFixture, _ report: CheckReport) {
    let audio = rig.renderer
    report.expect(audio.activePcmChannels >= 1,
        cppID: "transportcheck/TransportTest::unloadWhilePlayingCutsSongVoices",
        message: "song voice sounds before unload")
    audio.unload()
    _ = rig.render(8192)
    report.expect(audio.activePcmChannels == 0 && audio.activeCgbChannels == 0 && !audio.songLoaded,
        cppID: "transportcheck/TransportTest::unloadWhilePlayingCutsSongVoices", message: "unload retires voices before bank release")
}

private func checkUnloadedVoicegroupLifetime(_ report: CheckReport) throws {
    let id = "transportcheck/TransportTest::unloadWhilePlayingCutsSongVoices"
    var bank: AudioControllerCheckFixture? = try AudioControllerCheckFixture(square: true)
    let audio = bank!.renderer
    report.expect(audio.songLoaded, cppID: id, message: "heap-bank note song loaded")
    report.expectEqual(1, audio.timeline!.usedTrackCount, cppID: id, what: "one song track")
    audio.play()
    _ = bank!.render(12_000)
    report.expect(audio.activePcmChannels >= 1, cppID: id, message: "heap-bank note sounds")
    audio.unload()
    report.expectEqual(0, audio.activePcmChannels, cppID: id, what: "unload immediately retires song voices")
    bank = nil
    var output = [Float](repeating: 0, count: 1024)
    for _ in 0..<29 {
        output.withUnsafeMutableBufferPointer { audio.render($0.baseAddress!, frames: 512) }
    }
    report.expectEqual(0, audio.activePcmChannels, cppID: id,
                      what: "callbacks remain voiceless after heap-bank destruction")
}
