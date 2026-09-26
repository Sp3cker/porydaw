import Foundation
@testable import PorydawApp
import PorydawCore

@MainActor
internal func runTransportBarChecks(_ report: CheckReport) {
    let id = "swiftcore/TransportBar::clockAndMeasure"
    report.expectEqual(expected: "0:00.0", actual: TransportBarPresenter.clock(sample: 0, sampleRate: 48_000),
                       cppID: id, what: "empty transport starts at zero tenths")
    report.expectEqual(expected: "0:59.9", actual: TransportBarPresenter.clock(sample: 2_879_999,
                                                              sampleRate: 48_000),
                       cppID: id, what: "subminute clock truncates rather than rounds")
    report.expectEqual(expected: "1:00.0", actual: TransportBarPresenter.clock(sample: 2_880_000,
                                                              sampleRate: 48_000),
                       cppID: id, what: "clock carries seconds at minute boundary")

    var file = makeMidiFixture()
    file.chunks[0].events.append(.meta(tick: 192, type: 0x58, data: [3, 2, 24, 8]))
    let timeline = PlaybackTimeline.build(file: file, sampleRate: 48_000)
    report.expectEqual(expected: "1:1", actual: TransportBarPresenter.measure(at: 0, timeline: timeline),
                       cppID: id, what: "opening bar and beat are one-based")
    report.expectEqual(expected: "1:4", actual: TransportBarPresenter.measure(at: 72, timeline: timeline),
                       cppID: id, what: "fourth beat belongs to opening measure")
    report.expectEqual(expected: "2:1", actual: TransportBarPresenter.measure(at: 96, timeline: timeline),
                       cppID: id, what: "bar increments at its beat boundary")
    report.expectEqual(expected: "3:1", actual: TransportBarPresenter.measure(at: 192, timeline: timeline),
                       cppID: id, what: "time-signature change starts the third bar")
    report.expectEqual(expected: "4:1", actual: TransportBarPresenter.measure(at: 264, timeline: timeline),
                       cppID: id, what: "new 3/4 segment advances after three beats")
    checkRestoredOutputVolumeAfterAttachment(report)

    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail("swiftcore/DocumentWorkspace::audibleMix", "missing --swiftcore fixture root")
        return
    }
    checkSelectedWorkspaceAudio(report, fixtureRoot: fixtureRoot)
}

@MainActor
private func checkRestoredOutputVolumeAfterAttachment(_ report: CheckReport) {
    let id = "swiftcore/TransportBar::lateOutputVolumeAttachment"
    let store = PreferencesStore()
    defer {
        store.remove(key: "outputVolume")
        store.synchronize()
    }
    store.setInt(key: "outputVolume", value: 37)
    store.synchronize()
    let presenter = TransportBarPresenter()
    presenter.restoreOutputVolume()
    report.expectEqual(expected: 37, actual: presenter.outputVolume, cppID: id,
                       what: "stored output volume survives before audio attachment")
    let app = ApplicationSession()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    guard let audio = app.transportAudio else {
        report.fail(id, "native audio failed to initialize: \(app.lastSaveError)")
        return
    }
    presenter.attach(session: app)
    report.expectEqual(expected: 37, actual: audio.outputVolume, cppID: id,
                       what: "stored output volume survives late audio attachment")

    store.setInt(key: "outputVolume", value: 145)
    presenter.restoreOutputVolume()
    report.expectEqual(expected: 100, actual: presenter.outputVolume, cppID: id,
                       what: "stored output volume above the maximum clamps to 100")
    report.expectEqual(expected: 100, actual: audio.outputVolume, cppID: id,
                       what: "audio receives the clamped upper volume")
    store.setInt(key: "outputVolume", value: -5)
    presenter.restoreOutputVolume()
    report.expectEqual(expected: 0, actual: presenter.outputVolume, cppID: id,
                       what: "stored output volume below zero clamps to zero")
    report.expectEqual(expected: 0, actual: audio.outputVolume, cppID: id,
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
    guard let audio = app.transportAudio else {
        report.fail(id, "native audio failed to initialize: \(app.lastSaveError)")
        return
    }
    app.openProjectAndSong(path: project, label: "mus_session_test")
    guard pollCheckUntil({ app.songOpen || !app.lastSaveError.isEmpty }, seconds: 25),
          app.songOpen, let first = app.songTabs.selectedPage else {
        report.fail(id, "first fixture workspace did not open: \(app.lastSaveError)")
        return
    }
    let meter = app.transportBarPresenter()
    meter.refresh()
    let meterID = "swiftcore/TransportBar::polyphonyMeter"
    report.expect(meter.polyMeterVisible, cppID: meterID,
                  message: "the selected loaded song publishes the PCM/CGB meter")
    report.expectEqual(expected: "0/\(audio.maxPcmChannels)", actual: meter.pcmText,
                       cppID: meterID, what: "idle PCM channels use the audio engine's current limit")
    report.expectEqual(expected: "0/4", actual: meter.cgbText,
                       cppID: meterID, what: "idle CGB channels use the four-channel limit")
    report.expect(!meter.lostVisible && meter.lostText.isEmpty, cppID: meterID,
                  message: "zero lost notes hide and clear the lost readout")
    guard let silentTrack = app.selectedDocument?.document.addTrack(voice: 0),
          silentTrack != 0 else {
        report.fail(id, "fixture could not add an empty track for the solo exclusion")
        return
    }
    guard checkSelectedTrackMuteSolo(app: app, audio: audio, report: report, id: id,
                                     page: first, silentTrack: silentTrack) else {
        return
    }
    checkTwoTabAudioIsolation(app: app, audio: audio, report: report, id: id, firstID: first.tabId)
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
    audio.activeCgbChannels > 0 && audio.polySnapshot().cgb.contains {
        $0.on && !$0.releasing && $0.track == 0 && $0.midiKey == 60
    }
}

@MainActor
private func observeWorkspaceOpeningNote(app: ApplicationSession, audio: NativeAudio,
                                         failure: inout String) -> Bool? {
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
        failure = "missed note window \(noteWindow)..<\(noteEnd): "
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
        failure = "note window reached at \(observedSample), "
            + "activeCGB=\(audio.activeCgbChannels), activePCM=\(audio.activePcmChannels), "
            + "CGB voices=\(channels)"
    }
    app.stop()
    guard pollCheckUntil({ audio.playheadSamples == 0 && !workspaceAudioSounding(audio) }) else {
        failure = "stop did not rewind and release voices: "
            + "sample=\(audio.playheadSamples), transport=\(audio.transport)"
        return nil
    }
    return result
}

