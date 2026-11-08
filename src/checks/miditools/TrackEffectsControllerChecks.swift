import Foundation
import PorydawAppPresentation
import PorydawCore
import PorydawPlayback

@testable import PorydawApp
@testable import PorydawDocument
@testable import PorydawPluginHost

private enum EffectsCheckError: Error { case fixture, deadline }
private enum EffectsCheckLane { case headless, editor }

private func effectsState(pitch: Int32 = 0, fault: Int32 = 0, diagnostic: Bool = false) -> PluginStateBlob {
    var component: [UInt8] = []
    for field in [pitch, Int32(128), Int32(0), fault | (diagnostic ? 0x4000_0000 : 0)] {
        for shift in stride(from: 0, to: 32, by: 8) {
            component.append(UInt8(truncatingIfNeeded: UInt32(bitPattern: field) >> shift))
        }
    }
    return PluginStateBlob(component: component, controller: diagnostic ? [] : component)
}

@MainActor
private func effectsHeldKeys(_ audio: NativeAudio, track: Int) -> Set<UInt8>? {
    let snapshot = audio.polySnapshot()
    guard audio.songLoaded, audio.status.appliedTimelineIdentity == audio.requestedTimelineIdentity,
        !snapshot.pcm.isEmpty, !snapshot.cgb.isEmpty
    else { return nil }
    var keys: Set<UInt8> = []
    for channel in snapshot.pcm {
        if channel.on && !channel.releasing && Int(channel.track) == track { keys.insert(channel.midiKey) }
    }
    for channel in snapshot.cgb {
        if channel.on && !channel.releasing && Int(channel.track) == track { keys.insert(channel.midiKey) }
    }
    return keys
}

@MainActor
private func effectsWait(_ predicate: @MainActor () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(6))
    while try await predicate() == false {
        guard ContinuousClock.now < deadline else { throw EffectsCheckError.deadline }
        await Task.yield()
    }
}

@MainActor
private func effectsElapse(_ duration: Duration) async {
    let until = ContinuousClock.now.advanced(by: duration)
    while ContinuousClock.now < until { await Task.yield() }
}

@MainActor
private final class EffectsFixture {
    let audio: NativeAudio
    let session: DocumentSession
    let workspace: DocumentWorkspace
    let playhead = SharedPlayheadPresenter()
    let guides = PlayheadGuidesPresenter()
    let events = EventListPresenter()
    var controller: TrackEffectsController { workspace.effects }

    init(suite: DocumentSession, service: ProjectService, catalog: PluginCatalog, audio: NativeAudio) {
        self.audio = audio
        let file = MidiFile(
            division: 24,
            chunks: [
                MidiChunk(
                    events: [
                        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
                        .meta(tick: 0, type: 0x58, data: [3, 2, 24, 8]),
                        .meta(tick: 72, type: 0x06, data: Array("[".utf8)),
                        .meta(tick: 144, type: 0x06, data: Array("]".utf8)),
                    ], endTick: 216),
                MidiChunk(
                    events: [
                        .channel(tick: 0, status: 0xC0, data0: 0),
                        .channel(tick: 0, status: 0x90, data0: 40, data1: 100),
                        .channel(tick: 60, status: 0x80, data0: 40),
                    ], endTick: 216),
                // Independent CGB channels let source and peer voices prove isolation simultaneously.
                MidiChunk(events: [.channel(tick: 0, status: 0xC1, data0: 1)], endTick: 216),
            ])
        let document = SongDocument(
            file: file, config: suite.document.state.config, source: suite.document.source,
            trackBudget: max(2, suite.document.trackBudget))
        session = DocumentSession(
            document: document, service: service, lease: suite.bankLease, slots: suite.bankSlots,
            dirty: false, loadName: suite.bankLoadName, sampleRate: audio.sampleRate)
        workspace = DocumentWorkspace(
            viewport: DocumentViewport(session: session), audio: audio, pluginCatalog: catalog,
            preferences: PreferencesStore(),
            playhead: playhead, playheadGuides: guides, eventList: events, palette: GridPalette(),
            typography: Typography(baseFontPx: 13),
            callbacks: .init(
                changeTrackVoiceRequested: { (_: Int) in }, revealTrackVoiceRequested: { (_: Int) in },
                gridCommandAvailabilityChanged: {}, sessionStateChanged: {}, publicationFailed: { (_: String) in },
                timeSignaturePromptInvalidated: { (_: DocumentSession, _: UInt64) in }))
        workspace.activate()
    }

    func add(_ entry: PluginCatalogEntry, track: Int = 0, pacing: EffectPacing = .offline) throws -> EffectID {
        try session.document.addEffect(
            TrackEffectConfig(
                track: track,
                plugin: PluginEffectConfig(
                    modulePath: entry.modulePath, classUID: entry.classUID, name: entry.name,
                    input: .none, pacing: pacing, prerollBars: 0)))
    }

