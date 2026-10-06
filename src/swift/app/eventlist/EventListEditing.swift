import Foundation
import PorydawCore
import PorydawAppEventList

@MainActor
extension EventListPresenter {
    func dispatchCanStepEditing() -> Bool {
        editing
            && ((2...4).contains(editingColumn)
                || (editingColumn == 5 && model.row(at: editingRow)?.tempo != nil))
    }

    func dispatchSteppedEditingText(currentText: String, delta: Int) -> String {
        guard canStepEditing() else { return currentText }
        return EventListCellPolicy.steppedText(
            column: editingColumn, currentText: currentText, delta: delta)
    }

    public func commitCellEdit(row: Int, column: Int, text: String) -> Bool {
        guard let session, !session.isClosed,
            session.document.rawChunks.indices.contains(chunkIndex),
            let item = model.row(at: row),
            let value = EventListCellPolicy.parseCommit(
                column: column, text: text, item: item,
                isEditable: model.isCellEditable(row: row, column: column),
                chunkIndex: chunkIndex, lastEventTick: model.chunk.events.last?.tick ?? 0)
        else { return false }
        let document = session.document
        if item.isEndOfTrack {
            guard case let .tick(tick) = value else { return false }
            document.setChunkEnd(chunkIndex, tick: tick)
            return true
        }
        if let tempo = item.tempo {
            switch value {
            case let .tick(tick):
                document.editTempo(
                    TempoEdit(
                        remove: [tempo],
                        add: [
                            TempoPoint(
                                tick: tick,
                                microsecondsPerQuarterNote: tempo.microsecondsPerQuarterNote)
                        ]))
            case let .kind(kind):
                if kind == .tempo { return true }
                guard
                    let newEvent = Self.retyped(
                        MidiEvent.meta(
                            tick: tempo.tick, type: 6,
                            data: []), as: kind.rawValue)
                else {
                    return false
                }
                document.editRawAndTempo(
                    chunk: chunkIndex, deleting: [],
                    tempo: TempoEdit(remove: [tempo]), inserting: newEvent)
            case let .tempoBPM(bpm):
                document.editTempo(
                    TempoEdit(
                        remove: [tempo],
                        add: [
                            TempoPoint(
                                tick: tempo.tick,
                                microsecondsPerQuarterNote: TimeDefaults.microsecondsPerQuarterNote(
                                    forBPM: bpm))
                        ]))
            case .channel, .data0, .data1, .blob: return false
            }
            return true
        }
        guard let event = item.event, let index = item.eventIndex else { return false }
        if case .kind(.tempo) = value {
            document.editRawAndTempo(
                chunk: chunkIndex, deleting: [index],
                tempo: TempoEdit(add: [
                    TempoPoint(
                        tick: event.tick, microsecondsPerQuarterNote: 500_000)
                ]))
            return true
        }
        var replacement = event
        switch value {
        case let .tick(tick):
            replacement.tick = tick
        case let .kind(kind):
            guard let changed = Self.retyped(event, as: kind.rawValue) else {
                return false
            }
            replacement = changed
        case let .channel(value):
            guard case let .channel(status, data0, data1) = event.payload else { return false }
            replacement.payload = .channel(
                status: (status & 0xF0) | (value - 1),
                data0: data0, data1: data1)
        case let .data0(value):
            switch event.payload {
            case let .channel(status, _, data1):
                replacement.payload = .channel(status: status, data0: value, data1: data1)
            case let .meta(_, bytes): replacement.payload = .meta(type: value, data: bytes)
            default: return false
            }
        case let .data1(value):
            guard case let .channel(status, data0, _) = event.payload else { return false }
            replacement.payload = .channel(status: status, data0: data0, data1: value)
        case let .blob(bytes):
            switch event.payload {
            case let .meta(type, _): replacement.payload = .meta(type: type, data: bytes)
            case let .systemExclusive(status, _):
                replacement.payload = .systemExclusive(status: status, data: bytes)
            default: return false
            }
        case .tempoBPM: return false
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
            } else {
                old = (0, 0)
            }
            return .channel(
                tick: event.tick, status: status, data0: old.0,
                data1: kind == 4 || kind == 5 ? 0 : old.1)
        case 7, 8:
            status = kind == 7 ? 0xF0 : 0xF7
            return .systemExclusive(tick: event.tick, status: status, data: event.blob ?? [])
        case 10:
            return .meta(
                tick: event.tick, type: event.metaType ?? 6,
                data: event.blob ?? [])
        default: return nil
        }
    }

    func dispatchAddEvent() {
        guard let session, !session.isClosed,
            session.document.rawChunks.indices.contains(chunkIndex)
        else { return }
        if let row = model.row(at: currentRow), row.isEndOfTrack { return }
        if chunkIndex == 0, let tempo = model.row(at: currentRow)?.tempo {
            session.document.editTempo(
                TempoEdit(add: [
                    TempoPoint(
                        tick: session.editCursor,
                        microsecondsPerQuarterNote: tempo.microsecondsPerQuarterNote)
                ]))
            selectedRows = []
            selectionAnchor = -1
            if let row = model.rows.firstIndex(where: { $0.tempo?.tick == session.editCursor })
                ?? model.rows.firstIndex(where: {
                    $0.eventIndex != nil
                        && $0.tick == session.editCursor
                })
            {
                focusRow(row: row)
                selectedRows = [row]
            }
            return
        }
        var event =
            model.row(at: currentRow)?.event
            ?? .channel(status: 0xB0, data0: 7, data1: 100)
        event.tick = session.editCursor
        session.document.insertRawEvent(chunk: chunkIndex, event: event)
        selectedRows = []
        selectionAnchor = -1
        if let row = model.rows.firstIndex(where: { $0.event == event }) {
            focusRow(row: row)
            selectedRows = [row]
        }
    }

    func insertCopyOfRow(row: Int) {
        guard let session, !session.isClosed,
            session.document.rawChunks.indices.contains(chunkIndex),
            let item = model.row(at: row)
        else { return }
        if let tempo = item.tempo {
            session.document.editTempo(TempoEdit(add: [tempo]))
        } else if let event = item.event {
            session.document.insertRawEvent(chunk: chunkIndex, event: event)
        } else {
            addEvent()
            return
        }
        if let copied = model.rows.lastIndex(where: {
            $0.event == item.event && item.event != nil
                || $0.tempo == item.tempo && item.tempo != nil
        }) {
            focusRow(row: copied)
            selectedRows = [copied]
            selectionAnchor = copied
        }
    }

    func dispatchDeleteSelected() {
        guard let session, !session.isClosed,
            session.document.rawChunks.indices.contains(chunkIndex)
        else { return }
        let selection = selectedRows.compactMap { model.row(at: $0) }
        let indices = selection.compactMap(\.eventIndex)
        let tempos = selection.compactMap(\.tempo)
        let deletable = indices.count + tempos.count
        guard deletable > 0 else { return }
        let priorRow = currentRow
        if deletable > 1 {
            selectedRows = []
            selectionAnchor = -1
            model.setCurrentRow(-1)
            currentRow = -1
        }
        session.document.editRawAndTempo(
            chunk: chunkIndex, deleting: indices,
            tempo: TempoEdit(remove: tempos))
        if deletable == 1, rowCount > 0 {
            focusRow(row: max(0, min(priorRow, rowCount - 1)))
        }
    }
}
