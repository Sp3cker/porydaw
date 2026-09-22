import Foundation
import PorydawCore

// The pure Automation projection domain: the font-relative interaction
// geometry, the grid/clock snapping lattice, and the per-event projection
// engine over the shared camera. Every x is plot-relative (0 = the plot's
// left edge); the page publishes the plot origin separately.

// MARK: - Geometry and snapping

/// One half-open visible grid cell. A tick on a boundary belongs to the cell
/// that begins there, which is the single boundary rule for snapping, pencil
/// cells and hit testing.
public struct AutomationGridCell: Equatable, Sendable {
    public let tickBegin: Tick
    public let tickEnd: Tick

    public init(tickBegin: Tick, tickEnd: Tick) {
        self.tickBegin = tickBegin
        self.tickEnd = tickEnd
    }

    public func contains(_ rawTick: Double) -> Bool {
        rawTick >= Double(tickBegin) && rawTick < Double(tickEnd)
    }
}

/// `AutomationGeometry::resolve`: the font-relative interaction geometry.
public struct AutomationPlotGeometry: Equatable, Sendable {
    public let rowHeight: Double
    public let pointHitRadius: Double
    public let neutralSnapRadius: Double
    public let nodeDragActivationDistance: Double
    public let pointDetailThreshold: Double
    public let valuePlotPadding: Double

    public init(baseFontPx: Double) {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        let nodePaintRadius = fontPxF(base, 3.0 / 16.0)
        let nodeOutlineDipWidth = fontPxF(base, 1.0 / 12.0)
        let selectedRingRadius = fontPxF(base, 9.0 / 32.0)
        let selectedRingDipWidth = fontPxF(base, 1.0 / 5.0)
        rowHeight = fontPx(base, 4.0)
        pointHitRadius = fontPx(base, 7.0 / 12.0)
        neutralSnapRadius = fontPx(base, 2.0 / 3.0)
        nodeDragActivationDistance = fontPx(base, 5.0 / 12.0)
        pointDetailThreshold = fontPx(base, 2.0)
        // Endpoint centers sit at the painted outer edge, marker stroke included.
        valuePlotPadding = (max(nodePaintRadius + nodeOutlineDipWidth,
                                selectedRingRadius + selectedRingDipWidth * 0.5)).rounded()
    }
}

/// The plot rectangle the automation body owns, in the page's own units.
public struct AutomationPlotBounds: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var devicePixelRatio: Double

    public init(width: Double = 0, height: Double = 0, devicePixelRatio: Double = 1) {
        self.width = max(0, width.isFinite ? width : 0)
        self.height = max(0, height.isFinite ? height : 0)
        self.devicePixelRatio = devicePixelRatio.isFinite && devicePixelRatio > 0
            ? devicePixelRatio : 1
    }
}

/// The snapping lattice: the shared visible grid for a coarse pointer position,
/// and the shared document clock lattice for a fine (Alt) one.
public struct AutomationSnapPolicy: Sendable {
    private let metrics: GridMetrics
    public let clockTicks: Tick

