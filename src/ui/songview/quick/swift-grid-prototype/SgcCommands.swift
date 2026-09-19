import SwiftGridCommands

// Swift mirror of the sgc_ intent vocabulary (spec.md §2). Values are plain
// Sendable copies; the C command is built at submission and never retained.

public enum SgcIntent: Sendable {
    // Document intents (undoable; one intent = one undo entry).
    case noteAdd(track: Int32, key: Int32, onTick: UInt32, durationTicks: UInt32, velocity: Int32)
    case noteMove(noteId: UInt64, deltaTicks: Int64, deltaKeys: Int32)
    case noteResize(noteId: UInt64, durationTicks: UInt32)
    case noteDelete(noteIds: [UInt64])
    // Batch forms: one gesture's move/resize as one intent = one undo entry
    // (spec §5, S-3). noteResizeBatch carries a uniform duration DELTA
    // mirroring production resizeNotes, not an absolute duration.
    case noteMoveBatch(noteIds: [UInt64], deltaTicks: Int64, deltaKeys: Int32)
    case noteResizeBatch(noteIds: [UInt64], dDuration: Int64)
    case trackAdd(voice: Int32)
    case trackDuplicate(track: Int32)
    case trackDelete(track: Int32)
    case trackReorder(track: Int32, newIndex: Int32)
    case trackRename(track: Int32, name: String)
    // Session intents (no undo entries).
    case selectionSetNotes(noteIds: [UInt64])
    case selectionClear
    case trackMute(track: Int32, on: Bool)
    case trackSolo(track: Int32, on: Bool)
}

public enum SgcResult: Sendable, Equatable {
    case executed
    case rejectedInvalid
    case rejectedUnavailable
}

public struct SgcOutcome: Sendable, Equatable {
    public let result: SgcResult
    // noteAdd only: the minted NoteId token of the new note; 0 otherwise.
    public let noteId: UInt64

    public init(result: SgcResult, noteId: UInt64 = 0) {
        self.result = result
        self.noteId = noteId
    }
}

// Submission endpoint for one document feed id. GUI-thread only, like the
// C++ executor it routes to.
public struct SgcCommandPipe: Sendable {
    public let documentId: UInt64

    public init(documentId: UInt64) {
        precondition(documentId != 0)
        self.documentId = documentId
    }

    @discardableResult
    public func submit(_ intent: SgcIntent) -> SgcOutcome {
        var outcome = SwiftGridCommands.SgcOutcome()
        let result = withCommand(for: intent) { command in
            sgc_submit(command, &outcome)
        }
        return SgcOutcome(result: Self.result(result), noteId: outcome.noteId)
    }
}

// Gesture→intent helpers (spec.md §5): the grid's commit points speak in
// gesture terms; each helper maps to the closed §2 vocabulary. Document
// intents are undoable (one intent = one undo entry); selection intents
// carry the complete desired set computed from sgs_ state.
public extension SgcCommandPipe {
    // Draw commit: adds the note and returns the outcome carrying the
    // minted NoteId token (0 when rejected).
    @discardableResult
    func addDrawnNote(
        track: Int32, key: Int32, onTick: UInt32,
        durationTicks: UInt32, velocity: Int32
    ) -> SgcOutcome {
        submit(.noteAdd(
            track: track, key: key, onTick: onTick,
            durationTicks: durationTicks, velocity: velocity))
    }
    // Move commit: the whole selection as one batch intent = one undo
    // entry (SGC_NOTE_MOVE_BATCH, spec §5).
    @discardableResult
    func moveNotes(noteIds: [UInt64], deltaTicks: Int64, deltaKeys: Int32) -> SgcOutcome {
        submit(.noteMoveBatch(
            noteIds: noteIds, deltaTicks: deltaTicks, deltaKeys: deltaKeys))
    }

    // Trailing-edge resize commit: the whole selection as one batch intent
    // = one undo entry. dDuration is the uniform duration delta mirroring
    // production resizeNotes.
    @discardableResult
    func resizeNotes(noteIds: [UInt64], dDuration: Int64) -> SgcOutcome {
        submit(.noteResizeBatch(noteIds: noteIds, dDuration: dDuration))
    }

    // Delete commit: the whole selection as one batch intent = one undo
    // entry.
    @discardableResult
    func deleteNotes(_ noteIds: [UInt64]) -> SgcOutcome {
        submit(.noteDelete(noteIds: noteIds))
    }

    // Selection commit: the complete desired set (empty → clear).
    @discardableResult
    func selectNotes(_ noteIds: [UInt64]) -> SgcOutcome {
        noteIds.isEmpty
            ? submit(.selectionClear)
            : submit(.selectionSetNotes(noteIds: noteIds))
    }
}

private extension SgcCommandPipe {
    static func result(_ raw: SwiftGridCommands.SgcResult) -> SgcResult {
        // The imported C enum exposes rawValue only (no case names), so the
        // mapping is by raw value, order-frozen in command_feed.h.
        switch raw.rawValue {
        case 0: return .executed
        case 1: return .rejectedInvalid
        case 2: return .rejectedUnavailable
        default: preconditionFailure("unknown SgcResult raw value")
        }
    }

