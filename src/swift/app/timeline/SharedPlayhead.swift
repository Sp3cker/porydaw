import Foundation
import PorydawCore
import QtBridge

// The shared playhead: one playback-position presentation for the whole editor
// surface. `ApplicationSession` retains exactly one presenter; the roll plot and
// every visible drawer body render a clipped segment from that one publication.
//
// Authority: the native audio service's sample and transport, mapped exclusively
// by `PlaybackTimeline.tick(for:)` and projected by the current
// `DocumentSession` camera. No elapsed wall time, interpolation, QML animation
// or page timer infers position. The presenter owns no document, timeline,
// camera, history or audio service; it reads the ones `ApplicationSession`
// installs, and it owns exactly one cancellable polling task.

// MARK: - Authoritative observation

/// One authoritative transport observation: the sample position and raw
/// transport value the native audio service reports. The presenter never
/// derives either from a clock.
public struct SharedPlayheadObservation: Equatable, Sendable {
    public var sample: UInt64
    public var transport: Int32

    public init(sample: UInt64, transport: Int32) {
        self.sample = sample
        self.transport = transport
    }

    public var playing: Bool { SharedPlayheadPolicy.isPlaying(transport: transport) }
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

    public init(gridActive: Bool = false, drawerActive: Bool = false,
                explicitSuspension: Bool = false) {
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

    public init(tick: Double = 0, contentX: Double = 0, timelineAttached: Bool = false,
                visible: Bool = false, playing: Bool = false) {
        self.tick = tick
        self.contentX = contentX
        self.timelineAttached = timelineAttached
        self.visible = visible
        self.playing = playing
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
    public static func presentation(tick: Double, transport: Int32,
                                    timelineAttached: Bool,
                                    camera: EditorCamera) -> SharedPlayheadPresentation {
        let x = camera.contentX(tick: tick)
        let width = camera.snapshot.viewportWidth
        return SharedPlayheadPresentation(
            tick: tick,
            contentX: x,
            timelineAttached: timelineAttached,
            visible: timelineAttached && x >= 0 && x < width,
            playing: isPlaying(transport: transport))
    }

    /// The horizontal scroll follow asks for, or `nil` when the policy moves
    /// nothing. Follow runs only while playing, with follow enabled and no
    /// aggregate interaction, and only once the projected x leaves
    /// `[0, 0.85 * viewportWidth]`; the camera performs its own clamping.
    public static func followTarget(tick: Double, camera: EditorCamera, playing: Bool,
                                    followEnabled: Bool,
                                    interactions: SharedPlayheadInteractions) -> Double? {
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
    /// The transport raw value `ApplicationSession.playPause()` calls playing.
    public var playing: Bool = false

    /// Distinct published presentations, for coverage and performance checks.
    /// `UInt64` is not a bridge type, so this diagnostic stays Swift-only.
    @QtIgnored public private(set) var presentationCount: UInt64 = 0
    /// Follow is enabled by default and has no user-facing command; this switch
    /// exists for deterministic policy checks.
    @QtIgnored public private(set) var followEnabled = true
    /// Raised by a page that owns a prompt or a drag outside the grid/drawer.
    @QtIgnored public private(set) var explicitSuspension = false
    /// One Swift-only notification per distinct presentation. `ApplicationSession`
    /// installs it to fan the shared clock into document-bound pages in Swift;
    /// reading the presenter from QML and calling a page's mutator back through
    /// that bridge wrapper would route the page's clock through a transient
    /// object. The QML-facing fields and signals below are unchanged, and this
    /// callback never changes what the presenter publishes.
    @QtIgnored public var onPresentation: ((SharedPlayheadPresentation) -> Void)?
    @QtIgnored public var onPoll: ((Float, Bool) -> Void)?

    /// The polling lifecycle token: a new one per attach, and every observation
    /// carries the token of the generation that produced it. A task from a
    /// cancelled generation is refused, so it can never publish into a
    /// replacement document.
    @QtIgnored public private(set) var lifecycleToken: UInt64 = 0
    @QtIgnored public var isPolling: Bool { pollTask != nil }

    /// One display cadence for every transport state. Cancellation does not wait
    /// out the sleep: `Task.sleep` throws as soon as the task is cancelled.
    private static let pollInterval: Duration = .milliseconds(16)

    @QtIgnored private weak var session: DocumentSession?
    @QtIgnored private weak var audio: NativeAudio?
    @QtIgnored private weak var grid: PianoGrid?
    @QtIgnored private weak var drawer: EditorDrawerPresenter?
    @QtIgnored private var pollTask: Task<Void, Never>?
    @QtIgnored private var retained: SharedPlayheadObservation?
    @QtIgnored private var published: SharedPlayheadPresentation?

    public init() {}

    // MARK: Owner installation

    /// Installs the owners for one document and presents the current
    /// authoritative observation synchronously. Polling starts separately, once
    /// the audio binding is installed: `ApplicationSession` calls `startPolling`
    /// after every owner is in place.
    @QtIgnored
    public func attach(session: DocumentSession, audio: NativeAudio?, grid: PianoGrid?,
                       drawer: EditorDrawerPresenter?) {
        lifecycleToken &+= 1
        self.session = session
        self.audio = audio
        self.grid = grid
        self.drawer = drawer
        retained = nil
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
        session = nil
        audio = nil
        grid = nil
        drawer = nil
        retained = nil
        apply(SharedPlayheadPresentation())
    }

    /// Starts the one polling task for the installed generation. A second call
    /// while a task exists is refused, so the presenter never runs two.
    @QtIgnored
    public func startPolling() {
        guard pollTask == nil, session != nil else { return }
        let token = lifecycleToken
        pollTask = Task { [weak self] in
            var previous = ContinuousClock.now
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: SharedPlayheadPresenter.pollInterval)
                } catch {
                    return
                }
                guard let self, self.lifecycleToken == token else { return }
                self.observeCurrent(token: token)
                let now = ContinuousClock.now
                let elapsed = previous.duration(to: now).components
                previous = now
                self.onPoll?(Float(elapsed.seconds) + Float(elapsed.attoseconds) / 1e18,
                             self.playing)
            }
        }
    }

