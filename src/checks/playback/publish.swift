import Foundation
import PorydawApp
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

func checkControllerPublication(_ report: CheckReport) throws {
    try checkPublicationRequestContract(report)
    let rig = try AudioControllerCheckFixture()
    let audio = rig.renderer
    for target in [UInt64(1000), 2000, 3000] { audio.seek(target) }
    report.expectEqual(expected: UInt64(0), actual: audio.playheadSamples,
        cppID: "transportcheck/TransportTest::seekPublishesWithoutBlocking", what: "seek remains pending before callback")
    let replacement = rig.timeline(changed: true)
    audio.publish(replacement)
    _ = rig.render(1)
    report.expect(audio.timeline?.events == replacement.events && audio.playheadSamples == 3000,
        cppID: "transportcheck/TransportTest::updateTimelineCarriesPendingSeek", message: "replacement must carry latest seek")
    for _ in 0..<64 { audio.publish(rig.timeline()) }
    _ = rig.render(1)
    report.expectEqual(expected: UInt64(3000), actual: audio.playheadSamples,
        cppID: "transportcheck/TransportTest::timelineHandoffOwnership", what: "coalescing preserves current cursor and live publication")
    report.expect(audio.timeline?.events == rig.timeline().events,
        cppID: "transportcheck/TransportTest::timelineHandoffOwnership", message: "callback adopts newest coalesced timeline")
    audio.play()
    _ = rig.render(rig.settle + rig.ramp + 4096)
    audio.seek(12345)
    audio.stop()
    _ = rig.render(rig.settle + rig.ramp * 3)
    report.expectEqual(expected: UInt64(0), actual: audio.playheadSamples,
        cppID: "transportcheck/TransportTest::stopCancelsPendingSeek", what: "stop cancels pending seek")
}

private func checkPublicationRequestContract(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture(silent: true)
    let audio = rig.renderer
    let timeline = playbackCheckSilentTimeline()
    audio.bind(timeline: timeline, voicegroup: rig.voices, settings: AudioSettings())
    report.expect(audio.songLoaded, cppID: seekID, message: "original silent song loads")
    report.expectEqual(expected: 2, actual: timeline.usedTrackCount, cppID: seekID, what: "original two-track fixture")
    let midpoint = timeline.lengthSamples / 2
    let clock = ContinuousClock()
    for row in 0..<5 {
        let elapsed = clock.measure { audio.seek(row & 1 == 0 ? midpoint : 0) }
        report.expect(elapsed <= .milliseconds(20), cppID: seekID,
                      message: "seek row \(row) publishes within 20 ms")
    }
    _ = rig.render(1)
    report.expectEqual(expected: midpoint, actual: audio.playheadSamples, cppID: seekID, what: "callback applies latest seek")
    audio.seek(0)
    _ = rig.render(1)
    report.expectEqual(expected: UInt64(0), actual: audio.playheadSamples, cppID: seekID, what: "callback applies reset seek")

    let pendingReplacement = playbackCheckSilentTimeline(program: 1)
    audio.seek(midpoint)
    audio.publish(pendingReplacement)
    _ = rig.render(1)
    report.expect(audio.timeline?.events == pendingReplacement.events && audio.playheadSamples == midpoint,
                  cppID: updateSeekID, message: "distinct program replacement carries pending midpoint seek")

    audio.seek(0)
    audio.play()
    _ = rig.render(12_000)
    report.expect(audio.playheadSamples > 0, cppID: stopSeekID, message: "playback starts before stop cancellation")
    audio.seek(midpoint)
    audio.stop()
    _ = rig.render(rig.settle + rig.ramp * 3)
    report.expectEqual(expected: UInt64(0), actual: audio.playheadSamples, cppID: stopSeekID, what: "stop cancels midpoint seek")

    audio.bind(timeline: timeline, voicegroup: rig.voices, settings: AudioSettings())
    let liveReplacement = playbackCheckSilentTimeline(finalTick: 4700)
    audio.play()
    _ = rig.render(12_000)
    let before = audio.playheadSamples
    report.expect(before > 0, cppID: playbackCheckLiveReplacementID, message: "playback starts before live edit")
    let elapsed = clock.measure { audio.publish(liveReplacement) }
    report.expect(elapsed <= .milliseconds(20), cppID: playbackCheckLiveReplacementID,
                  message: "live replacement publishes within 20 ms")
    _ = rig.render(512)
    report.expect(audio.timeline?.events == liveReplacement.events && audio.playheadSamples > before,
                  cppID: playbackCheckLiveReplacementID, message: "callback adopts live event layout and advances")
    audio.stop()
    _ = rig.render(rig.settle + rig.ramp * 3)
    report.expectEqual(expected: UInt64(0), actual: audio.playheadSamples, cppID: playbackCheckLiveReplacementID,
                       what: "stop after live replacement resets cursor")
}


