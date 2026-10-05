import PorydawCore

/// One document's viewport presentation: the camera, the roll grid, the scale
/// and the drawer view state. It owns no document state and edits nothing in
/// the song or its history.
///
/// The viewport repairs itself through the session's `onViewportRepair` hook,
/// inside the session's state-change batch and before any change publication
/// fans out, so every change consumer reads already-repaired presentation.
/// That hook is a single slot: a session has exactly one viewport.
@MainActor
public final class DocumentViewport {
    public let session: DocumentSession
    public private(set) var camera: EditorCamera
    public var grid: RollGrid
    public internal(set) var scale = ScaleProjection()
    public internal(set) var editorViewState = EditorViewState()

    /// Camera publication with the field-level delta the workspace uses to
    /// choose projection-only drawer updates.
    public var onCameraChangeDetailed: ((EditorCamera.Snapshot, EditorCamera.Change) -> Void)?
    /// A changed origin publishes once; sibling projections do not publish.
    public var onEditorViewStateChanged: ((EditorViewState) -> Void)?

    public init(session: DocumentSession) {
        self.session = session
        camera = EditorCamera(
            ticksPerBeat: UInt32(max(1, session.document.ticksPerBeat)),
            lengthTicks: UInt64(session.timeline.lengthTicks),
            viewportWidth: 0,
            rollHeight: 0,
            limits: GridCameraPolicy.limits(baseFontPx: GridCameraPolicy.seedBaseFontPx))
        grid = RollGrid(clockTicks: session.gridClockTicks)
        syncTimeAxis()
        session.onViewportRepair = { [weak self] repair in
            self?.repair(repair)
        }
    }

    /// Applies one camera mutation and publishes exactly once when either the
    /// numeric snapshot or the pitch projection changes.
    @discardableResult
    public func mutateCamera(_ body: (inout EditorCamera) -> Void) -> Bool {
        let oldSnapshot = camera.snapshot
        let oldProjection = camera.projection
        body(&camera)
        let newSnapshot = camera.snapshot
        let projectionChanged = camera.projection != oldProjection
        guard newSnapshot != oldSnapshot || projectionChanged else {
            return false
        }
        let change = EditorCamera.Change.between(
            oldSnapshot, newSnapshot, projectionChanged: projectionChanged)
        onCameraChangeDetailed?(newSnapshot, change)
        return true
    }

    /// Points the grid at the document's current time axis. The only writer of
    /// `grid.axis`, so the roll, the drawer pages and the timeline repair all
    /// read the same axis.
    @discardableResult
    public func syncTimeAxis() -> TimeAxis {
        let axis = session.projectionCache.timeAxis
        grid.axis = axis
        return axis
    }

    // MARK: - Scale

    /// Changes one tab's display state without changing MIDI or song history.
    public func setScale(root: Int) {
        var next = scale
        next.setRoot(root)
        applyScale(next)
    }

    public func setScale(type: ScaleID) {
        var next = scale
        next.setScale(type)
        applyScale(next)
    }

    public func setScale(highlight: Bool) {
        var next = scale
        next.highlight = highlight
        applyScale(next)
    }

    public func setScale(fold: Bool) {
        var next = scale
        next.fold = fold
        applyScale(next)
    }

    private func applyScale(_ next: ScaleProjection) {
        guard next != scale else { return }
        let foldChanged = next.fold != scale.fold
        scale = next
        if foldChanged { refreshScaleProjection() }
        session.noteScaleChanged()
    }

    private func refreshScaleProjection() {
        let notes = session.selectedTrack.map { session.document.notes(in: $0) } ?? []
        let rows = scale.projection(notes: notes)
        guard rows != camera.projection else { return }
        let before = camera.snapshot
        let centeredPitch = camera.projection.pitch(
            atY: before.rollHeight / 2, keyHeight: before.keyHeight,
            scrollY: before.scrollY, dpr: 1)
        mutateCamera {
            $0.updateProjection(rows)
            if let centeredPitch, let nearest = rows.nearestVisiblePitch(to: centeredPitch) {
                _ = $0.setVScroll(
                    Double(rows.row(forPitch: nearest)) * before.keyHeight
                        - before.rollHeight / 2)
            }
        }
    }

    // MARK: - Editor view state

    /// Sets presentation-only editor state without document history.
    /// Returns true only for a changed value and publishes its origin once.
    @discardableResult
    public func setEditorViewState(_ state: EditorViewState) -> Bool {
        guard editorViewState != state else { return false }
        editorViewState = state
        onEditorViewStateChanged?(state)
        return true
    }

    /// Adopts the application-wide state another tab published, silently.
    public func applyEditorViewStateProjection(_ state: EditorViewState) {
        editorViewState = state
    }

    // MARK: - Session repair

    private func repair(_ repair: ViewportRepair) {
        switch repair {
        case .trackRemap(let remap):
            var next = editorViewState
            if next.remapEngineTracks(remap.engineTrackMap) {
                setEditorViewState(next)
            }
        case .scaleFold:
            if scale.fold { refreshScaleProjection() }
        case .timeDomain:
            camera.updateTimeDomain(
                ticksPerBeat: UInt32(max(1, session.document.ticksPerBeat)),
                lengthTicks: UInt64(session.timeline.lengthTicks))
            syncTimeAxis()
            grid.setTicksPerClock(session.gridClockTicks)
        }
    }
}
