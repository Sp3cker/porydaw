import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore
@testable import PorydawDocument
import QtBridge

@MainActor
func checkSelectionBandAudition(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectionBandSweep"
    let initialSelection = session.selectedNoteOrder
    let grid = makeCameraGrid(session: session)
    guard let baseline = try? session.document.captureSave() else {
        report.fail(id, "could not capture the pre-band MIDI bytes")
        return
    }
    defer {
        selectionRestore(
            report, id: id, session: session, baseline: baseline,
            selection: initialSelection,
            message: "band audition unwinds to the pre-seed MIDI bytes and history")
    }
    guard let seed = velocityPairSeed(session: session, grid: grid) else {
        report.fail(id, "could not seed the two band-audition notes")
        return
    }
    var auditions: [(track: Int, pitch: Int, velocity: Int)] = []
    grid.onAudition = { auditions.append(($0, $1, $2)) }
    defer { grid.onAudition = nil }
    guard let first = session.document.note(seed.ids[0]),
        let second = session.document.note(seed.ids[1])
    else {
        report.fail(id, "band-audition seed notes disappeared")
        return
    }
    let p0 = Int(first.pitch)
    let p1 = Int(second.pitch)
    let pitchRange = (min(p0, p1) + 1)..<max(p0, p1)
    guard
        let zeroPitch = pitchRange.first(where: { pitch in
            !session.document.notes(in: grid.trackIndex).contains {
                Int($0.pitch) == pitch && $0.tick == first.tick
            }
        })
    else {
        report.fail(id, "no free visible pitch between the band-audition notes")
        return
    }
    session.document.insertRawEvent(
        chunk: first.chunk,
        event: .channel(
            tick: first.tick, status: 0x90 | first.channel,
            data0: UInt8(zeroPitch), data1: 77))
    grid.refreshFromSession()
    guard
        let zero = session.document.notes(in: grid.trackIndex).first(where: {
            Int($0.pitch) == zeroPitch && $0.tick == first.tick && $0.duration == 0
        }), selectionRect(zero.id, grid: grid) != nil,
        let planted = try? session.document.captureSave()
    else {
        report.fail(id, "raw note-on did not publish a visible zero-duration band note")
        return
    }
    let revision = session.document.revision
    let history = session.document.history.currentIdentity
    session.clearSelectedNotes()
    let ax = seed.rects[0].x + seed.rects[0].width / 2
    let ay = seed.rects[0].y + seed.rects[0].height / 2
    let endX =
        max(
            seed.rects[0].x + seed.rects[0].width,
            seed.rects[1].x + seed.rects[1].width) + 4
    let endY =
        max(
            seed.rects[0].y + seed.rects[0].height,
            seed.rects[1].y + seed.rects[1].height) + 4
    let shrinkX = min(seed.rects[0].x, seed.rects[1].x) - 8
    guard shrinkX >= 7 else {
        report.fail(id, "band-audition notes sit too close to the plot origin to shrink past")
        return
    }
    grid.beginRightPointer(x: 1, y: 0)
    grid.updateRightPointer(x: ax, y: ay)
    report.expect(
        auditions.contains { $0.pitch == p0 && $0.velocity == 93 }, cppID: id,
        message: "covering a note starts its band audition at the document velocity")
    grid.updateRightPointer(x: shrinkX, y: 4)
    report.expect(
        auditions.contains { $0.pitch == p0 && $0.velocity == 0 }, cppID: id,
        message: "shrinking the band past a note releases its audition immediately")
    grid.updateRightPointer(x: endX, y: endY)
    grid.endRightPointer(x: endX, y: endY)
    report.expect(
        auditions.filter { $0.pitch == p0 && $0.velocity > 0 }.count >= 2, cppID: id,
        message: "re-covering a note re-auditions it")
    report.expect(
        auditions.contains { $0.pitch == p1 && $0.velocity == 0 }, cppID: id,
        message: "the drag end releases every auditioned key")
    report.expect(
        session.selectedNotes.contains(zero.id)
            && !auditions.contains { $0.pitch == zeroPitch && $0.velocity > 0 },
        cppID: id, message: "a swept zero-duration note is never auditioned")
    report.expect(
        session.selectedNotes.isSuperset(of: Set(seed.ids)), cppID: id,
        message: "band release selects every swept note identity")
    report.expect(
        session.document.revision == revision
            && session.document.history.currentIdentity == history, cppID: id,
        message: "band audition changes no document revision or undo entry")
    do {
        let after = try session.document.captureSave()
        report.expect(
            after.bytes == planted.bytes, cppID: id,
            message: "band audition leaves the planted MIDI bytes untouched")
    } catch {
        report.fail(id, "could not encode the post-band MIDI document: \(error)")
    }
}

@MainActor
func checkTransposeAudition(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::drawerTransposeAuditionReleasesOnPhysicalKeyUp"
    let originalSelection = session.selectedNoteOrder
    guard let baseline = try? session.document.captureSave() else {
        report.fail(id, "could not capture the pre-transpose MIDI bytes")
        return
    }
    let grid = makeCameraGrid(session: session)
    defer {
        grid.onAudition = nil
        selectionRestore(
            report, id: id, session: session, baseline: baseline,
            selection: originalSelection,
            message: "transpose audition restores the original document and selection")
    }
    guard let selectedTrack = session.selectedTrack,
        let ids = try? session.document.addNotes([
            NewNote(track: selectedTrack, tick: 12_000, pitch: 60, duration: 24, velocity: 41),
            NewNote(track: selectedTrack, tick: 12_048, pitch: 67, duration: 24, velocity: 93),
        ]), ids.count == 2
    else {
        report.fail(id, "could not seed ordered transpose-audition notes")
        return
    }
    session.setSelectedNotes(ids)
    var auditions: [(track: Int, pitch: Int, velocity: Int)] = []
    grid.onAudition = { auditions.append(($0, $1, $2)) }
    grid.performCommand(command: EditCommand.transposeUp.rawValue)
    report.expect(
        session.document.note(ids[0])?.pitch == 61
            && session.document.note(ids[1])?.pitch == 68
            && auditions.count == 1 && auditions[0].track == selectedTrack
            && auditions[0].pitch == 61 && auditions[0].velocity == 41, cppID: id,
        message: "transpose key-down auditions the transposed pitch above zero velocity")
}

