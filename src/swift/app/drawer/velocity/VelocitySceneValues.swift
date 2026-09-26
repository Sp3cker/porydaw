import PorydawCore
import QtBridge

// Pure scene-value computation for the drawer's Velocity section: the page's
// session reads, the presented context's value axis and ruler rows, the time
// grid, the PSG level bands and the gesture transient's dashed edges.
//
// Ownership: values in, values out. Every entry is pure over its arguments;
// nothing here retains page or document state.

// MARK: - Scene values

/// The velocity band's static value computation: the page's session reads, the
/// value axis and its rows, the grid, the PSG bands and the small shared value
/// helpers. Every entry is pure over its arguments; nothing here retains page
/// or document state.
@MainActor
enum VelocityScene {
    /// The primary track's notes.
    static func trackNotes(_ session: DocumentSession?) -> [Note] {
        guard let session, let track = session.selectedTrack else { return [] }
        return session.projectionCache.notes(in: track)
    }

    /// The primary track's selected notes, in the session's insertion order.
    static func selectedTrackNotes(_ session: DocumentSession?) -> [Note] {
        guard let session, let track = session.selectedTrack else { return [] }
        return session.selectedNoteOrder.compactMap { session.projectionCache.note($0, in: track) }
    }

    /// The bank/timeline facts one build resolves voice contexts from.
    static func contextSource(_ session: DocumentSession?) -> VelocityContextSource {
        guard let session else { return .unresolved }
        let track = session.selectedTrack ?? -1
        guard track >= 0, track < session.timeline.tracks.count else { return .unresolved }
        return VelocityContextSource(
            firstProgram: session.timeline.tracks[track].firstProgram,
            voiceChanges: session.projectionCache.lanePoints(track: track, lane: .voice),
            slots: session.bankSlots)
    }

    /// The exact context at one tick, before any selection compatibility rule.
    static func contextResolver(_ session: DocumentSession?) -> (Tick, Int?) -> VelocityVoiceContext {
        contextSource(session).resolver()
    }

    /// The stable identity used to decide whether a context presentation changed.
    static func contextKey(_ session: DocumentSession?, at tick: Tick, playing: Bool)
        -> VelocityContextKey
    {
        contextSource(session).key(at: tick, playing: playing)
    }

    /// The context the ruler presents: the shared playhead's rounded tick while
    /// transport is playing, the edit cursor while stopped.
    static func effectiveContextTick(_ session: DocumentSession?, playing: Bool,
                                     contextTick: Tick) -> Tick {
        guard let session else { return 0 }
        return playing ? contextTick : session.editCursor
    }

    /// `VelocityArea::currentContext`: no selection resolves the context at the
    /// effective tick; a selection resolves per note, keeps an intrinsic map only
    /// when every selected note resolves to the same PSG voice, and falls back to
    /// the continuous domain when their maps disagree.
    static func presentation(_ session: DocumentSession?, playing: Bool,
                             contextTick: Tick) -> VelocityVoiceContext {
        VelocityContextPolicy.presentation(
            selectedNotes: selectedTrackNotes(session),
            effectiveTick: effectiveContextTick(session, playing: playing, contextTick: contextTick),
            resolve: contextResolver(session))
    }

