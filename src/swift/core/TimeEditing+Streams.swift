import Foundation

@MainActor
extension SongDocument {
    func applyRemoveToValueStreams(
        range: TimeRange, plan: TimePlan, state: SongState,
        actions: inout TimeActions
    ) {
        var grouped: [TimeStream: [TimeEventRef]] = [:]
        for event in plan.events {
            if let stream = event.stream { grouped[stream, default: []].append(event) }
        }
        let consumed = xcmdConsumed(in: state.file)
        for points in grouped.values {
            let ordered = points.sorted { ($0.tick, $0.chunk, $0.index) < ($1.tick, $1.chunk, $1.index) }
            let seamCovered = ordered.contains { $0.tick == range.endTick }
            var winner: Int?
            for (position, point) in ordered.enumerated()
            where range.contains(point.tick) && !consumed[point.chunk].contains(point.index) {
                winner = position
            }
            for (position, point) in ordered.enumerated() {
                if point.tick < range.startTick { continue }
                if point.tick >= range.endTick {
                    actions.move(
                        chunk: point.chunk, index: point.index,
                        to: point.tick - range.span, preserveIdentity: false)
                } else if position == winner && !seamCovered {
                    actions.move(
                        chunk: point.chunk, index: point.index,
                        to: range.startTick, preserveIdentity: false)
                } else {
                    actions.remove(chunk: point.chunk, index: point.index)
                }
            }
        }
    }

    func seedAndCopyValueStreams(
        range: TimeRange, plan: TimePlan, state: SongState,
        actions: inout TimeActions, extra: inout [[MidiEvent]]
    ) {
        var grouped: [TimeStream: [TimeEventRef]] = [:]
        for event in plan.events {
            if let stream = event.stream { grouped[stream, default: []].append(event) }
        }
        let consumed = xcmdConsumed(in: state.file)
        // Streams are visited in hash order; emitting by source position keeps same-tick order deterministic.
        var emitted: [(source: TimeEventRef, chunk: Int, event: MidiEvent)] = []
        for points in grouped.values {
            let ordered = points.sorted { ($0.tick, $0.chunk, $0.index) < ($1.tick, $1.chunk, $1.index) }
            let atStart = ordered.last { $0.tick <= range.startTick }
            let firstInside = ordered.first { $0.tick > range.startTick && $0.tick < range.endTick }
            if let source = atStart {
                if consumed[source.chunk].contains(source.index) {
                    actions.values[source.chunk][source.index] = .copy(range.endTick)
                } else {
                    var copy = state.file.chunks[source.chunk].events[source.index]
                    copy.tick = range.endTick
                    emitted.append((source, source.chunk, copy))
                }
            } else if let prototype = firstInside,
                let value = defaultEvent(
                    for: state.file.chunks[prototype.chunk].events[prototype.index],
                    kind: prototype.kind, tick: range.endTick)
            {
                let chunk = prototype.kind == .signature ? 0 : prototype.chunk
                if extra.indices.contains(chunk) { emitted.append((prototype, chunk, value)) }
            }
            for point in ordered where point.tick > range.startTick && point.tick < range.endTick {
                if consumed[point.chunk].contains(point.index) {
                    actions.values[point.chunk][point.index] = .copy(point.tick + range.span)
                } else {
                    var copy = state.file.chunks[point.chunk].events[point.index]
                    copy.tick += range.span
                    emitted.append((point, point.chunk, copy))
                }
            }
        }
        emitted.sort { ($0.source.chunk, $0.source.index) < ($1.source.chunk, $1.source.index) }
        for item in emitted { extra[item.chunk].append(item.event) }
    }

    func shiftEndsRight(
        range: TimeRange, threshold: Tick, plan: TimePlan,
        actions: inout TimeActions
    ) {
        for chunk in actions.endTicks.indices where plan.affectedChunks[chunk] && actions.endTicks[chunk] >= threshold {
            actions.endTicks[chunk] += range.span
        }
    }

