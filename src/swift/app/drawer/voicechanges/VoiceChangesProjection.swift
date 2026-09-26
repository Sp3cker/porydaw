import Foundation
import NativeGridTypography
import PorydawCore
import QtBridge

/// One drawn voice-change marker: its occurrence identity, projected label and
/// marker rule, and its interaction state.
@MainActor
@QtBridgeable
// Swift 6.4 misses the macro-emitted inherited conformance across source files.
// Remove this explicit conformance once the toolchain contains swiftlang/swift#92390.
public final class VoiceMarkerHandle: QVariantGettable {
    public var identity: String = ""
    public var tick: Double = 0
    public var value: Int = 0
    public var slotBlank: Bool = false
    public var symbol: String = ""
    public var label: String = ""
    public var labelRect: [String: QVariantSettable] = VoiceMarkerHandle.rect(0, 0, 0, 0)
    public var labelColor: String = ""
    public var x: Double = 0
    public var lineTop: Double = 0
    public var lineBottom: Double = 0
    public var lineWidth: Double = 0
    public var lineColor: String = ""
    public var selected: Bool = false
    public var hovered: Bool = false
    public var preview: Bool = false
    public var offscreen: Bool = false
    public var primitiveName: String = "voiceChangeMarker"

    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double)
        -> [String: QVariantSettable]
    {
        ["x": x, "y": y, "width": w, "height": h]
    }

    static func rectMatches(_ lhs: [String: QVariantSettable],
                            _ rhs: [String: QVariantSettable]) -> Bool {
        for key in ["x", "y", "width", "height"] {
            guard let left = lhs[key] as? Double, let right = rhs[key] as? Double,
                  left == right else { return false }
        }
        return true
    }

    @QtIgnored
    func matches(_ other: VoiceMarkerHandle) -> Bool {
        identity == other.identity && tick == other.tick && value == other.value
            && slotBlank == other.slotBlank && symbol == other.symbol
            && label == other.label && labelColor == other.labelColor
            && x == other.x && lineTop == other.lineTop && lineBottom == other.lineBottom
            && lineWidth == other.lineWidth && lineColor == other.lineColor
            && selected == other.selected && hovered == other.hovered
            && preview == other.preview && offscreen == other.offscreen
            && primitiveName == other.primitiveName
            && VoiceMarkerHandle.rectMatches(labelRect, other.labelRect)
    }
}

@MainActor
@QtBridgeable
public final class VoicePickerRowHandle {
    public var program: Int = 0
    public var label: String = ""
    public var blank: Bool = false
    public var symbol: String = ""
    public var selected: Bool = false
    public var primitiveName: String = "voicePickerRow"

    @QtIgnored
    func matches(_ other: VoicePickerRowHandle) -> Bool {
        program == other.program && label == other.label && blank == other.blank
            && symbol == other.symbol && selected == other.selected
            && primitiveName == other.primitiveName
    }
}

/// Bank facts are invalidated by their actual publication, not song revision.
/// Formatting/filtering is independent of the picker's changing selection.
@MainActor
final class VoicePickerProjectionCache {
    private var slots: [BankSlotView] = []
    private var rows: [VoicePickerRowHandle] = []
    private var filter: String?
    private var filtered: [VoicePickerRowHandle] = []
    private var selectedIndex: Int?
    private(set) var programs: [Int] = []
    private(set) var indices: [Int: Int] = [:]

    func refresh(slots: [BankSlotView]) {
        guard self.slots != slots else { return }
        self.slots = slots
        rows = VoiceChangesProjection.pickerRows(
            programs: Array(slots.indices), slots: slots, selected: -1)
        filter = nil
    }

    func resolve(filter: String) {
        guard self.filter != filter else { return }
        self.filter = filter
        filtered = rows.filter {
            filter.isEmpty || $0.label.range(of: filter, options: .caseInsensitive) != nil
        }
        programs = filtered.map(\.program)
        indices = Dictionary(uniqueKeysWithValues: programs.enumerated().map { ($1, $0) })
        selectedIndex = nil
    }

    func selectedRows(program: Int) -> [VoicePickerRowHandle] {
        let next = indices[program]
        guard next != selectedIndex else { return filtered }
        replaceSelection(at: selectedIndex, selected: false)
        replaceSelection(at: next, selected: true)
        selectedIndex = next
        return filtered
    }

    private func replaceSelection(at index: Int?, selected: Bool) {
        guard let index else { return }
        let old = filtered[index]
        let row = VoicePickerRowHandle()
        row.program = old.program
        row.label = old.label
        row.blank = old.blank
        row.symbol = old.symbol
        row.selected = selected
        filtered[index] = row
    }
}

