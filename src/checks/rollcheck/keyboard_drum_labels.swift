import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore

@MainActor
func checkDrumPadLabels(_ report: CheckReport) {
    let id = "timelinepan/TimelinePanTest::drumGutterLabelsAndHover"
    guard let scratch = CheckEnvironment.fixtureRoot else {
        report.fail(id, "missing staged project fixtures")
        return
    }
    let fixture = scratch
    do {
        let service = ProjectService()
        let session = try runBlocking {
            try await service.open(root: fixture)
            return try await DocumentSession.open(
                service: service, label: "mus_route101", sampleRate: 48_000)
        }
        guard session.bankSlots.indices.contains(11),
              let melodic = session.document.addTrack(voice: 0),
              let track = session.document.addTrack(voice: 11) else {
            report.fail(id, "the real drum bank and a writable track are required")
            return
        }
        session.selectPrimaryTrack(track)
        let grid = PianoGrid(session: session)
        grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
        session.mutateCamera { camera in
            _ = camera.setVScroll(Double(camera.projection.row(forPitch: 37)) * camera.snapshot.keyHeight
                                  - camera.snapshot.rollHeight / 2)
        }
        grid.refreshFromSession()
        let camera = session.camera
        let rowHeight = camera.snapshot.keyHeight
        let projection = camera.projection
        let labels = grid.scene.pianoKeyboardTextModel.asArray
        func record(_ pitch: Int) -> SceneText? {
            guard let top = projection.contentRowTop(
                projection.row(forPitch: pitch), keyHeight: rowHeight, dpr: grid.devicePixelRatio)
            else { return nil }
            return grid.scene.pianoKeyboardTextModel.asArray.first {
                $0.labelRect["y"] as? Double == top
            }
        }
        let names = session.bankSlots[11].drumPadNames
        report.expect(names?.count == 128 && names?[37] == "fixture_named_pad_long_label_123",
                      cppID: id, message: "A036 the loaded bank publishes detached indexed pad names")
        report.expect(labels.count == projection.visibleRowCount,
                      cppID: id, message: "A061 the drum keyboard labels every projected pitch")
        report.expect(record(36)?.labelText == "fixture_pluck",
                      cppID: id, message: "A036 the first named sample pad displays its full name")
        let long = record(37)
        report.expect(long?.labelText == "fixture_named_pad_long_label_123",
                      cppID: id, message: "A038 the full long drum-pad name is a fixed keyboard label")
        report.expect(record(39)?.labelText == GridScene.keyName(39),
                      cppID: id, message: "A044 an unnamed drum pad displays its pitch name")
        let inset = grid.metrics.keyLabelRightInset
        let advance = grid.typography?.keyLabelAdvance("fixture_named_pad_long_label_123") ?? 0
        let expectedWidth = max(grid.metrics.keyboardWidth - inset, advance + inset)
        report.expect((long?.labelRect["width"] as? Double) == expectedWidth
                          && expectedWidth > grid.metrics.keyboardWidth, cppID: id,
                      message: "A039 the long label width includes measured text and inset")
        report.expect(long?.labelRect["x"] as? Double == 0, cppID: id,
                      message: "A041 the long label starts at the keyboard origin")
        let row = projection.row(forPitch: 37)
        guard let top = projection.contentRowTop(
                  row, keyHeight: rowHeight, dpr: grid.devicePixelRatio),
              let bottom = projection.contentRowBottom(
                  row, keyHeight: rowHeight, dpr: grid.devicePixelRatio) else {
            report.fail(id, "the loaded pad has no projected row")
            return
        }
        report.expect(long?.labelRect["y"] as? Double == top, cppID: id,
                      message: "A042 the long label starts at the projected row top")
        report.expect(long?.labelRect["height"] as? Double == bottom - top,
                      cppID: id, message: "A043 the long label fills the projected row height")
        report.expect(record(38)?.labelText == "fixture_drum", cppID: id,
                      message: "A061 the adjacent sample pad retains its loaded name")
        grid.updateHover(x: 0, y: (top + bottom) / 2 - camera.snapshot.scrollY)
        let chip = grid.scene
        report.expect(chip.hoverChipText == "fixture_named_pad_long_label_123",
                      cppID: id, message: "A038 the hover chip shows the same full pad name")
        report.expect(chip.hoverChipRect["width"] as? Double
                          == (grid.typography?.chipAdvance("fixture_named_pad_long_label_123") ?? 0)
                              + grid.metrics.chipHPadding,
                      cppID: id, message: "A039 the full hover chip has measured text width")
        grid.setTrack(index: melodic)
        let expectedMelodic = (0..<projection.visibleRowCount).compactMap {
            projection.visiblePitch(at: $0)
        }.filter { $0 % 12 == 0 }.map(GridScene.keyName)
        let melodicLabels = grid.scene.pianoKeyboardTextModel.asArray.map(\.labelText)
        report.expect(melodicLabels == expectedMelodic, cppID: id,
                      message: "A064 a melodic track shows exactly the visible octave-C names")
        report.expect(!melodicLabels.contains("fixture_named_pad_long_label_123"),
                      cppID: id, message: "A065 the accidental drum pad disappears on the melodic track")
        grid.setTrack(index: track)
        report.expect(record(37)?.labelText == "fixture_named_pad_long_label_123",
                      cppID: id, message: "A069 returning to the drum track restores the exact pad name")
        let later = Tick(session.document.ticksPerBeat * 2)
        session.document.writeLane(track: track, lane: .voice, from: later, through: later,
                                   points: [LaneWrite(tick: later, value: 0)])
        grid.refreshFromSession()
        let points = session.document.lanePoints(track: track, lane: .voice)
        func currentProgram(at tick: Tick) -> Int {
            VoiceLanePolicy.slot(firstProgram: session.timeline.tracks[track].firstProgram,
                                 tick: tick, points: points)
        }
        func synchronizedLabel() -> String? {
            grid.reloadVisuals()
            return record(37)?.labelText
        }
        let playhead = SharedPlayheadPresenter()
        playhead.attach(session: session, audio: nil, grid: grid, drawer: nil)
        playhead.setFollowEnabled(false)
        defer { playhead.detach() }
        report.expect(currentProgram(at: 0) == 11 && synchronizedLabel() == names?[37],
                      cppID: id, message: "A079 the initial drum voice still owns pad names after synchronization")
        report.expect(currentProgram(at: 0) == 11
                          && synchronizedLabel() == "fixture_named_pad_long_label_123",
                      cppID: id, message: "A080 the initial program classifies the synchronized pad")
        session.editCursor = later
        grid.refreshCursorPresentation()
        report.expect(currentProgram(at: session.editCursor) == 0,
                      cppID: id, message: "A081 the later edit cursor resolves the melodic program")
        report.expect(currentProgram(at: session.editCursor) == 0
                          && synchronizedLabel() == "fixture_named_pad_long_label_123",
                      cppID: id, message: "A082 a later melodic cursor program keeps the initial drum label")
        session.editCursor = 0
        let playback = later + Tick(session.document.ticksPerBeat)
        playhead.observe(sample: session.timeline.sample(for: playback),
                         transport: SharedPlayheadPolicy.playingTransport)
        report.expect(playhead.playing && playhead.tick >= Double(later),
                      cppID: id, message: "A083 the playing presenter advances past the later program event")
        report.expect(currentProgram(at: TimeDefaults.tick(from: playhead.tick)) == 0,
                      cppID: id, message: "A084 the later playhead resolves the melodic program")
        report.expect(playhead.playing && playhead.tick >= Double(later)
                          && currentProgram(at: TimeDefaults.tick(from: playhead.tick)) == 0
                          && synchronizedLabel() == "fixture_named_pad_long_label_123",
                      cppID: id, message: "A085 a later melodic playhead program keeps the initial drum label")
        playhead.observe(sample: session.timeline.sample(for: 0),
                         transport: SharedPlayheadPolicy.playingTransport)
        report.expect(currentProgram(at: TimeDefaults.tick(from: playhead.tick)) == 11,
                      cppID: id, message: "A086 the reset playhead resolves the original drum program")
        report.expect(playhead.playing && playhead.tick == 0
                          && currentProgram(at: TimeDefaults.tick(from: playhead.tick)) == 11
                          && synchronizedLabel() == "fixture_named_pad_long_label_123",
                      cppID: id, message: "A087 reset playhead keeps the initial drum label")
    } catch {
        report.fail(id, "could not open the loaded fixture bank: \(error)")
    }
}