    func ready() async throws {
        let timeline = audio.requestedTimelineIdentity
        try await effectsWait {
            audio.songLoaded && audio.status.appliedTimelineIdentity == timeline
                && audio.status.appliedTransport == .stopped
        }
    }

    func finish() async {
        await controller.shutdown()
        workspace.teardown()
        await workspace.awaitAudioRelease()
    }
}

@MainActor
private func effectsRangesAndRender(
    _ fixture: EffectsFixture, entry: PluginCatalogEntry, check: CheckReport.Scoped
) async throws {
    let controller = fixture.controller
    let document = fixture.session.document
    let grabTimeline = PlaybackTimeline.build(
        file: document.state.file, sampleRate: fixture.audio.sampleRate,
        settings: PlaybackSettings(exactGate: false))
    var take = LiveTake()
    take.commitSegment(
        span: TimeRange(startTick: 0, endTick: 26),
        events: [RawNoteEvent(tick: 0, pitch: 70, velocity: 100, isOn: true, noteID: 1)])
    guard let span = take.span else { throw EffectsCheckError.fixture }
    let grabRange = try PluginEffectRenderer.snappedRange(span, timeline: grabTimeline)
    let grabbed = try PluginEffectRenderer.normalize(
        take.events, track: 0, range: grabRange, timeline: grabTimeline, origin: .grab)
    check.expect(
        grabbed.range == TimeRange(startTick: 0, endTick: 72) && grabbed.origin == .grab,
        message: "production Grab normalization snaps a 0..<26 take outward to the full 3/4 bar")
    check.expect(
        grabbed.notes == [NewNote(track: 0, tick: 0, pitch: 70, duration: 28, velocity: 100)],
        message: "production Grab chooses the later duration-28 fixed point, not the unsnapped take endpoint")
    let id = try fixture.add(entry)
    check.expect(
        !controller.isLive(id) && controller.instance(for: id) == nil, message: "effects open unloaded with Live off")
    let loopRange = try controller.renderRange(id)
    check.expect(
        loopRange == TimeRange(startTick: 72, endTick: 144), message: "valid song loop is the default Render range")
    fixture.session.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 80, endTick: 145), scope: .tracks([0])))
    let selectionRange = try controller.renderRange(id)
    check.expect(
        selectionRange == TimeRange(startTick: 72, endTick: 216),
        message: "covered selection wins and snaps outward to 3/4 bars")
    fixture.session.clearTimeSelection()
    document.setLoop(end: true, tick: nil)
    let songRange = try controller.renderRange(id)
    check.expect(
        songRange == TimeRange(startTick: 0, endTick: 216), message: "missing loop end falls back to the whole song")
    _ = try await fixture.session.undo()
    let before = document.state
    try await controller.render(id, range: TimeRange(startTick: 1, endTick: 24))
    guard let rendered = controller.outputs[id] else { throw EffectsCheckError.fixture }
    check.expect(
        rendered.range == TimeRange(startTick: 0, endTick: 72) && !rendered.notes.isEmpty,
        message: "real helper Render normalizes notes into a bar-snapped output")
    check.expect(
        rendered.report?.nonNoteEvents == 1 && document.state == before,
        message: "capture diagnostics retain the fixture CC and output never edits the song")
    try await controller.setLive(id, true)
    guard let instance = controller.instance(for: id), let insert = instance.liveInsert else {
        throw EffectsCheckError.fixture
    }
    check.expect(instance.isLiveArmed && insert.isAttached, message: "real helper processes before Live attaches")
    try controller.grabPlayed(id)
    check.expect(controller.status(id) == .nothingHeard, message: "an empty take is a status, not a fabricated result")
    try await controller.render(id, range: TimeRange(startTick: 0, endTick: 24))
    check.expect(
        instance.isLiveArmed && insert.isAttached, message: "stopped-armed Render re-setups realtime and reattaches")
    fixture.audio.play()
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 0)?.contains(60) == true }
    check.expect(
        effectsHeldKeys(fixture.audio, track: 0)?.contains(40) == false,
        message: "consumer channel telemetry proves Live sounds plugin pitch 60 and masks source pitch 40")
    do {
        try await controller.render(id)
        check.fail("armed/playing Render was accepted")
    } catch {
        check.expect(
            controller.status(id) == .failed("Stop playback to render"),
            message: "armed playback refuses Render with the exact reason")
    }
    try await effectsWait { insert.ring.dropped > 0 || fixture.audio.playheadSamples > 8_000 }
    try controller.grabPlayed(id)
    check.expect(
        controller.outputs[id]?.origin == .grab && controller.outputs[id]?.notes.isEmpty == false,
        message: "50 ms callback take drain and Grab normalize real played output")
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 0)?.isEmpty == false }
    try await controller.setLive(id, false)
    check.expect(!insert.isAttached && !instance.isLiveArmed, message: "disarm detaches before processing stops")
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 0)?.isEmpty == true }
    check.expect(
        effectsHeldKeys(fixture.audio, track: 0)?.isEmpty == true,
        message: "disarm releases live held keys; release tails need not disappear immediately")
    fixture.audio.seek(sample: 0)
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 0)?.contains(40) == true }
    check.expect(
        effectsHeldKeys(fixture.audio, track: 0)?.contains(40) == true,
        message: "source key resumes after detach and seek, proving the live mask was cleared")
    fixture.audio.stop()
    try await effectsWait { fixture.audio.status.appliedTransport == .stopped }
    for _ in 0...LiveTakeRing.capacity {
        insert.ring.push(LiveTakeEvent(tick: 72, kind: .position))
    }
    try controller.grabPlayed(id)
    check.expect(
        controller.outputs[id]?.degraded == true,
        message: "the controller preserves the callback ring's genuine overflow degradation on Grab")
    try await controller.setLive(id, true)
    fixture.audio.play()
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 0)?.contains(60) == true }
    _ = try await fixture.session.undo()
    try await effectsWait { controller.instance(for: id) == nil && !insert.isAttached }
    check.expect(
        controller.outputs[id] == nil && !insert.isAttached, message: "undo of add detaches and clears session output")
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 0)?.contains(60) == false }
    fixture.audio.seek(sample: 0)
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 0)?.contains(40) == true }
    check.expect(
        effectsHeldKeys(fixture.audio, track: 0)?.contains(40) == true,
        message: "undo of a sounding Live add releases the plugin key and restores the original source")
    fixture.audio.stop()
    try await effectsWait { fixture.audio.status.appliedTransport == .stopped }
    _ = try await fixture.session.redo()
    try await controller.setLive(id, true)
    let replacement = try document.addEffect(document.effects[0].config, replacing: id)
    check.expect(
        controller.instance(for: id) == nil && !controller.isLive(id),
        message: "replacement retires the old helper synchronously")
    try await controller.setLive(replacement, true)
    let replacementInstance = controller.instance(for: replacement)
    fixture.audio.play()
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 0)?.contains(60) == true }
    document.deleteTrack(0)
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 0)?.isEmpty == true }
    check.expect(
        effectsHeldKeys(fixture.audio, track: 0)?.isEmpty == true,
        message: "track deletion releases consumer-visible held plugin keys")
    try await effectsWait { replacementInstance?.liveInsert?.isAttached != true }
    check.expect(
        controller.instance(for: replacement) == nil && replacementInstance?.liveInsert?.isAttached != true,
        message: "track deletion acknowledges renderer detach before reclaiming the helper")
}