    func materialize(
        actions: TimeActions, from state: SongState,
        extra: [[MidiEvent]]? = nil, logicalLaneMoves: Bool = false
    ) -> DocumentMutation? {
        var result = DocumentMutation(state)
        let file = state.file
        let map = file.engineTracks()
        for chunk in file.chunks.indices {
            let originals = file.chunks[chunk].events
            let stream = streamIndex(for: chunk, map: map)
            let traffic = Xcmd.traffic(in: file.chunks[chunk], stream: stream)
            let projection = Xcmd.project(traffic)
            let consumed = Set(
                projection.consumed.compactMap {
                    $0 <= UInt64(Int.max) ? Int($0) : nil
                })
            let knownByIndex =
                logicalLaneMoves
                ? Dictionary(uniqueKeysWithValues: projection.points.map { (Int($0.index), $0) })
                : [:]
            var knownRemovals: [UInt64] = []
            var knownWrites: [Xcmd.PointWrite] = []
            var removeIDs: [UInt64] = []
            var moves: [Xcmd.Relocation] = []
            var copies: [Xcmd.Relocation] = []
            var removals = Set<Int>()
            var insertions: [MidiEvent] = []
            var directInsertions: [MidiEvent] = []
            for index in originals.indices {
                switch actions.values[chunk][index] {
                case .keep: break
                case .remove:
                    if consumed.contains(index) { removeIDs.append(UInt64(index)) } else { removals.insert(index) }
                case .move(let tick, let preserve):
                    if let point = knownByIndex[index] {
                        knownRemovals.append(UInt64(index))
                        knownWrites.append(
                            Xcmd.PointWrite(
                                tick: tick, lane: point.lane,
                                value: Int(point.value), stream: point.stream,
                                channel: originals[index].channel))
                    } else if consumed.contains(index) {
                        moves.append(
                            Xcmd.Relocation(
                                index: UInt64(index), tick: tick,
                                channel: originals[index].channel))
                    } else {
                        removals.insert(index)
                        var event = originals[index]
                        event.tick = tick
                        if event.isNoteOn && !preserve { event.noteID = nil }
                        if logicalLaneMoves { directInsertions.append(event) } else { insertions.append(event) }
                    }
                case .copy(let tick):
                    if consumed.contains(index) {
                        copies.append(
                            Xcmd.Relocation(
                                index: UInt64(index), tick: tick,
                                channel: originals[index].channel))
                    } else {
                        var event = originals[index]
                        event.tick = tick
                        if event.isNoteOn { event.noteID = nil }
                        if logicalLaneMoves { directInsertions.append(event) } else { insertions.append(event) }
                    }
                }
            }
            if !knownRemovals.isEmpty {
                guard
                    let patch = Xcmd.rewrite(
                        traffic, removing: knownRemovals,
                        writing: knownWrites)
                else { return nil }
                for identity in patch.removeEvents {
                    guard identity <= UInt64(Int.max) else { return nil }
                    removals.insert(Int(identity))
                }
                for emission in patch.inserts {
                    guard let event = emittedEvent(emission, originals: originals) else { return nil }
                    insertions.append(event)
                }
            }
            // Native range moves emit logical lane pairs before shifted raw events.
            insertions.append(contentsOf: directInsertions)
            if !removeIDs.isEmpty || !moves.isEmpty || !copies.isEmpty {
                guard
                    let patch = Xcmd.reconcile(
                        traffic, removing: removeIDs,
                        moving: moves, copying: copies),
                    patch.removeEvents.allSatisfy({
                        $0 <= UInt64(Int.max) && !removals.contains(Int($0))
                    })
                else { return nil }
                for identity in patch.removeEvents {
                    removals.insert(Int(identity))
                }
                for emission in patch.inserts {
                    guard let event = emittedEvent(emission, originals: originals) else { return nil }
                    insertions.append(event)
                }
            }
            if let extra { insertions.append(contentsOf: extra[chunk]) }
            for index in insertions.indices where insertions[index].isNoteOn && insertions[index].noteID == nil {
                insertions[index].noteID = mintNoteID()
            }
            guard
                removals.allSatisfy({
                    result.state.file.chunks[chunk].events.indices.contains($0)
                })
            else { return nil }
            result.apply(removing: Array(removals), inserting: insertions, chunk: chunk)
        }
        return result
    }
}
