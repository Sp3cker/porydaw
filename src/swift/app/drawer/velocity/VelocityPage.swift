import Foundation
import PorydawCore
import QtBridge

// The production Velocity page: one deep owner for the drawer's Velocity
// section, following `src/ui/editordrawer/velocityarea/` and `velocityaxis.*`
// for behaviour. It publishes primitives and stable item models for QML and
// owns no camera, clock, viewport, history or selection storage: selection
// lives in `DocumentSession`, the horizontal projection is `EditorCamera`, and
// the playhead is the composition-owned segment the page only reads.
//
// Ownership: `ApplicationSession` creates the page for the current document,
// attaches it before `songOpen` publishes, refreshes it from the session's
// existing document/grid/playhead publications, and cancels it synchronously
// before the document owners retire.
//
// Split: the scene build vocabulary and orchestration
// (`VelocityScene.swift`), the pure scene-value helpers it calls
// (`VelocitySceneValues.swift`) and the plot-relative maths
// (`VelocityProjection.swift`) are value layers this page feeds from its
// session and its live gesture/hover state;
// `VelocityInteraction.swift` holds the gesture, hover and prompt machinery
// behind this page's Qt seam, and `VelocityPublication.swift` holds the
// content rebuild and every publish apply path. Published state and the reuse
// caches stay declared on this type — `@QtBridgeable` registers class-body
// members only and stored properties cannot move to an extension — and the
// Qt-facing input methods stay here for the same reason: each decodes its raw
// payload exactly once, then sends one typed reducer event.
//

// MARK: - Page vocabulary

/// The page's published constants. The base font seed mirrors the grid's
/// `GridCameraPolicy.seedBaseFontPx`, which is internal to this module.
public enum VelocityPagePolicy {
    public static let seedBaseFontPx: Double = 13
}

/// Where a pointer event landed in the page body. Mirrors the legacy
/// `TimelineInputSurface` split: the ruler column click-sets, the plot edits.
public enum VelocityInputSurface: Int, Sendable {
    case ruler = 0
    case plot = 1
}


// MARK: - Published note handle

/// One published note handle: stable identity, plot geometry, displayed value
/// and state. QML draws these rows after the publisher flattens the same plain
/// descriptors consumed by hit testing.
@MainActor
@QtBridgeable
public final class VelocityHandle {
    @QtIgnored var noteID = NoteID(0)
    /// The stable `NoteID` token as text: `UInt64` is not a bridge type.
    public var noteIdText: String = ""
    public var tick: Double = 0
    public var endTick: Double = 0
    public var x: Double = 0
    public var endX: Double = 0
    public var value: Int = 1
    public var y: Double = 0
    public var selected: Bool = false
    public var hovered: Bool = false
    public var preview: Bool = false
    public var dimmed: Bool = false
    public var level: Int = -1
    public var label: String = ""
    public var hitRadius: Double = 0
    public var stemWidth: Double = 0
    public var nodeRadius: Double = 0
    public var outlineRadius: Double = 0
    public var outlineWidth: Double = 0
    public var ringRadius: Double = 0
    public var ringWidth: Double = 0
    public var fillColor: String = ""
    public var stemColor: String = ""
    public var ringColor: String = ""
    public var outlineColor: String = ""
    public var primitiveName: String = ""

    public init() {}

    convenience init(_ value: VelocityHandleValue) {
        self.init()
        noteID = value.noteID
        noteIdText = value.noteIdText
        tick = value.tick
        endTick = value.endTick
        x = value.x
        endX = value.endX
        self.value = value.value
        y = value.y
        selected = value.selected
        hovered = value.hovered
        preview = value.preview
        dimmed = value.dimmed
        level = value.level
        label = value.label
        hitRadius = value.hitRadius
        stemWidth = value.stemWidth
        nodeRadius = value.nodeRadius
        outlineRadius = value.outlineRadius
        outlineWidth = value.outlineWidth
        ringRadius = value.ringRadius
        ringWidth = value.ringWidth
        fillColor = value.fillColor
        stemColor = value.stemColor
        ringColor = value.ringColor
        outlineColor = value.outlineColor
        primitiveName = value.primitiveName
    }

}

// MARK: - Page owner

/// The production Velocity page. Every published value derives from the current
/// document session; every mutation goes through `SongDocument.setVelocities`
/// with the revision captured when the interaction began, so at most one history
/// entry is produced per completed gesture or accepted prompt.
@MainActor
@QtBridgeable
public final class VelocityPage: EditorDrawerPage {
    /// The fixed production QML URL, resolved once by the container at attach.
    public static let contentUrl = "qrc:/porydaw/drawer/VelocityPage.qml"

