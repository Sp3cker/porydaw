import Foundation
import PorydawCore
import PorydawAppPresentation
import PorydawAppAudio
import PorydawDocument
import QtBridge

// The shared playhead: one playback-position presentation for the whole editor
// surface. `ApplicationSession` retains exactly one presenter; the roll plot and
// every visible drawer body render a clipped segment from that one publication.
//
// Audio callback snapshots anchor display-frame projection through the canonical
// playback timeline and current camera. Polling drives semantic pages and
// telemetry, plus discrete non-playing position and transport changes.

// MARK: - Authoritative observation

/// A temporary playback window in document ticks; no tick means stopped preview.
public struct SharedPlayheadPreview: Equatable, Sendable {
    public let start: Tick
    public let end: Tick
    public let tick: Double?

    public init(start: Tick, end: Tick, tick: Double? = nil) {
        self.start = start
        self.end = end
        self.tick = tick
    }
}

/// One authoritative transport observation: the sample position and raw
/// transport value the native audio service reports. The presenter never
/// derives either from a clock.
public struct SharedPlayheadObservation: Equatable, Sendable {
    public var sample: UInt64
    public var transport: Int32
    public var preview: SharedPlayheadPreview?

    public init(sample: UInt64, transport: Int32, preview: SharedPlayheadPreview? = nil) {
        self.sample = sample
        self.transport = transport
        self.preview = preview
    }

    public var playing: Bool { SharedPlayheadPolicy.isPlaying(transport: transport) }

    public var displayTransport: Int32 {
        preview?.tick == nil ? transport : SharedPlayheadPolicy.playingTransport
    }

    public func displayTick(in timeline: borrowing PlaybackTimeline) -> Double {
        preview?.tick ?? timeline.tick(for: sample)
    }
}

// MARK: - Aggregate interaction

/// The facts that suspend follow-scroll: a live roll gesture, the drawer's
/// aggregate (chrome resize or an attached page's own interaction), and an
/// explicit temporary suspension a page raises while it owns a prompt or a drag
/// outside the two owners.
public struct SharedPlayheadInteractions: Equatable, Sendable {
    public var gridActive: Bool
    public var drawerActive: Bool
    public var explicitSuspension: Bool

    public init(
        gridActive: Bool = false, drawerActive: Bool = false,
        explicitSuspension: Bool = false
    ) {
        self.gridActive = gridActive
        self.drawerActive = drawerActive
        self.explicitSuspension = explicitSuspension
    }

    /// Any of the three suspends follow; the aggregate never has tiers.
    public var suspendsFollow: Bool { gridActive || drawerActive || explicitSuspension }
}

// MARK: - Published presentation

/// What one authoritative observation presents. Values only: the QML surface
/// renders these primitives, and equality is the presenter's whole no-op rule.
public struct SharedPlayheadPresentation: Equatable, Sendable {
    public var tick: Double = 0
    public var contentX: Double = 0
    public var timelineAttached: Bool = false
    public var visible: Bool = false
    public var playing: Bool = false
    public var previewVisible: Bool = false
    public var previewStartX: Double = 0
    public var previewEndX: Double = 0
    public var glowLeft: Double =
        SharedPlayheadAppearance.glowLeftExtent(
            baseFontPx: GridCameraPolicy.seedBaseFontPx, playing: false)
    public var glowRight: Double =
        SharedPlayheadAppearance.glowRightExtent(
            baseFontPx: GridCameraPolicy.seedBaseFontPx, playing: false)
    public var peakAlpha: Double = SharedPlayheadAppearance.peakAlpha(playing: false)
    public var lineWidthPx: Double = SharedPlayheadAppearance.lineWidth
    public var triangleHalfWidthPx: Double =
        SharedPlayheadAppearance.triangleHalfWidth(
            baseFontPx: GridCameraPolicy.seedBaseFontPx)
    public var triangleHeightPx: Double =
        SharedPlayheadAppearance.triangleHeight(
            baseFontPx: GridCameraPolicy.seedBaseFontPx)
    public var trianglePointsUp: Bool = SharedPlayheadAppearance.trianglePointsUp

