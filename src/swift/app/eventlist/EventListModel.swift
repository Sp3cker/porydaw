import Foundation
import PorydawCore

/// The event-table type ids from `src/ui/eventtabletypes.h`.
public enum EventListEventType: Int, Equatable, Sendable {
    case noteOff = 0
    case noteOn = 1
    case polyTouch = 2
    case cc = 3
    case program = 4
    case channelTouch = 5
    case bend = 6
    case sysEx0 = 7
    case sysEx7 = 8
    case tempo = 9
    case meta = 10
    case endOfTrack = -1
}

/// One visible event-list row. The final row is the end-of-track sentinel and
/// has no source event while still exposing the chunk's end tick.
public struct EventListRow: Equatable, Sendable {
    public let index: Int
    public let eventIndex: Int?
    public let tick: Tick
    public let event: MidiEvent?
    public let tempo: TempoPoint?
    public let kind: EventListEventType

    public var typeKind: Int { kind.rawValue }
    public var isEndOfTrack: Bool { event == nil && tempo == nil }

    init(index: Int, eventIndex: Int?, tick: Tick, event: MidiEvent?,
         tempo: TempoPoint? = nil, kind: EventListEventType) {
        self.index = index
        self.eventIndex = eventIndex
        self.tick = tick
        self.event = event
        self.tempo = tempo
        self.kind = kind
    }
}

/// Pure row and playhead semantics for one MIDI chunk.
///
/// Rows are rebuilt from the chunk's sorted events and always end in one
/// sentinel row. `currentRow` is edit focus; `playRow` is transport state and
/// never changes the edit cursor.
public struct EventListModel: Equatable, Sendable {
    public static let playheadTint = "#2CE24244"
    public static let columnCount = 7

    public private(set) var chunk: MidiChunk = MidiChunk()
    public private(set) var tempos: [TempoPoint] = []
    public private(set) var filterMask = 127
    public private(set) var rows: [EventListRow] = []
    public private(set) var currentRow = -1
    public private(set) var playRow = -1
    public private(set) var playheadTick = -1.0
    public var voiceNames: [String] = []

    private var hasSource = false

    /// Creates an unattached model. An attached empty chunk has one EOT row;
    /// an unattached model has no rows.
    public init() {}

    /// Creates an attached model over `chunk`.
    public init(chunk: MidiChunk, tempos: [TempoPoint] = [], filterMask: Int = 127) {
        self.chunk = chunk
        self.tempos = tempos
        self.filterMask = filterMask
        hasSource = true
        rows = Self.makeRows(for: chunk, tempos: tempos, filterMask: filterMask)
    }

    /// Replaces the source chunk and clears focus unless explicitly preserved.
    public mutating func setSource(_ chunk: MidiChunk?, tempos: [TempoPoint] = [],
                                   filterMask: Int = 127,
                                   preservingCurrentRow: Bool = false) {
        let oldCurrent = currentRow
        self.tempos = tempos
        self.filterMask = filterMask
        if let chunk {
            self.chunk = chunk
            hasSource = true
            rows = Self.makeRows(for: chunk, tempos: tempos, filterMask: filterMask)
        } else {
            self.chunk = MidiChunk()
            hasSource = false
            rows.removeAll(keepingCapacity: true)
        }
        if preservingCurrentRow, rows.indices.contains(oldCurrent) {
            currentRow = oldCurrent
        } else {
            currentRow = -1
        }
        playRow = playheadRow(tick: playheadTick)
    }

    /// Clears the source and all visible rows.
    public mutating func detach() {
        setSource(nil)
        playheadTick = -1
        playRow = -1
    }

    /// The number of rows, including the end-of-track sentinel when attached.
    public var rowCount: Int { rows.count }

    /// Returns the row at `row`, or nil when it is outside the model.
    public func row(at row: Int) -> EventListRow? {
        rows.indices.contains(row) ? rows[row] : nil
    }

    /// Returns the tick represented by a row. The sentinel returns `endTick`.
    public func rowTick(row: Int) -> Tick? {
        self.row(at: row)?.tick
    }

    /// Returns the C++-compatible type id, or nil for an invalid row.
    public func rowType(row: Int) -> Int? {
        self.row(at: row)?.typeKind
    }

