import Foundation
import PorydawCore
import QtBridge

public enum VoiceInputSurface: Int, Sendable {
    case gutter = 0
    case plot = 1
}

enum VoiceHintProfile {
    static let horizontalScroll = 12
    static let marker = 21
}

/// Qt/session adapter for the pure Voice Changes reducer and scene.
@MainActor
@QtBridgeable
public final class VoiceChangesPage: EditorDrawerPage {
    public static let contentUrl = "qrc:/porydaw/drawer/VoiceChangesPage.qml"

    @QtIgnored public let sectionKind: DrawerSectionKind = .voiceChanges
    @QtIgnored public var contentUrl: String { Self.contentUrl }
    @QtIgnored public var bodyPolicy: EditorDrawerBodyPolicy
    public var interactionActive: Bool = false

    // MARK: Published body facts

    public var plotOrigin: Double = 0
    public var plotWidth: Double = 0
    public var plotHeight: Double = 0
    public var devicePixelRatio: Double = 1
    public var baseFontPx: Double = GridCameraPolicy.seedBaseFontPx
    public var promptAppearance: [String: QVariantSettable] = [:]
    public var promptFont: [String: QVariantSettable] = [:]
    public var captionFont: [String: QVariantSettable] = [:]
    public var titleFont: [String: QVariantSettable] = [:]
    public var trackAvailable: Bool = false
    public var plotMessage: String = "No track selected"
    public var gutterTitle: String = "Voice"
    public var gutterTexts: QListModel<SceneText> = QListModel()
    public var readoutText: String = ""
    public var readoutVisible: Bool = false
    public var readoutRect: [String: QVariantSettable] = VoiceMarkerHandle.rect(0, 0, 0, 0)
    public var readoutAlignment: Int = VoiceChangesPagePolicy.readoutAlignment
    public var contextSlot: Int = -1
    public var contextBlank: Bool = true
    public var contextSymbol: String = ""
    public var hoverVisible: Bool = false
    public var hoverText: String = ""
    public var hoverLabelRect: [String: QVariantSettable] = VoiceMarkerHandle.rect(0, 0, 0, 0)
    public var hoverTick: Double = 0
    public var hoverHintProfile: Int = VoiceHintProfile.horizontalScroll
    public var cursorKind: Int = 0
    public var previewVisible: Bool = false
    public var previewX: Double = 0
    public var previewTick: Double = 0
    public var selectedIdentity: String = ""

    // MARK: Published modal state

    public var menuOpen: Bool = false
    public var menuX: Double = 0
    public var menuY: Double = 0
    public var pickerOpen: Bool = false
    public var pickerTitle: String = ""
    public var pickerFilter: String = ""
    public var pickerIndex: Int = -1
    public var pickerHasMatch: Bool = false
    public var pickerEmptyText: String = "No matching voices"
    public var auditionAvailable: Bool = false
    public var auditionDiagnostic: String = "Voice audition is unavailable."
    @QtIgnored public var onAuditionVoice: ((UInt8, UInt8, UInt8) -> Void)? {
        willSet { _ = send(.auditionOwnerWillChange) }
        didSet { requestPublication(.capability) }
    }

    // MARK: Published models

    public var markers: QListModel<VoiceMarkerHandle> = QListModel()
    public var heldSpans: QListModel<SceneRect> = QListModel()
    public var gridLines: QListModel<SceneRect> = QListModel()
    public var pickerRows: QListModel<VoicePickerRowHandle> = QListModel()
    public var menuRows: QListModel<VoiceMenuRowHandle> = QListModel()

    // MARK: Diagnostics and check-facing state

    @QtIgnored public internal(set) var contentBuildCount: UInt64 = 0
    @QtIgnored public var playheadPresentationCount: UInt64 { state.presentationCount }
    @QtIgnored public var contextChangeCount: UInt64 { state.contextChangeCount }
    @QtIgnored public var presentedContextTick: Tick { state.presentedTick }
    @QtIgnored public var presentedContextSlot: Int { state.contextSlot }
    @QtIgnored public var presentedPlaying: Bool { state.playing }