    /// Cancels polling and keeps the owners and the retained observation.
    @QtIgnored
    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Presentation

    /// Reads the audio service's authoritative sample and transport and
    /// presents them. Used by the polling task and after every transport,
    /// timeline, and document transition.
    @QtIgnored
    public func refreshImmediate() {
        observeCurrent(token: lifecycleToken)
    }

    /// Re-projects the retained observation through the current timeline and
    /// camera without reading the audio service again and without following:
    /// a camera publication keeps the same tick and may change visibility.
    @QtIgnored
    public func refreshProjection() {
        guard let session, let retained else { return }
        let tick = session.timeline.tick(for: retained.sample)
        apply(SharedPlayheadPolicy.presentation(tick: tick, transport: retained.transport,
                                                timelineAttached: true,
                                                camera: session.camera))
    }

    /// Presents one injected observation for the current generation. This is the
    /// deterministic policy hook: production QML never calls it, and the polling
    /// task presents through the token-taking entry below.
    @discardableResult
    @QtIgnored
    public func observe(sample: UInt64, transport: Int32) -> Bool {
        observe(SharedPlayheadObservation(sample: sample, transport: transport),
                token: lifecycleToken)
    }

    /// Accepts one observation for the generation that produced it: the sole
    /// mapping is `PlaybackTimeline.tick(for:)`, follow may move the camera once
    /// through the document session, and only a changed presentation publishes.
    /// Returns `false` for a stale token or with no document attached.
    @discardableResult
    @QtIgnored
    public func observe(_ observation: SharedPlayheadObservation, token: UInt64) -> Bool {
        guard token == lifecycleToken, let session else { return false }
        retained = observation
        let tick = session.timeline.tick(for: observation.sample)
        if let target = SharedPlayheadPolicy.followTarget(
            tick: tick, camera: session.camera, playing: observation.playing,
            followEnabled: followEnabled, interactions: interactions)
        {
            // The camera's own clamping and its callback publish; the
            // presentation below reads the camera this mutation produced.
            _ = session.mutateCamera { $0.setHScroll(target) }
        }
        return apply(SharedPlayheadPolicy.presentation(
            tick: tick, transport: observation.transport, timelineAttached: true,
            camera: session.camera))
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
        SharedPlayheadInteractions(gridActive: grid?.interactionActive ?? false,
                                   drawerActive: drawer?.interactionActive ?? false,
                                   explicitSuspension: explicitSuspension)
    }

    private func observeCurrent(token: UInt64) {
        let observation = SharedPlayheadObservation(sample: audio?.playheadSamples ?? 0,
                                                    transport: audio?.transport ?? 0)
        observe(observation, token: token)
    }

    /// Publishes only a changed presentation, writing only the primitives that
    /// changed so an unchanged field emits no property signal.
    @discardableResult
    private func apply(_ presentation: SharedPlayheadPresentation) -> Bool {
        guard presentation != published else { return false }
        published = presentation
        presentationCount &+= 1
        if tick != presentation.tick { tick = presentation.tick }
        if contentX != presentation.contentX { contentX = presentation.contentX }
        if timelineAttached != presentation.timelineAttached {
            timelineAttached = presentation.timelineAttached
        }
        if visible != presentation.visible { visible = presentation.visible }
        if playing != presentation.playing { playing = presentation.playing }
        // The one Swift fan-out, after every QML-facing field is published so a
        // callback reads the presentation it was notified about.
        onPresentation?(presentation)
        return true
    }
}