@MainActor
private func effectsStateHistory(
    _ fixture: EffectsFixture, entry: PluginCatalogEntry, check: CheckReport.Scoped
) async throws {
    let id = try fixture.add(entry)
    let controller = fixture.controller
    let document = fixture.session.document
    let count = document.history.undoCount
    try await controller.load(id)
    guard let instance = controller.instance(for: id) else { throw EffectsCheckError.fixture }
    check.expect(
        document.history.undoCount == count && document.effects[0].pluginState == nil,
        message: "post-load serialized baseline creates no history or document state")
    try await controller.setLive(id, true)
    try await instance.restore(effectsState(pitch: 2))
    try await instance.restore(effectsState(pitch: 4))
    try await effectsWait { document.history.undoCount == count + 1 }
    check.expect(
        document.effects[0].pluginState?.component.first == 4,
        message: "real parameter notifications debounce the gesture burst into one settings step")
    _ = try await fixture.session.undo()
    try await effectsWait { try await instance.state().component.first == 0 }
    check.expect(
        instance.liveInsert?.isAttached == true,
        message: "foreign state undo restores while the Live insert remains attached")
    await effectsElapse(.milliseconds(700))
    check.expect(
        document.history.canRedo && document.history.undoCount == count + 1,
        message: "restore notification suppression preserves redo and creates no settings step")
    _ = try await fixture.session.redo()
    try await effectsWait { try await instance.state().component.first == 4 }
    try await controller.setLive(id, false)
    do {
        try await controller.openEditor(id)
        check.fail("the fixture class without an editor opened one")
    } catch {
        check.expect(
            !instance.isEditorOpen && instance.failure == nil,
            message: "a class without an editor remains usable after Open Editor is refused")
    }
    for _ in 0..<3 {
        controller.suspend()
        controller.suspend()
        controller.activate()
        try await controller.setLive(id, true)
        check.expect(
            controller.instance(for: id) === instance && instance.liveInsert?.isAttached == true,
            message: "rapid repeated suspension joins only this entry before rearming the retained helper")
    }
    let resumedCount = document.history.undoCount
    try await instance.restore(effectsState(pitch: 6))
    try await effectsWait { document.history.undoCount == resumedCount + 1 }
    check.expect(
        document.effects[0].pluginState?.component.first == 6,
        message: "reactivation restarts edit recording without losing or duplicating the finished gesture")
    try await instance.restore(effectsState(pitch: 7))
    try await controller.render(id, range: TimeRange(startTick: 0, endTick: 24))
    try await effectsWait { document.history.undoCount == resumedCount + 2 }
    check.expect(
        document.effects[0].pluginState?.component.first == 7,
        message: "Render defers a pending finished gesture and records it once after capture instead of losing it")
    try await instance.restore(effectsState(pitch: 8))
    try document.removeEffect(id)
    let removedCount = document.history.undoCount
    await controller.shutdown()
    check.expect(
        document.history.undoCount == removedCount && document.effects.isEmpty && controller.outputs[id] == nil,
        message: "retirement cancels and joins the pending gesture without a stale document or output write")
}

