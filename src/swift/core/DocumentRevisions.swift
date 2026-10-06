/// Stamps for one chunk's content, split by what consumers publish: a note move
/// advances `notes` only, so lane and voice presenters skip their rebuild.
public struct ChunkRevisions: Equatable, Sendable {
    public internal(set) var notes: UInt64
    public internal(set) var lanes: UInt64
    public internal(set) var voices: UInt64
    /// Names, markers, text, sysex and aftertouch.
    public internal(set) var meta: UInt64

    /// Any event edit. Projections carry raw event offsets, so anything that
    /// reads or edits by offset keys on this, not on one kind.
    public var events: UInt64 { max(max(notes, lanes), max(voices, meta)) }

    init(_ stamp: UInt64) {
        notes = stamp
        lanes = stamp
        voices = stamp
        meta = stamp
    }
}

/// Version stamps per document dependency: a consumer memoizes derived state on
/// the stamps it reads, like a React dependency array. Stamps are globally unique.
public struct DocumentRevisions: Equatable, Sendable {
    /// Indexed by MIDI chunk; structure edits re-index, so they restamp every chunk.
    public private(set) var chunks: [ChunkRevisions]
    /// Same kinds, advanced when any chunk's did: for readers spanning all tracks.
    public private(set) var all = ChunkRevisions(1)
    public private(set) var structure: UInt64 = 1
    /// Tempo map, chunk end ticks, division: anything that moves the time axis.
    public private(set) var time: UInt64 = 1
    public private(set) var config: UInt64 = 1
    private var clock: UInt64 = 1

    init(chunkCount: Int) {
        chunks = Array(repeating: ChunkRevisions(1), count: chunkCount)
    }

    private mutating func next() -> UInt64 {
        clock += 1
        return clock
    }

    mutating func advance(for changes: DocumentChangeSet, chunkCount: Int) {
        if !changes.chunkInsertions.isEmpty || !changes.chunkRemovals.isEmpty
            || !changes.chunkMoves.isEmpty
        {
            structure = next()
            chunks = (0..<chunkCount).map { _ in ChunkRevisions(next()) }
            all = ChunkRevisions(next())
        } else {
            for change in changes.events { stamp(change) }
        }
        if changes.tempo != nil || !changes.chunkEnds.isEmpty || changes.fileMetadata != nil {
            time = next()
        }
        if changes.config != nil { config = next() }
    }

    private mutating func stamp(_ change: EventChange) {
        let chunk = change.chunk
        switch change.event.payload {
        case let .channel(status, _, _):
            switch status >> 4 {
            case 0x8, 0x9:
                chunks[chunk].notes = next()
                all.notes = chunks[chunk].notes
            case 0xB, 0xE:
                chunks[chunk].lanes = next()
                all.lanes = chunks[chunk].lanes
            case 0xC:
                chunks[chunk].voices = next()
                all.voices = chunks[chunk].voices
            default:
                chunks[chunk].meta = next()
                all.meta = chunks[chunk].meta
            }
        case .meta, .systemExclusive:
            chunks[chunk].meta = next()
            all.meta = chunks[chunk].meta
        }
    }
}
