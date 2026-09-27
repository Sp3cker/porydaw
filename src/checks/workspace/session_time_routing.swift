import Foundation
import PorydawApp
import PorydawCore
import PorydawCoreCheckNative
import PorydawPlayback

// MARK: - Session Time Routing

@MainActor
internal func runTimeRoutingChecks(report: CheckReport, suite: DocumentSession,
                                   service: ProjectService) {
    let insertID = "mainwindowrouting/MainWindowRoutingInputTest::insertTimeRoutesActiveSongAndRestoresUndoBytes"
    let selectionID = "mainwindowrouting/MainWindowRoutingInputTest::insertTimeActionAnchorsSelectionDuringPlayback"
    let deleteID = "mainwindowrouting/MainWindowRoutingInputTest::deleteTimeActionRipplesScopedAndWholeSongSelections"
    let file = MidiFile(division: 24, chunks: [
        MidiChunk(events: [], endTick: 192),
        MidiChunk(events: [
            .channel(tick: 0, status: 0x90, data0: 60, data1: 80),
            .channel(tick: 8, status: 0x80, data0: 60),
            .channel(tick: 24, status: 0x90, data0: 62, data1: 80),
            .channel(tick: 32, status: 0x80, data0: 62),
            .channel(tick: 48, status: 0x90, data0: 64, data1: 80),
            .channel(tick: 56, status: 0x80, data0: 64),
            .channel(tick: 96, status: 0x90, data0: 66, data1: 80),
            .channel(tick: 104, status: 0x80, data0: 66),
        ], endTick: 192),
        MidiChunk(events: [
            .channel(tick: 24, status: 0x91, data0: 70, data1: 80),
            .channel(tick: 32, status: 0x81, data0: 70),
            .channel(tick: 120, status: 0x91, data0: 72, data1: 80),
            .channel(tick: 128, status: 0x81, data0: 72),
        ], endTick: 192),
    ])
    let document = SongDocument(file: file, config: suite.document.state.config,
                                source: suite.document.source, trackBudget: suite.document.trackBudget)
    let session = DocumentSession(document: document, service: service,
                                  lease: suite.bankLease, slots: suite.bankSlots,
                                  dirty: false, loadName: suite.bankLoadName, sampleRate: 48_000)
    let grid = PianoGrid(session: session)
    let page = AutomationPage()
    page.attach(session: session, palette: GridPalette())
    defer { page.detach() }
    session.onChange = { [weak page] _ in page?.refreshFromDocument() }
    session.selectedTrack = 0
    let ruler = RulerMenuPresenter(session: session, grid: grid, automation: page)
    let router = EditorCommandRouter(session: session, grid: grid, automation: page, rulerMenu: ruler)
    guard let source = document.notes(in: 0).first(where: { $0.tick == 0 }),
          let inside = document.notes(in: 0).first(where: { $0.tick == 24 }),
          let seam = document.notes(in: 0).first(where: { $0.tick == 48 }),
          let later = document.notes(in: 0).first(where: { $0.tick == 96 }),
          let otherInside = document.notes(in: 1).first(where: { $0.tick == 24 }),
          let otherLater = document.notes(in: 1).first(where: { $0.tick == 120 }),
          let original = try? document.state.file.encoded(),
          let inactiveBytes = try? suite.document.state.file.encoded()
    else {
        report.fail(insertID, "two-track time routing fixture did not encode or project notes")
        return
    }
    let originalIndex = document.history.undoIndex
    document.setTimeSignature(tick: 0, numerator: 3, denominatorPower: 6)
    guard let promptBytes = try? document.state.file.encoded() else {
        report.fail(insertID, "3/64 insertion fixture did not encode")
        return
    }
    session.editCursor = 20
    for (label, bars, beats, fractions, shift, playing) in [
        ("stopped two beats", 0, 2, 0, Tick(2), false),
        ("playing one bar", 1, 0, 0, Tick(3), true),
        ("playing quarter beat", 0, 0, 1, Tick(1), true),
    ] {
        let beforeRevision = document.revision
        let beforeIndex = document.history.undoIndex
        page.refreshPlayhead(tick: 96, playing: playing)
        report.expect(router.isAvailable(.insertTime), cppID: insertID,
                      message: "\(label) admits standalone Insert Time without a range")
        router.perform(.insertTime)
        report.expect(ruler.insertTimePromptOpen && ruler.insertTimePromptInitialBars == 1
                      && ruler.insertTimePromptInitialBeats == 0
                      && ruler.insertTimePromptInitialBeatFractions == 0
                      && ruler.insertTimePromptMaximumBeats == 2,
                      cppID: insertID, message: "\(label) displays the captured 3/64 defaults")
        report.expect(document.revision == beforeRevision && session.editCursor == 20
                      && page.contextTick == (playing ? 96 : 20),
                      cppID: insertID, message: "\(label) opens at the edit cursor without seeking or editing")
        if playing {
            page.refreshPlayhead(tick: 120, playing: true)
            report.expect(page.contextTick == 120, cppID: insertID,
                          message: "\(label) advances the playing playhead under the prompt")
            report.expect(ruler.insertTimePromptOpen, cppID: insertID,
                          message: "\(label) advancing playhead keeps the captured prompt open")
            report.expect(session.editCursor == 20, cppID: insertID,
                          message: "\(label) advancing playhead preserves the captured edit cursor")
        }
        ruler.acceptInsertTimePrompt(bars: bars, beats: beats, fractions: fractions)
        report.expect(document.note(inside.id)?.tick == 24 + shift,
                      cppID: insertID, message: "\(label) shifts the first track by the exact span")
        report.expect(document.note(otherInside.id)?.tick == 24 + shift,
                      cppID: insertID, message: "\(label) shifts the second track by the exact span")
        report.expectEqual(expected: beforeRevision + 1, actual: document.revision,
                           cppID: insertID, what: "\(label) commits one revision")
        report.expectEqual(expected: beforeIndex + 1, actual: document.history.undoIndex,
                           cppID: insertID, what: "\(label) records one undo entry")
        report.expect((try? suite.document.state.file.encoded()) == inactiveBytes,
                      cppID: insertID, message: "\(label) leaves the inactive song's bytes unchanged")
        report.expect(!ruler.insertTimePromptOpen, cppID: insertID,
                      message: "\(label) acceptance closes the form")
        report.expect(document.history.undoDocument()
                      && (try? document.state.file.encoded()) == promptBytes,
                      cppID: insertID, message: "\(label) one undo restores exact MIDI bytes")
        report.expectEqual(expected: beforeIndex, actual: document.history.undoIndex,
                           cppID: insertID, what: "\(label) one undo restores the history index")
    }
    page.refreshPlayhead(tick: 0, playing: false)
    let noOpRevision = document.revision
    let noOpIndex = document.history.undoIndex
    let noOpCount = document.history.undoCount
    router.perform(.insertTime)
    ruler.acceptInsertTimePrompt(bars: 0, beats: 0, fractions: 0)
    report.expect(!ruler.insertTimePromptOpen, cppID: insertID,
                  message: "zero acceptance closes the standalone form")
    report.expect((try? document.state.file.encoded()) == promptBytes,
                  cppID: insertID, message: "zero acceptance leaves active MIDI bytes unchanged")
    report.expect((try? suite.document.state.file.encoded()) == inactiveBytes,
                  cppID: insertID, message: "zero acceptance leaves inactive MIDI bytes unchanged")
    report.expectEqual(expected: noOpRevision, actual: document.revision, cppID: insertID,
                       what: "zero acceptance preserves revision")
    report.expect(document.history.undoIndex == noOpIndex
                  && document.history.undoCount == noOpCount,
                  cppID: insertID, message: "zero acceptance preserves history")
    router.perform(.insertTime)
    ruler.cancelInsertTimePrompt()
    report.expect(!ruler.insertTimePromptOpen, cppID: insertID,
                  message: "Cancel closes the standalone form")
    report.expect((try? document.state.file.encoded()) == promptBytes,
                  cppID: insertID, message: "Cancel preserves active MIDI bytes")
    report.expectEqual(expected: noOpRevision, actual: document.revision, cppID: insertID,
                       what: "Cancel preserves revision")
    report.expect(document.history.undoIndex == noOpIndex
                  && document.history.undoCount == noOpCount,
                  cppID: insertID, message: "Cancel preserves history")
    router.perform(.insertTime)
    document.setTimeSignature(tick: 48, numerator: 4, denominatorPower: 2)
    guard let interveningBytes = try? document.state.file.encoded() else {
        report.fail(insertID, "intervening time-signature edit did not encode")
        return
    }
    let interveningRevision = document.revision
    let interveningIndex = document.history.undoIndex
    let interveningCount = document.history.undoCount
    ruler.acceptInsertTimePrompt(bars: 1, beats: 0, fractions: 0)
    report.expect(!ruler.insertTimePromptOpen, cppID: insertID,
                  message: "stale acceptance closes the form")
    report.expect((try? document.state.file.encoded()) == interveningBytes,
                  cppID: insertID, message: "stale acceptance preserves the intervening MIDI bytes")
    report.expectEqual(expected: interveningRevision, actual: document.revision, cppID: insertID,
                       what: "stale acceptance preserves the intervening revision")
    report.expectEqual(expected: interveningIndex, actual: document.history.undoIndex,
                       cppID: insertID, what: "stale acceptance preserves the undo index")
    report.expectEqual(expected: interveningCount, actual: document.history.undoCount,
                       cppID: insertID, what: "stale acceptance preserves the undo count")
    _ = document.history.undoDocument()
    _ = document.history.undoDocument()


    func expectSingleRevisionEntry(revision: UInt64, revisionWhat: String, undoWhat: String, cppID: String) {
        report.expectEqual(expected: revision + 1, actual: document.revision, cppID: cppID, what: revisionWhat)
        report.expectEqual(expected: originalIndex + 1, actual: document.history.undoIndex, cppID: cppID, what: undoWhat)
    }
    func expectUndoRestoresBytes(cppID: String, message: String) {
        report.expect(document.history.undoDocument() &&
                      (try? document.state.file.encoded()) == original &&
                      document.history.undoIndex == originalIndex,
                      cppID: cppID, message: message)
    }

    let wholeRange = TimeRange(startTick: 24, endTick: 48)
    let wholeRevision = document.revision
    report.expect(document.insertBlankTime(wholeRange, scope: TimeScope(wholeSong: true)),
                  cppID: insertID, message: "whole-song insertion commits across tracks")
    report.expect(document.note(inside.id)?.tick == 48 &&
                  document.note(seam.id)?.tick == 72 &&
                  document.note(otherInside.id)?.tick == 48 &&
                  document.note(otherLater.id)?.tick == 144,
                  cppID: insertID, message: "whole-song insertion shifts both tracks by 24 ticks")
    expectSingleRevisionEntry(revision: wholeRevision,
                              revisionWhat: "whole-song insertion advances one revision",
                              undoWhat: "whole-song insertion records one undo entry", cppID: insertID)
    expectUndoRestoresBytes(cppID: insertID,
                            message: "one undo restores exact whole-song insertion bytes")

    let scopedRange = TimeRange(startTick: 48, endTick: 72)
    page.applyTimeSelection(AutomationTimeSelection(range: scopedRange, scope: .tracks([0])))
    session.editCursor = 0
    page.refreshPlayhead(tick: 96, playing: true)
    report.expectEqual(expected: Tick(96), actual: page.contextTick, cppID: selectionID,
                       what: "advancing playback context stays away from the selected insertion seam")
    let scopedRevision = document.revision
    report.expect(router.isAvailable(.insertTime), cppID: selectionID,
                  message: "selected track admits routed Insert Time")
    router.perform(.insertTime)
    report.expect(document.note(seam.id)?.tick == 72 &&
                  document.note(later.id)?.tick == 120 &&
                  document.note(otherLater.id)?.tick == 120 &&
                  document.note(otherInside.id)?.tick == 24,
                  cppID: selectionID, message: "routed insertion anchors on selection instead of cursor and shifts only its track")
    report.expect(page.selection?.range == scopedRange && session.editCursor == 48,
                  cppID: selectionID, message: "routed insertion retains selected span and parks cursor at its start")
    expectSingleRevisionEntry(revision: scopedRevision,
                              revisionWhat: "routed insertion advances one revision",
                              undoWhat: "routed insertion records one undo entry", cppID: selectionID)
    expectUndoRestoresBytes(cppID: selectionID,
                            message: "one undo restores exact routed insertion bytes")
    page.clearTimeSelection()
    page.refreshPlayhead(tick: 0, playing: false)

    let zeroBytes = try? document.state.file.encoded()
    let zeroRevision = document.revision
    let zeroIndex = document.history.undoIndex
    let zeroCount = document.history.undoCount
    report.expect(!document.insertBlankTime(TimeRange(startTick: 48, endTick: 48),
                                            scope: TimeScope(wholeSong: true)) &&
                  (try? document.state.file.encoded()) == zeroBytes &&
                  document.revision == zeroRevision,
                  cppID: insertID, message: "zero-span insertion leaves bytes and revision untouched")
    report.expect(document.history.undoIndex == zeroIndex &&
                  document.history.undoCount == zeroCount,
                  cppID: insertID, message: "zero-span insertion records no history")

    let deleteRange = TimeRange(startTick: 24, endTick: 48)
    page.applyTimeSelection(AutomationTimeSelection(range: deleteRange, scope: .tracks([0])))
    session.editCursor = 96
    let scopedDeleteRevision = document.revision
    report.expect(router.isAvailable(.deleteTime), cppID: deleteID,
                  message: "selected track admits routed Delete Time")
    router.perform(.deleteTime)
    report.expect(document.note(inside.id) == nil &&
                  document.note(seam.id)?.tick == 24 &&
                  document.note(later.id)?.tick == 72 &&
                  document.note(source.id)?.tick == 0 &&
                  document.note(otherInside.id)?.tick == 24 &&
                  document.note(otherLater.id)?.tick == 120,
                  cppID: deleteID, message: "scoped removal deletes in-range notes and ripples only the chosen track")
    report.expect(page.selection == nil && session.editCursor == 24,
                  cppID: deleteID, message: "routed removal clears selection and parks cursor at seam")
    expectSingleRevisionEntry(revision: scopedDeleteRevision,
                              revisionWhat: "scoped removal advances one revision",
                              undoWhat: "scoped removal records one undo entry", cppID: deleteID)
    expectUndoRestoresBytes(cppID: deleteID,
                            message: "one undo restores exact scoped removal bytes")

    let allTracks = Set(0..<document.engineTracks.usedTrackCount)
    page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 48), scope: .tracks(allTracks)))
    session.editCursor = 96
    let wholeDeleteRevision = document.revision
    router.perform(.deleteTime)
    report.expect(document.note(source.id) == nil && document.note(inside.id) == nil &&
                  document.note(otherInside.id) == nil &&
                  document.note(seam.id)?.tick == 0 &&
                  document.note(later.id)?.tick == 48 &&
                  document.note(otherLater.id)?.tick == 72,
                  cppID: deleteID, message: "all-track removal deletes across tracks and ripples later notes")
    report.expect(page.selection == nil && session.editCursor == 0,
                  cppID: deleteID, message: "whole selection removal clears range and parks cursor at zero")
    expectSingleRevisionEntry(revision: wholeDeleteRevision,
                              revisionWhat: "whole selection removal advances one revision",
                              undoWhat: "whole selection removal records one undo entry", cppID: deleteID)
    expectUndoRestoresBytes(cppID: deleteID,
                            message: "one undo restores exact all-track removal bytes")
}