@MainActor
private func effectsControllerOnlyState(
    _ fixture: EffectsFixture, entry: PluginCatalogEntry, check: CheckReport.Scoped
) async throws {
    let id = try fixture.add(entry)
    let document = fixture.session.document
    try document.recordPluginState(id, state: effectsState(diagnostic: true))
    try await fixture.controller.openEditor(id)
    guard let instance = fixture.controller.instance(for: id) else { throw EffectsCheckError.fixture }
    check.expect(instance.isEditorOpen, message: "controller opens the real fixture helper editor")
    await effectsElapse(.milliseconds(1200))
    let baseline = await instance.stateDigest()
    var changed = try await instance.state()
    guard changed.controller.count == 112 else { throw EffectsCheckError.fixture }
    changed.controller[8] = 73
    let count = document.history.undoCount
    try await instance.restore(changed)
    let reread = try await instance.state()
    check.expect(
        reread.controller[8] == 73 && reread.component == changed.component,
        message: "diagnostic fixture genuinely changes controller-only bytes and preserves all component flags")
    await effectsElapse(.milliseconds(1200))
    let digest = await instance.stateDigest()
    check.expect(
        digest == baseline && document.history.undoCount == count,
        message: "editor digest polling never records controller-only state changes")
    try await instance.restore(effectsState(pitch: 3, diagnostic: true))
    try await effectsWait { document.history.undoCount == count + 1 }
    check.expect(
        document.effects[0].pluginState?.component.first == 3,
        message: "stable component digest polling records a non-parameter edit as one step")
    await fixture.controller.closeEditor(id)
    check.expect(!instance.isEditorOpen, message: "controller closes the real helper editor")
    try await instance.restore(effectsState(pitch: 5, diagnostic: true))
    await effectsElapse(.milliseconds(1200))
    check.expect(
        document.history.undoCount == count + 1,
        message: "closing the editor makes component-digest observation quiescent")
    try await fixture.controller.openEditor(id)
    try await effectsWait { document.history.undoCount == count + 2 }
    check.expect(
        document.effects[0].pluginState?.component.first == 5,
        message: "reopening starts a fresh stable-digest observation instead of reviving an old polling task")
    try await fixture.controller.render(id, range: TimeRange(startTick: 0, endTick: 24))
    try await instance.restore(effectsState(pitch: 7, diagnostic: true))
    try await effectsWait { document.history.undoCount == count + 3 }
    check.expect(
        document.effects[0].pluginState?.component.first == 7,
        message: "Render rejoins recorder work and restarts editor observation after its exclusive capture")
    await fixture.controller.closeEditor(id)
}

