import Foundation
import PorydawApp
import PorydawAppCommands
import PorydawCore
import PorydawCoreCheckNative

@MainActor
internal func runEditRoutingChecks(report: CheckReport, fixtureRoot: String) {
    let unboundID = "mainwindowrouting/MainWindowRoutingStateTest::editActionProjectionAndIdentity"
    let shell = ShellPresenter()
    let app = shell.session
    report.expect(!app.songOpen && app.songTabs.selectedPage == nil
                  && app.selectedDocument == nil
                  && !app.gridCommandAvailable(command: EditCommand.copy.rawValue),
                  cppID: unboundID,
                  message: "an empty tab strip has no document-bound command router")
    report.expect(!shell.actionEnabled(id: "roll.copy"), cppID: unboundID,
                  message: "the empty shell disables Copy")
    report.expect(!shell.actionEnabled(id: "roll.solo_tracks"), cppID: unboundID,
                  message: "the empty shell disables Solo Tracks")
    report.expect(!shell.actionEnabled(id: "edit.insert_time"), cppID: unboundID,
                  message: "the empty shell disables Insert Time")
    report.expect(!shell.actionEnabled(id: "edit.delete_time"), cppID: unboundID,
                  message: "the empty shell disables Delete Time")

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
    let sourceTicksPerBeat = UInt32(document.state.file.division)
    let copyIndex = document.history.undoIndex
    let copyRevision = document.revision
    let inactiveIndex = inactive.document.history.undoIndex
    let inactiveRevision = inactive.document.revision
    session.addSelectedNote(note.id)
    report.expect(router.isAvailable(.copy), cppID: copyID,
                  message: "copy routes the complete clip and time selection")
    router.perform(.copy)
    report.expect(document.history.undoIndex == copyIndex &&
                  document.revision == copyRevision &&
                  (try? document.state.file.encoded()) == original &&
                  inactive.document.history.undoIndex == inactiveIndex &&
                  inactive.document.revision == inactiveRevision &&
                  (try? inactive.document.state.file.encoded()) == inactiveOriginal,
                  cppID: copyID, message: "selected note Copy leaves both songs and histories untouched")
    let noteClip = clipboard.read()
    report.expect(noteClip != nil, cppID: copyID,
                  message: "selected note Copy writes a readable clip")
    report.expect(noteClip?.ticksPerBeat == sourceTicksPerBeat, cppID: copyID,
                  message: "selected note Copy retains the source ticks per beat")
    report.expect(noteClip?.clip.span == 0, cppID: copyID,
                  message: "selected note Copy has zero clip span")
    report.expect(noteClip?.clip.tracks.count == 1, cppID: copyID,
                  message: "selected note Copy has exactly one track")
    report.expect(noteClip?.clip.tracks.first?.notes.count == 1, cppID: copyID,
                  message: "selected note Copy has exactly one note")
    report.expect(noteClip?.clip.tracks.first?.notes.first?.key == note.pitch, cppID: copyID,
                  message: "selected note Copy preserves its key")
    report.expect(noteClip?.clip.tracks.first?.notes.first?.velocity == note.velocity,
                  cppID: copyID, message: "selected note Copy preserves its velocity")
    let noteClipMatches = noteClip?.ticksPerBeat == sourceTicksPerBeat &&
        noteClip?.clip.span == 0 && noteClip?.clip.tracks.count == 1 &&
        noteClip?.clip.tracks.first?.track == firstTrack &&
        noteClip?.clip.tracks.first?.notes.count == 1 &&
        noteClip?.clip.tracks.first?.notes.first?.key == note.pitch &&
        noteClip?.clip.tracks.first?.notes.first?.velocity == note.velocity
    report.expect(noteClipMatches, cppID: copyID,
                  message: "note copy publishes the entire selected note payload")
    session.clearSelectedNotes()
    let span = Tick(document.state.file.division)
    page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: note.tick, endTick: note.tick + span),
        scope: .tracks([firstTrack])))
    router.perform(.copy)
    report.expect(document.history.undoIndex == copyIndex &&
                  document.revision == copyRevision &&
                  (try? document.state.file.encoded()) == original &&
                  inactive.document.history.undoIndex == inactiveIndex &&
                  inactive.document.revision == inactiveRevision &&
                  (try? inactive.document.state.file.encoded()) == inactiveOriginal,
                  cppID: copyID, message: "both Copy paths leave both songs and histories untouched")
    let rangeClip = clipboard.read()
    report.expect(rangeClip != nil, cppID: copyID,
                  message: "selected time-range Copy writes a readable clip")
    report.expect(rangeClip?.ticksPerBeat == sourceTicksPerBeat, cppID: copyID,
                  message: "selected time-range Copy retains the source ticks per beat")
    report.expect(rangeClip?.clip.span == span, cppID: copyID,
                  message: "selected time-range Copy preserves its exact span")
    let selectedTrackCopy = rangeClip?.clip.tracks.first(where: { $0.track == firstTrack })
    let copiedRangeNote = selectedTrackCopy?.notes.first(where: {
        $0.relTick == 0 && $0.key == note.pitch && $0.velocity == note.velocity
    })
    let rangeClipMatches = rangeClip?.ticksPerBeat == sourceTicksPerBeat &&
        rangeClip?.clip.span == span && copiedRangeNote != nil
    report.expect(rangeClipMatches, cppID: copyID,
                  message: "a time selection supersedes note copy and preserves its exact span")
    page.clearTimeSelection()

    let soloID = "mainwindowrouting/MainWindowRoutingInputTest::soloActionUsesSingleWindowOwnerAndRespectsTextFocus"
    let beforeSolo = session.soloedTracks
    let inactiveSolo = inactive.soloedTracks
    report.expect(router.isAvailable(.soloTracks), cppID: soloID,
                  message: "solo keeps one enabled editor route for the selected track")
    router.perform(.soloTracks)
    report.expect(session.soloedTracks != beforeSolo && session.soloedTracks.contains(firstTrack),
                  cppID: soloID, message: "the selected track becomes solo through the editor route")
    report.expect(inactive.soloedTracks == inactiveSolo, cppID: soloID,
                  message: "the first Solo leaves the inactive song mix unchanged")
    router.perform(.soloTracks)
    report.expect(session.soloedTracks == beforeSolo, cppID: soloID,
                  message: "a second solo command restores the previous mix")
    report.expect(inactive.soloedTracks == inactiveSolo, cppID: soloID,
                  message: "the second Solo leaves the inactive song mix unchanged")

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
    checkMountedPitchKeyAndUndo(report: report, fixtureRoot: fixtureRoot)
}

