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

/// Serialized producer membership and lossless batches; teardown requires a parked callback.
final class AudioBandAuditionEndpoint: Sendable {
    fileprivate struct Member {
        let noteID: UInt64
        let serial: UInt64
        var seen: UInt64
    }

    fileprivate enum Command: Sendable {
        case start(serial: UInt64, track: UInt8, key: UInt8, velocity: UInt8, durationSamples: UInt64)
        case release(serial: UInt64)
    }

    fileprivate struct Commands: Sendable {
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

    fileprivate final class Batch: Sendable {
        let next = AtomicLazyReference<Batch>()
        let commands: Commands
        let sequence: UInt64

        init(commands: Commands, sequence: UInt64) {
            self.commands = commands
            self.sequence = sequence
        }
    }

    private struct Producer {
        var members: [Member] = []
        var memberIndex: [UInt64: Int] = [:]
        var generation: UInt64 = 0
        var serial: UInt64 = 0
        var head: Batch
        var tail: Batch
    }

    private let producer: Mutex<Producer>
    fileprivate let publishedSequence = Atomic<UInt64>(0)
    fileprivate let acknowledgedSequence = Atomic<UInt64>(0)

    fileprivate init(dummy: Batch) {
        producer = Mutex(Producer(head: dummy, tail: dummy))
    }

    deinit {
        producer.withLock { (state: inout Producer) in
            while state.head !== state.tail {
                guard let next = state.head.next.load() else {
                    preconditionFailure("Producer tail must be reachable from the producer head")
                }
                state.head = next
            }
        }
    }

    fileprivate func retireConsumer(_ cursor: inout Batch) {
        producer.withLock { (state: inout Producer) in
            cursor = state.tail
        }
    }

    func update(_ notes: [BandAuditionNote]) {
        producer.withLock { (state: inout Producer) in
            state.generation += 1
            var commands = Commands()
            let incoming = notes.span
            let capacity = state.members.count + incoming.count
            for noteIndex in incoming.indices {
                let note = incoming[noteIndex]
                if let index = state.memberIndex[note.noteID] {
                    state.members[index].seen = state.generation
                }
            }
            var index = 0
            while index < state.members.count {
                let member = state.members[index]
                if member.seen == state.generation {
                    index += 1
                    continue
                }
                commands.append(.release(serial: member.serial), capacity: capacity)
                state.memberIndex.removeValue(forKey: member.noteID)
                let last = state.members.removeLast()
                if index < state.members.count {
                    state.members[index] = last
                    state.memberIndex[last.noteID] = index
                }
            }
            for noteIndex in incoming.indices {
                let note = incoming[noteIndex]
                guard state.memberIndex[note.noteID] == nil else { continue }
                state.serial += 1
                state.memberIndex[note.noteID] = state.members.count
                state.members.append(Member(noteID: note.noteID, serial: state.serial, seen: state.generation))
                commands.append(
                    .start(
                        serial: state.serial, track: note.track, key: note.key, velocity: note.velocity,
                        durationSamples: note.durationSamples), capacity: capacity)
            }
            guard commands.count > 0 else { return }
            let acknowledged = acknowledgedSequence.load(ordering: .acquiring)
            while state.head.sequence < acknowledged {
                guard let next = state.head.next.load() else {
                    preconditionFailure("Acknowledged cursor must follow the producer head")
                }
                state.head = next
            }
            let batch = Batch(commands: commands, sequence: state.tail.sequence + 1)
            _ = state.tail.next.storeIfNil(batch)
            state.tail = batch
            publishedSequence.store(batch.sequence, ordering: .releasing)
        }
    }
}

final class AudioBandAudition {
    private let source: AudioAuditionVoices.Source
    let endpoint: AudioBandAuditionEndpoint
    private var consumerCursor: AudioBandAuditionEndpoint.Batch

    init(source: AudioAuditionVoices.Source) {
        self.source = source
        let dummy = AudioBandAuditionEndpoint.Batch(commands: .init(), sequence: 0)
        endpoint = AudioBandAuditionEndpoint(dummy: dummy)
        consumerCursor = dummy
    }

    deinit { endpoint.retireConsumer(&consumerCursor) }

    func update(_ notes: [BandAuditionNote]) { endpoint.update(notes) }

    func apply(_ engine: UnsafeMutablePointer<M4AEngine>, voices: AudioAuditionVoices) {
        // One acquire captures a finite drain, even if the producer keeps writing.
        let cutoff = endpoint.publishedSequence.load(ordering: .acquiring)
        while consumerCursor.sequence < cutoff {
            guard let batch = consumerCursor.next.load() else {
                preconditionFailure("Published sequence must be reachable from the consumer cursor")
            }
            if batch.commands.count <= batch.commands.inline.count {
                Self.apply(
                    batch.commands.inline.span, count: batch.commands.count, source: source,
                    engine: engine, voices: voices)
            } else {
                let payload = batch.commands.overflow
                Self.apply(
                    payload.span, count: batch.commands.count, source: source, engine: engine,
                    voices: voices)
            }
            consumerCursor = batch
            endpoint.acknowledgedSequence.store(batch.sequence, ordering: .releasing)
        }
    }

    private static func apply(
        _ commands: borrowing Span<AudioBandAuditionEndpoint.Command>, count: Int, source: AudioAuditionVoices.Source,
        engine: UnsafeMutablePointer<M4AEngine>, voices: AudioAuditionVoices
    ) {
        for index in 0..<count {
            switch commands[index] {
            case .start(let serial, let track, let key, let velocity, let durationSamples):
                guard durationSamples > 0 else { continue }
                engine.pointee.polyEventClock = UInt32.max
                voices.start(
                    engine: engine, track: Int32(track), key: key, velocity: velocity,
                    source: source, serial: serial, durationSamples: durationSamples)
            case .release(let serial):
                voices.release(engine: engine, source: source, serial: serial)
            }
        }
    }

    /// Consumer-side (or cold parked) invalidation through a finite cutoff.
    /// Later commands survive; unchanged producer membership must not reattack.
    func discardPending() {
        let cutoff = endpoint.publishedSequence.load(ordering: .acquiring)
        while consumerCursor.sequence < cutoff {
            guard let next = consumerCursor.next.load() else {
                preconditionFailure("Published sequence must be reachable from the consumer cursor")
            }
            consumerCursor = next
        }
        endpoint.acknowledgedSequence.store(cutoff, ordering: .releasing)
    }
}