@MainActor
@QtBridgeable
public final class VoiceMenuRowHandle {
    public var actionId: Int = 0
    public var text: String = ""
    public var primitiveName: String = "voiceChangeMenuRow"

    @QtIgnored
    func matches(_ other: VoiceMenuRowHandle) -> Bool {
        actionId == other.actionId && text == other.text
            && primitiveName == other.primitiveName
    }
}

/// Captions measured through the native font metrics used by the roll.
@MainActor
final class VoiceCaption {
    let fontMap: [String: QVariantSettable]
    let height: Double
    private let session: OpaquePointer

    init(pixelSize: Int, weight: Int) {
        let family = VoiceChangesPage.fontFamily
        fontMap = ["family": family, "pixelSize": pixelSize, "weight": weight,
                   "letterSpacing": 0.0, "features": ["tnum": 1],
                   "hintingPreference": fontPreferNoHinting]
        session = family.withCString { sgf_create($0, Int32(pixelSize), Int32(weight), 0)! }
        height = sgf_extents(session).height
    }

    isolated deinit { sgf_destroy(session) }

    func advance(_ text: String) -> Double { text.withCString { sgf_advance(session, $0) } }

    func elided(_ text: String, toWidth width: Double) -> String {
        guard width > 0, advance(text) > width else { return text }
        let characters = Array(text)
        var lower = 0
        var upper = max(0, characters.count - 1)
        while lower < upper {
            let middle = (lower + upper + 1) / 2
            if advance(String(characters.prefix(middle)) + "…") <= width {
                lower = middle
            } else {
                upper = middle - 1
            }
        }
        return String(characters.prefix(lower)) + "…"
    }
}

struct VoiceProjectionEntry {
    var tick: Tick
    var value: Int
    var identity: String
    var sourceOrder: Int = 0
}

struct VoiceMarkerProjectionInput {
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
    var caption: VoiceCaption
    var displayX: (Tick) -> Double
}

struct VoiceSpanProjectionInput {
    var entries: [VoiceProjectionEntry]
    var firstProgram: Int
    var lengthTicks: Tick
    var plotWidth: Double
    var plotHeight: Double
    var color: String
    var displayX: (Tick) -> Double
}

struct VoiceGutterProjectionInput {
    var plotHeight: Double
    var plotOrigin: Double
    var title: String
    var summary: String?
    var titleFont: [String: QVariantSettable]
    var captionFont: [String: QVariantSettable]
    var titleHeight: Double
    var captionHeight: Double
    var titleColor: String
    var captionColor: String
}

struct VoiceReadoutProjection {
    var slot: Int
    var blank: Bool
    var symbol: String
    var text: String
    var rect: [String: QVariantSettable]
}

struct VoiceGridProjectionColors {
    var subdivision1: String
    var subdivision2: String
    var subdivision3: String
    var bar: String
    var beat: String
    var fineBeat: String
}

/// Pure layout/projection of lane data into published marker, span, picker and
/// menu records. The page supplies camera, palette and interaction facts.
@MainActor
enum VoiceChangesProjection {
    static func entries(points: [LanePoint]) -> [VoiceProjectionEntry] {
        var projected: [VoiceProjectionEntry] = []
        projected.reserveCapacity(points.count)
        for (index, point) in points.enumerated() {
            let identity = VoiceOccurrence(point).text
            projected.append(
                VoiceProjectionEntry(tick: point.tick, value: point.value,
                                     identity: identity, sourceOrder: index))
        }
        return projected.sorted { left, right in
            if left.tick != right.tick { return left.tick < right.tick }
            return left.sourceOrder < right.sourceOrder
        }
    }

