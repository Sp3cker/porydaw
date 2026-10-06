import Foundation
import PorydawApp
@testable import PorydawAppAudio
import PorydawCore
import PorydawDocument
import PorydawPlayback
import PorydawPlaybackNative
import PorydawProject

@MainActor
func runAudioControllerChecks(_ report: CheckReport) {
    do {
        checkTimelineReclamationSafety(report)
        try checkControllerReclamation(report)
        try checkControllerCuts(report)
        try checkAuditionTailTransitions(report)
        try checkControllerPublication(report)
        try checkControllerCgbPublication(report)
        try checkControllerSuppression(report)
        try checkControllerControls(report)
        try checkControllerTailMatrix(report)
        try checkControllerSettingsAndBank(report)
        try checkControllerPreviewIsolation(report)
        try checkControllerPitchBendAudio(report)
        try checkNativeAudioLifetime(report)
    } catch { report.fail("swiftcore/AudioController", "controller initialization failed: \(error)") }
}

private func recyclingTimelineFile(_ identity: UInt8) -> MidiFile {
    MidiFile(
        division: 24,
        chunks: [
            MidiChunk(
                events: [
                    .meta(type: 0x51, data: [0x07, 0xA1, 0x20]),
                    .meta(type: 0x58, data: [identity + 3, 2]),
                    .meta(type: 0x06, data: [0x5B]),
                    .meta(tick: 72, type: 0x06, data: [0x5D]),
                ], endTick: 72),
            MidiChunk(
                events: [
                    .meta(type: 0x03, data: Array("Voice \(identity)".utf8)),
                    .channel(status: 0xC0, data0: identity),
                    .channel(
                        tick: 24, status: 0x90, data0: 60 + identity, data1: 100, noteID: NoteID(UInt64(identity))),
                    .channel(tick: 48, status: 0x80, data0: 60 + identity),
                    .meta(tick: 72, type: 0x05, data: Array("lyric \(identity)".utf8)),
                ], endTick: 72),
        ])
}