    public init(
        tick: Double = 0, contentX: Double = 0, timelineAttached: Bool = false,
        visible: Bool = false, playing: Bool = false,
        baseFontPx: Double = SharedPlayheadAppearance.seedBaseFontPx
    ) {
        self.tick = tick
        self.contentX = contentX
        self.timelineAttached = timelineAttached
        self.visible = visible
        self.playing = playing
        glowLeft = SharedPlayheadAppearance.glowLeftExtent(
            baseFontPx: baseFontPx, playing: playing)
        glowRight = SharedPlayheadAppearance.glowRightExtent(
            baseFontPx: baseFontPx, playing: playing)
        peakAlpha = SharedPlayheadAppearance.peakAlpha(playing: playing)
        lineWidthPx = SharedPlayheadAppearance.lineWidth
        triangleHalfWidthPx = SharedPlayheadAppearance.triangleHalfWidth(
            baseFontPx: baseFontPx)
        triangleHeightPx = SharedPlayheadAppearance.triangleHeight(baseFontPx: baseFontPx)
        trianglePointsUp = SharedPlayheadAppearance.trianglePointsUp
    }
}

// MARK: - Pure policy

/// The playhead's whole rule set as pure values: what one authoritative
/// observation presents, and when follow moves the camera. Deterministic checks
/// drive this layer directly with synthetic timelines and cameras.
public enum SharedPlayheadPolicy {

    /// The transport raw value `ApplicationSession.playPause()` treats as playing.
    public static let playingTransport: Int32 = 2
    /// Follow re-enters once the projected x passes this fraction of the viewport
    /// width (`songview.cpp` `px > vw * 85.0 / 100.0`).
    public static let followRightFraction = 0.85
    /// The follow scroll parks the playhead one tenth of the viewport width from
    /// the plot origin (`songview.cpp` `setHScroll(tick * pxPerTick() - vw / 10.0)`).
    public static let followLeadDivisor = 10.0

    public static func isPlaying(transport: Int32) -> Bool { transport == playingTransport }

    /// Projects one tick through the camera. The playhead stays attached while a
    /// timeline exists; only a projected x inside the viewport renders.
    public static func presentation(
        tick: Double, transport: Int32,
        timelineAttached: Bool,
        camera: EditorCamera,
        baseFontPx: Double = SharedPlayheadAppearance.seedBaseFontPx,
        preview: SharedPlayheadPreview? = nil
    )
        -> SharedPlayheadPresentation
    {
        let x = camera.contentX(tick: tick)
        let width = camera.snapshot.viewportWidth
        var result = SharedPlayheadPresentation(
            tick: tick,
            contentX: x,
            timelineAttached: timelineAttached,
            visible: timelineAttached && x >= 0 && x < width,
            playing: isPlaying(transport: transport),
            baseFontPx: baseFontPx)
        if let preview {
            result.previewStartX = min(max(camera.contentX(tick: Double(preview.start)), 0), width)
            result.previewEndX = min(max(camera.contentX(tick: Double(preview.end)), 0), width)
            result.previewVisible = timelineAttached && result.previewEndX > result.previewStartX
        }
        return result
    }

    /// The horizontal scroll follow asks for, or `nil` when the policy moves
    /// nothing. Follow runs only while playing, with follow enabled and no
    /// aggregate interaction, and only once the projected x leaves
    /// `[0, 0.85 * viewportWidth]`; the camera performs its own clamping.
    public static func followTarget(
        tick: Double, camera: EditorCamera, playing: Bool,
        followEnabled: Bool,
        interactions: SharedPlayheadInteractions
    ) -> Double? {
        guard playing, followEnabled, !interactions.suspendsFollow else { return nil }
        let snapshot = camera.snapshot
        let x = camera.contentX(tick: tick)
        guard x < 0 || x > snapshot.viewportWidth * followRightFraction else { return nil }
        return tick * snapshot.pixelsPerTick - snapshot.viewportWidth / followLeadDivisor
    }
}

