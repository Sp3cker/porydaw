import Foundation
import PorydawApp
import PorydawAppAudio
import PorydawAppCommands
import PorydawCore
import QtBridge
import QtBridgeCpp

/// QML-facing bridge for the lane: the staged scratch paths, the accumulated
/// page-cancellation count, and every test page the container hosts.
///
/// The pinned bridge cannot pass a bridged object *into* a slot (only
/// `Bool`/`Int`/`UInt`/`Double`/`Float`/`String`/`[String]`/`[String: QVariantSettable]`
/// are extractable), so the suite declares the lane's one production
/// `ApplicationSession` as a direct QML child of this object and the bootstrap
/// reaches it through the framework's Swift-child list — the seam
/// `QmlInstantiable` documents and the QtBridge quick-test suite verifies.
@MainActor
@QtBridgeable
public final class EditorQmlBootstrap: QmlInstantiableStatus {
    private static var stagedProjectRoot = ""
    static var stagedSongLabel = ""
    static var stagedProfile = ""
    static var stagedProfileDpr = 0.0
    static var stagedProfileFontPx = 0
    private static var stagedProfilePanes: [String] = []
    private static var stagedPhase = ""

    static func stage(projectRoot: String) {
        stagedProjectRoot = projectRoot
    }

    /// The song this process opened from the staged project: the fixture identity
    /// every profile artifact records is derived from it, in the child that wrote
    /// the record and in the parent that verifies it.
    static func stageSongLabel(_ label: String) {
        stagedSongLabel = label
    }

    /// What this process staged and opened, for the parent's own copy of the facts
    /// a profile artifact's fixture identity is derived from.
    static var stagedProject: (root: String, label: String) {
        (stagedProjectRoot, stagedSongLabel)
    }

    /// The reference profile this process renders: set only in a profile child,
    /// before any QML object exists.
    static func stageProfile(profile: String, dpr: Double, fontPx: Int, panes: [String]) {
        stagedProfile = profile
        stagedProfileDpr = dpr
        stagedProfileFontPx = fontPx
        stagedProfilePanes = panes
    }

    /// The lane phase this process runs: `""` for the production phase and
    /// `"container"` for the container child. Staged before any QML object
    /// exists, exactly like the profile, because the phase decides what the
    /// composition mounts with.
    static func stagePhase(_ phase: String) {
        stagedPhase = phase
    }

    /// `"container"` in the container child, `""` in the production phase. Stored
    /// because the bridged property table carries stored properties, and the
    /// phase is fixed before this object exists.
    public var lanePhase: String = EditorQmlBootstrap.stagedPhase
    @QtTracked public var preferences = PreferencesStore()

    public func resetPreferences() -> Bool {
        preferences.resetPreferences()
    }

    /// The artifact path stem for one profile pane, shared by the child that
    /// writes it and the parent that verifies it.
    static func profileArtifactPath(scratch: String, profile: String, pane: String) -> String {
        URL(fileURLWithPath: scratch, isDirectory: true)
            .appendingPathComponent("reference-\(profile)-\(pane)").path
    }

    /// The runner's scratch directory, staged before Qt builds any QML object.
    public var projectRoot: String = EditorQmlBootstrap.stagedProjectRoot

    // ---- reference profile capture -----------------------------------------

    /// `true` only inside a profile child, so the ordinary single run skips the
    /// capture case instead of multiplying the suite. Stored for the same reason
    /// as `lanePhase`: the profile is staged before this object exists.
    public var profileActive: Bool = !EditorQmlBootstrap.stagedProfile.isEmpty
    public var profileName: String = EditorQmlBootstrap.stagedProfile
    public var profileDpr: Double = EditorQmlBootstrap.stagedProfileDpr
    public var profileFontPx: Int = EditorQmlBootstrap.stagedProfileFontPx
    public var profilePanes: [String] = EditorQmlBootstrap.stagedProfilePanes

