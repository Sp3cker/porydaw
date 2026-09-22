import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

private let chromeGapID = "swiftrollgated/SwiftRollGatedTest::chromeRasterParity"
private let clipboardGapID =
    "swiftrollgated/SwiftRollGatedTest::hostClipboardRoundTripAndReplacement"
private let drawerParityGapID =
    "swiftrollgated/SwiftRollGatedTest::drawerAutomationHoverRaster"
private let gestureGapID =
    "swiftrollgated/SwiftRollGatedTest::focusedGridCommandRouting"

private func gatedComposite(_ foreground: String, over background: String) -> (Int, Int, Int) {
    let fg = PaletteMath.channels(foreground)
    let bg = PaletteMath.channels(background)
    let alpha = fg.a
    let blend: (Int, Int) -> Int = { channel, base in
        (channel * alpha + base * (255 - alpha) + 127) / 255
    }
    return (blend(fg.r, bg.r), blend(fg.g, bg.g), blend(fg.b, bg.b))
}

private func gatedDistinct(_ lhs: (Int, Int, Int), _ rhs: (Int, Int, Int)) -> Bool {
    abs(lhs.0 - rhs.0) > 2 || abs(lhs.1 - rhs.1) > 2 || abs(lhs.2 - rhs.2) > 2
}

private final class GatedClipboardReadBox {
    var data: Data?
}

private func gatedClipboardData() -> Data? {
    let box = GatedClipboardReadBox()
    let context = Unmanaged.passUnretained(box).toOpaque()
    guard pd_clipboard_read(context, { rawContext, bytes, count in
        guard let rawContext, let bytes else { return }
        Unmanaged<GatedClipboardReadBox>.fromOpaque(rawContext)
            .takeUnretainedValue().data = Data(bytes: bytes, count: count)
    }) else { return nil }
    return box.data
}