private let handoffID = "transportcheck/TransportTest::timelineHandoffOwnership"
private let seekID = "transportcheck/TransportTest::seekPublishesWithoutBlocking"
private let stopSeekID = "transportcheck/TransportTest::stopCancelsPendingSeek"
private let updateSeekID = "transportcheck/TransportTest::updateTimelineCarriesPendingSeek"
internal let playbackCheckLiveReplacementID =
    "transportcheck/TransportTest::liveTimelineReplacementDoesNotBlock"
func checkReplacementRows(original: PlaybackTimeline, replacement: PlaybackTimeline,
                                  report: CheckReport) -> Bool {
    guard let handoffEngine = PlaybackCheckEngine() else {
        report.fail(handoffID, "handoff engine initialization failed")
        return false
    }
    var handoff = Sequencer()
    renderPlaybackCheckFrames(&handoff, engine: handoffEngine.pointer, timeline: original, frames: 5_000)
    let handoffPosition = handoff.position
    handoff.replaceTimeline(handoffPosition, timeline: replacement)
    renderPlaybackCheckFrames(&handoff, engine: handoffEngine.pointer, timeline: replacement, frames: 4_000)
    report.expectEqual(expected: [UInt8(60), 67], actual: playbackCheckPcmKeys(handoffEngine.pointer), cppID: handoffID,
                       what: "replacement source keyed-on notes")

    var seek = Sequencer()
    seek.seek(12_000, timeline: original)
    report.expectEqual(expected: UInt64(12_000), actual: seek.position, cppID: seekID,
                       what: "published seek position")

    var stopped = Sequencer()
    stopped.seek(12_000, timeline: original)
    stopped.reset()
    report.expectEqual(expected: UInt64(0), actual: stopped.position, cppID: stopSeekID,
                       what: "reset position after pending seek")

    var carried = Sequencer()
    carried.seek(5_000, timeline: original)
    carried.replaceTimeline(carried.position, timeline: replacement)
    report.expectEqual(expected: UInt64(5_000), actual: carried.position, cppID: updateSeekID,
                       what: "replacement position after seek")

    guard let liveEngine = PlaybackCheckEngine() else {
        report.fail(playbackCheckLiveReplacementID, "live replacement engine initialization failed")
        return false
    }
    var live = Sequencer()
    renderPlaybackCheckFrames(&live, engine: liveEngine.pointer, timeline: original, frames: 5_000)
    live.replaceTimeline(live.position, timeline: replacement)
    renderPlaybackCheckFrames(&live, engine: liveEngine.pointer, timeline: replacement, frames: 4_000)
    report.expectEqual(expected: UInt64(9_000), actual: live.position, cppID: playbackCheckLiveReplacementID,
                       what: "position after live replacement")
    report.expectEqual(expected: [UInt8(60), 67], actual: playbackCheckPcmKeys(liveEngine.pointer),
                       cppID: playbackCheckLiveReplacementID, what: "live replacement keyed-on notes")

    return true
}
