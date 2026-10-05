import Foundation
@testable import PorydawApp
import PorydawAppAudio
import PorydawCore
import PorydawCoreCheckNative
@testable import PorydawDocument
import PorydawPlayback
import PorydawPlaybackNative

// MARK: - Playback Projection and State Publication

@MainActor
internal func sessionPlaybackProjectionAndStatePublication(report: CheckReport, session: DocumentSession) {
    // 3. Architecture Amendment: State-to-Playback factory verification
    // Verify initial timeline matches canonical state factory projection
    let initialExpectedTimeline = PlaybackTimeline.build(state: session.document.state, sampleRate: 48_000)
    report.expectEqual(
        expected: initialExpectedTimeline.sample(for: 24), actual: session.timeline.sample(for: 24),
        cppID: "swiftcore/DocumentSession::initialPlaybackProjection",
        what: "initial timeline matches canonical state factory projection")

    // Verify adoption stripped tempo metas from file chunks
    var chunkMetasStripped = true
    for chunk in session.document.state.file.chunks {
        for event in chunk.events {
            if case .meta(let type, _) = event.payload, type == 0x51 {
                chunkMetasStripped = false
            }
        }
    }
    report.expect(
        chunkMetasStripped,
        cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
        message: "adoption stripped tempo meta events from file chunks into authoritative state.tempo")
    report.expectEqual(
        expected: 1, actual: session.document.state.tempo.count,
        cppID: "swiftcore/DocumentSession::authoritativeTempoAdoption",
        what: "authoritative tempo point count in state")

    // At 120 BPM (500_000 us/quarter note) and division 24, 24 ticks = 0.5s -> 24000 samples at 48kHz
    let initialSampleAt24 = session.timeline.sample(for: 24)
    report.expectEqual(
        expected: UInt64(24_000), actual: initialSampleAt24,
        cppID: "project-io-mutations/ProjectIoMutationsTest::semanticSaveBareAndWithRecipe",
        what: "initial tempo 120 BPM schedules exactly 24000 samples at tick 24")

    // Presenter callbacks publication setup
    var publishedChangeCount = 0
    var publishedPlaybackCount = 0
    var publishedChanges: [SessionChange] = []
    var publicationObserver: ((SessionChange) -> Void)?
    var lastPublishedTimeline: PlaybackTimeline?
    session.onChange = { change in
        publishedChangeCount += 1
        publishedChanges.append(change)
        publicationObserver?(change)
    }
    session.onPlayback = { timeline in
        publishedPlaybackCount += 1
        lastPublishedTimeline = timeline
    }

    // Edit tempo to 150 BPM (400_000 us/quarter note)
    let tempo150 = TempoPoint(tick: 0, microsecondsPerQuarterNote: 400_000)
    session.document.editTempo(TempoEdit(remove: session.document.state.tempo, add: [tempo150]))

    // After edit: state factory rebuilds timeline, onChange and onPlayback fire
    report.expect(
        publishedChangeCount > 0,
        cppID: "projectworkspacecheck/ProjectWorkspaceTest::planEventsForwardKeyed",
        message: "document mutation invokes session presenter callback")
    report.expect(
        lastPublishedTimeline != nil,
        cppID: "project-io-flow/ProjectIoFlowTest::voicegroupLoadAndPreviewPaths",
        message: "immutable playback publication callback received updated timeline")

    // At 150 BPM (400_000 us/quarter note), 24 ticks = 0.4s -> exactly 19200 samples at 48kHz
    let editedSampleAt24 = session.timeline.sample(for: 24)
    report.expectEqual(
        expected: UInt64(19_200), actual: editedSampleAt24,
        cppID: "project-io-flow/ProjectIoFlowTest::fifoDeliversInSubmissionOrder",
        what: "state factory projection computes exact 19200 samples for edited tempo")

    // Build from the same canonical state under the two mid2agb clock/gate modes.
    let defaultGate60 = noteOffSample(session.timeline, key: 60)
    let defaultClock64 = noteOffSample(session.timeline, key: 64)
    var extendedState = session.document.state
    extendedState.config.extendedClocks = true
    extendedState.config.exactGate = false
    let extendedTimeline = PlaybackTimeline.build(state: extendedState, sampleRate: 48_000)
    report.expectEqual(
        expected: UInt64(48_000), actual: noteOffSample(extendedTimeline, key: 64),
        cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[private-load]",
        what: "48-clock conversion quantizes the 13-tick gate to 12 ticks")
    report.expect(
        defaultClock64 != noteOffSample(extendedTimeline, key: 64),
        cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[private-load]",
        message: "extended clocks change an observable note-release sample")

    var updatedCfg = session.document.state.config
    updatedCfg.extendedClocks = true
    updatedCfg.exactGate = true
    session.document.setConfig(updatedCfg)
    let configuredGate60 = noteOffSample(session.timeline, key: 60)
    report.expectEqual(
        expected: UInt64(20_000), actual: configuredGate60,
        cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[reload]",
        what: "exact gate preserves the 25-tick release instead of LUT bucket 24")
    report.expect(
        defaultGate60 != configuredGate60,
        cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[reload]",
        message: "exact gate changes an observable note-release sample")

    // Undo and redo must reproduce both tempo and settings-sensitive event timing.
    do {
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(
            expected: defaultGate60, actual: noteOffSample(session.timeline, key: 60),
            cppID: "swiftcore/DocumentSession::configurationUndoRedoPlayback",
            what: "undo config restores default gate release scheduling")
        report.expectEqual(
            expected: UInt64(19_200), actual: session.timeline.sample(for: 24),
            cppID: "swiftcore/DocumentSession::configurationUndoRedoPlayback",
            what: "timeline remains at 150 BPM prior to tempo undo")

        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(
            expected: UInt64(24_000), actual: session.timeline.sample(for: 24),
            cppID: "project-identity/ProjectIdentityTest::savedRecipe_selectionFallbacks",
            what: "undo tempo restores initial 120 BPM timing")

        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(
            expected: UInt64(19_200), actual: session.timeline.sample(for: 24),
            cppID: "project-identity/ProjectIdentityTest::savedRecipe_legacySingleLabelAndEmpty",
            what: "redo tempo restores 150 BPM timing")
        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(
            expected: configuredGate60, actual: noteOffSample(session.timeline, key: 60),
            cppID: "swiftcore/DocumentSession::configurationUndoRedoPlayback",
            what: "redo config reproduces exact-gate event timing")
    } catch {
        report.fail(
            "swiftcore/DocumentSession::configurationUndoRedoPlayback",
            "undo/redo cycle threw: \(error)")
    }

    // 4. Session-only state publication and isolation
    let statePublicationID = "swiftcore/DocumentSession::sessionStatePublication"
    let preRevision = session.document.revision
    let preDirty = session.document.isDirty
    let preIdentity = session.document.history.currentIdentity
    let preCanUndo = session.document.history.canUndo
    let preCanRedo = session.document.history.canRedo
    let prePlaybackCount = publishedPlaybackCount

    var publicationStart = publishedChangeCount
    session.editCursor = 48
    report.expect(
        publishedChangeCount == publicationStart + 1
            && publishedChanges.last?.domains == [.cursor]
            && publishedChanges.last?.revision == preRevision
            && publishedChanges.last?.trackRemap == nil,
        cppID: statePublicationID,
        message: "cursor-only mutation publishes exactly the cursor domain")
    publicationStart = publishedChangeCount
    session.editCursor = 48
    report.expectEqual(
        expected: publicationStart, actual: publishedChangeCount,
        cppID: statePublicationID,
        what: "equal cursor assignment publishes nothing")

    publicationStart = publishedChangeCount
    session.mutedTracks = [1]
    report.expect(
        publishedChangeCount == publicationStart + 1
            && publishedChanges.last?.domains == [.mixState],
        cppID: statePublicationID,
        message: "mute mutation publishes exactly the mix-state domain")
    publicationStart = publishedChangeCount
    session.soloedTracks = [1]
    report.expect(
        publishedChangeCount == publicationStart + 1
            && publishedChanges.last?.domains == [.mixState],
        cppID: statePublicationID,
        message: "solo mutation publishes exactly the mix-state domain")
    publicationStart = publishedChangeCount
    session.mutedTracks = [1]
    session.soloedTracks = [1]
    report.expectEqual(
        expected: publicationStart, actual: publishedChangeCount,
        cppID: statePublicationID,
        what: "equal mute and solo assignments publish nothing")

    var observedCompletedBatch = false
    publicationObserver = { change in
        observedCompletedBatch =
            change.domains == [.selection, .cursor, .mixState]
            && session.editCursor == 96
            && session.selectedTrack == 0
            && session.mutedTracks == [0]
    }
    publicationStart = publishedChangeCount
    do {
        let _: Void = try session.withStateChanges {
            session.withStateChanges {
                session.editCursor = 96
                session.selectedTrack = 0
            }
            session.mutedTracks = [0]
            throw RunBlockingError.timeout
        }
        report.fail(statePublicationID, "throwing batch unexpectedly returned")
    } catch RunBlockingError.timeout {
        // Expected: the defer must publish the completed state before propagation.
    } catch {
        report.fail(statePublicationID, "throwing batch propagated an unexpected error")
    }
    publicationObserver = nil
    report.expect(
        publishedChangeCount == publicationStart + 1 && observedCompletedBatch,
        cppID: statePublicationID,
        message: "nested throwing batch publishes completed state exactly once")

    session.mutateCamera { _ = $0.setHScroll(12.5) }
    report.expect(
        session.document.revision == preRevision
            && session.document.isDirty == preDirty
            && session.document.history.currentIdentity == preIdentity
            && session.document.history.canUndo == preCanUndo
            && session.document.history.canRedo == preCanRedo
            && publishedPlaybackCount == prePlaybackCount,
        cppID: statePublicationID,
        message: "session-only changes preserve revision, dirty/history, and playback publication")

    // Selection reconciliation
    let note1 = session.document.notes(in: 0).last?.id ?? NoteID(0)
    if note1.isAssigned {
        session.addSelectedNote(note1)
        session.document.deleteNotes([note1])
        report.expectEqual(
            expected: false, actual: session.selectedNotes.contains(note1),
            cppID: "swiftcore/DocumentSession::selectionPrunesDeletedNotes",
            what: "selection reconciler prunes dead note IDs when notes are deleted")
    }
}

