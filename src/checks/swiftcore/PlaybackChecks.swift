import Foundation
import PorydawCore
import PorydawPlayback
import PorydawPlaybackNative

/// Frozen oracle identities used by the controller-wired `swiftcore:playback`
/// slot. Every comparison failure must include the corresponding value.
public enum PlaybackBaselineID {
    public static let invalidEngineValues =
        "smfcheck/MidiSmfTest::{programChangesRejectOutOfRangeValues,noteOnsRejectOutOfRangeKeys}"
    public static let exactSamples =
        "smfcheck/MidiSmfTest::tempoConversionSchedulesExactSamples"
    public static let mapping =
        "smfcheck/MidiSmfTest::engineTrackMappingAgreesAcrossProjections/document-and-timeline assertions"
    public static let identities =
        "noteidcheck/NoteIdentityCheckTest::timelineTransportsOnlyStampedNoteIds"
    public static let loopPoints =
        "loopcheck/LoopTest::synthesizedLoopSongHasExactLoopPoints"
    public static let loopRender =
        "loopcheck/LoopTest::loopWrapMatchesHardwareGoto[rows=pass-1-tied-note-sounds,pass-2-gate-carry-holds-across-wrap,gate-carry-releases-at-written-duration,pass-2-tied-note-stacks,pass-3-tied-note-stacks,loop-boundary-notes-play-without-looping]"
    public static let prime =
        "primecheck/PrimeTest::{unprimedTrackAuditionIsSilent,primeVoicesApplyTrackPrograms[rows=chase-applied-voice-not-overridden,later-voice-primed-at-load,voiceless-track-never-primed],primedTrackAuditionIsAudible,midSongChaseSuppliesAllPrograms}"
    public static let controllerDefaults =
        "no-row/core/timedefaults.h exhaustive functions"
    public static let replacement =
        "transportcheck/TransportTest::{timelineHandoffOwnership,seekPublishesWithoutBlocking,stopCancelsPendingSeek,updateTimelineCarriesPendingSeek,liveTimelineReplacementDoesNotBlock,rebuildKeepsSoundingCgbSongNote,rebuildKeepsCgbNotePreview}"
    public static let transportTransitions =
        "transportcheck/TransportTest::{playFromStoppedCutsAuditionTail,pauseSilencesPlayingPreview,spacePathSeekAndPlayCutsTail,resumeCutsCountingDownPreview,unloadWhilePlayingCutsSongVoices,songStartEntersAtUnityGain,pausePreservesSuppressorAdaptation,stopLeaksNoDelayedSuppressorAudio,restartProducesAudioWithSuppression,secondSongStartDoesNotReuseResumeFade,resumeParksSequencerThroughSettle,pendingCutRetargetsOntoPlaying,coldReplacementLeaksNoPriorSongAudio}"
    public static let trackActivity =
        "trackactivitycheck/TrackActivityTest::{freshActivityIsDark,attackRetainsStereoTargets[all named rows],releaseIsGradualAndMonotonic,imperceptibleTailSnapsToZero,retriggerRetainsInertia,resetClearsEveryLight,pausedFillSettlesEveryTrack,resumeUsesFastWindowThenOrdinaryRelease,rapidPauseRearmsFastDescent,clampedElapsedNeedsTicksWithoutMovement}"
    public static let exports =
        "exportcheck-{loop,tail}/MidiExportTest::{durationCalculationMatchesRenderParity,offlineExportProducesValidRiffPcm,resonanceSuppressionChangesPcmWithoutChangingFrames,cancelledExportRemovesPartialFile}"
}