private func checkTimelineReclamationSafety(_ report: CheckReport) {
    let id = "no-row/audio/timelineReclamationSafety"
    var builder = PlaybackTimelineBuilder()
    let retained = builder.build(file: recyclingTimelineFile(1), sampleRate: 1000)
    let handoff = AudioTimelineHandoff()
    handoff.reset(retained)
    var reclaimed: [NoteID] = []
    func publish(_ identity: UInt8) {
        let timeline = builder.build(file: recyclingTimelineFile(identity), sampleRate: 1000)
        handoff.publish(timeline) { old in
            guard let note = old.events.first(where: { $0.type == 0x9 }) else {
                report.fail(id, "reclaimed populated timeline lost its note identity")
                return
            }
            reclaimed.append(note.noteID)
            builder.recycle(old)
        }
    }

    publish(2)
    report.expect(reclaimed.isEmpty, cppID: id, message: "advertised initial snapshot is not reclaimed")
    publish(3)
    report.expectEqual(
        expected: [NoteID(2)], actual: reclaimed, cppID: id,
        what: "only replaced never-acquired pending output is returned")
    report.expect(
        handoff.active?.pointee.events.first { $0.type == 0x9 }?.noteID == NoteID(1)
            && handoff.active?.pointee.tracks[0].name == "Voice 1",
        cppID: id, message: "rapid pending replacement preserves the initially advertised snapshot")
    guard let acquired = handoff.acquirePending() else {
        report.fail(id, "latest pending timeline was not acquired")
        return
    }
    report.expect(
        acquired.pointee.events.first { $0.type == 0x9 }?.noteID == NoteID(3)
            && acquired.pointee.tracks[0].name == "Voice 3",
        cppID: id, message: "acquisition adopts the latest complete timeline")
    report.expectEqual(
        expected: [NoteID(2)], actual: reclaimed, cppID: id,
        what: "callback acquisition does not invoke producer reclamation")
    publish(4)
    publish(5)
    report.expectEqual(
        expected: [NoteID(2), NoteID(1), NoteID(4)], actual: reclaimed, cppID: id,
        what: "acknowledged older retired and replaced pending outputs are reclaimed once")
    report.expect(
        handoff.active == acquired && acquired.pointee.events.first { $0.type == 0x9 }?.sample == 500
            && acquired.pointee.events.first { $0.type == 0x9 }?.noteID == NoteID(3)
            && acquired.pointee.tracks[0].firstProgram == 3,
        cppID: id, message: "advertised acquired output remains readable through rapid publications")
    _ = handoff.acquirePending()
    publish(6)
    report.expectEqual(
        expected: [NoteID(2), NoteID(1), NoteID(4), NoteID(3)], actual: reclaimed, cppID: id,
        what: "previous acquired output is returned only after a later acquisition")

    let replacement = builder.build(
        file: recyclingTimelineFile(7),
        tempo: [TempoPoint(tick: 0, microsecondsPerQuarterNote: 750_000)],
        sampleRate: 2000, settings: PlaybackSettings(exactGate: true, extendedClocks: true))
    report.expect(
        retained.events.first { $0.type == 0x9 }?.noteID == NoteID(1)
            && retained.events.first { $0.type == 0x9 }?.sample == 500
            && retained.tracks[0].name == "Voice 1" && retained.tracks[0].noteCount == 1
            && retained.tempoMap[0].microsecondsPerQuarterNote == 500_000
            && retained.timeSignatures[0].numerator == 4
            && retained.otherEvents.last?.label == "Lyric: lyric 1"
            && retained.loopEndSample == 1500,
        cppID: id, message: "external retained output remains immutable after its storage is offered for reuse")
    report.expect(
        replacement.events.first { $0.type == 0x9 }?.sample == 1500
            && replacement.events.first { $0.type == 0x9 }?.noteID == NoteID(7)
            && replacement.tracks[0].name == "Voice 7" && replacement.tracks[0].firstProgram == 7
            && replacement.timeSignatures[0].numerator == 10
            && replacement.otherEvents.last?.label == "Lyric: lyric 7"
            && replacement.otherEvents.last?.sample == 4500
            && replacement.tempoMap[0].microsecondsPerQuarterNote == 750_000
            && replacement.loopEndSample == 4500,
        cppID: id, message: "recycled arrays are completely refilled with new samples, identities and metadata")
    builder.recycle(replacement)
    let empty = builder.build(file: MidiFile(division: 48, chunks: []), sampleRate: 4000)
    report.expect(
        empty.events.count == 1 && empty.events[0].type == playbackTempoEventType
            && empty.tracks.allSatisfy { !$0.used && $0.name.isEmpty && $0.noteCount == 0 && $0.firstProgram == -1 }
            && empty.tempoMap.count == 1 && empty.timeSignatures.isEmpty && empty.otherEvents.isEmpty
            && empty.lengthSamples == 0 && empty.lengthTicks == 0 && !empty.hasLoop
            && empty.ticksPerBeat == 48 && empty.sampleRate == 4000
            && empty.loopStartTick == TimeDefaults.noTick && empty.loopEndTick == TimeDefaults.noTick
            && empty.usedTrackCount == 0 && empty.droppedTracks == 0 && empty.settings == PlaybackSettings(),
        cppID: id, message: "empty input clears every reclaimed output's prior semantics")
    report.expect(
        replacement.events.first { $0.type == 0x9 }?.noteID == NoteID(7)
            && replacement.events.first { $0.type == 0x9 }?.sample == 1500
            && replacement.tracks[0].name == "Voice 7"
            && replacement.tempoMap[0].microsecondsPerQuarterNote == 750_000
            && replacement.timeSignatures[0].numerator == 10
            && replacement.otherEvents.last?.sample == 4500,
        cppID: id, message: "retained recycled output survives a subsequent empty build with different timing")
    handoff.reset(empty)
    report.expect(
        handoff.acquirePending() == nil && handoff.active?.pointee.events == empty.events,
        cppID: id,
        message: "quiescent reset releases both pending and retired ownership and installs only its initial value")
    handoff.reset()
    handoff.reset()
    report.expect(
        handoff.active == nil && handoff.acquirePending() == nil,
        cppID: id, message: "repeated quiescent reset leaves no advertised or pending timeline")
    handoff.reset(retained)
    publish(2)
    _ = handoff.acquirePending()
    publish(3)
    report.expect(
        handoff.active?.pointee.tracks[0].name == "Voice 2",
        cppID: id, message: "publishing after reset preserves the newly acquired timeline")
}

