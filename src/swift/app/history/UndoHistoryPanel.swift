import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import QtBridge

/// Owns history commands and a visible-only projection, newest step first.
@MainActor
@QtBridgeable
public final class UndoHistoryPanel {
    public enum Request {
        case undo
        case redo
        case jump(toIndex: Int)
    }

    public enum Event {
        case began
        case failed(String)
        case settled
    }

    public var rows: QListModel<UndoHistoryRow> = QListModel()
    @QtTracked public var currentRow = -1
    @QtTracked public var canJump = false
    @QtIgnored public var context: (() -> (session: DocumentSession?, bankTransitionInFlight: Bool))?
    @QtIgnored public var onEvent: ((Event) -> Void)?

    private weak var projectedHistory: SongHistory?
    private var projectedRevision: Int?
    private var wasVisible = false
    private var jumpInFlight = false

    private struct RowValue {
        let label: String
        let applied: Bool
        let isCurrent: Bool
        let isSaved: Bool
        let isBase: Bool
    }

    public init() {}

    /// Refreshes command availability even when row projection is hidden.
    @QtIgnored
    @discardableResult
    public func refresh(visible: Bool) -> (canUndo: Bool, canRedo: Bool) {
        let current = context?() ?? (session: nil, bankTransitionInFlight: false)
        let available = availability(
            for: current.session, bankTransitionInFlight: current.bankTransitionInFlight)
        publish(\.canJump, available.canJump)
        project(history: current.session?.document.history, visible: visible)
        return (available.canUndo, available.canRedo)
    }

    private func project(history: SongHistory?, visible: Bool) {
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

        let rowCount = history.map { $0.undoCount + 1 } ?? 0
        let values: LazyMapCollection<Range<Int>, RowValue> = (0..<rowCount).lazy.map { row in
            if let history, row == history.undoCount {
                return RowValue(
                    label: history.hasEvictedSteps ? "Oldest kept state" : "Opened",
                    applied: true, isCurrent: history.undoIndex == 0,
                    isSaved: history.baseIsSaved, isBase: true)
            }
            guard let step = history?.step(at: rowCount - 2 - row) else {
                preconditionFailure("A retained history offset must have a step.")
            }
            return RowValue(
                label: step.label, applied: step.applied, isCurrent: step.isCurrent,
                isSaved: step.isSaved, isBase: false)
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

    private func availability(
        for session: DocumentSession?, bankTransitionInFlight: Bool
    ) -> (canUndo: Bool, canRedo: Bool, canJump: Bool) {
        guard let session, !bankTransitionInFlight, !jumpInFlight else {
            return (false, false, false)
        }
        let history = session.document.history
        return (history.canUndo, history.canRedo, true)
    }

    /// Revalidates the selected session and global bank gate before capturing replay.
    @QtIgnored
    public func request(_ request: Request) {
        let current = context?() ?? (session: nil, bankTransitionInFlight: false)
        guard let session = current.session else { return }
        let available = availability(
            for: session, bankTransitionInFlight: current.bankTransitionInFlight)
        let isJump: Bool
        switch request {
        case .undo:
            guard available.canUndo else { return }
            isJump = false
        case .redo:
            guard available.canRedo else { return }
            isJump = false
        case .jump:
            guard available.canJump else { return }
            isJump = true
        }
        if isJump { jumpInFlight = true }
        publish(\.canJump, isJump ? false : available.canJump)
        onEvent?(.began)
        Task { [weak self, session] in
            defer {
                if isJump {
                    self?.jumpInFlight = false
                    self?.onEvent?(.settled)
                }
            }
            do {
                switch request {
                case .undo: _ = try await session.undo()
                case .redo: _ = try await session.redo()
                case .jump(let target): _ = try await session.jump(toIndex: target)
                }
            } catch {
                self?.onEvent?(.failed(String(describing: error)))
                if !isJump { self?.onEvent?(.settled) }
            }
        }
    }

    /// Activates a retained row; the base row rewinds to cursor zero.
    public func activate(row: Int) {
        guard canJump, row >= 0, row < rows.count, row != currentRow else { return }
        request(.jump(toIndex: rows.count - 1 - row))
    }
}
