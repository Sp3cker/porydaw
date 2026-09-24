import Foundation
import PorydawCore

@MainActor
extension EventListPresenter {
    func dispatchCanStepEditing() -> Bool {
        editing && ((2...4).contains(editingColumn)
            || (editingColumn == 5 && model.row(at: editingRow)?.tempo != nil))
    }

    func dispatchSteppedEditingText(currentText: String, delta: Int) -> String {
        guard canStepEditing(), delta != 0, let current = Int(currentText) else {
            return currentText
        }
        let bounds = editingColumn == 2 ? 1...16
            : editingColumn == 5 ? 20...255 : 0...127
        guard bounds.contains(current) else { return currentText }
        return String(max(bounds.lowerBound, min(bounds.upperBound, current + delta)))
    }

    public func commitCellEdit(row: Int, column: Int, text: String) -> Bool {
        let convertingToTempo = column == 1 && chunkIndex == 0
            && text.trimmingCharacters(in: .whitespacesAndNewlines)
                == String(EventListEventType.tempo.rawValue)
            && model.row(at: row)?.event != nil
        guard let session, !session.isClosed,
              session.document.rawChunks.indices.contains(chunkIndex),
              model.validatesEdit(row: row, column: column, text: text) || convertingToTempo,
              let item = model.row(at: row) else { return false }
        let document = session.document
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.isEndOfTrack {
            guard let tick = Tick(input),
                  tick >= (model.chunk.events.last?.tick ?? 0) else { return false }
            document.setChunkEnd(chunkIndex, tick: tick)
            return true
        }
        if let tempo = item.tempo {
            switch column {
            case 0:
                guard let tick = Tick(input) else { return false }
                document.editTempo(TempoEdit(remove: [tempo], add: [
                    TempoPoint(tick: tick,
                               microsecondsPerQuarterNote: tempo.microsecondsPerQuarterNote)]))
            case 1:
                guard let kind = Int(input) else { return false }
                if kind == EventListEventType.tempo.rawValue { return true }
                guard let newEvent = Self.retyped(MidiEvent.meta(tick: tempo.tick, type: 6,
                                                                   data: []), as: kind) else {
                    return false
                }
                document.editRawAndTempo(chunk: chunkIndex, deleting: [],
                                         tempo: TempoEdit(remove: [tempo]), inserting: newEvent)
            case 5:
                guard let bpm = Int(input) else { return false }
                document.editTempo(TempoEdit(remove: [tempo], add: [TempoPoint(
                    tick: tempo.tick,
                    microsecondsPerQuarterNote: TimeDefaults.microsecondsPerQuarterNote(
                        forBPM: bpm))]))
            default: return false
            }
            return true
        }
        guard let event = item.event, let index = item.eventIndex else { return false }
        if column == 1, input == String(EventListEventType.tempo.rawValue) {
            guard chunkIndex == 0 else { return false }
            document.editRawAndTempo(chunk: chunkIndex, deleting: [index],
                                     tempo: TempoEdit(add: [TempoPoint(
                                        tick: event.tick, microsecondsPerQuarterNote: 500_000)]))
            return true
        }
        var replacement = event
        switch column {
        case 0:
            guard let tick = Tick(input) else { return false }
            replacement.tick = tick
        case 1:
            guard let kind = Int(input), let changed = Self.retyped(event, as: kind) else {
                return false
            }
            replacement = changed
        case 2:
            guard let value = UInt8(input),
                  case let .channel(status, data0, data1) = event.payload else { return false }
            replacement.payload = .channel(status: (status & 0xF0) | (value - 1),
                                           data0: data0, data1: data1)
        case 3:
            guard let value = UInt8(input) else { return false }
            switch event.payload {
            case let .channel(status, _, data1):
                replacement.payload = .channel(status: status, data0: value, data1: data1)
            case let .meta(_, bytes): replacement.payload = .meta(type: value, data: bytes)
            default: return false
            }
        case 4:
            guard let value = UInt8(input),
                  case let .channel(status, data0, _) = event.payload else { return false }
            replacement.payload = .channel(status: status, data0: data0, data1: value)
        case 5:
            guard let bytes = EventListModel.parseBlob(input) else { return false }
            switch event.payload {
            case let .meta(type, _): replacement.payload = .meta(type: type, data: bytes)
            case let .systemExclusive(status, _):
                replacement.payload = .systemExclusive(status: status, data: bytes)
            default: return false
            }
        default: return false
        }
        document.modifyRawEvent(chunk: chunkIndex, index: index, event: replacement)
        return true
    }

    private static func retyped(_ event: MidiEvent, as kind: Int) -> MidiEvent? {
        let status: UInt8
        switch kind {
        case 0...6:
            status = (UInt8(kind + 8) << 4) | (event.isChannel ? event.channel : 0)
            let old: (UInt8, UInt8)
            if case let .channel(_, data0, data1) = event.payload {
                old = (data0, data1)
            } else { old = (0, 0) }
            return .channel(tick: event.tick, status: status, data0: old.0,
                            data1: kind == 4 || kind == 5 ? 0 : old.1)
        case 7, 8:
            status = kind == 7 ? 0xF0 : 0xF7
            return .systemExclusive(tick: event.tick, status: status, data: event.blob ?? [])
        case 10:
            return .meta(tick: event.tick, type: event.metaType ?? 6,
                         data: event.blob ?? [])
        default: return nil
        }
    }

    func dispatchAddEvent() {
        guard let session, !session.isClosed,
              session.document.rawChunks.indices.contains(chunkIndex) else { return }
        if chunkIndex == 0, model.row(at: currentRow)?.tempo != nil {
            session.document.editTempo(TempoEdit(add: [TempoPoint(
                tick: session.editCursor, microsecondsPerQuarterNote: 500_000)]))
            return
        }
        var event = model.row(at: currentRow)?.event
            ?? .channel(status: 0xB0, data0: 7, data1: 100)
        event.tick = session.editCursor
        session.document.insertRawEvent(chunk: chunkIndex, event: event)
    }

    func dispatchDeleteSelected() {
        guard let session, !session.isClosed,
              session.document.rawChunks.indices.contains(chunkIndex) else { return }
        let selection = selectedRows.compactMap { model.row(at: $0) }
        let indices = selection.compactMap(\.eventIndex)
        let tempos = selection.compactMap(\.tempo)
        guard !indices.isEmpty || !tempos.isEmpty else { return }
        selectedRows = []
        selectionAnchor = -1
        model.setCurrentRow(-1)
        currentRow = -1
        session.document.editRawAndTempo(chunk: chunkIndex, deleting: indices,
                                         tempo: TempoEdit(remove: tempos))
    }
}