@MainActor
private func effectsStartFault(
    _ fixture: EffectsFixture, id: EffectID, instance: PluginInstance, fault: Int32, check: CheckReport.Scoped
) async throws {
    // Attached inserts process stopped blocks too; fault injection and callback
    // evidence must proceed together rather than assuming restore finishes first.
    let injection = Task { @MainActor in try await instance.restore(effectsState(fault: fault)) }
    do {
        fixture.audio.play()
        if fault == 2 {
            var stalled: BridgeSnapshot?
            var position: UInt64 = 0
            try await effectsWait {
                guard let snapshot = instance.bridgeSnapshot, snapshot.request != snapshot.reply else {
                    stalled = nil
                    return false
                }
                if let stalled, stalled.request == snapshot.request, stalled.reply == snapshot.reply {
                    return fixture.audio.playheadSamples >= position + UInt64(fixture.audio.periodSizeFrames * 4)
                }
                stalled = snapshot
                position = fixture.audio.playheadSamples
                return false
            }
            guard let stalled else { throw EffectsCheckError.fixture }
            let missed = instance.bridgeSnapshot
            check.expect(
                missed?.request == stalled.request && missed?.reply == stalled.reply,
                message:
                    "bounded callback misses let the audio device advance without overwriting a hung bridge request")
        }
        let outcome = await injection.result
        switch outcome {
        case .success:
            break
        case .failure(let error):
            let committed: PluginHostError
            if let transport = error as? HelperProcessError {
                switch transport {
                case .eof, .terminated:
                    guard fault == 1 else { throw error }
                    committed = .native(transport.description)
                case .stoppedResponding, .timeout:
                    guard fault == 2 else { throw error }
                    committed = .stoppedResponding(transport.description)
                case .scannerMissing, .channelCreation, .channelUnlink, .invalidPayload, .notReady, .launch, .native:
                    throw error
                }
            } else if let hostError = error as? PluginHostError {
                switch hostError {
                case .native:
                    guard fault == 1 else { throw error }
                case .stoppedResponding:
                    guard fault == 2 else { throw error }
                }
                committed = hostError
            } else {
                throw error
            }
            guard instance.failure == committed else { throw error }
            let reason = fault == 1 ? "stopped working" : "stopped responding"
            check.expect(
                fixture.controller.status(id) == .crashed(reason),
                message: "injection-time failure retains the exact committed cause and controller crash classification")
        }
    } catch {
        injection.cancel()
        _ = await injection.result
        throw error
    }
}

@MainActor
private func effectsPollingWatchdog(
    _ fixture: EffectsFixture, entry: PluginCatalogEntry, check: CheckReport.Scoped
) async throws {
    let id = try fixture.add(entry)
    try await fixture.controller.openEditor(id)
    try await fixture.controller.setLive(id, true)
    guard let instance = fixture.controller.instance(for: id), instance.isEditorOpen else {
        throw EffectsCheckError.fixture
    }
    let started = ContinuousClock.now
    try await effectsStartFault(fixture, id: id, instance: instance, fault: 2, check: check)
    try await effectsWait { fixture.controller.status(id) == .crashed("stopped responding") }
    check.expect(
        ContinuousClock.now - started < .seconds(4),
        message: "editor digest polling leaves the armed watchdog advancing before the five-second control timeout")
}

@MainActor
private func effectsCancellationAndOwnership(
    _ first: EffectsFixture, second: EffectsFixture, entry: PluginCatalogEntry, check: CheckReport.Scoped
) async throws {
    second.workspace.deactivate()
    first.workspace.activate()
    try await first.ready()
    let id = try first.add(entry, pacing: .realtime)
    try await first.controller.setLive(id, true)
    try await first.controller.openEditor(id)
    guard let instance = first.controller.instance(for: id) else { throw EffectsCheckError.fixture }
    let render = Task { @MainActor in
        try await first.controller.render(id, range: TimeRange(startTick: 0, endTick: 216))
    }
    try await effectsWait {
        if case .rendering(let progress) = first.controller.status(id) { return progress > 0 }
        return false
    }
    first.controller.cancelRender(id)
    if case .success = await render.result { check.fail("cancelled Render published a completion") }
    check.expect(
        instance.liveInsert?.isAttached == true && first.controller.outputs[id] == nil,
        message: "cancelled worker restores Live and discards its result")
    let superseded = Task { @MainActor in
        try await first.controller.render(id, range: TimeRange(startTick: 0, endTick: 216))
    }
    try await effectsWait {
        if case .rendering = first.controller.status(id) { return true }
        return false
    }
    let latest = Task { @MainActor in
        try await first.controller.render(id, range: TimeRange(startTick: 72, endTick: 144))
    }
    if case .success = await superseded.result { check.fail("superseded Render applied") }
    try await latest.value
    check.expect(
        first.controller.outputs[id]?.range == TimeRange(startTick: 72, endTick: 144),
        message: "new request exclusively replaces the older capture and publishes only its range")
    let late = Task { @MainActor in try await first.controller.render(id, range: TimeRange(startTick: 0, endTick: 216))
    }
    try await effectsWait {
        if case .rendering = first.controller.status(id) { return true }
        return false
    }
    first.workspace.deactivate()
    check.expect(!first.controller.isLive(id), message: "tab deactivation synchronously disarms Live")
    second.workspace.activate()
    try await second.ready()
    let peer = try second.add(entry, track: 0)
    try await second.controller.setLive(peer, true)
    guard let peerInstance = second.controller.instance(for: peer) else { throw EffectsCheckError.fixture }
    await first.controller.shutdown()
    if case .success = await late.result { check.fail("retired workspace published its late capture") }
    check.expect(
        !instance.isEditorOpen && instance.liveInsert == nil,
        message: "shutdown awaits worker idle, editor closure and helper reclamation")
    check.expect(
        peerInstance.liveInsert?.isAttached == true && second.controller.isLive(peer),
        message: "outgoing workspace cleanup cannot detach the incoming workspace's same-track insert")
    second.audio.play()
    try await effectsWait {
        second.audio.status.appliedTransport == .playing
            && effectsHeldKeys(second.audio, track: 0)?.contains(60) == true
            && second.audio.playheadSamples > 8_000
    }
    try second.controller.grabPlayed(peer)
    check.expect(
        second.controller.outputs[peer]?.notes.isEmpty == false,
        message: "incoming callback still dispatches after old-owner identity-specific detach acknowledgments")
    second.audio.stop()
    try await effectsWait { second.audio.status.appliedTransport == .stopped }
    second.workspace.suspendCallbacks()
    check.expect(!second.controller.isLive(peer), message: "workspace suspension synchronously disarms Live intent")
    try await effectsWait { peerInstance.liveInsert?.isAttached != true }
    check.expect(
        peerInstance.liveInsert?.isAttached != true,
        message: "suspension awaits renderer acknowledgment before stopping the bridge producer")
    second.workspace.deactivate()
    second.workspace.activate()
    try await second.ready()
    check.expect(!second.controller.isLive(peer), message: "tab reactivation never resurrects desired arming")
}

