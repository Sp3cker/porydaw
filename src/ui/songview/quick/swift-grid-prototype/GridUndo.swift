import Foundation

// Undoable gesture commits for the Swift piano-grid prototype.
//
// Snapshot-pair form: exact restore by construction. The cutover-relevant
// contract is granularity (one command per gesture commit), not the payload
// shape — a later SongDocument cutover deletes the stack and keeps it.
@MainActor
struct GridNoteSnapshot: Equatable {
    let noteId: Int
    let tick: Int
    let duration: Int
    let pitch: Int
    let track: Int
    let velocity: Int
    let ghost: Bool

    init(_ note: GridNote) {
        noteId = note.noteId
        tick = note.tick
        duration = note.duration
        pitch = note.pitch
        track = note.track
        velocity = note.velocity
        ghost = note.ghost
    }

    func materialize() -> GridNote {
        GridNote(
            noteId: noteId, tick: tick, duration: duration, pitch: pitch,
            track: track, velocity: velocity, ghost: ghost)
    }
}

extension GridControllerEvent: Equatable {
    static func == (lhs: GridControllerEvent, rhs: GridControllerEvent) -> Bool {
        lhs.tick == rhs.tick && lhs.track == rhs.track
            && lhs.controller == rhs.controller && lhs.value == rhs.value
    }
}

@MainActor
enum GridEditCommand {
    // Snapshot-pair form: exact restore by construction. The cutover-
    // relevant contract is granularity (one command per gesture commit),
    // not the payload shape.
    case notes(before: [GridNoteSnapshot], after: [GridNoteSnapshot])
    case controllerEvents(before: [GridControllerEvent], after: [GridControllerEvent])

    /// True when both snapshots are identical: pushing is a no-op.
    var isNoop: Bool {
        switch self {
        case .notes(let before, let after):
            before == after
        case .controllerEvents(let before, let after):
            before == after
        }
    }
}

@MainActor
struct GridUndoStack {
    private(set) var undoCount: Int = 0
    private(set) var redoCount: Int = 0
    private var undoStorage: [GridEditCommand] = []
    private var redoStorage: [GridEditCommand] = []

    mutating func push(_ command: GridEditCommand) {
        // No-op if before == after: redundant writes leave revision
        // unchanged and preserve the redo stack.
        guard !command.isNoop else { return }
        undoStorage.append(command)
        redoStorage.removeAll()
        undoCount = undoStorage.count
        redoCount = 0
    }

    /// Nil when undoCount == 0.
    mutating func undo() -> GridEditCommand? {
        guard let command = undoStorage.popLast() else { return nil }
        redoStorage.append(command)
        undoCount = undoStorage.count
        redoCount = redoStorage.count
        return command
    }

    /// Nil when redoCount == 0.
    mutating func redo() -> GridEditCommand? {
        guard let command = redoStorage.popLast() else { return nil }
        undoStorage.append(command)
        undoCount = undoStorage.count
        redoCount = redoStorage.count
        return command
    }

    mutating func removeAll() {
        undoStorage.removeAll()
        redoStorage.removeAll()
        undoCount = 0
        redoCount = 0
    }
}