private func checkControllerReclamation(_ report: CheckReport) throws {
    let id = "no-row/audio/controllerReclamation"
    let rig = try AudioControllerCheckFixture()
    var reclaimed: [NoteID] = []
    func publish(_ identity: UInt8) {
        let timeline = PlaybackTimeline.build(file: recyclingTimelineFile(identity), sampleRate: Double(rig.rate))
        rig.renderer.publish(timeline) { old in
            if let note = old.events.first(where: { $0.type == 0x9 }) { reclaimed.append(note.noteID) }
        }
    }
    publish(1)
    publish(2)
    report.expectEqual(
        expected: [NoteID(1)], actual: reclaimed, cppID: id,
        what: "render facade synchronously forwards replaced pending output")
    _ = rig.render(1)
    report.expect(
        reclaimed == [NoteID(1)] && rig.renderer.timeline?.tracks[0].name == "Voice 2",
        cppID: id, message: "render adopts latest output without calling reclaim")
    publish(3)
    rig.renderer.unload()
    report.expect(
        !rig.renderer.songLoaded && rig.renderer.timeline == nil,
        cppID: id, message: "cold unload discards acquired, retired and pending outputs safely")
    rig.renderer.bind(timeline: rig.timeline(), voicegroup: rig.voices, settings: AudioSettings())
    rig.renderer.play()
    let samples = rig.render(rig.ramp + rig.settle + 4096)
    report.expect(
        rig.sustaining(60) && audioControllerCheckPeak(samples.suffix(2048)) > 0.01,
        cppID: id, message: "cold rebind after reclamation still produces audible samples")
}

