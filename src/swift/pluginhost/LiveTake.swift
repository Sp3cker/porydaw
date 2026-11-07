import Foundation
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

    private static func pairs(_ source: [RawNoteEvent], closeAt end: Int64) -> [(RawNoteEvent, RawNoteEvent)] {
        var queues: [Int64: [Int]] = [:]
        var heads: [Int64: Int] = [:]
        var result: [(RawNoteEvent, RawNoteEvent)] = []
        result.reserveCapacity(source.count / 2)
        for event in source {
            let key =
                event.noteID.flatMap { (id: Int32) -> Int64? in id > 0 ? Int64(id) : nil }
                ?? (-Int64(event.pitch) - 1)
            if event.isOn && event.velocity > 0 {
                queues[key, default: []].append(result.count)
                let off = RawNoteEvent(tick: end, pitch: event.pitch, velocity: 0, isOn: false, noteID: event.noteID)
                result.append((event, off))
            } else if let queue = queues[key], heads[key, default: 0] < queue.count {
                let head = heads[key, default: 0]
                let index = queue[head]
                heads[key] = head + 1
                var off = event
                off.pitch = result[index].0.pitch
                off.noteID = result[index].0.noteID
                result[index].1 = off
            }
        }
        return result
    }

    /// Replaces complete old note pairs by onset, retaining notes outside the segment.
    public mutating func commitSegment(span newSpan: TimeRange, events incoming: [RawNoteEvent]) {
        guard !newSpan.isEmpty, !newSpan.hasReservedEndpoint else { return }
        let oldEnd = Int64(span?.endTick ?? newSpan.endTick)
        var replacement: [RawNoteEvent] = []
        replacement.reserveCapacity(min(Self.eventLimit, events.count + incoming.count))
        for (on, off) in Self.pairs(events, closeAt: oldEnd) {
            if on.tick >= Int64(newSpan.startTick) && on.tick < Int64(newSpan.endTick) { continue }
            replacement.append(on)
            replacement.append(off)
        }
        for (on, off) in Self.pairs(incoming, closeAt: Int64(newSpan.endTick)) {
            guard on.tick >= Int64(newSpan.startTick), on.tick < Int64(newSpan.endTick) else { continue }
            guard replacement.count + 2 <= Self.eventLimit else {
                degraded = true
                continue
            }
            replacement.append(on)
            var closed = off
            closed.tick = min(Int64(newSpan.endTick), max(on.tick, off.tick))
            replacement.append(closed)
        }
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

    /// Grab uses the sole Core normalizer and an outward bar-snapped range.
    public mutating func grab(
        track: Int, timeline: PlaybackTimeline
    ) throws -> (notes: [NewNote], report: NormalizationReport) {
        finishSegment(at: segmentEnd)
        guard let span else { throw NormalizationError.invalidRange }
        let request = CaptureRequest(
            timeline: timeline, track: track, range: span, input: .none, pacing: .offline, prerollBars: 0)
        let transport = try CaptureTransport(request)
        let context = transport.context(at: transport.sample(for: Double(span.startTick)))
        let start = Tick(max(0, (context.barStartPPQ * Double(timeline.ticksPerBeat)).rounded(.down)))
        let last = max(transport.startSample, transport.sample(for: Double(span.endTick)) - 1)
        let end = Tick(
            min(Double(TimeDefaults.noTick - 1), transport.tick(for: transport.nextBar(after: last)).rounded()))
        let range = TimeRange(startTick: start, endTick: end)
        let lattice = try EngineNoteLattice(ticksPerBeat: timeline.ticksPerBeat, playbackSettings: timeline.settings)
        return try EngineNoteNormalizer.normalize(events, track: track, range: range, lattice: lattice)
    }
}
