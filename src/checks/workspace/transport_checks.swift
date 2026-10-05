import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument

@MainActor
internal func runTransportBarChecks(_ report: CheckReport) {
    let id = "swiftcore/TransportBar::clockAndMeasure"
    report.expectEqual(
        expected: "0:00.0", actual: TransportBarPresenter.clock(sample: 0, sampleRate: 48_000),
        cppID: id, what: "empty transport starts at zero tenths")
    report.expectEqual(
        expected: "0:59.9",
        actual: TransportBarPresenter.clock(
            sample: 2_879_999,
            sampleRate: 48_000),
        cppID: id, what: "subminute clock truncates rather than rounds")
    report.expectEqual(
        expected: "1:00.0",
        actual: TransportBarPresenter.clock(
            sample: 2_880_000,
            sampleRate: 48_000),
        cppID: id, what: "clock carries seconds at minute boundary")

    var file = makeMidiFixture()
    file.chunks[0].events.append(.meta(tick: 192, type: 0x58, data: [3, 2, 24, 8]))
    let timeline = PlaybackTimeline.build(file: file, sampleRate: 48_000)
    report.expectEqual(
        expected: "1:1", actual: TransportBarPresenter.measure(at: 0, timeline: timeline),
        cppID: id, what: "opening bar and beat are one-based")
    report.expectEqual(
        expected: "1:4", actual: TransportBarPresenter.measure(at: 72, timeline: timeline),
        cppID: id, what: "fourth beat belongs to opening measure")
    report.expectEqual(
        expected: "2:1", actual: TransportBarPresenter.measure(at: 96, timeline: timeline),
        cppID: id, what: "bar increments at its beat boundary")
    report.expectEqual(
        expected: "3:1", actual: TransportBarPresenter.measure(at: 192, timeline: timeline),
        cppID: id, what: "time-signature change starts the third bar")
    report.expectEqual(
        expected: "4:1", actual: TransportBarPresenter.measure(at: 264, timeline: timeline),
        cppID: id, what: "new 3/4 segment advances after three beats")

    var boundaryFile = makeMidiFixture()
    boundaryFile.chunks[0].events.append(.meta(tick: 25, type: 0x58, data: [3, 3, 24, 8]))
    boundaryFile.chunks[0].events.append(.meta(tick: 62, type: 0x58, data: [5, 4, 24, 8]))
    let boundaryTimeline = PlaybackTimeline.build(file: boundaryFile, sampleRate: 48_000)
    let boundaries: [(tick: Tick, measure: String)] = [
        (0, "1:1"), (23, "1:1"), (24, "1:2"), (25, "2:1"),
        (36, "2:1"), (37, "2:2"), (60, "2:3"), (61, "3:1"),
        (62, "4:1"), (67, "4:1"), (68, "4:2"), (91, "4:5"), (92, "5:1"),
    ]
    for boundary in boundaries {
        report.expectEqual(
            expected: boundary.measure,
            actual: TransportBarPresenter.measure(at: boundary.tick, timeline: boundaryTimeline),
            cppID: id, what: "partial-bar signature changes and beat floors at tick \(boundary.tick)")
    }
    checkRestoredOutputVolumeAfterAttachment(report)
    checkTransportVolumeIsolation(report, fixtureRoot: CheckEnvironment.fixtureRoot)
    checkTransportTogglePreferences(report)

    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail("swiftcore/DocumentWorkspace::audibleMix", "missing --swiftcore fixture root")
        return
    }
    checkSelectedWorkspaceAudio(report, fixtureRoot: fixtureRoot)
    checkLiveTimelineTransport(report, fixtureRoot: fixtureRoot)
}

