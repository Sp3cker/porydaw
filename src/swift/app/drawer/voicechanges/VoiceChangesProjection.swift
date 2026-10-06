import Foundation
import NativeGridTypography
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
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
    public var labelX: Double = 0
    public var labelY: Double = 0
    public var labelWidth: Double = 0
    public var labelHeight: Double = 0
    public var labelColor: QmlColor = .clear
    public var x: Double = 0
    public var lineTop: Double = 0
    public var lineBottom: Double = 0
    public var lineWidth: Double = 0
    public var lineColor: QmlColor = .clear
    public var selected: Bool = false
    public var hovered: Bool = false
    public var preview: Bool = false
    public var offscreen: Bool = false
    public var primitiveName: String = "voiceChangeMarker"


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
            && labelX == other.labelX && labelY == other.labelY
            && labelWidth == other.labelWidth && labelHeight == other.labelHeight
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
    private var soundingProgram: UInt8?

    func initialProgram(_ desired: Int) -> Int {
        programs.contains(desired) ? desired : (programs.first ?? -1)
    }

    func filteredProgram(_ text: String) -> Int {
        resolve(filter: String(text.prefix(64)))
        return programs.first ?? -1
    }

    func program(at index: Int) -> Int {
        programs.indices.contains(index) ? programs[index] : -1
    }

    func movedProgram(from program: Int, delta: Int) -> Int? {
        guard !programs.isEmpty else { return nil }
        guard let current = indices[program] else { return programs[0] }
        return programs[min(max(current + delta, 0), programs.count - 1)]
    }

    func hold(program: Int, audition: ((UInt8, UInt8, UInt8) -> Void)?) {
        guard let audition, let voice = UInt8(exactly: program), voice < 128 else { return }
        release(audition: audition)
        soundingProgram = voice
        audition(voice, 60, 112)
    }

    func release(audition: ((UInt8, UInt8, UInt8) -> Void)?) {
        guard let program = soundingProgram else { return }
        soundingProgram = nil
        audition?(program, 60, 0)
    }

    func releaseIfFilteredOut(audition: ((UInt8, UInt8, UInt8) -> Void)?) {
        if let soundingProgram, indices[Int(soundingProgram)] == nil {
            release(audition: audition)
        }
    }

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
    let font: QmlFont
    var height: Double { metrics.height }
    private let metrics: LaneCaptionMetrics

    init(font: GridFontSpec) {
        self.font = font.qmlFont
        metrics = LaneCaptionMetrics(font: font)
    }

    func advance(_ text: String) -> Double { metrics.advance(text) }

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
    var labelColor: QmlColor
    var lineColor: QmlColor
    var selectedIdentity: String?
    var hoverIdentity: String?
    var previewIdentity: String?
    var caption: VoiceCaption
    var displayX: (Tick) -> Double
}

struct VoiceGutterProjectionInput {
    var plotHeight: Double
    var plotOrigin: Double
    var pad: Double
    var title: String
    var summary: String?
    var titleFont: QmlFont
    var captionFont: QmlFont
    var titleHeight: Double
    var captionHeight: Double
    var titleColor: QmlColor
    var captionColor: QmlColor
}

