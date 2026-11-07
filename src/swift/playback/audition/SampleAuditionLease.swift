/// One producer's claim on the shared sample output. The next `AudioAudition.beginSample()`
/// supersedes it; a superseded lease can neither publish nor silence its successor.
public struct SampleAuditionLease {
    weak var audition: AudioAudition?
    let request: UInt64

    public var isCurrent: Bool { audition?.sampleRequest == request }

    /// - Returns: false when superseded or while all four slots still sound earlier notes.
    public func publish(
        pcm: SampleAuditionPcm, frequency: UInt32, loopStart: UInt32,
        looped: Bool, key: UInt8, adsr: AudioADSR, toneKey: UInt8
    ) -> Bool {
        guard isCurrent, let audition else { return false }
        return audition.samples.publish(
            pcm: pcm, frequency: frequency, loopStart: loopStart,
            looped: looped, key: key, adsr: adsr, toneKey: toneKey)
    }

    public func publish(wave16: [UInt8], key: UInt8, adsr: AudioADSR) -> Bool {
        guard isCurrent, let audition else { return false }
        return audition.samples.publish(wave16: wave16, key: key, adsr: adsr)
    }

    /// Publishes an in-memory kit through the shared four-slot retirement pool.
    public func publish(kit: KitAuditionTone, key: UInt8) -> Bool {
        guard isCurrent, let audition else { return false }
        return audition.samples.publishKitTone(kit, key: key)
    }

    /// Silences the output and ends this lease, unless a newer lease already holds it.
    public func stop() {
        guard isCurrent else { return }
        audition?.endSample()
    }
}