@MainActor
private func checkTransportTogglePreferences(_ report: CheckReport) {
    let id = "swiftcore/TransportBar::togglePreferences"
    let store = PreferencesStore()
    let originalFollow =
        store.hasValue(key: "followPlayhead")
        ? store.bool(key: "followPlayhead", fallback: true) : nil
    let originalResonance =
        store.hasValue(key: "dsp.resonanceSuppression")
        ? store.bool(key: "dsp.resonanceSuppression", fallback: false) : nil
    defer {
        if let originalFollow {
            store.setBool(key: "followPlayhead", value: originalFollow)
        } else {
            store.remove(key: "followPlayhead")
        }
        if let originalResonance {
            store.setBool(key: "dsp.resonanceSuppression", value: originalResonance)
        } else {
            store.remove(key: "dsp.resonanceSuppression")
        }
        store.synchronize()
    }
    store.setBool(key: "followPlayhead", value: false)
    store.setBool(key: "dsp.resonanceSuppression", value: true)
    store.synchronize()
    let session = ApplicationSession()
    defer {
        session.hostClosing()
        session.acknowledgeGridDetached()
    }
    let presenter = session.transportBarPresenter()
    presenter.restoreTransportToggles()
    guard let audio = try? runBlocking({ await session.preparedAudio() }) else {
        report.fail(id, "native audio failed to initialize: \(session.lastSaveError)")
        return
    }
    report.expectEqual(
        expected: false, actual: presenter.followPlayhead, cppID: id,
        what: "stored follow-playhead preference restores into the transport presenter")
    report.expectEqual(
        expected: true, actual: audio.resonanceSuppression, cppID: id,
        what: "stored resonance suppression restores into the audio engine")
    presenter.setFollowPlayhead(enabled: true)
    report.expectEqual(
        expected: true, actual: store.bool(key: "followPlayhead", fallback: false),
        cppID: id, what: "toggling follow playhead stores its preference on change")
    presenter.setResonanceSuppression(enabled: false)
    report.expectEqual(
        expected: false,
        actual: store.bool(key: "dsp.resonanceSuppression", fallback: true),
        cppID: id, what: "toggling resonance suppression stores its preference on change")
    report.expectEqual(
        expected: false, actual: audio.resonanceSuppression,
        cppID: id, what: "toggling resonance suppression updates the real audio engine")
}

@MainActor
private func checkTransportVolumeIsolation(_ report: CheckReport, fixtureRoot: String?) {
    let id = "swiftcore/TransportBar::volumeIsolation"
    guard let fixtureRoot else {
        report.fail(id, "missing transport fixture root")
        return
    }
    let store = PreferencesStore()
    let original = store.hasValue(key: "outputVolume") ? store.int(key: "outputVolume", fallback: 100) : nil
    defer {
        if let original {
            store.setInt(key: "outputVolume", value: original)
        } else {
            store.remove(key: "outputVolume")
        }
        store.synchronize()
    }
    store.setInt(key: "outputVolume", value: 37)
    store.synchronize()
    let project = stageTestProject(in: fixtureRoot, projectName: "swiftcore-transport-volume")
    let app = ApplicationSession()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    let bar = app.transportBarPresenter()
    bar.restoreOutputVolume()
    guard let audio = try? runBlocking({ await app.preparedAudio() }) else {
        report.fail(id, "native audio failed to initialize: \(app.lastSaveError)")
        return
    }
    report.expectEqual(
        expected: 37, actual: bar.outputVolume, cppID: id,
        what: "staged 37 output preference restores into selected toolbar")
    report.expectEqual(
        expected: 37, actual: audio.outputVolume, cppID: id,
        what: "restored 37 output preference reaches real native audio")
    app.openProjectAndSong(path: project, label: "mus_session_test")
    guard pollCheckUntil({ app.songOpen || !app.lastSaveError.isEmpty }, seconds: 25),
        let first = app.songTabs.selectedPage
    else {
        report.fail(id, "first transport song did not open: \(app.lastSaveError)")
        return
    }
    bar.refresh()
    let firstDocument = first.workspace.session.document
    let initialMaster = firstDocument.state.config.masterVolume
    let initialCount = firstDocument.history.undoCount
    let initialIndex = firstDocument.history.undoIndex
    report.expectEqual(
        expected: initialMaster, actual: bar.masterVolume, cppID: id,
        what: "loaded master field projection reads the first song cfg")
    bar.commitOutputVolume(percent: 42)
    report.expectEqual(
        expected: 42, actual: audio.outputVolume, cppID: id,
        what: "edited 42 application output reaches real native audio")
    report.expectEqual(
        expected: 42, actual: PreferencesStore().int(key: "outputVolume", fallback: -1),
        cppID: id, what: "edited 42 output persists in the isolated preference domain")
    report.expectEqual(
        expected: initialMaster, actual: firstDocument.state.config.masterVolume,
        cppID: id, what: "output edit leaves first song master cfg unchanged")
    report.expect(
        firstDocument.history.undoCount == initialCount && firstDocument.history.undoIndex == initialIndex, cppID: id,
        message: "output edit records no song history count or index")
    report.expect(
        !firstDocument.isDirty, cppID: id,
        message: "output edit leaves the first song clean")
    bar.commitOutputVolume(percent: bar.outputVolume)
    report.expect(
        firstDocument.history.undoCount == initialCount && firstDocument.history.undoIndex == initialIndex, cppID: id,
        message: "same-value output commit preserves the exact song history count and index")
    bar.commitOutputVolume(percent: 37)
    let editedMaster = initialMaster == 100 ? 101 : 100
    bar.setMasterVolume(value: editedMaster)
    report.expectEqual(
        expected: editedMaster, actual: firstDocument.state.config.masterVolume,
        cppID: id, what: "song master edit changes the first song cfg")
    report.expectEqual(
        expected: editedMaster, actual: audio.appliedSongVolume,
        cppID: id, what: "edited song master reaches applied audio settings")
    report.expect(
        firstDocument.history.undoCount == initialCount + 1 && firstDocument.history.undoIndex == initialIndex + 1
            && firstDocument.history.canUndo, cppID: id,
        message: "song master edit creates one reachable undo entry")
    report.expect(
        firstDocument.isDirty, cppID: id,
        message: "song master edit dirties its owning document")
    let firstID = first.tabId
    app.openSong(label: "mus_session_test2")
    guard
        pollCheckUntil(
            { app.songTabs.tabCount == 2 && app.songTabs.selectedId != firstID || !app.lastSaveError.isEmpty },
            seconds: 25), let second = app.songTabs.selectedPage,
        second.tabId != firstID
    else {
        report.fail(id, "second transport song did not open: \(app.lastSaveError)")
        return
    }
    bar.refresh()
    report.expectEqual(
        expected: second.workspace.session.document.state.config.masterVolume, actual: bar.masterVolume,
        cppID: id, what: "tab switch projects the second song's own master cfg")
    report.expectEqual(
        expected: 37, actual: audio.outputVolume, cppID: id,
        what: "global 37 output remains applied to audio after tab switch")
    report.expect(
        !second.workspace.session.document.isDirty, cppID: id,
        message: "switching away from master edit leaves the second song clean")
    app.songTabs.selectTab(tabId: firstID)
    bar.refresh()
    report.expectEqual(
        expected: editedMaster, actual: bar.masterVolume, cppID: id,
        what: "return to first tab restores its edited master field")
    app.requestUndo()
    guard pollCheckUntil({ firstDocument.history.undoIndex == initialIndex }, seconds: 5) else {
        report.fail(id, "first song master undo did not complete")
        return
    }
    bar.refresh()
    report.expectEqual(
        expected: initialMaster, actual: firstDocument.state.config.masterVolume,
        cppID: id, what: "undo restores first song master cfg")
    report.expectEqual(
        expected: initialMaster, actual: bar.masterVolume, cppID: id,
        what: "undo restores first song master field")
    report.expect(
        !firstDocument.isDirty, cppID: id,
        message: "undo returns the first song to its clean saved state")
}

