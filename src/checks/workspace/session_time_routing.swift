import Foundation
import PorydawApp
import PorydawAppPresentation
import PorydawAppCommands
import PorydawCore
import PorydawCoreCheckNative
import PorydawDocument
import PorydawPlayback

// MARK: - Session Time Routing

@MainActor
internal func runTimeRoutingChecks(
    report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let insertID = "mainwindowrouting/MainWindowRoutingInputTest::insertTimeRoutesActiveSongAndRestoresUndoBytes"
    let selectionID = "mainwindowrouting/MainWindowRoutingInputTest::insertTimeActionAnchorsSelectionDuringPlayback"
    let deleteID = "mainwindowrouting/MainWindowRoutingInputTest::deleteTimeActionRipplesScopedAndWholeSongSelections"
    let file = MidiFile(
        division: 24,
        chunks: [
            MidiChunk(events: [], endTick: 192),
            MidiChunk(
                events: [
                    .channel(tick: 0, status: 0x90, data0: 60, data1: 80),
                    .channel(tick: 8, status: 0x80, data0: 60),
                    .channel(tick: 24, status: 0x90, data0: 62, data1: 80),
                    .channel(tick: 32, status: 0x80, data0: 62),
                    .channel(tick: 48, status: 0x90, data0: 64, data1: 80),
                    .channel(tick: 56, status: 0x80, data0: 64),
                    .channel(tick: 96, status: 0x90, data0: 66, data1: 80),
                    .channel(tick: 104, status: 0x80, data0: 66),
                ], endTick: 192),
            MidiChunk(
                events: [
                    .channel(tick: 24, status: 0x91, data0: 70, data1: 80),
                    .channel(tick: 32, status: 0x81, data0: 70),
                    .channel(tick: 120, status: 0x91, data0: 72, data1: 80),
                    .channel(tick: 128, status: 0x81, data0: 72),
                ], endTick: 192),
        ])
    let document = SongDocument(
        file: file, config: suite.document.state.config,
        source: suite.document.source, trackBudget: suite.document.trackBudget)
    let session = DocumentSession(
        document: document, service: service,
        lease: suite.bankLease, slots: suite.bankSlots,
        dirty: false, loadName: suite.bankLoadName, sampleRate: 48_000)
    let viewport = DocumentViewport(session: session)
    let grid = PianoGrid(viewport: viewport)
    let page = AutomationPage()
    page.attach(viewport: viewport, palette: GridPalette())
    defer { page.detach() }
    session.onChange = { [weak page] _ in page?.refreshFromDocument() }
    session.selectedTrack = 0
    let ruler = RulerMenuPresenter(viewport: viewport, grid: grid, automation: page)
    let router = EditorCommandRouter(session: session, grid: grid, automation: page, rulerMenu: ruler)
    guard let source = document.notes(in: 0).first(where: { $0.tick == 0 }),
        let inside = document.notes(in: 0).first(where: { $0.tick == 24 }),
        let seam = document.notes(in: 0).first(where: { $0.tick == 48 }),
        let later = document.notes(in: 0).first(where: { $0.tick == 96 }),
        let otherInside = document.notes(in: 1).first(where: { $0.tick == 24 }),
        let otherLater = document.notes(in: 1).first(where: { $0.tick == 120 })
    else {
        report.fail(insertID, "two-track time routing fixture did not encode or project notes")
        return
    }
    guard
        let excludedLaterID = try? document.addNotes([
            NewNote(track: 1, tick: 72, pitch: 74, duration: 8, velocity: 80)
        ]).first,
        let excludedLater = document.note(excludedLaterID),
        let original = try? document.state.file.encoded(),
        let inactiveBytes = try? suite.document.state.file.encoded()
    else {
        report.fail(deleteID, "the excluded-track later note did not seed or encode")
        return
    }
    let originalIndex = document.history.undoIndex
    document.setTimeSignature(tick: 0, numerator: 3, denominatorPower: 6)
    let signatureAxis = TimeAxis(
        map: TimeMap(
            ticksPerBeat: UInt32(document.ticksPerBeat),
            timeSigs: document.timeSignatures.map {
                TimeSigPoint(
                    tick: $0.tick, numerator: $0.numerator,
                    denomPow2: $0.denominatorPower)
            }))
    let sourceSegment = signatureAxis.segmentAt(source.tick)
    report.expect(
        sourceSegment.beatTicks == 1 && sourceSegment.beatsPerBar == 3,
        cppID: insertID,
        message: "A092: the 3/64 signature gives the source segment one tick per beat and three beats per bar")
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
        report.expect(
            router.isAvailable(.insertTime), cppID: insertID,
            message: "\(label) admits standalone Insert Time without a range")
        router.perform(.insertTime)
        report.expect(
            ruler.insertTimePromptOpen && ruler.insertTimePromptInitialBars == 1
                && ruler.insertTimePromptInitialBeats == 0
                && ruler.insertTimePromptInitialBeatFractions == 0
                && ruler.insertTimePromptMaximumBeats == 2,
            cppID: insertID, message: "\(label) displays the captured 3/64 defaults")
        report.expect(
            document.revision == beforeRevision && session.editCursor == 20
                && page.contextTick == (playing ? 96 : 20),
            cppID: insertID, message: "\(label) opens at the edit cursor without seeking or editing")
        if playing {
            page.refreshPlayhead(tick: 120, playing: true)
            report.expect(
                page.contextTick == 120, cppID: insertID,
                message: "\(label) advances the playing playhead under the prompt")
            report.expect(
                ruler.insertTimePromptOpen, cppID: insertID,
                message: "\(label) advancing playhead keeps the captured prompt open")
            report.expect(
                session.editCursor == 20, cppID: insertID,
                message: "\(label) advancing playhead preserves the captured edit cursor")
        }
        ruler.acceptInsertTimePrompt(bars: bars, beats: beats, fractions: fractions)
        report.expect(
            document.note(inside.id)?.tick == 24 + shift,
            cppID: insertID, message: "\(label) shifts the first track by the exact span")
        report.expect(
            document.note(otherInside.id)?.tick == 24 + shift,
            cppID: insertID, message: "\(label) shifts the second track by the exact span")
        report.expectEqual(
            expected: beforeRevision + 1, actual: document.revision,
            cppID: insertID, what: "\(label) commits one revision")
        report.expectEqual(
            expected: beforeIndex + 1, actual: document.history.undoIndex,
            cppID: insertID, what: "\(label) records one undo entry")
        report.expect(
            (try? suite.document.state.file.encoded()) == inactiveBytes,
            cppID: insertID, message: "\(label) leaves the inactive song's bytes unchanged")
        report.expect(
            !ruler.insertTimePromptOpen, cppID: insertID,
            message: "\(label) acceptance closes the form")
        report.expect(
            document.history.undoDocument()
                && (try? document.state.file.encoded()) == promptBytes,
            cppID: insertID, message: "\(label) one undo restores exact MIDI bytes")
        report.expectEqual(
            expected: beforeIndex, actual: document.history.undoIndex,
            cppID: insertID, what: "\(label) one undo restores the history index")
    }
    page.refreshPlayhead(tick: 0, playing: false)
    let noOpRevision = document.revision
    let noOpIndex = document.history.undoIndex
    let noOpCount = document.history.undoCount
    router.perform(.insertTime)
    ruler.acceptInsertTimePrompt(bars: 0, beats: 0, fractions: 0)
    report.expect(
        !ruler.insertTimePromptOpen, cppID: insertID,
        message: "zero acceptance closes the standalone form")
    report.expect(
        (try? document.state.file.encoded()) == promptBytes,
        cppID: insertID, message: "zero acceptance leaves active MIDI bytes unchanged")
    report.expect(
        (try? suite.document.state.file.encoded()) == inactiveBytes,
        cppID: insertID, message: "zero acceptance leaves inactive MIDI bytes unchanged")
    report.expectEqual(
        expected: noOpRevision, actual: document.revision, cppID: insertID,
        what: "zero acceptance preserves revision")
    report.expect(
        document.history.undoIndex == noOpIndex
            && document.history.undoCount == noOpCount,
        cppID: insertID, message: "zero acceptance preserves history")
    router.perform(.insertTime)
    ruler.cancelInsertTimePrompt()
    report.expect(
        !ruler.insertTimePromptOpen, cppID: insertID,
        message: "Cancel closes the standalone form")
    report.expect(
        (try? document.state.file.encoded()) == promptBytes,
        cppID: insertID, message: "Cancel preserves active MIDI bytes")
    report.expectEqual(
        expected: noOpRevision, actual: document.revision, cppID: insertID,
        what: "Cancel preserves revision")
    report.expect(
        document.history.undoIndex == noOpIndex
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
    report.expect(
        !ruler.insertTimePromptOpen, cppID: insertID,
        message: "stale acceptance closes the form")
    report.expect(
        (try? document.state.file.encoded()) == interveningBytes,
        cppID: insertID, message: "stale acceptance preserves the intervening MIDI bytes")
    report.expectEqual(
        expected: interveningRevision, actual: document.revision, cppID: insertID,
        what: "stale acceptance preserves the intervening revision")
    report.expectEqual(
        expected: interveningIndex, actual: document.history.undoIndex,
        cppID: insertID, what: "stale acceptance preserves the undo index")
    report.expectEqual(
        expected: interveningCount, actual: document.history.undoCount,
        cppID: insertID, what: "stale acceptance preserves the undo count")
    _ = document.history.undoDocument()
    _ = document.history.undoDocument()

    func expectSingleRevisionEntry(revision: UInt64, revisionWhat: String, undoWhat: String, cppID: String) {
        report.expectEqual(expected: revision + 1, actual: document.revision, cppID: cppID, what: revisionWhat)
        report.expectEqual(
            expected: originalIndex + 1, actual: document.history.undoIndex, cppID: cppID, what: undoWhat)
    }
    func expectUndoRestoresBytes(cppID: String, message: String) {
        report.expect(
            document.history.undoDocument() && (try? document.state.file.encoded()) == original
                && document.history.undoIndex == originalIndex,
            cppID: cppID, message: message)
    }

    let wholeRange = TimeRange(startTick: 24, endTick: 48)
    let wholeRevision = document.revision
    report.expect(
        document.insertBlankTime(wholeRange, scope: TimeScope(wholeSong: true)),
        cppID: insertID, message: "whole-song insertion commits across tracks")
    report.expect(
        document.note(inside.id)?.tick == 48 && document.note(seam.id)?.tick == 72
            && document.note(otherInside.id)?.tick == 48 && document.note(otherLater.id)?.tick == 144,
        cppID: insertID, message: "whole-song insertion shifts both tracks by 24 ticks")
    expectSingleRevisionEntry(
        revision: wholeRevision,
        revisionWhat: "whole-song insertion advances one revision",
        undoWhat: "whole-song insertion records one undo entry", cppID: insertID)
    expectUndoRestoresBytes(
        cppID: insertID,
        message: "one undo restores exact whole-song insertion bytes")

    let scopedRange = TimeRange(startTick: 48, endTick: 72)
    page.applyTimeSelection(AutomationTimeSelection(range: scopedRange, scope: .tracks([0])))
    session.editCursor = 0
    page.refreshPlayhead(tick: 24, playing: true)
    report.expectEqual(
        expected: Tick(24), actual: page.contextTick, cppID: selectionID,
        what: "advancing playback context stays away from the selected insertion seam")
    report.expectEqual(
        expected: Tick(0), actual: session.editCursor, cppID: selectionID,
        what: "playing insertion begins with its edit cursor before the range")
    let scopedRevision = document.revision
    let scopedIndex = document.history.undoIndex
    report.expect(
        router.isAvailable(.insertTime), cppID: selectionID,
        message: "selected track admits routed Insert Time")
    router.perform(.insertTime)
    report.expect(
        !ruler.insertTimePromptOpen, cppID: selectionID,
        message: "playing selected insertion bypasses the ruler prompt")
    report.expect(
        document.note(seam.id)?.tick == 72 && document.note(later.id)?.tick == 120
            && document.note(otherLater.id)?.tick == 120 && document.note(otherInside.id)?.tick == 24,
        cppID: selectionID, message: "routed insertion anchors on selection instead of cursor and shifts only its track"
    )
    report.expect(
        document.note(seam.id) != nil, cppID: selectionID,
        message: "playing insertion retains the seam note identity")
    report.expect(
        document.note(otherInside.id) != nil, cppID: selectionID,
        message: "playing insertion retains the excluded track's note identity")
    report.expectEqual(
        expected: Tick(72), actual: document.note(seam.id)?.tick,
        cppID: selectionID, what: "playing insertion shifts the seam note by the interval width")
    report.expectEqual(
        expected: seam.pitch, actual: document.note(seam.id)?.pitch,
        cppID: selectionID, what: "playing insertion preserves the seam note pitch")
    report.expectEqual(
        expected: otherLater.tick, actual: document.note(otherLater.id)?.tick,
        cppID: selectionID, what: "playing insertion leaves the excluded later note at its tick")
    report.expectEqual(
        expected: otherInside.tick, actual: document.note(otherInside.id)?.tick,
        cppID: selectionID, what: "playing insertion leaves the excluded inside note at its tick")
    report.expectEqual(
        expected: excludedLater.tick, actual: document.note(excludedLaterID)?.tick,
        cppID: selectionID, what: "playing insertion leaves the excluded seam note in place")
    report.expect(
        page.selection?.isActive == true, cppID: selectionID,
        message: "playing insertion retains an active time range")
    report.expect(
        page.selection?.range == scopedRange && session.editCursor == 48,
        cppID: selectionID, message: "routed insertion retains selected span and parks cursor at its start")
    report.expectEqual(
        expected: scopedRange.startTick, actual: page.selection?.range.startTick,
        cppID: selectionID, what: "playing insertion retains the range start")
    report.expectEqual(
        expected: scopedRange.endTick, actual: page.selection?.range.endTick,
        cppID: selectionID, what: "playing insertion retains the range end")
    report.expect(
        page.selection?.scope == .tracks([0]), cppID: selectionID,
        message: "playing insertion retains only the chosen track scope")
    report.expectEqual(
        expected: scopedRange.startTick, actual: session.editCursor,
        cppID: selectionID, what: "playing insertion parks the edit cursor at the selected start")
    report.expectEqual(
        expected: Tick(24), actual: page.contextTick, cppID: selectionID,
        what: "playing insertion does not retarget the playhead")
    expectSingleRevisionEntry(
        revision: scopedRevision,
        revisionWhat: "routed insertion advances one revision",
        undoWhat: "routed insertion records one undo entry", cppID: selectionID)
    report.expectEqual(
        expected: scopedIndex + 1, actual: document.history.undoIndex,
        cppID: selectionID, what: "playing insertion adds exactly one history step")
    page.refreshPlayhead(tick: 0, playing: false)
    expectUndoRestoresBytes(
        cppID: selectionID,
        message: "one undo restores exact routed insertion bytes")
    report.expect(
        (try? document.state.file.encoded()) == original, cppID: selectionID,
        message: "stopped insertion undo restores the exact original MIDI bytes")
    report.expectEqual(
        expected: scopedIndex, actual: document.history.undoIndex,
        cppID: selectionID, what: "stopped insertion undo returns to its original history position")
    page.clearTimeSelection()

    let zeroBytes = try? document.state.file.encoded()
    let zeroRevision = document.revision
    let zeroIndex = document.history.undoIndex
    let zeroCount = document.history.undoCount
    report.expect(
        !document.insertBlankTime(
            TimeRange(startTick: 48, endTick: 48),
            scope: TimeScope(wholeSong: true)) && (try? document.state.file.encoded()) == zeroBytes
            && document.revision == zeroRevision,
        cppID: insertID, message: "zero-span insertion leaves bytes and revision untouched")
    report.expect(
        document.history.undoIndex == zeroIndex && document.history.undoCount == zeroCount,
        cppID: insertID, message: "zero-span insertion records no history")

    let deleteRange = TimeRange(startTick: 24, endTick: 48)
    page.applyTimeSelection(AutomationTimeSelection(range: deleteRange, scope: .tracks([0])))
    session.editCursor = 96
    let scopedDeleteRevision = document.revision
    let scopedDeleteIndex = document.history.undoIndex
    report.expect(
        router.isAvailable(.deleteTime), cppID: deleteID,
        message: "selected track admits routed Delete Time")
    router.perform(.deleteTime)
    report.expect(
        !ruler.insertTimePromptOpen, cppID: deleteID,
        message: "scoped Delete Time never opens the insertion prompt")
    report.expect(
        document.note(inside.id) == nil && document.note(seam.id)?.tick == 24 && document.note(later.id)?.tick == 72
            && document.note(source.id)?.tick == 0 && document.note(otherInside.id)?.tick == 24
            && document.note(otherLater.id)?.tick == 120,
        cppID: deleteID, message: "scoped removal deletes in-range notes and ripples only the chosen track")
    report.expect(
        document.note(inside.id) == nil, cppID: deleteID,
        message: "scoped deletion removes its inside note")
    report.expect(
        document.note(later.id) != nil, cppID: deleteID,
        message: "scoped deletion retains the later note identity")
    report.expect(
        document.note(source.id) != nil, cppID: deleteID,
        message: "scoped deletion retains the earlier note identity")
    report.expect(
        document.note(otherInside.id) != nil, cppID: deleteID,
        message: "scoped deletion retains the excluded track's note identity")
    report.expectEqual(
        expected: Tick(24), actual: document.note(seam.id)?.tick,
        cppID: deleteID, what: "scoped deletion moves the seam note left one interval")
    report.expectEqual(
        expected: Tick(72), actual: document.note(later.id)?.tick,
        cppID: deleteID, what: "scoped deletion ripples the later note left one interval")
    report.expectEqual(
        expected: source.tick, actual: document.note(source.id)?.tick,
        cppID: deleteID, what: "scoped deletion preserves its earlier note")
    report.expectEqual(
        expected: otherInside.tick, actual: document.note(otherInside.id)?.tick,
        cppID: deleteID, what: "scoped deletion preserves the excluded inside note")
    report.expectEqual(
        expected: otherLater.tick, actual: document.note(otherLater.id)?.tick,
        cppID: deleteID, what: "scoped deletion preserves the excluded later note")
    report.expectEqual(
        expected: excludedLater.tick, actual: document.note(excludedLaterID)?.tick,
        cppID: deleteID, what: "scoped deletion leaves the excluded later seam note in place")
    report.expect(
        page.selection == nil && session.editCursor == 24,
        cppID: deleteID, message: "routed removal clears selection and parks cursor at seam")
    report.expect(
        page.selection == nil, cppID: deleteID,
        message: "scoped deletion clears the active time range")
    report.expectEqual(
        expected: deleteRange.startTick, actual: session.editCursor,
        cppID: deleteID, what: "scoped deletion parks the edit cursor at the range start")
    expectSingleRevisionEntry(
        revision: scopedDeleteRevision,
        revisionWhat: "scoped removal advances one revision",
        undoWhat: "scoped removal records one undo entry", cppID: deleteID)
    report.expectEqual(
        expected: scopedDeleteIndex + 1, actual: document.history.undoIndex,
        cppID: deleteID, what: "scoped deletion records exactly one history step")
    expectUndoRestoresBytes(
        cppID: deleteID,
        message: "one undo restores exact scoped removal bytes")
    report.expect(
        (try? document.state.file.encoded()) == original, cppID: deleteID,
        message: "scoped deletion undo restores the exact original MIDI bytes")
    report.expectEqual(
        expected: scopedDeleteIndex, actual: document.history.undoIndex,
        cppID: deleteID, what: "scoped deletion undo restores the original history position")

    let allTracks = Set(0..<document.engineTracks.usedTrackCount)
    let wholeDeleteRange = TimeRange(startTick: 0, endTick: 48)
    page.applyTimeSelection(AutomationTimeSelection(range: wholeDeleteRange, scope: .tracks(allTracks)))
    report.expect(
        page.selection?.isActive == true, cppID: deleteID,
        message: "whole-song deletion begins with an active range")
    session.editCursor = 96
    report.expectEqual(
        expected: Tick(0), actual: page.selection?.range.startTick,
        cppID: deleteID, what: "whole-song deletion selection starts at zero")
    report.expect(
        page.selection?.scope == .tracks(allTracks), cppID: deleteID,
        message: "whole-song deletion selects every used track")
    report.expect(
        page.selection?.coversTempo(usedTracks: allTracks) == true, cppID: deleteID,
        message: "whole-song deletion selection covers the tempo scope")
    let wholeDeleteRevision = document.revision
    let wholeDeleteIndex = document.history.undoIndex
    report.expect(
        router.isAvailable(.deleteTime), cppID: deleteID,
        message: "whole-song selection enables routed Delete Time")
    router.perform(.deleteTime)
    report.expect(
        !ruler.insertTimePromptOpen, cppID: deleteID,
        message: "whole-song Delete Time never opens the insertion prompt")
    report.expect(
        document.note(source.id) == nil && document.note(inside.id) == nil && document.note(otherInside.id) == nil
            && document.note(seam.id)?.tick == 0 && document.note(later.id)?.tick == 48
            && document.note(otherLater.id)?.tick == 72,
        cppID: deleteID, message: "all-track removal deletes across tracks and ripples later notes")
    report.expect(
        document.note(source.id) == nil, cppID: deleteID,
        message: "whole-song deletion removes the first selected-track note")
    report.expect(
        document.note(inside.id) == nil, cppID: deleteID,
        message: "whole-song deletion removes the second selected-track note")
    report.expect(
        document.note(otherInside.id) == nil, cppID: deleteID,
        message: "whole-song deletion removes the other track's inside note")
    report.expect(
        document.note(excludedLaterID) != nil, cppID: deleteID,
        message: "whole-song deletion retains the other track's later note identity")
    report.expectEqual(
        expected: Tick(24), actual: document.note(excludedLaterID)?.tick,
        cppID: deleteID, what: "whole-song deletion shifts the other track's later note to tick 24")
    report.expectEqual(
        expected: Tick(72), actual: document.note(otherLater.id)?.tick,
        cppID: deleteID, what: "whole-song deletion moves the other track's later note to tick 72")
    report.expect(
        page.selection == nil && session.editCursor == 0,
        cppID: deleteID, message: "whole selection removal clears range and parks cursor at zero")
    report.expect(
        page.selection == nil, cppID: deleteID,
        message: "whole-song deletion clears the active time range")
    report.expectEqual(
        expected: Tick(0), actual: session.editCursor,
        cppID: deleteID, what: "whole-song deletion leaves the edit cursor at zero")
    expectSingleRevisionEntry(
        revision: wholeDeleteRevision,
        revisionWhat: "whole selection removal advances one revision",
        undoWhat: "whole selection removal records one undo entry", cppID: deleteID)
    report.expectEqual(
        expected: wholeDeleteIndex + 1, actual: document.history.undoIndex,
        cppID: deleteID, what: "whole-song deletion records exactly one history step")
    expectUndoRestoresBytes(
        cppID: deleteID,
        message: "one undo restores exact all-track removal bytes")
    report.expect(
        (try? document.state.file.encoded()) == original, cppID: deleteID,
        message: "whole-song deletion undo restores the exact original MIDI bytes")
    report.expectEqual(
        expected: wholeDeleteIndex, actual: document.history.undoIndex,
        cppID: deleteID, what: "whole-song deletion undo restores the original history position")
    checkLiveTabTimeIsolation(report: report, sourcePath: suite.document.source.midiPath)
}

