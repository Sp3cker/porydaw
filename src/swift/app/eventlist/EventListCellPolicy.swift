import Foundation
import PorydawCore

/// Pure text acceptance and parsing for event-list cell edits.
public enum EventListCellPolicy {
    /// A parsed cell value for the presenter's document-edit dispatch.
    public enum Value {
        case tick(Tick)
        case kind(EventListEventType)
        case channel(UInt8)
        case data0(UInt8)
        case data1(UInt8)
        case tempoBPM(Int)
        case blob([UInt8])
    }

    private static let channelBounds = 1...16
    private static let dataBounds = 0...127
    private static let tempoBounds = 20...255

    static func accepts(column: Int, text: String, isTempo: Bool) -> Bool {
        parse(
            column: column, input: text.trimmingCharacters(in: .whitespacesAndNewlines),
            isTempo: isTempo, allowsTempoKind: isTempo, forCommit: false) != nil
    }

    /// Parses a commit, including its raw-to-tempo and end-of-track allowances.
    public static func parseCommit(
        column: Int, text: String, item: EventListRow, isEditable: Bool,
        chunkIndex: Int, lastEventTick: Tick
    ) -> Value? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let convertingToTempo =
            column == 1 && chunkIndex == 0
            && input == String(EventListEventType.tempo.rawValue)
            && item.event != nil
        guard isEditable || convertingToTempo,
            let value = parse(
                column: column, input: input, isTempo: item.tempo != nil,
                allowsTempoKind: item.tempo != nil || convertingToTempo, forCommit: true)
        else { return nil }
        if item.isEndOfTrack {
            guard case .tick(let tick) = value, tick >= lastEventTick else { return nil }
        }
        return value
    }

    /// Steps a numeric cell using the same channel, data-byte, and BPM bounds.
    public static func steppedText(column: Int, currentText: String, delta: Int) -> String {
        guard delta != 0, let current = Int(currentText) else { return currentText }
        let bounds =
            column == 2
            ? channelBounds
            : column == 5 ? tempoBounds : dataBounds
        guard bounds.contains(current) else { return currentText }
        return String(max(bounds.lowerBound, min(bounds.upperBound, current + delta)))
    }

    private static func parse(
        column: Int, input: String, isTempo: Bool, allowsTempoKind: Bool, forCommit: Bool
    ) -> Value? {
        switch column {
        case 0:
            guard let value = UInt64(input), value <= UInt64(TimeDefaults.maxTick) else {
                return nil
            }
            if forCommit {
                guard let tick = Tick(input) else { return nil }
                return .tick(tick)
            }
            return .tick(Tick(value))
        case 1:
            guard let value = Int(input), let kind = EventListEventType(rawValue: value) else {
                return nil
            }
            switch kind {
            case .noteOff, .noteOn, .polyTouch, .cc, .program, .channelTouch,
                .bend, .sysEx0, .sysEx7, .meta:
                return .kind(kind)
            case .tempo:
                return allowsTempoKind ? .kind(kind) : nil
            case .endOfTrack:
                return nil
            }
        case 2, 3, 4:
            let bounds = column == 2 ? channelBounds : dataBounds
            guard let value = Int(input), bounds.contains(value) else { return nil }
            // The model uses signed parsing; commits also require unsigned text parsing.
            let byte: UInt8
            if forCommit {
                guard let parsed = UInt8(input) else { return nil }
                byte = parsed
            } else {
                byte = UInt8(value)
            }
            switch column {
            case 2: return .channel(byte)
            case 3: return .data0(byte)
            default: return .data1(byte)
            }
        case 5:
            if isTempo {
                guard let bpm = Int(input), tempoBounds.contains(bpm) else { return nil }
                return .tempoBPM(bpm)
            }
            guard let bytes = EventListModel.parseBlob(input) else { return nil }
            return .blob(bytes)
        default:
            return nil
        }
    }
}
