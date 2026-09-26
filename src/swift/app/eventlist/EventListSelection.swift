import Foundation
import PorydawCore
import PorydawAppEventList

@MainActor
extension EventListPresenter {
    func dispatchIsSelected(row: Int) -> Bool { selectedRows.contains(row) }

    func dispatchSelectRow(row: Int, modifiers: Int) {
        guard model.rows.indices.contains(row) else {
            selectionAnchor = -1
            selectedRows = []
            model.setCurrentRow(-1)
            currentRow = -1
            return
        }
        // Qt::ShiftModifier and Qt::ControlModifier (platform-neutral QML masks).
        let control = modifiers & 0x04000000 != 0
        let shift = modifiers & 0x02000000 != 0
        var next = control ? Set(selectedRows) : []
        if shift {
            let anchor = selectionAnchor >= 0 ? selectionAnchor
                : (currentRow >= 0 ? currentRow : row)
            if !control { next.removeAll() }
            next.formUnion(min(anchor, row)...max(anchor, row))
        } else if control {
            if !next.insert(row).inserted { next.remove(row) }
        } else {
            next = [row]
            selectionAnchor = row
        }
        if control && !shift && selectionAnchor < 0 { selectionAnchor = row }
        selectedRows = next.sorted()
        focusRow(row: row)
    }

    func dispatchSelectAll() {
        selectedRows = Array(model.rows.indices)
        if currentRow < 0, !model.rows.isEmpty { focusRow(row: 0) }
    }

    func dispatchSetVisible(visible: Bool) {
        if visible, !self.visible, let session,
           let selectedChunk = mappedChunk(for: session.selectedTrack, in: session.document),
           selectedChunk != chunkIndex {
            setChunk(index: selectedChunk)
        }
        self.visible = visible
        if !visible {
            clearEditing()
            dismissMenu()
        }
    }

    func dispatchIsCellEditable(row: Int, column: Int) -> Bool {
        model.isCellEditable(row: row, column: column)
    }

    func dispatchCellDisplay(row: Int, column: Int) -> String {
        model.cellText(row: row, column: column)
    }

    func dispatchCellEdit(row: Int, column: Int) -> String {
        model.cellText(row: row, column: column, editing: true)
    }

    func dispatchTickString(row: Int) -> String {
        model.row(at: row).map { String($0.tick) } ?? ""
    }

    func dispatchRowKind(row: Int) -> Int { model.rowKind(row: row) }

    func dispatchHeaderAlignment(column: Int) -> Int {
        [0, 2, 3, 4].contains(column) ? 0x0002 : 0x0001
    }

    func dispatchResizeColumn(column: Int, width: Double) {
        guard (0..<6).contains(column), width.isFinite else { return }
        let next = max(24, width)
        guard savedColumnWidth(column: column) != next else { return }
        var widths = columnWidths
        if widths.count < 6 {
            widths.reserveCapacity(6)
            for index in widths.count..<6 {
                widths.append(defaultColumnWidth(column: index))
            }
        }
        widths[column] = next
        resizedColumns.insert(column)
        columnWidths = widths
    }

    public func toggleFilter(bit: Int) {
        guard bit != 0, bit & 127 == bit else { return }
        filterMask ^= bit
        let checked = EventListMenuKind.categories.filter { filterMask & $0.bit != 0 }
        filterSummary = checked.count == EventListMenuKind.categories.count ? "All events"
            : checked.isEmpty ? "No events"
            : checked.count == 1 ? checked[0].label
            : "\(checked[0].label) +\(checked.count - 1)"
        selectionAnchor = -1
        selectedRows = []
        rebuildFromDocument(preservingCurrentRow: false)
    }

    func dispatchIsLegalDrop(fromRow: Int, gap: Int) -> Bool {
        guard let session, !session.isClosed,
              let source = model.row(at: fromRow)?.eventIndex,
              model.rows.indices.contains(fromRow),
              (0...model.rowCount).contains(gap),
              session.document.rawChunks.indices.contains(chunkIndex) else { return false }
        let preceding = model.rows[..<gap].last(where: { $0.eventIndex != nil })?.eventIndex
        let following = model.rows[gap...].first(where: { $0.eventIndex != nil })?.eventIndex
        let destination: Int
        if let following { destination = following > source ? following - 1 : following }
        else if let preceding { destination = preceding < source ? preceding + 1 : preceding }
        else { return false }
        let events = session.document.rawChunks[chunkIndex].events
        guard events.indices.contains(destination), events[source].tick == events[destination].tick,
              let bounds = session.document.rawMoveBounds(chunk: chunkIndex, index: source) else {
            return false
        }
        return bounds.contains(destination) && destination != source
    }

    func dispatchCommitDrop(fromRow: Int, gap: Int) {
        guard isLegalDrop(fromRow: fromRow, gap: gap), let session,
              let source = model.row(at: fromRow)?.eventIndex else { return }
        let following = model.rows[gap...].first(where: { $0.eventIndex != nil })?.eventIndex
        let preceding = model.rows[..<gap].last(where: { $0.eventIndex != nil })?.eventIndex
        let destination: Int?
        if let following {
            destination = following > source ? following - 1 : following
        } else if let preceding {
            destination = preceding < source ? preceding + 1 : preceding
        } else {
            destination = nil
        }
        guard let destination else { return }
        session.document.moveRawEvent(chunk: chunkIndex, index: source, to: destination)
        selectedRows = []
        selectionAnchor = -1
        if let row = model.rows.firstIndex(where: { $0.eventIndex == destination }) {
            focusRow(row: row)
            selectedRows = [row]
        }
    }

    func moveDestination(delta: Int) -> Int? {
        guard visible, !editing, let session, !session.isClosed,
              let source = model.row(at: currentRow)?.eventIndex,
              let adjacent = model.row(at: currentRow + delta),
              let destination = adjacent.eventIndex,
              session.document.rawChunks.indices.contains(chunkIndex) else { return nil }
        let events = session.document.rawChunks[chunkIndex].events
        guard events.indices.contains(source), events.indices.contains(destination),
              events[source].tick == events[destination].tick,
              let bounds = session.document.rawMoveBounds(chunk: chunkIndex, index: source),
              bounds.contains(destination), destination != source else { return nil }
        return destination
    }

    func moveEvent(delta: Int) {
        guard let destination = moveDestination(delta: delta), let session,
              let source = model.row(at: currentRow)?.eventIndex else { return }
        session.document.moveRawEvent(chunk: chunkIndex, index: source, to: destination)
        if let row = model.rows.firstIndex(where: { $0.eventIndex == destination }) {
            focusRow(row: row)
            selectedRows = [row]
            selectionAnchor = row
        }
    }
}
