import Foundation
@testable import PorydawApp
import PorydawCore

@MainActor
internal func runTransportBarChecks(_ report: CheckReport) {
    let id = "swiftcore/TransportBar::clockAndMeasure"
    report.expectEqual("0:00.0", TransportBarPresenter.clock(sample: 0, sampleRate: 48_000),
                       cppID: id, what: "empty transport starts at zero tenths")
    report.expectEqual("0:59.9", TransportBarPresenter.clock(sample: 2_879_999,
                                                              sampleRate: 48_000),
                       cppID: id, what: "subminute clock truncates rather than rounds")
    report.expectEqual("1:00.0", TransportBarPresenter.clock(sample: 2_880_000,
                                                              sampleRate: 48_000),
                       cppID: id, what: "clock carries seconds at minute boundary")

    var file = makeMidiFixture()
    file.chunks[0].events.append(.meta(tick: 192, type: 0x58, data: [3, 2, 24, 8]))
    let timeline = PlaybackTimeline.build(file: file, sampleRate: 48_000)
    report.expectEqual("1:1", TransportBarPresenter.measure(at: 0, timeline: timeline),
                       cppID: id, what: "opening bar and beat are one-based")
    report.expectEqual("1:4", TransportBarPresenter.measure(at: 72, timeline: timeline),
                       cppID: id, what: "fourth beat belongs to opening measure")
    report.expectEqual("2:1", TransportBarPresenter.measure(at: 96, timeline: timeline),
                       cppID: id, what: "bar increments at its beat boundary")
    report.expectEqual("3:1", TransportBarPresenter.measure(at: 192, timeline: timeline),
                       cppID: id, what: "time-signature change starts the third bar")
    report.expectEqual("4:1", TransportBarPresenter.measure(at: 264, timeline: timeline),
                       cppID: id, what: "new 3/4 segment advances after three beats")
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail("swiftcore/DocumentWorkspace::audibleMix", "missing --swiftcore fixture root")
        return
    }
    checkSelectedWorkspaceAudio(report, fixtureRoot: fixtureRoot)
}

@MainActor
private func checkSelectedWorkspaceAudio(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/DocumentWorkspace::audibleMix"
    let project = stageTestProject(in: fixtureRoot, projectName: "swiftcore-workspace-audio")
    do {
        for label in ["mus_session_test", "mus_session_test2"] {
            let url = URL(fileURLWithPath: project)
                .appendingPathComponent("sound/songs/midi/\(label).mid")
            var file = try MidiFile.decode(Array(Data(contentsOf: url)))
            guard let chunk = file.engineTracks().tracks.first?.midiChunk else {
                report.fail(id, "\(label) has no playable MIDI track")
                return
            }
            file.chunks[chunk].events.insert(.channel(tick: 0, status: 0xC0, data0: 0), at: 0)
            try Data(file.encoded()).write(to: url)
        }
    } catch {
        report.fail(id, "could not prepare sounding MIDI fixture: \(error)")
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
    func until(_ predicate: () -> Bool, seconds: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !predicate() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return predicate()
    }
    func sounding() -> Bool {
        audio.activeCgbChannels > 0 && audio.polySnapshot().cgb.contains {
            $0.on && !$0.releasing && $0.track == 0 && $0.midiKey == 60
        }
    }
    var observationFailure = ""
    func observeOpeningNote() -> Bool? {
        observationFailure = ""
        guard let session = app.selectedDocument else {
            observationFailure = "no selected document"
            return nil
        }
        let noteWindow = session.timeline.sample(for: 10)
        let noteEnd = session.timeline.sample(for: 20)
        app.play()
        let reachedWindow = until({ audio.playheadSamples >= noteWindow && audio.transport == 2 })
        let observedSample = audio.playheadSamples
        guard reachedWindow, observedSample < noteEnd else {
            observationFailure = "missed note window \(noteWindow)..<\(noteEnd): "
                + "sample=\(observedSample), transport=\(audio.transport), "
                + "backend=\(audio.backendName), period=\(audio.periodSizeFrames)"
            app.stop()
            return nil
        }
        let result = sounding()
        if !result {
            let channels = audio.polySnapshot().cgb.filter(\.on).map {
                "(track:\($0.track), key:\($0.midiKey), releasing:\($0.releasing))"
            }
            observationFailure = "note window reached at \(observedSample), "
                + "activeCGB=\(audio.activeCgbChannels), activePCM=\(audio.activePcmChannels), "
                + "CGB voices=\(channels)"
        }
        app.stop()
        guard until({ audio.playheadSamples == 0 && !sounding() }) else {
            observationFailure = "stop did not rewind and release voices: "
                + "sample=\(audio.playheadSamples), transport=\(audio.transport)"
            return nil
        }
        return result
    }
    func expectOpeningNote(_ expected: Bool, message: String) {
        let observed = observeOpeningNote()
        let detail = observationFailure.isEmpty ? "" : ": \(observationFailure)"
        report.expect(observed == expected, cppID: id, message: "\(message)\(detail)")
    }

    app.openProjectAndSong(path: project, label: "mus_session_test")
    guard until({ app.songOpen || !app.lastSaveError.isEmpty }, seconds: 25),
          app.songOpen, let first = app.songTabs.selectedPage else {
        report.fail(id, "first fixture workspace did not open: \(app.lastSaveError)")
        return
    }
    guard let silentTrack = app.selectedDocument?.document.addTrack(voice: 0),
          silentTrack != 0 else {
        report.fail(id, "fixture could not add an empty track for the solo exclusion")
        return
    }
    guard observeOpeningNote() == true else {
        report.fail(id, "selected fixture note must produce native CGB activity and a sounding "
            + "polyphony voice: \(observationFailure)")
        return
    }
    first.trackHeadersPresenter().activateMute(track: 0)
    expectOpeningNote(false, message: "selected track mute prevents a sequenced voice from sounding")
    first.trackHeadersPresenter().activateMute(track: 0)
    expectOpeningNote(true, message: "unmuting selected track restores its sequenced voice")
    first.trackHeadersPresenter().activateSolo(track: silentTrack)
    expectOpeningNote(false, message: "soloing the empty track suppresses the other track's sequenced voice")
    first.trackHeadersPresenter().activateSolo(track: silentTrack)
    first.trackHeadersPresenter().activateMute(track: 0)
    let firstID = first.tabId
    app.openSong(label: "mus_session_test2")
    guard until({ app.songTabs.tabCount == 2 && app.songTabs.selectedId != firstID
                  || !app.lastSaveError.isEmpty }, seconds: 25),
          app.songTabs.tabCount == 2, app.songTabs.selectedId != firstID else {
        report.fail(id, "second fixture workspace did not open: \(app.lastSaveError)")
        return
    }
    let secondID = app.songTabs.selectedId
    expectOpeningNote(true, message: "activating another tab restores its audible unmuted mix")
    app.songTabs.selectTab(tabId: firstID)
    expectOpeningNote(false, message: "reactivating muted workspace suppresses its real sequenced voice")
    app.songTabs.selectTab(tabId: secondID)
    expectOpeningNote(true, message: "switching back restores the other workspace's native voice")
}
