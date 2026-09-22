import Foundation
import PorydawCore

/// One document occurrence projected into marker order.
struct VoiceProjectionEntry: Equatable, Sendable {
    var occurrence: VoiceOccurrence
    var tick: Tick
    var value: Int
    var identity: String
    var sourceOrder: Int
}

/// One premeasured elision candidate. Native measurement stays in the adapter;
/// the projection only chooses among immutable measured strings.
struct VoiceElisionCandidate: Equatable, Sendable {
    var text: String
    var width: Double
}

struct VoiceTextMeasurement: Equatable, Sendable {
    var source: String
    var width: Double
    var elisions: [VoiceElisionCandidate]

    func fitted(toWidth limit: Double) -> (text: String, width: Double) {
        guard width > limit else { return (source, width) }
        var result = elisions.first ?? VoiceElisionCandidate(text: "…", width: width)
        for candidate in elisions where candidate.width <= limit {
            result = candidate
        }
        return (result.text, result.width)
    }
}

/// Typography values sampled by the native presentation adapter before a pure
/// scene build.
struct VoiceTypographyValues: Equatable, Sendable {
    var captionFont: GridFontSpec
    var titleFont: GridFontSpec
    var captionHeight: Double
    var titleHeight: Double
    var measurements: [String: VoiceTextMeasurement]
}

/// One plain marker descriptor. The exact occurrence is retained for hit tests;
/// only its bridge-safe spelling is copied to the Qt row.
struct VoiceMarkerValue: Equatable, Sendable {
    var occurrence: VoiceOccurrence
    var identity: String
    var tick: Double
    var value: Int
    var slotBlank: Bool
    var symbol: String
    var label: String
    var labelRect: DrawerRectValue
    var labelColor: String
    var x: Double
    var lineTop: Double
    var lineBottom: Double
    var lineWidth: Double
    var lineColor: String
    var selected: Bool
    var hovered: Bool
    var preview: Bool
    var offscreen: Bool
    var primitiveName: String = "voiceChangeMarker"
}

struct VoicePickerRowValue: Equatable, Sendable {
    var program: Int
    var label: String
    var blank: Bool
    var symbol: String
    var selected: Bool
    var primitiveName: String = "voicePickerRow"
}

struct VoiceMenuRowValue: Equatable, Sendable {
    var actionId: Int
    var text: String
    var primitiveName: String = "voiceChangeMenuRow"
}

struct VoiceReadoutValue: Equatable, Sendable {
    var slot: Int = -1
    var blank = true
    var symbol = ""
    var text = ""
    var rect = DrawerRectValue()
}

struct VoiceMarkerProjectionInput: Sendable {
    var entries: [VoiceProjectionEntry]
    var slots: [BankSlotView]
    var plotWidth: Double
    var plotHeight: Double
    var pad: Double
    var gap: Double
    var stairLimit: Double
    var physicalPixel: Double
    var labelColor: String
    var lineColor: String
    var selectedIdentity: String?
    var hoverIdentity: String?
    var previewIdentity: String?
    var typography: VoiceTypographyValues
    var camera: EditorCamera
    var devicePixelRatio: Double
}

struct VoiceSpanProjectionInput: Sendable {
    var entries: [VoiceProjectionEntry]
    var firstProgram: Int
    var lengthTicks: Tick
    var plotWidth: Double
    var plotHeight: Double
    var color: String
    var camera: EditorCamera
    var devicePixelRatio: Double
}

struct VoiceGutterProjectionInput: Sendable {
    var plotHeight: Double
    var plotOrigin: Double
    var title: String
    var summary: String?
    var titleFont: GridFontSpec
    var captionFont: GridFontSpec
    var titleHeight: Double
    var captionHeight: Double
    var titleColor: String
    var captionColor: String
}

struct VoiceGridProjectionColors: Sendable {
    var subdivision1: String
    var subdivision2: String
    var subdivision3: String
    var bar: String
    var beat: String
    var fineBeat: String
}

/// Pure layout and projection rules for Voice Changes.
enum VoiceChangesProjection {
    static func entries(points: borrowing [LanePoint]) -> [VoiceProjectionEntry] {
        var entries: [VoiceProjectionEntry] = []
        entries.reserveCapacity(points.count)
        for index in points.indices {
            let point = points[index]
            let occurrence = VoiceOccurrence(point)
            entries.append(VoiceProjectionEntry(
                occurrence: occurrence, tick: point.tick, value: point.value,
                identity: occurrence.text, sourceOrder: index))
        }
        entries.sort {
            $0.tick == $1.tick ? $0.sourceOrder < $1.sourceOrder : $0.tick < $1.tick
        }
        return entries
    }

