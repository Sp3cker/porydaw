import Foundation
import PorydawApp
import PorydawCore
import PorydawAppCommands

@MainActor
func checkRulerSeekEmission(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::rulerSeekEmission"
    let palette = GridPalette()
    let grid = PianoGrid(session: session, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: palette)
    defer { automation.detach() }
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    let previousTrack = session.selectedTrack
    if previousTrack == nil { session.selectPrimaryTrack(0) }
    defer { session.selectedTrack = previousTrack }
    let previousCursor = session.editCursor
    defer { session.editCursor = previousCursor }
    defer { automation.clearTimeSelection(); menu.close(); menu.cancelSweep() }
    let primary = session.selectedTrack ?? 0
    automation.clearTimeSelection()
    menu.close()
    let cell = max(1, grid.snapTicks)
    let anchor = Tick(grid.snapTickDown(Double(72)))
    let farTick = anchor + Tick(cell * 4)
    let atAnchor = session.camera.contentX(tick: Double(anchor))
    let atFar = session.camera.contentX(tick: Double(farTick))
    var outside = farTick + Tick(cell)
    var steps = 0
    while Tick(grid.snapTickDown(Double(outside))) != outside && steps < 1024 {
        outside = outside + 1
        steps += 1
    }
    let playhead = SharedPlayheadPresenter()
    playhead.attach(session: session, audio: nil, grid: grid, drawer: nil)
    playhead.setFollowEnabled(false)
    playhead.observe(sample: session.timeline.sample(for: anchor), transport: 0)
    let playbackTick = playhead.tick
    defer { playhead.detach() }
    session.editCursor = anchor
    menu.beginSweep(contentX: session.camera.contentX(tick: Double(outside)), pointerY: 0)
    menu.endSweep(contentX: session.camera.contentX(tick: Double(outside)))
    playhead.refreshProjection()
    report.expect(
        session.editCursor == outside && playhead.tick == playbackTick, cppID: id,
        message: "a ruler tap commits the exact snapped anchor without moving playback")
    let start = anchor
    let end = outside
    automation.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: start, endTick: end), scope: .tracks([primary])))
    session.editCursor = anchor
    openRulerMenu(menu, at: session.camera.contentX(tick: Double(end) + 0.5))
    playhead.refreshProjection()
    report.expect(
        session.editCursor == end && playhead.tick == playbackTick, cppID: id,
        message: "an outside press commits the exact snapped end tick without moving playback")
    let chipOff = end + 1
    session.document.setTimeSignature(tick: chipOff, numerator: 7, denominatorPower: 2)
    automation.clearTimeSelection()
    openRulerMenu(menu, at: session.camera.contentX(tick: Double(chipOff)))
    playhead.refreshProjection()
    report.expect(
        session.editCursor == chipOff && playhead.tick == playbackTick, cppID: id,
        message: "a chip press commits the exact chip tick without moving playback")
    menu.close()
    session.document.deleteTimeSignature(at: chipOff)
    automation.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: start, endTick: end), scope: .tracks([primary])))
    openRulerMenu(menu, at: session.camera.contentX(tick: Double(end - 1)))
    menu.beginSweep(contentX: atAnchor, pointerY: 0)
    menu.updateSweep(contentX: atFar)
    menu.endSweep(contentX: atFar)
    menu.cancelSweep()
    automation.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: start, endTick: end), scope: .tracks([primary])))
    menu.openTimeSelection(contentX: session.camera.contentX(tick: Double((start + end) / 2)))
    automation.clearTimeSelection()
    _ = menu.activate(actionId: 6)
    playhead.refreshProjection()
    report.expect(
        session.editCursor == chipOff && playhead.tick == playbackTick, cppID: id,
        message: "inside presses, sweeps, cancels and menu commands preserve cursor and playback")
    menu.close()
    let sample = session.timeline.sample(for: end)
    report.expect(
        abs(session.timeline.tick(for: sample) - Double(end)) < 0.001, cppID: id,
        message: "the timeline inverts the sought sample back to the exact tick")
    _ = playhead.observe(sample: sample, transport: 0)
    report.expect(
        playhead.tick == Double(end), cppID: id,
        message: "the shared playhead presents the sought tick from its sample")
}

@MainActor
func checkGridLoopCommandArms(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::gridLoopCommandArms"
    let grid = PianoGrid(session: session, palette: GridPalette())
    let originalStart = session.timeline.loopStartTick
    let originalEnd = session.timeline.loopEndTick
    let previousCursor = session.editCursor
    defer {
        session.editCursor = previousCursor
        session.document.setLoop(
            end: false,
            tick: originalStart == TimeDefaults.noTick
                ? nil : Int64(originalStart))
        session.document.setLoop(
            end: true,
            tick: originalEnd == TimeDefaults.noTick
                ? nil : Int64(originalEnd))
    }
    session.document.setLoop(end: false, tick: nil)
    session.document.setLoop(end: true, tick: nil)
    report.expect(
        grid.commandAvailable(command: EditCommand.setLoopStart.rawValue),
        cppID: id, message: "the mounted grid enables Set Loop Start without markers")
    report.expect(
        grid.commandAvailable(command: EditCommand.setLoopEnd.rawValue),
        cppID: id, message: "the mounted grid enables Set Loop End without markers")
    report.expect(
        !grid.commandAvailable(command: EditCommand.removeLoop.rawValue),
        cppID: id, message: "the mounted grid disables Remove Loop without markers")
    let startTick: Tick = 72
    let endTick: Tick = 96
    grid.setEditCursorTick(tick: Int(startTick))
    grid.performCommand(command: EditCommand.setLoopStart.rawValue)
    report.expect(
        session.timeline.loopStartTick == startTick, cppID: id,
        message: "the grid Set Loop Start arm writes at the committed edit cursor")
    report.expect(
        grid.commandAvailable(command: EditCommand.removeLoop.rawValue),
        cppID: id, message: "the mounted grid enables Remove Loop when one marker exists")
    grid.setEditCursorTick(tick: Int(endTick))
    grid.performCommand(command: EditCommand.setLoopEnd.rawValue)
    report.expect(
        session.timeline.loopEndTick == endTick, cppID: id,
        message: "the grid Set Loop End arm writes at the committed edit cursor")
    grid.performCommand(command: EditCommand.removeLoop.rawValue)
    report.expect(
        session.timeline.loopStartTick == TimeDefaults.noTick
            && session.timeline.loopEndTick == TimeDefaults.noTick,
        cppID: id, message: "the grid Remove Loop arm clears both markers")
    _ = session.document.history.undoDocument()
    report.expect(
        session.timeline.loopStartTick == TimeDefaults.noTick
            && session.timeline.loopEndTick == endTick, cppID: id,
        message: "the grid Remove Loop arm records a separate end-marker undo")
    _ = session.document.history.undoDocument()
    report.expect(
        session.timeline.loopStartTick == startTick
            && session.timeline.loopEndTick == endTick, cppID: id,
        message: "the grid Remove Loop arm records a separate start-marker undo")
}
