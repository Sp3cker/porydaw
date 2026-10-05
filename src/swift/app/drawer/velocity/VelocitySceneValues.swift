import PorydawCore
import QtBridge

/// Pure value computation for the velocity ruler, grid and interaction overlays.
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
    static func contextKey(
        _ session: DocumentSession?, at tick: Tick, playing: Bool
    )
        -> VelocityContextKey
    {
        contextSource(session).key(at: tick, playing: playing)
    }

    /// The context the ruler presents: the shared playhead's rounded tick while
    /// transport is playing, the edit cursor while stopped.
    static func effectiveContextTick(
        _ session: DocumentSession?, playing: Bool,
        contextTick: Tick
    ) -> Tick {
        guard let session else { return 0 }
        return playing ? contextTick : session.editCursor
    }

    /// `VelocityArea::currentContext`: no selection resolves the context at the
    /// effective tick; a selection resolves per note, keeps an intrinsic map only
    /// when every selected note resolves to the same PSG voice, and falls back to
    /// the continuous domain when their maps disagree.
    static func presentation(
        _ session: DocumentSession?, playing: Bool,
        contextTick: Tick
    ) -> VelocityVoiceContext {
        VelocityContextPolicy.presentation(
            selectedNotes: selectedTrackNotes(session),
            effectiveTick: effectiveContextTick(session, playing: playing, contextTick: contextTick),
            resolve: contextResolver(session))
    }

    /// The shared grid metrics at one size.
    static func gridMetrics(
        baseFontPx: Double, devicePixelRatio: Double, width: Double,
        height: Double, timeAxis: TimeAxis
    ) -> GridMetrics {
        GridMetrics(
            baseFontPx: baseFontPx, dpr: devicePixelRatio, width: width, height: height,
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
            let note = input.notes.first(where: { $0.id == hovered })
        {
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
        axisGeometry.labelHeight = NativeFontMetrics(input.typography.noteName).extents.height
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
    static func axisRows(
        _ input: VelocitySceneInput, axis: VelocityAxisModel,
        relativeGesture: Bool
    ) -> VelocityAxisRows {
        let separatorX = max(0, input.rulerWidth - input.geometry.pixel)
        // The ruler spans the whole gutter (track headers plus the keyboard
        // column); the label column keeps its keyboard-column width, anchored
        // to the separator the ticks draw against.
        let labelColumnWidth = fontPx(input.baseFontPx, 13.0 / 3.0) - input.geometry.pixel
        let labelRight = max(
            input.geometry.labelSideInset,
            separatorX - input.geometry.labelSideInset)
        let labelLeft = max(input.geometry.labelSideInset, labelRight - labelColumnWidth)
        let labelWidth = max(0, labelRight - labelLeft)
        let labelHeight = max(0, axis.geometry.labelHeight)
        let labelColor = input.palette.primaryText
        let selectedColor = input.palette.selectionRing
        let noteNameFont = input.typography.noteName.qmlFont
        let markerFont = input.typography.captionBold.qmlFont
        var rows = VelocityAxisRows()
        if axis.mode == .intrinsic && input.interaction.detentsEnabled {
            for graduation in axis.graduations {
                let width = graduation.active ? 1.5 : input.geometry.pixel
                rows.graduations.append(
                    SceneRectValue(
                        x: separatorX - input.geometry.tickLabelLength, y: graduation.y - width / 2,
                        width: input.geometry.tickLabelLength, height: width,
                        fillColor: graduation.active ? selectedColor : labelColor,
                        primitiveName: "velocityGraduation"))
                let emphasized =
                    graduation.active
                    && (relativeGesture || !graduation.labelVisible)
                guard (!relativeGesture && graduation.labelVisible) || emphasized else {
                    continue
                }
                rows.labels.append(
                    SceneTextValue(
                        rect: (labelLeft, graduation.y - labelHeight / 2, labelWidth, labelHeight),
                        text: graduation.text, color: labelColor,
                        font: emphasized ? markerFont : noteNameFont, horizontal: 0x2))
            }
        } else {
            for tick in axis.ticks {
                let length =
                    axis.hasLabel(tick.velocity)
                    ? input.geometry.tickLabelLength
                    : input.geometry.tickShortLength
                rows.ticks.append(
                    SceneRectValue(
                        x: separatorX - length, y: tick.y - input.geometry.pixel / 2, width: length,
                        height: input.geometry.pixel, fillColor: labelColor,
                        primitiveName: "velocityTick"))
            }
            if !relativeGesture {
                for label in axis.labels {
                    rows.labels.append(
                        SceneTextValue(
                            rect: (labelLeft, label.y - labelHeight / 2, labelWidth, labelHeight),
                            text: label.text, color: labelColor,
                            font: noteNameFont, horizontal: 0x2))
                }
            }
            for marker in axis.markers {
                rows.markers.append(
                    SceneRectValue(
                        x: separatorX - input.geometry.markerLength, y: marker.y - 0.75,
                        width: input.geometry.markerLength, height: 1.5, fillColor: selectedColor,
                        primitiveName: "velocityMarker"))
                guard relativeGesture else { continue }
                rows.labels.append(
                    SceneTextValue(
                        rect: (labelLeft, marker.y - labelHeight / 2, labelWidth, labelHeight),
                        text: "\(marker.velocity)", color: labelColor,
                        font: markerFont, horizontal: 0x2))
            }
        }
        return rows
    }

    static func modelBands(_ input: VelocitySceneInput, axis: VelocityAxisModel) -> [DrawerStaticRect] {
        guard input.plotHeight > 0 else { return [] }
        var rects: [DrawerStaticRect] = []
        let source = input.source
        var start: Tick = 0
        var slot = source.firstProgram
        for change in source.voiceChanges {
            appendModelBands(
                &rects, from: start, to: change.tick, slot: slot,
                input: input, axis: axis)
            start = change.tick
            slot = change.value
        }
        appendModelBands(
            &rects, from: start, to: TimeDefaults.maxTick, slot: slot,
            input: input, axis: axis)
        return rects
    }

    private static func appendModelBands(
        _ rects: inout [DrawerStaticRect],
        from start: Tick, to end: Tick, slot: Int,
        input: VelocitySceneInput, axis: VelocityAxisModel
    ) {
        guard end > start else { return }
        let context = VelocityContextPolicy.resolve(
            slot: slot, endTick: end,
            slots: input.source.slots)
        guard context.status == .resolved, context.map.isPSG,
            context.map.levelCount > 1
        else { return }
        let stroke = input.geometry.gridLineStroke
        let argb = SceneRectPacking.argb(input.palette.separator)
        for level in 0..<(context.map.levelCount - 1) {
            rects.append(
                DrawerStaticRect(
                    tickStart: start, tickEnd: end,
                    y: Float(axis.levelBoundaryToY(level, map: context.map) - stroke / 2),
                    height: Float(stroke), argb: argb))
        }
    }
}
