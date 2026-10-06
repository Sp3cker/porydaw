/// Semantic content dependencies affected by an accepted document transition.
public struct DocumentEditEffectKinds: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let notes = Self(rawValue: 1 << 0)
    public static let lanes = Self(rawValue: 1 << 1)
    public static let voices = Self(rawValue: 1 << 2)
    public static let otherEvents = Self(rawValue: 1 << 3)
    public static let trackNames = Self(rawValue: 1 << 4)
    public static let timeDomain = Self(rawValue: 1 << 5)
    public static let structure = Self(rawValue: 1 << 6)
    public static let configuration = Self(rawValue: 1 << 7)
}

/// A transition's semantic impact and exact touched chunks, inline for one chunk.
public struct DocumentEditEffects: Equatable, Sendable {
    public private(set) var flags: DocumentEditEffectKinds = []
    private var firstChunk: Int?
    private var remainingChunks: [Int] = []

    /// Creates an empty summary for notifications without document edits.
    public init() {}

    /// Whether this transition affects the given nonnegative MIDI chunk index.
    public func affects(chunk: Int) -> Bool {
        chunk >= 0
            && (flags.contains(.structure) || firstChunk == chunk || remainingChunks.contains(chunk))
    }

    /// Whether any chunk content or its structural identity was affected.
    public var affectsAnyChunk: Bool {
        flags.contains(.structure) || firstChunk != nil
    }

    /// Accumulates another transition without losing restored or remapped content.
    public mutating func formUnion(_ other: DocumentEditEffects) {
        flags.formUnion(other.flags)
        if flags.contains(.structure) {
            firstChunk = nil
            remainingChunks.removeAll(keepingCapacity: true)
            return
        }
        if let chunk = other.firstChunk { include(chunk: chunk) }
        for chunk in other.remainingChunks { include(chunk: chunk) }
    }

    internal mutating func include(_ kinds: DocumentEditEffectKinds) {
        flags.formUnion(kinds)
        if flags.contains(.structure) {
            firstChunk = nil
            remainingChunks.removeAll(keepingCapacity: true)
        }
    }

    internal mutating func include(chunk: Int) {
        precondition(chunk >= 0)
        guard !flags.contains(.structure) else { return }
        guard let first = firstChunk else {
            firstChunk = chunk
            return
        }
        guard chunk != first else { return }
        if chunk < first {
            remainingChunks.insert(first, at: 0)
            firstChunk = chunk
        } else {
            let offset = remainingChunks.firstIndex(where: { $0 >= chunk }) ?? remainingChunks.count
            if offset == remainingChunks.count || remainingChunks[offset] != chunk {
                remainingChunks.insert(chunk, at: offset)
            }
        }
    }

    internal struct ChunkContentExtent: Equatable {
        var channel: Tick?
        var other: Tick?
        var name: Tick?
    }

    internal struct ContentExtents: Equatable {
        var first: ChunkContentExtent?
        var remaining: [ChunkContentExtent] = []
    }

    /// Separate contributor classes prevent ignored metadata from masking music.
    internal func contentExtents(in file: borrowing MidiFile) -> ContentExtents {
        var extents = ContentExtents()
        if let chunk = firstChunk {
            let sourceEvents = file.chunks[chunk].events
            extents.first = contentExtent(in: sourceEvents.span)
        }
        for chunk in remainingChunks {
            let sourceEvents = file.chunks[chunk].events
            extents.remaining.append(contentExtent(in: sourceEvents.span))
        }
        return extents
    }