@MainActor
private func effectsRetiredRenderIsolation(
    _ fixture: EffectsFixture, entry: PluginCatalogEntry, check: CheckReport.Scoped
) async throws {
    let controller = fixture.controller
    let retired = try fixture.add(entry)
    let healthy = try fixture.add(entry, track: 1)
    try await controller.load(retired)
    guard let stalled = controller.instance(for: retired) else { throw EffectsCheckError.fixture }
    try await stalled.restore(effectsState(fault: 2))
    let render = Task { @MainActor in
        try await controller.render(retired, range: TimeRange(startTick: 0, endTick: 24))
    }
    do {
        try await effectsWait {
            guard let snapshot = stalled.bridgeSnapshot else { return false }
            return snapshot.request != snapshot.reply
        }
        try fixture.session.document.removeEffect(retired)
        var commandsFinished = false
        let commands = Task { @MainActor in
            try await controller.setLive(healthy, true)
            try await controller.render(healthy, range: TimeRange(startTick: 0, endTick: 24))
            try await controller.setLive(healthy, false)
            try await controller.setLive(healthy, true)
            commandsFinished = true
        }
        do {
            try await effectsWait { commandsFinished }
            try await commands.value
        } catch {
            commands.cancel()
            _ = await commands.result
            throw error
        }
        guard let pending = stalled.bridgeSnapshot else { throw EffectsCheckError.fixture }
        check.expect(
            pending.request != pending.reply && controller.isLive(healthy)
                && controller.instance(for: healthy)?.liveInsert?.isAttached == true
                && controller.outputs[healthy]?.notes.isEmpty == false,
            message: "healthy B Live and Render finish while removed A's real processing request remains outstanding")
        fixture.audio.play()
        try await effectsWait { effectsHeldKeys(fixture.audio, track: 1)?.contains(60) == true }
        check.expect(
            effectsHeldKeys(fixture.audio, track: 1)?.contains(60) == true,
            message: "retired A cleanup does not block B's consumer-visible engine output")
        fixture.audio.stop()
        try await effectsWait { fixture.audio.status.appliedTransport == .stopped }
        var shutdownStarted = false
        var shutdownFinished = false
        let shutdown = Task { @MainActor in
            shutdownStarted = true
            await controller.shutdown()
            shutdownFinished = true
        }
        try await effectsWait { shutdownStarted }
        let joining = stalled.bridgeSnapshot
        check.expect(
            !shutdownFinished && joining != nil && joining?.request != joining?.reply,
            message: "shutdown still joins removed A rather than dropping its outstanding per-owner cleanup")
        await shutdown.value
        check.expect(
            stalled.bridgeSnapshot == nil && stalled.liveInsert == nil && !stalled.isEditorOpen,
            message: "shutdown returns only after the retired helper and its worker have been reclaimed")
    } catch {
        render.cancel()
        await controller.shutdown()
        _ = await render.result
        throw error
    }
    if case .success = await render.result { check.fail("removed hung A published a late Render result") }
    check.expect(
        controller.outputs[retired] == nil && controller.outputs[healthy] == nil,
        message: "per-owner shutdown clears both outputs without resurrecting the removed effect")
}