@MainActor
private func checkRestoredOutputVolumeAfterAttachment(_ report: CheckReport) {
    let id = "swiftcore/TransportBar::lateOutputVolumeAttachment"
    let store = PreferencesStore()
    let original = store.hasValue(key: "outputVolume") ? store.int(key: "outputVolume", fallback: 100) : nil
    defer {
        if let original {
            store.setInt(key: "outputVolume", value: original)
        } else {
            store.remove(key: "outputVolume")
        }
        store.synchronize()
    }
    store.setInt(key: "outputVolume", value: 37)
    store.synchronize()
    let app = ApplicationSession()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    let presenter = app.transportBarPresenter()
    presenter.restoreOutputVolume()
    report.expectEqual(
        expected: 37, actual: presenter.outputVolume, cppID: id,
        what: "stored output volume survives before audio readiness")
    guard let audio = try? runBlocking({ await app.preparedAudio() }) else {
        report.fail(id, "native audio failed to initialize: \(app.lastSaveError)")
        return
    }
    report.expectEqual(
        expected: 37, actual: audio.outputVolume, cppID: id,
        what: "stored output volume reaches the real engine when audio becomes ready")

    store.setInt(key: "outputVolume", value: 145)
    presenter.restoreOutputVolume()
    report.expectEqual(
        expected: 100, actual: presenter.outputVolume, cppID: id,
        what: "stored output volume above the maximum clamps to 100")
    report.expectEqual(
        expected: 100, actual: audio.outputVolume, cppID: id,
        what: "audio receives the clamped upper volume")
    store.setInt(key: "outputVolume", value: -5)
    presenter.restoreOutputVolume()
    report.expectEqual(
        expected: 0, actual: presenter.outputVolume, cppID: id,
        what: "stored output volume below zero clamps to zero")
    report.expectEqual(
        expected: 0, actual: audio.outputVolume, cppID: id,
        what: "audio receives the clamped lower volume")
}

