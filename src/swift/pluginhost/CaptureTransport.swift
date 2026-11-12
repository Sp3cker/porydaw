import Foundation
import PorydawCore

public struct CaptureRequest: Sendable {
    public let timeline: PlaybackTimeline
    public let track: Int
    public let range: TimeRange
    public let input: EffectInput
    public let pacing: EffectPacing
    public let prerollBars: Int

    public init(
        timeline: PlaybackTimeline, track: Int, range: TimeRange, input: EffectInput,
        pacing: EffectPacing, prerollBars: Int
    ) {
        self.timeline = timeline
        self.track = track
        self.range = range
        self.input = input
        self.pacing = pacing
        self.prerollBars = prerollBars
    }
}

public struct CaptureContext: Equatable, Sendable {
    public let sample: Int64
    public let sampleRate: Double
    public let ppq: Double
    public let tempo: Double
    public let numerator: Int32
    public let denominator: Int32
    public let barStartPPQ: Double
    public let cycleStartPPQ: Double
    public let cycleEndPPQ: Double
}

struct CaptureInput: Sendable {
    let sample: Int64
    let pitch: UInt8
    let velocity: UInt8
    let id: Int32
}

/// Pure timing projection; the native wire conversion belongs to the bridge producer.
public struct CaptureTransport: Sendable {
    public static let sampleRate: Double = 48_000
    public static let blockFrames: Int32 = 256
    public let request: CaptureRequest
    public let startSample: Int64
    public let endSample: Int64
    public let prerollStart: Tick
    let inputs: [CaptureInput]

    private static func bounds(
        for request: CaptureRequest
    ) throws -> (prerollStart: Tick, startSample: Int64, endSample: Int64) {
        guard !request.range.isEmpty, !request.range.hasReservedEndpoint,
            request.timeline.ticksPerBeat > 0, !request.timeline.tempoMap.isEmpty,
            request.track >= 0, request.track < 16, (0...2).contains(request.prerollBars)
        else { throw PluginHostError.native("Invalid capture range or timing.") }
        var start = Double(request.range.startTick)
        for _ in 0..<request.prerollBars {
            let meter = Self.meter(at: max(0, start - 1), timeline: request.timeline)
            let length = Self.barLength(meter, division: request.timeline.ticksPerBeat)
            start = max(0, start - length)
        }
        return (
            Tick(start), Self.sample(for: start, timeline: request.timeline),
            Self.sample(for: Double(request.range.endTick), timeline: request.timeline)
        )
    }

    /// Returns the request's validated duration in seconds, including preroll, without preparing input notes.
    /// - Throws: `PluginHostError` if the request's range or timing is invalid.
    public static func estimatedSeconds(for request: CaptureRequest) throws -> Double {
        let bounds = try bounds(for: request)
        return Double(bounds.endSample - bounds.startSample) / sampleRate
    }

    public init(_ request: CaptureRequest) throws {
        let bounds = try Self.bounds(for: request)
        self.request = request
        prerollStart = bounds.prerollStart
        startSample = bounds.startSample
        endSample = bounds.endSample
        var scheduled: [CaptureInput] = []
        if request.input == .trackNotes {
            var counts = InlineArray<128, Int>(repeating: 0)
            var noteCount = 0
            for event in request.timeline.events
            where Int(event.track) == request.track && event.type == 9 && event.data1 > 0 {
                counts[Int(event.data0 & 127)] += 1
                noteCount += 1
                guard noteCount < Int(Int32.max) else { throw PluginHostError.native("Too many input notes.") }
            }
            var heads = InlineArray<128, Int>(repeating: 0)
            var offset = 0
            for pitch in 0..<128 {
                heads[pitch] = offset
                offset += counts[pitch]
            }
            var tails = heads
            var pending = [
                (
                    on: CaptureInput, offSample: Int64?
                )
            ](
                repeating: (CaptureInput(sample: 0, pitch: 0, velocity: 0, id: 0), nil),
                count: noteCount)
            var nextID: Int32 = 1
            for event in request.timeline.events where Int(event.track) == request.track {
                guard event.type == 8 || event.type == 9 else { continue }
                let pitch = Int(event.data0 & 127)
                let sample = Self.sample(for: Double(event.tick), timeline: request.timeline)
                if event.type == 9 && event.data1 > 0 {
                    pending[tails[pitch]].on = CaptureInput(
                        sample: sample, pitch: UInt8(pitch), velocity: min(127, event.data1), id: nextID)
                    tails[pitch] += 1
                    nextID += 1
                } else if heads[pitch] < tails[pitch] {
                    pending[heads[pitch]].offSample = sample
                    heads[pitch] += 1
                }
            }
            var pairCount = 0
            for note in pending where note.on.sample < endSample {
                if let release = note.offSample, release <= startSample { continue }
                pairCount += 1
            }
            scheduled.reserveCapacity(pairCount * 2)
            for note in pending where note.on.sample < endSample {
                if let release = note.offSample, release <= startSample { continue }
                scheduled.append(
                    CaptureInput(
                        sample: max(startSample, note.on.sample), pitch: note.on.pitch,
                        velocity: note.on.velocity, id: note.on.id))
                scheduled.append(
                    CaptureInput(
                        sample: min(endSample, note.offSample ?? endSample), pitch: note.on.pitch,
                        velocity: 0, id: note.on.id))
            }
        }
        scheduled.sort { (lhs: CaptureInput, rhs: CaptureInput) -> Bool in
            if lhs.sample != rhs.sample { return lhs.sample < rhs.sample }
            if (lhs.velocity == 0) != (rhs.velocity == 0) { return lhs.velocity == 0 }
            return lhs.id < rhs.id
        }
        inputs = scheduled
    }