@MainActor
private func checkNativeAudioLifetime(_ report: CheckReport) throws {
    guard let projectRoot = CheckEnvironment.fixtureRoot else {
        report.fail("swiftcore/NativeAudio::forcedNullBackend", "missing real-project audio fixture")
        return
    }

    for detachedRelease in [false, true] {
        let id =
            detachedRelease
            ? "swiftcore/NativeAudio::detachedLastRelease"
            : "swiftcore/NativeAudio::mainActorLastRelease"
        let service = ProjectService()
        var facade: NativeAudio?
        weak var releasedFacade: NativeAudio?
        weak var releasedBank: ProjectBankLease?
        do {
            let song = try runBlocking {
                try await service.open(root: projectRoot)
                return try await service.openSong(label: "mus_route101")
            }
            do {
                let owner = try runBlocking { try await NativeAudio() }
                let midi = try MidiFile.decode(song.midiBytes)
                let timeline = PlaybackTimeline.build(file: midi, sampleRate: owner.sampleRate)
                owner.bind(timeline: timeline, bank: song.bank, config: song.config)
                owner.play()
                if !detachedRelease {
                    report.expect(
                        owner.usingNullBackend && owner.nullBackendForced
                            && owner.backendName == "Null",
                        cppID: "swiftcore/NativeAudio::forcedNullBackend",
                        message: "forced null request resolves to the reported Null backend")
                }

                let soundingDeadline = Date().addingTimeInterval(5)
                var sounding = false
                while !sounding && Date() < soundingDeadline {
                    sounding =
                        owner.playheadSamples > 0
                        && owner.consumeTrackActivityLevels().contains {
                            $0.left > 0 || $0.right > 0
                        }
                    if !sounding {
                        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
                    }
                }
                report.expect(
                    sounding, cppID: id,
                    message: "real bank sounds through the null-backend callback before teardown")
                releasedBank = song.bank
                releasedFacade = owner
                facade = owner
            }
            try runBlocking { await service.close() }
        } catch {
            do {
                try runBlocking { await service.close() }
            } catch {
                report.fail(id, "project close after audio setup failure failed: \(error)")
            }
            report.fail(id, "real-project audio setup failed: \(error)")
            continue
        }

        report.expect(
            releasedFacade != nil && releasedBank != nil, cppID: id,
            message: "the facade still pins its bank after project service close")
        if detachedRelease {
            let handoff = AsyncStream<Void>.makeStream()
            let lastOwner: Task<Void, Never>
            do {
                guard let owner = facade else {
                    report.fail(id, "detached handoff lost its final facade owner")
                    continue
                }
                lastOwner = Task.detached { [owner] in
                    for await _ in handoff.stream { break }
                    withExtendedLifetime(owner) {}
                }
            }
            facade = nil
            handoff.continuation.yield(())
            handoff.continuation.finish()
            try runBlocking { await lastOwner.value }
        } else {
            facade = nil
        }

        let releaseDeadline = Date().addingTimeInterval(5)
        while (releasedFacade != nil || releasedBank != nil) && Date() < releaseDeadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        report.expect(
            releasedFacade == nil && releasedBank == nil, cppID: id,
            message: "isolated deinit joins callback and releases facade and pinned bank")
    }
}

private func checkControllerPitchBendAudio(_ report: CheckReport) throws {
    func renderPhrase(bent: Bool) throws -> [Float] {
        let rig = try AudioControllerCheckFixture()
        var events: [MidiEvent] = [.channel(tick: 0, status: 0xC0, data0: 0)]
        if bent { events.append(.channel(tick: 0, status: 0xE0, data0: 0, data1: 32)) }
        events.append(.channel(tick: 0, status: 0x90, data0: 60, data1: 100))
        if bent { events.append(.channel(tick: 12, status: 0xE0, data0: 0, data1: 96)) }
        events.append(.channel(tick: 4800, status: 0xB0, data0: 7, data1: 100))
        let file = MidiFile(
            division: 24,
            chunks: [
                MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 4800),
                MidiChunk(events: events, endTick: 4800),
            ])
        let timeline = PlaybackTimeline.build(file: file, sampleRate: Double(rig.rate))
        rig.renderer.bind(timeline: timeline, voicegroup: rig.voices, settings: AudioSettings())
        rig.renderer.play()
        return rig.render(rig.ramp + rig.settle + Int(timeline.sample(for: 6)))
    }

    let plain = try renderPhrase(bent: false)
    let bent = try renderPhrase(bent: true)
    let difference = zip(plain, bent).reduce(0.0) { sum, pair in
        sum + abs(Double(pair.0) - Double(pair.1))
    }
    report.expect(
        plain.count == bent.count && difference > 0.01,
        cppID: "swiftgridprototype/audio_smoke.cpp::A008",
        message: "early pitch-bend point audibly changes production PCM before the final curve point")
}