    private func contentExtent(in events: borrowing Span<MidiEvent>) -> ChunkContentExtent {
        let needsChannel = !flags.intersection([.notes, .lanes, .voices, .otherEvents]).isEmpty
        let needsOther = flags.contains(.otherEvents)
        let needsName = flags.contains(.trackNames)
        var extent = ChunkContentExtent()
        for index in events.indices.reversed() {
            let event = events[index]
            switch event.payload {
            case let .channel(status, _, _):
                if needsChannel, extent.channel == nil, (0x8...0xE).contains(status >> 4) {
                    extent.channel = event.tick
                }
            case .systemExclusive:
                if needsOther, extent.other == nil { extent.other = event.tick }
            case let .meta(type, data):
                if type == 0x03 {
                    if needsName, extent.name == nil { extent.name = event.tick }
                } else if needsOther, extent.other == nil,
                    !(type == 0x51 && data.count == 3),
                    !(type == 0x58 && data.count >= 2),
                    !(type == 0x20 && !data.isEmpty)
                {
                    if !(0x01...0x07).contains(type)
                        || data.prefix(32).contains(where: { !Self.isTextWhitespace($0) })
                    {
                        extent.other = event.tick
                    }
                }
            }
            if (!needsChannel || extent.channel != nil)
                && (!needsOther || extent.other != nil) && (!needsName || extent.name != nil)
            {
                break
            }
        }
        return extent
    }

    private static func isTextWhitespace(_ byte: UInt8) -> Bool {
        (9...13).contains(byte) || byte == 32 || byte == 133 || byte == 160
    }
}

internal enum EventChange: Sendable {
    case insert(EventInsertion)
    case remove(EventRemoval)
}

internal struct EventInsertion: Sendable {
    let chunk: Int
    let offset: Int
    let event: MidiEvent
}

internal struct EventRemoval: Sendable {
    let chunk: Int
    let offset: Int
    let event: MidiEvent
}

internal struct ChunkInsertion: Sendable {
    let offset: Int
    let chunk: MidiChunk
}

internal struct ChunkRemoval: Sendable {
    let offset: Int
    let chunk: MidiChunk
}

internal struct ChunkMove: Sendable {
    let from: Int
    let to: Int
}

internal struct ChunkEndChange: Sendable {
    let chunk: Int
    let before: Tick
    var after: Tick
}

internal struct FileMetadataChange: Sendable {
    let beforeDivision: UInt16
    let afterDivision: UInt16
    let beforeWasFormat0: Bool
    let afterWasFormat0: Bool
}

internal struct TempoInsertion: Sendable {
    let offset: Int
    let point: TempoPoint
}

internal struct TempoRemoval: Sendable {
    let offset: Int
    let point: TempoPoint
}

internal struct TempoChange: Sendable {
    var insertions: [TempoInsertion]
    var removals: [TempoRemoval]
}

internal struct ConfigChange: Sendable {
    let before: SongConfig
    let after: SongConfig
}

/// A compact reversible record assembled by an accepted document mutation.
/// Retains exact inserted and removed values, not unrelated song state.
internal struct DocumentChangeSet: Sendable {
    var events: [EventChange] = []
    var chunkInsertions: [ChunkInsertion] = []
    var chunkRemovals: [ChunkRemoval] = []
    var chunkMoves: [ChunkMove] = []
    var chunkEnds: [ChunkEndChange] = []
    var fileMetadata: FileMetadataChange?
    var tempo: TempoChange?
    var config: ConfigChange?

    var isEmpty: Bool {
        events.isEmpty && chunkInsertions.isEmpty && chunkRemovals.isEmpty && chunkMoves.isEmpty && chunkEnds.isEmpty
            && fileMetadata == nil && tempo == nil && config == nil
    }

