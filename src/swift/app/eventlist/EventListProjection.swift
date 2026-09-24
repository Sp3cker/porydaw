import Foundation
import PorydawCore

/// The seven visible table values are derived from the same row snapshot used
/// for selection, editing, and the playhead. No QML copy owns MIDI data.
extension EventListModel {
    public func rowKind(row: Int) -> Int {
        guard let item = self.row(at: row) else { return -1 }
        return item.isEndOfTrack ? 2 : item.tempo != nil ? 1 : 0
    }

    public func cellText(row: Int, column: Int, editing: Bool = false) -> String {
        guard let item = self.row(at: row) else { return "" }
        if column == 0 { return String(item.tick) }
        if item.isEndOfTrack { return column == 1 && !editing ? "End of track" : "" }
        if let tempo = item.tempo {
            let bpm = String(Int(TimeDefaults.tempoBPM(
                forMicrosecondsPerQuarterNote: tempo.microsecondsPerQuarterNote).rounded()))
            switch column {
            case 1: return editing ? String(EventListEventType.tempo.rawValue) : "Tempo"
            case 5: return editing ? bpm : "\(bpm) BPM"
            case 6: return editing ? "" : "Tempo \(bpm) BPM"
            default: return ""
            }
        }
        guard let event = item.event else { return "" }
        let data: (UInt8, UInt8)
        switch event.payload {
        case let .channel(_, first, second): data = (first, second)
        default: data = (0, 0)
        }
        switch column {
        case 1: return editing ? String(item.typeKind) : Self.typeName(item.kind)
        case 2: return event.isChannel ? String(Int(event.channel) + 1) : ""
        case 3:
            if let meta = event.metaType { return String(meta) }
            return event.isChannel ? String(data.0) : ""
        case 4:
            return [.noteOff, .noteOn, .polyTouch, .cc, .bend].contains(item.kind)
                ? String(data.1) : ""
        case 5:
            guard let blob = event.blob else { return "" }
            if let meta = event.metaType, (1...7).contains(meta),
               blob.allSatisfy({ (32..<127).contains($0) }) {
                return "\"\(String(decoding: blob, as: UTF8.self))\""
            }
            let bytes = editing ? blob : Array(blob.prefix(64))
            let hex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            return blob.count > 64 && !editing ? "\(hex) … (\(blob.count) bytes)" : hex
        case 6:
            return editing ? "" : Self.summary(event, kind: item.kind)
        default: return ""
        }
    }

    private static func typeName(_ kind: EventListEventType) -> String {
        switch kind {
        case .noteOff: "Note off"
        case .noteOn: "Note on"
        case .polyTouch: "Poly aftertouch"
        case .cc: "Control change"
        case .program: "Program change"
        case .channelTouch: "Channel aftertouch"
        case .bend: "Pitch bend"
        case .sysEx0: "SysEx (F0)"
        case .sysEx7: "SysEx (F7)"
        case .tempo: "Tempo"
        case .meta: "Meta"
        case .endOfTrack: "End of track"
        }
    }

    private static func summary(_ event: MidiEvent, kind: EventListEventType) -> String {
        switch event.payload {
        case let .channel(_, data0, data1):
            switch kind {
            case .noteOn: return data1 == 0 ? "Note off \(data0) (velocity-0 note-on)"
                : "Note on \(data0), velocity \(data1)"
            case .noteOff: return "Note off \(data0)"
            case .polyTouch: return "Poly aftertouch \(data0) = \(data1)"
            case .cc: return "CC \(data0) = \(data1)"
            case .program: return "Voice \(data0)"
            case .channelTouch: return "Channel aftertouch = \(data0)"
            case .bend: return "Pitch bend \(Int(data1) * 128 + Int(data0) - 8192)"
            default: return ""
            }
        case let .meta(type, _): return "Meta 0x\(String(format: "%02X", type))"
        case let .systemExclusive(_, data): return "\(data.count) payload byte(s)"
        }
    }

    public static func parseBlob(_ text: String) -> [UInt8]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2, trimmed.first == "\"", trimmed.last == "\"" {
            return Array(trimmed.dropFirst().dropLast().utf8)
        }
        let digits = trimmed.filter { $0 != " " && $0 != "," }
        guard !digits.isEmpty, digits.utf8.count.isMultiple(of: 2),
              digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0)
                  || (97...102).contains($0) }) else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(digits.utf8.count / 2)
        var pairs = digits.utf8.makeIterator()
        while let first = pairs.next(), let second = pairs.next() {
            let byte = String(decoding: [first, second], as: UTF8.self)
            guard let value = UInt8(byte, radix: 16) else { return nil }
            result.append(value)
        }
        return result
    }
}
