import SwiftGridDocumentFeed
import SwiftGridSessionFeed

public struct SgdDocument {
    public struct Note: Equatable {
        public let noteId: UInt64
        public let trackIndex: Int32
        public let key: Int32
        public let onTick: UInt32
        public let durationTicks: UInt32
        public let velocity: Int32

        public init(noteId: UInt64, trackIndex: Int32, key: Int32, onTick: UInt32,
                    durationTicks: UInt32, velocity: Int32) {
            self.noteId = noteId
            self.trackIndex = trackIndex
            self.key = key
            self.onTick = onTick
            self.durationTicks = durationTicks
            self.velocity = velocity
        }
    }

    public struct TimeSignature: Equatable {
        public let startTick: UInt32
        public let numerator: UInt8
        public let denomPow2: UInt8

        public init(startTick: UInt32, numerator: UInt8, denomPow2: UInt8) {
            self.startTick = startTick
            self.numerator = numerator
            self.denomPow2 = denomPow2
        }
    }

    public let documentId: UInt64
    public let revision: UInt64
    public let ticksPerBeat: Int32
    public let trackCount: Int32
    public let notes: [Note]
    public let signatures: [TimeSignature]

    public init(documentId: UInt64, revision: UInt64, ticksPerBeat: Int32, trackCount: Int32,
                notes: [Note], signatures: [TimeSignature]) {
        self.documentId = documentId
        self.revision = revision
        self.ticksPerBeat = ticksPerBeat
        self.trackCount = trackCount
        self.notes = notes
        self.signatures = signatures
    }
}

// Complete session state pushed by the host (spec §3). Every push is
// authoritative: the receiver replaces its snapshot wholesale and retains no
// selection state between pushes. Note ids are raw NoteId tokens valid only
// against the document that minted them.
public struct SgsSession: Equatable, Sendable {
    public struct Lane: Equatable, Sendable {
        public let track: Int32
        public let controller: UInt8

        public init(track: Int32, controller: UInt8) {
            self.track = track
            self.controller = controller
        }
    }

    public struct TimeSelection: Equatable, Sendable {
        public let startTick: UInt32
        public let endTick: UInt32
        public let scope: Int32
        public let lanes: [Lane]
        public let tempo: Bool

        public init(startTick: UInt32, endTick: UInt32, scope: Int32, lanes: [Lane], tempo: Bool) {
            self.startTick = startTick
            self.endTick = endTick
            self.scope = scope
            self.lanes = lanes
            self.tempo = tempo
        }

        public var active: Bool { endTick > startTick }
    }

    public let sessionId: UInt64
    public let revision: UInt64
    public let primaryTrack: Int32
    public let trackScope: UInt32
    public let selectedNoteIds: [UInt64]
    public let timeSelection: TimeSelection
    public let muteMask: UInt32
    public let soloMask: UInt32

    public init(sessionId: UInt64, revision: UInt64, primaryTrack: Int32, trackScope: UInt32,
                selectedNoteIds: [UInt64], timeSelection: TimeSelection, muteMask: UInt32,
                soloMask: UInt32) {
        self.sessionId = sessionId
        self.revision = revision
        self.primaryTrack = primaryTrack
        self.trackScope = trackScope
        self.selectedNoteIds = selectedNoteIds
        self.timeSelection = timeSelection
        self.muteMask = muteMask
        self.soloMask = soloMask
    }
}

@MainActor
public final class DocumentFeed {
    public let documentId: UInt64
    public private(set) var appliedRevision: UInt64?
    public private(set) var document: SgdDocument?
    public var onDocument: ((SgdDocument) -> Void)?
    private var connected = false

    public init(documentId: UInt64) {
        precondition(documentId != 0)
        self.documentId = documentId
    }

    public func connect() -> Bool {
        guard !connected else { return false }
        connected = sgd_set_delivery(
            documentId,
            { header, notes, signatures, context in
                MainActor.assumeIsolated {
                    let receiver = Unmanaged<DocumentFeed>.fromOpaque(context!).takeUnretainedValue()
                    _ = receiver.apply(header: header!.pointee, notes: notes, signatures: signatures)
                }
            },
            Unmanaged.passUnretained(self).toOpaque())
        return connected
    }

    public func disconnect() {
        // A receiver whose binding failed must not clear the actual recipient.
        guard connected else { return }
        sgd_clear_delivery(documentId)
        connected = false
    }

    isolated deinit {
        disconnect()
    }

