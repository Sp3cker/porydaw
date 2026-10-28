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
    @QtIgnored public var context: (() -> (song: DocumentSession?, voicegroup: VoicegroupSession?))?
    @QtIgnored public var onEvent: ((Event) -> Void)?

    private weak var projectedHistory: SongHistory?
    private weak var projectedVoicegroupHistory: VoicegroupHistory?
    private var projectedRevision: Int?
    private var wasVisible = false
    private var replayingOwners: Set<ObjectIdentifier> = []

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
        let current = context?() ?? (song: nil, voicegroup: nil)
        let available = availability(song: current.song, voicegroup: current.voicegroup)
        publish(\.canJump, available.canJump)
        project(history: current.song?.document.history, voicegroup: current.voicegroup?.history, visible: visible)
        return (available.canUndo, available.canRedo)
    }

    private func project(history: SongHistory?, voicegroup: VoicegroupHistory?, visible: Bool) {
        guard visible else {
            wasVisible = false
            return
        }
        let needsProjection =
            !wasVisible || projectedHistory !== history
            || projectedVoicegroupHistory !== voicegroup
            || projectedRevision != (voicegroup?.revision ?? history?.revision)
        wasVisible = true
        guard needsProjection else { return }
        projectedHistory = history
        projectedVoicegroupHistory = voicegroup
        projectedRevision = voicegroup?.revision ?? history?.revision

        let count = voicegroup?.undoCount ?? history?.undoCount
        let index = voicegroup?.undoIndex ?? history?.undoIndex
        let rowCount = count.map { $0 + 1 } ?? 0
        let values: LazyMapCollection<Range<Int>, RowValue> = (0..<rowCount).lazy.map { row in
            if row == count {
                return RowValue(
                    label: (voicegroup?.hasEvictedSteps ?? history?.hasEvictedSteps ?? false)
                        ? "Oldest kept state" : "Opened",
                    applied: true, isCurrent: index == 0,
                    isSaved: voicegroup?.baseIsSaved ?? history?.baseIsSaved ?? false, isBase: true)
            }
            guard
                let step = voicegroup?.step(at: rowCount - 2 - row)
                    ?? history?.step(at: rowCount - 2 - row)
            else {
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
        let current = count.map { $0 - (index ?? 0) } ?? -1
        publish(\.currentRow, current)
    }

    private func availability(
        song: DocumentSession?, voicegroup: VoicegroupSession?
    ) -> (canUndo: Bool, canRedo: Bool, canJump: Bool) {
        if let voicegroup {
            guard !voicegroup.isBusy, !replayingOwners.contains(ObjectIdentifier(voicegroup)) else {
                return (false, false, false)
            }
            return (voicegroup.history.canUndo, voicegroup.history.canRedo, true)
        }
        guard let song, !song.document.history.bindingTransitionInFlight,
            !replayingOwners.contains(ObjectIdentifier(song))
        else {
            return (false, false, false)
        }
        return (song.document.history.canUndo, song.document.history.canRedo, true)
    }

    /// Captures only the selected owner's replay; unrelated histories remain available.
    @QtIgnored
    public func request(_ request: Request) {
        let current = context?() ?? (song: nil, voicegroup: nil)
        guard current.song != nil || current.voicegroup != nil else { return }
        let available = availability(song: current.song, voicegroup: current.voicegroup)
        switch request {
        case .undo:
            guard available.canUndo else { return }
        case .redo:
            guard available.canRedo else { return }
        case .jump:
            guard available.canJump else { return }
        }
        let identity: ObjectIdentifier
        if let voicegroup = current.voicegroup {
            identity = ObjectIdentifier(voicegroup)
        } else if let song = current.song {
            identity = ObjectIdentifier(song)
        } else {
            return
        }
        replayingOwners.insert(identity)
        publish(\.canJump, false)
        onEvent?(.began)
        Task { [weak self] in
            defer {
                self?.replayingOwners.remove(identity)
                self?.onEvent?(.settled)
            }
            do {
                if let voicegroup = current.voicegroup {
                    switch request {
                    case .undo: _ = try await voicegroup.undo()
                    case .redo: _ = try await voicegroup.redo()
                    case .jump(let target): _ = try await voicegroup.jump(toIndex: target)
                    }
                } else if let song = current.song {
                    switch request {
                    case .undo: _ = try await song.undo()
                    case .redo: _ = try await song.redo()
                    case .jump(let target): _ = try await song.jump(toIndex: target)
                    }
                }
            } catch {
                self?.onEvent?(.failed(String(describing: error)))
            }
        }
    }

    /// Activates a retained row; the base row rewinds to cursor zero.
    public func activate(row: Int) {
        guard canJump, row >= 0, row < rows.count, row != currentRow else { return }
        request(.jump(toIndex: rows.count - 1 - row))
    }
}