    /// Only the frozen occurrence moves; equal ticks keep document source order.
    static func moving(_ entries: [VoiceProjectionEntry],
                       drag: VoiceDragState?) -> [VoiceProjectionEntry] {
        guard let drag,
              let index = entries.firstIndex(where: { $0.identity == drag.identity })
        else { return entries }
        var result = entries
        var moved = result.remove(at: index)
        moved.tick = drag.previewTick
        var lower = 0
        var upper = result.count
        while lower < upper {
            let middle = (lower + upper) / 2
            let entry = result[middle]
            if entry.tick < moved.tick
                || (entry.tick == moved.tick && entry.sourceOrder < moved.sourceOrder) {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        result.insert(moved, at: lower)
        return result
    }

    static func spans(_ input: borrowing VoiceSpanProjectionInput) -> [DrawerRectValue] {
        var program = input.firstProgram
        var spanStart: Tick = 0
        var rects: [DrawerRectValue] = []
        rects.reserveCapacity(input.entries.count + 1)
        func appendSpan(from begin: Tick, to end: Tick) {
            let left = min(max(input.camera.displayX(
                tick: Double(begin), origin: 0, dpr: input.devicePixelRatio), 0), input.plotWidth)
            let right = min(max(input.camera.displayX(
                tick: Double(end), origin: 0, dpr: input.devicePixelRatio), 0), input.plotWidth)
            let rect = DrawerRectValue(
                x: left, y: 0, width: max(0, right - left), height: input.plotHeight,
                fillColor: input.color, primitiveName: "voiceHeldSpan")
            if rect.width > 0 { rects.append(rect) }
        }
        for index in input.entries.indices {
            let entry = input.entries[index]
            if program >= 0, entry.tick > spanStart {
                appendSpan(from: spanStart, to: entry.tick)
            }
            program = entry.value
            spanStart = entry.tick
        }
        if program >= 0, input.lengthTicks > spanStart {
            appendSpan(from: spanStart, to: input.lengthTicks)
        }
        return rects
    }

    static func gutterTexts(_ input: borrowing VoiceGutterProjectionInput) -> [DrawerTextValue] {
        let top = max(0, (input.plotHeight - input.titleHeight - input.captionHeight) / 2)
        var texts = [DrawerTextValue(
            rect: DrawerRectValue(x: 0, y: top, width: input.plotOrigin,
                                  height: input.titleHeight),
            text: input.title, color: input.titleColor, font: input.titleFont)]
        if let summary = input.summary {
            texts.append(DrawerTextValue(
                rect: DrawerRectValue(x: 0, y: top + input.titleHeight,
                                      width: input.plotOrigin, height: input.captionHeight),
                text: summary, color: input.captionColor, font: input.captionFont))
        }
        return texts
    }

    static func readout(firstProgram: Int, tick: Tick, points: borrowing [LanePoint],
                        slots: borrowing [BankSlotView], pad: Double,
                        plotWidth: Double, plotHeight: Double) -> VoiceReadoutValue {
        let slot = VoiceLanePolicy.slot(firstProgram: firstProgram, tick: tick, points: points)
        let view = slots.indices.contains(slot) ? slots[slot] : nil
        let label = VoiceLanePolicy.label(slot: slot, view: view)
        return VoiceReadoutValue(
            slot: slot,
            blank: view?.voice == nil,
            symbol: view?.voice?.symbol ?? "",
            text: label.isEmpty ? "No voice" : label,
            rect: DrawerRectValue(x: pad, y: 0, width: max(0, plotWidth - 2 * pad),
                                  height: plotHeight))
    }

    static func grid(metrics: borrowing GridMetrics, camera: borrowing EditorCamera,
                     plotWidth: Double, plotHeight: Double,
                     colors: borrowing VoiceGridProjectionColors) -> [DrawerRectValue] {
        let physicalPixel = max(metrics.pixel, 0.0001)
        let roundingMargin = physicalPixel / 2
        let beginTick = camera.tickAtContentX(-roundingMargin)
        let endTick = camera.tickAtContentX(plotWidth - physicalPixel + roundingMargin) + 1
        guard endTick > beginTick else { return [] }
        let range = (begin: Tick(max(0, beginTick.rounded(.down))),
                     end: Tick(max(1, endTick.rounded(.up))))
        let stroke = metrics.gridLineStroke
        var rects: [DrawerRectValue] = []
        metrics.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let color = level == 1 ? colors.subdivision1
                : level == 2 ? colors.subdivision2 : colors.subdivision3
            rects.append(DrawerRectValue(
                x: camera.displayX(tick: Double(tick), origin: 0, dpr: metrics.dpr)
                    - stroke / 2, y: 0, width: stroke, height: plotHeight,
                fillColor: color, primitiveName: "voiceGrid"))
        }
        var segment = metrics.timeAxis.segmentAt(range.begin)
        var finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
            }
            rects.append(DrawerRectValue(
                x: camera.displayX(tick: Double(tick), origin: 0, dpr: metrics.dpr)
                    - stroke / 2, y: 0, width: stroke, height: plotHeight,
                fillColor: isBar ? colors.bar : finest ? colors.fineBeat : colors.beat,
                primitiveName: "voiceGrid"))
        }
        return rects
    }

    static func markers(_ input: borrowing VoiceMarkerProjectionInput) -> [VoiceMarkerValue] {
        let labelHeight = input.typography.captionHeight
        let centerY = input.plotHeight / 2 - labelHeight / 2
        let stairStep = min(input.stairLimit,
                            (input.plotHeight - labelHeight - 2 * input.pad) / 2)
        let canStair = stairStep > 1
        var stairUp = true
        var lastEnd = -Double.infinity
        var values: [VoiceMarkerValue] = []
        values.reserveCapacity(input.entries.count)
        for index in input.entries.indices {
            let entry = input.entries[index]
            let labelX = input.camera.displayX(
                tick: Double(entry.tick), origin: 0, dpr: input.devicePixelRatio) + input.pad
            let view = input.slots.indices.contains(entry.value) ? input.slots[entry.value] : nil
            let label = VoiceLanePolicy.label(slot: entry.value, view: view)
            let source = label.isEmpty ? "No voice" : label
            let maxWidth = max(0, input.plotWidth - labelX)
            let measured = input.typography.measurements[source]
                ?? VoiceTextMeasurement(source: source, width: 0,
                                        elisions: [VoiceElisionCandidate(text: "…", width: 0)])
            let fitted = measured.fitted(toWidth: maxWidth)
            let offscreen = labelX + fitted.width < 0 || labelX > input.plotWidth
                || fitted.width <= 0
            var labelY = centerY
            if !offscreen {
                if labelX < lastEnd, canStair {
                    stairUp.toggle()
                    labelY = stairUp ? centerY - stairStep : centerY + stairStep
                }
                let lower = input.pad
                let upper = max(lower, input.plotHeight - labelHeight - input.pad)
                labelY = min(max(labelY, lower), upper)
                lastEnd = labelX + fitted.width + input.gap
            }
            values.append(VoiceMarkerValue(
                occurrence: entry.occurrence,
                identity: entry.identity,
                tick: Double(entry.tick),
                value: entry.value,
                slotBlank: view?.voice == nil,
                symbol: view?.voice?.symbol ?? "",
                label: fitted.text,
                labelRect: DrawerRectValue(x: labelX, y: labelY, width: fitted.width,
                                           height: labelHeight),
                labelColor: input.labelColor,
                x: labelX - input.pad,
                lineTop: input.pad,
                lineBottom: max(input.pad, input.plotHeight - input.pad),
                lineWidth: 2 * input.physicalPixel,
                lineColor: input.lineColor,
                selected: input.selectedIdentity == entry.identity,
                hovered: input.hoverIdentity == entry.identity,
                preview: input.previewIdentity == entry.identity,
                offscreen: offscreen))
        }
        return values
    }

    /// Hit the exact geometry the scene drew. Equal-distance overlaps keep the
    /// later row, matching the legacy forward scan.
    static func marker(at x: Double, in markers: borrowing [VoiceMarkerValue],
                       hitRadius: Double) -> VoiceOccurrence? {
        var hit: VoiceOccurrence?
        var distance = Double.infinity
        for index in markers.indices {
            let marker = markers[index]
            let candidate = abs(marker.x - x)
            if candidate <= hitRadius, candidate <= distance {
                hit = marker.occurrence
                distance = candidate
            }
        }
        return hit
    }

    static func pickerRows(slots: borrowing [BankSlotView], filter: String,
                           selected: Int) -> [VoicePickerRowValue] {
        var rows: [VoicePickerRowValue] = []
        rows.reserveCapacity(slots.count)
        for program in slots.indices {
            let view = slots[program]
            let label = VoiceLanePolicy.pickerLabel(slot: program, view: view)
            guard filter.isEmpty
                    || label.range(of: filter, options: .caseInsensitive) != nil
            else { continue }
            rows.append(VoicePickerRowValue(
                program: program, label: label, blank: view.voice == nil,
                symbol: view.voice?.symbol ?? "", selected: program == selected))
        }
        return rows
    }

    static func menuRows(for target: borrowing VoiceTarget) -> [VoiceMenuRowValue] {
        target.occurrence == nil
            ? [VoiceMenuRowValue(actionId: VoiceChangesPagePolicy.insertVoiceChangeAction,
                                 text: "Insert voice change")]
            : [VoiceMenuRowValue(actionId: VoiceChangesPagePolicy.changeVoiceAction,
                                 text: "Change voice"),
               VoiceMenuRowValue(actionId: VoiceChangesPagePolicy.deleteMarkerAction,
                                 text: "Delete")]
    }
}