    // Raw values of the C SgcIntent enumerators (command_feed.h order). The
    // imported C enum has no case names; construction goes through rawValue.
    // If command_feed.h ever reorders, the swiftcommands matrix fails loudly
    // rather than silently crossing intents.
    private enum RawIntent: UInt32 {
        case noteAdd = 0, noteMove, noteResize, noteDelete
        case trackAdd, trackDuplicate, trackDelete, trackReorder, trackRename
        case selectionSetNotes, selectionClear, trackMute, trackSolo
        case noteMoveBatch = 13, noteResizeBatch
    }
    private static func rawIntent(_ raw: RawIntent) -> SwiftGridCommands.SgcIntent {
        // The imported initializer is non-failable: an out-of-range raw value
        // still constructs, so RawIntent's order freeze is what carries safety.
        SwiftGridCommands.SgcIntent(rawValue: raw.rawValue)
    }

    // Builds the C command for intent, then runs body while any borrowed
    // array/string storage is still alive.
    func withCommand(
        for intent: SgcIntent,
        _ body: (UnsafePointer<SwiftGridCommands.SgcIntentCommand>) -> SwiftGridCommands.SgcResult
    ) -> SwiftGridCommands.SgcResult {
        var command = SwiftGridCommands.SgcIntentCommand()
        command.documentId = documentId
        switch intent {
        case let .noteAdd(track, key, onTick, durationTicks, velocity):
            command.intent = Self.rawIntent(.noteAdd)
            command.payload.noteAdd = SwiftGridCommands.SgcNoteAdd(
                trackIndex: track, key: key, onTick: onTick,
                durationTicks: durationTicks, velocity: velocity)
            return body(&command)
        case let .noteMove(noteId, deltaTicks, deltaKeys):
            command.intent = Self.rawIntent(.noteMove)
            command.payload.noteMove = SwiftGridCommands.SgcNoteMove(
                noteId: noteId, deltaTicks: deltaTicks, deltaKeys: deltaKeys)
            return body(&command)
        case let .noteResize(noteId, durationTicks):
            command.intent = Self.rawIntent(.noteResize)
            command.payload.noteResize = SwiftGridCommands.SgcNoteResize(
                noteId: noteId, durationTicks: durationTicks)
            return body(&command)
        case let .noteDelete(noteIds):
            command.intent = Self.rawIntent(.noteDelete)
            return noteIds.withUnsafeBufferPointer { buffer in
                command.payload.noteList = SwiftGridCommands.SgcNoteList(
                    noteIds: buffer.baseAddress, count: Int32(buffer.count))
                return body(&command)
            }
        case let .noteMoveBatch(noteIds, deltaTicks, deltaKeys):
            command.intent = Self.rawIntent(.noteMoveBatch)
            return noteIds.withUnsafeBufferPointer { buffer in
                command.payload.noteMoveBatch = SwiftGridCommands.SgcNoteMoveBatch(
                    noteIds: buffer.baseAddress, count: Int32(buffer.count),
                    deltaTicks: deltaTicks, deltaKeys: deltaKeys)
                return body(&command)
            }
        case let .noteResizeBatch(noteIds, dDuration):
            command.intent = Self.rawIntent(.noteResizeBatch)
            return noteIds.withUnsafeBufferPointer { buffer in
                command.payload.noteResizeBatch = SwiftGridCommands.SgcNoteResizeBatch(
                    noteIds: buffer.baseAddress, count: Int32(buffer.count),
                    dDuration: dDuration)
                return body(&command)
            }
        case let .trackAdd(voice):
            command.intent = Self.rawIntent(.trackAdd)
            command.payload.trackAdd = SwiftGridCommands.SgcTrackAdd(voice: voice)
            return body(&command)
        case let .trackDuplicate(track):
            command.intent = Self.rawIntent(.trackDuplicate)
            command.payload.trackIndex = SwiftGridCommands.SgcTrackIndex(trackIndex: track)
            return body(&command)
        case let .trackDelete(track):
            command.intent = Self.rawIntent(.trackDelete)
            command.payload.trackIndex = SwiftGridCommands.SgcTrackIndex(trackIndex: track)
            return body(&command)
        case let .trackReorder(track, newIndex):
            command.intent = Self.rawIntent(.trackReorder)
            command.payload.trackReorder = SwiftGridCommands.SgcTrackReorder(
                trackIndex: track, newIndex: newIndex)
            return body(&command)
        case let .trackRename(track, name):
            command.intent = Self.rawIntent(.trackRename)
            return name.withCString { text in
                command.payload.trackRename = SwiftGridCommands.SgcTrackRename(
                    trackIndex: track, name: text, nameLength: Int32(name.utf8.count))
                return body(&command)
            }
        case let .selectionSetNotes(noteIds):
            command.intent = Self.rawIntent(.selectionSetNotes)
            return noteIds.withUnsafeBufferPointer { buffer in
                command.payload.noteList = SwiftGridCommands.SgcNoteList(
                    noteIds: buffer.baseAddress, count: Int32(buffer.count))
                return body(&command)
            }
        case .selectionClear:
            command.intent = Self.rawIntent(.selectionClear)
            return body(&command)
        case let .trackMute(track, on):
            command.intent = Self.rawIntent(.trackMute)
            command.payload.trackFlag = SwiftGridCommands.SgcTrackFlag(
                trackIndex: track, on: on ? 1 : 0)
            return body(&command)
        case let .trackSolo(track, on):
            command.intent = Self.rawIntent(.trackSolo)
            command.payload.trackFlag = SwiftGridCommands.SgcTrackFlag(
                trackIndex: track, on: on ? 1 : 0)
            return body(&command)
        }
    }
}