    init(baseFontPx: Double, devicePixelRatio: Double, timeAxis: TimeAxis,
         clockTicks: Tick) {
        metrics = GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio, width: 0, height: 0,
                              timeAxis: timeAxis)
        self.clockTicks = max(1, clockTicks)
    }

    @MainActor
    public init(document: SongDocument, timeline: PlaybackTimeline, baseFontPx: Double,
                devicePixelRatio: Double) {
        self.init(baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio,
                  timeAxis: TimeAxis(map: TimeMap(
                      ticksPerBeat: UInt32(max(1, document.ticksPerBeat)),
                      lengthTicks: timeline.lengthTicks,
                      loopStartTick: timeline.loopStartTick,
                      loopEndTick: timeline.loopEndTick,
                      timeSigs: document.timeSignatures.map {
                          TimeSigPoint(tick: $0.tick, numerator: $0.numerator,
                                       denomPow2: $0.denominatorPower)
                      })),
                  clockTicks: TimelineSnapPolicy.clockTicks(
                      division: document.ticksPerBeat,
                      extendedClocks: document.state.config.extendedClocks))
    }


    public func snap(_ tick: Double, fine: Bool, camera: EditorCamera) -> Tick {
        fine ? TimelineSnapPolicy.fineSnap(tick, clockTicks: clockTicks)
             : Tick(metrics.snapTick(tick, camera: camera))
    }

    public func snapDown(_ tick: Double, fine: Bool, camera: EditorCamera) -> Tick {
        let position = max(0, tick)
        guard fine else { return Tick(metrics.snapTickDown(position, camera: camera)) }
        let limit = Double(TimeDefaults.maxTick)
        let clamped = min(position, limit)
        return Tick(min(limit, (clamped / Double(clockTicks)).rounded(.down) * Double(clockTicks)))
    }

    /// `Grid::nextSnapTickAfter`, clamped to `limit`.
    public func next(after tick: Tick, fine: Bool, limit: Tick, camera: EditorCamera) -> Tick {
        if tick >= limit { return limit }
        if fine {
            let next = (UInt64(tick) / UInt64(clockTicks) + 1) * UInt64(clockTicks)
            return min(limit, Tick(min(next, UInt64(TimeDefaults.maxTick))))
        }
        let candidate = metrics.snapTickUp(Double(tick) + 1, camera: camera)
        return min(limit, Tick(max(Int(tick) + 1, candidate)))
    }
}

// MARK: - Projection

/// Per-event projection over the shared camera: tick to x, value to y, the
/// snapping lattice, and cell traversal. Construct one per pointer event or
/// build pass, exactly as production does.
public struct AutomationProjection: Sendable {
    public let camera: EditorCamera
    public let bounds: AutomationPlotBounds
    public let geometry: AutomationPlotGeometry
    public let snapPolicy: AutomationSnapPolicy
    public let songEndTick: Tick
    public let displayMaximum: Int?

    public static func displayMaximum(snapshot: AutomationLaneSnapshot, range: Int?) -> Int? {
        guard snapshot.metadata.zoomable else { return nil }
        let range = range ?? Int(AutomationCatalog.defaultRange(snapshot.parameter.controller ?? 0))
        guard range == 0 else { return range }
        let maximum = snapshot.displaySeries.map(\.value).max() ?? 0
        return Int(AutomationCatalog.autoRange(maximum: maximum))
    }

    public init(camera: EditorCamera, bounds: AutomationPlotBounds,
                geometry: AutomationPlotGeometry, snapPolicy: AutomationSnapPolicy,
                songEndTick: Tick, displayMaximum: Int? = nil) {
        self.camera = camera
        self.bounds = bounds
        self.geometry = geometry
        self.snapPolicy = snapPolicy
        self.songEndTick = songEndTick
        self.displayMaximum = displayMaximum
    }

    // MARK: Time

    public func contentX(_ tick: Tick) -> Double { camera.contentX(tick: Double(tick)) }

    /// The display x of a tick: the camera's projection, snapped to the physical
    /// pixel grid exactly as the roll and every other page snap theirs.
    public func x(_ tick: Tick) -> Double {
        let value = camera.contentX(tick: Double(tick))
        let scale = bounds.devicePixelRatio
        return scale > 0 ? (value * scale).rounded() / scale : value
    }

    /// The raw (unsnapped) tick under an x, clamped to `[0, songEnd]`.
    public func rawTick(atX x: Double) -> Double {
        min(max(0, camera.tickAtContentX(max(0, x))), Double(songEndTick))
    }

    public func tick(atX x: Double, fine: Bool) -> Tick {
        snapPolicy.snap(rawTick(atX: x), fine: fine, camera: camera)
    }

