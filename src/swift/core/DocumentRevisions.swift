/// Version stamps per document dependency: a consumer memoizes derived state on
/// the stamps it reads, like a React dependency array. Stamps are globally unique.
public struct DocumentRevisions: Equatable, Sendable {
    /// One stamp per MIDI chunk index; structure edits re-index, so they restamp all.
    public private(set) var chunks: [UInt64]
    public private(set) var structure: UInt64 = 1
    public private(set) var tempo: UInt64 = 1
    public private(set) var config: UInt64 = 1
    private var clock: UInt64 = 1

    init(chunkCount: Int) {
        chunks = Array(repeating: 1, count: chunkCount)
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
            chunks = (0..<chunkCount).map { _ in next() }
        } else {
            for change in changes.events { chunks[change.chunk] = next() }
            for end in changes.chunkEnds { chunks[end.chunk] = next() }
        }
        if changes.tempo != nil { tempo = next() }
        if changes.config != nil || changes.fileMetadata != nil { config = next() }
    }
}