/// Projects a fixture through production Swift. The return value is the required
/// event count; -1 means decode/projection failed. A sizing call may pass a null
/// event buffer. The scalar data view deliberately owns no pointers: checks copy
/// events separately and production publication ownership stays in PlaybackBridge.
@_cdecl("pdc_playback_project_file")
public func pdcPlaybackProjectFile(
    _ path: UnsafePointer<CChar>?, _ sampleRate: Double,
    _ exactGate: Bool, _ extendedClocks: Bool,
    _ events: UnsafeMutablePointer<PdPlaybackEvent>?, _ eventCapacity: Int,
    _ data: UnsafeMutablePointer<PdPlaybackData>?,
    _ errorOut: UnsafeMutablePointer<CChar>?, _ errorCapacity: Int
) -> Int64 {
    clearPlaybackCheckError(errorOut, capacity: errorCapacity)
    do {
        let timeline = try loadPlaybackCheckTimeline(
            path: path, sampleRate: sampleRate,
            settings: PlaybackSettings(exactGate: exactGate,
                                       extendedClocks: extendedClocks))
        if let events, eventCapacity > 0 {
            let count = min(eventCapacity, timeline.events.count)
            for index in 0..<count {
                let event = timeline.events[index]
                events[index] = PdPlaybackEvent(
                    sample: event.sample, tick: event.tick, type: event.type,
                    track: event.track, data0: event.data0, data1: event.data1,
                    noteID: event.noteID.rawValue)
            }
        }
        if let data {
            data.pointee = PdPlaybackData(
                events: nil, eventCount: timeline.events.count,
                tempoMap: nil, tempoPointCount: timeline.tempoMap.count,
                sampleRate: timeline.sampleRate, lengthSamples: timeline.lengthSamples,
                loopStartSample: timeline.loopStartSample,
                loopEndSample: timeline.loopEndSample,
                ticksPerBeat: timeline.ticksPerBeat, lengthTicks: timeline.lengthTicks,
                loopStartTick: timeline.loopStartTick, loopEndTick: timeline.loopEndTick,
                usedTrackCount: UInt32(timeline.usedTrackCount),
                droppedTracks: UInt32(timeline.droppedTracks),
                exactGate: timeline.settings.exactGate,
                extendedClocks: timeline.settings.extendedClocks,
                ownerContext: nil)
        }
        return Int64(timeline.events.count)
    } catch {
        writePlaybackCheckError(String(describing: error), to: errorOut, capacity: errorCapacity)
        return -1
    }
}

/// Renders through production `Sequencer` and the caller's real poryaaaa engine.
/// When replacementPath is non-null, the replacement is installed at the exact
/// current position after replacementFrame frames. This is the mid-position
/// replacement path used by the retained transport oracle. Choosing a frame
/// count beyond loopEndSample exercises a real loop crossing in one call.
@_cdecl("pdc_playback_render_files")
public func pdcPlaybackRenderFiles(
    _ path: UnsafePointer<CChar>?, _ replacementPath: UnsafePointer<CChar>?,
    _ sampleRate: Double, _ exactGate: Bool, _ extendedClocks: Bool,
    _ engine: UnsafeMutablePointer<M4AEngine>?,
    _ left: UnsafeMutablePointer<Float>?, _ right: UnsafeMutablePointer<Float>?,
    _ frames: Int, _ replacementFrame: Int,
    _ looping: Bool, _ muteMask: UInt32, _ chase: Bool, _ prime: Bool,
    _ errorOut: UnsafeMutablePointer<CChar>?, _ errorCapacity: Int
) -> Bool {
    clearPlaybackCheckError(errorOut, capacity: errorCapacity)
    guard let engine, let left, let right, frames >= 0,
          replacementFrame >= 0, replacementFrame <= frames else {
        writePlaybackCheckError("invalid playback check arguments", to: errorOut,
                                capacity: errorCapacity)
        return false
    }

    do {
        let settings = PlaybackSettings(exactGate: exactGate,
                                        extendedClocks: extendedClocks)
        let timeline = try loadPlaybackCheckTimeline(path: path, sampleRate: sampleRate,
                                                     settings: settings)
        let replacement = try replacementPath.map {
            try loadPlaybackCheckTimeline(path: $0, sampleRate: sampleRate, settings: settings)
        }
        var sequencer = Sequencer()
        if chase { Sequencer.chase(engine: engine, timeline: timeline, position: 0) }
        if prime { Sequencer.primeVoices(engine: engine, timeline: timeline, position: 0) }

        let firstFrames = replacement == nil ? frames : replacementFrame
        if firstFrames > 0 {
            sequencer.render(
                engine: engine, timeline: timeline,
                left: UnsafeMutableBufferPointer(start: left, count: firstFrames),
                right: UnsafeMutableBufferPointer(start: right, count: firstFrames),
                looping: looping, muteMask: muteMask)
        }
        if let replacement {
            let currentPosition = sequencer.position
            sequencer.replaceTimeline(currentPosition, timeline: replacement)
            if chase {
                Sequencer.chase(engine: engine, timeline: replacement,
                                position: currentPosition)
            }
            if prime {
                Sequencer.primeVoices(engine: engine, timeline: replacement,
                                      position: currentPosition)
            }
            let remaining = frames - firstFrames
            if remaining > 0 {
                sequencer.render(
                    engine: engine, timeline: replacement,
                    left: UnsafeMutableBufferPointer(
                        start: left.advanced(by: firstFrames), count: remaining),
                    right: UnsafeMutableBufferPointer(
                        start: right.advanced(by: firstFrames), count: remaining),
                    looping: looping, muteMask: muteMask)
            }
        }
        return true
    } catch {
        writePlaybackCheckError(String(describing: error), to: errorOut, capacity: errorCapacity)
        return false
    }
}

