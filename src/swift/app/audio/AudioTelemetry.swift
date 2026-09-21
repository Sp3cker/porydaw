import Synchronization
import PorydawPlaybackNative

public struct AudioActivityLevel: Equatable {
    public var left: UInt8 = 0
    public var right: UInt8 = 0
}
public struct AudioPolyChannel {
    public var on: Bool
    public var releasing: Bool
    public var track: UInt8
    public var midiKey: UInt8
}
public struct AudioPolySnapshot {
    public var maxPcmChannels: UInt8
    public var invert: Bool
    public var pcm: [AudioPolyChannel]
    public var cgb: [AudioPolyChannel]
    public var drop: [UInt32]
    public var steal: [UInt32]
    public var tailCut: [UInt32]
    public var eventTotal: UInt32
    public var events: [M4APolyEvent]
}

/// Callback publishes component-wise peak holds. GUI consumption alone allocates value arrays.
final class AudioTelemetry {
    let playhead = Atomic<UInt64>(0)
    let activePcm = Atomic<Int>(0)
    let activeCgb = Atomic<Int>(0)
    private let peaks: UnsafeMutablePointer<Atomic<UInt32>>
    private let scratch: UnsafeMutablePointer<UInt32>
    private let tracks = Int(MAX_TRACKS)

    init() {
        peaks = .allocate(capacity: Int(MAX_TRACKS))
        scratch = .allocate(capacity: Int(MAX_TRACKS))
        scratch.initialize(repeating: 0, count: Int(MAX_TRACKS))
        for i in 0..<Int(MAX_TRACKS) { (peaks + i).initialize(to: Atomic(0)) }
    }
    deinit {
        peaks.deinitialize(count: tracks)
        peaks.deallocate()
        scratch.deinitialize(count: tracks)
        scratch.deallocate()
    }
    func clear() {
        playhead.store(0, ordering: .relaxed)
        activePcm.store(0, ordering: .relaxed)
        activeCgb.store(0, ordering: .relaxed)
        for i in 0..<tracks { peaks[i].store(0, ordering: .relaxed) }
    }
    private func maximum(_ a: UInt32, _ b: UInt32) -> UInt32 {
        max(a & 255, b & 255) | (max((a >> 8) & 255, (b >> 8) & 255) << 8)
    }
    func consume() -> [AudioActivityLevel] {
        (0..<tracks).map {
            let value = peaks[$0].exchange(0, ordering: .relaxed)
            return AudioActivityLevel(left: UInt8(truncatingIfNeeded: value),
                                      right: UInt8(truncatingIfNeeded: value >> 8))
        }
    }
    func publish(engine: UnsafeMutablePointer<M4AEngine>, position: UInt64) {
        scratch.update(repeating: 0, count: tracks)
        var pcm = 0
        var cgb = 0
        withUnsafePointer(to: &engine.pointee.pcmChannels) {
            $0.withMemoryRebound(to: M4APCMChannel.self, capacity: Int(TOTAL_PCM_CHANNELS)) { channels in
                for i in 0..<Int(engine.pointee.maxPcmChannels) {
                    let ch = channels + i
                    guard ch.pointee.status & 0xC7 != 0 else { continue }
                    pcm += 1
                    let track = Int(ch.pointee.trackIndex)
                    guard track >= 0 && track < tracks else { continue }
                    let dominant = UInt32(max(ch.pointee.leftVolume, ch.pointee.rightVolume))
                    guard dominant > 0 else { continue }
                    let left = UInt32(ch.pointee.envelopeVolume) * UInt32(ch.pointee.leftVolume) / dominant
                    let right = UInt32(ch.pointee.envelopeVolume) * UInt32(ch.pointee.rightVolume) / dominant
                    scratch[track] = maximum(scratch[track], left | (right << 8))
                }
            }
        }
        withUnsafePointer(to: &engine.pointee.cgbChannels) {
            $0.withMemoryRebound(to: M4ACGBChannel.self, capacity: Int(TOTAL_CGB_CHANNELS)) { channels in
                for i in 0..<Int(MAX_CGB_CHANNELS) {
                    let ch = channels + i
                    guard ch.pointee.status & 0xC7 != 0 else { continue }
                    cgb += 1
                    let track = Int(ch.pointee.trackIndex)
                    guard track >= 0 && track < tracks else { continue }
                    let envelope = UInt32(min(ch.pointee.envelopeVolume, 15)) * 17
                    let left: UInt32 = ch.pointee.pan & 0xF0 != 0 ? envelope : 0
                    let right: UInt32 = ch.pointee.pan & 0x0F != 0 ? envelope : 0
                    scratch[track] = maximum(scratch[track], left | (right << 8))
                }
            }
        }
        playhead.store(position, ordering: .relaxed)
        activePcm.store(pcm, ordering: .relaxed)
        activeCgb.store(cgb, ordering: .relaxed)
        for i in 0..<tracks {
            var observed = peaks[i].load(ordering: .relaxed)
            while true {
                let result = peaks[i].compareExchange(expected: observed,
                    desired: maximum(observed, scratch[i]), ordering: .relaxed)
                if result.exchanged { break }
                observed = result.original
            }
        }
    }

