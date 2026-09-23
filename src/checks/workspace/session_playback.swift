import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Playback Projection and State Publication

@MainActor
internal func sessionPlaybackProjectionAndStatePublication(report: CheckReport, session: DocumentSession) {
    // 3. Architecture Amendment: State-to-Playback factory verification
    // Verify initial timeline matches canonical state factory projection
    let initialExpectedTimeline = PlaybackTimeline.build(state: session.document.state, sampleRate: 48_000)
    report.expectEqual(initialExpectedTimeline.sample(for: 24), session.timeline.sample(for: 24),
                       cppID: "swiftcore/DocumentSession::initialPlaybackProjection",
                       what: "initial timeline matches canonical state factory projection")

    // Verify adoption stripped tempo metas from file chunks
    var chunkMetasStripped = true
    for chunk in session.document.state.file.chunks {
        for event in chunk.events {
            if case let .meta(type, _) = event.payload, type == 0x51 {
                chunkMetasStripped = false
            }
        }
    }
    report.expect(chunkMetasStripped,
                  cppID: "savecheck/ProjectSaveTest::saveReloadsNoteLoopAndCfg_preservesOtherCfgBytes",
                  message: "adoption stripped tempo meta events from file chunks into authoritative state.tempo")
    report.expectEqual(1, session.document.state.tempo.count,
                       cppID: "swiftcore/DocumentSession::authoritativeTempoAdoption",
                       what: "authoritative tempo point count in state")

    // At 120 BPM (500_000 us/quarter note) and division 24, 24 ticks = 0.5s -> 24000 samples at 48kHz
    let initialSampleAt24 = session.timeline.sample(for: 24)
    report.expectEqual(UInt64(24_000), initialSampleAt24,
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
    report.expect(publishedChangeCount > 0,
                  cppID: "projectworkspacecheck/ProjectWorkspaceTest::planEventsForwardKeyed",
                  message: "document mutation invokes session presenter callback")
    report.expect(lastPublishedTimeline != nil,
                  cppID: "project-io-flow/ProjectIoFlowTest::voicegroupLoadAndPreviewPaths",
                  message: "immutable playback publication callback received updated timeline")

    // At 150 BPM (400_000 us/quarter note), 24 ticks = 0.4s -> exactly 19200 samples at 48kHz
    let editedSampleAt24 = session.timeline.sample(for: 24)
    report.expectEqual(UInt64(19_200), editedSampleAt24,
                       cppID: "project-io-flow/ProjectIoFlowTest::fifoDeliversInSubmissionOrder",
                       what: "state factory projection computes exact 19200 samples for edited tempo")

    // Build from the same canonical state under the two mid2agb clock/gate modes.
    let defaultGate60 = noteOffSample(session.timeline, key: 60)
    let defaultClock64 = noteOffSample(session.timeline, key: 64)
    var extendedState = session.document.state
    extendedState.config.extendedClocks = true
    extendedState.config.exactGate = false
    let extendedTimeline = PlaybackTimeline.build(state: extendedState, sampleRate: 48_000)
    report.expectEqual(UInt64(48_000), noteOffSample(extendedTimeline, key: 64),
                       cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[private-load]",
                       what: "48-clock conversion quantizes the 13-tick gate to 12 ticks")
    report.expect(defaultClock64 != noteOffSample(extendedTimeline, key: 64),
                  cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[private-load]",
                  message: "extended clocks change an observable note-release sample")

    var updatedCfg = session.document.state.config
    updatedCfg.extendedClocks = true
    updatedCfg.exactGate = true
    session.document.setConfig(updatedCfg)
    let configuredGate60 = noteOffSample(session.timeline, key: 60)
    report.expectEqual(UInt64(20_000), configuredGate60,
                       cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[reload]",
                       what: "exact gate preserves the 25-tick release instead of LUT bucket 24")
    report.expect(defaultGate60 != configuredGate60,
                  cppID: "project-io-flow/ProjectIoFlowTest::songChains_openReloadStageTag[reload]",
                  message: "exact gate changes an observable note-release sample")

    // Undo and redo must reproduce both tempo and settings-sensitive event timing.
    do {
        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(defaultGate60, noteOffSample(session.timeline, key: 60),
                           cppID: "swiftcore/DocumentSession::configurationUndoRedoPlayback",
                           what: "undo config restores default gate release scheduling")
        report.expectEqual(UInt64(19_200), session.timeline.sample(for: 24),
                           cppID: "swiftcore/DocumentSession::configurationUndoRedoPlayback",
                           what: "timeline remains at 150 BPM prior to tempo undo")

        _ = try runBlocking {
            try await session.undo()
        }
        report.expectEqual(UInt64(24_000), session.timeline.sample(for: 24),
                           cppID: "project-identity/ProjectIdentityTest::savedRecipe_selectionFallbacks",
                           what: "undo tempo restores initial 120 BPM timing")

        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(UInt64(19_200), session.timeline.sample(for: 24),
                           cppID: "project-identity/ProjectIdentityTest::savedRecipe_legacySingleLabelAndEmpty",
                           what: "redo tempo restores 150 BPM timing")
        _ = try runBlocking {
            try await session.redo()
        }
        report.expectEqual(configuredGate60, noteOffSample(session.timeline, key: 60),
                           cppID: "swiftcore/DocumentSession::configurationUndoRedoPlayback",
                           what: "redo config reproduces exact-gate event timing")
    } catch {
        report.fail("swiftcore/DocumentSession::configurationUndoRedoPlayback",
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
    report.expectEqual(publicationStart, publishedChangeCount,
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
    report.expectEqual(publicationStart, publishedChangeCount,
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
    report.expect(publishedChangeCount == publicationStart + 1 && observedCompletedBatch,
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
        report.expectEqual(false, session.selectedNotes.contains(note1),
                           cppID: "swiftcore/DocumentSession::selectionPrunesDeletedNotes",
                           what: "selection reconciler prunes dead note IDs when notes are deleted")
    }
}