    public func nextGridTick(after tick: Tick, fine: Bool) -> Tick {
        snapPolicy.next(after: tick, fine: fine, limit: songEndTick, camera: camera)
    }

    /// The half-open cell a raw tick lands in. The song's end tick belongs to the
    /// cell that ends there, so a position at the end never starts a new one.
    public func cell(atRawTick rawTick: Double) -> AutomationGridCell {
        guard songEndTick > 0 else { return AutomationGridCell(tickBegin: 0, tickEnd: 0) }
        let clamped = min(max(0, rawTick), Double(songEndTick))
        let position = clamped >= Double(songEndTick) ? songEndTick - 1 : Tick(clamped)
        let begin = snapPolicy.snapDown(Double(position), fine: false, camera: camera)
        return AutomationGridCell(tickBegin: begin,
                                  tickEnd: nextGridTick(after: begin, fine: false))
    }

    /// Every cell the pointer crossed from `previous` to `current`, in traversal
    /// order and including both endpoint cells. Stops at the same guards as
    /// production: a cell that cannot advance, or a walk past the song's end.
    public func cellsCrossed(from previous: Double, to current: Double) -> [AutomationGridCell] {
        guard songEndTick > 0 else { return [] }
        let forward = current >= previous
        let target = cell(atRawTick: current)
        var crossed: [AutomationGridCell] = []
        var current = cell(atRawTick: previous)
        while current.tickBegin < current.tickEnd && current.tickEnd <= songEndTick {
            crossed.append(current)
            if current.tickBegin == target.tickBegin { return crossed }
            if forward {
                let nextStart = nextGridTick(after: current.tickBegin, fine: false)
                if nextStart >= songEndTick { break }
                let next = cell(atRawTick: Double(nextStart))
                if next.tickBegin <= current.tickBegin { break }
                current = next
            } else {
                if current.tickBegin == 0 { break }
                let previousCell = cell(atRawTick: Double(current.tickBegin - 1))
                if previousCell.tickBegin >= current.tickBegin { break }
                current = previousCell
            }
        }
        return crossed
    }

    // MARK: Value

    /// The value axis: the parameter maximum sits at the top edge of the padded
    /// plot, the minimum at the bottom.
    public func y(_ value: Int, metadata: AutomationParameterMetadata) -> Double {
        let top = geometry.valuePlotPadding
        let bottom = max(top, bounds.height - geometry.valuePlotPadding)
        let clamped = Double(metadata.clamp(value))
        let span = max(1, (displayMaximum ?? metadata.maximum) - metadata.minimum)
        return bottom - (clamped - Double(metadata.minimum)) * (bottom - top) / Double(span)
    }

    public func value(atY y: Double, metadata: AutomationParameterMetadata) -> Int {
        let top = geometry.valuePlotPadding
        let bottom = max(top, bounds.height - geometry.valuePlotPadding)
        let clamped = min(max(y, top), bottom)
        let span = Double((displayMaximum ?? metadata.maximum) - metadata.minimum)
        let exact = Double(metadata.minimum)
            + (bottom - clamped) * span / max(1.0, bottom - top)
        return metadata.clamp(Int(exact.rounded()))
    }

    /// `AutomationProjection::nodeMarkersVisible`: node markers only at a zoom
    /// that can show them.
    public func markersVisible() -> Bool {
        camera.snapshot.pixelsPerBeat >= geometry.pointDetailThreshold
    }

    // MARK: Lane projection

