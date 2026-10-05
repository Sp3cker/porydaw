import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawAppCommands
import PorydawCore
import QtBridge
import QtBridgeCpp

/// The pinned bridge cannot pass a bridged object *into* a slot, so the suite
/// declares the lane's one production `ApplicationSession` as a direct QML
/// child of this object and the bootstrap reaches it through the framework's
/// Swift-child list — the seam `QmlInstantiable` documents and the editor
/// drawer's QML lane already uses.
@MainActor
@QtBridgeable
public final class RollQmlBootstrap: QmlInstantiableStatus {
    private static var stagedProjectRoot = ""

    private var timeSigFixtureIdentity: DocumentIdentity?
    private var releasedDocument: DocumentSession?
    private var releasedGrid: PianoGrid?
    private weak var releasingTab: SongTabSession?
    private var releasingTabId = -1
    private var headerAuditionEvents: [String] = []
    private var headerAuditionForward: ((UInt8, UInt8, UInt8) -> Void)?

    private var allocationProbe: AllocationProbe?
    private var allocationPreparationAttempted = false
    @QtTracked public var allocationWarmup = 0
    @QtTracked public var allocationIterations = 0
    @QtTracked public var allocationError = ""

    /// The runner's scratch directory, staged before Qt builds any QML object.
    public var projectRoot: String = RollQmlBootstrap.stagedProjectRoot
    @QtTracked public var preferences = PreferencesStore()

    public func resetPreferences() -> Bool {
        preferences.resetPreferences()
    }
    public func seedDrawerPreferences(
        velocityVisible: Bool, automationVisible: Bool,
        voiceChangesVisible: Bool, activePage: Int
    ) {
        preferences.setBool(key: "editorDrawer.velocityVisible", value: velocityVisible)
        preferences.setInt(key: "editorDrawer.velocityHeight", value: 160)
        preferences.setBool(key: "editorDrawer.automationVisible", value: automationVisible)
        preferences.setInt(key: "editorDrawer.automationHeight", value: 240)
        preferences.setBool(key: "editorDrawer.voiceChangesVisible", value: voiceChangesVisible)
        preferences.setInt(key: "editorDrawer.voiceChangesHeight", value: 90)
        preferences.setString(key: "editorDrawer.activePage", value: activePage == 1 ? "velocity" : "automations")
    }

    static func stage(projectRoot: String) {
        stagedProjectRoot = projectRoot
    }

    public required init() {}

    public func componentComplete() {}

    /// The suite's production session, declared as this object's QML child.
    private var session: ApplicationSession? {
        qmlChildren.compactMap { $0 as? ApplicationSession }.first
    }

    /// The selected tab's document session: the document's own timeline and
    /// camera, for the deterministic drive seams below.
    private var document: DocumentSession? {
        session?.selectedDocument
    }

    // ---- the run loop and the staged project --------------------------------

    /// Qt Quick Test's wait() pumps Qt but does not service Swift's main-actor
    /// tasks. The suite's `waitForNative` calls this between Qt waits so real
    /// opens, saves and the close walk can complete.
    public func pumpMainRunLoop() {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }

