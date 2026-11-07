import Synchronization
import PorydawPlaybackNative

public struct AudioActivityLevel: Equatable, Sendable {
    public var left: UInt8 = 0
    public var right: UInt8 = 0

    public init(left: UInt8 = 0, right: UInt8 = 0) {
        self.left = left
        self.right = right
    }
}
public struct AudioPolyChannel: Sendable {
    public var on: Bool
    public var releasing: Bool
    public var track: UInt8
    public var midiKey: UInt8
}
public struct AudioPolyEvent: Sendable {
    public var type: UInt8
    public var trackIndex: UInt8
    public var midiKey: UInt8
    public var byTrack: UInt8
    public var program: UInt8
    public var tick: UInt32

    public init(type: UInt8, trackIndex: UInt8, midiKey: UInt8, byTrack: UInt8, program: UInt8, tick: UInt32) {
        self.type = type
        self.trackIndex = trackIndex
        self.midiKey = midiKey
        self.byTrack = byTrack
        self.program = program
        self.tick = tick
    }
}
public struct AudioPolySnapshot: Sendable {
    public var maxPcmChannels: UInt8
    public var invert: Bool
    public var pcm: [AudioPolyChannel]
    public var cgb: [AudioPolyChannel]
    public var drop: [UInt32]
    public var steal: [UInt32]
    public var tailCut: [UInt32]
    public var eventTotal: UInt32
    public var events: [AudioPolyEvent]

    public static var empty: AudioPolySnapshot {
        AudioPolySnapshot(
            maxPcmChannels: 0, invert: false, pcm: [], cgb: [], drop: [], steal: [],
            tailCut: [], eventTotal: 0, events: [])
    }
}

/// Callback publishes component-wise peak holds. GUI consumption alone allocates value arrays.
final class AudioTelemetry {
    private let status: AudioStatus
    private let peaks: UnsafeMutablePointer<Atomic<UInt32>>
    private let scratch: UnsafeMutablePointer<UInt32>
    private let tracks = Int(MAX_TRACKS)
    private let polyVersions: UnsafeMutablePointer<Atomic<UInt64>>
    private let polyPublished = Atomic<Int>(0)
    private let polyPinned = Atomic<Int>(-1)
    private var cachedPoly: [UInt64]
    private let poly: UnsafeMutablePointer<Atomic<UInt64>>
    private let previewVersion = Atomic<UInt64>(0)
    private let previewPair0 = Atomic<UInt64>(0)
    private let previewPair1 = Atomic<UInt64>(0)
    private let previewPair2 = Atomic<UInt64>(0)
    private let previewPair3 = Atomic<UInt64>(0)
    private var cachedPreview: [UInt64]
    private static let pcmCount = Int(TOTAL_PCM_CHANNELS)
    private static let cgbCount = Int(TOTAL_CGB_CHANNELS)
    private static let trackCount = Int(MAX_TRACKS)
    private static let eventCount = Int(M4A_POLY_EVENT_CAPACITY)
    private static let polyCount = 1 + pcmCount + cgbCount + trackCount * 3 + eventCount * 2