    @QtIgnored public let sectionKind: DrawerSectionKind = .velocity
    @QtIgnored public var contentUrl: String { Self.contentUrl }
    /// Production's velocity default body:
    /// `clamp(hostHeight / 6, fontPx(8), fontPx(12))`.
    @QtIgnored public var bodyPolicy: EditorDrawerBodyPolicy
    /// The container's follow-scroll gate: a pointer gesture, a frozen preview,
    /// a live prompt or a band selection is an active interaction. The publication
    /// pass derives it from the current interaction state.
    public var interactionActive: Bool = false
    /// `VelocityArea::useDetents`: the page's own detent preference. Enabled by
    /// default; `setUseDetents(false)` turns every context into the continuous
    /// 1-127 domain, which is what the legacy detent control toggles.
    public var detentsEnabled: Bool = true
    /// `VelocityArea::isPsgContext`: the detent control is available only while
    /// the presented context resolves to a PSG voice.
    public var detentsAvailable: Bool = false

    // MARK: Published projection

    public var plotHeight: Double = 0
    public var plotWidth: Double = 0
    public var rulerWidth: Double = 0
    public var devicePixelRatio: Double = 1
    public var baseFontPx: Double = GridCameraPolicy.seedBaseFontPx
    public var axisMode: Int = 0
    /// `rebuildQuickAxis`'s rendering branch: the level graduations are drawn only
    /// for an intrinsic context with detents enabled, and the continuous ladder
    /// takes over otherwise.
    public var axisGraduationsVisible: Bool = false
    public var axisAccessibleDescription: String = "Velocity"
    /// `true` while the active context's exact map is unknown: rendering, hover
    /// and navigation stay live, and every exact-map edit is refused.
    public var contextUnsupported: Bool = false
    public var contextDiagnostic: String = ""
    public var contextSlot: Int = -1
    public var contextVoiceName: String = ""
    public var readoutText: String = ""
    public var readoutVisible: Bool = false
    public var readoutX: Double = 0
    public var readoutY: Double = 0
    public var selectedCount: Int = 0
    public var hoveredNoteText: String = ""
    public var rampVisible: Bool = false
    public var rampX0: Double = 0
    public var rampY0: Double = 0
    public var rampLength: Double = 0
    public var rampSlopeY: Double = 0
    public var rampColor: String = ""
    public var promptOpen: Bool = false
    public var promptAppearance: [String: QVariantSettable] = [:]
    public var promptFont: [String: QVariantSettable] = [:]
    public var promptDraft: String = ""
    public var promptError: String = ""
    public var promptTitle: String = "Note velocity"
    public var promptLabel: String = "Velocity (1-127):"
    public var promptMinimum: Int = VelocityPromptPolicy.minimum
    public var promptMaximum: Int = VelocityPromptPolicy.maximum
    public var promptInitialValue: Int = VelocityPromptPolicy.minimum
    /// Accepted prompt values also seed subsequently drawn notes, including no-op edits.
    @QtIgnored public var onVelocityAccepted: ((UInt8) -> Void)?

    public var gridLines: QListModel<SceneRect> = QListModel()
    public var psgBands: QListModel<SceneRect> = QListModel()
    /// The gesture transient's rects. `transient` alone is a reserved QML
    /// keyword, so the published name carries its own noun.
    public var transientRects: QListModel<SceneRect> = QListModel()
    public var axisTicks: QListModel<SceneRect> = QListModel()
    public var axisGraduations: QListModel<SceneRect> = QListModel()
    public var axisMarkers: QListModel<SceneRect> = QListModel()
    public var axisLabels: QListModel<SceneText> = QListModel()
    public var handles: QListModel<VelocityHandle> = QListModel()

    /// Distinct content rebuilds: shared-playhead movement inside one voice
    /// context, and repeated equal publications, rebuild nothing.
    @QtIgnored public internal(set) var contentBuildCount: UInt64 = 0
    @QtIgnored public var playheadPresentationCount: UInt64 {
        state.playheadPresentationCount
    }
    @QtIgnored public var presentedContextTick: Tick { state.contextTick }
    @QtIgnored public var presentedContextSlot: Int { state.presentedContext.slot }
    @QtIgnored public var presentedPlaying: Bool { state.playing }
    @QtIgnored public var hasGesture: Bool {
        if case .gesture = state.mode { return true }
        return false
    }
    /// The primary track's selected notes as the published identity text.
    public func selectedNoteIdText() -> String {
        state.selectedNotes.map { velocityNoteText($0.id) }.joined(separator: ",")
    }
    @QtIgnored public var hasPrompt: Bool {
        if case .prompt = state.mode { return true }
        return false
    }
    @QtIgnored public var frozenPreview: [NoteID: UInt8] { gesture?.preview ?? [:] }
    @QtIgnored public var frozenNotes: [VelocityFrozenNote] { gesture?.notes ?? [] }
    @QtIgnored public var promptTargets: [NoteID] { prompt?.noteIDs ?? [] }
    @QtIgnored public var promptBeforeValues: [UInt8] { prompt?.beforeValues ?? [] }
    @QtIgnored public var publishedNoteCount: Int { sceneCache.handles.count }
    @QtIgnored var publishedHandlesSnapshot: [VelocityHandleValue] { sceneCache.handles }
    @QtIgnored public var axisModel: VelocityAxisModel { axis }
    @QtIgnored public var context: VelocityVoiceContext { state.presentedContext }
    @QtIgnored public var presentedContextEndTick: Tick {
        state.presentedContext.endTick ?? TimeDefaults.noTick
    }

