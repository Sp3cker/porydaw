import Foundation
import PorydawCore
import PorydawPluginHost

@MainActor
public struct PluginEffectRenderer {
    public init() {}

    public static func snappedRange(_ range: TimeRange, timeline: PlaybackTimeline) throws -> TimeRange {
        guard !range.isEmpty, !range.hasReservedEndpoint, timeline.ticksPerBeat > 0 else {
            throw NormalizationError.invalidRange
        }
        func bar(containing tick: Tick) -> (start: UInt64, end: UInt64) {
            var meter = PlaybackTimeSignature(tick: 0, numerator: 4, denominatorPowerOfTwo: 2)
            var nextChange = UInt64(TimeDefaults.noTick - 1)
            for candidate in timeline.timeSignatures {
                if candidate.tick > tick {
                    nextChange = UInt64(candidate.tick)
                    break
                }
                meter = candidate
            }
            let beat = signatureBeatTicks(
                ticksPerBeat: timeline.ticksPerBeat, denominatorPowerOfTwo: meter.denominatorPowerOfTwo)
            let length = max(1, UInt64(beat) * UInt64(max(1, meter.numerator)))
            let start = UInt64(meter.tick) + (UInt64(tick) - UInt64(meter.tick)) / length * length
            return (start, min(nextChange, start + length))
        }
        let first = bar(containing: range.startTick)
        let last = bar(containing: range.endTick - 1)
        return TimeRange(startTick: Tick(first.start), endTick: Tick(min(UInt64(TimeDefaults.noTick - 1), last.end)))
    }

    public nonisolated static func normalize(
        _ events: [RawNoteEvent], track: Int, range: TimeRange, timeline: PlaybackTimeline,
        nonNoteEvents: Int = 0, origin: EffectOutputOrigin, degraded: Bool = false
    ) throws -> EffectOutput {
        let lattice = try EngineNoteLattice(ticksPerBeat: timeline.ticksPerBeat, playbackSettings: timeline.settings)
        let normalized = try EngineNoteNormalizer.normalize(events, track: track, range: range, lattice: lattice)
        var report = normalized.report
        report.nonNoteEvents = nonNoteEvents
        return EffectOutput(range: range, notes: normalized.notes, origin: origin, report: report, degraded: degraded)
    }

    @concurrent
    private static func normalizeRender(_ capture: CaptureResult, request: CaptureRequest) async throws -> EffectOutput
    {
        try Task.checkCancellation()
        let output = try normalize(
            capture.events, track: request.track, range: request.range, timeline: request.timeline,
            nonNoteEvents: capture.nonNoteEvents, origin: .render)
        try Task.checkCancellation()
        return output
    }

    public func render(
        instance: PluginInstance, effect: TrackEffect, timeline: PlaybackTimeline, range: TimeRange,
        progress: @escaping @MainActor @Sendable (CaptureProgress) -> Void
    ) async throws -> EffectOutput {
        let plugin = effect.config.plugin
        let request = CaptureRequest(
            timeline: timeline, track: effect.config.track, range: range, input: plugin.input,
            pacing: plugin.pacing, prerollBars: plugin.prerollBars)
        let capture = try await instance.capture.render(request, progress: progress)
        return try await Self.normalizeRender(capture, request: request)
    }
}