@MainActor
func drawerSwiftRollGatedPortableGaps(_ report: CheckReport,
                                      suite: DocumentSession,
                                      service: ProjectService) {
    let palette = GridPalette()
    let natural = PaletteMath.channels(palette.rollBackground)
    let accidental = PaletteMath.channels(palette.accidentalLane)
    let naturalRGB = (natural.r, natural.g, natural.b)
    let accidentalRGB = (accidental.r, accidental.g, accidental.b)
    let barNatural = gatedComposite(palette.gridLineBar, over: palette.rollBackground)
    let barAccidental = gatedComposite(palette.gridLineBar, over: palette.accidentalLane)
    report.expect(gatedDistinct(barNatural, naturalRGB)
        && gatedDistinct(barAccidental, accidentalRGB), cppID: chromeGapID,
                  message: "A031 bar role remains distinguishable over both row roles")
    let beatNatural = gatedComposite(palette.gridLineBeat, over: palette.rollBackground)
    let beatAccidental = gatedComposite(palette.gridLineBeat, over: palette.accidentalLane)
    report.expect(gatedDistinct(beatNatural, naturalRGB)
        && gatedDistinct(beatAccidental, accidentalRGB), cppID: chromeGapID,
                  message: "A032 beat role remains distinguishable over both row roles")

    let savedClipboard = drawerAutomationPorydawSelectionClipboardState()
    defer { savedClipboard.restore() }
    _ = pd_clipboard_write(nil, 0)
    let clipboardFile = MidiFile(chunks: [
        MidiChunk(events: [
            .channel(status: 0x90, data0: 60, data1: 91),
            .channel(tick: 24, status: 0x80, data0: 60),
            .channel(tick: 48, status: 0x90, data0: 67, data1: 73),
            .channel(tick: 60, status: 0x80, data0: 67),
        ], endTick: 96),
    ])
    let clipboardDocument = SongDocument(
        file: clipboardFile, config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    let clipboardSession = DocumentSession(
        document: clipboardDocument, service: service, lease: suite.bankLease,
        slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName,
        sampleRate: 48_000)
    let clipboardGrid = PianoGrid(session: clipboardSession)
    clipboardGrid.configureViewport(width: 800, height: 720, fontPx: 13, dpr: 1)
    let sourceNotes = clipboardDocument.notes(in: 0).sorted { $0.tick < $1.tick }
    report.expect(sourceNotes.count == 2
        && sourceNotes.allSatisfy { $0.track == sourceNotes[0].track },
                  cppID: clipboardGapID,
                  message: "A007 both source notes retain one track membership")
    guard sourceNotes.count == 2 else {
        report.fail(clipboardGapID, "clipboard fixture did not expose two source notes")
        return
    }
    let sourceRects = sourceNotes.compactMap { note in
        (0..<clipboardGrid.scene.pianoNoteFills.count)
            .map { clipboardGrid.scene.pianoNoteFills[$0] }
            .first { $0.primitiveName == "gridNote_\(note.id.rawValue)" }
    }
    guard sourceRects.count == 2 else {
        report.fail(clipboardGapID, "production grid did not publish both source rectangles")
        return
    }
    for index in sourceRects.indices {
        let rect = sourceRects[index]
        let modifiers = index == 0 ? 0 : DrawerModifiers.shiftBit
        clipboardGrid.beginPointer(
            x: rect.x + rect.width / 2, y: rect.y + rect.height / 2,
            modifiers: modifiers)
        clipboardGrid.endPointer(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
    }
    clipboardGrid.performCommand(command: EditCommand.copy.rawValue)
    guard let bytes = gatedClipboardData(),
          let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
          let tracks = object["tracks"] as? [[String: Any]],
          let copiedTrack = tracks.first,
          let notes = copiedTrack["notes"] as? [[String: Any]] else {
        report.fail(clipboardGapID, "A030 production Copy did not write its JSON object schema")
        return
    }
    report.pass(clipboardGapID, row: "A030 production Copy payload is a JSON object")
    report.expectEqual(1, (object["format"] as? NSNumber)?.intValue,
                       cppID: clipboardGapID, what: "A031 format is version 1")
    report.expectEqual(Int(clipboardDocument.ticksPerBeat),
                       (object["ticksPerBeat"] as? NSNumber)?.intValue,
                       cppID: clipboardGapID, what: "A032 ticksPerBeat is preserved")
    report.expectEqual(0, (object["span"] as? NSNumber)?.intValue,
                       cppID: clipboardGapID, what: "A033 note-only selection span is zero")
    report.expectEqual(false, (object["wholeLane"] as? NSNumber)?.boolValue,
                       cppID: clipboardGapID, what: "A034 note payload is not a whole lane")
    report.expectEqual(0, (object["lanes"] as? [Any])?.count,
                       cppID: clipboardGapID, what: "A035 note payload has no lanes")
    report.expectEqual(0, (object["tempo"] as? [Any])?.count,
                       cppID: clipboardGapID, what: "A036 note payload has no tempo points")
    report.expectEqual(1, tracks.count, cppID: clipboardGapID,
                       what: "A037 payload has one source track")
    report.expectEqual(0, (copiedTrack["track"] as? NSNumber)?.intValue,
                       cppID: clipboardGapID, what: "A038 payload preserves source track")
    report.expectEqual(2, notes.count, cppID: clipboardGapID,
                       what: "A039 payload has both selected notes")
    let noteShapes = notes.map {
        "\(($0["relTick"] as? NSNumber)?.intValue ?? -1):"
            + "\(($0["key"] as? NSNumber)?.intValue ?? -1):"
            + "\(($0["duration"] as? NSNumber)?.intValue ?? -1):"
            + "\(($0["velocity"] as? NSNumber)?.intValue ?? -1)"
    }
    report.expect(noteShapes.contains("0:60:24:91"), cppID: clipboardGapID,
                  message: "A040 payload contains the first selected note")
    report.expect(noteShapes.contains("48:67:12:73"), cppID: clipboardGapID,
                  message: "A041 payload contains the second selected note")

    let automation = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(24, 64)])
    automation.activate(automation.panLane)
    let revision = automation.document.revision
    _ = automation.page.pointerMove(x: automation.x(80), y: 60, buttons: 0, modifiers: 0)
    report.expectEqual(revision, automation.document.revision, cppID: drawerParityGapID,
                       what: "A011 background hover leaves revision unchanged")
    automation.page.pointerLeave()
    report.expectEqual(revision, automation.document.revision, cppID: drawerParityGapID,
                       what: "A015 hover-away leaves revision unchanged")
    _ = automation.page.pointerMove(x: automation.x(24),
                                    y: automation.y(automation.panLane, 64),
                                    buttons: 0, modifiers: 0)
    report.expectEqual(revision, automation.document.revision, cppID: drawerParityGapID,
                       what: "A021 written-node hover leaves revision unchanged")
    automation.page.pointerLeave()
    report.expectEqual(revision, automation.document.revision, cppID: drawerParityGapID,
                       what: "A024 complete node-hover sequence leaves revision unchanged")

    let tracks = MidiFile(chunks: [
        MidiChunk(events: [
            .channel(status: 0x90, data0: 60, data1: 90),
            .channel(tick: 24, status: 0x80, data0: 60),
        ], endTick: 96),
        MidiChunk(events: [
            .channel(status: 0x91, data0: 67, data1: 90),
            .channel(tick: 24, status: 0x81, data0: 67),
        ], endTick: 96),
    ])
    let trackDocument = SongDocument(
        file: tracks, config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    let trackSession = DocumentSession(
        document: trackDocument, service: service, lease: suite.bankLease,
        slots: suite.bankSlots, dirty: false, loadName: suite.bankLoadName,
        sampleRate: 48_000)
    let grid = PianoGrid(session: trackSession)
    grid.setTrack(index: 1)
    let projected = (try? JSONSerialization.jsonObject(
        with: Data(grid.noteSummary.utf8))) as? [[String: Any]]
    report.expect(grid.trackIndex == 1 && grid.renderedNoteCount == projected?.count
        && projected?.isEmpty == false
        && projected?.allSatisfy { ($0["track"] as? NSNumber)?.intValue == 1 } == true,
                  cppID: gestureGapID,
                  message: "A066 track switch publishes only the new track's notes")

    grid.performCommand(command: EditCommand.pencilMode.rawValue)
    report.expect(grid.pencilMode, cppID: gestureGapID,
                  message: "A085 Pencil Mode command publishes enabled state")
    let repeatDecision = grid.routeKey(command: EditCommand.pencilMode.rawValue, autoRepeat: true)
    report.expect(repeatDecision == EditKeyDecision.consume.rawValue && grid.pencilMode,
                  cppID: gestureGapID,
                  message: "A086 auto-repeat is consumed without toggling pencil state")
    grid.performCommand(command: EditCommand.pencilMode.rawValue)
    report.expect(!grid.pencilMode, cppID: gestureGapID,
                  message: "A092 second Pencil Mode command toggles state off")
    grid.performCommand(command: EditCommand.pencilMode.rawValue)
    grid.performCommand(command: EditCommand.pencilMode.rawValue)
    report.expect(!grid.pencilMode, cppID: gestureGapID,
                  message: "A095 paired pencil toggles restore the prior state")
}

private let sessionReopenGapID =
    "swiftrollgated/SwiftRollGatedTest::failedReopenLeavesEmptyStripAndSurfacesError"

@MainActor
private func gatedWait(timeout: TimeInterval = 15,
                       until predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate() {
        if Date() >= deadline { return false }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    return true
}

@MainActor
func drawerSwiftRollGatedSessionReopenSurvival(_ report: CheckReport,
                                               suite: DocumentSession) {
    let source = suite.document.source
    guard !source.label.isEmpty, !source.midiPath.isEmpty else {
        report.fail(sessionReopenGapID, "fixture document has no reopenable source")
        return
    }
    var project = URL(fileURLWithPath: source.midiPath)
    for _ in 0..<4 { project.deleteLastPathComponent() }
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("porydaw-reopen-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.copyItem(at: project, to: temporary)
    } catch {
        report.fail(sessionReopenGapID, "could not stage private reopen project: \(error)")
        return
    }
    defer { try? FileManager.default.removeItem(at: temporary) }

    let midi = temporary.appendingPathComponent(
        "sound/songs/midi/\(source.label).mid")
    let backup = midi.appendingPathExtension("reopen-backup")
    let app = ApplicationSession()
    app.componentComplete()
    func closeApp() {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    app.openProjectAndSong(path: temporary.path, label: source.label)
    let initiallyOpen = gatedWait { app.projectOpen && app.songOpen }
    report.expect(initiallyOpen, cppID: sessionReopenGapID,
                  message: "A003 project and song reach open state")
    guard initiallyOpen else {
        closeApp()
        return
    }

    do {
        try FileManager.default.moveItem(at: midi, to: backup)
    } catch {
        closeApp()
        report.fail(sessionReopenGapID, "could not stage reopen failure: \(error)")
        return
    }
    app.openSong(label: source.label)
    let failedCleanly = gatedWait(timeout: 5) {
        !app.songOpen && app.songTabs.tabCount == 0
    }
    do {
        try FileManager.default.moveItem(at: backup, to: midi)
    } catch {
        closeApp()
        report.fail(sessionReopenGapID, "could not restore staged song: \(error)")
        return
    }
    guard failedCleanly else {
        closeApp()
        report.fail(sessionReopenGapID, "failed reopen did not leave an empty closed strip")
        return
    }
    app.openSong(label: source.label)
    let reopened = gatedWait {
        app.songOpen && app.songTabs.tabCount == 1
    }
    report.expect(reopened, cppID: sessionReopenGapID,
                  message: "A031 restored song reopens and republishes songOpen")
    closeApp()
}
