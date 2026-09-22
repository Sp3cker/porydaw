import Foundation
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback
import PorydawPlaybackNative

internal let playbackCheckSampleRate = 48_000.0
internal let playbackCheckDivision: UInt16 = 24
internal let playbackCheckSamplesPerTick: UInt64 = 1_000

internal func playbackCheckSilentTimeline(program: UInt8 = 0, finalTick: Tick = 4800) -> PlaybackTimeline {
    let file = MidiFile(division: 24, chunks: [
        MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 4800),
        MidiChunk(events: [.channel(tick: 0, status: 0xC0, data0: program),
                           .channel(tick: finalTick, status: 0xB0, data0: 7, data1: 100)], endTick: 4800),
        MidiChunk(events: [.channel(tick: 0, status: 0xC1, data0: 1)], endTick: 4800),
    ])
    return PlaybackTimeline.build(file: file, sampleRate: playbackCheckSampleRate)
}

// Engine channel-status masks — Clang macros do not cross the Swift module
// re-export, so they are restated with provenance: pinned poryaaaa
// m4a_engine.h:23-32 (CHN_STOP 0x40, CHN_IEC 0x04, CHN_ENV_MASK 0x03;
// CHN_ON is CHN_START 0x80 plus their union).
internal let playbackCheckChannelStop: UInt8 = 0x40
internal let playbackCheckChannelOn: UInt8 = 0x80 | 0x40 | 0x04 | 0x03

internal final class PlaybackCheckEngine {
    let handle: OpaquePointer
    let pointer: UnsafeMutablePointer<M4AEngine>

    init?() {
        guard let handle = pdc_playback_engine_create(playbackCheckSampleRate),
              let rawPointer = pdc_playback_engine_pointer(handle) else {
            return nil
        }
        self.handle = handle
        pointer = rawPointer.assumingMemoryBound(to: M4AEngine.self)
    }

    deinit {
        pdc_playback_engine_destroy(handle)
    }
}

internal func playbackCheckPcmKeys(_ engine: UnsafeMutablePointer<M4AEngine>) -> [UInt8] {
    var keys: [UInt8] = []
    withUnsafePointer(to: &engine.pointee.pcmChannels) { storage in
        let channels = UnsafeRawPointer(storage).assumingMemoryBound(to: M4APCMChannel.self)
        let count = MemoryLayout.size(ofValue: storage.pointee) /
            MemoryLayout<M4APCMChannel>.stride
        for index in 0..<count {
            let channel = channels[index]
            if channel.status & playbackCheckChannelOn != 0 &&
                channel.status & playbackCheckChannelStop == 0 {
                keys.append(channel.midiKey)
            }
        }
    }
    return keys.sorted()
}

internal func renderPlaybackCheckFrames(_ sequencer: inout Sequencer,
                          engine: UnsafeMutablePointer<M4AEngine>,
                          timeline: PlaybackTimeline, frames: UInt64) {
    var rendered: UInt64 = 0
    var left = [Float](repeating: 0, count: 512)
    var right = [Float](repeating: 0, count: 512)
    while rendered < frames {
        let count = Int(min(UInt64(left.count), frames - rendered))
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                sequencer.render(
                    engine: engine, timeline: timeline,
                    left: UnsafeMutableBufferPointer(start: leftBuffer.baseAddress, count: count),
                    right: UnsafeMutableBufferPointer(start: rightBuffer.baseAddress, count: count),
                    looping: false, muteMask: 0)
            }
        }
        rendered += UInt64(count)
    }
}

internal func playbackCheckReplacementSong(replacement: Bool, program: UInt8 = 0) -> MidiFile {
    var events = [
        MidiEvent.channel(tick: 0, status: 0xC0, data0: program),
        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 60),
    ]
    if replacement {
        events.append(.channel(tick: 8, status: 0x90, data0: 67, data1: 100))
        events.append(.channel(tick: 14, status: 0x80, data0: 67))
        events = events.enumerated().sorted {
            $0.element.tick == $1.element.tick ? $0.offset < $1.offset : $0.element.tick < $1.element.tick
        }.map(\.element)
    }
    return MidiFile(division: playbackCheckDivision, chunks: [
        MidiChunk(events: [.meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20])],
                  endTick: 48),
        MidiChunk(events: events, endTick: 48),
    ])
}

internal func playbackCheckCgbKeys(_ engine: UnsafeMutablePointer<M4AEngine>) -> [UInt8] {
    var keys: [UInt8] = []
    withUnsafePointer(to: &engine.pointee.cgbChannels) { storage in
        let channels = UnsafeRawPointer(storage).assumingMemoryBound(to: M4ACGBChannel.self)
        let count = MemoryLayout.size(ofValue: storage.pointee) /
            MemoryLayout<M4ACGBChannel>.stride
        for index in 0..<count {
            let channel = channels[index]
            if channel.status & playbackCheckChannelOn != 0 &&
                channel.status & playbackCheckChannelStop == 0 {
                keys.append(channel.midiKey)
            }
        }
    }
    return keys.sorted()
}
