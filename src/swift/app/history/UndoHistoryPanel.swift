import PorydawAppPresentation
import PorydawCore
import QtBridge

/// A visible-only projection of the selected song's history, newest step first.
@MainActor
@QtBridgeable
public final class UndoHistoryPanel {
    public var rows: QListModel<UndoHistoryRow> = QListModel()
    @QtTracked public var currentRow = -1
    @QtTracked public var canJump = false
    @QtIgnored var onJumpRequested: ((Int) -> Void)?

    private weak var projectedHistory: SongHistory?
    private var projectedRevision: Int?
    private var wasVisible = false

    private struct RowValue {
        let label: String
        let applied: Bool
        let isCurrent: Bool
        let isSaved: Bool
        let isBase: Bool
    }

    init() {}

    func sync(history: SongHistory?, visible: Bool) {
        guard visible else {
            wasVisible = false
            return
        }
        let needsProjection =
            !wasVisible || projectedHistory !== history
            || projectedRevision != history?.revision
        wasVisible = true
        guard needsProjection else { return }
        projectedHistory = history
        projectedRevision = history?.revision

        var values: [RowValue] = []
        if let history {
            values.reserveCapacity(history.undoCount + 1)
            for offset in stride(from: history.undoCount - 1, through: 0, by: -1) {
                guard let step = history.step(at: offset) else {
                    preconditionFailure("A retained history offset must have a step.")
                }
                values.append(
                    RowValue(
                        label: step.label, applied: step.applied, isCurrent: step.isCurrent,
                        isSaved: step.isSaved, isBase: false))
            }
            values.append(
                RowValue(
                    label: history.hasEvictedSteps ? "Oldest kept state" : "Opened",
                    applied: true, isCurrent: history.undoIndex == 0,
                    isSaved: history.baseIsSaved, isBase: true))
        }
        syncRetained(
            rows, values,
            make: { value in
                UndoHistoryRow(
                    label: value.label, applied: value.applied, isCurrent: value.isCurrent,
                    isSaved: value.isSaved, isBase: value.isBase)
            },
            update: { row, value in
                guard
                    row.label != value.label || row.applied != value.applied
                        || row.isCurrent != value.isCurrent || row.isSaved != value.isSaved
                        || row.isBase != value.isBase
                else { return false }
                row.label = value.label
                row.applied = value.applied
                row.isCurrent = value.isCurrent
                row.isSaved = value.isSaved
                row.isBase = value.isBase
                return true
            })
        let current = history.map { $0.undoCount - $0.undoIndex } ?? -1
        publish(\.currentRow, current)
    }

    /// Activates a retained row; the base row rewinds to cursor zero.
    public func activate(row: Int) {
        guard canJump, row >= 0, row < rows.count, row != currentRow else { return }
        onJumpRequested?(rows.count - 1 - row)
    }
}