    @QtIgnored public var hasGesture: Bool { state.pointerMode.drag != nil }
    @QtIgnored public var hasPan: Bool {
        if case .pan = state.pointerMode { return true }
        return false
    }
    @QtIgnored public var hasPicker: Bool { state.modalMode.picker != nil }
    @QtIgnored public var hasMenu: Bool { state.modalMode.menu != nil }
    @QtIgnored public var publishedMarkers: [VoiceMarkerHandle] { markers.asArray }
    @QtIgnored public var markerIdentities: [String] { sceneCache.markers.map(\.identity) }
    @QtIgnored public var markerTicks: [Tick] { sceneCache.markers.map { Tick($0.tick) } }
    @QtIgnored public var frozenOccurrence: VoiceOccurrence? { state.pointerMode.drag?.occurrence }
    @QtIgnored public var frozenIdentity: String? { state.pointerMode.drag?.identity }
    @QtIgnored public var dragPreviewTick: Tick? { state.pointerMode.drag?.previewTick }
    @QtIgnored public var dragActive: Bool { state.pointerMode.activeDrag != nil }
    @QtIgnored public var pickerTargetTick: Tick? { state.modalMode.picker?.target.tick }
    @QtIgnored public var pickerTargetIdentity: String? {
        state.modalMode.picker?.target.occurrence?.text
    }
    @QtIgnored public var menuTargetTick: Tick? { state.modalMode.menu?.target.tick }
    @QtIgnored public var menuTargetIdentity: String? {
        state.modalMode.menu?.target.occurrence?.text
    }
    @QtIgnored public var pickerRowValues: [VoicePickerRowHandle] { pickerRows.asArray }
    @QtIgnored public var pickerProgram: Int { state.modalMode.picker?.program ?? -1 }
    @QtIgnored public var pickerRowPrograms: [Int] { sceneCache.modal.pickerRows.map(\.program) }
    @QtIgnored public var menuRowActions: [Int] { sceneCache.modal.menuRows.map(\.actionId) }
    @QtIgnored public var publishedSlotCount: Int { state.bank.count }
    @QtIgnored public var presentedContextLabel: String {
        VoiceChangesScene.contextLabel(slot: state.contextSlot, bank: state.bank)
    }
    @QtIgnored public var presentedContextEndTick: Tick {
        VoiceLanePolicy.endTick(after: state.presentedTick, points: state.lane.points)
            ?? TimeDefaults.noTick
    }

    @QtIgnored
    public func contextLabel(at slot: Int) -> String {
        VoiceChangesScene.contextLabel(slot: slot, bank: state.bank)
    }

    // MARK: Adapter-owned state and caches

    @QtIgnored weak var session: DocumentSession?
    @QtIgnored var palette = GridPalette()
    @QtIgnored var state = VoiceChangesState()
    @QtIgnored var sceneCache = VoiceChangesScene.detached
    @QtIgnored let typography = VoiceTypographyAdapter()
    @QtIgnored var markerRows: [VoiceMarkerValue] = []
    @QtIgnored var typographySnapshot: VoiceTypographyValues?
    @QtIgnored var spanRows: [DrawerRectValue] = []
    @QtIgnored var gridRows: [DrawerRectValue] = []
    @QtIgnored var gutterRows: [DrawerTextValue] = []
    @QtIgnored var pickerRowDescriptors: [VoicePickerRowValue] = []
    @QtIgnored var menuRowDescriptors: [VoiceMenuRowValue] = []
    @QtIgnored var metricsKey: MetricsKey?
    @QtIgnored var cachedMetrics: GridMetrics?
    @QtIgnored var entriesRevision: UInt64?
    @QtIgnored var entriesTrack: Int?
    @QtIgnored var cachedEntries: [VoiceProjectionEntry] = []
    @QtIgnored var dispatchDepth = 0
    @QtIgnored var pendingPublication: VoiceChangesPublicationScope = []
    @QtIgnored var isPublishing = false
    @QtIgnored var configuredWidth: Double = 0
    @QtIgnored var configuredHeight: Double = 0
    @QtIgnored var configuredGutter: Double = 0
    @QtIgnored var configuredDpr: Double = 1
    @QtIgnored var configuredFont: Double = GridCameraPolicy.seedBaseFontPx
    @QtIgnored var configuredDragDistance: Double = 10