    /// Finds the last event row at or before `tick`, with the C++ sentinel and
    /// negative-tick boundaries. A focused event row wins within half a tick.
    public func playheadRow(tick: Double) -> Int {
        guard hasSource else { return -1 }
        if tick < 0 { return -1 }
        if tick >= Double(chunk.endTick) { return rows.count - 1 }

        var lower = 0
        var upper = rows.count - 1
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if Double(rows[middle].tick) <= tick {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        var result = lower - 1

        // The native model only treats an event row as an exact focused tick;
        // the EOT sentinel is intentionally not a sibling-snap candidate.
        if tick >= 0, rows.indices.contains(currentRow),
           rows[currentRow].event != nil,
           result != currentRow,
           abs(Double(rows[currentRow].tick) - tick) < 0.5 {
            result = currentRow
        }
        return result
    }

    /// Stores edit focus independently of the transport row and reapplies the
    /// focused-sibling rule against the retained playhead tick.
    public mutating func setCurrentRow(_ row: Int) {
        currentRow = rows.indices.contains(row) ? row : -1
        playRow = playheadRow(tick: playheadTick)
    }

    /// Updates the transport row without changing edit focus.
    public mutating func setPlayheadTick(_ tick: Double) {
        playheadTick = tick
        playRow = playheadRow(tick: tick)
    }

    /// Returns the tint for exactly the transport row, or nil for every other
    /// row. This makes whole-row exclusivity observable without a view.
    public func rowTint(row: Int) -> String? {
        guard rows.indices.contains(row), row == playRow else { return nil }
        return Self.playheadTint
    }

    public func isTinted(row: Int) -> Bool {
        rowTint(row: row) != nil
    }

    /// The unique tinted row, or -1 when transport is not positioned.
    public var tintedRow: Int { playRow >= 0 ? playRow : -1 }

    /// Mirrors EventTableModel::flags for the columns relevant to editing.
    public func isCellEditable(row: Int, column: Int) -> Bool {
        guard rows.indices.contains(row), (0..<Self.columnCount).contains(column) else {
            return false
        }
        let item = rows[row]
        if item.isEndOfTrack { return column == 0 }
        if item.tempo != nil { return column == 0 || column == 1 || column == 5 }
        guard let event = item.event else { return false }
        switch column {
        case 0, 1:
            return true
        case 2:
            return event.isChannel
        case 3:
            return event.isChannel || event.isMeta
        case 4:
            switch item.kind {
            case .noteOff, .noteOn, .polyTouch, .cc, .bend:
                return true
            default:
                return false
            }
        case 5:
            return event.isMeta || event.isSystemExclusive
        default:
            return false
        }
    }

    /// Validates the small editing contract needed to hold an in-cell session.
    /// Actual document mutation remains owned by the document presenter.
    public func validatesEdit(row: Int, column: Int, text: String) -> Bool {
        guard isCellEditable(row: row, column: column) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch column {
        case 0:
            guard let value = UInt64(trimmed) else { return false }
            return value <= UInt64(TimeDefaults.maxTick)
        case 1:
            guard let value = Int(trimmed) else { return false }
            if rows[row].tempo != nil { return (0...10).contains(value) }
            switch value {
            case EventListEventType.noteOff.rawValue,
                 EventListEventType.noteOn.rawValue,
                 EventListEventType.polyTouch.rawValue,
                 EventListEventType.cc.rawValue,
                 EventListEventType.program.rawValue,
                 EventListEventType.channelTouch.rawValue,
                 EventListEventType.bend.rawValue,
                 EventListEventType.sysEx0.rawValue,
                 EventListEventType.sysEx7.rawValue,
                 EventListEventType.meta.rawValue:
                return true
            default:
                return false
            }
        case 2:
            guard let value = Int(trimmed) else { return false }
            return (1...16).contains(value)
        case 3, 4:
            guard let value = Int(trimmed) else { return false }
            return (0...127).contains(value)
        case 5:
            if rows[row].tempo != nil {
                return Int(trimmed).map { (20...255).contains($0) } ?? false
            }
            return Self.parseBlob(trimmed) != nil
        default:
            return false
        }
    }

    private static func makeRows(for chunk: MidiChunk, tempos: [TempoPoint],
                                 filterMask: Int) -> [EventListRow] {
        var result: [EventListRow] = []
        result.reserveCapacity(chunk.events.count + tempos.count + 1)
        for (index, event) in chunk.events.enumerated() {
            let kind = eventType(for: event)
            let bit: Int
            switch kind {
            case .noteOff, .noteOn: bit = 1
            case .cc: bit = 2
            case .program: bit = 4
            case .bend: bit = 8
            case .polyTouch, .channelTouch: bit = 16
            case .sysEx0, .sysEx7: bit = 32
            default: bit = 64
            }
            guard event.metaType != 0x51, filterMask & bit != 0 else { continue }
            result.append(EventListRow(index: result.count, eventIndex: index, tick: event.tick,
                                       event: event, kind: kind))
        }
        if filterMask & 64 != 0, !tempos.isEmpty {
            let orderedTempos = tempos.sorted { $0.tick < $1.tick }
            var merged: [EventListRow] = []
            merged.reserveCapacity(result.count + orderedTempos.count)
            var nextTempo = 0
            for eventRow in result {
                while nextTempo < orderedTempos.count
                    && orderedTempos[nextTempo].tick <= eventRow.tick {
                    let tempo = orderedTempos[nextTempo]
                    merged.append(EventListRow(index: merged.count, eventIndex: nil,
                                               tick: tempo.tick, event: nil,
                                               tempo: tempo, kind: .tempo))
                    nextTempo += 1
                }
                merged.append(eventRow)
            }
            while nextTempo < orderedTempos.count {
                let tempo = orderedTempos[nextTempo]
                merged.append(EventListRow(index: merged.count, eventIndex: nil,
                                           tick: tempo.tick, event: nil,
                                           tempo: tempo, kind: .tempo))
                nextTempo += 1
            }
            result = merged
        }
        for index in result.indices {
            let row = result[index]
            result[index] = EventListRow(index: index, eventIndex: row.eventIndex, tick: row.tick,
                                         event: row.event, tempo: row.tempo, kind: row.kind)
        }
        result.append(EventListRow(index: result.count, eventIndex: nil,
                                   tick: chunk.endTick, event: nil, kind: .endOfTrack))
        return result
    }

    private static func eventType(for event: MidiEvent) -> EventListEventType {
        if event.isMeta { return .meta }
        if event.status == 0xF0 { return .sysEx0 }
        if event.status == 0xF7 { return .sysEx7 }
        switch event.typeNibble {
        case 0x8: return .noteOff
        case 0x9: return .noteOn
        case 0xA: return .polyTouch
        case 0xB: return .cc
        case 0xC: return .program
        case 0xD: return .channelTouch
        default: return .bend
        }
    }
}
