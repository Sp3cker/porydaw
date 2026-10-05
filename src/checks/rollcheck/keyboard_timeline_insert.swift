import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore
@testable import PorydawDocument

@MainActor
func checkTimelineInsertBlankTimeTracks(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::timelineInsertBlankTimeTracks"
    withKeyboardSeed(report, viewport: viewport, id: id) { grid, seed in
        let start = seed.tick + 2 * seed.snap
        let end = start + seed.snap
        session.document.nudgeNotes([seed.id], byTicks: Int64(2 * seed.snap), byKeys: -10)
        report.expect(
            session.document.note(seed.id).map {
                $0.tick == start && Int($0.pitch) == seed.pitch - 10
            } == true, cppID: id, message: "track insertion seed reaches its shortcut position")
        report.expect(
            session.document.canAddTrack, cppID: id,
            message: "a second track can be provisioned for the insert fixture")
        guard session.document.canAddTrack,
            let otherTrack = session.document.addTrack(voice: 0),
            otherTrack != seed.track
        else {
            report.fail(id, "could not provision the unselected track for blank insertion")
            return
        }
        report.expect(
            session.document.engineTracks.usedTrackCount > otherTrack,
            cppID: id, message: "a distinct second track exists for scoped insertion")
        let otherPitch = (12..<128).first(where: { pitch in
            !session.document.notes(in: otherTrack).contains {
                $0.tick == start && Int($0.pitch) == pitch
            }
        })
        report.expect(
            otherPitch != nil, cppID: id,
            message: "a free key exists on the unselected track")
        guard let otherPitch else { return }
        let otherID = try? session.document.addNotes([
            NewNote(
                track: otherTrack, tick: start, pitch: UInt8(otherPitch),
                duration: seed.snap, velocity: 91)
        ]).first
        let otherBefore = otherID.flatMap { session.document.note($0) }
        report.expect(
            otherBefore.map {
                $0.track == otherTrack && $0.tick == start && Int($0.pitch) == otherPitch
                    && $0.duration == seed.snap && $0.velocity == 91
            } == true, cppID: id, message: "the unselected-track insert fixture exists")
        guard let otherID, let otherBefore else { return }
        let baseline = session.document.state
        let page = AutomationPage()
        page.attach(viewport: viewport, palette: grid.palette)
        defer { page.detach() }
        let originalTimeSelection = session.timeSelection
        let originalCursor = session.editCursor
        defer {
            session.applyTimeSelection(originalTimeSelection)
            session.editCursor = originalCursor
        }
        session.applyTimeSelection(
            AutomationTimeSelection(
                range: TimeRange(startTick: start, endTick: end), scope: .tracks([seed.track])))
        session.editCursor = end + seed.snap
        let selectionBefore = session.timeSelection
        let cursorBefore = session.editCursor
        let undoIndex = session.document.history.undoIndex
        let history = session.document.history.currentIdentity
        report.expect(
            session.timeSelection == selectionBefore && cursorBefore > end,
            cppID: id, message: "track insert starts with the scoped range and parked cursor")
        let routed = EditKeyArbiter.decide(
            command: .insertTime,
            surface: EditSurfaceState(
                pointerGestureActive: false, timeSelectionActive: true, noteSelectionEmpty: true,
                origin: .timeline, autoRepeat: false, commandAvailable: true))
        report.expect(
            routed == .execute, cppID: id,
            message: "a normalized Insert Time key executes with an active time selection")
        let performed = page.consumeSelectionCommand(command: .insertTime)
        report.expect(
            performed
                && session.document.notes(in: seed.track).contains(where: {
                    $0.tick == end && Int($0.pitch) == seed.pitch - 10
                })
                && session.document.note(otherID).map {
                    $0.tick == otherBefore.tick && $0.duration == otherBefore.duration
                        && $0.pitch == otherBefore.pitch && $0.velocity == otherBefore.velocity
                } == true && session.document.history.undoIndex == undoIndex + 1
                && session.timeSelection == selectionBefore && session.editCursor == start
                && cursorBefore > end, cppID: id,
            message: "track-scoped blank insertion shifts only the selected track")
        report.expect(
            session.document.history.undoDocument()
                && session.document.state == baseline
                && session.document.history.currentIdentity == history,
            cppID: id, message: "undo restores the track-scoped insertion")
    }
}

