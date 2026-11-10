import PorydawCore

/// Session-only dispatched notes, drained by the owner's 50 ms armed timer.
@MainActor
public struct LiveTake {
    public static let eventLimit = 65_536
    public private(set) var events: [RawNoteEvent] = []
    public private(set) var span: TimeRange?
    public private(set) var degraded = false
    private var pending: [RawNoteEvent] = []
    private var segmentStart: Int64?
    private var segmentEnd: Int64 = 0

    public init() {}

    /// Replaces complete old note pairs by onset, retaining notes outside the segment.
    public mutating func commitSegment(span newSpan: TimeRange, events incoming: [RawNoteEvent]) {
        guard !newSpan.isEmpty, !newSpan.hasReservedEndpoint else { return }
        let oldEnd = Int64(span?.endTick ?? newSpan.endTick)
        var replacement: [RawNoteEvent] = []
        replacement.reserveCapacity(min(Self.eventLimit, events.count + incoming.count))
        func onsetCount(_ source: [RawNoteEvent]) -> Int {
            var count = 0
            for event in source where event.isOn && event.velocity > 0 { count += 1 }
            return count
        }
        func pairingKey(_ event: RawNoteEvent) -> Int64 {
            if let id = event.noteID, id > 0 { return Int64(id) }
            return -Int64(event.pitch) - 1
        }
        var indices = [Int](repeating: -1, count: max(onsetCount(events), onsetCount(incoming)))
        var queues: [Int64: (count: Int, start: Int, head: Int, tail: Int)] = [:]
        var capped = false
        func appendPairs(_ source: [RawNoteEvent], closeAt end: Int64, incoming: Bool) {
            queues.removeAll(keepingCapacity: true)
            for event in source where event.isOn && event.velocity > 0 {
                queues[pairingKey(event), default: (0, -1, 0, 0)].count += 1
            }
            var offset = 0
            for event in source {
                let key = pairingKey(event)
                if event.isOn && event.velocity > 0 {
                    var queue = queues[key, default: (0, -1, 0, 0)]
                    if queue.start < 0 {
                        queue.start = offset
                        queue.head = offset
                        queue.tail = offset
                        offset += queue.count
                    }
                    var index = -1
                    let inSpan = event.tick >= Int64(newSpan.startTick) && event.tick < Int64(newSpan.endTick)
                    if inSpan == incoming {
                        if incoming && replacement.count + 2 > Self.eventLimit {
                            capped = true
                        } else {
                            index = replacement.count
                            replacement.append(event)
                            replacement.append(
                                RawNoteEvent(
                                    tick: end, pitch: event.pitch, velocity: 0, isOn: false, noteID: event.noteID))
                        }
                    }
                    indices[queue.tail] = index
                    queue.tail += 1
                    queues[key] = queue
                } else if var queue = queues[key], queue.head < queue.tail {
                    let index = indices[queue.head]
                    queue.head += 1
                    queues[key] = queue
                    guard index >= 0 else { continue }
                    let on = replacement[index]
                    var off = event
                    off.pitch = on.pitch
                    off.noteID = on.noteID
                    if incoming { off.tick = min(end, max(on.tick, off.tick)) }
                    replacement[index + 1] = off
                }
            }
        }
        appendPairs(events, closeAt: oldEnd, incoming: false)
        appendPairs(incoming, closeAt: Int64(newSpan.endTick), incoming: true)
        if capped { degraded = true }
        replacement.sort { (lhs: RawNoteEvent, rhs: RawNoteEvent) -> Bool in
            if lhs.tick != rhs.tick { return lhs.tick < rhs.tick }
            return !lhs.isOn && rhs.isOn
        }
        events = replacement
        if let old = span {
            span = TimeRange(
                startTick: min(old.startTick, newSpan.startTick), endTick: max(old.endTick, newSpan.endTick))
        } else {
            span = newSpan
        }
    }

    private mutating func finishSegment(at end: Int64) {
        guard let start = segmentStart, end > start else { return }
        let boundedEnd = min(Int64(TimeDefaults.noTick) - 1, end)
        commitSegment(span: TimeRange(startTick: Tick(max(0, start)), endTick: Tick(boundedEnd)), events: pending)
        pending.removeAll(keepingCapacity: true)
        segmentStart = boundedEnd
        segmentEnd = boundedEnd
    }

    /// Only ordered position records advance segment time; discontinuity releases use the old endpoint.
    public mutating func drain(_ ring: LiveTakeRing, finish: Bool = false) {
        degraded = degraded || ring.degraded
        while let entry = ring.pop() {
            let position = Int64(max(0, entry.tick).rounded())
            switch entry.kind {
            case .boundary:
                finishSegment(at: segmentEnd)
                pending.removeAll(keepingCapacity: true)
                segmentStart = position
                segmentEnd = position
            case .position:
                if segmentStart == nil { segmentStart = position }
                segmentEnd = position
            case .note:
                if segmentStart == nil {
                    segmentStart = position
                    segmentEnd = position
                }
                guard pending.count < Self.eventLimit else {
                    degraded = true
                    continue
                }
                let note = entry.note
                let noteTick = note.velocity == 0 && !entry.discontinuity.isEmpty ? segmentEnd : position
                pending.append(
                    RawNoteEvent(
                        tick: noteTick, pitch: Int(note.key), velocity: Int(note.velocity),
                        isOn: note.velocity > 0, noteID: Int32(exactly: note.noteId)))
            }
        }
        if finish { finishSegment(at: segmentEnd) }
    }
}