@MainActor
private func effectsFailure(
    _ fixture: EffectsFixture, entry: PluginCatalogEntry, fault: Int32, check: CheckReport.Scoped
) async throws {
    let id = try fixture.add(entry)
    let other = try fixture.add(entry, track: 1)
    try await fixture.controller.setLive(id, true)
    try await fixture.controller.setLive(other, true)
    guard let instance = fixture.controller.instance(for: id), let peer = fixture.controller.instance(for: other) else {
        throw EffectsCheckError.fixture
    }
    let saved = fixture.session.document.state
    let started = ContinuousClock.now
    try await effectsStartFault(fixture, id: id, instance: instance, fault: fault, check: check)
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 1)?.contains(60) == true }
    let reason = fault == 1 ? "stopped working" : "stopped responding"
    try await effectsWait { fixture.controller.status(id) == .crashed(reason) }
    let typedFailureMatches: Bool
    switch instance.failure {
    case .native?: typedFailureMatches = fault == 1
    case .stoppedResponding?: typedFailureMatches = fault == 2
    case nil: typedFailureMatches = false
    }
    check.expect(
        typedFailureMatches, message: "the injected processing fault retains its typed helper failure classification")
    check.expect(
        ContinuousClock.now - started < .seconds(5),
        message: "real fixture fault \(fault) reaches bounded \(reason) handling")
    try await effectsWait { instance.liveInsert?.isAttached != true }
    check.expect(
        !fixture.controller.isLive(id) && instance.liveInsert?.isAttached != true,
        message: "helper failure detaches the crashed insert without terminating the app")
    check.expect(
        peer.liveInsert?.isAttached == true && fixture.controller.isLive(other),
        message: "a second helper remains armed after its peer fails")
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 0)?.contains(60) == false }
    check.expect(
        effectsHeldKeys(fixture.audio, track: 0)?.contains(60) == false,
        message: "failed helper leaves no held plugin voice, while legitimate release tails may continue")
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 1)?.contains(60) == true }
    check.expect(
        effectsHeldKeys(fixture.audio, track: 1)?.contains(60) == true,
        message: "the surviving helper continues dispatching real engine voices")
    fixture.audio.seek(sample: 0)
    try await effectsWait {
        effectsHeldKeys(fixture.audio, track: 0)?.contains(40) == true
            && effectsHeldKeys(fixture.audio, track: 1)?.contains(60) == true
    }
    check.expect(
        effectsHeldKeys(fixture.audio, track: 0)?.contains(40) == true,
        message: "failed effect releases its source mask while the other helper keeps sounding")
    check.expect(fixture.session.document.state == saved, message: "crash saves only previously recorded plugin state")
    fixture.audio.stop()
    try await effectsWait { fixture.audio.status.appliedTransport == .stopped }
    try await fixture.controller.reload(id)
    guard let reloaded = fixture.controller.instance(for: id) else { throw EffectsCheckError.fixture }
    check.expect(
        reloaded !== instance && fixture.controller.isLive(id) && reloaded.liveInsert?.isAttached == true,
        message: "manual Reload creates a fresh helper, restores the document and re-arms only the failed Live effect")
    let state = try await reloaded.state()
    check.expect(state.component == effectsState().component, message: "Reload discards the unrecorded fault gesture")
    try await fixture.controller.setLive(id, false)
    try await reloaded.restore(effectsState(fault: fault))
    do {
        try await fixture.controller.render(id, range: TimeRange(startTick: 0, endTick: 24))
        check.fail("a faulting disarmed Render returned output")
    } catch {
        check.expect(error is PluginHostError, message: "real disarmed Render failure propagates the helper fault")
    }
    try await effectsWait { fixture.controller.status(id) == .crashed(reason) }
    check.expect(
        fixture.controller.outputs[id] == nil && fixture.session.document.state == saved,
        message: "faulted Render publishes no late output and leaves the recorded document state unchanged")
    try await fixture.controller.reload(id)
    check.expect(!fixture.controller.isLive(id), message: "Reload does not arm an effect that failed while disarmed")
}

@MainActor
private func effectsActiveShutdown(
    _ fixture: EffectsFixture, entry: PluginCatalogEntry, check: CheckReport.Scoped
) async throws {
    let unknown = try fixture.session.document.addEffect(
        TrackEffectConfig(
            track: 0,
            plugin: PluginEffectConfig(
                modulePath: entry.modulePath + ".missing", classUID: entry.classUID, name: entry.name,
                input: .none, pacing: .offline, prerollBars: 0)))
    do {
        try await fixture.controller.load(unknown)
        check.fail("an unknown plugin was loaded outside the shared catalog")
    } catch {
        if case .unavailable = fixture.controller.status(unknown) {
            check.expect(
                fixture.controller.instance(for: unknown) == nil,
                message: "unknown catalog identities report unavailable without spawning a helper")
        } else {
            check.fail("unknown plugin did not publish unavailable")
        }
    }
    try fixture.session.document.removeEffect(unknown)
    let id = try fixture.add(entry)
    try await fixture.controller.setLive(id, true)
    guard let instance = fixture.controller.instance(for: id) else { throw EffectsCheckError.fixture }
    await fixture.controller.deviceDidRebind()
    check.expect(
        fixture.controller.instance(for: id) === instance && instance.liveInsert?.isAttached == true,
        message: "an active device rebind re-arms the existing instance instead of replacing it")
    try await fixture.controller.openEditor(id)
    fixture.audio.play()
    try await effectsWait { effectsHeldKeys(fixture.audio, track: 0)?.contains(60) == true }
    await fixture.controller.shutdown()
    try await effectsWait {
        let keys = effectsHeldKeys(fixture.audio, track: 0)
        return keys?.allSatisfy { (key: UInt8) in key == 40 } == true
    }
    check.expect(
        instance.liveInsert == nil && !instance.isEditorOpen,
        message: "active shutdown detaches before reclaiming the helper and closes its real editor")
    check.expect(
        !fixture.controller.isLive(id) && fixture.controller.outputs[id] == nil,
        message: "shutdown clears arming and session output without touching the document")
    await fixture.controller.shutdown()
}