    struct MetricsKey: Equatable {
        var revision: UInt64
        var font: Double
        var dpr: Double
        var width: Double
        var height: Double
    }

    public init(baseFontPx: Double = VoiceChangesPagePolicy.seedBaseFontPx) {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx : GridCameraPolicy.seedBaseFontPx
        let minimum = max(1, Int((base * 17.0 / 5.0).rounded()))
        let maximum = Int((Double(minimum) * VoiceChangesPagePolicy.maximumBodyRows).rounded())
        bodyPolicy = EditorDrawerBodyPolicy(maximumBodyHeight: maximum) { _, _ in minimum }
        configuredFont = base
        typographySnapshot = typography.values(baseFontPx: base, labels: ["No voice"])
    }

    // MARK: Lifecycle and session refresh

    @QtIgnored
    public func attach(session: DocumentSession, palette: GridPalette) {
        if state.attached { _ = send(.cancelAll) }
        self.session = session
        self.palette = palette
        invalidateDocumentCaches()
        let lane = laneFacts(session)
        let view = viewFacts(session)
        _ = send(.attached(
            lane: lane, bank: session.bankSlots, view: view,
            editCursor: session.editCursor))
    }

    @QtIgnored
    public func detach() {
        _ = send(.detached)
        session = nil
        invalidateDocumentCaches()
    }

    public func configureBody(width: Double, height: Double, gutter: Double,
                              devicePixelRatio: Double, baseFontPx: Double,
                              dragDistance: Double) {
        let nextWidth = max(0, width.isFinite ? width : 0)
        let nextHeight = max(0, height.isFinite ? height : 0)
        let nextGutter = max(0, gutter.isFinite ? gutter : 0)
        let nextDpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        let nextFont = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx : GridCameraPolicy.seedBaseFontPx
        let nextDrag = dragDistance.isFinite && dragDistance > 0 ? dragDistance : 10
        configuredWidth = nextWidth
        configuredHeight = nextHeight
        configuredGutter = nextGutter
        configuredDpr = nextDpr
        configuredFont = nextFont
        configuredDragDistance = nextDrag
        guard let session else { return }
        let unchanged = state.view.map {
            $0.plotWidth == nextWidth && $0.plotHeight == nextHeight
                && $0.plotOrigin == nextGutter && $0.devicePixelRatio == nextDpr
                && $0.baseFontPx == nextFont && $0.dragDistance == nextDrag
        } ?? false
        guard !unchanged else { return }
        let view = viewFacts(
            session, width: nextWidth, height: nextHeight, gutter: nextGutter,
            dpr: nextDpr, font: nextFont, dragDistance: nextDrag)
        _ = send(.viewChanged(view))
    }

    @QtIgnored
    public func refreshFromDocument() {
        guard let session else { return }
        let lane = laneFacts(session)
        if entriesRevision != lane.revision || entriesTrack != lane.track {
            entriesRevision = nil
            entriesTrack = nil
        }
        metricsKey = nil
        cachedMetrics = nil
        let view = viewFacts(session)
        _ = send(.documentChanged(
            lane: lane, bank: session.bankSlots, view: view,
            editCursor: session.editCursor))
    }

    @QtIgnored
    public func refreshEditCursor() {
        guard let session else { return }
        _ = send(.editCursorChanged(session.editCursor))
    }

    @QtIgnored
    public func refreshCamera() {
        guard let session else { return }
        _ = send(.viewChanged(viewFacts(session)))
    }

    @QtIgnored
    public func refreshPlayhead(tick: Double, playing: Bool) {
        _ = send(.playheadChanged(tick: velocityContextTick(tick), playing: playing))
    }

    // MARK: Qt-facing input

    public func handleEscape() -> Bool { send(.escape).consumed }

    public func cancelSectionInteraction() { _ = send(.cancelAll) }