    init(status: AudioStatus) {
        self.status = status
        poly = .allocate(capacity: Self.polyCount * 3)
        for i in 0..<(Self.polyCount * 3) { (poly + i).initialize(to: Atomic(0)) }
        polyVersions = .allocate(capacity: 3)
        for i in 0..<3 { (polyVersions + i).initialize(to: Atomic(0)) }
        cachedPoly = [UInt64](repeating: 0, count: Self.polyCount)
        precondition(Self.cgbCount == 8)
        cachedPreview = [UInt64](repeating: 0, count: Self.cgbCount)
        peaks = .allocate(capacity: Int(MAX_TRACKS))
        scratch = .allocate(capacity: Int(MAX_TRACKS))
        scratch.initialize(repeating: 0, count: Int(MAX_TRACKS))
        for i in 0..<Int(MAX_TRACKS) { (peaks + i).initialize(to: Atomic(0)) }
    }
    deinit {
        poly.deinitialize(count: Self.polyCount * 3)
        poly.deallocate()
        polyVersions.deinitialize(count: 3)
        polyVersions.deallocate()
        peaks.deinitialize(count: tracks)
        peaks.deallocate()
        scratch.deinitialize(count: tracks)
        scratch.deallocate()
    }
    func clear() {
        status.playhead.store(0, ordering: .relaxed)
        status.activePcm.store(0, ordering: .relaxed)
        status.activeCgb.store(0, ordering: .relaxed)
        for i in 0..<tracks { peaks[i].store(0, ordering: .relaxed) }
    }
    private func maximum(_ a: UInt32, _ b: UInt32) -> UInt32 {
        max(a & 255, b & 255) | (max((a >> 8) & 255, (b >> 8) & 255) << 8)
    }
    func consume() -> [AudioActivityLevel] {
        (0..<tracks).map {
            let value = peaks[$0].exchange(0, ordering: .relaxed)
            return AudioActivityLevel(
                left: UInt8(truncatingIfNeeded: value),
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
        status.playhead.store(position, ordering: .relaxed)
        status.activePcm.store(pcm, ordering: .relaxed)
        status.activeCgb.store(cgb, ordering: .relaxed)
        for i in 0..<tracks {
            var observed = peaks[i].load(ordering: .relaxed)
            while true {
                let result = peaks[i].compareExchange(
                    expected: observed,
                    desired: maximum(observed, scratch[i]), ordering: .relaxed)
                if result.exchanged { break }
                observed = result.original
            }
        }
    }

    func publishPoly(_ engine: UnsafeMutablePointer<M4AEngine>) {
        let published = polyPublished.load(ordering: .sequentiallyConsistent)
        let pinned = polyPinned.load(ordering: .sequentiallyConsistent)
        var index = (published + 1) % 3
        if index == pinned { index = (index + 1) % 3 }
        let poly = self.poly + index * Self.polyCount
        let version = polyVersions[index].load(ordering: .sequentiallyConsistent)
        polyVersions[index].store(version &+ 1, ordering: .sequentiallyConsistent)
        poly[0].store(
            UInt64(engine.pointee.maxPcmChannels) | (engine.pointee.polyDebugInvert ? 1 << 8 : 0)
                | UInt64(engine.pointee.polyEventTotal) << 32, ordering: .sequentiallyConsistent)
        var offset = 1
        withUnsafePointer(to: &engine.pointee.pcmChannels) { (tuple: UnsafePointer<_>) in
            tuple.withMemoryRebound(to: M4APCMChannel.self, capacity: Self.pcmCount) {
                (channels: UnsafePointer<M4APCMChannel>) in
                for i in 0..<Self.pcmCount {
                    let channel = channels + i
                    poly[offset + i].store(
                        Self.packChannel(
                            status: channel.pointee.status, track: channel.pointee.trackIndex,
                            key: channel.pointee.midiKey),
                        ordering: .sequentiallyConsistent)
                }
            }
        }
        offset += Self.pcmCount
        withUnsafePointer(to: &engine.pointee.cgbChannels) { (tuple: UnsafePointer<_>) in
            tuple.withMemoryRebound(to: M4ACGBChannel.self, capacity: Self.cgbCount) {
                (channels: UnsafePointer<M4ACGBChannel>) in
                for i in 0..<Self.cgbCount {
                    let channel = channels + i
                    poly[offset + i].store(
                        Self.packChannel(
                            status: channel.pointee.status, track: channel.pointee.trackIndex,
                            key: channel.pointee.midiKey),
                        ordering: .sequentiallyConsistent)
                }
            }
        }
        offset += Self.cgbCount
        var lost: UInt64 = 0
        func publishCounters<T>(_ counters: inout T) {
            withUnsafePointer(to: &counters) { (tuple: UnsafePointer<T>) in
                tuple.withMemoryRebound(to: UInt32.self, capacity: Self.trackCount) { (values: UnsafePointer<UInt32>) in
                    for i in 0..<Self.trackCount {
                        let value = UInt64(values[i])
                        poly[offset + i].store(value, ordering: .sequentiallyConsistent)
                        if offset < 1 + Self.pcmCount + Self.cgbCount + Self.trackCount * 2 { lost += value }
                    }
                }
            }
            offset += Self.trackCount
        }
        publishCounters(&engine.pointee.polyDropCount)
        publishCounters(&engine.pointee.polyStealCount)
        publishCounters(&engine.pointee.polyTailCutCount)
        status.lostTotal.store(lost, ordering: .relaxed)
        withUnsafePointer(to: &engine.pointee.polyEvents) { (tuple: UnsafePointer<_>) in
            tuple.withMemoryRebound(to: M4APolyEvent.self, capacity: Self.eventCount) {
                (events: UnsafePointer<M4APolyEvent>) in
                for i in 0..<Self.eventCount {
                    let event = events[i]
                    let fields =
                        UInt64(event.type) | UInt64(event.trackIndex) << 8 | UInt64(event.midiKey) << 16
                        | UInt64(event.byTrack) << 24 | UInt64(event.program) << 32
                    poly[offset + i * 2].store(fields, ordering: .sequentiallyConsistent)
                    poly[offset + i * 2 + 1].store(UInt64(event.tick), ordering: .sequentiallyConsistent)
                }
            }
        }
        polyVersions[index].store(version &+ 2, ordering: .sequentiallyConsistent)
        polyPublished.store(index, ordering: .sequentiallyConsistent)
    }

    private static func packChannel(status: UInt8, track: Int32, key: UInt8) -> UInt64 {
        UInt64(status) | UInt64(UInt8(truncatingIfNeeded: track)) << 8 | UInt64(key) << 16
    }

    func publishPreview(_ engine: UnsafeMutablePointer<M4AEngine>) {
        let version = previewVersion.load(ordering: .sequentiallyConsistent)
        previewVersion.store(version &+ 1, ordering: .sequentiallyConsistent)
        withUnsafePointer(to: &engine.pointee.cgbChannels) { (tuple: UnsafePointer<_>) in
            tuple.withMemoryRebound(to: M4ACGBChannel.self, capacity: Self.cgbCount) {
                (channels: UnsafePointer<M4ACGBChannel>) in
                func pair(_ index: Int) -> UInt64 {
                    let first = channels + index
                    let second = channels + index + 1
                    return Self.packChannel(
                        status: first.pointee.status, track: first.pointee.trackIndex,
                        key: first.pointee.midiKey)
                        | Self.packChannel(
                            status: second.pointee.status, track: second.pointee.trackIndex,
                            key: second.pointee.midiKey) << 24
                }
                previewPair0.store(pair(0), ordering: .sequentiallyConsistent)
                previewPair1.store(pair(2), ordering: .sequentiallyConsistent)
                previewPair2.store(pair(4), ordering: .sequentiallyConsistent)
                previewPair3.store(pair(6), ordering: .sequentiallyConsistent)
            }
        }
        previewVersion.store(version &+ 2, ordering: .sequentiallyConsistent)
    }

    func previewSnapshot() -> AudioPolySnapshot {
        var values = [UInt64](repeating: 0, count: Self.cgbCount)
        var captured = false
        for _ in 0..<3 {
            let version = previewVersion.load(ordering: .sequentiallyConsistent)
            guard version & 1 == 0 else { continue }
            let pairs = [
                previewPair0.load(ordering: .sequentiallyConsistent),
                previewPair1.load(ordering: .sequentiallyConsistent),
                previewPair2.load(ordering: .sequentiallyConsistent),
                previewPair3.load(ordering: .sequentiallyConsistent),
            ]
            for i in 0..<4 {
                values[i * 2] = pairs[i] & 0xFF_FFFF
                values[i * 2 + 1] = pairs[i] >> 24
            }
            captured = version == previewVersion.load(ordering: .sequentiallyConsistent)
            if captured { break }
        }
        if captured { cachedPreview = values } else { values = cachedPreview }
        var snapshot = AudioPolySnapshot.empty
        snapshot.cgb = values.map { (value: UInt64) in
            AudioPolyChannel(
                on: value & 0xC7 != 0, releasing: value & 0x44 != 0,
                track: UInt8(truncatingIfNeeded: value >> 8), midiKey: UInt8(truncatingIfNeeded: value >> 16))
        }
        return snapshot
    }

    func snapshot() -> AudioPolySnapshot {
        var values = [UInt64](repeating: 0, count: Self.polyCount)
        var captured = false
        for _ in 0..<3 {
            let index = polyPublished.load(ordering: .sequentiallyConsistent)
            polyPinned.store(index, ordering: .sequentiallyConsistent)
            guard index == polyPublished.load(ordering: .sequentiallyConsistent) else {
                polyPinned.store(-1, ordering: .sequentiallyConsistent)
                continue
            }
            let version = polyVersions[index].load(ordering: .sequentiallyConsistent)
            if version & 1 == 0 {
                let slot = poly + index * Self.polyCount
                for i in 0..<Self.polyCount { values[i] = slot[i].load(ordering: .sequentiallyConsistent) }
                captured = version == polyVersions[index].load(ordering: .sequentiallyConsistent)
            }
            polyPinned.store(-1, ordering: .sequentiallyConsistent)
            if captured { break }
        }
        if captured { cachedPoly = values } else { values = cachedPoly }
        var offset = 1
        func channels(_ count: Int) -> [AudioPolyChannel] {
            let result = values[offset..<(offset + count)].map { (value: UInt64) in
                AudioPolyChannel(
                    on: value & 0xC7 != 0, releasing: value & 0x44 != 0,
                    track: UInt8(truncatingIfNeeded: value >> 8), midiKey: UInt8(truncatingIfNeeded: value >> 16))
            }
            offset += count
            return result
        }
        let pcm = channels(Self.pcmCount)
        let cgb = channels(Self.cgbCount)
        func counters() -> [UInt32] {
            let result = values[offset..<(offset + Self.trackCount)].map { (value: UInt64) in
                UInt32(truncatingIfNeeded: value)
            }
            offset += Self.trackCount
            return result
        }
        let drop = counters()
        let steal = counters()
        let tailCut = counters()
        let events = (0..<Self.eventCount).map { (index: Int) -> AudioPolyEvent in
            let fields = values[offset + index * 2]
            return AudioPolyEvent(
                type: UInt8(truncatingIfNeeded: fields),
                trackIndex: UInt8(truncatingIfNeeded: fields >> 8),
                midiKey: UInt8(truncatingIfNeeded: fields >> 16),
                byTrack: UInt8(truncatingIfNeeded: fields >> 24),
                program: UInt8(truncatingIfNeeded: fields >> 32),
                tick: UInt32(truncatingIfNeeded: values[offset + index * 2 + 1]))
        }
        return AudioPolySnapshot(
            maxPcmChannels: UInt8(truncatingIfNeeded: values[0]),
            invert: values[0] & (1 << 8) != 0, pcm: pcm, cgb: cgb, drop: drop, steal: steal,
            tailCut: tailCut, eventTotal: UInt32(truncatingIfNeeded: values[0] >> 32), events: events)
    }
}