// MARK: - Presenter

/// The one owner of playback-position presentation for the attached document.
/// `ApplicationSession` retains it, installs the session/audio/grid/drawer
/// owners, and cancels it before retirement. QML reads the published primitives
/// only; the Swift-only entries below drive policy checks and are not commands.
@MainActor
@QtBridgeable
public final class SharedPlayheadPresenter {
    /// Authoritative tick for the retained observation, `0` while detached.
    public var tick: Double = 0
    /// Plot-local camera projection of `tick`.
    public var contentX: Double = 0
    /// A document with a timeline is attached and polling is allowed.
    public var timelineAttached: Bool = false
    /// `timelineAttached` and the projected x inside the camera viewport.
    public var visible: Bool = false
    /// Whether the displayed playback source is running, including audition.
    public var playing: Bool = false
    /// False when the owning polling lifecycle is stopped, including test fixtures.
    public var frameUpdatesEnabled: Bool = false
    /// A recent callback can advance a display frame; polling rechecks after a stall.
    public var frameClockAvailable: Bool = false
    public var previewVisible: Bool = false
    public var previewStartX: Double = 0
    public var previewEndX: Double = 0
    /// Left bloom extent from the core to the outer edge.
    public var glowLeft: Double =
        SharedPlayheadAppearance.glowLeftExtent(
            baseFontPx: GridCameraPolicy.seedBaseFontPx, playing: false)
    /// Right bloom extent from the core to the outer edge.
    public var glowRight: Double =
        SharedPlayheadAppearance.glowRightExtent(
            baseFontPx: GridCameraPolicy.seedBaseFontPx, playing: false)
    /// Peak opacity at the core-facing edge of each bloom.
    public var peakAlpha: Double = SharedPlayheadAppearance.peakAlpha(playing: false)
    /// One logical device pixel, matching layout::singlePixel().
    public var lineWidthPx: Double = SharedPlayheadAppearance.lineWidth
    public var triangleHalfWidthPx: Double =
        SharedPlayheadAppearance.triangleHalfWidth(
            baseFontPx: GridCameraPolicy.seedBaseFontPx)
    public var triangleHeightPx: Double =
        SharedPlayheadAppearance.triangleHeight(
            baseFontPx: GridCameraPolicy.seedBaseFontPx)
    /// Retained for parity with the native overlay; the Swift roll points down.
    public var trianglePointsUp: Bool = SharedPlayheadAppearance.trianglePointsUp

    /// Distinct published presentations, for coverage and performance checks.
    /// `UInt64` is not a bridge type, so this diagnostic stays Swift-only.
    public private(set) var presentationCount: UInt64 = 0
    /// Follow is enabled by default and has no user-facing command; this switch
    /// exists for deterministic policy checks.
    public private(set) var followEnabled = true
    /// Raised by a page that owns a prompt or a drag outside the grid/drawer.
    public private(set) var explicitSuspension = false
    /// One Swift-only notification per distinct presentation. `ApplicationSession`
    /// installs it to fan the shared clock into document-bound pages in Swift;
    /// reading the presenter from QML and calling a page's mutator back through
    /// that bridge wrapper would route the page's clock through a transient
    /// object. The QML-facing fields and signals below are unchanged, and this
    /// callback never changes what the presenter publishes.
    @QtIgnored public var onPresentation: ((SharedPlayheadPresentation) -> Void)?
    /// Poll callback: elapsed seconds, song transport state, and changed presentation.
    @QtIgnored public var onPoll: ((Float, Bool, Bool) -> Void)?

    /// The polling lifecycle token: a new one per attach, and every observation
    /// carries the token of the generation that produced it. A task from a
    /// cancelled generation is refused, so it can never publish into a
    /// replacement document.
    public private(set) var lifecycleToken: UInt64 = 0
    @QtIgnored public var isPolling: Bool { pollTask != nil }