/// Applies production chase/prime without rendering so the C++ oracle can
/// compare track programs and audition PCM on the same real engine fixture.
@_cdecl("pdc_playback_prepare_file")
public func pdcPlaybackPrepareFile(
    _ path: UnsafePointer<CChar>?, _ sampleRate: Double,
    _ exactGate: Bool, _ extendedClocks: Bool,
    _ engine: UnsafeMutablePointer<M4AEngine>?, _ position: UInt64,
    _ chase: Bool, _ prime: Bool,
    _ errorOut: UnsafeMutablePointer<CChar>?, _ errorCapacity: Int
) -> Bool {
    clearPlaybackCheckError(errorOut, capacity: errorCapacity)
    guard let engine else {
        writePlaybackCheckError("missing playback engine", to: errorOut, capacity: errorCapacity)
        return false
    }
    do {
        let timeline = try loadPlaybackCheckTimeline(
            path: path, sampleRate: sampleRate,
            settings: PlaybackSettings(exactGate: exactGate,
                                       extendedClocks: extendedClocks))
        if chase { Sequencer.chase(engine: engine, timeline: timeline, position: position) }
        if prime { Sequencer.primeVoices(engine: engine, timeline: timeline, position: position) }
        return true
    } catch {
        writePlaybackCheckError(String(describing: error), to: errorOut, capacity: errorCapacity)
        return false
    }
}

/// Native-publication counterpart to `pdc_playback_prepare_file`. The
/// controller-default matrix drives the same engine through both functions:
/// first with a non-default controller event, then with a rebuilt fixture that
/// omits it (which must restore `TimeDefaults`), and separately with a real
/// pre-seek event (which must override the default).
@_cdecl("pdc_playback_prepare_file_native")
public func pdcPlaybackPrepareFileNative(
    _ path: UnsafePointer<CChar>?, _ sampleRate: Double,
    _ engine: UnsafeMutablePointer<M4AEngine>?, _ position: UInt64,
    _ chase: Bool, _ prime: Bool,
    _ errorOut: UnsafeMutablePointer<CChar>?, _ errorCapacity: Int
) -> Bool {
    clearPlaybackCheckError(errorOut, capacity: errorCapacity)
    guard let engine else {
        writePlaybackCheckError("missing playback engine", to: errorOut, capacity: errorCapacity)
        return false
    }

    var data: UnsafeMutablePointer<PdPlaybackData>?
    guard pdPlaybackDataLoadFile(path, sampleRate, &data, errorOut, errorCapacity),
          let data else {
        return false
    }
    defer { pdPlaybackDataRelease(data) }
    if chase { pdPlayerChase(engine, data, position) }
    if prime { pdPlayerPrime(engine, data, position) }
    return true
}

private enum PlaybackCheckError: Error, CustomStringConvertible {
    case missingPath

    var description: String { "missing playback fixture path" }
}

private func loadPlaybackCheckTimeline(path: UnsafePointer<CChar>?, sampleRate: Double,
                                       settings: PlaybackSettings) throws -> PlaybackTimeline {
    guard let path else { throw PlaybackCheckError.missingPath }
    let bytes = try Data(contentsOf: URL(fileURLWithPath: String(cString: path)))
    let file = try MidiFile.decode(Array(bytes))
    return PlaybackTimeline.build(file: file, sampleRate: sampleRate, settings: settings)
}

private func clearPlaybackCheckError(_ output: UnsafeMutablePointer<CChar>?, capacity: Int) {
    guard let output, capacity > 0 else { return }
    output[0] = 0
}

private func writePlaybackCheckError(_ text: String, to output: UnsafeMutablePointer<CChar>?,
                                     capacity: Int) {
    guard let output, capacity > 0 else { return }
    let bytes = Array(text.utf8)
    let count = min(bytes.count, capacity - 1)
    for index in 0..<count { output[index] = CChar(bitPattern: bytes[index]) }
    output[count] = 0
}
