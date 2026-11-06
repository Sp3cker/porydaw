import PorydawAppAudio
import PorydawPlayback

@MainActor
public protocol SampleAuditionOutput: AnyObject {
    func beginSampleRequest() -> UInt64
    func sampleRequestIsCurrent(_ request: UInt64) -> Bool
    func auditionSample(
        request: UInt64, pcm: SampleAuditionPcm, frequency: UInt32, loopStart: UInt32,
        looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) -> Bool
    func auditionSampleOff(request: UInt64)
}

/// Coordinates ownership while sample preparation and native slot retirement complete.
@MainActor
public final class SampleAuditionArbiter {
    private let output: (any SampleAuditionOutput)?
    private weak var activeOwner: AnyObject?
    private var activeRequest: UInt64?

    public init(output: (any SampleAuditionOutput)?) {
        self.output = output
    }

    public var isAvailable: Bool { output != nil }

    /// A new request immediately silences the preceding owner, before any preparation.
    func begin(owner: AnyObject) -> UInt64? {
        guard let output else { return nil }
        let request = output.beginSampleRequest()
        activeOwner = owner
        activeRequest = request
        return request
    }

    func isCurrent(owner: AnyObject, request: UInt64) -> Bool {
        activeOwner === owner && activeRequest == request && output?.sampleRequestIsCurrent(request) == true
    }

    /// Busy native storage stays silent and reserved for this request's next retry.
    func publish(
        owner: AnyObject, request: UInt64, pcm: SampleAuditionPcm,
        frequency: UInt32, loopStart: UInt32, looped: Bool,
        key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) -> Bool {
        guard isCurrent(owner: owner, request: request), let output else { return false }
        return output.auditionSample(
            request: request, pcm: pcm, frequency: frequency, loopStart: loopStart,
            looped: looped, key: key, adsr: adsr, toneKey: toneKey)
    }

    /// Stops only the caller's current reservation, including unfinished preparation.
    public func stop(owner: AnyObject) {
        guard let request = activeRequest, isCurrent(owner: owner, request: request) else { return }
        activeOwner = nil
        activeRequest = nil
        output?.auditionSampleOff(request: request)
    }
}