struct VoiceReadoutProjection {
    var slot: Int
    var blank: Bool
    var symbol: String
    var text: String
    var rect: CGRect
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
                VoiceProjectionEntry(
                    tick: point.tick, value: point.value,
                    identity: identity, sourceOrder: index))
        }
        return projected.sorted { left, right in
            if left.tick != right.tick { return left.tick < right.tick }
            return left.sourceOrder < right.sourceOrder
        }
    }

    /// Only the frozen occurrence moves; equal ticks keep source order.
    static func moving(
        _ entries: [VoiceProjectionEntry], drag: VoiceDragState?
    )
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
                || (entry.tick == moved.tick && entry.sourceOrder < moved.sourceOrder)
            {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        result.insert(moved, at: lower)
        return result
    }

    static func gutterTexts(_ input: VoiceGutterProjectionInput) -> [SceneText] {
        let top = max(0, (input.plotHeight - input.titleHeight - input.captionHeight) / 2)
        var texts = [
            SceneText(
                rect: (input.pad, top, max(0, input.plotOrigin - input.pad), input.titleHeight),
                text: input.title,
                color: input.titleColor,
                font: input.titleFont,
                horizontal: 0x1,
                vertical: 0x80)
        ]
        if let summary = input.summary {
            texts.append(
                SceneText(
                    rect: (
                        input.pad, top + input.titleHeight,
                        max(0, input.plotOrigin - input.pad), input.captionHeight
                    ),
                    text: summary,
                    color: input.captionColor,
                    font: input.captionFont,
                    horizontal: 0x1,
                    vertical: 0x80))
        }
        return texts
    }

    static func readout(
        firstProgram: Int, tick: Tick, points: [LanePoint],
        slots: [BankSlotView], pad: Double,
        plotWidth: Double, plotHeight: Double
    ) -> VoiceReadoutProjection {
        let slot = VoiceLanePolicy.slot(firstProgram: firstProgram, tick: tick, points: points)
        let view = slots.indices.contains(slot) ? slots[slot] : nil
        let label = VoiceLanePolicy.label(slot: slot, view: view)
        return VoiceReadoutProjection(
            slot: slot,
            blank: view?.voice == nil && view?.tone == nil,
            symbol: view?.voice?.symbol ?? "",
            text: label.isEmpty ? "No voice" : label,
            rect: CGRect(x: pad, y: 0, width: max(0, plotWidth - 2 * pad), height: plotHeight))
    }

    static func markers(
        _ input: VoiceMarkerProjectionInput,
        reusing previous: [String: VoiceMarkerHandle] = [:]
    )
        -> [VoiceMarkerHandle]
    {
        let labelHeight = input.caption.height
        let centerY = input.plotHeight / 2 - labelHeight / 2
        let stairStep = min(
            input.stairLimit,
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
            let maxWidth = max(0, input.plotWidth - input.pad)
            let drawn: String
            let labelWidth: Double
            if let old, old.tick == Double(entry.tick), old.value == entry.value {
                drawn = old.label
                labelWidth = old.labelWidth
            } else {
                let label = VoiceLanePolicy.label(slot: entry.value, view: view)
                let source = label.isEmpty ? "No voice" : label
                drawn =
                    input.caption.advance(source) > maxWidth && maxWidth > 0
                    ? input.caption.elided(source, toWidth: maxWidth.rounded(.down))
                    : source
                labelWidth = min(input.caption.advance(drawn), maxWidth)
            }
            let offscreen = labelWidth <= 0
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
                old.labelY == labelY,
                old.selected == (input.selectedIdentity == entry.identity),
                old.hovered == (input.hoverIdentity == entry.identity),
                old.preview == (input.previewIdentity == entry.identity)
            {
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
            handle.labelX = labelX
            handle.labelY = labelY
            handle.labelWidth = labelWidth
            handle.labelHeight = labelHeight
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

    static func pickerRows(
        programs: [Int], slots: [BankSlotView], selected: Int
    )
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
        let values: [(Int, String)] =
            target.occurrence == nil
            ? [(VoiceChangesPagePolicy.insertVoiceChangeAction, "Insert voice change")]
            : [
                (VoiceChangesPagePolicy.changeVoiceAction, "Change voice"),
                (VoiceChangesPagePolicy.deleteMarkerAction, "Delete"),
            ]
        return values.map { action, text in
            let row = VoiceMenuRowHandle()
            row.actionId = action
            row.text = text
            return row
        }
    }

    static func publishPickerRows(
        _ model: QListModel<VoicePickerRowHandle>,
        snapshots: inout [VoicePickerRowHandle],
        values: [VoicePickerRowHandle]
    ) {
        let samePrograms =
            snapshots.count == values.count
            && zip(snapshots, values).allSatisfy { $0.program == $1.program }
        snapshots = values
        if samePrograms {
            syncModel(model, values, matches: { $0.matches($1) })
        } else {
            model.reset(to: values)
        }
    }

}
