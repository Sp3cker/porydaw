import Foundation

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
    public var s8: [Int8] = []
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
}