    /// Opens the staged project through the production session path and drives
    /// the asynchronous work to a definite outcome.
    ///
    /// The core session checks pump the run loop the same way: a Qt Quick Test
    /// slot can run outside any Qt event loop, so a main-actor task is only
    /// serviced while something drains the main queue and a merely kicked-off
    /// open would never complete. The wait is bounded, and a failure names the
    /// session's own reason in the lane's captured output.
    public func start(songLabel: String) -> Bool {
        guard let session, !songLabel.isEmpty else { return false }
        session.openProjectAndSong(path: projectRoot, label: songLabel)
        let initialError = session.lastSaveError
        let deadline = Date().addingTimeInterval(RollQmlBootstrap.openTimeout)
        while Date() < deadline {
            if session.projectOpen && session.songOpen { return true }
            if !session.lastSaveError.isEmpty, session.lastSaveError != initialError { break }
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return reportOpenOutcome(session, songLabel: songLabel, initialError: initialError)
    }

    /// Bounded like the windowed harness's own session-open waits.
    private static let openTimeout: TimeInterval = 15

    /// A failure the session reported is a verdict, and the lane must show it as
    /// one. Running out of time is not: the open is still in flight, the suite's
    /// own bounded wait has not run yet, so the lane names what it saw and keeps
    /// the request alive for that wait instead of inventing a second timeout.
    private func reportOpenOutcome(
        _ session: ApplicationSession, songLabel: String,
        initialError: String
    ) -> Bool {
        let failure = session.lastSaveError
        let state = "projectOpen=\(session.projectOpen) songOpen=\(session.songOpen)"
        let reason =
            !failure.isEmpty && failure != initialError
            ? "failed (\(state)): \(failure)"
            : "is still in flight (\(state)) after \(RollQmlBootstrap.openTimeout)s"
        FileHandle.standardError.write(
            Data(
                "swiftroll-window: opening \"\(songLabel)\" at \(projectRoot) \(reason)\n".utf8))
        return failure.isEmpty || failure == initialError
    }

    // ---- opt-in GUI-thread allocation capture -------------------------------

    public func allocationWindowResizeRequested() -> Bool {
        AllocationBenchmarkOptions.requestedScenario == "window-resize"
    }

    /// No ordinary suite calls this: the profiling library is loaded only for
    /// the explicitly requested scenario, once, before any captured operation.
    public func prepareWindowAllocationCapture() -> Bool {
        if allocationPreparationAttempted { return allocationProbe != nil }
        allocationPreparationAttempted = true
        do {
            guard let options = try AllocationBenchmarkOptions.load(for: "window-resize") else {
                allocationError = "window-resize allocation scenario was not requested"
                return false
            }
            let probe = try AllocationProbe.load()
            allocationWarmup = options.warmup
            allocationIterations = options.iterations
            allocationProbe = probe
            return true
        } catch {
            allocationError = "window-resize allocation capture: \(error)"
            return false
        }
    }

    public func resetAllocationCapture() {
        allocationProbe?.reset()
    }

    // No observer property writes or result/string construction at these
    // boundaries. The suite reports identical empty bridge/wait overhead.
    public func beginAllocationCapture() {
        allocationProbe?.begin()
    }

    public func pauseAllocationCapture() {
        allocationProbe?.pause()
    }

    public func reportAllocationCapture(label: String, operations: Int) -> Bool {
        guard let probe = allocationProbe, operations > 0 else {
            allocationError = "window-resize allocation report requires a probe and positive operations"
            return false
        }
        probe.report(label: label, operations: UInt64(operations))
        return true
    }

    /// Observed only after pause: QML's actual plot geometry must have reached
    /// the selected production document's authoritative camera.
    public func allocationCameraViewportMatches(width: Double, height: Double) -> Bool {
        guard let document, width.isFinite, height.isFinite, width > 0, height > 0 else {
            return false
        }
        let camera = document.camera.snapshot
        return abs(camera.viewportWidth - width) < 0.001
            && abs(camera.rollHeight - height) < 0.001
    }

    // ---- the host's own close path ------------------------------------------

    public func hostClosing() -> Bool {
        guard let session, let tab = session.songTabs.selectedPage else { return false }
        releasedDocument = session.selectedDocument
        releasedGrid = tab.grid
        releasingTab = tab
        releasingTabId = tab.tabId
        session.hostClosing()
        return session.songOpen && releasingTab != nil
            && !session.songDockController().songListPresenter().songListings.isEmpty
    }

    public func releasePresentedPage() -> Bool {
        guard let session, releasingTabId >= 0 else { return false }
        session.songTabs.requestClose(tabId: releasingTabId)
        if session.songTabs.pendingCloseId == releasingTabId {
            session.songTabs.confirmDiscard()
        }
        return session.songTabs.tabCount == 0
    }

    public func pageWorkspaceReleased() -> Bool {
        releasingTab == nil
    }

    public func acknowledgeSceneRemoval() -> Bool {
        guard let session else { return false }
        session.acknowledgeGridDetached()
        return !session.songOpen && session.songTabs.tabCount == 0
            && session.songTabs.selectedPage == nil
            && session.songDockController().songListPresenter().songListings.isEmpty
    }

    public func acknowledgeSceneRemovalAgain() -> Bool {
        guard let session else { return false }
        let dock = session.songDockController()
        dock.confirmation = "dispose-idempotence"
        defer { dock.confirmation = "" }
        session.acknowledgeGridDetached()
        return dock.confirmation == "dispose-idempotence"
            && !session.songOpen && session.songTabs.tabCount == 0
    }

    public func releasedDocumentCannotPublish() -> Bool {
        guard let document = releasedDocument, let grid = releasedGrid else { return false }
        defer {
            releasedDocument = nil
            releasedGrid = nil
        }
        guard document.onCameraChange == nil, document.onCameraChangeDetailed == nil,
            document.onChange == nil, document.onPlayback == nil
        else { return false }
        let priorBeatWidth = grid.beatWidth
        let priorRevisionText = grid.appliedRevisionText
        let priorRevision = document.document.revision
        let currentZoom = document.camera.snapshot.pixelsPerBeat
        let moved = document.mutateCamera { $0.setTimeZoom(currentZoom * 2) }
        document.document.setTimeSignature(
            tick: Tick(document.document.ticksPerBeat * 8), numerator: 5, denominatorPower: 2)
        return moved && document.document.revision > priorRevision
            && document.onCameraChange == nil && document.onCameraChangeDetailed == nil
            && document.onChange == nil && document.onPlayback == nil
            && grid.beatWidth == priorBeatWidth
            && grid.appliedRevisionText == priorRevisionText
    }

    public func bridgeStaleSelectionReleased() -> Bool {
        BridgeProbeLifetimeChecks.staleSelectionReleased()
    }

    public func bridgeReturnedRowReleased() -> Bool {
        BridgeProbeLifetimeChecks.returnedRowReleased()
    }

    /// The composition's own cancellation path, so a lane case never starts from
    /// the previous case's live interaction: the grid receives the reason and
    /// the drawer cancels every attached page's interaction in the same call,
    /// which is exactly what a hidden surface does. `true` means no interaction
    /// is live afterwards.
    public func cancelInput() -> Bool {
        guard let session else { return false }
        session.cancelGridInput(reason: 2)
        return !session.drawerPresenter().interactionActive
    }

    public func timeSigFixtureActive() -> Bool {
        timeSigFixtureIdentity != nil
    }

    /// Seeds the real presented document; all following observations read that
    /// same document after QML pointer and key delivery.
    public func seedTimeSigFixture() -> Double {
        guard let document else { return -1 }
        timeSigFixtureIdentity = document.document.history.currentIdentity
        let tick = Tick(document.document.ticksPerBeat * 4)
        document.document.setTimeSignature(tick: tick, numerator: 3, denominatorPower: 2)
        return Double(tick)
    }

    public func restoreTimeSigFixture() -> Bool {
        guard let document, let identity = timeSigFixtureIdentity else { return false }
        let history = document.document.history
        while history.currentIdentity != identity && history.canUndo {
            guard history.undoDocument() else { return false }
        }
        timeSigFixtureIdentity = nil
        return history.currentIdentity == identity
    }

    public func undoTimeSignature() -> Bool {
        document?.document.history.undoDocument() ?? false
    }
    public func redoTimeSignature() -> Bool {
        document?.document.history.redoDocument() ?? false
    }

    public func setTimeSigCursor(tick: Double) -> Bool {
        guard let document, tick.isFinite, tick >= 0 else { return false }
        document.editCursor = TimeDefaults.tick(from: tick)
        return true
    }

    public func setInterveningTimeSignature(tick: Double) -> Bool {
        guard let document, tick.isFinite, tick >= 0 else { return false }
        document.document.setTimeSignature(
            tick: TimeDefaults.tick(from: tick), numerator: 5, denominatorPower: 2)
        return true
    }

    public func timeSigBytes() -> String {
        guard let document, let snapshot = try? document.document.captureSave()
        else { return "" }
        return Data(snapshot.bytes).base64EncodedString()
    }

    public func timeSigRevision() -> Double {
        Double(document?.document.revision ?? 0)
    }

    public func timeSigUndoIndex() -> Int {
        document?.document.history.undoIndex ?? -1
    }

    public func timeSigUndoCount() -> Int {
        document?.document.history.undoCount ?? -1
    }

    public func timeSigNumerator(tick: Double) -> Int {
        guard let document, tick.isFinite, tick >= 0 else { return -1 }
        return document.document.timeSignatures.first {
            Double($0.tick) == tick
        }.map { Int($0.numerator) } ?? -1
    }

    public func timeSigDenominatorPower(tick: Double) -> Int {
        guard let document, tick.isFinite, tick >= 0 else { return -1 }
        return document.document.timeSignatures.first {
            Double($0.tick) == tick
        }.map { Int($0.denominatorPower) } ?? -1
    }

    public func timeSigSegmentStart(tick: Double) -> Double {
        Double(timeSigSegment(tick: tick)?.start ?? TimeDefaults.noTick)
    }

    public func timeSigSegmentBeats(tick: Double) -> Int {
        Int(timeSigSegment(tick: tick)?.beatsPerBar ?? 0)
    }

    public func timeSigSegmentBeatTicks(tick: Double) -> Int {
        Int(timeSigSegment(tick: tick)?.beatTicks ?? 0)
    }

    @QtIgnored
    private func timeSigSegment(tick: Double) -> GridSegment? {
        guard let document, tick.isFinite, tick >= 0 else { return nil }
        let song = document.document
        let axis = TimeAxis(
            map: TimeMap(
                ticksPerBeat: UInt32(song.ticksPerBeat),
                timeSigs: song.timeSignatures.map {
                    TimeSigPoint(
                        tick: $0.tick, numerator: $0.numerator,
                        denomPow2: $0.denominatorPower)
                }))
        return axis.segmentAt(TimeDefaults.tick(from: tick))
    }

    public func timeSigTicksPerBeat() -> Int {
        document?.document.ticksPerBeat ?? 0
    }

    /// `EditCommand.setVelocity`'s canonical value, so no case copies the table.
    public func setVelocityCommand() -> Int { EditCommand.setVelocity.rawValue }

    // ---- shared playhead drive ----------------------------------------------
    //
    // Deterministic lane controls for the one production playhead owner — the
    // Swift-side equivalents of the `pd_check_playhead_*` cdecls the
    // swiftrollgated lane called. The offscreen lane's native playhead never
    // advances (the audio engine moves it in its device callback), so a case
    // presents the authoritative observation itself through the production
    // presenter instead of racing a polling task that could only re-present a
    // stopped position. No clock, no second presenter and no production test
    // branch is involved.

    /// Stops the production polling task. `true` means a task had been running.
    public func pausePlayheadPolling() -> Bool {
        guard let presenter = session?.playheadPresenter() else { return false }
        let wasPolling = presenter.isPolling
        presenter.stopPolling()
        return wasPolling
    }

    /// Restarts the production polling task. `true` means it is polling again.
    public func resumePlayheadPolling() -> Bool {
        guard let presenter = session?.playheadPresenter(), presenter.timelineAttached else {
            return false
        }
        presenter.startPolling()
        return presenter.isPolling
    }

    /// One authoritative `(sample, transport)` observation, presented by the
    /// same production owner the polling task drives. `true` means the
    /// published presentation changed.
    public func presentPlayheadObservation(sample: Double, transport: Int) -> Bool {
        guard let presenter = session?.playheadPresenter(), sample.isFinite, sample >= 0 else {
            return false
        }
        return presenter.observe(sample: UInt64(sample), transport: Int32(transport))
    }

    /// One synthetic observation at `tick`, mapped through the attached
    /// document's own tempo map — the check-side `setPlayheadSample(
    /// sampleForTick(t))`. `true` means the presentation changed.
    public func presentPlayheadTick(tick: Double, transport: Int) -> Bool {
        guard let document, tick.isFinite, tick >= 0 else { return false }
        let sample = document.timeline.sample(for: TimeDefaults.tick(from: tick))
        guard let presenter = session?.playheadPresenter() else { return false }
        return presenter.observe(sample: sample, transport: Int32(transport))
    }

    /// Enables or disables playhead follow — the check-side `setFollowPlayhead`.
    public func setFollowPlayhead(enabled: Bool) -> Bool {
        guard let presenter = session?.playheadPresenter() else { return false }
        presenter.setFollowEnabled(enabled)
        return true
    }

    /// The shared presenter's own published-change count: the comparison
    /// baseline for a page's diagnostic, because the presenter publishes only a
    /// changed presentation.
    public func publishedPlayheadPresentations() -> Double {
        Double(session?.playheadPresenter().presentationCount ?? 0)
    }

    // ---- owner-aware hover guides --------------------------------------------

    /// Publishes a hover guide for one owner at a plot-local contentX — the
    /// owner-aware entry production QML never calls.
    public func guideHover(owner: Int, contentX: Double) -> Bool {
        guard let session else { return false }
        session.playheadGuidesPresenter().updateHover(owner: owner, contentX: contentX)
        return true
    }

    /// Clears one owner's hover guide.
    public func guideClear(owner: Int) -> Bool {
        guard let session else { return false }
        session.playheadGuidesPresenter().clearHover(owner: owner)
        return true
    }

    // ---- the document's camera and timeline -----------------------------------

    /// Sets the camera's horizontal zoom — the deterministic `pxPerBeat` the
    /// follow-scroll check parks on.
    public func setCameraTimeZoom(pxPerBeat: Double) -> Bool {
        guard let document, pxPerBeat.isFinite, pxPerBeat > 0 else { return false }
        return document.mutateCamera { $0.setTimeZoom(pxPerBeat) }
    }

    /// The attached document's timeline length in ticks.
    public func timelineLengthTicks() -> Double {
        Double(document?.timeline.lengthTicks ?? 0)
    }

    /// The plot-local projection of `tick` through the session camera.
    public func cameraContentX(tick: Double) -> Double {
        document?.camera.contentX(tick: tick) ?? 0
    }

    /// The session camera's pixels-per-tick.
    public func cameraPxPerTick() -> Double {
        document?.camera.pixelsPerTick ?? 0
    }

    public func presentHeaderActivity(
        track: Int, left: Int, right: Int,
        playing: Bool
    ) -> Bool {
        guard let session else { return false }
        pushTrackActivity(
            presenter: session.trackHeadersPresenter(), track: track,
            left: left, right: right, elapsed: 60, playing: playing)
        return true
    }

    public func observeHeaderVoiceAudition() -> Bool {
        guard let picker = session?.headerVoicePickerModel() else { return false }
        if headerAuditionForward == nil {
            let forward = picker.onAuditionVoice
            headerAuditionForward = forward
            picker.onAuditionVoice = { [weak self] program, key, velocity in
                self?.headerAuditionEvents.append("\(program):\(key):\(velocity)")
                forward?(program, key, velocity)
            }
        }
        headerAuditionEvents.removeAll(keepingCapacity: true)
        return true
    }

    public func headerVoiceAuditionEvents() -> String {
        headerAuditionEvents.joined(separator: ",")
    }

    public func stopObservingHeaderVoiceAudition() {
        guard let forward = headerAuditionForward else { return }
        session?.headerVoicePickerModel().onAuditionVoice = forward
        headerAuditionForward = nil
    }

    public func seedDuplicateInitialVoice(track: Int, first: Int, last: Int) -> Bool {
        guard let document, (0...127).contains(first), (0...127).contains(last),
            (0..<document.document.engineTracks.usedTrackCount).contains(track)
        else { return false }
        let tick = document.document.lanePoints(track: track, lane: .voice).first?.tick ?? 0
        document.document.writeLane(
            track: track, lane: .voice, from: tick, through: tick,
            points: [
                LaneWrite(tick: tick, value: first),
                LaneWrite(tick: tick, value: last),
            ])
        return true
    }

    public func moveHeaderTrack(from: Int, to: Int) -> Bool {
        guard let document else { return false }
        return document.document.moveTrack(from, to: to)
    }

    @QtIgnored
    public func pushTrackActivity(
        presenter: TrackHeadersPresenter, track: Int,
        left: Int, right: Int, elapsed: Double,
        playing: Bool
    ) {
        precondition(
            (0..<16).contains(track) && (0...255).contains(left)
                && (0...255).contains(right))
        var levels = Array(repeating: AudioActivityLevel(), count: 16)
        levels[track] = AudioActivityLevel(left: UInt8(left), right: UInt8(right))
        presenter.advanceActivity(
            levels: levels, elapsedSeconds: Float(elapsed),
            playing: playing)
    }
}