    var editEffects: DocumentEditEffects {
        var effects = DocumentEditEffects()
        if !chunkInsertions.isEmpty || !chunkRemovals.isEmpty || !chunkMoves.isEmpty {
            effects.include(.structure)
        }
        for change in events {
            let chunk: Int
            let event: MidiEvent
            switch change {
            case let .insert(insertion):
                chunk = insertion.chunk
                event = insertion.event
            case let .remove(removal):
                chunk = removal.chunk
                event = removal.event
            }
            effects.include(chunk: chunk)
            switch event.payload {
            case let .channel(status, _, _):
                switch status >> 4 {
                case 0x8, 0x9: effects.include(.notes)
                case 0xB, 0xE: effects.include(.lanes)
                case 0xC: effects.include(.voices)
                default: effects.include(.otherEvents)
                }
            case let .meta(type, data):
                switch type {
                case 0x03: effects.include(.trackNames)
                case 0x20:
                    effects.include(.trackNames)
                    if data.isEmpty { effects.include(.otherEvents) }
                case 0x51: effects.include(data.count == 3 ? .timeDomain : .otherEvents)
                case 0x58: effects.include(data.count >= 2 ? .timeDomain : .otherEvents)
                default: effects.include(.otherEvents)
                }
                if MidiFile.metaIsMarker(event) { effects.include(.timeDomain) }
            case .systemExclusive:
                effects.include(.otherEvents)
            }
        }
        for change in chunkEnds where change.before != change.after {
            effects.include(chunk: change.chunk)
            effects.include(.timeDomain)
        }
        if let metadata = fileMetadata {
            if metadata.beforeDivision != metadata.afterDivision { effects.include(.timeDomain) }
            if metadata.beforeWasFormat0 != metadata.afterWasFormat0 { effects.include(.configuration) }
        }
        if let tempo, !tempo.insertions.isEmpty || !tempo.removals.isEmpty {
            effects.include(.timeDomain)
        }
        if let config, config.before != config.after {
            effects.include(.configuration)
            if config.before.extendedClocks != config.after.extendedClocks {
                effects.include(.timeDomain)
            }
        }
        return effects
    }

    internal struct TrackNameRole: Equatable {
        let chunk: Int
        let payload: MidiEventPayload
        let eligible: Bool
    }

    private struct ChannelBounds {
        let chunk: Int
        var first: Tick
        var last: Tick
    }

    /// Channel boundaries can expose or hide names inside a channel-prefix span.
    /// Only candidates within the edited spans are retained; no label decoding.
    func contextualTrackNameRoles(in file: borrowing MidiFile) -> [TrackNameRole] {
        var firstBounds: ChannelBounds?
        var remainingBounds: [ChannelBounds] = []
        for change in events {
            let chunk: Int
            let event: MidiEvent
            switch change {
            case let .insert(insertion):
                chunk = insertion.chunk
                event = insertion.event
            case let .remove(removal):
                chunk = removal.chunk
                event = removal.event
            }
            guard event.isChannel else { continue }
            if var bounds = firstBounds, bounds.chunk == chunk {
                bounds.first = min(bounds.first, event.tick)
                bounds.last = max(bounds.last, event.tick)
                firstBounds = bounds
            } else if firstBounds == nil {
                firstBounds = ChannelBounds(chunk: chunk, first: event.tick, last: event.tick)
            } else if let index = remainingBounds.firstIndex(where: { $0.chunk == chunk }) {
                remainingBounds[index].first = min(remainingBounds[index].first, event.tick)
                remainingBounds[index].last = max(remainingBounds[index].last, event.tick)
            } else {
                remainingBounds.append(ChannelBounds(chunk: chunk, first: event.tick, last: event.tick))
            }
        }
        var roles: [TrackNameRole] = []
        if let bounds = firstBounds {
            let sourceEvents = file.chunks[bounds.chunk].events
            appendTrackNameRoles(in: sourceEvents.span, bounds: bounds, to: &roles)
        }
        for bounds in remainingBounds {
            let sourceEvents = file.chunks[bounds.chunk].events
            appendTrackNameRoles(in: sourceEvents.span, bounds: bounds, to: &roles)
        }
        return roles
    }