    @discardableResult
    public func pointerPress(x: Double, y: Double, surface: Int, button: Int,
                             modifiers: Int) -> Bool {
        guard let surface = VoiceInputSurface(rawValue: surface) else { return false }
        let input = DrawerPointerInput(
            x: x, y: y, qtButton: button, qtModifiers: modifiers, phase: .press)
        let target = captureTarget(at: input.x)
        return send(.pointerPressed(VoicePointerPress(
            x: input.x, y: input.y, surface: surface,
            button: input.changedButton, target: target))).consumed
    }

    @discardableResult
    public func pointerMove(x: Double, y: Double, buttons: Int,
                            modifiers: Int = 0) -> Bool {
        let input = DrawerPointerInput(
            x: x, y: y, qtButtons: buttons, qtModifiers: modifiers, phase: .move)
        let hit = markerHit(at: input.x)
        let tick = VoiceChangesScene.snapTick(
            at: input.x, fine: input.modifiers.alt, state: state)
        return send(.pointerMoved(VoicePointerMove(
            x: input.x, hit: hit, snappedTick: tick))).consumed
    }

    @discardableResult
    public func pointerRelease(x: Double, y: Double, button: Int) -> Bool {
        let input = DrawerPointerInput(x: x, y: y, qtButton: button, phase: .release)
        return send(.pointerReleased(VoicePointerRelease(
            button: input.changedButton, hit: markerHit(at: input.x)))).consumed
    }

    public func pointerLeave() { _ = send(.pointerLeft) }

    @discardableResult
    public func pointerDoubleClick(x: Double, y: Double) -> Bool {
        _ = y
        let target = captureTarget(at: x)
        let bank = session?.bankSlots ?? state.bank
        return send(.pointerDoubleClicked(VoicePointerDoubleClick(
            target: target, bank: bank))).consumed
    }

    public func setPickerFilter(text: String) { _ = send(.pickerFilterChanged(text)) }
    public func selectPickerRow(index: Int) { _ = send(.pickerRowSelected(index)) }
    public func pressAndHoldPickerRow(index: Int) { _ = send(.pickerRowHeld(index)) }
    public func releasePickerAudition() { _ = send(.pickerAuditionReleased) }
    public func movePickerSelection(delta: Int) { _ = send(.pickerSelectionMoved(delta)) }

    @discardableResult
    public func acceptPicker() -> Bool {
        let result = send(.pickerAccepted)
        return result.accepted || result.committed
    }

    public func cancelPicker() { _ = send(.pickerCancelled) }

    @discardableResult
    public func activateMenuAction(actionId: Int) -> Bool {
        let result = send(.menuActionActivated(actionId))
        return result.accepted || result.committed
    }

    @discardableResult
    public func activateMenuRow(index: Int) -> Bool {
        guard sceneCache.modal.menuRows.indices.contains(index) else { return false }
        return activateMenuAction(actionId: sceneCache.modal.menuRows[index].actionId)
    }

    public func dismissVoiceMenu() { _ = send(.menuDismissed) }
    public func dismissModal() { _ = send(.modalDismissed) }

    // MARK: Synchronous reducer/effect seam

    @discardableResult
    private func send(_ event: consuming VoiceChangesEvent) -> VoiceChangesOutcome {
        dispatchDepth += 1
        let transition = VoiceChangesInteraction.reduce(state, event: event)
        state = transition.state
        pendingPublication.formUnion(transition.publication)
        for effect in transition.effects { execute(effect) }
        dispatchDepth -= 1
        flushPublicationIfReady()
        return transition.outcome
    }

    private func requestPublication(_ scope: VoiceChangesPublicationScope) {
        pendingPublication.formUnion(scope)
        flushPublicationIfReady()
    }

    private func flushPublicationIfReady() {
        guard dispatchDepth == 0, !isPublishing, !pendingPublication.isEmpty else { return }
        let scope = pendingPublication
        pendingPublication = []
        isPublishing = true
        publish(scope)
        isPublishing = false
        if !pendingPublication.isEmpty { flushPublicationIfReady() }
    }

