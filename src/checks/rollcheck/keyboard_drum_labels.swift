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
        let probe = RollContentProbe(grid)
        func record(_ pitch: Int) -> String? {
            let current = RollContentProbe(grid)
            guard current.rows.contains(where: { $0.pitch == pitch }) else { return nil }
            return current.keyboardNames[pitch] ?? GridScene.keyName(pitch)
        }
        let names = session.bankSlots[11].drumPadNames
        report.expect(names?.count == 128 && names?[37] == "fixture_named_pad_long_label_123",
                      cppID: id, message: "A036 the loaded bank publishes detached indexed pad names")
        report.expect(
            !probe.keyboardNames.isEmpty && probe.rows.count == projection.visibleRowCount,
                      cppID: id, message: "A061 the drum keyboard labels every projected pitch")
        report.expect(
            record(36) == "fixture_pluck",
                      cppID: id, message: "A036 the first named sample pad displays its full name")
        let long = record(37)
        report.expect(
            long == "fixture_named_pad_long_label_123",
                      cppID: id, message: "A038 the full long drum-pad name is a fixed keyboard label")
        report.expect(
            probe.keyboardNames[39] == nil && record(39) == GridScene.keyName(39),
                      cppID: id, message: "A044 an unnamed drum pad displays its pitch name")
        let inset = grid.metrics.keyLabelRightInset
        let advance = grid.typography?.keyLabelAdvance("fixture_named_pad_long_label_123") ?? 0
        let expectedWidth = max(grid.metrics.keyboardWidth - inset, advance + inset)
        report.expect(
            long != nil && probe.drumKeyboard && expectedWidth > grid.metrics.keyboardWidth, cppID: id,
            message:
                "A039 the drum keyboard publishes the long pad name, whose measured label exceeds the keyboard width")
        report.expect(
            probe.keyboardNames[37] == "fixture_named_pad_long_label_123", cppID: id,
            message: "A041 the long pad name is published at its own pitch in the drum keyboard names")
        let row = projection.row(forPitch: 37)
        guard let top = projection.contentRowTop(
                  row, keyHeight: rowHeight, dpr: grid.devicePixelRatio),
              let bottom = projection.contentRowBottom(
                  row, keyHeight: rowHeight, dpr: grid.devicePixelRatio) else {
            report.fail(id, "the loaded pad has no projected row")
            return
        }
        report.expect(
            probe.rows.firstIndex(where: { $0.pitch == 37 }) == row, cppID: id,
            message: "A042 the long pad's published row index equals its projected row")
        report.expect(
            probe.rows.first(where: { $0.pitch == 37 })?.accidentalLane == GridScene.isBlackKey(37),
            cppID: id, message: "A043 the long pad's published row carries its accidental flag for the drum background")
        report.expect(
            record(38) == "fixture_drum", cppID: id,
                      message: "A061 the adjacent sample pad retains its loaded name")
        grid.updateHover(x: 0, y: (top + bottom) / 2 - camera.snapshot.scrollY)
        let chip = grid.scene
        report.expect(chip.hoverChipText == "fixture_named_pad_long_label_123",
                      cppID: id, message: "A038 the hover chip shows the same full pad name")
        report.expect(RollContentProbe(grid).keyboardHighlightRects().count == 1,
                      cppID: id, message: "A040 the hovered pad paints one keyboard highlight record")
        report.expect(chip.hoverChipRect["width"] as? Double
                          == (grid.typography?.chipAdvance("fixture_named_pad_long_label_123") ?? 0)
                              + grid.metrics.chipHPadding,
                      cppID: id, message: "A039 the full hover chip has measured text width")
        grid.setTrack(index: melodic)
        let expectedMelodic = (0..<projection.visibleRowCount).compactMap {
            projection.visiblePitch(at: $0)
        }.filter { $0 % 12 == 0 }.map(GridScene.keyName)
        let melodicProbe = RollContentProbe(grid)
        let melodicLabels =
            melodicProbe.keyboardNames.isEmpty
            ? melodicProbe.rows.map(\.pitch).filter { $0 % 12 == 0 }.map(GridScene.keyName)
            : melodicProbe.rows.map { melodicProbe.keyboardNames[$0.pitch] ?? GridScene.keyName($0.pitch) }
        report.expect(melodicLabels == expectedMelodic, cppID: id,
                      message: "A064 a melodic track shows exactly the visible octave-C names")
        report.expect(!melodicLabels.contains("fixture_named_pad_long_label_123"),
                      cppID: id, message: "A065 the accidental drum pad disappears on the melodic track")
        grid.setTrack(index: track)
        report.expect(
            record(37) == "fixture_named_pad_long_label_123",
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
            return record(37)
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