    /// The shared grid metrics at one size.
    static func gridMetrics(baseFontPx: Double, devicePixelRatio: Double, width: Double,
                            height: Double, timeAxis: TimeAxis) -> GridMetrics {
        GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio, width: width, height: height,
                    timeAxis: timeAxis)
    }

    /// The roll's own time axis, built from the same document facts the grid
    /// uses, so the velocity band's grid is the roll's grid.
    static func timeAxis(_ session: DocumentSession) -> TimeAxis {
        session.projectionCache.timeAxis
    }


    /// The value axis: the presented context's map, the active set's markers and
    /// the font-relative ruler geometry. A hovered note takes its own tick's map
    /// while the selection keeps its own.
    static func axisModel(_ input: VelocitySceneInput) -> VelocityAxisModel {
        var activeValues: [UInt8] = []
        var mapped = input.context.map
        if let hovered = input.interaction.hovered,
           let note = input.notes.first(where: { $0.id == hovered }) {
            activeValues.append(input.interaction.preview[note.id] ?? note.velocity)
            mapped = input.source.map(at: note.tick, key: Int(note.pitch))
        } else {
            for note in input.selectedNotes {
                activeValues.append(input.interaction.preview[note.id] ?? note.velocity)
            }
        }
        var axisGeometry = VelocityAxisGeometry()
        axisGeometry.height = input.plotHeight
        axisGeometry.verticalInset = input.geometry.verticalInset
        axisGeometry.labelWidth = max(0, input.rulerWidth - input.geometry.pixel)
        axisGeometry.labelSideInset = input.geometry.labelSideInset
        axisGeometry.labelColumnGap = input.geometry.labelColumnGap
        axisGeometry.labelHeight = NativeFontMetrics(
            Typography(baseFontPx: Int(input.baseFontPx.rounded())).noteName).extents.height
        axisGeometry.continuousDensityD1 = input.geometry.densityD1
        axisGeometry.continuousDensityD2 = input.geometry.densityD2
        axisGeometry.continuousDensityD3 = input.geometry.densityD3
        axisGeometry.continuousDensityD4 = input.geometry.densityD4
        return VelocityAxisModel(map: mapped, geometry: axisGeometry, activeValues: activeValues)
    }

    /// The ruler's rows and labels: the intrinsic graduations with their
    /// density-thinned labels, or the continuous ladder with its ticks, markers
    /// and active-value labels. The label column's own geometry is part of the
    /// value, exactly as `rebuildQuickAxis` derives it.
    static func axisRows(_ input: VelocitySceneInput, axis: VelocityAxisModel,
                         relativeGesture: Bool) -> VelocityAxisRows {
        let separatorX = max(0, input.rulerWidth - input.geometry.pixel)
        // The ruler spans the whole gutter (track headers plus the keyboard
        // column); the label column keeps its keyboard-column width, anchored
        // to the separator the ticks draw against.
        let labelColumnWidth = fontPx(input.baseFontPx, 13.0 / 3.0) - input.geometry.pixel
        let labelRight = max(input.geometry.labelSideInset,
                             separatorX - input.geometry.labelSideInset)
        let labelLeft = max(input.geometry.labelSideInset, labelRight - labelColumnWidth)
        let labelWidth = max(0, labelRight - labelLeft)
        let labelHeight = max(0, axis.geometry.labelHeight)
        let labelColor = input.palette.primaryText
        let selectedColor = input.palette.selectionRing
        let typography = Typography(baseFontPx: Int(input.baseFontPx.rounded()))
        let noteNameFont = typography.noteName.map
        let markerFont = typography.captionBold.map
        var rows = VelocityAxisRows()
        if axis.mode == .intrinsic && input.interaction.detentsEnabled {
            for graduation in axis.graduations {
                let width = graduation.active ? 1.5 : input.geometry.pixel
                rows.graduations.append(SceneRect(
                    x: separatorX - input.geometry.tickLabelLength, y: graduation.y - width / 2,
                    width: input.geometry.tickLabelLength, height: width,
                    fillColor: graduation.active ? selectedColor : labelColor,
                    primitiveName: "velocityGraduation"))
                let emphasized = graduation.active
                    && (relativeGesture || !graduation.labelVisible)
                guard (!relativeGesture && graduation.labelVisible) || emphasized else {
                    continue
                }
                rows.labels.append(SceneText(
                    rect: (labelLeft, graduation.y - labelHeight / 2, labelWidth, labelHeight),
                    text: graduation.text, color: labelColor,
                    font: emphasized ? markerFont : noteNameFont, horizontal: 0x2))
            }
        } else {
            for tick in axis.ticks {
                let length = axis.hasLabel(tick.velocity) ? input.geometry.tickLabelLength
                                                          : input.geometry.tickShortLength
                rows.ticks.append(SceneRect(
                    x: separatorX - length, y: tick.y - input.geometry.pixel / 2, width: length,
                    height: input.geometry.pixel, fillColor: labelColor,
                    primitiveName: "velocityTick"))
            }
            if !relativeGesture {
                for label in axis.labels {
                    rows.labels.append(SceneText(
                        rect: (labelLeft, label.y - labelHeight / 2, labelWidth, labelHeight),
                        text: label.text, color: labelColor,
                        font: noteNameFont, horizontal: 0x2))
                }
            }
            for marker in axis.markers {
                rows.markers.append(SceneRect(
                    x: separatorX - input.geometry.markerLength, y: marker.y - 0.75,
                    width: input.geometry.markerLength, height: 1.5, fillColor: selectedColor,
                    primitiveName: "velocityMarker"))
                guard relativeGesture else { continue }
                rows.labels.append(SceneText(
                    rect: (labelLeft, marker.y - labelHeight / 2, labelWidth, labelHeight),
                    text: "\(marker.velocity)", color: labelColor,
                    font: markerFont, horizontal: 0x2))
            }
        }
        return rows
    }

    /// The vertical grid over the visible plot: `composeBandedGrid`'s
    /// subdivisions plus the beat, fine-beat and bar lines.
    static func grid(_ input: VelocitySceneInput) -> [SceneRect] {
        guard let camera = input.camera, let metrics = input.metrics,
              input.plotHeight > 0, input.plotWidth > input.rulerWidth else { return [] }
        guard var grid = input.grid else { return [] }
        grid.metrics = metrics
        let physicalPixel = max(input.geometry.pixel, 0.0001)
        let roundingMargin = physicalPixel / 2
        let beginTick = camera.tickAtContentX(-roundingMargin)
        let endTick = camera.tickAtContentX(input.plotWidth - physicalPixel + roundingMargin) + 1
        guard endTick > beginTick else { return [] }
        let range = (begin: Tick(max(0, beginTick.rounded(.down))),
                     end: Tick(max(1, endTick.rounded(.up))))
        let stroke = metrics.gridLineStroke
        var rects: [SceneRect] = []
        grid.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: input.devicePixelRatio)
            let color = level == 1 ? input.palette.gridLineSub1
                : level == 2 ? input.palette.gridLineSub2 : input.palette.gridLineSub3
            rects.append(SceneRect(x: x - stroke / 2, y: 0, width: stroke,
                                   height: input.plotHeight, fillColor: color,
                                   primitiveName: "velocityGrid"))
        }
        var segment = metrics.timeAxis.segmentAt(range.begin)
        var finest = grid.gridTicksAt(range.begin, camera: camera) == 1
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                finest = grid.gridTicksAt(tick, camera: camera) == 1
            }
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: input.devicePixelRatio)
            rects.append(SceneRect(
                x: x - stroke / 2, y: 0, width: stroke, height: input.plotHeight,
                fillColor: isBar ? input.palette.gridLineBar
                    : finest ? input.palette.gridLineBeatFine : input.palette.gridLineBeat,
                primitiveName: "velocityGrid"))
        }
        return rects
    }

    /// PSG level bands: one horizontal boundary per level inside each voice
    /// context section whose map resolves exactly to a PSG voice. A section
    /// whose map is unknown draws no level line rather than a guessed layout.
    static func bands(_ input: VelocitySceneInput, axis: VelocityAxisModel,
                      projection: VelocityProjection) -> [SceneRect] {
        guard let camera = input.camera, input.plotHeight > 0,
              input.plotWidth > input.rulerWidth else { return [] }
        let color = input.palette.separator
        let first = Tick(max(0, camera.tickAtContentX(0).rounded(.down)))
        let last = max(Tick(first + 1), Tick(camera.tickAtContentX(input.plotWidth).rounded(.up)))
        var sectionTick = first
        var rects: [SceneRect] = []
        var guardCounter = 0
        let resolve = input.source.resolver()
        while sectionTick < last, guardCounter < 4096 {
            guardCounter += 1
            let context = resolve(sectionTick, nil)
            let sectionEnd = min(last, context.endTick ?? last)
            if sectionEnd <= sectionTick { break }
            if context.status == .resolved, context.map.isPSG, context.map.levelCount > 1 {
                let left = min(max(projection.xForDisplayTick(Double(sectionTick)), 0),
                               input.plotWidth)
                let right = min(max(projection.xForDisplayTick(Double(sectionEnd)), 0),
                                input.plotWidth)
                if right > left {
                    let sectionMap = context.map
                    for level in 0..<(context.map.levelCount - 1) {
                        let y = axis.levelBoundaryToY(level, map: sectionMap)
                        rects.append(SceneRect(
                            x: left, y: y - input.geometry.gridLineStroke / 2,
                            width: right - left, height: input.geometry.gridLineStroke,
                            fillColor: color, primitiveName: "velocityBand"))
                    }
                }
            }
            sectionTick = sectionEnd
        }
        return rects
    }

    /// One dashed band edge of the gesture transient. The page supplies the
    /// physical pixel and edge colour the reticle draws with.
    static func appendDashed(_ rects: inout [SceneRect], horizontal: Bool, fixed: Double,
                             from: Double, to: Double, dash: Double, gap: Double,
                             physicalPixel: Double, color: String) {
        let period = dash + gap
        guard period > 0, to > from else { return }
        var position = from
        while position < to {
            let end = min(position + dash, to)
            if horizontal {
                rects.append(SceneRect(x: position, y: fixed - physicalPixel / 2,
                                       width: end - position, height: physicalPixel,
                                       fillColor: color, primitiveName: "velocityBandEdge"))
            } else {
                rects.append(SceneRect(x: fixed - physicalPixel / 2, y: position,
                                       width: physicalPixel, height: end - position,
                                       fillColor: color, primitiveName: "velocityBandEdge"))
            }
            position += period
        }
    }
}