@MainActor
func checkMountedTransposeAudition(_ report: CheckReport, fixtureRoot: String) {
    let id = "swiftcore/PianoRoll::drawerTransposeAuditionReleasesOnPhysicalKeyUp"
    let root = stageTestProject(in: fixtureRoot, projectName: "swiftcore-transpose-audition")
    let app = ApplicationSession()
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    app.openProjectAndSong(path: root, label: "mus_session_test")
    let deadline = Date().addingTimeInterval(25)
    while !app.songOpen && app.lastSaveError.isEmpty && Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    guard app.songOpen, let session = app.selectedDocument, let track = session.selectedTrack else {
        report.fail(id, "mounted fixture could not open: \(app.lastSaveError)")
        return
    }
    guard
        let ids = try? session.document.addNotes([
            NewNote(track: track, tick: 12_000, pitch: 60, duration: 24, velocity: 41)
        ]), let noteID = ids.first
    else {
        report.fail(id, "mounted transpose-audition note could not be seeded")
        return
    }
    session.setSelectedNotes([noteID])
    let grid = app.gridPresenter()
    let forward = grid.onAudition
    var auditions: [(track: Int, pitch: Int, velocity: Int)] = []
    grid.onAudition = { noteTrack, pitch, velocity in
        auditions.append((noteTrack, pitch, velocity))
        forward?(noteTrack, pitch, velocity)
    }
    defer { grid.onAudition = forward }
    app.performGridCommand(command: EditCommand.transposeUp.rawValue)
    let repeated = app.routeGridKey(command: EditCommand.transposeUp.rawValue, autoRepeat: true)
    if repeated == EditKeyDecision.execute.rawValue {
        app.performGridCommand(command: EditCommand.transposeUp.rawValue)
    }
    let afterRepeat = auditions.count
    let repeatRelease = app.releaseGridKey(autoRepeat: true)
    report.expect(
        repeated == EditKeyDecision.execute.rawValue
            && session.document.note(noteID)?.pitch == 62
            && afterRepeat == 2 && auditions[1].pitch == 62 && auditions[1].velocity == 41
            && !repeatRelease && auditions.count == afterRepeat, cppID: id,
        message: "autorepeat key-up holds the transpose audition")
    let physicalRelease = app.releaseGridKey(autoRepeat: false)
    let duplicateRelease = app.releaseGridKey(autoRepeat: false)
    report.expect(
        physicalRelease && !duplicateRelease && auditions.count == afterRepeat + 1
            && auditions.last?.track == track && auditions.last?.pitch == 62
            && auditions.last?.velocity == 0, cppID: id,
        message: "physical key-up ends the transpose audition with a zero-velocity release")
}

@MainActor
func checkKeyboardAuditionTrackSwitch(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::keyboardAuditionTrackSwitch"
    let originalTrack = session.selectedTrack
    let originalSelection = session.selectedNoteOrder
    let originalCamera = session.camera
    defer { _ = session.mutateCamera { $0 = originalCamera } }
    let grid = makeCameraGrid(session: session)
    let pressedTrack = grid.trackIndex
    guard let baseline = try? session.document.captureSave() else {
        report.fail(id, "could not capture the pre-audition MIDI bytes")
        return
    }
    defer {
        grid.endKeyboardPointer()
        grid.onAudition = nil
        session.selectedTrack = originalTrack
        selectionRestore(
            report, id: id, session: session, baseline: baseline,
            selection: originalSelection,
            message: "keyboard audition track switch restores the original document")
    }
    let otherTrack =
        (0..<session.document.engineTracks.usedTrackCount).first {
            $0 != pressedTrack
        } ?? (session.document.canAddTrack ? session.document.addTrack(voice: 0) : nil)
    guard let otherTrack else {
        report.fail(id, "no second track available for keyboard audition")
        return
    }
    guard let found = visibleRow(grid) else {
        report.fail(id, "no visible keyboard row available for audition")
        return
    }
    let pitch = found.pitch
    var auditions: [(track: Int, pitch: Int, velocity: Int)] = []
    grid.onAudition = { auditions.append(($0, $1, $2)) }
    grid.beginKeyboardPointer(y: found.y)
    session.selectedTrack = otherTrack
    grid.refreshFromSession()
    grid.endKeyboardPointer()
    report.expect(
        grid.trackIndex == otherTrack && auditions.count == 2
            && auditions[0].track == pressedTrack && auditions[0].pitch == pitch
            && auditions[0].velocity > 0
            && auditions[1].track == pressedTrack && auditions[1].pitch == pitch
            && auditions[1].velocity == 0
            && !auditions.contains { $0.track == otherTrack && $0.velocity == 0 },
        cppID: id, message: "keyboard audition releases on the pressed track after a track switch")
}
