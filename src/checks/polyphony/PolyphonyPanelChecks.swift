@testable import PorydawApp
@testable import PorydawAppAudio
import PorydawPlaybackNative

@MainActor
func runPolyphonyPanelChecks(_ report: CheckReport) {
    let id = "swiftcore/PolyphonyPanel::snapshotProjection"
    let panel = PolyphonyPanelPresenter()
    panel.setVisible(showing: true)
    var snapshot = AudioPolySnapshot(maxPcmChannels: 5, invert: true,
        pcm: Array(repeating: AudioPolyChannel(on: false, releasing: false, track: 0, midiKey: 0),
                   count: Int(TOTAL_PCM_CHANNELS)),
        cgb: Array(repeating: AudioPolyChannel(on: false, releasing: false, track: 0, midiKey: 0),
                   count: Int(TOTAL_CGB_CHANNELS)),
        drop: Array(repeating: 0, count: Int(MAX_TRACKS)),
        steal: Array(repeating: 0, count: Int(MAX_TRACKS)),
        tailCut: Array(repeating: 0, count: Int(MAX_TRACKS)),
        eventTotal: 0,
        events: Array(repeating: M4APolyEvent(type: 0, trackIndex: 0, midiKey: 0,
                                              byTrack: 0, program: 0, tick: 0),
                      count: Int(M4A_POLY_EVENT_CAPACITY)))
    snapshot.pcm[0] = AudioPolyChannel(on: true, releasing: false, track: 2, midiKey: 60)
    snapshot.pcm[1] = AudioPolyChannel(on: true, releasing: true, track: 3, midiKey: 64)
    snapshot.pcm[Int(MAX_PCM_CHANNELS)] = AudioPolyChannel(
        on: true, releasing: false, track: 4, midiKey: 72)
    snapshot.cgb[0] = AudioPolyChannel(on: true, releasing: false, track: 1, midiKey: 67)
    snapshot.drop[1] = 1
    snapshot.steal[2] = 2
    snapshot.tailCut[2] = 3
    panel.update(snapshot)
    report.expectEqual(expected: 5, actual: panel.pcm.count, cppID: id, what: "PCM allocation follows the configured limit")
    report.expectEqual(expected: 4, actual: panel.cgb.count, cppID: id, what: "four CGB channels are displayed")
    report.expectEqual(expected: 1, actual: panel.pcm[0].state, cppID: id, what: "sounding PCM has active ink")
    report.expectEqual(expected: 2, actual: panel.pcm[1].state, cppID: id, what: "released PCM has tail ink")
    report.expectEqual(expected: 3, actual: panel.shadowPcm[0].state, cppID: id, what: "lost note has shadow ink")
    report.expect(panel.showingShadow, cppID: id, message: "engine invert snapshot displays shadow pool")
    report.expectEqual(expected: 2, actual: panel.counterCount, cppID: id, what: "only overflowing tracks are listed")
    report.expectEqual(expected: 1, actual: panel.counters[0].dropped, cppID: id, what: "drop counter projects unchanged")
    report.expectEqual(expected: 2, actual: panel.counters[1].cutOff, cppID: id, what: "steal counter projects unchanged")
    report.expectEqual(expected: 3, actual: panel.counters[1].tailCut, cppID: id, what: "tail counter projects unchanged")
    snapshot.steal[2] += 1
    panel.update(snapshot)
    report.expect(panel.counters[1].flash, cppID: id, message: "counter increase highlights its track")
    snapshot.invert = false
    panel.update(snapshot)
    report.expectEqual(expected: 0, actual: panel.shadowPcm.count, cppID: id, what: "normal mode hides shadow allocation")
    report.expect(!panel.showingShadow, cppID: id, message: "normal snapshot hides shadow pool")

    let eventID = "swiftcore/PolyphonyPanel::ringAndJump"
    let oldest = M4APolyEvent(type: 1, trackIndex: 2, midiKey: 60,
                               byTrack: 4, program: 5, tick: 96)
    let newest = M4APolyEvent(type: 0, trackIndex: 1, midiKey: 67,
                               byTrack: 1, program: 0, tick: UInt32.max)
    snapshot.events[0] = oldest
    snapshot.events[1] = newest
    snapshot.eventTotal = 2
    panel.update(snapshot)
    report.expectEqual(expected: 2, actual: panel.eventCount, cppID: eventID, what: "ring drains oldest first")
    report.expect(panel.events[0].text.contains("live") && panel.events[0].text.contains("dropped"),
                  cppID: eventID, message: "newest live drop appears first")
    report.expect(panel.events[1].text.contains("2:1.0")
        && panel.events[1].text.contains("Trk 3")
        && panel.events[1].text.contains("C4")
        && panel.events[1].text.contains("cut off by Trk 5"),
        cppID: eventID, message: "positioned steal formats bar beat track and key")
    var jumped: (UInt32, Int, Int, Double)?
    panel.onJump = { tick, track, key, dpr in jumped = (tick, track, key, dpr) }
    panel.activateEvent(index: 0, devicePixelRatio: 2)
    report.expect(jumped == nil, cppID: eventID, message: "live sentinel cannot jump")
    panel.activateEvent(index: 1, devicePixelRatio: 2)
    report.expect(jumped?.0 == 96 && jumped?.1 == 2 && jumped?.2 == 60 && jumped?.3 == 2,
                  cppID: eventID, message: "positioned row jumps to the precise note")

    snapshot.eventTotal = 1
    snapshot.events[0] = oldest
    panel.update(snapshot)
    report.expectEqual(expected: 1, actual: panel.eventCount, cppID: eventID,
                       what: "smaller ring total rebases an old run")
    for burst in 0..<10 {
        for offset in 0..<60 {
            let index = burst * 60 + offset + 1
            snapshot.events[index % snapshot.events.count] = M4APolyEvent(
                type: 0, trackIndex: 0, midiKey: 60, byTrack: 0, program: 0,
                tick: UInt32(index))
        }
        snapshot.eventTotal = UInt32((burst + 1) * 60 + 1)
        panel.update(snapshot)
    }
    report.expectEqual(expected: 500, actual: panel.eventCount, cppID: eventID,
                       what: "ten 60-event bursts retain only the latest 500")
    report.expectEqual(expected: Double(600), actual: panel.events[0].tick, cppID: eventID,
                       what: "newest retained event is first")

    let invertID = "swiftcore/PolyphonyPanel::invertVisibilityGate"
    do {
        let audio = try NativeAudio()
        panel.attach(audio: audio)
        panel.setVisible(showing: false)
        panel.setInvertChecked(checked: true)
        report.expect(!audio.polyDebugInvert && panel.invertChecked,
                      cppID: invertID, message: "hidden checkbox retains state without inverting audio")
        panel.setVisible(showing: true)
        report.expect(audio.polyDebugInvert, cppID: invertID,
                      message: "reopening checked panel enables audio invert")
        panel.setVisible(showing: false)
        report.expect(!audio.polyDebugInvert && panel.invertChecked,
                      cppID: invertID, message: "closing panel suspends invert but remembers checkbox")
        panel.setVisible(showing: true)
        panel.setInvertChecked(checked: false)
        report.expect(!audio.polyDebugInvert, cppID: invertID,
                      message: "unchecking an open panel disables renderer invert")
    } catch {
        report.fail(invertID, "audio device initialization failed: \(error)")
    }
}