    // Native engine explicitly permits best-effort GUI reads of these diagnostic fields.
    static func lostTotal(_ engine: UnsafeMutablePointer<M4AEngine>) -> UInt64 {
        withUnsafePointer(to: &engine.pointee.polyDropCount) { drops in
            drops.withMemoryRebound(to: UInt32.self, capacity: Int(MAX_TRACKS)) { drop in
                withUnsafePointer(to: &engine.pointee.polyStealCount) { steals in
                    steals.withMemoryRebound(to: UInt32.self, capacity: Int(MAX_TRACKS)) { steal in
                        var total: UInt64 = 0
                        for i in 0..<Int(MAX_TRACKS) { total += UInt64(drop[i]) + UInt64(steal[i]) }
                        return total
                    }
                }
            }
        }
    }
    static func snapshot(_ engine: UnsafeMutablePointer<M4AEngine>) -> AudioPolySnapshot {
        let total = engine.pointee.polyEventTotal
        func counters<T>(_ tuple: inout T) -> [UInt32] {
            withUnsafePointer(to: &tuple) {
                $0.withMemoryRebound(to: UInt32.self, capacity: Int(MAX_TRACKS)) {
                    Array(UnsafeBufferPointer(start: $0, count: Int(MAX_TRACKS)))
                }
            }
        }
        let events = withUnsafePointer(to: &engine.pointee.polyEvents) {
            $0.withMemoryRebound(to: M4APolyEvent.self, capacity: Int(M4A_POLY_EVENT_CAPACITY)) {
                Array(UnsafeBufferPointer(start: $0, count: Int(M4A_POLY_EVENT_CAPACITY)))
            }
        }
        let pcm = withUnsafePointer(to: &engine.pointee.pcmChannels) {
            $0.withMemoryRebound(to: M4APCMChannel.self, capacity: Int(TOTAL_PCM_CHANNELS)) { ptr in
                (0..<Int(TOTAL_PCM_CHANNELS)).map {
                    let ch = ptr[$0]
                    return AudioPolyChannel(on: ch.status & 0xC7 != 0, releasing: ch.status & 0x44 != 0,
                        track: UInt8(truncatingIfNeeded: ch.trackIndex), midiKey: ch.midiKey)
                }
            }
        }
        let cgb = withUnsafePointer(to: &engine.pointee.cgbChannels) {
            $0.withMemoryRebound(to: M4ACGBChannel.self, capacity: Int(TOTAL_CGB_CHANNELS)) { ptr in
                (0..<Int(TOTAL_CGB_CHANNELS)).map {
                    let ch = ptr[$0]
                    return AudioPolyChannel(on: ch.status & 0xC7 != 0, releasing: ch.status & 0x44 != 0,
                        track: UInt8(truncatingIfNeeded: ch.trackIndex), midiKey: ch.midiKey)
                }
            }
        }
        return AudioPolySnapshot(maxPcmChannels: engine.pointee.maxPcmChannels,
            invert: engine.pointee.polyDebugInvert, pcm: pcm, cgb: cgb,
            drop: counters(&engine.pointee.polyDropCount), steal: counters(&engine.pointee.polyStealCount),
            tailCut: counters(&engine.pointee.polyTailCutCount), eventTotal: total, events: events)
    }
}