    /// Semantic/telemetry cadence only; playback visuals follow display frames.
    /// Cancellation interrupts the sleep immediately.
    private static let pollInterval: Duration = .milliseconds(16)

    private weak var viewport: DocumentViewport?
    private weak var audio: NativeAudio?
    private weak var grid: PianoGrid?
    private weak var drawer: EditorDrawerPresenter?
    private var readPreview: (() -> SharedPlayheadPreview?)?
    private var pollTask: Task<Void, Never>?
    private var retained: SharedPlayheadObservation?
    private var published: SharedPlayheadPresentation?
    private var visualTick: Double?

    public init() {}

    // MARK: Owner installation

    /// Installs the owners for one document and presents the current
    /// authoritative observation synchronously. Polling starts separately, once
    /// the audio binding is installed: `ApplicationSession` calls `startPolling`
    /// after every owner is in place.
    @QtIgnored
    public func attach(
        viewport: DocumentViewport, audio: NativeAudio?, grid: PianoGrid?,
        drawer: EditorDrawerPresenter?,
        preview: (() -> SharedPlayheadPreview?)? = nil
    ) {
        lifecycleToken &+= 1
        self.viewport = viewport
        self.audio = audio
        self.grid = grid
        self.drawer = drawer
        readPreview = preview
        retained = nil
        visualTick = nil
        observeCurrent(token: lifecycleToken)
    }

    /// Cancels polling, drops the owners, and clears the attached presentation
    /// synchronously while those owners still exist. The presentation callback is
    /// cleared first, so the empty presentation below never fans into a page whose
    /// document is being released.
    @QtIgnored
    public func detach() {
        lifecycleToken &+= 1
        stopPolling()
        onPresentation = nil
        onPoll = nil
        viewport = nil
        audio = nil
        grid = nil
        drawer = nil
        readPreview = nil
        retained = nil
        visualTick = nil
        apply(SharedPlayheadPresentation())
    }

