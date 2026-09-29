import Foundation

public enum SampleSourceKind: Sendable { case wav, aif, mp3, flac, ogg, sf2 }

public struct SampleImportFailure: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

public struct ImportedSample: Sendable, Equatable {
    public static let gbaDefaultRate = 13379.0
    public var buffer: [Float]
    public var sampleRate: Double
    public var baseKey: Int
    public var fracSemitone: Double
    public var hasLoop: Bool
    public var loopStart: Int
    public var loopEndInclusive: Int
    public var playLength: Int
    public var exactPitch: UInt32
    public var hasPitchMetadata: Bool
    public var suggestedName: String
    public var sourcePath: String
    public var sourceKind: SampleSourceKind
    public var sourceChannels: Int
    public var sourceBits: Int
    public var sourceFloat: Bool
    public var gbaReady: Bool
    public var phaseCancelStereo: Bool
    public var warnings: [String]
    public var frameCount: Int { buffer.count }

    public init(
        buffer: [Float] = [], sampleRate: Double = 0, baseKey: Int = 60,
        fracSemitone: Double = 0, hasLoop: Bool = false, loopStart: Int = 0,
        loopEndInclusive: Int = 0, playLength: Int = 0, exactPitch: UInt32 = 0,
        hasPitchMetadata: Bool = false, suggestedName: String = "", sourcePath: String = "",
        sourceKind: SampleSourceKind = .wav, sourceChannels: Int = 1, sourceBits: Int = 0,
        sourceFloat: Bool = false, gbaReady: Bool = false, phaseCancelStereo: Bool = false,
        warnings: [String] = []
    ) {
        self.buffer = buffer
        self.sampleRate = sampleRate
        self.baseKey = baseKey
        self.fracSemitone = fracSemitone
        self.hasLoop = hasLoop
        self.loopStart = loopStart
        self.loopEndInclusive = loopEndInclusive
        self.playLength = playLength
        self.exactPitch = exactPitch
        self.hasPitchMetadata = hasPitchMetadata
        self.suggestedName = suggestedName
        self.sourcePath = sourcePath
        self.sourceKind = sourceKind
        self.sourceChannels = sourceChannels
        self.sourceBits = sourceBits
        self.sourceFloat = sourceFloat
        self.gbaReady = gbaReady
        self.phaseCancelStereo = phaseCancelStereo
        self.warnings = warnings
    }
}