@MainActor
internal func checkMountedPitchKeyAndUndo(report: CheckReport, fixtureRoot: String) {
    let keyID = "selectionkey/SelectionLocalInputTierTest::pitchBendOverlayOwnsKeys"
    let curveID = "pitchbend/PitchBendEditingTest::standardUndoShortcutRestoresCurve"
    let tapID = "selectionkey/SelectionWindowTierTest::parameterLabelActivationAndSharedCommands"
    let shell = ShellPresenter()
    let app = shell.session
    defer {
        app.hostClosing()
        app.acknowledgeGridDetached()
    }
    func until(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(25)
        while !predicate() && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return predicate()
    }
    app.openProjectAndSong(path: fixtureRoot, label: "mus_route101")
    guard until({ app.songOpen || !app.lastSaveError.isEmpty }),
          let tab = app.songTabs.selectedPage,
          let session = app.selectedDocument,
          let note = session.document.notes(in: 0)
              .first(where: { !$0.isUnterminated && $0.duration >= 3 }),
          let baseline = try? session.document.state.file.encoded() else {
        report.fail(keyID, "the real routing fixture cannot stage the selected pitch note")
        return
    }
    let document = session.document
    session.selectPrimaryTrack(0)
    session.setSelectedNotes([note.id])
    report.expect(session.selectedTrack == note.track
                  && session.selectedNotes == Set([note.id])
                  && session.timeSelection == nil,
                  cppID: keyID,
                  message: "the selected primary-track pitch note has no time selection")
    let openingIndex = document.history.undoIndex
    report.expect(shell.routeEditorKey(key: 0x47, modifiers: 0, autoRepeat: false),
                  cppID: keyID, message: "the first routed G opens the selected pitch note")
    let editor = tab.pitchBendPresenter()
    guard editor.isOpen, let firstGraph = editor.currentPitch else {
        report.fail(keyID, "the routed pitch opener has no live graph")
        return
    }
    report.expect(shell.routeEditorKey(key: 0x47, modifiers: 0, autoRepeat: true),
                  cppID: keyID, message: "eligible pitch G autorepeat is consumed by the production route")
    report.expect(editor.isOpen && editor.currentPitch === firstGraph
                  && document.history.undoIndex == openingIndex
                  && (try? document.state.file.encoded()) == baseline,
                  cppID: keyID,
                  message: "pitch G autorepeat retains the one opening and never creates a second transaction")
    pitchBendStroke(firstGraph, x0f: 0.20, y0f: 0.75,
                    x1f: 0.80, y1f: 0.25)
    report.expect(document.history.undoIndex == openingIndex + 1
                  && (try? document.state.file.encoded()) != baseline,
                  cppID: curveID,
                  message: "the selected note's drawn pitch curve commits one song transaction")
    shell.activate(id: "edit.undo")
    report.expect(until({ document.history.undoIndex == openingIndex
                         && (try? document.state.file.encoded()) == baseline }),
                  cppID: curveID,
                  message: "canonical window Undo restores the exact serialized full-song bytes")
    report.expect(editor.isOpen && editor.currentPitch === firstGraph,
                  cppID: curveID,
                  message: "canonical window Undo keeps the original pitch popup graph alive")
    editor.cancelAndClose()
    let page = tab.automationPage()
    let selectedLanes: Set<AutomationParameter> = [
        .controlChange(track: 0, controller: TimeDefaults.ccPan),
        .controlChange(track: 0, controller: TimeDefaults.ccModulation),
    ]
    let selectedRange = TimeRange(startTick: 5760, endTick: 5784)
    page.selectRange(from: selectedRange.startTick, to: selectedRange.endTick,
                     lanes: selectedLanes)
    report.expect(session.timeSelection?.range == selectedRange, cppID: tapID,
                  message: "the Tap draft starts with the exact selected time bounds")
    report.expect(session.timeSelection?.scope == .lanes, cppID: tapID,
                  message: "the Tap draft starts with lane-scoped time selection")
    report.expect(session.timeSelection?.lanes == selectedLanes, cppID: tapID,
                  message: "the Tap draft starts with Pan and Modulation selected")
    report.expect(session.timeSelection?.tempo == false && session.selectedNotes.isEmpty,
                  cppID: tapID,
                  message: "the Tap draft excludes Tempo and has no competing note selection")
    let tapIndex = document.history.undoIndex
    let tapCount = document.history.undoCount
    let tapNotes = session.selectedNotes
    let tapSelection = session.timeSelection
    page.tapTempoTap(atMilliseconds: 1_000)
    page.tapTempoTap(atMilliseconds: 1_500)
    report.expect(page.tapTempoTapCount == 2, cppID: tapID,
                  message: "the real automation page holds two uncommitted tempo taps")
    shell.activate(id: "transport.play_pause")
    report.expect(document.history.undoCount == tapCount, cppID: tapID,
                  message: "window Space during a Tap draft preserves the exact undo count")
    report.expect(document.history.undoIndex == tapIndex, cppID: tapID,
                  message: "window Space during a Tap draft preserves the exact undo index")
    report.expect(session.selectedNotes == tapNotes && session.timeSelection == tapSelection,
                  cppID: tapID,
                  message: "window Space during a Tap draft preserves the selected note and time range")
    report.expect(session.timeSelection?.range == selectedRange
                  && session.timeSelection?.scope == .lanes
                  && session.timeSelection?.lanes == selectedLanes
                  && session.timeSelection?.tempo == false
                  && session.selectedNotes.isEmpty,
                  cppID: tapID,
                  message: "window Space retains exact Pan and Modulation bounds without Tempo or notes")
    shell.activate(id: "transport.play_pause")
    page.resetTapTempo()
}
