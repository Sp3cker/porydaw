import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore
import PorydawCoreCheckNative

@MainActor
internal func runEditRoutingChecks(report: CheckReport, fixtureRoot: String) {
    let service = ProjectService()
    let session: DocumentSession
    let inactive: DocumentSession
    do {
        try runBlocking { try await service.open(root: fixtureRoot) }
        session = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_route101", sampleRate: 48_000)
        }
        inactive = try runBlocking {
            try await DocumentSession.open(service: service, label: "mus_route102", sampleRate: 48_000)
        }
    } catch {
        report.fail("mainwindowrouting/MainWindowRoutingInputTest::copyActionRoutesCompleteClipAndTimeSelection",
                    "could not open the two real routing fixture songs: \(error)")
        return
    }
    let document = session.document
    let tracks = (0..<document.engineTracks.usedTrackCount).filter { !document.notes(in: $0).isEmpty }
    guard tracks.count >= 2, let firstTrack = tracks.first,
          let note = document.notes(in: firstTrack).first,
          let secondTrack = tracks.dropFirst().first,
          let otherNote = document.notes(in: secondTrack).first,
          let original = try? document.state.file.encoded(),
          let inactiveOriginal = try? inactive.document.state.file.encoded() else {
        report.fail("mainwindowrouting/MainWindowRoutingInputTest::insertTimeRoutesActiveSongAndRestoresUndoBytes",
                    "real routing song needs two populated tracks and encodable bytes")
        return
    }
    let grid = PianoGrid(session: session)
    let page = AutomationPage()
    page.attach(session: session, palette: GridPalette())
    defer { page.detach() }
    session.onChange = { [weak page] _ in page?.refreshFromDocument() }
    let ruler = RulerMenuPresenter(session: session, grid: grid, automation: page)
    let router = EditorCommandRouter(session: session, grid: grid, automation: page, rulerMenu: ruler)
    let savedClipboard = drawerAutomationPorydawSelectionClipboardState()
    defer { savedClipboard.restore() }
    let clipboard = GridClipboard()
    session.selectedTrack = firstTrack

    let copyID = "mainwindowrouting/MainWindowRoutingInputTest::copyActionRoutesCompleteClipAndTimeSelection"
    session.addSelectedNote(note.id)
    report.expect(router.isAvailable(.copy), cppID: copyID,
                  message: "copy routes the complete clip and time selection")
    router.perform(.copy)
    let noteClip = clipboard.read()
    let noteClipMatches: Bool
    if let noteClip, let track = noteClip.clip.tracks.first,
       let copied = track.notes.first {
        noteClipMatches = noteClip.ticksPerBeat == document.state.file.division &&
            noteClip.clip.span == 0 && noteClip.clip.tracks.count == 1 &&
            track.track == firstTrack && track.notes.count == 1 &&
            copied.key == note.pitch && copied.velocity == note.velocity
    } else {
        noteClipMatches = false
    }
    report.expect(noteClipMatches, cppID: copyID,
                  message: "note copy publishes the entire selected note payload")
    session.clearSelectedNotes()
    let span = Tick(document.state.file.division)
    page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: note.tick, endTick: note.tick + span),
        scope: .tracks([firstTrack])))
    router.perform(.copy)
    let rangeClip = clipboard.read()
    let rangeClipMatches: Bool
    if let rangeClip {
        let selectedTrackCopy = rangeClip.clip.tracks.first(where: { $0.track == firstTrack })
        let copiedRangeNote = selectedTrackCopy?.notes.first(where: {
            $0.relTick == 0 && $0.key == note.pitch && $0.velocity == note.velocity
        })
        rangeClipMatches = rangeClip.ticksPerBeat == document.state.file.division &&
            rangeClip.clip.span == span && copiedRangeNote != nil
    } else {
        rangeClipMatches = false
    }
    report.expect(rangeClipMatches, cppID: copyID,
                  message: "a time selection supersedes note copy and preserves its exact span")
    page.clearTimeSelection()

    let soloID = "mainwindowrouting/MainWindowRoutingInputTest::soloActionUsesSingleWindowOwnerAndRespectsTextFocus"
    let beforeSolo = session.soloedTracks
    report.expect(router.isAvailable(.soloTracks), cppID: soloID,
                  message: "solo keeps one enabled editor route for the selected track")
    router.perform(.soloTracks)
    report.expect(session.soloedTracks != beforeSolo && session.soloedTracks.contains(firstTrack),
                  cppID: soloID, message: "the selected track becomes solo through the editor route")
    router.perform(.soloTracks)
    report.expect(session.soloedTracks == beforeSolo, cppID: soloID,
                  message: "a second solo command restores the previous mix")

    let insertID = "mainwindowrouting/MainWindowRoutingInputTest::insertTimeRoutesActiveSongAndRestoresUndoBytes"
    let playbackID = "mainwindowrouting/MainWindowRoutingInputTest::insertTimeActionAnchorsSelectionDuringPlayback"
    let rulerID = "mainwindowrouting/MainWindowRoutingInputTest::insertTimeRulerMenuAnchorsEditCursor"
    let deleteID = "mainwindowrouting/MainWindowRoutingInputTest::deleteTimeActionRipplesScopedAndWholeSongSelections"
    let seam = max(note.tick, otherNote.tick)
    let range = TimeRange(startTick: seam, endTick: seam + span)
    guard let inside = document.notes(in: firstTrack).first(where: {
        $0.tick >= range.startTick && $0.tick < range.endTick
    }),
          let later = document.notes(in: firstTrack).first(where: { $0.tick >= range.endTick }),
          let otherLater = document.notes(in: secondTrack).first(where: { $0.tick >= range.endTick })
    else {
        report.fail(insertID, "the real routing fixture needs late notes on selected and excluded tracks")
        return
    }
    let initialIndex = document.history.undoIndex
    let initialRevision = document.revision
    page.applyTimeSelection(AutomationTimeSelection(range: range, scope: .tracks([firstTrack])))
    session.editCursor = 0
    page.refreshPlayhead(tick: Double(range.endTick) + Double(span), playing: true)
    report.expect(page.contextTick != range.startTick && router.isAvailable(.insertTime),
                  cppID: playbackID, message: "insert time anchors the selection during playback")
    router.perform(.insertTime)
    report.expect(document.history.undoIndex == initialIndex + 1 &&
                  document.revision == initialRevision + 1 &&
                  page.selection?.range == range && session.editCursor == range.startTick &&
                  document.note(otherNote.id)?.tick == otherNote.tick &&
                  document.note(note.id)?.tick == note.tick + (note.tick >= seam ? span : 0) &&
                  document.note(later.id)?.tick == later.tick + span &&
                  document.note(otherLater.id)?.tick == otherLater.tick &&
                  (try? inactive.document.state.file.encoded()) == inactiveOriginal,
                  cppID: playbackID, message: "selection insertion parks its cursor and leaves other tracks untouched")
    report.expect(document.history.undoDocument() &&
                  (try? document.state.file.encoded()) == original &&
                  document.history.undoIndex == initialIndex,
                  cppID: playbackID, message: "one undo restores exact selection insertion bytes")
    page.clearTimeSelection()
    page.refreshPlayhead(tick: 0, playing: false)

    session.editCursor = span
    ruler.captureRulerPress(contentX: session.camera.contentX(tick: 0),
                            pointerY: grid.rulerHeight * 0.75)
    ruler.openRulerAtRelease()
    report.expect(ruler.isOpen && ruler.menuKind == 1 && ruler.targetTick() == 0 &&
                  session.editCursor == 0 && ruler.rows.count > 0 &&
                  ruler.rows[0].actionId == 1 && ruler.rows[0].enabled,
                  cppID: rulerID, message: "the insert-time ruler menu anchors the edit cursor")
    let rulerIndex = document.history.undoIndex
    let rulerRevision = document.revision
    let beatTicks = Tick(document.state.file.division)
    _ = ruler.activate(actionId: 1)
    report.expect(ruler.insertTimePromptOpen &&
                  ruler.insertTimePromptInitialBars == 1 &&
                  ruler.insertTimePromptInitialBeats == 0 &&
                  ruler.insertTimePromptInitialBeatFractions == 0,
                  cppID: insertID, message: "the cursor ruler action opens the standalone Insert Time prompt")
    ruler.acceptInsertTimePrompt(bars: 0, beats: 1, fractions: 0)
    report.expect(!ruler.insertTimePromptOpen &&
                  document.history.undoIndex == rulerIndex + 1 &&
                  document.revision == rulerRevision + 1 &&
                  document.note(note.id)?.tick == note.tick + beatTicks &&
                  document.note(otherNote.id)?.tick == otherNote.tick + beatTicks &&
                  (try? inactive.document.state.file.encoded()) == inactiveOriginal,
                  cppID: insertID, message: "insert time routes the active song and restores undo bytes")
    report.expect(document.history.undoDocument() &&
                  document.history.undoIndex == rulerIndex &&
                  (try? document.state.file.encoded()) == original &&
                  (try? inactive.document.state.file.encoded()) == inactiveOriginal,
                  cppID: insertID, message: "one undo restores both the active and inactive song bytes")

    ruler.captureRulerPress(contentX: session.camera.contentX(tick: 0),
                            pointerY: grid.rulerHeight * 0.75)
    ruler.openRulerAtRelease()
    _ = ruler.activate(actionId: 1)
    let zeroCount = document.history.undoCount
    let zeroRevision = document.revision
    ruler.acceptInsertTimePrompt(bars: 0, beats: 0, fractions: 0)
    report.expect(!ruler.insertTimePromptOpen &&
                  document.history.undoIndex == rulerIndex &&
                  document.history.undoCount == zeroCount &&
                  document.revision == zeroRevision &&
                  (try? document.state.file.encoded()) == original,
                  cppID: insertID, message: "zero-span prompt acceptance changes neither bytes nor history")
    ruler.captureRulerPress(contentX: session.camera.contentX(tick: 0),
                            pointerY: grid.rulerHeight * 0.75)
    ruler.openRulerAtRelease()
    _ = ruler.activate(actionId: 1)
    ruler.cancelInsertTimePrompt()
    report.expect(!ruler.insertTimePromptOpen &&
                  document.history.undoIndex == rulerIndex &&
                  document.revision == zeroRevision &&
                  (try? document.state.file.encoded()) == original,
                  cppID: insertID, message: "cancelling the standalone prompt preserves the song")

    page.applyTimeSelection(AutomationTimeSelection(range: range, scope: .tracks([firstTrack])))
    session.editCursor = range.endTick + span
    let deleteIndex = document.history.undoIndex
    let deleteRevision = document.revision
    report.expect(router.isAvailable(.deleteTime), cppID: deleteID,
                  message: "delete time ripples scoped and whole-song selections")
    router.perform(.deleteTime)
    report.expect(document.revision == deleteRevision + 1 &&
                  document.history.undoIndex == deleteIndex + 1 &&
                  session.editCursor == range.startTick && page.selection == nil &&
                  document.note(inside.id) == nil &&
                  document.note(note.id)?.tick == note.tick &&
                  document.note(otherNote.id)?.tick == otherNote.tick &&
                  document.note(later.id)?.tick == later.tick - span &&
                  document.note(otherLater.id)?.tick == otherLater.tick &&
                  (try? inactive.document.state.file.encoded()) == inactiveOriginal,
                  cppID: deleteID, message: "scoped deletion parks at the seam and leaves the other track untouched")
    report.expect(document.history.undoDocument() &&
                  document.history.undoIndex == deleteIndex &&
                  (try? document.state.file.encoded()) == original &&
                  (try? inactive.document.state.file.encoded()) == inactiveOriginal,
                  cppID: deleteID, message: "one undo restores exact scoped-deletion bytes")
    page.applyTimeSelection(AutomationTimeSelection(range: range, scope: .tracks(Set(tracks))))
    let wholeIndex = document.history.undoIndex
    router.perform(.deleteTime)
    report.expect(document.history.undoIndex == wholeIndex + 1 &&
                  document.note(inside.id) == nil &&
                  document.note(otherNote.id) == nil &&
                  document.note(later.id)?.tick == later.tick - span &&
                  document.note(otherLater.id)?.tick == otherLater.tick - span &&
                  (try? inactive.document.state.file.encoded()) == inactiveOriginal,
                  cppID: deleteID, message: "whole-song deletion ripples the other track")
    report.expect(document.history.undoDocument() &&
                  document.history.undoIndex == wholeIndex &&
                  (try? document.state.file.encoded()) == original &&
                  (try? inactive.document.state.file.encoded()) == inactiveOriginal,
                  cppID: deleteID, message: "one undo restores exact whole-song removal bytes")
}
