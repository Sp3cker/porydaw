import SwiftGridDocumentFeed

public struct SgdDocument {
    public struct Note: Equatable {
        public let trackIndex: Int32
        public let key: Int32
        public let onTick: UInt32
        public let durationTicks: UInt32
        public let velocity: Int32

        public init(trackIndex: Int32, key: Int32, onTick: UInt32, durationTicks: UInt32, velocity: Int32) {
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
                    trackIndex: note.trackIndex, key: note.key, onTick: note.onTick,
                    durationTicks: note.durationTicks, velocity: note.velocity))
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
