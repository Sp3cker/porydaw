/// Voicegroup-independent locked-voice payload for in-memory audition.
public struct KitAuditionPsg: Sendable, Equatable {
    public var kind: Int
    public var key: Int
    public var pan: Int
    public var sweep: Int
    public var duty: Int
    public var period: Int
    public var attack: Int
    public var decay: Int
    public var sustain: Int
    public var release: Int
    public var progWave: [UInt32]?

    public init(
        kind: Int, key: Int, pan: Int, sweep: Int, duty: Int, period: Int,
        attack: Int, decay: Int, sustain: Int, release: Int,
        progWave: [UInt32]? = nil
    ) {
        self.kind = kind
        self.key = key
        self.pan = pan
        self.sweep = sweep
        self.duty = duty
        self.period = period
        self.attack = attack
        self.decay = decay
        self.sustain = sustain
        self.release = release
        self.progWave = progWave
    }
}

/// A split wrapper whose assets are copied into one audition storage slot.
public struct KitAuditionTone: Sendable {
    public enum KitAuditionMode: Sendable { case drumkit, keysplit }

    public enum Child: Sendable {
        /// `kind` is the engine ToneData type byte; loop metadata comes from the rendered sample.
        case sample(
            pcm: [Int8], frequency: UInt32, key: UInt8, panSweep: UInt8, adsr: AudioADSR,
            kind: Int, looped: Bool, loopStart: Int)
        case psg(KitAuditionPsg)
    }

    public var mode: KitAuditionMode
    public var children: [Child]
    public var splitTable: [UInt8]?

    public init(mode: KitAuditionMode, children: [Child], splitTable: [UInt8]? = nil) {
        self.mode = mode
        self.children = children
        self.splitTable = splitTable
    }
}