    /// Only the frozen occurrence moves; equal ticks keep source order.
    static func moving(_ entries: [VoiceProjectionEntry], drag: VoiceDragState?)
        -> [VoiceProjectionEntry]
    {
        guard let drag, drag.active,
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

    static func spans(_ input: VoiceSpanProjectionInput) -> [SceneRect] {
        var program = input.firstProgram
        var spanStart: Tick = 0
        var rects: [SceneRect] = []
        func appendSpan(from begin: Tick, to end: Tick) {
            let left = min(max(input.displayX(begin), 0), input.plotWidth)
            let right = min(max(input.displayX(end), 0), input.plotWidth)
            let rect = SceneRect(x: left, y: 0, width: max(0, right - left),
                                 height: input.plotHeight, fillColor: input.color,
                                 primitiveName: "voiceHeldSpan")
            if rect.width > 0 { rects.append(rect) }
        }
        for entry in input.entries {
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

    static func gutterTexts(_ input: VoiceGutterProjectionInput) -> [SceneText] {
        let top = max(0, (input.plotHeight - input.titleHeight - input.captionHeight) / 2)
        var texts = [SceneText(
            rect: (0, top, input.plotOrigin, input.titleHeight),
            text: input.title,
            color: input.titleColor,
            font: input.titleFont,
            horizontal: 0x1,
            vertical: 0x80)]
        if let summary = input.summary {
            texts.append(SceneText(
                rect: (0, top + input.titleHeight, input.plotOrigin, input.captionHeight),
                text: summary,
                color: input.captionColor,
                font: input.captionFont,
                horizontal: 0x1,
                vertical: 0x80))
        }
        return texts
    }

    static func readout(firstProgram: Int, tick: Tick, points: [LanePoint],
                        slots: [BankSlotView], pad: Double,
                        plotWidth: Double, plotHeight: Double) -> VoiceReadoutProjection {
        let slot = VoiceLanePolicy.slot(firstProgram: firstProgram, tick: tick, points: points)
        let view = slots.indices.contains(slot) ? slots[slot] : nil
        let label = VoiceLanePolicy.label(slot: slot, view: view)
        return VoiceReadoutProjection(
            slot: slot,
            blank: view?.voice == nil && view?.tone == nil,
            symbol: view?.voice?.symbol ?? "",
            text: label.isEmpty ? "No voice" : label,
            rect: VoiceMarkerHandle.rect(pad, 0, max(0, plotWidth - 2 * pad), plotHeight))
    }

    static func grid(metrics: GridMetrics, camera: EditorCamera, plotWidth: Double,
                     plotHeight: Double, colors: VoiceGridProjectionColors,
                     displayX: (Tick) -> Double) -> [SceneRect] {
        let physicalPixel = max(metrics.pixel, 0.0001)
        let roundingMargin = physicalPixel / 2
        let beginTick = camera.tickAtContentX(-roundingMargin)
        let endTick = camera.tickAtContentX(plotWidth - physicalPixel + roundingMargin) + 1
        guard endTick > beginTick else { return [] }
        let range = (begin: Tick(max(0, beginTick.rounded(.down))),
                     end: Tick(max(1, endTick.rounded(.up))))
        let stroke = metrics.gridLineStroke
        var rects: [SceneRect] = []
        metrics.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let color = level == 1 ? colors.subdivision1
                : level == 2 ? colors.subdivision2 : colors.subdivision3
            rects.append(SceneRect(
                x: displayX(tick) - stroke / 2,
                y: 0,
                width: stroke,
                height: plotHeight,
                fillColor: color,
                primitiveName: "voiceGrid"))
        }
        var segment = metrics.timeAxis.segmentAt(range.begin)
        var finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
            }
            rects.append(SceneRect(
                x: displayX(tick) - stroke / 2,
                y: 0,
                width: stroke,
                height: plotHeight,
                fillColor: isBar ? colors.bar : finest ? colors.fineBeat : colors.beat,
                primitiveName: "voiceGrid"))
        }
        return rects
    }