    /// `file://` URL the pane's PNG is written to.
    public func profilePngUrl(pane: String) -> String {
        guard !pane.isEmpty else { return "" }
        return URL(fileURLWithPath: EditorQmlBootstrap.profileArtifactPath(
            scratch: projectRoot, profile: EditorQmlBootstrap.stagedProfile, pane: pane)).absoluteString
            + ".png"
    }

    /// Read-only legacy geometry; captures remain in the runner scratch directory.
    public func trackHeaderReferenceJson() -> String {
        guard EditorQmlLane.referenceProfiles.contains(where: { $0.name == profileName })
        else { return "" }
        let url = URL(fileURLWithPath: EditorQmlPaths.testDirectory, isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/visual/macos-\(profileName)/quick/vanilla/track-headers.json")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    public func writeProfileMetadata(pane: String, observedDpr: Double, observedFontPx: Double,
                                     drawnRoot: String, logicalWidth: Double, logicalHeight: Double,
                                     regionX: Int, regionY: Int,
                                     regionWidth: Int, regionHeight: Int) -> Bool {
        writeProfileMetadataImpl(pane: pane, observedDpr: observedDpr, observedFontPx: observedFontPx,
                                 drawnRoot: drawnRoot, logicalWidth: logicalWidth,
                                 logicalHeight: logicalHeight, regionX: regionX, regionY: regionY,
                                 regionWidth: regionWidth, regionHeight: regionHeight)
    }

    // ---- the document-bound page's own lifecycle ---------------------------

    /// Detaches the current document's page from its kind's slot through the real
    /// presenter, so a container-only case can attach its own test page. The page
    /// owner stays retained by the session, exactly as it does across a hide.
    public func detachProductionSection(kind: Int) -> Bool {
        guard let session, let sectionKind = DrawerSectionKind(rawValue: kind) else { return false }
        let page: EditorDrawerPage
        switch sectionKind {
        case .velocity: page = session.velocityPage()
        case .voiceChanges: page = session.voiceChangesPage()
        case .automation: page = session.automationPage()
        }
        session.drawerPresenter().detachSection(page)
        return !session.drawerPresenter().section(kind: kind).available
    }

    /// Re-attaches the session's retained page to its slot. `true` means the
    /// kind is available again.
    public func attachProductionSection(kind: Int) -> Bool {
        guard let session, let sectionKind = DrawerSectionKind(rawValue: kind) else { return false }
        let page: EditorDrawerPage
        switch sectionKind {
        case .velocity: page = session.velocityPage()
        case .voiceChanges: page = session.voiceChangesPage()
        case .automation: page = session.automationPage()
        }
        session.drawerPresenter().attachSection(page)
        return session.drawerPresenter().section(kind: kind).available
    }

    public func hostClosing() -> Bool {
        guard let session else { return false }
        session.hostClosing()
        return session.songOpen
    }

    public func acknowledgeSceneRemoval() -> Bool {
        guard let session else { return false }
        session.acknowledgeGridDetached()
        return !session.songOpen
    }

    /// The document-bound Velocity page for the lane's Swift-side reads. The QML
    /// cases reach the same object through `applicationSession.velocityPage()`,
    /// which is the production accessor.
    @QtIgnored
    public func velocityPage() -> Optional<VelocityPage> { session?.velocityPage() }

    /// `EditCommand.setVelocity`'s canonical value, so no case copies the table.
    public func setVelocityCommand() -> Int { EditCommand.setVelocity.rawValue }

    /// The page's content-build diagnostic: `UInt64` is not a bridge type, so the
    /// lane reads it as a number it can compare.
    public func velocityContentBuilds() -> Double {
        Double(session?.velocityPage().contentBuildCount ?? 0)
    }

    /// The page's shared-playhead presentation diagnostic.
    public func velocityPlayheadPresentations() -> Double {
        Double(session?.velocityPage().playheadPresentationCount ?? 0)
    }

    /// The page's live selection as identity text: the lane's cases act on the
    /// note the production selection path actually selected.
    public func velocitySelectedNoteIds() -> String {
        session?.velocityPage().selectedNoteIdText() ?? ""
    }

    /// The presented voice-context span's end tick: a playhead case presents
    /// inside it so a rebuild can only come from a real content change.
    public func velocityContextEndTick() -> Double {
        Double(session?.velocityPage().presentedContextEndTick ?? TimeDefaults.noTick)
    }

    /// The presented voice-context slot, so a case can prove it never changed.
    public func velocityPresentedSlot() -> Int {
        session?.velocityPage().presentedContextSlot ?? -1
    }

    /// The shared presenter's own published-change count: the comparison baseline
    /// for the page's diagnostic, because the presenter publishes only a changed
    /// presentation.
    public func publishedPlayheadPresentations() -> Double {
        Double(session?.playheadPresenter().presentationCount ?? 0)
    }

    /// The page's published unsupported-context flag.
    public func velocityContextUnsupported() -> Bool {
        session?.velocityPage().contextUnsupported ?? false
    }

    // ---- the production Voice Changes page ---------------------------------

    /// The document-bound Voice Changes page for the lane's Swift-side reads.
    /// The QML cases reach the same object through
    /// `applicationSession.voiceChangesPage()`, which is the production accessor.
    @QtIgnored
    public func voiceChangesPage() -> Optional<VoiceChangesPage> { session?.voiceChangesPage() }

    /// The page's content-build diagnostic: `UInt64` is not a bridge type, so the
    /// lane reads it as a number it can compare.
    public func voiceContentBuilds() -> Double {
        Double(session?.voiceChangesPage().contentBuildCount ?? 0)
    }

    /// The page's shared-playhead presentation diagnostic.
    public func voicePlayheadPresentations() -> Double {
        Double(session?.voiceChangesPage().playheadPresentationCount ?? 0)
    }

    /// The presented voice-context span's end tick: a playhead case presents
    /// inside it so a rebuild can only come from a real content change.
    public func voiceContextEndTick() -> Double {
        Double(session?.voiceChangesPage().presentedContextEndTick ?? TimeDefaults.noTick)
    }

    /// The presented voice-context slot, so a case can prove it never changed.
    public func voicePresentedSlot() -> Int {
        session?.voiceChangesPage().presentedContextSlot ?? -1
    }

    private var auditionEvents: [String] = []
    private var auditionObserverInstalled = false
    private var auditionForward: ((UInt8, UInt8, UInt8) -> Void)?

    /// Observes production pointer delivery while retaining the real audio sink.
    /// Callback evidence is not proof of audible native output.
    public func observeVoiceAudition() -> Bool {
        guard let page = session?.voiceChangesPage() else { return false }
        if !auditionObserverInstalled {
            let forward = page.onAuditionVoice
            auditionForward = forward
            page.onAuditionVoice = { [weak self] program, key, velocity in
                self?.auditionEvents.append("\(program):\(key):\(velocity)")
                forward?(program, key, velocity)
            }
            auditionObserverInstalled = true
        }
        auditionEvents.removeAll(keepingCapacity: true)
        return true
    }

    public func voiceAuditionEvents() -> String {
        auditionEvents.joined(separator: ",")
    }

    public func stopObservingVoiceAudition() {
        guard auditionObserverInstalled else { return }
        session?.voiceChangesPage().onAuditionVoice = auditionForward
        auditionForward = nil
        auditionObserverInstalled = false
    }

    // ---- the production Automation page ------------------------------------

    /// The document-bound Automation page for the lane's Swift-side reads. The
    /// QML cases reach the same object through
    /// `applicationSession.automationPage()`, which is the production accessor.
    @QtIgnored
    public func automationPage() -> Optional<AutomationPage> { session?.automationPage() }

    /// The page's content-build diagnostic: `UInt64` is not a bridge type, so the
    /// lane reads it as a number it can compare. A shared-playhead-only update
    /// must never move it.
    public func automationContentBuilds() -> Double {
        Double(session?.automationPage().contentBuildCount ?? 0)
    }

    /// The page's shared-playhead presentation diagnostic.
    public func automationPlayheadPresentations() -> Double {
        Double(session?.automationPage().playheadPresentationCount ?? 0)
    }

    /// The live document revision, so a case asserts that a refused or cancelled
    /// interaction published none.
    public func automationDocumentRevision() -> Double {
        Double(session?.automationPage().documentRevision ?? 0)
    }

    /// The page's hover publication diagnostic.
    public func automationHoverBuilds() -> Double {
        Double(session?.automationPage().hoverBuildCount ?? 0)
    }

    /// One production undo (`redo: false`) or redo, with the lane's own run-loop
    /// pump: the session's request is asynchronous, and the offscreen lane drains
    /// main-actor work the same way its own session open does. `true` means the
    /// session reported the request back, so the history really moved.
    public func requestAutomationUndo() -> Bool { requestHistory(redo: false) }

    public func requestAutomationRedo() -> Bool { requestHistory(redo: true) }


    /// The page's live interaction fact, read from the owner the container's
    /// follow gate reads.
    public func automationInteractionActive() -> Bool {
        session?.automationPage().interactionActive ?? false
    }

    /// The frozen revision or confirmation an interaction captured, or `-1` when
    /// nothing is frozen: the lane's proof that a cancelled prompt leaves no
    /// frozen revision behind.
    public func automationFrozenRevision() -> Double {
        guard let revision = session?.automationPage().frozenRevision else { return -1 }
        return Double(revision)
    }

    /// The active parameter's written-event count in the document, so a case can
    /// tell an empty lane from an occupied one without copying lane policy.
    public func automationLaneEventCount() -> Int {
        guard let page = session?.automationPage(), let track = page.activeTrackIndex else {
            return -1
        }
        return page.laneEventCount(track: track)
    }

    /// The active selector index the page published.
    public func automationActiveParameterIndex() -> Int {
        session?.automationPage().activeParameterIndex ?? -1
    }

    /// The ghost-pinned catalog indexes the page published, comma-separated.
    public func automationGhostParameters() -> String {
        guard let page = session?.automationPage() else { return "" }
        return page.firstGhostText
    }

    /// The first per-track parameter whose lane carries written events in the
    /// staged song, or -1.
    public func automationTabWithEvents() -> Int {
        guard let page = session?.automationPage() else { return -1 }
        return page.firstCatalogIndex { !$0.isTempo && page.catalogEventCount($0) > 0 } ?? -1
    }

    /// The first per-track parameter whose lane is empty, or -1.
    public func automationEmptyTab() -> Int {
        guard let page = session?.automationPage() else { return -1 }
        return page.firstCatalogIndex { !$0.isTempo && page.catalogEventCount($0) == 0 } ?? -1
    }

    /// The published tab labels, comma-separated, so a case compares the drawn
    /// selector against the same catalog the page published.
    public func automationTabLabels() -> String {
        guard let page = session?.automationPage() else { return "" }
        return page.publishedTabs.map(\.label).joined(separator: ",")
    }

    /// Whether the prompt surface is open on the page owner.
    public func automationPromptOpen() -> Bool {
        session?.automationPage().promptOpen ?? false
    }

    /// Whether a menu is open on the page owner, which is the fact the modal
    /// surface is driven by.
    public func automationMenuOpen() -> Bool {
        session?.automationPage().menuOpen ?? false
    }

    /// The open menu's captured action ids, comma-separated, and `""` when no
    /// menu is open.
    public func automationMenuActions() -> String {
        guard let page = session?.automationPage() else { return "" }
        return page.menuRowActions.map(String.init).joined(separator: ",")
    }

    /// The ticks of the active parameter's written events, comma-separated.
    public func automationLaneTicks() -> String {
        guard let page = session?.automationPage() else { return "" }
        return page.activeLaneTicks.map(String.init).joined(separator: ",")
    }

    /// The active parameter's written `tick:value` pairs, comma-separated.
    public func automationLaneValues() -> String {
        guard let page = session?.automationPage() else { return "" }
        return page.activeLaneValues.joined(separator: ",")
    }

    /// The selector index of the Pan parameter, so a case drives the neutral-snap
    /// row through the same catalog the selector publishes.
    public func automationPanIndex() -> Int {
        guard let page = session?.automationPage() else { return -1 }
        return page.catalogIndex(of: .controlChange(track: 0, controller: TimeDefaults.ccPan))
    }

    /// The selector index of the Volume parameter.
    public func automationVolumeIndex() -> Int {
        guard let page = session?.automationPage() else { return -1 }
        return page.catalogIndex(of: .controlChange(track: 0, controller: TimeDefaults.ccVolume))
    }

    /// The tick-zero tempo in BPM, or `-1` when the stream holds none.
    public func automationTempoBpm() -> Int {
        session?.automationPage().tempoBpmAtTickZero ?? -1
    }

    /// The tap session's tap count and draft, so a case can tell a live session
    /// from a reset one.
    public func automationTapCount() -> Int {
        session?.automationPage().tapTempoSession.tapCount ?? 0
    }

    public func automationTapDraftBpm() -> Int {
        session?.automationPage().tapTempoSession.draftBpm ?? 0
    }

    /// The page's published tap-tempo idle window, so a case waits exactly the
    /// deadline the owner published.
    public func automationTapIdleCommitMs() -> Int {
        session?.automationPage().tapTempoIdleCommitMs ?? 0
    }

    /// The page's published explicit time selection as `start:end`, or `""`.
    public func automationSelectionRange() -> String {
        guard let page = session?.automationPage(), let selection = page.selection,
              selection.isActive else { return "" }
        return "\(selection.range.startTick):\(selection.range.endTick)"
    }

    /// The page's published lane clip availability, so a case can prove the
    /// lane menu's Paste row is live only when the accepted clipboard holds this
    /// parameter.
    public func automationLaneClipAvailable() -> Bool {
        session?.automationPage().laneClipAvailable ?? false
    }

    /// A deterministic cadence through the page's own captured tap session, so a
    /// case lands an exact tapped average without a wall-clock wait: `taps` taps,
    /// each `gapMs` after the one before it.
    public func automationTapCadence(gapMs: Int, taps: Int) -> Bool {
        guard let page = session?.automationPage(), taps > 0, gapMs >= 0 else { return false }
        var now: Int64 = 0
        for _ in 0..<taps {
            page.tapTempoTap(atMilliseconds: now)
            now += Int64(gapMs)
        }
        return true
    }

    /// The idle deadline for the session above, landed through the page's own
    /// route. `true` means one tempo edit was written.
    public func automationTapIdleElapsed() -> Bool {
        session?.automationPage().tapTempoIdleElapsed() ?? false
    }

    /// The context tick the Voice Changes page last presented, so a case can
    /// present inside the span it is measuring.
    public func voicePresentedTick() -> Double {
        Double(session?.voiceChangesPage().presentedContextTick ?? 0)
    }

    /// The tick the open picker captured: a lane case chooses a column whose
    /// snapped tick holds no change, so its acceptance is an insertion rather
    /// than the production value replacement at an occupied tick.
    public func voicePickerTargetTick() -> Double {
        Double(session?.voiceChangesPage().pickerTargetTick ?? TimeDefaults.noTick)
    }

    /// The ticks of the published voice-change markers, comma-separated, so a
    /// lane case can tell an occupied lane tick from a free one.
    public func voiceMarkerTicks() -> String {
        guard let page = session?.voiceChangesPage() else { return "" }
        return page.publishedMarkers.map { "\(Tick($0.tick))" }.joined(separator: ",")
    }

    /// The composition's own cancellation path, so a lane case never starts from
    /// the previous case's live interaction: the grid receives the reason and the
    /// drawer cancels every attached page's interaction in the same call, which
    /// is exactly what a hidden surface does. `true` means no interaction is
    /// live afterwards.
    public func cancelInput() -> Bool {
        guard let session else { return false }
        session.cancelGridInput(reason: 2)
        return !session.drawerPresenter().interactionActive
    }

    /// Every `cancelSectionInteraction()` the container performed on a test
    /// page this bootstrap created, detach-cancels included.
    public var pageCancelCount: Int = 0

    @QtIgnored var testPages: [DrawerSectionKind: DrawerTestPage] = [:]
    @QtIgnored var testMaximums: [DrawerSectionKind: Int] = [:]

    public required init() {}

    public func componentComplete() {}
    public func start(songLabel: String) -> Bool { startImpl(songLabel: songLabel) }
    public func attachTestSection(kind: Int, contentUrl: String) -> Bool {
        attachTestSectionImpl(kind: kind, contentUrl: contentUrl)
    }
    public func detachTestSection(kind: Int) { detachTestSectionImpl(kind: kind) }





    /// Test-only policy knob for the voice-changes spill case: declares a
    /// maximum body height (logical pixels) for that kind; `0` clears it.
    public func setTestSectionMaximumBodyHeight(kind: Int, maximum: Int) {
        guard let sectionKind = DrawerSectionKind(rawValue: kind) else { return }
        if maximum > 0 {
            testMaximums[sectionKind] = maximum
        } else {
            testMaximums.removeValue(forKey: sectionKind)
        }
        testPages[sectionKind]?.setMaximumBodyHeight(maximum > 0 ? maximum : nil)
    }

    var session: ApplicationSession? {
        qmlChildren.compactMap { $0 as? ApplicationSession }.first
    }

    // ---- shared playhead drive ---------------------------------------------
    //
    // Deterministic lane controls for the one production playhead owner. The
    // offscreen lane's native playhead never advances (the audio engine moves it
    // in its device callback), so a case presents the authoritative observation
    // itself through the production presenter instead of racing a polling task
    // that could only re-present a stopped position. No clock, no second
    // presenter and no production test branch is involved.

    /// Stops the production polling task. `true` means a task had been running.
    public func pausePlayheadPolling() -> Bool {
        guard let presenter = session?.playheadPresenter() else { return false }
        let wasPolling = presenter.isPolling
        presenter.stopPolling()
        return wasPolling
    }

    public func presentHeaderActivity(track: Int, left: Int, right: Int,
                                      playing: Bool) -> Bool {
        precondition((0..<16).contains(track) && (0...255).contains(left)
                     && (0...255).contains(right))
        guard let session else { return false }
        var levels = Array(repeating: AudioActivityLevel(), count: 16)
        levels[track] = AudioActivityLevel(left: UInt8(left), right: UInt8(right))
        session.trackHeadersPresenter().advanceActivity(levels: levels,
                                                        elapsedSeconds: 60, playing: playing)
        return true
    }

    /// Restarts the production polling task. `true` means it is polling again.
    public func resumePlayheadPolling() -> Bool {
        guard let presenter = session?.playheadPresenter(), presenter.timelineAttached else {
            return false
        }
        presenter.startPolling()
        return presenter.isPolling
    }

    /// One authoritative `(sample, transport)` observation, presented by the same
    /// production owner the polling task drives. `true` means the published
    /// presentation changed.
    public func presentPlayheadObservation(sample: Double, transport: Int) -> Bool {
        guard let presenter = session?.playheadPresenter(), sample.isFinite, sample >= 0 else {
            return false
        }
        return presenter.observe(sample: UInt64(sample), transport: Int32(transport))
    }

    /// Sets the test page's own interaction through the real page seam the
    /// container reads. `true` means the page now reports it.
    public func setTestSectionInteraction(kind: Int, active: Bool) -> Bool {
        guard let sectionKind = DrawerSectionKind(rawValue: kind),
              let page = testPages[sectionKind] else { return false }
        page.setInteractionActive(active)
        return page.interactionActive == active
    }
}
