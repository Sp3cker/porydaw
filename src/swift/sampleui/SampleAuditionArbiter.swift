import PorydawAppAudio

@MainActor
public protocol SampleAuditionOutput: AnyObject {
    func auditionSample(
        samples: [Int8], frequency: UInt32, loopStart: UInt32,
        looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) -> Bool
    func auditionSampleOff()
}

/// Coordinates ownership of the shared sample audition output.
@MainActor
public final class SampleAuditionArbiter {
    private let output: (any SampleAuditionOutput)?
    private weak var activeOwner: AnyObject?

    public init(output: (any SampleAuditionOutput)?) {
        self.output = output
    }

    public var isAvailable: Bool { output != nil }

    /// Releases the preceding audition before attempting to sound a new owner's sample.
    /// A failed publish leaves the lane unowned.
    public func publish(
        owner: AnyObject, samples: [Int8], frequency: UInt32, loopStart: UInt32,
        looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) -> Bool {
        activeOwner = nil
        guard let output else { return false }
        output.auditionSampleOff()
        guard
            output.auditionSample(
                samples: samples, frequency: frequency, loopStart: loopStart,
                looped: looped, key: key, adsr: adsr, toneKey: toneKey)
        else { return false }
        activeOwner = owner
        return true
    }

    /// Silences the lane only when the caller still owns its current audition.
    public func stop(owner: AnyObject) {
        guard activeOwner === owner else { return }
        activeOwner = nil
        output?.auditionSampleOff()
    }
}
