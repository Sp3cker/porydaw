import Foundation
import PorydawCore
import PorydawPlaybackNative

/// Owns the immutable C publication and all buffers borrowed through it.
/// Instances are retained and released only through the control-thread ABI.
public final class PlaybackPublication {
    public static func create(
        from timeline: borrowing PlaybackTimeline
    ) -> UnsafeMutablePointer<PdPlaybackData> {
        let publication = PlaybackPublication(timeline: timeline)
        let owner = Unmanaged.passRetained(publication)
        publication.data.pointee.ownerContext = UnsafeRawPointer(owner.toOpaque())
        return publication.data
    }

    let data: UnsafeMutablePointer<PdPlaybackData>

    private let events: UnsafeMutablePointer<PdPlaybackEvent>?
    private let eventCount: Int
    private let tempos: UnsafeMutablePointer<PdPlaybackTempoPoint>?
    private let tempoCount: Int

    private init(timeline: borrowing PlaybackTimeline) {
        eventCount = timeline.events.count
        if eventCount == 0 {
            events = nil
        } else {
            let storage = UnsafeMutablePointer<PdPlaybackEvent>.allocate(capacity: eventCount)
            for index in 0..<eventCount {
                let event = timeline.events[index]
                storage.advanced(by: index).initialize(to: PdPlaybackEvent(
                    sample: event.sample, tick: event.tick, type: event.type,
                    track: event.track, data0: event.data0, data1: event.data1,
                    noteID: event.noteID.rawValue))
            }
            events = storage
        }

        tempoCount = timeline.tempoMap.count
        if tempoCount == 0 {
            tempos = nil
        } else {
            let storage = UnsafeMutablePointer<PdPlaybackTempoPoint>.allocate(capacity: tempoCount)
            for index in 0..<tempoCount {
                let point = timeline.tempoMap[index]
                storage.advanced(by: index).initialize(to: PdPlaybackTempoPoint(
                    tick: point.tick,
                    microsecondsPerQuarterNote: point.microsecondsPerQuarterNote,
                    sampleOrigin: point.sampleOrigin))
            }
            tempos = storage
        }

        data = .allocate(capacity: 1)
        data.initialize(to: PdPlaybackData(
            events: events.map { UnsafePointer($0) }, eventCount: eventCount,
            tempoMap: tempos.map { UnsafePointer($0) }, tempoPointCount: tempoCount,
            sampleRate: timeline.sampleRate, lengthSamples: timeline.lengthSamples,
            loopStartSample: timeline.loopStartSample, loopEndSample: timeline.loopEndSample,
            ticksPerBeat: timeline.ticksPerBeat, lengthTicks: timeline.lengthTicks,
            loopStartTick: timeline.loopStartTick, loopEndTick: timeline.loopEndTick,
            usedTrackCount: UInt32(timeline.usedTrackCount),
            droppedTracks: UInt32(timeline.droppedTracks),
            exactGate: timeline.settings.exactGate,
            extendedClocks: timeline.settings.extendedClocks,
            ownerContext: nil))
    }

    deinit {
        data.deinitialize(count: 1)
        data.deallocate()
        if let events {
            events.deinitialize(count: eventCount)
            events.deallocate()
        }
        if let tempos {
            tempos.deinitialize(count: tempoCount)
            tempos.deallocate()
        }
    }
}

@_cdecl("pd_playback_data_retain")
public func pdPlaybackDataRetain(_ data: UnsafePointer<PdPlaybackData>?) {
    guard let context = data?.pointee.ownerContext else { return }
    _ = Unmanaged<PlaybackPublication>.fromOpaque(
        UnsafeMutableRawPointer(mutating: context)).retain()
}

@_cdecl("pd_playback_data_release")
public func pdPlaybackDataRelease(_ data: UnsafePointer<PdPlaybackData>?) {
    guard let context = data?.pointee.ownerContext else { return }
    Unmanaged<PlaybackPublication>.fromOpaque(
        UnsafeMutableRawPointer(mutating: context)).release()
}