@MainActor
private func checkLiveTabTimeIsolation(report: CheckReport, sourcePath: String) {
    let insertID = "mainwindowrouting/MainWindowRoutingInputTest::insertTimeActionAnchorsSelectionDuringPlayback"
    let deleteID = "mainwindowrouting/MainWindowRoutingInputTest::deleteTimeActionRipplesScopedAndWholeSongSelections"
    let projectRoot = URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path
    let app = ApplicationSession()
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
    app.openProjectAndSong(path: projectRoot, label: "mus_session_test")
    guard until({ app.songOpen || !app.lastSaveError.isEmpty }),
        let active = app.selectedDocument
    else {
        report.fail(insertID, "active time-routing tab failed to open: \(app.lastSaveError)")
        return
    }
    let activeID = app.songTabs.selectedId
    app.openSong(label: "mus_session_test2")
    guard
        until({
            app.songTabs.tabCount == 2 && app.songTabs.selectedId != activeID
                || !app.lastSaveError.isEmpty
        }),
        let inactive = app.selectedDocument,
        let inactiveBytes = try? inactive.document.state.file.encoded()
    else {
        report.fail(insertID, "inactive time-routing tab failed to open: \(app.lastSaveError)")
        return
    }
    app.songTabs.selectTab(tabId: activeID)
    guard app.selectedDocument === active,
        let insideID = try? active.document.addNotes([
            NewNote(track: 0, tick: 24, pitch: 79, duration: 8, velocity: 80)
        ]).first,
        let seam = active.document.notes(in: 0).first(where: { $0.tick == 48 }),
        let original = try? active.document.state.file.encoded()
    else {
        report.fail(insertID, "live active tab could not seed the time-routing range")
        return
    }
    active.selectedTrack = 0
    let page = app.automationPage()
    func inactiveIsUnchanged() -> Bool {
        app.songTabs.selectedId == activeID && app.selectedDocument === active
            && (try? inactive.document.state.file.encoded()) == inactiveBytes
    }

    page.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 48, endTick: 72), scope: .tracks([0])))
    active.editCursor = 0
    app.play()
    report.expect(
        app.playheadPresenter().playing, cppID: insertID,
        message: "live selected tab plays before scoped insertion")
    let insertRevision = active.document.revision
    app.performGridCommand(command: EditCommand.insertTime.rawValue)
    report.expect(
        active.document.revision == insertRevision + 1
            && active.document.note(seam.id)?.tick == 72, cppID: insertID,
        message: "live selected tab applies the scoped insertion to its own note")
    report.expect(
        inactiveIsUnchanged(), cppID: insertID,
        message: "playing insertion leaves the sibling document byte-exact")
    app.stop()
    _ = active.document.history.undoDocument()
    report.expect(
        (try? active.document.state.file.encoded()) == original, cppID: insertID,
        message: "live selected-tab insertion undo restores its active MIDI bytes")
    report.expect(
        inactiveIsUnchanged(), cppID: insertID,
        message: "stopped insertion undo leaves the sibling bytes untouched")

    page.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 24, endTick: 48), scope: .tracks([0])))
    let scopedRevision = active.document.revision
    app.performGridCommand(command: EditCommand.deleteTime.rawValue)
    report.expect(
        active.document.revision == scopedRevision + 1
            && active.document.note(insideID) == nil, cppID: deleteID,
        message: "live selected tab removes its scoped inside note")
    report.expect(
        inactiveIsUnchanged(), cppID: deleteID,
        message: "scoped deletion preserves the inactive document bytes")
    _ = active.document.history.undoDocument()
    report.expect(
        (try? active.document.state.file.encoded()) == original, cppID: deleteID,
        message: "live selected-tab scoped undo restores its active MIDI bytes")

    let allTracks = Set(0..<active.document.engineTracks.usedTrackCount)
    page.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 0, endTick: 48), scope: .tracks(allTracks)))
    let wholeRevision = active.document.revision
    app.performGridCommand(command: EditCommand.deleteTime.rawValue)
    report.expect(
        active.document.revision == wholeRevision + 1
            && active.document.note(insideID) == nil, cppID: deleteID,
        message: "live selected tab removes its whole-range inside note")
    report.expect(
        inactiveIsUnchanged(), cppID: deleteID,
        message: "whole-song deletion leaves the inactive song byte-exact")
    _ = active.document.history.undoDocument()
    report.expect(
        (try? active.document.state.file.encoded()) == original, cppID: deleteID,
        message: "live selected-tab whole undo restores its active MIDI bytes")
    report.expect(
        inactiveIsUnchanged(), cppID: deleteID,
        message: "whole-song deletion undo preserves the inactive song bytes")
}
