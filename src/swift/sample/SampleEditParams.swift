import Foundation
import Synchronization

public struct SampleEditParams: Sendable, Equatable {
    public enum NormalizeMode: Int, Sendable { case auto, looped, oneShot, off }
    public enum Toggle: Int, Sendable { case auto, on, off }

    public var cropStart = 0
    public var cropEnd = 0
    public var loopOn = false
    public var loopStart = 0
    public var loopEnd = 0
    public var baseKey = 60
    public var fineTuneCents = 0.0
    public var targetRate = 0.0
    public var normalizeMode: NormalizeMode = .auto
    public var dcRemove: Toggle = .auto
    public var fadeIn = true
    public var fadeOut = true
    public var crossfadeOn = false
    public var ditherOn = false
    public var exactPitchOverride: UInt32 = 0

    public init() {}
}

public struct ProcessedSample: Sendable, Equatable {
    private static let pcmRevisions = Atomic<UInt64>(0)
    public private(set) var pcmRevision: UInt64 = 0
    public var s8: [Int8] = [] {
        didSet {
            pcmRevision = s8.isEmpty ? 0 : Self.pcmRevisions.wrappingAdd(1, ordering: .relaxed).newValue
        }
    }
    public var freq: UInt32 = 0
    public var loopStart: UInt32 = 0
    public var size: UInt32 = 0
    public var looped = false
    public var declaredRate: UInt32 = 0
    public var unityNote = 60
    public var pitchFraction: UInt32 = 0
    public var outputRate = 0.0
    public var effectiveRate = 0.0
    public var normalizeGain = 1.0
    public var seam = SeamMetrics()
    public var warnings: [String] = []
    public var preview: [Float] = []

    public init() {}

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.s8 == rhs.s8 && lhs.freq == rhs.freq && lhs.loopStart == rhs.loopStart
            && lhs.size == rhs.size && lhs.looped == rhs.looped
            && lhs.declaredRate == rhs.declaredRate && lhs.unityNote == rhs.unityNote
            && lhs.pitchFraction == rhs.pitchFraction && lhs.outputRate == rhs.outputRate
            && lhs.effectiveRate == rhs.effectiveRate && lhs.normalizeGain == rhs.normalizeGain
            && lhs.seam == rhs.seam && lhs.warnings == rhs.warnings && lhs.preview == rhs.preview
    }
}