@MainActor
private func expectWorkspaceOpeningNote(app: ApplicationSession, audio: NativeAudio, report: CheckReport,
                                        id: String, expected: Bool, message: String) {
    var failure = ""
    let observed = observeWorkspaceOpeningNote(app: app, audio: audio, failure: &failure)
    let detail = failure.isEmpty ? "" : ": \(failure)"
    report.expect(observed == expected, cppID: id, message: "\(message)\(detail)")
}

@MainActor
private func checkSelectedTrackMuteSolo(app: ApplicationSession, audio: NativeAudio, report: CheckReport,
                                        id: String, page: SongTabSession, silentTrack: Int) -> Bool {
    var failure = ""
    guard observeWorkspaceOpeningNote(app: app, audio: audio, failure: &failure) == true else {
        report.fail(id, "selected fixture note must produce native CGB activity and a sounding "
            + "polyphony voice: \(failure)")
        return false
    }
    page.trackHeadersPresenter().activateMute(track: 0)
    expectWorkspaceOpeningNote(app: app, audio: audio, report: report, id: id,
                               expected: false,
                               message: "selected track mute prevents a sequenced voice from sounding")
    page.trackHeadersPresenter().activateMute(track: 0)
    expectWorkspaceOpeningNote(app: app, audio: audio, report: report, id: id,
                               expected: true,
                               message: "unmuting selected track restores its sequenced voice")
    page.trackHeadersPresenter().activateSolo(track: silentTrack)
    expectWorkspaceOpeningNote(app: app, audio: audio, report: report, id: id,
                               expected: false,
                               message: "soloing the empty track suppresses the other track's sequenced voice")
    page.trackHeadersPresenter().activateSolo(track: silentTrack)
    page.trackHeadersPresenter().activateMute(track: 0)
    return true
}

@MainActor
private func checkTwoTabAudioIsolation(app: ApplicationSession, audio: NativeAudio, report: CheckReport,
                                       id: String, firstID: Int) {
    app.openSong(label: "mus_session_test2")
    guard pollCheckUntil({ app.songTabs.tabCount == 2 && app.songTabs.selectedId != firstID
                  || !app.lastSaveError.isEmpty }, seconds: 25),
          app.songTabs.tabCount == 2, app.songTabs.selectedId != firstID else {
        report.fail(id, "second fixture workspace did not open: \(app.lastSaveError)")
        return
    }
    let secondID = app.songTabs.selectedId
    expectWorkspaceOpeningNote(app: app, audio: audio, report: report, id: id,
                               expected: true,
                               message: "activating another tab restores its audible unmuted mix")
    app.songTabs.selectTab(tabId: firstID)
    expectWorkspaceOpeningNote(app: app, audio: audio, report: report, id: id,
                               expected: false,
                               message: "reactivating muted workspace suppresses its real sequenced voice")
    app.songTabs.selectTab(tabId: secondID)
    expectWorkspaceOpeningNote(app: app, audio: audio, report: report, id: id,
                               expected: true,
                               message: "switching back restores the other workspace's native voice")
}
