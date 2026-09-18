import Foundation
import NativeGridAudio
import QtBridge

struct GridControllerEvent {
    var tick: Int
    var track: Int
    var controller: Int
    var value: Int
}

@MainActor
@QtBridgeable
public final class AudioSession {
    public var ready: Bool = false
    public var playing: Bool = false
    public var playheadTick: Double = 0
    public var sampleRate: Double = 0
    public var backendName: String = "Not initialized"
    public var usingNullBackend: Bool = false
    public var errorText: String = ""

    @QtIgnored private var session: OpaquePointer?

    public init() {
        guard let resources = Bundle.main.resourceURL else {
            errorText = "The application bundle has no audio resource directory."
            return
        }
        let fixture = resources.appendingPathComponent("AudioFixture", isDirectory: true).path
        var error = [CChar](repeating: 0, count: 1024)
        session = fixture.withCString { root in
            error.withUnsafeMutableBufferPointer { buffer in
                sga_create(root, buffer.baseAddress, buffer.count)
            }
        }
        guard let session else {
            errorText = error.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
            return
        }
        sampleRate = sga_sample_rate(session)
        backendName = String(cString: sga_backend_name(session))
        usingNullBackend = sga_using_null_backend(session) != 0
    }

    isolated deinit {
        if let session {
            sga_destroy(session)
        }
    }

    @QtIgnored
    func sync(notes: [GridNote], controllers: [GridControllerEvent]) {
        guard let session else { return }
        let projectedNotes = notes.map {
            SGNote(
                tick: Int64($0.tick), duration: Int64($0.duration),
                track: Int32($0.track), pitch: Int32($0.pitch), velocity: Int32($0.velocity))
        }
        let projectedControllers = controllers.map {
            SGController(
                tick: Int64($0.tick), track: Int32($0.track),
                controller: Int32($0.controller), value: Int32($0.value))
        }
        projectedNotes.withUnsafeBufferPointer { notes in
            projectedControllers.withUnsafeBufferPointer { controllers in
                sga_sync(
                    session, notes.baseAddress, notes.count,
                    controllers.baseAddress, controllers.count)
            }
        }
        ready = true
        refreshTransport()
    }

    public func togglePlayback() {
        guard ready, let session else { return }
        if sga_is_playing(session) != 0 {
            sga_pause(session)
        } else {
            sga_play(session)
        }
        refreshTransport()
    }

    public func stop() {
        guard ready, let session else { return }
        sga_stop(session)
        playing = false
        playheadTick = 0
    }

    public func playFrom(tick: Double) {
        guard ready, let session else { return }
        sga_seek_tick(session, tick)
        sga_play(session)
        refreshTransport()
        playheadTick = tick
    }

    public func refreshTransport() {
        guard let session else { return }
        playing = sga_is_playing(session) != 0
        playheadTick = sga_playhead_tick(session)
    }

    @QtIgnored
    func preview(track: Int, pitch: Int, velocity: Int) {
        guard ready, let session else { return }
        sga_preview(session, Int32(track), Int32(pitch), Int32(velocity))
    }
}