@MainActor
func checkTimelineInsertRejectedScope(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::timelineInsertRejectedScope"
    withKeyboardSeed(report, viewport: viewport, id: id) { _, seed in
        guard session.document.canAddTrack,
            let emptyTrack = session.document.addTrack(voice: 0),
            emptyTrack != seed.track,
            session.document.notes(in: emptyTrack).isEmpty
        else {
            report.fail(id, "could not provision a distinct empty track")
            return
        }
        let unusedTrack = session.document.engineTracks.usedTrackCount
        guard unusedTrack < 16 else {
            report.fail(id, "no unallocated track index remains for the rejected scope")
            return
        }
        let originalTrack = session.selectedTrack
        let originalSelection = session.timeSelection
        let originalCursor = session.editCursor
        defer {
            session.selectedTrack = originalTrack
            session.applyTimeSelection(originalSelection)
            session.editCursor = originalCursor
        }
        session.selectPrimaryTrack(emptyTrack)
        let range = TimeRange(
            startTick: seed.tick + 2 * seed.snap,
            endTick: seed.tick + 3 * seed.snap)
        session.applyTimeSelection(
            AutomationTimeSelection(
                range: range, scope: .tracks([emptyTrack])))
        session.editCursor = range.endTick + seed.snap
        guard session.selectedTrack == emptyTrack,
            session.selectedTracks == [emptyTrack],
            session.timeSelection
                == AutomationTimeSelection(
                    range: range, scope: .tracks([emptyTrack]))
        else {
            report.fail(id, "could not stage the valid track selection before the refused inputs")
            return
        }
        // Serialized SMF bytes are opaque: capture them before either rejected input.
        let bytes = coreTimeBytes(session.document)
        let revision = session.document.revision
        let history = session.document.history.currentIdentity
        let undoIndex = session.document.history.undoIndex
        let undoCount = session.document.history.undoCount
        let cursor = session.editCursor
        session.selectPrimaryTrack(unusedTrack)
        report.expect(
            session.selectedTrack == emptyTrack
                && session.selectedTracks == [emptyTrack]
                && session.timeSelection
                    == AutomationTimeSelection(
                        range: range, scope: .tracks([emptyTrack]))
                && session.editCursor == cursor
                && coreTimeBytes(session.document) == bytes
                && session.document.revision == revision
                && session.document.history.currentIdentity == history
                && session.document.history.undoIndex == undoIndex
                && session.document.history.undoCount == undoCount,
            cppID: id,
            message:
                "selecting an unallocated track refuses the primary change without touching selection, cursor, song, or history"
        )
        session.adjustTrackScope(track: unusedTrack, action: .plain)
        report.expect(
            session.selectedTrack == emptyTrack
                && session.selectedTracks == [emptyTrack]
                && session.timeSelection
                    == AutomationTimeSelection(
                        range: range, scope: .tracks([emptyTrack]))
                && session.editCursor == cursor
                && coreTimeBytes(session.document) == bytes
                && session.document.revision == revision
                && session.document.history.currentIdentity == history
                && session.document.history.undoIndex == undoIndex
                && session.document.history.undoCount == undoCount,
            cppID: id,
            message:
                "adjusting scope to an unallocated track refuses the active range change without touching cursor, song, or history"
        )
    }
}

@MainActor
func checkTimelineInsertBlankTimeLanes(_ report: CheckReport, viewport: DocumentViewport) {
    let session = viewport.session
    let id = "swiftcore/PianoRoll::timelineInsertBlankTimeLanes"
    withKeyboardSeed(report, viewport: viewport, id: id) { grid, seed in
        let start = seed.tick + 2 * seed.snap
        let end = start + seed.snap
        let pointTick = start + seed.snap / 2
        let lane: Lane = .controller(7)
        session.document.nudgeNotes([seed.id], byTicks: Int64(2 * seed.snap), byKeys: -10)
        report.expect(
            session.document.note(seed.id).map {
                $0.tick == start && Int($0.pitch) == seed.pitch - 10
            } == true, cppID: id, message: "lane insertion seed reaches its shortcut position")
        session.document.writeLane(
            track: seed.track, lane: lane, from: pointTick,
            through: pointTick, points: [LaneWrite(tick: pointTick, value: 80)])
        let pointBefore = session.document.lanePoints(track: seed.track, lane: lane)
            .first(where: { $0.tick == pointTick })
        let noteBefore = session.document.note(seed.id)
        report.expect(
            pointBefore?.value == 80
                && noteBefore.map {
                    $0.track == seed.track && $0.tick == start && Int($0.pitch) == seed.pitch - 10
                } == true, cppID: id, message: "the lane point and note insert fixtures exist")
        guard let noteBefore else { return }
        let baseline = session.document.state
        let history = session.document.history.currentIdentity
        let page = AutomationPage()
        page.attach(viewport: viewport, palette: grid.palette)
        defer { page.detach() }
        let originalTimeSelection = session.timeSelection
        let originalCursor = session.editCursor
        defer {
            session.applyTimeSelection(originalTimeSelection)
            session.editCursor = originalCursor
        }
        let range = TimeRange(startTick: start, endTick: end)
        session.applyTimeSelection(
            AutomationTimeSelection(
                range: range, scope: .lanes,
                lanes: [.controlChange(track: seed.track, controller: 7)]))
        session.editCursor = end + seed.snap
        let selectionBefore = session.timeSelection
        let cursorBefore = session.editCursor
        let undoIndex = session.document.history.undoIndex
        report.expect(
            session.timeSelection == selectionBefore && cursorBefore > end,
            cppID: id, message: "lane insert starts with the scoped range and parked cursor")
        let performed = page.consumeSelectionCommand(command: .insertTime)
        report.expect(
            performed
                && session.document.lanePoints(track: seed.track, lane: lane).contains(where: {
                    $0.tick == pointTick + seed.snap && $0.value == 80
                })
                && session.document.note(seed.id).map {
                    $0.tick == noteBefore.tick && $0.duration == noteBefore.duration
                        && $0.pitch == noteBefore.pitch && $0.velocity == noteBefore.velocity
                } == true && session.document.history.undoIndex == undoIndex + 1
                && session.timeSelection == selectionBefore && session.editCursor == start
                && cursorBefore > end, cppID: id,
            message: "lane-scoped blank insertion shifts CC7 without moving the note")
        report.expect(
            session.document.history.undoDocument()
                && session.document.state == baseline
                && session.document.history.currentIdentity == history,
            cppID: id, message: "undo restores the lane-scoped insertion")
    }
}
