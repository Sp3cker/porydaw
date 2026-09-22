import PorydawCore

// Pure geometry and presentation values. Session sampling and native font
// measurement stay in VelocityPublication.swift.
extension VelocityScene {
    static func gridMetrics(baseFontPx: Double, devicePixelRatio: Double, width: Double,
                            height: Double, timeAxis: TimeAxis) -> GridMetrics {
        GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio, width: width, height: height,
                    timeAxis: timeAxis)
    }

    static func axisModel(_ input: VelocitySceneInput) -> VelocityAxisModel {
        var activeValues: [UInt8] = []
        var mapped = input.context.map
        if let hovered = input.hovered,
           let note = input.notes.first(where: { $0.id == hovered }) {
            activeValues.append(input.gesture?.preview[note.id] ?? note.velocity)
            mapped = input.source.map(at: note.tick, key: Int(note.pitch))
        } else {
            for note in input.selectedNotes {
                activeValues.append(input.gesture?.preview[note.id] ?? note.velocity)
            }
        }
        var axisGeometry = VelocityAxisGeometry()
        axisGeometry.height = input.plotHeight
        axisGeometry.verticalInset = input.geometry.verticalInset
        axisGeometry.labelWidth = max(0, input.rulerWidth - input.geometry.pixel)
        axisGeometry.labelSideInset = input.geometry.labelSideInset
        axisGeometry.labelColumnGap = input.geometry.labelColumnGap
        axisGeometry.labelHeight = max(input.geometry.densityD1, input.plotHeight / 8)
        axisGeometry.continuousDensityD1 = input.geometry.densityD1
        axisGeometry.continuousDensityD2 = input.geometry.densityD2
        axisGeometry.continuousDensityD3 = input.geometry.densityD3
        axisGeometry.continuousDensityD4 = input.geometry.densityD4
        return VelocityAxisModel(map: mapped, geometry: axisGeometry, activeValues: activeValues)
    }

    static func axisRows(_ input: VelocitySceneInput, axis: VelocityAxisModel,
                         relativeGesture: Bool,
                         textMetrics: DrawerTextMetrics?) -> VelocityAxisRows {
        let separatorX = max(0, input.rulerWidth - input.geometry.pixel)
        let labelColumnWidth = fontPx(input.baseFontPx, 13.0 / 3.0) - input.geometry.pixel
        let labelRight = max(input.geometry.labelSideInset,
                             separatorX - input.geometry.labelSideInset)
        let labelLeft = max(input.geometry.labelSideInset, labelRight - labelColumnWidth)
        let labelWidth = max(0, labelRight - labelLeft)
        let labelHeight = max(0, axis.geometry.labelHeight)
        let labelColor = input.palette.primaryText
        let selectedColor = input.palette.selectionRing
        var rows = VelocityAxisRows()
        if axis.mode == .intrinsic && input.detentsEnabled {
            for graduation in axis.graduations {
                let width = graduation.active ? 1.5 : input.geometry.pixel
                rows.graduations.append(DrawerRectValue(
                    x: separatorX - input.geometry.tickLabelLength,
                    y: graduation.y - width / 2,
                    width: input.geometry.tickLabelLength,
                    height: width,
                    fillColor: graduation.active ? selectedColor : labelColor,
                    primitiveName: "velocityGraduation"))
                let emphasized = graduation.active
                    && (relativeGesture || !graduation.labelVisible)
                guard (!relativeGesture && graduation.labelVisible) || emphasized else {
                    continue
                }
                rows.labels.append(DrawerTextValue(
                    rect: DrawerRectValue(x: labelLeft, y: graduation.y - labelHeight / 2,
                                          width: labelWidth, height: labelHeight),
                    text: graduation.text,
                    color: labelColor,
                    font: fontSpec(emphasized: emphasized, textMetrics: textMetrics,
                                   baseFontPx: input.baseFontPx),
                    horizontalAlignment: 0x2))
            }
        } else {
            for tick in axis.ticks {
                let length = axis.hasLabel(tick.velocity) ? input.geometry.tickLabelLength
                                                          : input.geometry.tickShortLength
                rows.ticks.append(DrawerRectValue(
                    x: separatorX - length,
                    y: tick.y - input.geometry.pixel / 2,
                    width: length,
                    height: input.geometry.pixel,
                    fillColor: labelColor,
                    primitiveName: "velocityTick"))
            }
            if !relativeGesture {
                for label in axis.labels {
                    rows.labels.append(DrawerTextValue(
                        rect: DrawerRectValue(x: labelLeft, y: label.y - labelHeight / 2,
                                              width: labelWidth, height: labelHeight),
                        text: label.text,
                        color: labelColor,
                        font: fontSpec(emphasized: false, textMetrics: textMetrics,
                                       baseFontPx: input.baseFontPx),
                        horizontalAlignment: 0x2))
                }
            }
            for marker in axis.markers {
                rows.markers.append(DrawerRectValue(
                    x: separatorX - input.geometry.markerLength,
                    y: marker.y - 0.75,
                    width: input.geometry.markerLength,
                    height: 1.5,
                    fillColor: selectedColor,
                    primitiveName: "velocityMarker"))
                guard relativeGesture else { continue }
                rows.labels.append(DrawerTextValue(
                    rect: DrawerRectValue(x: labelLeft, y: marker.y - labelHeight / 2,
                                          width: labelWidth, height: labelHeight),
                    text: "\(marker.velocity)",
                    color: labelColor,
                    font: fontSpec(emphasized: true, textMetrics: textMetrics,
                                   baseFontPx: input.baseFontPx),
                    horizontalAlignment: 0x2))
            }
        }
        return rows
    }

    static func grid(_ input: VelocitySceneInput) -> [DrawerRectValue] {
        guard let camera = input.camera, let metrics = input.metrics,
              input.plotHeight > 0, input.plotWidth > input.rulerWidth else { return [] }
        let physicalPixel = max(input.geometry.pixel, 0.0001)
        let roundingMargin = physicalPixel / 2
        let beginTick = camera.tickAtContentX(-roundingMargin)
        let endTick = camera.tickAtContentX(input.plotWidth - physicalPixel + roundingMargin) + 1
        guard endTick > beginTick else { return [] }
        let range = (begin: Tick(max(0, beginTick.rounded(.down))),
                     end: Tick(max(1, endTick.rounded(.up))))
        let stroke = metrics.gridLineStroke
        var rects: [DrawerRectValue] = []
        metrics.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: input.devicePixelRatio)
            let color = level == 1 ? input.palette.gridLineSub1
                : level == 2 ? input.palette.gridLineSub2 : input.palette.gridLineSub3
            rects.append(DrawerRectValue(x: x - stroke / 2, y: 0, width: stroke,
                                         height: input.plotHeight, fillColor: color,
                                         primitiveName: "velocityGrid"))
        }
        var segment = metrics.timeAxis.segmentAt(range.begin)
        var finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
            }
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: input.devicePixelRatio)
            rects.append(DrawerRectValue(
                x: x - stroke / 2, y: 0, width: stroke, height: input.plotHeight,
                fillColor: isBar ? input.palette.gridLineBar
                    : finest ? input.palette.gridLineBeatFine : input.palette.gridLineBeat,
                primitiveName: "velocityGrid"))
        }
        return rects
    }

    static func bands(_ input: VelocitySceneInput, axis: VelocityAxisModel,
                      projection: VelocityProjection) -> [DrawerRectValue] {
        guard let camera = input.camera, input.plotHeight > 0,
              input.plotWidth > input.rulerWidth else { return [] }
        let first = Tick(max(0, camera.tickAtContentX(0).rounded(.down)))
        let last = max(Tick(first + 1), Tick(camera.tickAtContentX(input.plotWidth).rounded(.up)))
        var sectionTick = first
        var rects: [DrawerRectValue] = []
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
                    for level in 0..<(context.map.levelCount - 1) {
                        let y = axis.levelBoundaryToY(level, map: context.map)
                        rects.append(DrawerRectValue(
                            x: left, y: y - input.geometry.gridLineStroke / 2,
                            width: right - left, height: input.geometry.gridLineStroke,
                            fillColor: input.palette.separator,
                            primitiveName: "velocityBand"))
                    }
                }
            }
            sectionTick = sectionEnd
        }
        return rects
    }

    static func transient(_ input: VelocitySceneInput) -> VelocityTransientValue {
        guard let gesture = input.gesture else { return VelocityTransientValue() }
        switch gesture {
        case let .ramp(edit):
            let dx = edit.previousX - edit.pressX
            let dy = edit.previousY - edit.pressY
            let length = (dx * dx + dy * dy).squareRoot()
            return VelocityTransientValue(
                ramp: VelocityRampValue(visible: length > 0, x0: edit.pressX,
                                        y0: edit.pressY, length: length,
                                        slopeY: dy, color: input.palette.primaryText))
        case let .band(band), let .pendingBand(band):
            let minX = min(band.pressX, band.x)
            let maxX = max(band.pressX, band.x)
            let minY = min(band.pressY, band.y)
            let maxY = max(band.pressY, band.y)
            var rects = [DrawerRectValue(
                x: minX, y: minY, width: maxX - minX, height: maxY - minY,
                fillColor: input.palette.selectionFill,
                primitiveName: "velocityBandFill")]
            let dash = 4 * input.geometry.pixel
            let gap = 2 * input.geometry.pixel
            appendDashed(&rects, horizontal: true, fixed: minY, from: minX, to: maxX,
                         dash: dash, gap: gap, physicalPixel: input.geometry.pixel,
                         color: input.palette.selectionEdge)
            appendDashed(&rects, horizontal: true, fixed: maxY, from: minX, to: maxX,
                         dash: dash, gap: gap, physicalPixel: input.geometry.pixel,
                         color: input.palette.selectionEdge)
            appendDashed(&rects, horizontal: false, fixed: minX, from: minY, to: maxY,
                         dash: dash, gap: gap, physicalPixel: input.geometry.pixel,
                         color: input.palette.selectionEdge)
            appendDashed(&rects, horizontal: false, fixed: maxX, from: minY, to: maxY,
                         dash: dash, gap: gap, physicalPixel: input.geometry.pixel,
                         color: input.palette.selectionEdge)
            return VelocityTransientValue(rects: rects)
        case .relative, .paint, .pan:
            return VelocityTransientValue()
        }
    }

    static func readout(_ input: VelocitySceneInput,
                        handles: [VelocityHandleValue]) -> VelocityReadoutValue {
        var value = VelocityReadoutValue(
            selectedCount: handles.lazy.filter(\.selected).count,
            hoveredNoteText: input.hovered.map(velocityNoteText) ?? "")
        if let hovered = input.hovered,
           let handle = handles.first(where: { $0.noteID == hovered }) {
            value.text = handle.label
            value.visible = true
            value.x = handle.x
            value.y = handle.y
        } else if let gesture = input.gesture, let first = gesture.notes.first {
            let handle = handles.first { $0.noteID == first.noteID }
            let preview = gesture.preview[first.noteID].map(Int.init) ?? Int(first.velocity)
            value.text = handle?.label ?? "\(preview)"
            value.visible = true
            value.x = handle?.x ?? 0
            value.y = handle?.y ?? 0
        }
        return value
    }

    static func appendDashed(_ rects: inout [DrawerRectValue], horizontal: Bool,
                             fixed: Double, from: Double, to: Double, dash: Double,
                             gap: Double, physicalPixel: Double, color: String) {
        let period = dash + gap
        guard period > 0, to > from else { return }
        var position = from
        while position < to {
            let end = min(position + dash, to)
            if horizontal {
                rects.append(DrawerRectValue(
                    x: position, y: fixed - physicalPixel / 2,
                    width: end - position, height: physicalPixel,
                    fillColor: color, primitiveName: "velocityBandEdge"))
            } else {
                rects.append(DrawerRectValue(
                    x: fixed - physicalPixel / 2, y: position,
                    width: physicalPixel, height: end - position,
                    fillColor: color, primitiveName: "velocityBandEdge"))
            }
            position += period
        }
    }

    private static func fontSpec(emphasized: Bool, textMetrics: DrawerTextMetrics?,
                                 baseFontPx: Double) -> GridFontSpec {
        let fallback = GridFontSpec(
            family: "Atkinson Hyperlegible Next", pixelSize: Int(baseFontPx),
            weight: emphasized ? 600 : 400, letterSpacing: 0)
        return textMetrics?.font(emphasized ? .bold : .keyLabel, fallback: fallback) ?? fallback
    }
}