    private func appendTrackNameRoles(
        in events: borrowing Span<MidiEvent>, bounds: ChannelBounds,
        to roles: inout [TrackNameRole]
    ) {
        var lower = 0
        var upper = events.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if events[middle].tick < bounds.first {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        let begin = lower
        while lower > 0 {
            lower -= 1
            if events[lower].isChannel || events[lower].metaType == 0x20 { break }
        }
        var scanner = TrackNameScan()
        var hasContextualPrefix = false
        for index in lower..<events.count {
            let event = events[index]
            if event.tick > bounds.last && (event.isChannel || event.metaType == 0x20) { break }
            if case let .meta(type, data) = event.payload, type == 0x20, !data.isEmpty {
                hasContextualPrefix = true
            }
            let eligible = scanner.consume(event)
            if hasContextualPrefix, index >= begin, event.metaType == 0x03 {
                roles.append(TrackNameRole(chunk: bounds.chunk, payload: event.payload, eligible: eligible))
            }
        }
    }

    func apply(to state: inout SongState, direction: BankHistoryDirection) {
        if direction == .undo { applyChunkEnds(to: &state, direction: direction) }
        if direction == .redo { applyChunks(to: &state, direction: direction) }
        applyEvents(to: &state, direction: direction)
        if direction == .undo { applyChunks(to: &state, direction: direction) }
        if direction == .redo { applyChunkEnds(to: &state, direction: direction) }
        if let change = fileMetadata {
            state.file.division =
                direction == .redo
                ? change.afterDivision : change.beforeDivision
            state.file.wasFormat0 =
                direction == .redo
                ? change.afterWasFormat0 : change.beforeWasFormat0
        }
        if let tempo { applyTempo(tempo, to: &state.tempo, direction: direction) }
        if let config { state.config = direction == .redo ? config.after : config.before }
    }

    private func applyChunkEnds(
        to state: inout SongState,
        direction: BankHistoryDirection
    ) {
        for change in chunkEnds {
            state.file.chunks[change.chunk].endTick =
                direction == .redo ? change.after : change.before
        }
    }

    private func applyTempo(
        _ change: TempoChange, to tempo: inout [TempoPoint],
        direction: BankHistoryDirection
    ) {
        switch direction {
        case .redo:
            for removal in change.removals.sorted(by: { $0.offset > $1.offset }) {
                tempo.remove(at: removal.offset)
            }
            for insertion in change.insertions.sorted(by: { $0.offset < $1.offset }) {
                tempo.insert(insertion.point, at: insertion.offset)
            }
        case .undo:
            for insertion in change.insertions.sorted(by: { $0.offset > $1.offset }) {
                tempo.remove(at: insertion.offset)
            }
            for removal in change.removals.sorted(by: { $0.offset < $1.offset }) {
                tempo.insert(removal.point, at: removal.offset)
            }
        }
    }

    private func applyChunks(to state: inout SongState, direction: BankHistoryDirection) {
        switch direction {
        case .redo:
            for change in chunkRemovals.sorted(by: { $0.offset > $1.offset }) {
                state.file.chunks.remove(at: change.offset)
            }
            for change in chunkInsertions.sorted(by: { $0.offset < $1.offset }) {
                state.file.chunks.insert(change.chunk, at: change.offset)
            }
            for change in chunkMoves {
                let chunk = state.file.chunks.remove(at: change.from)
                state.file.chunks.insert(chunk, at: change.to)
            }
        case .undo:
            for change in chunkMoves.reversed() {
                let chunk = state.file.chunks.remove(at: change.to)
                state.file.chunks.insert(chunk, at: change.from)
            }
            for change in chunkInsertions.sorted(by: { $0.offset > $1.offset }) {
                state.file.chunks.remove(at: change.offset)
            }
            for change in chunkRemovals.sorted(by: { $0.offset < $1.offset }) {
                state.file.chunks.insert(change.chunk, at: change.offset)
            }
        }
    }

    private func applyEvents(to state: inout SongState, direction: BankHistoryDirection) {
        switch direction {
        case .redo:
            for change in events { applyEvent(change, to: &state) }
        case .undo:
            for change in events.reversed() { unapplyEvent(change, to: &state) }
        }
    }

    private func applyEvent(_ change: EventChange, to state: inout SongState) {
        switch change {
        case .insert(let insertion):
            state.file.chunks[insertion.chunk].events.insert(
                insertion.event, at: insertion.offset)
        case .remove(let removal):
            state.file.chunks[removal.chunk].events.remove(at: removal.offset)
        }
    }

    private func unapplyEvent(_ change: EventChange, to state: inout SongState) {
        switch change {
        case .insert(let insertion):
            state.file.chunks[insertion.chunk].events.remove(at: insertion.offset)
        case .remove(let removal):
            state.file.chunks[removal.chunk].events.insert(
                removal.event, at: removal.offset)
        }
    }
}