@MainActor
internal func checkLiveTimelineTransport(_ report: CheckReport, fixtureRoot: String) {
    let timelineID = "workspace/WorkspaceTimelineSelfTest::liveTimelineSwapAndUndo"
    let transportID = "workspace/WorkspaceTransportSelfTest::settingsAndSeekKeepLiveTransport"
    let project = stageTestProject(in: fixtureRoot, projectName: "swiftcore-live-timeline")
    let songURL = URL(fileURLWithPath: project)
        .appendingPathComponent("sound/songs/midi/mus_session_test.mid")
    do {
        var file = makeMidiFixture()
        file.chunks[1].events.removeFirst(2)
        file.chunks[1].events.insert(.channel(tick: 0, status: 0xC0, data0: 0), at: 0)
        try Data(file.encoded()).write(to: songURL)
    } catch {
        report.fail(timelineID, "could not stage the independent playable song: \(error)")
        return
    }
    let app = ApplicationSession()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    guard let audio = try? runBlocking({ await app.preparedAudio() }) else {
        report.fail(timelineID, "native audio failed to initialize: \(app.lastSaveError)")
        return
    }
    app.openProjectAndSong(path: project, label: "mus_session_test")
    guard liveAudioUntil({ app.songOpen || !app.lastSaveError.isEmpty }, seconds: 25),
        let page = app.songTabs.selectedPage, app.songOpen
    else {
        report.fail(timelineID, "playable workspace did not open: \(app.lastSaveError)")
        return
    }
    let session = page.workspace.session
    let document = session.document
    let originalBytes: [UInt8]
    do {
        originalBytes = try document.state.file.encoded()
    } catch {
        report.fail(timelineID, "initial document cannot encode: \(error)")
        return
    }
    let originalTimeline = session.timeline
    let originalEvents = originalTimeline.events
    let initialIndex = document.history.undoIndex
    let sampleRate = audio.sampleRate
    let startTarget = session.timeline.sample(for: session.editCursor)
    app.play()
    report.expect(
        liveAudioUntil({
            audio.transport == AudioTransportState.playing.rawValue
                && audio.playheadSamples >= startTarget + UInt64(sampleRate * 0.25)
        }), cppID: transportID,
        message: "stopped Play progresses at least a quarter second beyond its actual start sample")

    var settings = AudioSettings()
    settings.pcmMixer =
        audio.pcmMixerMode == M4A_PCM_MIXER_IPATIX
        ? M4A_PCM_MIXER_SAPPY : M4A_PCM_MIXER_IPATIX
    settings.maxPcmChannels = 8
    settings.pcmMixRate = 21_024
    settings.analogFilter = !audio.analogFilter
    let beforeSettings = audio.playheadSamples
    audio.updateSettings(settings)
    report.expect(
        liveAudioUntil({
            audio.pcmMixerMode == settings.pcmMixer
                && audio.maxPcmChannels == Int(settings.maxPcmChannels)
                && audio.pcmMixRate == settings.pcmMixRate
                && audio.analogFilter == settings.analogFilter
                && audio.transport == AudioTransportState.playing.rawValue
                && audio.playheadSamples > beforeSettings
        }), cppID: transportID,
        message: "all four replaced PCM settings reach the playing device as its sample advances")

    app.playPause()
    var lastSample = audio.playheadSamples
    let clock = ContinuousClock()
    var stableSince = clock.now
    report.expect(
        liveAudioUntil({
            let sample = audio.playheadSamples
            if sample != lastSample {
                lastSample = sample
                stableSince = clock.now
            }
            return audio.transport == AudioTransportState.paused.rawValue
                && clock.now - stableSince >= .milliseconds(100)
        }), cppID: transportID,
        message: "paused device samples remain unchanged throughout an uninterrupted 100 ms window")
    app.playheadPresenter().refreshImmediate()
    if let pausedTimeline = audio.timeline {
        report.expect(
            abs(
                app.playheadPresenter().tick
                    - pausedTimeline.tick(for: audio.playheadSamples)) <= 0.25,
            cppID: transportID,
            message: "presented paused playhead is within 0.25 tick of the device timeline")
    } else {
        report.fail(transportID, "paused device lost its timeline")
    }
    let beforeResume = audio.playheadSamples
    app.play()
    report.expect(
        liveAudioUntil({
            audio.transport == AudioTransportState.playing.rawValue
                && audio.playheadSamples > beforeResume
        }), cppID: transportID,
        message: "toolbar resume strictly advances past the sample captured immediately before resume")

    func expectedEvent(
        tick: Tick, type: UInt8, data0: UInt8, data1: UInt8,
        noteID: NoteID = NoteID()
    ) -> PlaybackEvent {
        PlaybackEvent(
            sample: originalTimeline.sample(for: tick), tick: tick,
            type: type, track: 0, data0: data0, data1: data1, noteID: noteID)
    }
    func matchesCompleteSchedule(_ additions: [PlaybackEvent]) -> Bool {
        var remaining = originalEvents
        remaining.append(contentsOf: additions)
        guard session.timeline.events.count == remaining.count else { return false }
        for event in session.timeline.events {
            guard let index = remaining.firstIndex(of: event) else { return false }
            remaining.swapAt(index, remaining.count - 1)
            remaining.removeLast()
        }
        return remaining.isEmpty
    }
    func deviceAgrees(after sample: UInt64) -> Bool {
        audio.transport == AudioTransportState.playing.rawValue
            && audio.playheadSamples > sample
            && audio.timeline?.events == session.timeline.events
    }
    let beforeEdit = audio.playheadSamples
    let ids: [NoteID]
    do {
        ids = try document.addNotes([
            NewNote(track: 0, tick: 0, pitch: 60, duration: 24, velocity: 100)
        ])
    } catch {
        report.fail(timelineID, "live note insert refused: \(error)")
        return
    }
    guard let noteID = ids.first else {
        report.fail(timelineID, "live note insert returned no note")
        return
    }
    document.writeLane(
        track: 0, lane: .controller(7), from: 0, through: 0,
        points: [LaneWrite(tick: 0, value: 100)])
    report.expect(
        document.isDirty, cppID: timelineID,
        message: "live note and controller edits dirty the selected document")
    report.expect(
        liveAudioUntil({ deviceAgrees(after: beforeEdit) })
            && matchesCompleteSchedule([
                expectedEvent(
                    tick: 0, type: 0x9, data0: 60,
                    data1: 100, noteID: noteID),
                expectedEvent(tick: 0, type: 0xB, data0: 7, data1: 100),
                expectedEvent(tick: 24, type: 0x8, data0: 60, data1: 0),
            ]),
        cppID: timelineID,
        message: "live edit publishes the independently scheduled C4 onset and release to playing audio")
    report.expect(
        document.note(noteID)?.tick == 0 && document.note(noteID)?.pitch == 60,
        cppID: timelineID,
        message: "inserted C4 note exists at tick zero in the selected document")

    let beforeMove = audio.playheadSamples
    document.moveNotes([noteID], byTicks: 24, byKeys: 1)
    report.expect(
        liveAudioUntil({ deviceAgrees(after: beforeMove) })
            && matchesCompleteSchedule([
                expectedEvent(tick: 0, type: 0xB, data0: 7, data1: 100),
                expectedEvent(
                    tick: 24, type: 0x9, data0: 61,
                    data1: 100, noteID: noteID),
                expectedEvent(tick: 48, type: 0x8, data0: 61, data1: 0),
            ]),
        cppID: timelineID,
        message: "live move publishes the independently scheduled C sharp onset and release")
    report.expect(
        document.note(noteID)?.tick == 24 && document.note(noteID)?.pitch == 61,
        cppID: timelineID,
        message: "moved note exists at tick 24 and key 61 in the selected document")

    let beforeUndo = audio.playheadSamples
    app.requestUndo()
    guard liveAudioUntil({ document.history.undoIndex == initialIndex + 2 }) else {
        report.fail(timelineID, "first live undo did not restore the note move")
        return
    }
    app.requestUndo()
    guard liveAudioUntil({ document.history.undoIndex == initialIndex + 1 }) else {
        report.fail(timelineID, "second live undo did not restore the controller edit")
        return
    }
    app.requestUndo()
    guard liveAudioUntil({ document.history.undoIndex == initialIndex }) else {
        report.fail(timelineID, "third live undo did not restore the note insertion")
        return
    }
    report.expect(
        liveAudioUntil({ deviceAgrees(after: beforeUndo) })
            && !document.isDirty && matchesCompleteSchedule([]),
        cppID: timelineID,
        message: "three live Undos restore the clean original event schedule while playback advances")
    report.expect(
        (try? document.state.file.encoded()) == originalBytes
            && document.history.undoIndex == initialIndex,
        cppID: timelineID,
        message: "live Undo restores every original MIDI byte and the original history index")

    let voice = app.voiceListController()
    let beforePreview = audio.playheadSamples
    voice.pressVoice(slot: 0)
    let playingPreviewActive = voice.soundingVoice == 0
    _ = liveAudioUntil({ audio.playheadSamples > beforePreview + UInt64(sampleRate * 0.25) })
    voice.releaseVoice()
    report.expect(
        playingPreviewActive && audio.transport == AudioTransportState.playing.rawValue,
        cppID: timelineID,
        message: "voice-control audition during playback leaves the song Playing")
    report.expect(
        audio.playheadSamples > beforePreview, cppID: timelineID,
        message: "voice-control audition leaves the song sample counter advancing")
    app.stop()
    report.expect(
        liveAudioUntil({ audio.transport == AudioTransportState.stopped.rawValue }),
        cppID: timelineID, message: "Stop leaves the song transport Stopped")
    voice.pressVoice(slot: 0)
    let stoppedPreviewActive = voice.soundingVoice == 0
    voice.releaseVoice()
    report.expect(
        stoppedPreviewActive
            && audio.transport == AudioTransportState.stopped.rawValue, cppID: timelineID,
        message: "voice-control audition from Stopped never starts the song transport")
    app.songTabs.requestClose(tabId: page.tabId)
    report.expect(
        liveAudioUntil({ !app.songOpen && app.songTabs.selectedId != page.tabId }),
        cppID: timelineID, message: "closing the final clean tab retires the selected song")
    report.expect(
        app.songTabs.tabCount == 0, cppID: timelineID,
        message: "final tab closure leaves no open workspace tabs")
    let retiredSample = audio.playheadSamples
    let settledAt = clock.now
    _ = liveAudioUntil({ clock.now - settledAt >= .milliseconds(200) }, seconds: 0.3)
    report.expect(
        audio.transport == AudioTransportState.stopped.rawValue
            && !audio.songLoaded && audio.playheadSamples == retiredSample,
        cppID: timelineID,
        message: "stopped engine owns no advancing retired timeline after final tab closure")
}

@MainActor
private func liveAudioUntil(_ predicate: () -> Bool, seconds: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !predicate() && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    return predicate()
}