    /// Starts the one polling task for the installed generation. A second call
    /// while a task exists is refused, so the presenter never runs two.
    @QtIgnored
    public func startPolling() {
        guard pollTask == nil, viewport != nil else { return }
        let token = lifecycleToken
        frameUpdatesEnabled = true
        pollTask = Task { [weak self] in
            var previous = ContinuousClock.now
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: SharedPlayheadPresenter.pollInterval)
                } catch {
                    return
                }
                guard let self, self.lifecycleToken == token else { return }
                let presentationChanged = self.observeCurrent(token: token, updatePosition: false)
                let now = ContinuousClock.now
                let elapsed = previous.duration(to: now).components
                previous = now
                self.onPoll?(
                    Float(elapsed.seconds) + Float(elapsed.attoseconds) / 1e18,
                    self.retained?.playing ?? false, presentationChanged)
            }
        }
    }

    /// Cancels polling and keeps the owners and the retained observation.
    @QtIgnored
    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        frameUpdatesEnabled = false
        frameClockAvailable = false
    }

    // MARK: Presentation

    /// Reads the audio service's authoritative sample and transport and
    /// presents them. Used by the polling task and after every transport,
    /// timeline, and document transition.
    @QtIgnored
    public func refreshImmediate() {
        _ = observeCurrent(token: lifecycleToken)
    }

    /// Re-projects the retained observation through the current timeline and
    /// camera without reading the audio service again and without following:
    /// a camera publication keeps the same tick and may change visibility.
    @QtIgnored
    public func refreshProjection() {
        guard let viewport, let retained else { return }
        let tick = retained.displayTick(in: viewport.session.timeline)
        let displayedTick = visualTick ?? tick
        apply(
            SharedPlayheadPolicy.presentation(
                tick: tick, transport: retained.displayTransport, timelineAttached: true,
                camera: viewport.camera, baseFontPx: currentBaseFontPx, preview: retained.preview),
            updatePosition: false)
        projectVisual(tick: displayedTick, viewport: viewport)
    }

    /// Projects the most recent coherent callback anchor on a display frame.
    /// The frame publishes only visual position and visibility, never page clocks.
    public func displayFrame() {
        guard frameUpdatesEnabled, let audio else { return }
        let patternActive: Bool
        if case .active = audio.patternState { patternActive = true } else { patternActive = false }
        presentFrame(
            clock: audio.playbackClock, uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
            sampleRate: audio.sampleRate, timelineIdentity: audio.requestedTimelineIdentity,
            patternIdentity: audio.requestedPatternIdentity, requestedTransport: audio.requestedTransport,
            patternActive: patternActive,
            deviceRunning: audio.isDeviceRunning)
    }

    /// Selects and projects the callback clock, holding the last visual across
    /// transient read failures and stopping animation after its prediction bound.
    @QtIgnored
    public func presentFrame(
        clock: AudioPlaybackClockSnapshot?, uptimeNanoseconds: UInt64,
        sampleRate: Double, timelineIdentity: UInt64, patternIdentity: UInt64,
        requestedTransport: Int32, patternActive: Bool, deviceRunning: Bool
    ) {
        let sourceMatches: Bool
        if let clock, let retained {
            sourceMatches =
                clock.pattern
                ? retained.preview?.tick != nil
                : retained.preview?.tick == nil && retained.playing
        } else {
            sourceMatches = false
        }
        let matches =
            sourceMatches
            && clockMatches(
                clock, timelineIdentity: timelineIdentity, patternIdentity: patternIdentity,
                requestedTransport: requestedTransport, patternActive: patternActive, deviceRunning: deviceRunning)
        let available = matches && clockIsFresh(clock, sampleRate: sampleRate, now: uptimeNanoseconds)
        if frameClockAvailable != available { frameClockAvailable = available }
        if matches {
            projectFrame(
                clock: clock, uptimeNanoseconds: uptimeNanoseconds, sampleRate: sampleRate,
                timelineIdentity: timelineIdentity, patternIdentity: patternIdentity,
                requestedTransport: requestedTransport)
        } else if let retained,
            !SharedPlayheadPolicy.isPlaying(transport: retained.displayTransport)
                || (retained.preview?.tick == nil && requestedTransport != SharedPlayheadPolicy.playingTransport)
        {
            projectFrame(
                clock: nil, uptimeNanoseconds: uptimeNanoseconds, sampleRate: sampleRate,
                timelineIdentity: timelineIdentity, patternIdentity: patternIdentity,
                requestedTransport: requestedTransport)
        }
    }

    /// The shared projection entry also accepts explicit clocks for deterministic checks.
    @QtIgnored
    public func projectFrame(
        clock: AudioPlaybackClockSnapshot?, uptimeNanoseconds: UInt64,
        sampleRate: Double, timelineIdentity: UInt64, patternIdentity: UInt64,
        requestedTransport: Int32
    ) {
        guard let viewport, let retained else { return }
        var displayTick = retained.displayTick(in: viewport.session.timeline)
        if let clock, clock.timelineIdentity == timelineIdentity {
            if clock.pattern, clock.patternIdentity == patternIdentity, patternIdentity != 0,
                retained.preview?.tick != nil
            {
                let candidate = viewport.session.timeline.tick(
                    for: clock.sample(at: uptimeNanoseconds, sampleRate: sampleRate))
                if let preview = retained.preview,
                    candidate >= Double(preview.start), candidate < Double(preview.end)
                {
                    displayTick = candidate
                }
            } else if !clock.pattern, retained.preview?.tick == nil, retained.playing,
                requestedTransport == SharedPlayheadPolicy.playingTransport,
                clock.transport.rawValue == SharedPlayheadPolicy.playingTransport
            {
                displayTick = viewport.session.timeline.tick(
                    for: clock.sample(at: uptimeNanoseconds, sampleRate: sampleRate))
            }
        }
        projectVisual(tick: displayTick, viewport: viewport)
    }

    /// Presents one injected observation for the current generation. This is the
    /// deterministic policy hook: production QML never calls it, and the polling
    /// task presents through the token-taking entry below.
    @discardableResult
    @QtIgnored
    public func observe(sample: UInt64, transport: Int32) -> Bool {
        observe(
            SharedPlayheadObservation(sample: sample, transport: transport),
            token: lifecycleToken)
    }

    /// Accepts one observation for the generation that produced it: the sole
    /// mapping is `PlaybackTimeline.tick(for:)`, follow may move the camera once
    /// through the document viewport, and only a changed presentation publishes.
    /// Returns `false` for a stale token or with no document attached.
    @discardableResult
    @QtIgnored
    public func observe(_ observation: SharedPlayheadObservation, token: UInt64) -> Bool {
        observe(observation, token: token, updatePosition: true)
    }

    /// Publishes a semantic poll without driving a playing source's visual x.
    /// Non-playing changes are discrete transport/position observations.
    @discardableResult
    @QtIgnored
    public func observePolled(_ observation: SharedPlayheadObservation, token: UInt64) -> Bool {
        guard token == lifecycleToken, let viewport else { return false }
        let rewind =
            retained?.playing == true && observation.transport == AudioTransportState.stopped.rawValue
            && observation.preview?.tick == nil
        let nonPlayingChange =
            !SharedPlayheadPolicy.isPlaying(transport: observation.displayTransport)
            && observation != retained
        let changed = observe(observation, token: token, updatePosition: nonPlayingChange && !rewind)
        if rewind { projectVisual(tick: 0, viewport: viewport) }
        return changed
    }

    private func observe(
        _ observation: SharedPlayheadObservation, token: UInt64, updatePosition: Bool
    ) -> Bool {
        guard token == lifecycleToken, let viewport else { return false }
        retained = observation
        let tick = observation.displayTick(in: viewport.session.timeline)
        if let target = SharedPlayheadPolicy.followTarget(
            tick: tick, camera: viewport.camera,
            playing: SharedPlayheadPolicy.isPlaying(transport: observation.displayTransport),
            followEnabled: followEnabled, interactions: interactions)
        {
            // The camera's own clamping and its callback publish; the
            // presentation below reads the camera this mutation produced.
            _ = viewport.mutateCamera { $0.setHScroll(target) }
        }
        return apply(
            SharedPlayheadPolicy.presentation(
                tick: tick, transport: observation.displayTransport, timelineAttached: true,
                camera: viewport.camera, baseFontPx: currentBaseFontPx, preview: observation.preview),
            updatePosition: updatePosition)
    }

    /// Enables or disables follow. Default enabled; no QML command exists.
    @QtIgnored
    public func setFollowEnabled(_ enabled: Bool) {
        followEnabled = enabled
    }

    /// Raises or clears the explicit temporary suspension.
    @QtIgnored
    public func setExplicitSuspension(_ suspended: Bool) {
        explicitSuspension = suspended
    }

    // MARK: Internals

    private var interactions: SharedPlayheadInteractions {
        SharedPlayheadInteractions(
            gridActive: grid?.interactionActive ?? false,
            drawerActive: drawer?.interactionActive ?? false,
            explicitSuspension: explicitSuspension)
    }
    private var currentBaseFontPx: Double {
        grid?.baseFontPx ?? GridCameraPolicy.seedBaseFontPx
    }

    private func clockMatches(
        _ clock: AudioPlaybackClockSnapshot?, timelineIdentity: UInt64, patternIdentity: UInt64,
        requestedTransport: Int32, patternActive: Bool, deviceRunning: Bool
    ) -> Bool {
        guard deviceRunning, let clock, clock.timelineIdentity == timelineIdentity else { return false }
        if clock.pattern {
            return patternActive && patternIdentity != 0 && clock.patternIdentity == patternIdentity
        }
        return requestedTransport == SharedPlayheadPolicy.playingTransport
            && clock.transport.rawValue == SharedPlayheadPolicy.playingTransport
    }

    private func clockIsFresh(
        _ clock: AudioPlaybackClockSnapshot?, sampleRate: Double, now: UInt64
    ) -> Bool {
        guard let clock, clock.predictionFrames > 0, sampleRate > 0 else { return false }
        guard now > clock.uptimeNanoseconds else { return true }
        let elapsedFrames = Double(now - clock.uptimeNanoseconds) * sampleRate / 1_000_000_000
        return elapsedFrames < Double(clock.predictionFrames)
    }

    @discardableResult
    private func observeCurrent(token: UInt64, updatePosition: Bool = true) -> Bool {
        if frameUpdatesEnabled, let audio {
            let clock = audio.playbackClock
            let patternActive: Bool
            if case .active = audio.patternState { patternActive = true } else { patternActive = false }
            let matches = clockMatches(
                clock, timelineIdentity: audio.requestedTimelineIdentity,
                patternIdentity: audio.requestedPatternIdentity, requestedTransport: audio.requestedTransport,
                patternActive: patternActive, deviceRunning: audio.isDeviceRunning)
            let available =
                matches
                && clockIsFresh(
                    clock, sampleRate: audio.sampleRate, now: DispatchTime.now().uptimeNanoseconds)
            // Let an already-running frame project the clamped endpoint before
            // it turns itself off when a coherent anchor ages out.
            if frameClockAvailable != available && (available || !matches) {
                frameClockAvailable = available
            }
        }
        let observation = SharedPlayheadObservation(
            sample: audio?.presentationPlayheadSamples ?? 0,
            transport: audio?.requestedTransport ?? 0, preview: readPreview?())
        if updatePosition { return observe(observation, token: token) }
        return observePolled(observation, token: token)
    }

    private func projectVisual(tick: Double, viewport: DocumentViewport) {
        visualTick = tick
        let x = viewport.camera.contentX(tick: tick)
        let isVisible = x >= 0 && x < viewport.camera.snapshot.viewportWidth
        if contentX != x { contentX = x }
        if visible != isVisible { visible = isVisible }
    }

    /// Publishes only a changed presentation, writing only the primitives that
    /// changed so an unchanged field emits no property signal.
    @discardableResult
    private func apply(_ presentation: SharedPlayheadPresentation, updatePosition: Bool = true) -> Bool {
        let changed = presentation != published
        if updatePosition {
            visualTick = presentation.timelineAttached ? presentation.tick : nil
            if contentX != presentation.contentX { contentX = presentation.contentX }
            if visible != presentation.visible { visible = presentation.visible }
        }
        guard changed else { return false }
        published = presentation
        presentationCount &+= 1
        if tick != presentation.tick { tick = presentation.tick }
        if timelineAttached != presentation.timelineAttached {
            timelineAttached = presentation.timelineAttached
        }
        if playing != presentation.playing { playing = presentation.playing }
        if previewVisible != presentation.previewVisible { previewVisible = presentation.previewVisible }
        if previewStartX != presentation.previewStartX { previewStartX = presentation.previewStartX }
        if previewEndX != presentation.previewEndX { previewEndX = presentation.previewEndX }
        if glowLeft != presentation.glowLeft { glowLeft = presentation.glowLeft }
        if glowRight != presentation.glowRight { glowRight = presentation.glowRight }
        if peakAlpha != presentation.peakAlpha { peakAlpha = presentation.peakAlpha }
        if lineWidthPx != presentation.lineWidthPx { lineWidthPx = presentation.lineWidthPx }
        if triangleHalfWidthPx != presentation.triangleHalfWidthPx {
            triangleHalfWidthPx = presentation.triangleHalfWidthPx
        }
        if triangleHeightPx != presentation.triangleHeightPx {
            triangleHeightPx = presentation.triangleHeightPx
        }
        if trianglePointsUp != presentation.trianglePointsUp {
            trianglePointsUp = presentation.trianglePointsUp
        }
        // The one Swift fan-out, after every QML-facing field is published so a
        // callback reads the presentation it was notified about.
        onPresentation?(presentation)
        return true
    }
}