private func checkControllerControls(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture()
    let audio = rig.renderer
    checkAudioVolumeClamps(audio, report)
    audio.play()
    _ = rig.render(rig.rate)
    let peaks = audio.consumeTrackActivityLevels()
    report.expect(
        peaks[0].left > 0 && peaks[0].right > 0, cppID: "swiftcore/AudioController::peakConsume",
        message: "rendered note publishes both stereo activity components")
    report.expect(
        audio.consumeTrackActivityLevels().allSatisfy { $0.left == 0 && $0.right == 0 },
        cppID: "swiftcore/AudioController::peakConsume", message: "consumption clears peak hold")
    audio.setOutputVolume(0)
    let fade = rig.render(rig.ramp + 1)
    report.expect(
        audioControllerCheckPeak(fade.prefix(2)) > 0 && audioControllerCheckPeak(fade.suffix(2)) == 0,
        cppID: "swiftcore/AudioController::volumeRamp", message: "volume reaches zero at 10 ms, not immediately")
    audio.setOutputVolume(100)
    _ = rig.render(rig.ramp)
    audio.setMix(muted: [0], soloed: [])
    let muted = rig.render(rig.rate)
    report.expect(
        !rig.sustaining(60) && audioControllerCheckPeak(muted.suffix(4096)) <= 1 / 32768,
        cppID: "swiftcore/AudioController::muteOnly",
        message: "mute-only releases the sounding track and drains to silence")
    audio.setMix(muted: [], soloed: [])
    audio.publish(rig.timeline(retriggerAt: 192))
    audio.seek(190_000)
    let unmuted = rig.render(12_000)
    report.expect(
        rig.sustaining(60) && audioControllerCheckPeak(unmuted.suffix(2048)) > 0.01,
        cppID: "swiftcore/AudioController::muteOnly", message: "future note-on sounds after unmute")
    audio.setMix(muted: [0], soloed: [0])
    _ = rig.render(1)
    report.expect(
        !rig.sustaining(60), cppID: "swiftcore/AudioController::soloPrecedence",
        message: "muted track remains muted inside the solo set")
    audio.setMix(muted: [], soloed: [0])
    audio.seek(190_000)
    _ = rig.render(12_000)
    report.expect(
        rig.sustaining(60), cppID: "swiftcore/AudioController::soloPrecedence",
        message: "unmuted solo track accepts its next note")
    audio.setMix(muted: [], soloed: [1])
    _ = rig.render(1)
    report.expect(
        !rig.sustaining(60), cppID: "swiftcore/AudioController::soloPrecedence",
        message: "track outside solo set releases")
    audio.setPolyDebugInvert(true)
    _ = rig.render(1)
    audio.bind(timeline: rig.timeline(), voicegroup: rig.voices, settings: AudioSettings())
    _ = rig.render(1)
    report.expect(
        audio.polySnapshot().invert, cppID: "swiftcore/AudioController::stickyPolyDebug",
        message: "invert reasserts after cold reinit")
    audio.setPolyDebugInvert(false)
    var limited = AudioSettings()
    limited.maxPcmChannels = 1
    audio.bind(timeline: rig.timeline(keys: [60, 64, 67, 72]), voicegroup: rig.voices, settings: limited)
    audio.play()
    _ = rig.render(rig.ramp + rig.settle + 4096)
    report.expect(
        audio.polyLostTotal > 0, cppID: "swiftcore/AudioController::polyReset",
        message: "one-channel chord must overflow before reset")
    audio.resetPolyStats()
    _ = rig.render(1)
    report.expectEqual(
        expected: UInt64(0), actual: audio.polyLostTotal, cppID: "swiftcore/AudioController::polyReset",
        what: "callback clears existing overflow")
    checkUnloadPlayingSong(rig, report)
}