    /// Project one frozen lane snapshot. Pure: nothing here mutates the document.
    public func project(_ snapshot: AutomationLaneSnapshot,
                        selection: AutomationTimeSelection? = nil,
                        usedTracks: Set<Int> = []) -> AutomationLaneProjection {
        let metadata = snapshot.metadata
        let covers = selection?.covers(snapshot.parameter, usedTracks: usedTracks) ?? false
        let range = covers ? selection?.range : nil

        func projected(_ tick: Tick, _ value: Int, identity: AutomationPointIdentity,
                       projectedNode: Bool) -> AutomationProjectedPoint {
            AutomationProjectedPoint(
                identity: identity, tick: tick, value: value,
                x: x(tick), y: y(value, metadata: metadata),
                selected: range.map { $0.contains(tick) } ?? false,
                projected: projectedNode)
        }

        // Display points: the synthetic tick-zero node first, then the written
        // occurrences with the last at a tick winning, as the lane adapters do.
        let points: [AutomationProjectedPoint] = snapshot.displaySeries.map { item in
            projected(item.tick, item.value, identity: item.identity,
                      projectedNode: item.projected)
        }

        let leadIn = snapshot.leadInValue.map {
            projected(0, metadata.clamp($0),
                      identity: AutomationPointIdentity(
                          revision: snapshot.revision, parameter: snapshot.parameter, tick: 0,
                          occurrence: -1, value: metadata.clamp($0)),
                      projectedNode: true)
        }

        // The step/ramp curve: each point holds (or ramps) into the next, the
        // last one runs to the song's end, and the lead-in opens the lane.
        var segments: [AutomationCurveSegment] = []
        if let leadIn, let first = points.first, leadIn.value != first.value {
            segments.append(AutomationCurveSegment(
                kind: .step, tickBegin: 0, tickEnd: first.tick, fromValue: leadIn.value,
                toValue: leadIn.value, isLeadIn: true, isSelected: false))
        }
        for (index, point) in points.enumerated() {
            let next = index + 1 < points.count ? points[index + 1] : nil
            let kind: AutomationCurveSegment.Kind =
                metadata.interpolation == .ramp ? .ramp : .step
            segments.append(AutomationCurveSegment(
                kind: kind, tickBegin: point.tick, tickEnd: next?.tick,
                fromValue: point.value,
                toValue: kind == .ramp ? (next?.value ?? point.value) : point.value,
                isLeadIn: false, isSelected: point.selected))
        }

        return AutomationLaneProjection(
            parameter: snapshot.parameter, metadata: metadata, revision: snapshot.revision,
            points: points, sources: snapshot.sources, leadIn: leadIn, segments: segments,
            scaleLabels: scaleLabels(metadata: metadata), songEndTick: snapshot.songEndTick,
            selectionRange: range)
    }

    /// Live modifier mapping against the captured time/value projection.
    func mappedPoint(x: Double, y: Double, facts: AutomationFrozenFacts,
                     modifiers: AutomationModifiers, plotHeight: Double,
                     neutralSnapRadius: Double) -> AutomationLanePoint {
        AutomationLanePoint(
            tick: tick(atX: x, fine: modifiers.fine),
            value: facts.metadata.snappedValue(
                value(atY: y, metadata: facts.metadata), snapValue: modifiers.snapValue,
                plotHeight: plotHeight, neutralSnapRadius: neutralSnapRadius))
    }

    /// The highlighted scale labels: maximum, minimum, and — only when the
    /// parameter has a neutral value — the neutral one, all at curve-true Y.
    public func scaleLabels(metadata: AutomationParameterMetadata) -> [AutomationScaleLabel] {
        let maximum = displayMaximum ?? metadata.maximum
        var labels: [AutomationScaleLabel] = [
            AutomationScaleLabel(role: .maximum, value: maximum,
                                 text: metadata.valueText(maximum),
                                 y: y(maximum, metadata: metadata)),
            AutomationScaleLabel(role: .minimum, value: metadata.minimum,
                                 text: metadata.valueText(metadata.minimum),
                                 y: y(metadata.minimum, metadata: metadata)),
        ]
        if let neutral = metadata.neutral {
            labels.append(AutomationScaleLabel(role: .neutral, value: neutral,
                                               text: metadata.valueText(neutral),
                                               y: y(neutral, metadata: metadata)))
        }
        return labels
    }
}