@MainActor
private func checkSelectedWorkspaceAudio(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/DocumentWorkspace::audibleMix"
    guard let project = stageSoundingWorkspaceFixtures(report: report, id: id, fixtureRoot: fixtureRoot) else {
        return
    }
    let app = ApplicationSession()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    guard let audio = try? runBlocking({ await app.preparedAudio() }) else {
        report.fail(id, "native audio failed to initialize: \(app.lastSaveError)")
        return
    }
    app.openProjectAndSong(path: project, label: "mus_session_test")
    guard pollCheckUntil({ app.songOpen || !app.lastSaveError.isEmpty }, seconds: 25),
        app.songOpen, let first = app.songTabs.selectedPage
    else {
        report.fail(id, "first fixture workspace did not open: \(app.lastSaveError)")
        return
    }
    let meter = app.transportBarPresenter()
    meter.refresh()
    let meterID = "swiftcore/TransportBar::polyphonyMeter"
    report.expect(
        meter.polyMeterVisible, cppID: meterID,
        message: "the selected loaded song publishes the PCM/CGB meter")
    report.expectEqual(
        expected: "0/\(audio.maxPcmChannels)", actual: meter.pcmText,
        cppID: meterID, what: "idle PCM channels use the audio engine's current limit")
    report.expectEqual(
        expected: "0/4", actual: meter.cgbText,
        cppID: meterID, what: "idle CGB channels use the four-channel limit")
    report.expect(
        !meter.lostVisible && meter.lostText.isEmpty, cppID: meterID,
        message: "zero lost notes hide and clear the lost readout")
    guard let silentTrack = app.selectedDocument?.document.addTrack(voice: 0),
        silentTrack != 0
    else {
        report.fail(id, "fixture could not add an empty track for the solo exclusion")
        return
    }
    guard
        checkSelectedTrackMuteSolo(
            app: app, audio: audio, report: report, id: id,
            page: first, silentTrack: silentTrack)
    else {
        return
    }
    checkTwoTabAudioIsolation(app: app, audio: audio, report: report, id: id, firstID: first.tabId)
    checkEngineStopResyncsTransportState(app: app, audio: audio, report: report)
    checkCursorCommitSeeksPausedAndPlayingTransport(app: app, audio: audio, report: report)
}

@MainActor
private func checkCursorCommitSeeksPausedAndPlayingTransport(
    app: ApplicationSession, audio: NativeAudio,
    report: CheckReport
) {
    let id = "workspace/WorkspaceTransportSelfTest::settingsAndSeekKeepLiveTransport"
    guard let page = app.songTabs.selectedPage else {
        report.fail(id, "cursor-commit seek needs the selected workspace")
        return
    }
    let session = page.workspace.session
    let length = session.timeline.lengthTicks
    guard length > 1 else {
        report.fail(id, "fixture song has no seekable length")
        return
    }
    let maxTick = length - 1
    app.stop()
    guard pollCheckUntil({ audio.transport == 0 }, seconds: 10) else {
        report.fail(id, "transport did not stop before the cursor-commit journey")
        return
    }
    let staged = min(Tick(session.timeline.ticksPerBeat) * 8, maxTick)
    page.workspace.grid.setEditCursorTick(tick: Int(staged))
    report.expect(
        session.editCursor == staged, cppID: id,
        message: "a stopped cursor commit moves only the edit cursor")
    app.play()
    guard pollCheckUntil({ audio.transport == 2 }, seconds: 10) else {
        report.fail(id, "fixture song did not start from its edit cursor")
        return
    }
    app.playPause()
    guard pollCheckUntil({ audio.transport == 1 }, seconds: 10) else {
        report.fail(id, "fixture song did not pause before the cursor-commit seek")
        return
    }
    let pausedTick = audio.timeline.map { Tick(max(0, $0.tick(for: audio.playheadSamples))) } ?? 0
    let ahead = pausedTick >= 960 ? pausedTick - 480 : min(pausedTick + 960, maxTick)
    page.workspace.grid.setEditCursorTick(tick: Int(ahead))
    report.expect(
        pollCheckUntil(
            {
                audio.transport == 1
                    && abs(app.playheadPresenter().tick - Double(ahead)) <= 0.25
            }, seconds: 5), cppID: id,
        message: "a paused cursor commit moves the shared playhead to its target")
    report.expect(
        pollCheckUntil(
            {
                guard let timeline = audio.timeline else { return false }
                return audio.transport == 1
                    && abs(timeline.tick(for: audio.playheadSamples) - Double(ahead)) <= 0.25
            }, seconds: 5), cppID: id,
        message: "a paused cursor commit moves the audio playhead within 0.25 ticks of its target")
    let beforeResume = audio.playheadSamples
    app.play()
    report.expect(
        pollCheckUntil(
            {
                audio.transport == 2 && audio.playheadSamples > beforeResume
            }, seconds: 5), cppID: id,
        message: "play after a paused cursor commit resumes past the committed sample")
    let seekTick = min(length / 2, Tick(session.timeline.ticksPerBeat) * 16)
    let seekSample = session.timeline.sample(for: seekTick)
    page.workspace.grid.setEditCursorTick(tick: Int(seekTick))
    report.expect(
        pollCheckUntil(
            {
                audio.transport == 2
                    && audio.playheadSamples >= seekSample
            }, seconds: 5), cppID: id,
        message: "a playing cursor commit seeks audio past its tick while staying Playing")
    app.stop()
    report.expect(
        pollCheckUntil({ audio.transport == 0 }, seconds: 10),
        cppID: id, message: "stop after a playing cursor commit leaves transport Stopped")
    app.play()
    let quarter = UInt64(Double(audio.sampleRate) * 0.25)
    report.expect(
        pollCheckUntil(
            {
                audio.transport == 2
                    && audio.playheadSamples >= seekSample + quarter
            }, seconds: 10), cppID: id,
        message: "play after stop restarts from the committed cursor and advances a quarter second")
}