private func checkControllerTailMatrix(_ report: CheckReport) throws {
    for songLoops in [false, true] {
        for enabled in [false, true] {
            let rig = try AudioControllerCheckFixture()
            let timeline = rig.timeline(looped: songLoops)
            let id = "swiftcore/AudioController::tailStop[songLoop=\(songLoops),enabled=\(enabled)]"
            report.expectEqual(
                expected: songLoops, actual: timeline.hasLoop, cppID: id, what: "MIDI loop-marker precondition")
            rig.renderer.bind(timeline: timeline, voicegroup: rig.voices, settings: AudioSettings())
            rig.renderer.setLoopEnabled(enabled)
            rig.renderer.play()
            _ = rig.render(rig.ramp + rig.settle + 4096)
            rig.renderer.seek(timeline.lengthSamples + 3 * UInt64(rig.rate) + 1)
            _ = rig.render(rig.ramp * 3 + rig.settle)
            if songLoops && enabled {
                report.expect(
                    rig.renderer.transport == .playing && rig.renderer.playheadSamples < timeline.loopEndSample,
                    cppID: id, message: "enabled song loop wraps instead of stopping")
            } else {
                report.expect(
                    rig.renderer.transport == .stopped && rig.renderer.playheadSamples == 0,
                    cppID: id, message: "without an effective loop the expired tail stops and rewinds")
            }
        }
    }
}

private func checkControllerSettingsAndBank(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture()
    let audio = rig.renderer
    audio.play()
    let initial = rig.render(rig.rate)
    let loud = audioControllerCheckPeak(initial.suffix(4096))
    var settings = AudioSettings()
    settings.songVolume = 32
    let cursor = audio.playheadSamples
    audio.updateSettings(settings)
    let quiet = rig.render(rig.rate)
    let quietPeak = audioControllerCheckPeak(quiet.suffix(4096))
    report.expect(
        loud > 0.01 && quietPeak > 0 && quietPeak < loud * 0.6,
        cppID: "swiftcore/AudioController::settingsVolume", message: "cold song volume changes actual sustained output")
    report.expectEqual(
        expected: cursor + UInt64(rig.rate), actual: audio.playheadSamples,
        cppID: "swiftcore/AudioController::settingsVolume", what: "settings preserve playing cursor")
    settings.pcmMixRate = 18157
    let rateCursor = audio.playheadSamples
    audio.updateSettings(settings)
    let rateChanged = rig.render(rig.rate)
    report.expect(
        audio.transport == .playing && audioControllerCheckPeak(rateChanged.suffix(4096)) > 0.001 && rig.sustaining(60),
        cppID: "swiftcore/AudioController::settingsMixRate", message: "mix-rate update preserves the sounding song")
    // Native rate reconfiguration resets the PCM FIFO; it is a cold discontinuity,
    // not a promised click-free crossfade. The sequence itself must not restart.
    report.expectEqual(
        expected: rateCursor + UInt64(rig.rate), actual: audio.playheadSamples,
        cppID: "swiftcore/AudioController::settingsMixRate", what: "mix-rate change preserves sequence position")

    let squareBank = try AudioControllerCheckFixture(square: true)
    withExtendedLifetime(squareBank) {
        audio.bind(timeline: rig.timeline(retriggerAt: 96), voicegroup: rig.voices, settings: AudioSettings())
        audio.play()
        let smooth = rig.render(rig.rate)
        let beforeSwap = audio.playheadSamples
        audio.updateVoicegroup(squareBank.voices)
        let swapped = rig.render(rig.rate * 2)
        report.expectEqual(
            expected: beforeSwap + UInt64(rig.rate * 2), actual: audio.playheadSamples,
            cppID: "swiftcore/AudioController::bankRebind", what: "bank swap preserves sequence cursor")
        report.expect(
            rig.sustaining(60) && audioControllerCheckPeak(swapped.suffix(4096)) > 0.01
                && audioControllerCheckStep(swapped, from: rig.rate * 2 - 2048, to: rig.rate * 2)
                    > audioControllerCheckStep(smooth, from: rig.rate - 2048, to: rig.rate) + 0.001,
            cppID: "swiftcore/AudioController::bankRebind",
            message: "future sequenced note uses the replacement square timbre after chase/prime")
        audio.unload()
    }
}

