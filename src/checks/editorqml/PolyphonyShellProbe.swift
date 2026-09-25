import Foundation
@testable import PorydawApp
@testable import PorydawAppAudio
import PorydawPlaybackNative
import QtBridge

/// Qt Quick Test owns an isolated presenter for deterministic widget-baseline captures.
@MainActor
@QtBridgeable
public final class PolyphonyShellProbe: QmlInstantiableStatus {
    public var profileName: String =
        ProcessInfo.processInfo.environment["PORYDAW_POLYPHONY_PROFILE"] ?? ""
    private let fixture = PolyphonyPanelPresenter()
    private var jumpedTick = -1

    public init() {
        fixture.onJump = { [weak self] tick, _, _, _ in
            self?.jumpedTick = Int(tick)
        }
    }
    public func componentComplete() {}

    public func fixturePresenter() -> PolyphonyPanelPresenter {
        jumpedTick = -1
        publishFixture()
        return fixture
    }

    public func lastJumpTick() -> Int { jumpedTick }

    @QtIgnored
    private func publishFixture() {
        var snapshot = AudioPolySnapshot(maxPcmChannels: 5, invert: true,
            pcm: Array(repeating: AudioPolyChannel(on: false, releasing: false, track: 0, midiKey: 0),
                       count: Int(TOTAL_PCM_CHANNELS)),
            cgb: Array(repeating: AudioPolyChannel(on: false, releasing: false, track: 0, midiKey: 0),
                       count: Int(TOTAL_CGB_CHANNELS)),
            drop: Array(repeating: 0, count: Int(MAX_TRACKS)),
            steal: Array(repeating: 0, count: Int(MAX_TRACKS)),
            tailCut: Array(repeating: 0, count: Int(MAX_TRACKS)), eventTotal: 3,
            events: Array(repeating: M4APolyEvent(type: 0, trackIndex: 0, midiKey: 0,
                                                  byTrack: 0, program: 0, tick: 0),
                          count: Int(M4A_POLY_EVENT_CAPACITY)))
        snapshot.pcm[0] = AudioPolyChannel(on: true, releasing: false, track: 2, midiKey: 60)
        snapshot.pcm[Int(MAX_PCM_CHANNELS)] = AudioPolyChannel(on: true, releasing: false,
                                                                track: 4, midiKey: 72)
        snapshot.cgb[0] = AudioPolyChannel(on: true, releasing: false, track: 0, midiKey: 60)
        snapshot.steal[2] = 1
        snapshot.tailCut[2] = 1
        snapshot.drop[1] = 1
        snapshot.events[0] = M4APolyEvent(type: 1, trackIndex: 2, midiKey: 60,
                                           byTrack: 4, program: 5, tick: 96)
        snapshot.events[1] = M4APolyEvent(type: 2, trackIndex: 2, midiKey: 72,
                                           byTrack: 0, program: 5, tick: 216)
        snapshot.events[2] = M4APolyEvent(type: 0, trackIndex: 1, midiKey: 67,
                                           byTrack: 1, program: 0, tick: UInt32.max)
        fixture.update(snapshot)
    }

    /// Read the pinned widget geometry instead of duplicating expected coordinates in QML.
    public func baseline(profile: String, state: String) -> String {
        let path = URL(fileURLWithPath: EditorQmlPaths.testDirectory)
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures/visual/macos-\(profile)/polyphony/\(state).json")
        return (try? String(contentsOf: path, encoding: .utf8)) ?? ""
    }

    public func artifactPath(root: String, profile: String, state: String) -> String {
        URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent("polyphony-\(profile)-\(state).png").path
    }
}