    @discardableResult
    public func apply(header: SgdDocumentHeader, notes: UnsafePointer<SgdNote>?,
                      signatures: UnsafePointer<SgdTimeSignature>?) -> Bool {
        guard header.documentId == documentId else { return false }
        if let appliedRevision, header.revision <= appliedRevision { return false }
        precondition(header.noteCount >= 0 && header.timeSignatureCount >= 0)
        precondition(header.noteCount == 0 || notes != nil)
        precondition(header.timeSignatureCount == 0 || signatures != nil)
        // C storage lives only for this synchronous call. Spans never escape;
        // each accepted array initializes its owned storage exactly once.
        let copiedNotes = [SgdDocument.Note](capacity: Int(header.noteCount)) { output in
            let buffer = UnsafeBufferPointer(start: notes, count: Int(header.noteCount))
            let borrowed = Span(_unsafeElements: buffer)
            for index in borrowed.indices {
                let note = borrowed[index]
                output.append(SgdDocument.Note(
                    noteId: note.noteId, trackIndex: note.trackIndex, key: note.key,
                    onTick: note.onTick, durationTicks: note.durationTicks,
                    velocity: note.velocity))
            }
        }
        let copiedSignatures = [SgdDocument.TimeSignature](capacity: Int(header.timeSignatureCount)) { output in
            let buffer = UnsafeBufferPointer(start: signatures, count: Int(header.timeSignatureCount))
            let borrowed = Span(_unsafeElements: buffer)
            for index in borrowed.indices {
                let signature = borrowed[index]
                output.append(SgdDocument.TimeSignature(
                    startTick: signature.startTick, numerator: signature.numerator,
                    denomPow2: signature.denomPow2))
            }
        }
        let snapshot = SgdDocument(
            documentId: header.documentId, revision: header.revision,
            ticksPerBeat: header.ticksPerBeat, trackCount: header.trackCount,
            notes: copiedNotes, signatures: copiedSignatures)
        appliedRevision = header.revision
        document = snapshot
        onDocument?(snapshot)
        return true
    }
}

@MainActor
public final class SessionFeed {
    public let sessionId: UInt64
    public private(set) var appliedRevision: UInt64?
    public private(set) var session: SgsSession?
    public var onSession: ((SgsSession) -> Void)?
    private var connected = false

    public init(sessionId: UInt64) {
        precondition(sessionId != 0)
        self.sessionId = sessionId
    }

    public func connect() -> Bool {
        guard !connected else { return false }
        connected = sgs_set_delivery(
            sessionId,
            { state, noteIds, lanes, context in
                MainActor.assumeIsolated {
                    let receiver = Unmanaged<SessionFeed>.fromOpaque(context!).takeUnretainedValue()
                    _ = receiver.apply(state: state!.pointee, noteIds: noteIds, lanes: lanes)
                }
            },
            Unmanaged.passUnretained(self).toOpaque())
        return connected
    }

    public func disconnect() {
        // A receiver whose binding failed must not clear the actual recipient.
        guard connected else { return }
        sgs_clear_delivery(sessionId)
        connected = false
    }

    isolated deinit {
        disconnect()
    }

    @discardableResult
    public func apply(state: SgsSessionState, noteIds: UnsafePointer<UInt64>?,
                      lanes: UnsafePointer<SgsLane>?) -> Bool {
        guard state.sessionId == sessionId else { return false }
        if let appliedRevision, state.revision <= appliedRevision { return false }
        precondition(state.selectedNoteCount >= 0 && state.timeSelection.laneCount >= 0)
        precondition(state.selectedNoteCount == 0 || noteIds != nil)
        precondition(state.timeSelection.laneCount == 0 || lanes != nil)
        // C storage lives only for this synchronous call. Spans never escape;
        // each accepted array initializes its owned storage exactly once.
        let copiedIds = [UInt64](capacity: Int(state.selectedNoteCount)) { output in
            let buffer = UnsafeBufferPointer(start: noteIds, count: Int(state.selectedNoteCount))
            let borrowed = Span(_unsafeElements: buffer)
            for index in borrowed.indices {
                output.append(borrowed[index])
            }
        }
        let copiedLanes = [SgsSession.Lane](capacity: Int(state.timeSelection.laneCount)) { output in
            let buffer = UnsafeBufferPointer(start: lanes, count: Int(state.timeSelection.laneCount))
            let borrowed = Span(_unsafeElements: buffer)
            for index in borrowed.indices {
                let lane = borrowed[index]
                output.append(SgsSession.Lane(track: lane.track, controller: lane.controller))
            }
        }
        let snapshot = SgsSession(
            sessionId: state.sessionId, revision: state.revision,
            primaryTrack: state.primaryTrack, trackScope: state.trackScope,
            selectedNoteIds: copiedIds,
            timeSelection: SgsSession.TimeSelection(
                startTick: state.timeSelection.startTick, endTick: state.timeSelection.endTick,
                scope: state.timeSelection.scope, lanes: copiedLanes,
                tempo: state.timeSelection.tempo != 0),
            muteMask: state.muteMask, soloMask: state.soloMask)
        appliedRevision = state.revision
        session = snapshot
        onSession?(snapshot)
        return true
    }
}
