import Foundation
import PorydawCore

/// The page's published constants. The base font seed mirrors the grid's
/// `GridCameraPolicy.seedBaseFontPx`, which is internal to this module.
public enum VoiceChangesPagePolicy {
    public static let seedBaseFontPx: Double = 13
    /// `kVoiceChangesMaximumHeightInRows`: Voice Changes is the only section
    /// with a page-declared maximum body.
    public static let maximumBodyRows: Double = 2.5
    /// `VoiceChangeArea::Geometry::resolve`: marker hit radius, hover paint
    /// padding and the minimum grid cell, all font-relative.
    public static let markerHitRadiusFactor: Double = 3.0 / 4.0
    public static let hoverPaintPaddingFactor: Double = 1.0 / 6.0
    /// `layout::Space::One` / `layout::Space::Four` multipliers.
    public static let spaceOneFactor: Double = 0.25
    public static let spaceFourFactor: Double = 1.0
    /// `VoiceChangeArea::VoiceMenuAction` ids: production dispatch and the
    /// checks that activate rendered rows both read these.
    public static let changeVoiceAction = 1
    public static let insertVoiceChangeAction = 2
    public static let deleteMarkerAction = 3
    /// `Qt::AlignRight`, the readout's own alignment.
    public static let readoutAlignment = 2
}

/// `m4aVoiceTypeName`: the declared type name for a bank macro ordinal, or `""`
/// for an ordinal the voicegroup editor does not publish as one voice.
public func voiceTypeName(macro: Int32?) -> String {
    switch macro {
    case BankVoiceMacro.directSound, BankVoiceMacro.keysplit: return "Sample"
    case BankVoiceMacro.directSoundNoResample: return "Sample (fixed pitch)"
    case BankVoiceMacro.directSoundAlt: return "Sample (reverse)"
    case BankVoiceMacro.square1, BankVoiceMacro.square1Alt: return "Square 1"
    case BankVoiceMacro.square2, BankVoiceMacro.square2Alt: return "Square 2"
    case BankVoiceMacro.programmableWave, BankVoiceMacro.programmableWaveAlt: return "Wave"
    case BankVoiceMacro.noise, BankVoiceMacro.noiseAlt: return "Noise"
    case BankVoiceMacro.keysplitAll: return "Drumkit"
    default: return ""
    }
}

/// One voice event's document-owned identity. `LanePoint` carries the chunk and
/// event index the document itself uses, and the tick and value join them so a
/// re-resolution can never accept a different occurrence.
public struct VoiceOccurrence: Equatable, Sendable {
    public var chunk: Int
    public var eventIndex: Int
    public var tick: Tick
    public var value: Int

    public init(chunk: Int, eventIndex: Int, tick: Tick, value: Int) {
        self.chunk = chunk
        self.eventIndex = eventIndex
        self.tick = tick
        self.value = value
    }

    public init(_ point: LanePoint) {
        self.init(chunk: point.chunk, eventIndex: point.eventIndex,
                  tick: point.tick, value: point.value)
    }

    /// The bridge-side spelling QML carries. `LanePoint` is not a bridge type,
    /// so identity crosses as text while the page keeps the typed occurrence.
    public var text: String { "\(chunk).\(eventIndex).\(tick).\(value)" }

    /// The occurrence as the lane's own point, for the semantic lane operations.
    public var point: LanePoint {
        LanePoint(chunk: chunk, eventIndex: eventIndex, tick: tick, value: value)
    }
}

/// Pure voice-lane rules: identity, context, visibility, labels and marker hit
/// testing. Every query is driven by values rather than page state.
public enum VoiceLanePolicy {
    /// `VoiceChangeArea::voiceSlotAt`: the track's first program advanced by
    /// every change at or before `tick`. `-1` means "no slot".
    public static func slot(firstProgram: Int, tick: Tick, points: [LanePoint]) -> Int {
        var slot = firstProgram
        for point in points where point.tick <= tick { slot = point.value }
        return slot
    }

    /// The next change strictly after `tick`, or `nil` when the context runs to
    /// the song's end.
    public static func endTick(after tick: Tick, points: [LanePoint]) -> Tick? {
        points.first { $0.tick > tick }?.tick
    }

    /// The document's current occurrence at an exact tick. Several events at
    /// one tick collapse to the last, exactly as the legacy projection would.
    public static func occurrence(at tick: Tick, in points: [LanePoint]) -> VoiceOccurrence? {
        points.last { $0.tick == tick }.map(VoiceOccurrence.init)
    }

    /// The occurrence a frozen identity still names, or `nil` when the lane no
    /// longer holds exactly it.
    public static func occurrence(_ identity: VoiceOccurrence,
                                  in points: [LanePoint]) -> VoiceOccurrence? {
        points.first { VoiceOccurrence($0) == identity }.map(VoiceOccurrence.init)
    }

    /// The nearest marker whose drawn x is inside the font-relative hit radius;
    /// ties keep the later point, exactly as the legacy scan does.
    public static func marker(at x: Double, points: [LanePoint], displayX: (Tick) -> Double,
                              hitRadius: Double) -> LanePoint? {
        var best: LanePoint?
        var distance = hitRadius + 1
        for point in points {
            let candidate = abs(displayX(point.tick) - x)
            if candidate <= hitRadius, candidate <= distance {
                best = point
                distance = candidate
            }
        }
        return best
    }

    /// `VoiceChangeArea::paintTextFor`: the program number plus the slot's short
    /// name. A blank or unresolvable slot keeps the program number and gains no
    /// name of its own.
    public static func label(slot: Int, view: BankSlotView?) -> String {
        guard slot >= 0, let view else { return "" }
        guard let voice = view.voice else { return String(format: "%03d", slot) }
        let type = voiceTypeName(macro: voice.macro)
        let name = voice.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let short: String
        if !name.isEmpty {
            short = type.isEmpty ? name : "\(name) (\(type))"
        } else {
            short = type.isEmpty ? "Voice" : type
        }
        return String(format: "%03d %@", slot, short)
    }

    /// `VoicePickerModel`: `"%03d  %@"` with the picker's own separator.
    static func pickerLabel(slot: Int, view: BankSlotView?) -> String {
        let label = label(slot: slot, view: view)
        guard let separator = label.firstIndex(of: " ") else { return label }
        return "\(label[label.startIndex..<separator])  \(label[label.index(after: separator)...])"
    }


    /// The hover spelling: the label with the legacy arrow prefix.
    public static func hoverLabel(_ label: String) -> String {
        label.isEmpty ? "" : "→ \(label)"
    }
}
