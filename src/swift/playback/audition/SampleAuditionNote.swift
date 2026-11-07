/// Identifies a note within a sample audition lease.
public struct SampleAuditionNoteID: RawRepresentable, Sendable, Equatable, Hashable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let unassigned = Self(rawValue: 0)
}

/// Value-owned audio source submitted to the sample audition producer.
public enum SampleAuditionSource: Sendable {
    case pcm(samples: [Int8], frequency: UInt32, loopStart: UInt32, looped: Bool)
    case wave16([UInt8])
    case kit(KitAuditionTone)
}

/// One note and its source, independent of native audition storage.
public struct SampleAuditionNote: Sendable {
    public var id: SampleAuditionNoteID
    public var source: SampleAuditionSource
    public var key: UInt8
    public var adsr: AudioADSR
    public var toneKey: UInt8

    public init(
        id: SampleAuditionNoteID = .unassigned, source: SampleAuditionSource,
        key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) {
        self.id = id
        self.source = source
        self.key = key
        self.adsr = adsr
        self.toneKey = toneKey
    }
}

/// Why a sample audition lease ended.
public enum SampleAuditionEndReason: Sendable, Equatable {
    case stopped
    case displaced
    case engineReset
    case unavailable
}

/// Lifecycle notifications for a sample audition lease.
public enum SampleAuditionEvent: Sendable, Equatable {
    case started(SampleAuditionNoteID)
    case finished(SampleAuditionNoteID)
    case ended(SampleAuditionEndReason)
}

/// Result of attempting to publish a note to the native slot pool.
public enum SampleAuditionPublication: Sendable, Equatable {
    case published(UInt64)
    case busy
    case invalid
}

/// Callback-published state, identified by the producer's publication generations.
public struct SampleAuditionFeedback: Sendable {
    public let adoptedGeneration: UInt64
    public let finishedGeneration: UInt64
    public let resetGeneration: UInt64
    public let resetPublicationGeneration: UInt64
    public let soundingGeneration: UInt64
    public let soundingFrame: Int?
}