    @QtIgnored weak var session: DocumentSession?
    @QtIgnored var palette = GridPalette()
    @QtIgnored var axis = VelocityAxisModel()
    @QtIgnored var sceneCache = VelocityScene()
    @QtIgnored var state = VelocityState()
    @QtIgnored private var dispatchDepth = 0
    @QtIgnored private var pendingPublication: VelocityPublicationScope = []
    @QtIgnored var typographyCache: (key: TypographyKey, value: DrawerTextMetrics)?
    @QtIgnored var metricsCache: (key: MetricsKey, value: GridMetrics)?

    @QtIgnored var gesture: VelocityGesture? {
        if case let .gesture(value) = state.mode { return value }
        return nil
    }

    @QtIgnored var prompt: VelocityPromptState? {
        if case let .prompt(value) = state.mode { return value }
        return nil
    }

    struct MetricsKey: Equatable {
        var revision: UInt64
        var font: Double
        var dpr: Double
        var width: Double
        var height: Double
    }

    struct TypographyKey: Equatable {
        var baseFontPx: Double
        var devicePixelRatio: Double
        var rowHeight: Double
    }

    public init(baseFontPx: Double = VelocityPagePolicy.seedBaseFontPx) {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        bodyPolicy = EditorDrawerBodyPolicy { hostHeight, _ in
            let preferred = Double(hostHeight) / 6
            let minimum = max(1, (base * 8).rounded())
            let maximum = max(minimum, (base * 12).rounded())
            return Int(min(max(preferred, minimum), maximum))
        }
        state.body.baseFontPx = base
        state.body.geometry = VelocityNodeGeometry(baseFontPx: base, devicePixelRatio: 1)
        promptAppearance = PromptAppearance.metrics(base: base)
        promptFont = PromptAppearance.font(base: base)
    }

    /// Installs the document and palette owners before the container attaches.
    @QtIgnored
    public func attach(session: DocumentSession, palette: GridPalette) {
        metricsCache = nil
        self.session = session
        self.palette = palette
        state.contextTick = session.editCursor
        _ = send(.document(documentFacts()))
        _ = send(.camera(session.camera))
    }

    /// Drops the session and every interaction-owned value.
    @QtIgnored
    public func detach() {
        _ = send(.cancel)
        _ = send(.detach)
        session = nil
        metricsCache = nil
        typographyCache = nil
    }

    // MARK: Composition and session input

    public func configureBody(width: Double, height: Double, rulerWidth: Double,
                              devicePixelRatio: Double, baseFontPx: Double,
                              dragDistance: Double) {
        _ = send(.body(width: width, height: height, rulerWidth: rulerWidth,
                       devicePixelRatio: devicePixelRatio, baseFontPx: baseFontPx,
                       dragDistance: dragDistance))
    }

    @QtIgnored
    public func refreshFromDocument() {
        guard session != nil else { return }
        _ = send(.document(documentFacts()))
    }

    @QtIgnored
    public func refreshEditCursor() {
        guard let session else { return }
        _ = send(.editCursor(session.editCursor))
    }

    @QtIgnored
    public func refreshCamera() {
        guard let session else { return }
        _ = send(.camera(session.camera))
    }

    @QtIgnored
    public func refreshPlayhead(tick: Double, playing: Bool) {
        guard session != nil else { return }
        _ = send(.playhead(tick: tick, playing: playing))
    }

    // MARK: Qt seam

    public func handleEscape() -> Bool {
        send(.escape).consumed
    }

    public func cancelSectionInteraction() {
        _ = send(.cancel)
    }

    @discardableResult
    public func pointerPress(x: Double, y: Double, surface: Int, button: Int,
                             modifiers: Int) -> Bool {
        let input = DrawerPointerInput(
            x: x, y: y, qtButton: button, qtModifiers: modifiers, phase: .press)
        return send(.pointer(surface: VelocityInputSurface(rawValue: surface),
                             input: input)).consumed
    }

