import Synchronization

/// Scalar state shared by the control thread, callback and presentation.
public final class AudioStatus: Sendable {
    let requested = Atomic<Int32>(AudioTransportState.stopped.rawValue)
    let applied = Atomic<Int32>(AudioTransportState.stopped.rawValue)
    let loaded = Atomic<Bool>(false)
    let patternActive = Atomic<Bool>(false)
    let patternPosition = Atomic<UInt64>(0)
    let playhead = Atomic<UInt64>(0)
    let activePcm = Atomic<Int>(0)
    let activeCgb = Atomic<Int>(0)
    let cpuGeneration = Atomic<UInt64>(0)
    let settingsWord = Atomic<UInt64>(0)
    let timelineIdentity = Atomic<UInt64>(0)
    let lostTotal = Atomic<UInt64>(0)

    public init() {}
    public func invalidateTelemetry() {
        cpuGeneration.wrappingAdd(1, ordering: .acquiringAndReleasing)
    }

    public var requestedTransport: AudioTransportState {
        guard let value = AudioTransportState(rawValue: requested.load(ordering: .relaxed)) else {
            preconditionFailure("Invalid requested transport")
        }
        return value
    }
    public var appliedTransport: AudioTransportState {
        guard let value = AudioTransportState(rawValue: applied.load(ordering: .relaxed)) else {
            preconditionFailure("Invalid applied transport")
        }
        return value
    }
    public var songLoaded: Bool { loaded.load(ordering: .acquiring) }
    public var isPatternAuditioning: Bool { patternActive.load(ordering: .acquiring) }
    public var patternAuditionPositionSamples: UInt64 { patternPosition.load(ordering: .relaxed) }
    public var playheadSamples: UInt64 { playhead.load(ordering: .relaxed) }
    public var activePcmChannels: Int { activePcm.load(ordering: .relaxed) }
    public var activeCgbChannels: Int { activeCgb.load(ordering: .relaxed) }
    public var telemetryGeneration: UInt64 { cpuGeneration.load(ordering: .acquiring) }
    public var appliedSettingsBits: UInt64 { settingsWord.load(ordering: .acquiring) }
    public var appliedTimelineIdentity: UInt64 { timelineIdentity.load(ordering: .acquiring) }
    public var polyLostTotal: UInt64 { lostTotal.load(ordering: .relaxed) }
}