    private static func meter(at tick: Double, timeline: PlaybackTimeline) -> PlaybackTimeSignature {
        var result = PlaybackTimeSignature(tick: 0, numerator: 4, denominatorPowerOfTwo: 2)
        for candidate in timeline.timeSignatures {
            if Double(candidate.tick) > tick { break }
            result = candidate
        }
        return result
    }

    private static func barLength(_ meter: PlaybackTimeSignature, division: UInt32) -> Double {
        Double(signatureBeatTicks(ticksPerBeat: division, denominatorPowerOfTwo: meter.denominatorPowerOfTwo))
            * Double(max(1, meter.numerator))
    }

    private static func sample(for tick: Double, timeline: PlaybackTimeline) -> Int64 {
        var point = timeline.tempoMap[0]
        for candidate in timeline.tempoMap {
            if Double(candidate.tick) > tick { break }
            point = candidate
        }
        let origin = point.sampleOrigin * sampleRate / timeline.sampleRate
        let delta =
            (tick - Double(point.tick)) * Double(point.microsecondsPerQuarterNote)
            / Double(timeline.ticksPerBeat) / 1_000_000 * sampleRate
        return Int64((origin + delta).rounded())
    }

    public func sample(for tick: Double) -> Int64 { Self.sample(for: tick, timeline: request.timeline) }

    public func tick(for sample: Int64) -> Double {
        let timeline = request.timeline
        var point = timeline.tempoMap[0]
        for candidate in timeline.tempoMap {
            if candidate.sampleOrigin * Self.sampleRate / timeline.sampleRate > Double(sample) { break }
            point = candidate
        }
        let origin = point.sampleOrigin * Self.sampleRate / timeline.sampleRate
        let samplesPerTick =
            Double(point.microsecondsPerQuarterNote) / Double(timeline.ticksPerBeat)
            / 1_000_000 * Self.sampleRate
        return Double(point.tick) + (Double(sample) - origin) / samplesPerTick
    }

    public func context(at sample: Int64) -> CaptureContext {
        let tick = tick(for: sample)
        let timeline = request.timeline
        let meter = Self.meter(at: tick, timeline: timeline)
        let length = Self.barLength(meter, division: timeline.ticksPerBeat)
        let bar = Double(meter.tick) + floor((tick - Double(meter.tick)) / length) * length
        var tempo = timeline.tempoMap[0].beatsPerMinute
        for point in timeline.tempoMap {
            if Double(point.tick) > tick { break }
            tempo = point.beatsPerMinute
        }
        let division = Double(timeline.ticksPerBeat)
        return CaptureContext(
            sample: sample, sampleRate: Self.sampleRate, ppq: tick / division, tempo: tempo,
            numerator: Int32(meter.numerator), denominator: Int32(1 << min(30, Int(meter.denominatorPowerOfTwo))),
            barStartPPQ: bar / division, cycleStartPPQ: Double(request.range.startTick) / division,
            cycleEndPPQ: Double(request.range.endTick) / division)
    }

    func nextBar(after sample: Int64) -> Int64 {
        let tick = tick(for: sample)
        let meter = Self.meter(at: tick, timeline: request.timeline)
        let length = Self.barLength(meter, division: request.timeline.ticksPerBeat)
        var next = Double(meter.tick) + (floor((tick - Double(meter.tick)) / length) + 1) * length
        for candidate in request.timeline.timeSignatures where Double(candidate.tick) > tick {
            next = min(next, Double(candidate.tick))
            break
        }
        return max(sample + 1, self.sample(for: next))
    }
}
