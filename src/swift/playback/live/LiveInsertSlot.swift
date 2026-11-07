import PorydawCore
import Synchronization

/// Chunk-relative MIDI notes. Zero velocity denotes note-off.
public struct LiveInputEvent: Equatable, Sendable {
    public var sampleOffset: Int32
    public var key: UInt8
    public var velocity: UInt8
    public var noteId: Int64

    public init(sampleOffset: Int32 = 0, key: UInt8 = 0, velocity: UInt8 = 0, noteId: Int64 = 0) {
        self.sampleOffset = sampleOffset
        self.key = key
        self.velocity = velocity
        self.noteId = noteId
    }
}

/// Plugin output uses the same velocity and ID convention as input.
public typealias LiveOutputEvent = LiveInputEvent

public struct LiveDiscontinuity: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let seek = Self(rawValue: 1 << 0)
    public static let stop = Self(rawValue: 1 << 1)
    public static let wrap = Self(rawValue: 1 << 2)
    public static let timelineAdoption = Self(rawValue: 1 << 3)
    public static let arm = Self(rawValue: 1 << 4)
    public static let restore = Self(rawValue: 1 << 5)
    public static let patternReturn = Self(rawValue: 1 << 6)
    public static let missed = Self(rawValue: 1 << 7)
    public static let transport = Self(rawValue: 1 << 8)
}

/// Raw pointers keep the C calling convention independent of Swift struct ABI.
public typealias LiveInsertProcess = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer) -> Void
public typealias LiveTakeSink = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer) -> Void

/// Borrowed only during the sink call. Position records carry completed callback time, including silence.
public struct LiveTakeEvent: Sendable {
    public enum Kind: Sendable, Equatable { case note, position, boundary }
    public var sample: UInt64
    public var tick: Double
    public var note: LiveOutputEvent
    public var kind: Kind
    public var discontinuity: LiveDiscontinuity

    public init(
        sample: UInt64 = 0, tick: Double = 0, note: LiveOutputEvent = LiveOutputEvent(),
        kind: Kind = .note, discontinuity: LiveDiscontinuity = []
    ) {
        self.sample = sample
        self.tick = tick
        self.note = note
        self.kind = kind
        self.discontinuity = discontinuity
    }
}

/// Borrowed for one process call. Output must be sample-ordered; excess output is counted, not written.
public struct LiveInsertCall {
    public static let eventCapacity = 4096
    public var track: Int32 = 0
    public var position: UInt64 = 0
    public var frames: Int32 = 0
    public var playing = false
    public var looping = false
    public var discontinuity: LiveDiscontinuity = []
    public var sampleRate: Double = 0
    public var ticksPerBeat: UInt32 = 0
    public var tick: Double = 0
    public var tempoBPM: Double = 120
    public var numerator: UInt8 = 4
    public var denominatorPowerOfTwo: UInt8 = 2
    public var barStartTick: Double = 0
    public var loopStartSample: UInt64 = 0
    public var loopEndSample: UInt64 = 0
    public var loopStartTick: Tick = 0
    public var loopEndTick: Tick = 0
    /// For chase, FIFO IDs are `(oneBasedPitchOnsetOrdinal - 1) * 128 + key + 1` per track.
    public var timelineEvents: UnsafePointer<PlaybackEvent>?
    public var timelineEventCount = 0
    public var tempoMap: UnsafePointer<PlaybackTempoPoint>?
    public var tempoCount = 0
    public var timeSignatures: UnsafePointer<PlaybackTimeSignature>?
    public var timeSignatureCount = 0
    public var input: UnsafePointer<LiveInputEvent>?
    public var inputCount = 0
    public var inputOverflow: UInt64 = 0
    public var output: UnsafeMutablePointer<LiveOutputEvent>?
    public var outputCapacity = LiveInsertCall.eventCapacity
    public var outputCount = 0
    public var outputOverflow: UInt64 = 0
    public var missed = false
    public var takeSink: LiveTakeSink?
    public var takeContext: UnsafeMutableRawPointer?

    public init() {}
}

/// The owner keeps this address and context alive until the renderer has detached it.
public struct LiveInsertSlot: ~Copyable {
    public let process: LiveInsertProcess
    public let context: UnsafeMutableRawPointer?
    public let takeSink: LiveTakeSink?
    public let takeContext: UnsafeMutableRawPointer?
    public let inputDiscontinuity = Atomic<Bool>(false)

    public init(
        process: LiveInsertProcess, context: UnsafeMutableRawPointer?,
        takeSink: LiveTakeSink? = nil, takeContext: UnsafeMutableRawPointer? = nil
    ) {
        self.process = process
        self.context = context
        self.takeSink = takeSink
        self.takeContext = takeContext
    }
}