    @discardableResult
    public func pointerMove(x: Double, y: Double, buttons: Int) -> Bool {
        let input = DrawerPointerInput(x: x, y: y, qtButtons: buttons, phase: .move)
        return send(.pointer(surface: .plot, input: input)).consumed
    }

    @discardableResult
    public func pointerRelease(x: Double, y: Double, button: Int) -> Bool {
        let input = DrawerPointerInput(x: x, y: y, qtButton: button, phase: .release)
        return send(.pointer(surface: .plot, input: input)).consumed
    }

    public func pointerLeave() {
        _ = send(.pointer(
            surface: nil,
            input: DrawerPointerInput(x: 0, y: 0, qtButton: 0, phase: .leave)))
    }

    @discardableResult
    public func openSelectedVelocityPrompt() -> Bool {
        send(.openPrompt).consumed
    }

    public func updatePromptDraft(draft text: String) {
        _ = send(.promptDraft(text))
    }

    @discardableResult
    public func acceptPrompt() -> Bool {
        send(.acceptPrompt).accepted
    }

    public func cancelPrompt() {
        _ = send(.cancelPrompt)
    }

    public func setUseDetents(enabled: Bool) {
        _ = send(.setDetents(enabled))
    }

    public func toggleDetents() {
        _ = send(.toggleDetents)
    }

    // MARK: Synchronous adapter and ordered effects

    @discardableResult
    @QtIgnored
    func send(_ event: consuming VelocityEvent) -> VelocityTransition {
        switch event {
        case .openPrompt, .acceptPrompt:
            if session != nil {
                let facts = VelocityReducer.reduce(
                    &state, event: .document(documentFacts()), scene: sceneCache)
                pendingPublication.formUnion(facts.publication)
            }
        default:
            break
        }
        dispatchDepth += 1
        let transition = VelocityReducer.reduce(&state, event: event, scene: sceneCache)
        pendingPublication.formUnion(transition.publication)

        // The inout reduction is complete before an effect can synchronously
        // call back into the page with newer document or camera facts.
        for effect in transition.effects { execute(effect) }

        dispatchDepth -= 1
        if dispatchDepth == 0 { flushPublication() }
        return transition
    }

    private func execute(_ effect: borrowing VelocityEffect) {
        switch effect {
        case let .setOrderedSelection(ids):
            guard let session else { return }
            session.setSelectedNotes(ids)
            _ = send(.document(documentFacts()))
        case let .setVelocities(updates, expectedRevision):
            commitVelocities(updates, expectedRevision: expectedRevision)
            if session != nil { _ = send(.document(documentFacts())) }
        case let .panCamera(delta):
            guard let session else { return }
            session.mutateCamera { $0.setHScroll($0.snapshot.scrollX - delta) }
            _ = send(.camera(session.camera))
        case let .notifyAcceptedVelocity(value):
            onVelocityAccepted?(value)
        }
    }

    private func commitVelocities(_ updates: borrowing [NoteVelocity],
                                  expectedRevision: UInt64) {
        guard let session, !updates.isEmpty else { return }
        _ = session.document.setVelocities(updates, expectedRevision: expectedRevision)
    }

    private func flushPublication() {
        guard !pendingPublication.isEmpty else { return }
        let scope = pendingPublication
        pendingPublication = []
        syncPublishedState()
        guard scope.contains(.clear)
                  || (state.body.plotWidth > 0 && state.body.plotHeight > 0) else { return }
        if scope.contains(.content) { contentBuildCount &+= 1 }
        publish(scope)
    }

    private func syncPublishedState() {
        let body = state.body
        if plotWidth != body.plotWidth { plotWidth = body.plotWidth }
        if plotHeight != body.plotHeight { plotHeight = body.plotHeight }
        if rulerWidth != body.rulerWidth { rulerWidth = body.rulerWidth }
        if devicePixelRatio != body.devicePixelRatio {
            devicePixelRatio = body.devicePixelRatio
        }
        if baseFontPx != body.baseFontPx {
            baseFontPx = body.baseFontPx
            promptAppearance = PromptAppearance.metrics(base: body.baseFontPx)
            promptFont = PromptAppearance.font(base: body.baseFontPx)
            typographyCache = nil
            metricsCache = nil
        }
        if detentsEnabled != state.detentsEnabled {
            detentsEnabled = state.detentsEnabled
        }
    }
}

// MARK: - Note identity text

/// The bridge-side spelling of a token, and the spelling published handles
/// carry. `NoteID` is not a bridge type, so identity crosses as decimal text.
func velocityNoteText(_ id: NoteID) -> String { "\(id.rawValue)" }