    private func execute(_ effect: consuming VoiceChangesEffect) {
        switch effect {
        case let .mutateCamera(deltaX):
            session?.mutateCamera { $0.setHScroll($0.snapshot.scrollX - deltaX) }
        case let .commit(mutation):
            if let session { VoiceChangesTransactions.apply(mutation, to: session) }
        case let .audition(program, key, velocity):
            guard let program = UInt8(exactly: program), let key = UInt8(exactly: key),
                  let velocity = UInt8(exactly: velocity) else { return }
            onAuditionVoice?(program, key, velocity)
        }
    }


    // MARK: Fact decoding

    private func currentTrack(_ session: DocumentSession) -> Int? {
        guard let track = session.selectedTrack, track >= 0,
              track < session.timeline.tracks.count else { return nil }
        return track
    }

    private func laneFacts(_ session: DocumentSession) -> VoiceLaneFacts {
        let track = currentTrack(session)
        return VoiceLaneFacts(
            revision: session.document.revision,
            track: track,
            points: track.map { session.projectionCache.lanePoints(track: $0, lane: .voice) } ?? [],
            firstProgram: track.map { session.timeline.tracks[$0].firstProgram } ?? -1,
            lengthTicks: session.timeline.lengthTicks,
            division: session.document.ticksPerBeat,
            extendedClocks: session.document.state.config.extendedClocks)
    }

    private func viewFacts(_ session: DocumentSession, width: Double? = nil,
                           height: Double? = nil, gutter: Double? = nil,
                           dpr: Double? = nil, font: Double? = nil,
                           dragDistance: Double? = nil) -> VoiceViewFacts {
        let current = state.view
        let width = width ?? current?.plotWidth ?? configuredWidth
        let height = height ?? current?.plotHeight ?? configuredHeight
        let gutter = gutter ?? current?.plotOrigin ?? configuredGutter
        let dpr = dpr ?? current?.devicePixelRatio ?? configuredDpr
        let font = font ?? current?.baseFontPx ?? configuredFont
        let dragDistance = dragDistance ?? current?.dragDistance ?? configuredDragDistance
        return VoiceViewFacts(
            plotOrigin: gutter, plotWidth: width, plotHeight: height,
            devicePixelRatio: dpr, baseFontPx: font, dragDistance: dragDistance,
            camera: session.camera,
            metrics: gridMetrics(session, width: width, height: height, dpr: dpr, font: font))
    }

    private func captureTarget(at x: Double) -> VoiceTarget? {
        guard let track = state.lane.track else { return nil }
        let occurrence = markerHit(at: x)
        return VoiceTarget(
            revision: state.lane.revision,
            track: track,
            tick: occurrence?.tick ?? VoiceChangesScene.snapTick(at: x, fine: false, state: state),
            occurrence: occurrence)
    }

    private func markerHit(at x: Double) -> VoiceOccurrence? {
        VoiceChangesScene.markerHit(
            at: x, markers: sceneCache.markers,
            baseFontPx: state.view?.baseFontPx ?? baseFontPx)
    }

    private func gridMetrics(_ session: DocumentSession, width: Double, height: Double,
                             dpr: Double, font: Double) -> GridMetrics {
        let key = MetricsKey(
            revision: session.document.revision, font: font, dpr: dpr,
            width: width, height: height)
        if metricsKey == key, let cachedMetrics { return cachedMetrics }
        let value = GridMetrics(
            baseFontPx: font, dpr: dpr, width: width, height: height,
            timeAxis: session.projectionCache.timeAxis)
        metricsKey = key
        cachedMetrics = value
        return value
    }

    func markerEntries() -> [VoiceProjectionEntry] {
        guard state.attached, let track = state.lane.track else { return [] }
        if entriesRevision != state.lane.revision || entriesTrack != track {
            cachedEntries = VoiceChangesProjection.entries(points: state.lane.points)
            entriesRevision = state.lane.revision
            entriesTrack = track
        }
        return cachedEntries
    }

    private func invalidateDocumentCaches() {
        metricsKey = nil
        cachedMetrics = nil
        entriesRevision = nil
        entriesTrack = nil
        cachedEntries.removeAll(keepingCapacity: true)
    }

    static let fontFamily = "Atkinson Hyperlegible Next"
}