    static func markers(_ input: VoiceMarkerProjectionInput,
                        reusing previous: [String: VoiceMarkerHandle] = [:])
        -> [VoiceMarkerHandle]
    {
        let labelHeight = input.caption.height
        let centerY = input.plotHeight / 2 - labelHeight / 2
        let stairStep = min(input.stairLimit,
                            (input.plotHeight - labelHeight - 2 * input.pad) / 2)
        let canStair = stairStep > 1
        var stairUp = true
        var lastXEnd = -Double.infinity
        var values: [VoiceMarkerHandle] = []
        values.reserveCapacity(input.entries.count)
        for entry in input.entries {
            let old = previous[entry.identity]
            let view = input.slots.indices.contains(entry.value) ? input.slots[entry.value] : nil
            let labelX = input.displayX(entry.tick) + input.pad
            let maxWidth = max(0, input.plotWidth - labelX)
            let drawn: String
            let labelWidth: Double
            if let old, old.tick == Double(entry.tick), old.value == entry.value {
                drawn = old.label
                labelWidth = old.labelRect["width"] as? Double ?? 0
            } else {
                let label = VoiceLanePolicy.label(slot: entry.value, view: view)
                let source = label.isEmpty ? "No voice" : label
                drawn = input.caption.advance(source) > maxWidth && maxWidth > 0
                    ? input.caption.elided(source, toWidth: maxWidth.rounded(.down))
                    : source
                labelWidth = min(input.caption.advance(drawn), maxWidth)
            }
            let offscreen = labelX + labelWidth < 0 || labelX > input.plotWidth || labelWidth <= 0
            var labelY = centerY
            if !offscreen {
                if labelX < lastXEnd + input.gap, canStair {
                    stairUp.toggle()
                    labelY = stairUp ? centerY - stairStep : centerY + stairStep
                }
                let lower = input.pad
                let upper = max(lower, input.plotHeight - labelHeight - input.pad)
                labelY = min(max(labelY, lower), upper)
                lastXEnd = labelX + labelWidth + input.gap
            }
            // Stair state propagates through overlapping neighbors. Walk the
            // cheap state, retaining every unaffected immutable published row.
            if let old, old.tick == Double(entry.tick), old.value == entry.value,
               old.label == drawn,
               old.labelRect["y"] as? Double == labelY,
               old.selected == (input.selectedIdentity == entry.identity),
               old.hovered == (input.hoverIdentity == entry.identity),
               old.preview == (input.previewIdentity == entry.identity) {
                values.append(old)
                continue
            }
            let handle = VoiceMarkerHandle()
            handle.identity = entry.identity
            handle.tick = Double(entry.tick)
            handle.value = entry.value
            handle.slotBlank = view?.voice == nil && view?.tone == nil
            handle.symbol = view?.voice?.symbol ?? ""
            handle.label = drawn
            handle.labelRect = VoiceMarkerHandle.rect(labelX, labelY, labelWidth, labelHeight)
            handle.labelColor = input.labelColor
            handle.x = labelX - input.pad
            handle.lineTop = input.pad
            handle.lineBottom = max(input.pad, input.plotHeight - input.pad)
            handle.lineWidth = 2 * input.physicalPixel
            handle.lineColor = input.lineColor
            handle.selected = input.selectedIdentity == entry.identity
            handle.hovered = input.hoverIdentity == entry.identity
            handle.preview = input.previewIdentity == entry.identity
            handle.offscreen = offscreen
            values.append(handle)
        }
        return values
    }

    static func pickerRows(programs: [Int], slots: [BankSlotView], selected: Int)
        -> [VoicePickerRowHandle]
    {
        programs.map { program in
            let view = slots.indices.contains(program) ? slots[program] : nil
            let row = VoicePickerRowHandle()
            row.program = program
            row.label = VoiceLanePolicy.pickerLabel(slot: program, view: view)
            row.blank = view?.voice == nil && view?.tone == nil
            row.symbol = view?.voice?.symbol ?? ""
            row.selected = program == selected
            return row
        }
    }

    static func menuRows(for target: VoiceTarget) -> [VoiceMenuRowHandle] {
        let values: [(Int, String)] = target.occurrence == nil
            ? [(VoiceChangesPagePolicy.insertVoiceChangeAction, "Insert voice change")]
            : [(VoiceChangesPagePolicy.changeVoiceAction, "Change voice"),
               (VoiceChangesPagePolicy.deleteMarkerAction, "Delete")]
        return values.map { action, text in
            let row = VoiceMenuRowHandle()
            row.actionId = action
            row.text = text
            return row
        }
    }

    static func syncRects(_ model: QListModel<SceneRect>, _ values: [SceneRect]) {
        syncModel(model, values, matches: { $0.matches($1) })
    }

    static func syncTexts(_ model: QListModel<SceneText>, _ values: [SceneText]) {
        syncModel(model, values, matches: textMatches)
    }

    static func syncPickerRows(_ model: QListModel<VoicePickerRowHandle>,
                               _ values: [VoicePickerRowHandle]) {
        syncModel(model, values, matches: { $0.matches($1) })
    }

    static func syncMenuRows(_ model: QListModel<VoiceMenuRowHandle>,
                             _ values: [VoiceMenuRowHandle]) {
        syncModel(model, values, matches: { $0.matches($1) })
    }

    static func textMatches(_ lhs: SceneText, _ rhs: SceneText) -> Bool {
        lhs.labelText == rhs.labelText && lhs.labelColor == rhs.labelColor
            && lhs.labelHorizontalAlignment == rhs.labelHorizontalAlignment
            && lhs.labelVerticalAlignment == rhs.labelVerticalAlignment
            && VoiceMarkerHandle.rectMatches(lhs.labelRect, rhs.labelRect)
            && lhs.labelFont.count == rhs.labelFont.count
            && lhs.labelFont.allSatisfy {
                String(describing: $1) == String(describing: rhs.labelFont[$0])
            }
    }

    static func fontMatches(_ lhs: [String: QVariantSettable],
                            _ rhs: [String: QVariantSettable]) -> Bool {
        lhs.count == rhs.count && lhs.allSatisfy {
            String(describing: $1) == String(describing: rhs[$0])
        }
    }
}