@MainActor
private func stageSoundingWorkspaceFixtures(report: CheckReport, id: String, fixtureRoot: String) -> String? {
    let project = stageTestProject(in: fixtureRoot, projectName: "swiftcore-workspace-audio")
    do {
        for label in ["mus_session_test", "mus_session_test2"] {
            let url = URL(fileURLWithPath: project)
                .appendingPathComponent("sound/songs/midi/\(label).mid")
            var file = try MidiFile.decode(Array(Data(contentsOf: url)))
            guard let chunk = file.engineTracks().tracks.first?.midiChunk else {
                report.fail(id, "\(label) has no playable MIDI track")
                return nil
            }
            file.chunks[chunk].events.insert(.channel(tick: 0, status: 0xC0, data0: 0), at: 0)
            try Data(file.encoded()).write(to: url)
        }
    } catch {
        report.fail(id, "could not prepare sounding MIDI fixture: \(error)")
        return nil
    }
    return project
}

@MainActor
private func pollCheckUntil(_ predicate: () -> Bool, seconds: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !predicate() && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    return predicate()
}

@MainActor
private func workspaceAudioSounding(_ audio: NativeAudio) -> Bool {
    audio.activeCgbChannels > 0
        && audio.polySnapshot().cgb.contains {
            $0.on && !$0.releasing && $0.track == 0 && $0.midiKey == 60
        }
}

@MainActor
private func observeWorkspaceOpeningNote(
    app: ApplicationSession, audio: NativeAudio,
    failure: inout String
) -> Bool? {
    failure = ""
    guard let session = app.selectedDocument else {
        failure = "no selected document"
        return nil
    }
    let noteWindow = session.timeline.sample(for: 10)
    let noteEnd = session.timeline.sample(for: 20)
    app.play()
    let reachedWindow = pollCheckUntil({ audio.playheadSamples >= noteWindow && audio.transport == 2 })
    let observedSample = audio.playheadSamples
    guard reachedWindow, observedSample < noteEnd else {
        failure =
            "missed note window \(noteWindow)..<\(noteEnd): "
            + "sample=\(observedSample), transport=\(audio.transport), "
            + "backend=\(audio.backendName), period=\(audio.periodSizeFrames)"
        app.stop()
        return nil
    }
    let result = workspaceAudioSounding(audio)
    if !result {
        let channels = audio.polySnapshot().cgb.filter(\.on).map {
            "(track:\($0.track), key:\($0.midiKey), releasing:\($0.releasing))"
        }
        failure =
            "note window reached at \(observedSample), "
            + "activeCGB=\(audio.activeCgbChannels), activePCM=\(audio.activePcmChannels), "
            + "CGB voices=\(channels)"
    }
    app.stop()
    guard pollCheckUntil({ audio.playheadSamples == 0 && !workspaceAudioSounding(audio) }) else {
        failure =
            "stop did not rewind and release voices: "
            + "sample=\(audio.playheadSamples), transport=\(audio.transport)"
        return nil
    }
    return result
}

