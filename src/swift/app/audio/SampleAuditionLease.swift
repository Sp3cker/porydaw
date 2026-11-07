import PorydawPlayback
import Synchronization

public enum SampleAuditionCommand: Sendable {
    case begin(UInt64)
    case play(UInt64, SampleAuditionNote)
    case stop(UInt64)
}

public final class SampleAuditionStatus: Sendable {
    private let version = Atomic<UInt64>(0)
    private let lease = Atomic<UInt64>(0)
    private let note = Atomic<UInt64>(0)
    private let generation = Atomic<UInt64>(0)
    private let feedback: SampleAuditionFeedbackCell

    public init(feedback: SampleAuditionFeedbackCell = SampleAuditionFeedbackCell()) {
        self.feedback = feedback
    }

    public func publish(lease: UInt64, note: SampleAuditionNoteID, generation: UInt64) {
        version.wrappingAdd(1, ordering: .sequentiallyConsistent)
        self.lease.store(lease, ordering: .sequentiallyConsistent)
        self.note.store(note.rawValue, ordering: .sequentiallyConsistent)
        self.generation.store(generation, ordering: .sequentiallyConsistent)
        version.wrappingAdd(1, ordering: .sequentiallyConsistent)
    }

    public func soundingFrame(lease: UInt64, note: SampleAuditionNoteID) -> Int? {
        for _ in 0..<3 {
            let start = version.load(ordering: .sequentiallyConsistent)
            guard start & 1 == 0 else { continue }
            let currentLease = self.lease.load(ordering: .sequentiallyConsistent)
            let currentNote = self.note.load(ordering: .sequentiallyConsistent)
            let currentGeneration = generation.load(ordering: .sequentiallyConsistent)
            guard start == version.load(ordering: .sequentiallyConsistent) else { continue }
            guard currentLease == lease, currentNote == note.rawValue, currentGeneration != 0,
                let snapshot = feedback.snapshot(), snapshot.soundingGeneration == currentGeneration
            else { return nil }
            return snapshot.soundingFrame
        }
        return nil
    }
}

@MainActor
public final class SampleAuditionLease {
    public let id: UInt64
    public private(set) var isCurrent = true
    private let status: SampleAuditionStatus
    private let submit: @Sendable (SampleAuditionCommand) -> Void
    private let onEvent: @MainActor (SampleAuditionEvent) -> Void
    private var nextNoteID: UInt64 = 0
    private var currentNote = SampleAuditionNoteID.unassigned

    public init(
        id: UInt64, status: SampleAuditionStatus,
        submit: @escaping @Sendable (SampleAuditionCommand) -> Void,
        onEvent: @escaping @MainActor (SampleAuditionEvent) -> Void
    ) {
        self.id = id
        self.status = status
        self.submit = submit
        self.onEvent = onEvent
    }

    public var soundingFrame: Int? {
        guard isCurrent else { return nil }
        return status.soundingFrame(lease: id, note: currentNote)
    }

    @discardableResult
    public func play(_ makeNote: (SampleAuditionNoteID) -> SampleAuditionNote) -> SampleAuditionNoteID {
        nextNoteID &+= 1
        let id = SampleAuditionNoteID(rawValue: nextNoteID)
        guard isCurrent else { return id }
        var note = makeNote(id)
        note.id = id
        currentNote = id
        submit(.play(self.id, note))
        return id
    }

    public func stop() {
        guard isCurrent else { return }
        isCurrent = false
        submit(.stop(id))
        onEvent(.ended(.stopped))
    }

    public func end(_ reason: SampleAuditionEndReason) {
        guard isCurrent else { return }
        isCurrent = false
        onEvent(.ended(reason))
    }

    public func deliver(_ event: SampleAuditionEvent) {
        guard isCurrent else { return }
        switch event {
        case .started(let id), .finished(let id):
            guard id == currentNote else { return }
        case .ended:
            isCurrent = false
        }
        onEvent(event)
    }
}
