/// One raw plugin note event in absolute, possibly pre-roll, document ticks.
public struct RawNoteEvent: Equatable, Sendable {
    public var tick: Int64
    public var pitch: Int
    public var velocity: Int
    public var isOn: Bool
    public var noteID: Int32?

    public init(tick: Int64, pitch: Int, velocity: Int, isOn: Bool, noteID: Int32? = nil) {
        self.tick = tick
        self.pitch = pitch
        self.velocity = velocity
        self.isOn = isOn
        self.noteID = noteID
    }
}

/// Counts discarded events and adjustments to the final surviving notes.
public struct NormalizationReport: Equatable, Sendable {
    public var notes: Int = 0
    public var nonNoteEvents: Int = 0
    public var droppedBeforeRange: Int = 0
    public var droppedAfterRange: Int = 0
    public var droppedPitch: Int = 0
    public var droppedTooShort: Int = 0
    public var orphanOffs: Int = 0
    public var unterminatedNotes: Int = 0
    public var snappedOnsets: Int = 0
    public var adjustedDurations: Int = 0
    public var velocityClamped: Int = 0
    public var overlapsTrimmed: Int = 0
    public var duplicatesSuppressed: Int = 0

    public init() {}
}

/// Invalid output bounds or more notes than the engine can accept.
public enum NormalizationError: Error, Equatable {
    case invalidRange
    case tooManyNotes
}

/// Pure batch conversion of raw plugin output to engine-representable notes.
public enum EngineNoteNormalizer {
    public static let noteLimit = 65_536

    private enum PairKey: Hashable {
        case id(Int32)
        case pitch(Int)

        init(_ event: RawNoteEvent) {
            if let id = event.noteID, id > 0 {
                self = .id(id)
            } else {
                self = .pitch(event.pitch)
            }
        }
    }

    private struct Pending {
        let event: RawNoteEvent
        var end: Int64?
        var next: Int?
    }

    private struct Queue {
        var first: Int
        var last: Int
    }

    private struct Candidate {
        var note: NewNote
        let target: Int64
        let snapped: Bool
        let clamped: Bool
        var duplicates = 0
        var trimmed = false
        var survives = true
    }

    private static func pair(_ events: [RawNoteEvent], report: inout NormalizationReport) -> [Pending] {
        let ordered = events.indices.sorted { (lhs: Int, rhs: Int) -> Bool in
            let left = events[lhs]
            let right = events[rhs]
            if left.tick != right.tick { return left.tick < right.tick }
            let leftOn = left.isOn && left.velocity != 0
            let rightOn = right.isOn && right.velocity != 0
            if leftOn != rightOn { return !leftOn }
            return lhs < rhs
        }
        var pending: [Pending] = []
        pending.reserveCapacity(events.count / 2)
        var queues: [PairKey: Queue] = [:]
        for index in ordered {
            let event = events[index]
            let key = PairKey(event)
            if event.isOn && event.velocity != 0 {
                let next = pending.count
                pending.append(Pending(event: event))
                if let queue = queues[key] {
                    pending[queue.last].next = next
                    queues[key] = Queue(first: queue.first, last: next)
                } else {
                    queues[key] = Queue(first: next, last: next)
                }
            } else if let queue = queues[key] {
                pending[queue.first].end = event.tick
                if let next = pending[queue.first].next {
                    queues[key] = Queue(first: next, last: queue.last)
                } else {
                    queues.removeValue(forKey: key)
                }
            } else {
                report.orphanOffs += 1
            }
        }
        return pending
    }

    /// Normalizes a batch without changing song state; equal-onset, equal-pitch notes use the later event.
    /// - Throws: `NormalizationError` for invalid bounds or more than `noteLimit` surviving notes.
    public static func normalize(
        _ events: [RawNoteEvent], track: Int, range: TimeRange, lattice: EngineNoteLattice
    ) throws -> (notes: [NewNote], report: NormalizationReport) {
        guard track >= 0, !range.isEmpty, !range.hasReservedEndpoint else {
            throw NormalizationError.invalidRange
        }
        var report = NormalizationReport()
        let pending = pair(events, report: &report)
        let first = Int64(range.startTick)
        let end = Int64(range.endTick)
        var candidates: [Candidate] = []
        candidates.reserveCapacity(pending.count)
        var lastByPitch: [Int?] = Array(repeating: nil, count: 128)
        for item in pending {
            if item.end == nil { report.unterminatedNotes += 1 }
            let tick = lattice.snap(item.event.tick)
            guard tick >= first else {
                report.droppedBeforeRange += 1
                continue
            }
            guard tick < end else {
                report.droppedAfterRange += 1
                continue
            }
            guard (0...127).contains(item.event.pitch) else {
                report.droppedPitch += 1
                continue
            }
            let release = item.end ?? end
            guard release > tick else {
                report.droppedTooShort += 1
                continue
            }
            let target = release - tick
            guard target >= lattice.quantumTicks,
                let duration = lattice.durationTicks(target: Double(target), maximum: end - tick)
            else {
                report.droppedTooShort += 1
                continue
            }
            let velocity = clampVelocity(item.event.velocity)
            var candidate = Candidate(
                note: NewNote(
                    track: track, tick: Tick(tick), pitch: UInt8(item.event.pitch),
                    duration: Tick(duration), velocity: velocity),
                target: target, snapped: tick != item.event.tick,
                clamped: Int(velocity) != item.event.velocity)
            if let previous = lastByPitch[item.event.pitch], candidates[previous].note.tick == Tick(tick) {
                candidate.duplicates = candidates[previous].duplicates + 1
                candidates[previous].survives = false
            }
            lastByPitch[item.event.pitch] = candidates.count
            candidates.append(candidate)
        }
        lastByPitch = Array(repeating: nil, count: 128)
        for index in candidates.indices where candidates[index].survives {
            let pitch = Int(candidates[index].note.pitch)
            if let previous = lastByPitch[pitch] {
                let available = Int64(candidates[index].note.tick) - Int64(candidates[previous].note.tick)
                if Int64(candidates[previous].note.duration) > available {
                    if let duration = lattice.durationTicks(target: Double(available), maximum: available) {
                        candidates[previous].note.duration = Tick(duration)
                        candidates[previous].trimmed = true
                    } else {
                        candidates[previous].survives = false
                        report.droppedTooShort += 1
                    }
                }
            }
            lastByPitch[pitch] = index
        }
        var notes: [NewNote] = []
        notes.reserveCapacity(min(candidates.count, noteLimit))
        for candidate in candidates where candidate.survives {
            guard notes.count < noteLimit else { throw NormalizationError.tooManyNotes }
            notes.append(candidate.note)
            if candidate.snapped { report.snappedOnsets += 1 }
            if Int64(candidate.note.duration) != candidate.target { report.adjustedDurations += 1 }
            if candidate.clamped { report.velocityClamped += 1 }
            if candidate.trimmed { report.overlapsTrimmed += 1 }
            report.duplicatesSuppressed += candidate.duplicates
        }
        report.notes = notes.count
        return (notes, report)
    }
}
