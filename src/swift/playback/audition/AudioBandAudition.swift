import PorydawPlaybackNative
import Synchronization

/// One document note covered by an audition band. Identity controls entrance
/// and departure; velocity and duration are captured on each fresh entrance.
public struct BandAuditionNote: Equatable, Sendable {
    public let noteID: UInt64
    public let track: UInt8
    public let key: UInt8
    public let velocity: UInt8
    public let durationSamples: UInt64

    public init(noteID: UInt64, track: UInt8, key: UInt8, velocity: UInt8, durationSamples: UInt64) {
        self.noteID = noteID
        self.track = track
        self.key = key
        self.velocity = velocity
        self.durationSamples = durationSamples
    }
}

/// Single-producer membership and lossless immutable batches. Only the producer
/// allocates and reclaims batches; owner teardown requires a parked callback.
final class AudioBandAudition {
    private struct Member {
        let noteID: UInt64
        let serial: UInt64
        var seen: UInt64
    }

    private enum Command: Sendable {
        case start(serial: UInt64, track: UInt8, key: UInt8, velocity: UInt8, durationSamples: UInt64)
        case release(serial: UInt64)
    }

    private struct Commands: Sendable {
        var inline = InlineArray<2, Command>(repeating: .release(serial: 0))
        var overflow: [Command] = []
        var count = 0

        mutating func append(_ command: Command, capacity: Int) {
            if count < inline.count {
                inline[count] = command
            } else {
                if count == inline.count {
                    overflow.reserveCapacity(capacity)
                    let prefix = inline.span
                    for index in prefix.indices { overflow.append(prefix[index]) }
                }
                overflow.append(command)
            }
            count += 1
        }
    }

    private final class Batch: Sendable {
        let next = AtomicLazyReference<Batch>()
        let commands: Commands
        let sequence: UInt64

        init(commands: Commands, sequence: UInt64) {
            self.commands = commands
            self.sequence = sequence
        }
    }

    private var members: [Member] = []
    private var memberIndex: [UInt64: Int] = [:]
    private var commands = Commands()
    private var generation: UInt64 = 0
    private var serial: UInt64 = 0
    // The producer head owns the chain through the tail, protecting callback
    // borrows. Only nodes strictly behind the acquired acknowledgment are pruned.
    private var producerHead: Batch
    private var producerTail: Batch
    private var consumerCursor: Batch
    private let publishedSequence = Atomic<UInt64>(0)
    private let acknowledgedSequence = Atomic<UInt64>(0)

    init() {
        let dummy = Batch(commands: Commands(), sequence: 0)
        producerHead = dummy
        producerTail = dummy
        consumerCursor = dummy
    }

    deinit {
        // Park the callback before teardown. Keep the head owning the whole chain
        // while dropping the old cursor, then release nodes without recursion.
        consumerCursor = producerTail
        while producerHead !== producerTail {
            guard let next = producerHead.next.load() else {
                preconditionFailure("Producer tail must be reachable from the producer head")
            }
            producerHead = next
        }
    }

    func update(_ notes: [BandAuditionNote]) {
        generation += 1
        commands.count = 0
        let incoming = notes.span
        let commandCapacity = members.count + incoming.count
        for noteIndex in incoming.indices {
            let note = incoming[noteIndex]
            if let index = memberIndex[note.noteID] { members[index].seen = generation }
        }
        var index = 0
        while index < members.count {
            let member = members[index]
            if member.seen == generation {
                index += 1
                continue
            }
            commands.append(.release(serial: member.serial), capacity: commandCapacity)
            memberIndex.removeValue(forKey: member.noteID)
            let last = members.removeLast()
            if index < members.count {
                members[index] = last
                memberIndex[last.noteID] = index
            }
        }
        for noteIndex in incoming.indices {
            let note = incoming[noteIndex]
            guard memberIndex[note.noteID] == nil else { continue }
            serial += 1
            memberIndex[note.noteID] = members.count
            members.append(Member(noteID: note.noteID, serial: serial, seen: generation))
            commands.append(
                .start(
                    serial: serial, track: note.track, key: note.key, velocity: note.velocity,
                    durationSamples: note.durationSamples), capacity: commandCapacity)
        }
        guard commands.count > 0 else { return }
        let acknowledged = acknowledgedSequence.load(ordering: .acquiring)
        while producerHead.sequence < acknowledged {
            guard let next = producerHead.next.load() else {
                preconditionFailure("Acknowledged cursor must follow the producer head")
            }
            producerHead = next
        }
        let batch = Batch(commands: commands, sequence: producerTail.sequence + 1)
        if commands.count > commands.inline.count { commands.overflow = [] }
        _ = producerTail.next.storeIfNil(batch)
        producerTail = batch
        publishedSequence.store(batch.sequence, ordering: .releasing)
    }

    func apply(_ engine: UnsafeMutablePointer<M4AEngine>) {
        // One acquire captures a finite drain, even if the producer keeps writing.
        let cutoff = publishedSequence.load(ordering: .acquiring)
        while consumerCursor.sequence < cutoff {
            guard let batch = consumerCursor.next.load() else {
                preconditionFailure("Published sequence must be reachable from the consumer cursor")
            }
            if batch.commands.count <= batch.commands.inline.count {
                Self.apply(batch.commands.inline.span, count: batch.commands.count, engine: engine)
            } else {
                let payload = batch.commands.overflow
                Self.apply(payload.span, count: batch.commands.count, engine: engine)
            }
            consumerCursor = batch
            acknowledgedSequence.store(batch.sequence, ordering: .releasing)
        }
    }

    private static func apply(
        _ commands: borrowing Span<Command>, count: Int,
        engine: UnsafeMutablePointer<M4AEngine>
    ) {
        for index in 0..<count {
            switch commands[index] {
            case .start(let serial, let track, let key, let velocity, let durationSamples):
                engine.pointee.polyEventClock = UInt32.max
                m4a_engine_audition_note_on(
                    engine, M4AAuditionID(serial: serial, source: UInt8(M4A_AUDITION_BAND)),
                    Int32(track), key, velocity, durationSamples)
            case .release(let serial):
                m4a_engine_audition_note_off(
                    engine, M4AAuditionID(serial: serial, source: UInt8(M4A_AUDITION_BAND)))
            }
        }
    }

    /// Consumer-side (or cold parked) invalidation through a finite cutoff.
    /// Later commands survive; unchanged producer membership must not reattack.
    func discardPending() {
        let cutoff = publishedSequence.load(ordering: .acquiring)
        while consumerCursor.sequence < cutoff {
            guard let next = consumerCursor.next.load() else {
                preconditionFailure("Published sequence must be reachable from the consumer cursor")
            }
            consumerCursor = next
        }
        acknowledgedSequence.store(cutoff, ordering: .releasing)
    }
}