@MainActor
private func expectWorkspaceOpeningNote(
    app: ApplicationSession, audio: NativeAudio, report: CheckReport,
    id: String, expected: Bool, message: String
) {
    var failure = ""
    let observed = observeWorkspaceOpeningNote(app: app, audio: audio, failure: &failure)
    let detail = failure.isEmpty ? "" : ": \(failure)"
    report.expect(observed == expected, cppID: id, message: "\(message)\(detail)")
}

@MainActor
private func checkSelectedTrackMuteSolo(
    app: ApplicationSession, audio: NativeAudio, report: CheckReport,
    id: String, page: SongTabSession, silentTrack: Int
) -> Bool {
    var failure = ""
    guard observeWorkspaceOpeningNote(app: app, audio: audio, failure: &failure) == true else {
        report.fail(
            id,
            "selected fixture note must produce native CGB activity and a sounding "
                + "polyphony voice: \(failure)")
        return false
    }
    page.trackHeadersPresenter().activateMute(track: 0)
    expectWorkspaceOpeningNote(
        app: app, audio: audio, report: report, id: id,
        expected: false,
        message: "selected track mute prevents a sequenced voice from sounding")
    page.trackHeadersPresenter().activateMute(track: 0)
    expectWorkspaceOpeningNote(
        app: app, audio: audio, report: report, id: id,
        expected: true,
        message: "unmuting selected track restores its sequenced voice")
    page.trackHeadersPresenter().activateSolo(track: silentTrack)
    expectWorkspaceOpeningNote(
        app: app, audio: audio, report: report, id: id,
        expected: false,
        message: "soloing the empty track suppresses the other track's sequenced voice")
    page.trackHeadersPresenter().activateSolo(track: silentTrack)
    page.trackHeadersPresenter().activateMute(track: 0)
    return true
}

@MainActor
private func checkTwoTabAudioIsolation(
    app: ApplicationSession, audio: NativeAudio, report: CheckReport,
    id: String, firstID: Int
) {
    app.openSong(label: "mus_session_test2")
    guard
        pollCheckUntil(
            {
                app.songTabs.tabCount == 2 && app.songTabs.selectedId != firstID
                    || !app.lastSaveError.isEmpty
            }, seconds: 25),
        app.songTabs.tabCount == 2, app.songTabs.selectedId != firstID
    else {
        report.fail(id, "second fixture workspace did not open: \(app.lastSaveError)")
        return
    }
    let secondID = app.songTabs.selectedId
    expectWorkspaceOpeningNote(
        app: app, audio: audio, report: report, id: id,
        expected: true,
        message: "activating another tab restores its audible unmuted mix")
    app.songTabs.selectTab(tabId: firstID)
    expectWorkspaceOpeningNote(
        app: app, audio: audio, report: report, id: id,
        expected: false,
        message: "reactivating muted workspace suppresses its real sequenced voice")
    app.songTabs.selectTab(tabId: secondID)
    expectWorkspaceOpeningNote(
        app: app, audio: audio, report: report, id: id,
        expected: true,
        message: "switching back restores the other workspace's native voice")
}

@MainActor
private func checkEngineStopResyncsTransportState(
    app: ApplicationSession, audio: NativeAudio,
    report: CheckReport
) {
    let checkID = "swiftcore/TransportBar::engineStopResyncsState"
    audio.setLoopEnabled(false)
    app.play()
    guard pollCheckUntil({ audio.transport == 2 }, seconds: 10) else {
        report.fail(checkID, "fixture song did not start: transport=\(audio.transport)")
        return
    }
    guard let timeline = audio.timeline else {
        report.fail(checkID, "engine has no timeline after start")
        return
    }
    let tailStop = timeline.lengthSamples + UInt64(3 * audio.sampleRate)
    audio.seek(sample: tailStop > 2048 ? tailStop - 1024 : 0)
    guard pollCheckUntil({ audio.transport == 0 }, seconds: 10) else {
        report.fail(
            checkID,
            "engine did not auto-stop past the tail: "
                + "sample=\(audio.playheadSamples), transport=\(audio.transport)")
        return
    }
    let meter = app.transportBarPresenter()
    report.expect(
        pollCheckUntil({ meter.state == 1 }, seconds: 5), cppID: checkID,
        message: "engine-initiated stop resyncs cached transport state without a manual refresh")
}
