import PorydawCore

/// Page-owned domain facts, independent of camera and paint. Frozen gestures
/// retain value snapshots when the live revision advances.
@MainActor
final class AutomationProjectionCache {
    private var sessionID: ObjectIdentifier?
    private var revision: UInt64?
    private var songEnd: Tick?
    private var lanes: [AutomationParameter: AutomationLaneSnapshot] = [:]
    private var rowFacts: AutomationRowStack?
    private var rowTrack: Int?
    private var rowSelection: AutomationTimeSelection?
    private var rowReady = false
    private var rowUsedTracks = -1
    private var policies: [AutomationParameter: (
        revision: UInt64, range: Int?, font: Double, selection: GridSelection,
        feel: GridFeel, projection: AutomationProjection)] = [:]

    private func refresh(_ session: DocumentSession) {
        let id = ObjectIdentifier(session)
        guard sessionID != id || revision != session.document.revision
            || songEnd != session.timeline.lengthTicks else { return }
        sessionID = id
        revision = session.document.revision
        songEnd = session.timeline.lengthTicks
        lanes.removeAll(keepingCapacity: true)
        rowFacts = nil
        policies.removeAll(keepingCapacity: true)
    }

    func snapshot(_ parameter: AutomationParameter,
                  session: DocumentSession) -> AutomationLaneSnapshot {
        refresh(session)
        if let snapshot = lanes[parameter] { return snapshot }
        let points = parameter.lane.flatMap { lane in
            parameter.track.map { session.projectionCache.lanePoints(track: $0, lane: lane) }
        }
        let snapshot = AutomationLaneSnapshot(parameter: parameter, in: session.document,
            songEndTick: session.timeline.lengthTicks, lanePoints: points)
        lanes[parameter] = snapshot
        return snapshot
    }

    func rows(session: DocumentSession, track: Int?, selection: AutomationTimeSelection?,
              ready: Bool) -> AutomationRowStack {
        refresh(session)
        let used = session.document.engineTracks.usedTrackCount
        if let rowFacts, rowTrack == track, rowSelection == selection,
           rowReady == ready, rowUsedTracks == used { return rowFacts }
        let rows = AutomationRowStack.build(document: session.document, primaryTrack: track,
            selection: selection, ready: ready, songEndTick: session.timeline.lengthTicks,
            snapshot: { self.snapshot($0, session: session) })
        rowTrack = track
        rowSelection = selection
        rowReady = ready
        rowUsedTracks = used
        rowFacts = rows
        return rows
    }

    func projection(snapshot: AutomationLaneSnapshot, session: DocumentSession,
                    camera: EditorCamera, bounds: AutomationPlotBounds,
                    geometry: AutomationPlotGeometry, font: Double,
                    range: Int?) -> AutomationProjection {
        refresh(session)
        if let cached = policies[snapshot.parameter], cached.revision == snapshot.revision,
           cached.range == range, cached.font == font,
           cached.selection == session.grid.selection, cached.feel == session.grid.feel,
           cached.projection.camera.snapshot == camera.snapshot,
           cached.projection.bounds == bounds, cached.projection.geometry == geometry,
           cached.projection.songEndTick == snapshot.songEndTick {
            return cached.projection
        }
        let projection = AutomationProjection(camera: camera, bounds: bounds, geometry: geometry,
            snapPolicy: snapPolicy(session: session, font: font, dpr: bounds.devicePixelRatio),
            songEndTick: snapshot.songEndTick,
            displayMaximum: AutomationProjection.displayMaximum(snapshot: snapshot, range: range))
        policies[snapshot.parameter] = (
            snapshot.revision, range, font, session.grid.selection, session.grid.feel, projection)
        return projection
    }

    func snapPolicy(session: DocumentSession, font: Double, dpr: Double) -> AutomationSnapPolicy {
        var grid = session.grid
        grid.metrics = GridMetrics(baseFontPx: font, dpr: dpr, width: 0, height: 0,
                                   timeAxis: grid.axis)
        return AutomationSnapPolicy(grid: grid, clockTicks: session.gridClockTicks)
    }
}
