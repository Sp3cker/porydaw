import Foundation

public struct SampleDocument: Sendable {
    public let source: ImportedSample
    public private(set) var params: SampleEditParams
    private var cached: ProcessedSample?

    public init(source: ImportedSample) {
        self.source = source
        params = Self.defaultParams(for: source)
    }

    public static func defaultParams(for source: ImportedSample) -> SampleEditParams {
        var params = SampleEditParams()
        params.cropEnd = source.hasLoop ? source.frameCount : min(source.playLength, source.frameCount)
        if params.cropEnd <= 0 { params.cropEnd = source.frameCount }
        params.loopOn = source.hasLoop
        params.loopStart = source.loopStart
        params.loopEnd = source.loopEndInclusive
        params.baseKey = source.baseKey
        params.fineTuneCents = min(max(0, source.fracSemitone * 100), 99.9999999999)
        params.targetRate = source.gbaReady ? source.sampleRate : min(source.sampleRate, ImportedSample.gbaDefaultRate)
        if source.gbaReady {
            params.normalizeMode = .off
            params.dcRemove = .off
            params.fadeIn = false
            params.fadeOut = false
            params.exactPitchOverride = source.exactPitch
        }
        return params
    }

    public mutating func setParams(_ newParams: SampleEditParams) {
        guard newParams != params else { return }
        params = newParams
        cached = nil
    }

    public var processed: ProcessedSample {
        mutating get {
            if let cached { return cached }
            let result = SampleRender.render(source: source, params: params)
            cached = result
            return result
        }
    }
}
