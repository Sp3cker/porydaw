import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore

@MainActor
func checkTimeSelectionHighlights(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardTimeSelectionShortcuts"
    withKeyboardSeed(report, session: session, id: id) { grid, seed in
        guard session.document.canAddTrack, let other = session.document.addTrack(voice: 0),
              other != seed.track else {
            report.fail(id, "could not provision the other track for time-scoped highlights")
            return
        }
        report.expect(session.document.engineTracks.usedTrackCount > other,
                      cppID: id, message: "a distinct second track exists for time-scoped highlights")
        let snapshot = session.camera.snapshot
        let projection = session.camera.projection
        guard let ghostPitch = (24...115).first(where: { pitch in
            let row = projection.row(forPitch: pitch)
            guard row != PitchProjection.hiddenRow,
                  let top = projection.rowTop(row, keyHeight: snapshot.keyHeight,
                                              scrollY: snapshot.scrollY,
                                              dpr: grid.devicePixelRatio),
                  let bottom = projection.rowBottom(row, keyHeight: snapshot.keyHeight,
                                                    scrollY: snapshot.scrollY,
                                                    dpr: grid.devicePixelRatio),
                  top >= 0, bottom <= snapshot.rollHeight else { return false }
            return !session.document.notes(in: other).contains { note in
                Int(note.pitch) == pitch && UInt64(note.tick) < UInt64(seed.tick + seed.duration)
                    && (note.endTick ?? UInt64.max) > UInt64(seed.tick)
            }
        }), let ids = try? session.document.addNotes([
            NewNote(track: other, tick: seed.tick, pitch: UInt8(ghostPitch),
                    duration: seed.duration, velocity: 100)
        ]), let ghostID = ids.first else {
            report.fail(id, "could not seed the time-scoped ghost note")
            return
        }
        defer { session.document.deleteNotes([ghostID]) }
        grid.refreshFromSession()
        let metrics = GridMetrics(baseFontPx: grid.baseFontPx, dpr: grid.devicePixelRatio,
                                  width: snapshot.viewportWidth, height: snapshot.rollHeight)
        let x0 = session.camera.contentTickX(tick: Double(seed.tick), dpr: grid.devicePixelRatio)
        let x1 = session.camera.contentTickX(tick: Double(seed.tick + seed.duration),
                                            dpr: grid.devicePixelRatio)
        let plainBox = metrics.noteBox(
            camera: session.camera, x0: x0, x1: x1, pitch: seed.pitch)
        let ghostBox = metrics.noteBox(
            camera: session.camera, x0: x0, x1: x1, pitch: ghostPitch)
        guard plainBox.w > 0, plainBox.h > 0, ghostBox.w > 0, ghostBox.h > 0 else {
            report.fail(id, "time-scoped fixtures have no projected boxes")
            return
        }
        report.expect(session.document.note(seed.id).map {
            $0.track == seed.track && $0.tick == seed.tick && Int($0.pitch) == seed.pitch
        } == true, cppID: id, message: "the time-shortcut fixture seeds its covered note")
        session.applyTimeSelection(AutomationTimeSelection(
            range: TimeRange(startTick: seed.tick, endTick: seed.tick + seed.duration),
            scope: .tracks([seed.track, other])))
        grid.refreshTimeSelectionHighlight()
        let covered = RollContentProbe(grid)
        report.expect(
            !covered.ringRects(seed.id).isEmpty
                && covered.note(ghostID)?.ghost == true
                && !covered.ringRects(ghostID).isEmpty,
                      cppID: id,
                      message: "A053/A029 covered notes ring, including the time-scoped ghost")
        report.expect(session.selectedNotes.isEmpty, cppID: id,
                      message: "A054 time-covered notes never leak into the note selection")
        let overlay = covered.overlay
        report.expect(
            overlay.active && overlay.startTick == Int(seed.tick)
                && overlay.endTick == Int(seed.tick + seed.duration) && overlay.selectedTrack == seed.track
                && overlay.scopeTracks.indices.contains(other)
                && overlay.scopeTracks[seed.track] && overlay.scopeTracks[other],
        cppID: id, message: "the covered selected track publishes its range band and edges")
        let bandEnd = seed.tick + seed.duration
        let automation = AutomationPage(baseFontPx: grid.baseFontPx)
        automation.attach(session: session, palette: grid.palette)
        defer { automation.detach() }
        report.expect(automation.consumeSelectionCommand(command: .transposeUp)
                      && session.document.note(seed.id).map { Int($0.pitch) == seed.pitch + 1 } == true,
                      cppID: id, message: "Up over an active time selection transposes the covered notes")
        report.expect(automation.consumeSelectionCommand(command: .nudgeRight)
                      && session.document.note(seed.id).map { $0.tick == seed.tick + seed.snap } == true
                      && session.timeSelection?.range.startTick == seed.tick + seed.snap
                      && session.timeSelection?.range.endTick == bandEnd + seed.snap,
                      cppID: id,
                      message: "Right over an active time selection nudges the covered notes and advances the band start")
        session.applyTimeSelection(AutomationTimeSelection(
            range: TimeRange(startTick: seed.tick, endTick: seed.tick + seed.duration),
            scope: .lanes, tempo: true))
        grid.refreshTimeSelectionHighlight()
        let laneScoped = RollContentProbe(grid)
        report.expect(
            laneScoped.ringRects(seed.id).isEmpty
                && laneScoped.ringRects(ghostID).isEmpty,
                      cppID: id, message: "lane-scoped ranges ring no roll notes")
        session.clearTimeSelection()
        grid.refreshTimeSelectionHighlight()
        let cleared = RollContentProbe(grid)
        report.expect(
            cleared.ringRects(seed.id).isEmpty && !cleared.overlay.active,
                      cppID: id, message: "clearing the range removes every highlight")
    }
}