private func checkControllerPreviewIsolation(_ report: CheckReport) throws {
    let rig = try AudioControllerCheckFixture()
    let audio = rig.renderer
    audio.play()
    let song = rig.render(rig.rate)
    let baseline = audioControllerCheckPeak(song.suffix(4096))
    let cursor = audio.playheadSamples
    audio.audition.previewVoice(program: 0, key: 67, velocity: 127)
    let combined = rig.render(rig.rate)
    report.expect(
        baseline > 0.01 && audioControllerCheckPeak(combined.suffix(4096)) > baseline * 1.2 && rig.sustaining(60)
            && !rig.sustaining(67),
        cppID: "swiftcore/AudioController::voicePreviewIsolation",
        message: "voice preview adds audible output without replacing the song engine's held note")
    report.expectEqual(
        expected: cursor + UInt64(rig.rate), actual: audio.playheadSamples,
        cppID: "swiftcore/AudioController::voicePreviewIsolation", what: "sequence advances during voice preview")
    audio.audition.previewVoice(program: 0, key: 67, velocity: 0)
    audio.setMix(muted: [0], soloed: [])
    let drained = rig.render(rig.rate * 2)
    report.expect(
        audioControllerCheckPeak(drained.suffix(4096)) <= 1 / 32768,
        cppID: "swiftcore/AudioController::voicePreviewIsolation",
        message: "released preview and muted main drain to silence")

    let sample = (0..<64).map { Int8((100 * sin(Double($0) * 2 * .pi / 64)).rounded()) }
    let accepted = audio.audition.publishSample(
        samples: sample, frequency: 8363 * 1024,
        loopStart: 0, looped: true, key: 60,
        adsr: AudioADSR(attack: 255, decay: 0, sustain: 255, release: 0), toneKey: 60)
    report.expect(
        accepted, cppID: "swiftcore/AudioController::samplePreviewIsolation", message: "sample publication accepted")
    let sampleCursor = audio.playheadSamples
    report.expect(
        audio.transport == .playing && sampleCursor > 0,
        cppID: "swiftcore/AudioController::samplePreviewIsolation",
        message: "sequence is actively playing before sample audition")
    let sampled = rig.render(rig.rate)
    report.expect(
        audioControllerCheckPeak(sampled.suffix(4096)) > 0.01 && audio.activePcmChannels == 0,
        cppID: "swiftcore/AudioController::samplePreviewIsolation",
        message: "sample sounds exclusively through preview engine")
    report.expectEqual(
        expected: sampleCursor + UInt64(rig.rate), actual: audio.playheadSamples,
        cppID: "swiftcore/AudioController::samplePreviewIsolation", what: "sample preview does not park sequence")
    audio.audition.sampleOff()
    let sampleReleased = rig.render(rig.rate)
    report.expect(
        audioControllerCheckPeak(sampleReleased.suffix(4096)) <= 1 / 32768,
        cppID: "swiftcore/AudioController::samplePreviewIsolation", message: "sampleOff silences the looped sample")

    let wave = [UInt8](repeating: 0xFF, count: 8) + [UInt8](repeating: 0, count: 8)
    let waveAccepted = audio.audition.publishWave(
        wave16: wave, key: 60,
        adsr: AudioADSR(attack: 7, decay: 0, sustain: 15, release: 0))
    report.expect(
        waveAccepted, cppID: "swiftcore/AudioController::wavePreviewIsolation", message: "wave publication accepted")
    let waved = rig.render(rig.rate)
    report.expect(
        audioControllerCheckPeak(waved.suffix(4096)) > 0.01 && audio.activeCgbChannels == 0,
        cppID: "swiftcore/AudioController::wavePreviewIsolation",
        message: "CGB wave sounds exclusively through preview engine")
    audio.audition.sampleOff()
    let waveReleased = rig.render(rig.rate)
    report.expect(
        audioControllerCheckPeak(waveReleased.suffix(4096)) <= 1 / 32768,
        cppID: "swiftcore/AudioController::wavePreviewIsolation", message: "sampleOff also releases the CGB wave")
}
