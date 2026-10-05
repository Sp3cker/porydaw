import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore
import PorydawAppAudio
import PorydawPlaybackNative
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
    guard let rig = AuditionCheckEngines(capacity: 15, sampleRate: session.timeline.sampleRate) else {
        report.fail(id, "real band engine could not be initialized")
        return
    }
    guard let first = session.document.note(seed.ids[0]),
        let second = session.document.note(seed.ids[1])
    else {
        report.fail(id, "band-audition seed notes disappeared")
        return
    }
    let tempoSeam = first.tick + first.duration / 2
    session.document.editTempo(
        TempoEdit(
            remove: session.document.state.tempo,
            add: [
                TempoPoint(tick: 0, microsecondsPerQuarterNote: 500_000),
                TempoPoint(tick: tempoSeam, microsecondsPerQuarterNote: 250_000),
            ]))
    let timeline = session.timeline
    let durationFrames = timeline.sample(for: first.tick + first.duration) - timeline.sample(for: first.tick)
    guard durationFrames > 1 && durationFrames <= UInt64(Int.max) else {
        report.fail(id, "seeded musical span has no usable rendered-frame boundary")
        return
    }
    report.expect(
        tempoSeam > first.tick && tempoSeam < first.tick + first.duration
            && timeline.tempoMap.contains { $0.tick == tempoSeam && $0.microsecondsPerQuarterNote == 250_000 },
        cppID: id, message: "band duration fixture crosses an authoritative session tempo change")
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
    var auditionedZero = false
    grid.onBandAudition = { notes in
        auditionedZero = auditionedZero || notes.contains { $0.noteID == zero.id.rawValue }
        rig.audition.updateBandAudition(notes)
    }
    defer {
        grid.inputCancelled(reason: GridCancelReason.hidden.rawValue)
        rig.apply()
        grid.onBandAudition = nil
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
    let firstVoice = AuditionHeldNote(first.velocity, track: first.track, key: first.pitch)
    let secondVoice = AuditionHeldNote(second.velocity, track: second.track, key: second.pitch)
    func moveBand(x: Double, y: Double) {
        grid.updateRightPointer(x: x, y: y)
        rig.apply()
    }
    func beginBand() {
        grid.beginRightPointer(x: 1, y: 0)
        moveBand(x: endX, y: endY)
    }
    grid.beginRightPointer(x: 1, y: 0)
    moveBand(x: ax, y: ay)
    report.expect(
        first.velocity == 93 && rig.records().contains(firstVoice), cppID: id,
        message: "production geometry covers a note and its exact document velocity reaches native")
    report.expect(
        rig.pump(rig.main, frames: min(4096, Int(durationFrames) - 1)) > 0,
        cppID: id, message: "production right-pointer band sounds through the real engine")
    let heldBefore = rig.records()
    moveBand(x: ax, y: ay)
    report.expect(
        rig.records() == heldBefore
            && rig.pcm(rig.main).allSatisfy { $0.status & 0x40 != 0 || $0.status & 0x80 == 0 },
        cppID: id, message: "unchanged production pointer coverage does not reattack")
    moveBand(x: shrinkX, y: 4)
    report.expect(
        !rig.records().contains { $0.track == first.track && $0.key == first.pitch },
        cppID: id, message: "shrinking production geometry releases the departed native occurrence immediately")
    moveBand(x: endX, y: endY)
    let covered = rig.records()
    report.expect(
        covered.contains(firstVoice) && covered.contains(secondVoice)
            && rig.pcm(rig.main).contains {
                $0.status & 0x80 != 0 && $0.status & 0x40 == 0 && $0.midiKey == first.pitch
            },
        cppID: id, message: "re-covering production geometry starts a fresh occurrence at its exact velocity")
    _ = rig.pump(rig.main, frames: Int(durationFrames) - 1)
    report.expect(
        rig.records().contains(firstVoice), cppID: id,
        message: "reentered document note stays held through the tempo-integrated penultimate frame")
    moveBand(x: endX, y: endY)
    _ = rig.pump(rig.main, frames: 1)
    report.expect(
        !rig.records().contains(firstVoice), cppID: id,
        message: "document tick endpoints gate native at the exact last sample despite unchanged coverage")
    moveBand(x: endX, y: endY)
    report.expect(
        !rig.records().contains(firstVoice), cppID: id,
        message: "unchanged production geometry cannot resurrect a musically expired note")
    grid.endRightPointer(x: endX, y: endY)
    rig.apply()
    report.expect(rig.records().isEmpty, cppID: id, message: "production drag end releases every native occurrence")
    let expected: [AuditionHeldNote] = session.selectedNoteOrder.compactMap { session.document.note($0) }
        .filter { $0.duration > 0 }
        .map { AuditionHeldNote($0.velocity, track: $0.track, key: $0.pitch) }.sorted()
    report.expect(
        expected.count <= Int(MAX_PCM_CHANNELS) && covered == expected, cppID: id,
        message: "every eligible swept document identity reaches native with its own exact velocity")
    report.expect(
        session.selectedNotes.contains(zero.id) && !auditionedZero,
        cppID: id, message: "a swept zero-duration note is selected but never auditioned")
    report.expect(
        session.selectedNotes.isSuperset(of: Set(seed.ids)), cppID: id,
        message: "band release selects every swept note identity")
    report.expect(
        session.document.revision == revision
            && session.document.history.currentIdentity == history, cppID: id,
        message: "band audition changes no document revision or undo entry")
    for reason in [GridCancelReason.focusLost, .pointerUngrabbed, .hidden] {
        beginBand()
        report.expect(
            rig.records().contains(firstVoice),
            cppID: id, message: "cancellation fixture starts a real native band for reason \(reason.rawValue)")
        grid.inputCancelled(reason: reason.rawValue)
        rig.apply()
        report.expect(
            rig.records().isEmpty && !grid.interactionActive,
            cppID: id, message: "production cancellation \(reason.rawValue) releases all native band occurrences")
    }
    beginBand()
    grid.beginPointer(x: ax, y: ay, modifiers: 0)
    grid.updatePointer(x: endX + grid.dragDistance + 4, y: endY)
    rig.apply()
    report.expect(
        rig.records().isEmpty, cppID: id,
        message: "combined-button demotion releases the actual sounding band")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    rig.apply()
    beginBand()
    report.expect(!rig.records().isEmpty, cppID: id, message: "detach fixture holds a real native band")
    grid.detach()
    rig.apply()
    report.expect(
        rig.records().isEmpty && !grid.interactionActive, cppID: id,
        message: "production detach ends every native band occurrence")
    report.expect(
        session.document.revision == revision
            && session.document.history.currentIdentity == history, cppID: id,
        message: "cancellation, demotion and detach change no document revision or undo entry")
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