@MainActor
private func runEffectsControllerChecks(
    _ report: CheckReport, session: DocumentSession, service: ProjectService, lane: EffectsCheckLane
) {
    let checkID = lane == .headless ? "no-row/miditools/controller" : "no-row/miditools/controller-editor"
    let check = report.scoped(cppID: checkID)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "porydaw-effects-\(UUID().uuidString)")
    let executable = HelperProcess.executableURL
    let fixtures = executable.deletingLastPathComponent().appendingPathComponent("vstfixtures")
    let catalog = PluginCatalog(cacheDirectory: root, scannerURL: executable, standardRoots: [])
    defer {
        catalog.cancelScan()
        do {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
        } catch { check.fail("controller fixture cache cleanup: \(error)") }
    }
    do {
        let (generator, realtime, audio) = try runBlocking {
            await catalog.scan(folders: [fixtures.appendingPathComponent("porydawtestgen.vst3").path])
            guard
                let generator = catalog.entries.first(where: { (entry: PluginCatalogEntry) in entry.name == "TestGen" }
                ),
                let realtime = catalog.entries.first(where: { (entry: PluginCatalogEntry) in
                    entry.name == "TestGenRealtimeOnly"
                })
            else {
                throw EffectsCheckError.fixture
            }
            return (generator, realtime, try await NativeAudio.make())
        }
        defer {
            do {
                try runBlocking { await audio.shutdown() }
            } catch { check.fail("controller fixture audio cleanup: \(error)") }
        }
        @MainActor
        func run(_ body: @escaping @MainActor (EffectsFixture) async throws -> Void) throws {
            try runBlocking {
                let fixture = EffectsFixture(suite: session, service: service, catalog: catalog, audio: audio)
                do {
                    try await fixture.ready()
                    try await body(fixture)
                } catch {
                    await fixture.finish()
                    throw error
                }
                await fixture.finish()
            }
        }
        switch lane {
        case .headless:
            try run { (fixture: EffectsFixture) in
                try await effectsRangesAndRender(fixture, entry: generator, check: check)
            }
            try run { (fixture: EffectsFixture) in
                try await effectsStateHistory(fixture, entry: realtime, check: check)
            }
            try run { (fixture: EffectsFixture) in
                try await effectsRetiredRenderIsolation(fixture, entry: generator, check: check)
            }
            for fault: Int32 in [1, 2] {
                try run { (fixture: EffectsFixture) in
                    try await effectsFailure(fixture, entry: generator, fault: fault, check: check)
                }
            }
        case .editor:
            try run { (fixture: EffectsFixture) in
                try await effectsControllerOnlyState(fixture, entry: generator, check: check)
            }
            try run { (fixture: EffectsFixture) in
                try await effectsPollingWatchdog(fixture, entry: generator, check: check)
            }
            try run { (fixture: EffectsFixture) in
                try await effectsActiveShutdown(fixture, entry: generator, check: check)
            }
            try run { (first: EffectsFixture) in
                first.workspace.deactivate()
                let second = EffectsFixture(suite: session, service: service, catalog: catalog, audio: audio)
                do {
                    try await second.ready()
                    try await effectsCancellationAndOwnership(
                        first, second: second, entry: generator, check: check)
                } catch {
                    await second.finish()
                    throw error
                }
                await second.finish()
            }
        }
    } catch { check.fail("real TrackEffectsController fixture: \(error)") }
}

@MainActor
public func runTrackEffectsControllerChecks(_ report: CheckReport, session: DocumentSession, service: ProjectService) {
    runEffectsControllerChecks(report, session: session, service: service, lane: .headless)
}

@MainActor
public func runTrackEffectsControllerEditorChecks(
    _ report: CheckReport, session: DocumentSession, service: ProjectService
) {
    runEffectsControllerChecks(report, session: session, service: service, lane: .editor)
}