@_cdecl("pd_playback_data_load_file")
public func pdPlaybackDataLoadFile(
    _ path: UnsafePointer<CChar>?, _ sampleRate: Double,
    _ output: UnsafeMutablePointer<UnsafeMutablePointer<PdPlaybackData>?>?,
    _ errorBuffer: UnsafeMutablePointer<CChar>?, _ errorCapacity: Int
) -> Bool {
    output?.pointee = nil
    clearDiagnostic(errorBuffer, capacity: errorCapacity)
    guard let path, let output else {
        writeDiagnostic("missing playback file path or output", to: errorBuffer,
                        capacity: errorCapacity)
        return false
    }

    do {
        let bytes = try Data(contentsOf: URL(fileURLWithPath: String(cString: path)))
        let file = try MidiFile.decode(Array(bytes))
        let timeline = PlaybackTimeline.build(file: file, sampleRate: sampleRate)
        output.pointee = PlaybackPublication.create(from: timeline)
        return true
    } catch {
        writeDiagnostic(String(describing: error), to: errorBuffer, capacity: errorCapacity)
        return false
    }
}

@_cdecl("pd_player_create")
public func pdPlayerCreate() -> UnsafeMutableRawPointer? {
    let player = UnsafeMutablePointer<Sequencer>.allocate(capacity: 1)
    player.initialize(to: Sequencer())
    return UnsafeMutableRawPointer(player)
}

@_cdecl("pd_player_destroy")
public func pdPlayerDestroy(_ handle: UnsafeMutableRawPointer?) {
    guard let handle else { return }
    let player = handle.assumingMemoryBound(to: Sequencer.self)
    player.deinitialize(count: 1)
    player.deallocate()
}

@_cdecl("pd_player_reset")
public func pdPlayerReset(_ handle: UnsafeMutableRawPointer?) {
    guard let handle else { return }
    handle.assumingMemoryBound(to: Sequencer.self).pointee.reset()
}

@_cdecl("pd_player_position")
public func pdPlayerPosition(_ handle: UnsafeRawPointer?) -> UInt64 {
    guard let handle else { return 0 }
    return handle.assumingMemoryBound(to: Sequencer.self).pointee.position
}

@_cdecl("pd_player_seek")
public func pdPlayerSeek(_ handle: UnsafeMutableRawPointer?, _ position: UInt64,
                         _ data: UnsafePointer<PdPlaybackData>?) {
    guard let handle, let data else { return }
    handle.assumingMemoryBound(to: Sequencer.self).pointee.seek(position, data: data)
}

@_cdecl("pd_player_replace")
public func pdPlayerReplace(_ handle: UnsafeMutableRawPointer?, _ position: UInt64,
                            _ data: UnsafePointer<PdPlaybackData>?) {
    guard let handle, let data else { return }
    handle.assumingMemoryBound(to: Sequencer.self).pointee
        .replaceTimeline(position, data: data)
}

@_cdecl("pd_player_chase")
public func pdPlayerChase(_ engine: UnsafeMutablePointer<M4AEngine>?,
                          _ data: UnsafePointer<PdPlaybackData>?, _ position: UInt64) {
    guard let engine, let data else { return }
    Sequencer.chase(engine: engine, data: data, position: position)
}

@_cdecl("pd_player_prime")
public func pdPlayerPrime(_ engine: UnsafeMutablePointer<M4AEngine>?,
                          _ data: UnsafePointer<PdPlaybackData>?, _ position: UInt64) {
    guard let engine, let data else { return }
    Sequencer.primeVoices(engine: engine, data: data, position: position)
}

@_cdecl("pd_player_render")
public func pdPlayerRender(
    _ handle: UnsafeMutableRawPointer?, _ engine: UnsafeMutablePointer<M4AEngine>?,
    _ data: UnsafePointer<PdPlaybackData>?, _ left: UnsafeMutablePointer<Float>?,
    _ right: UnsafeMutablePointer<Float>?, _ frames: Int, _ looping: Bool, _ muteMask: UInt32
) {
    guard frames > 0 else { return }
    guard let handle, let engine, let data, let left, let right else {
        preconditionFailure("pd_player_render requires non-null borrowed pointers")
    }
    handle.assumingMemoryBound(to: Sequencer.self).pointee.render(
        engine: engine, data: data, left: left, right: right, frames: frames,
        looping: looping, muteMask: muteMask)
}

private func clearDiagnostic(_ output: UnsafeMutablePointer<CChar>?, capacity: Int) {
    guard let output, capacity > 0 else { return }
    output[0] = 0
}

private func writeDiagnostic(_ text: String, to output: UnsafeMutablePointer<CChar>?,
                             capacity: Int) {
    guard let output, capacity > 0 else { return }
    let bytes = Array(text.utf8)
    let count = min(bytes.count, capacity - 1)
    for index in 0..<count { output[index] = CChar(bitPattern: bytes[index]) }
    output[count] = 0
}
