import PorydawApp
import PorydawAppCommands
import PorydawCore
import PorydawDocument

@MainActor
func windowTierKeyboardOutcomes(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "selectionkey/SelectionWindowTierTest::parameterLabelActivationAndSharedCommands"
    let savedClipboard = drawerAutomationPorydawSelectionClipboardState()
    defer { savedClipboard.restore() }
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, volume: [(5760, 48)], pan: [(5760, 32)],
        modulation: [(5760, 96)], tailTick: 9000)
    let document = fixture.document
    let session = fixture.session
    let page = fixture.page
    let selectedLanes: Set<AutomationParameter> = [fixture.panLane, fixture.modulationLane]
    guard
        let pair = try? document.addNotes([
            NewNote(track: 0, tick: 2400, pitch: 60, duration: 48, velocity: 100),
            NewNote(track: 0, tick: 2496, pitch: 64, duration: 48, velocity: 96),
        ]), pair.count == 2,
        let first = document.note(pair[0]), let second = document.note(pair[1])
    else {
        report.fail(id, "the reserved tick-2400 pair could not be staged")
        return
    }
    let grid = PianoGrid(viewport: fixture.viewport)
    let ruler = RulerMenuPresenter(viewport: fixture.viewport, grid: grid, automation: page)
    let router = EditorCommandRouter(session: session, grid: grid, automation: page, rulerMenu: ruler)
    let selection = AutomationTimeSelection(
        range: TimeRange(startTick: 5760, endTick: 5784), scope: .lanes,
        lanes: selectedLanes, tempo: false)
    session.setSelectedNotes(pair)
    page.applyTimeSelection(selection)
    let undoBefore = try? coreEditHistoryCountAtTip(document, report: report, cppID: id)
    fixture.activate(fixture.modulationLane)
    report.expectEqual(
        expected: Tick(5760), actual: session.timeSelection?.range.startTick,
        cppID: id, what: "A030 label activation keeps the selection start")
    report.expectEqual(
        expected: Tick(5784), actual: session.timeSelection?.range.endTick,
        cppID: id, what: "A030 label activation keeps the selection end")
    report.expect(
        session.timeSelection?.scope == .lanes, cppID: id,
        message: "A030 label activation keeps the lanes scope")
    report.expectEqual(
        expected: selectedLanes, actual: session.timeSelection?.lanes,
        cppID: id, what: "A030 label activation keeps both selected CC lanes")
    report.expect(
        session.timeSelection?.tempo == false, cppID: id,
        message: "A030 label activation keeps Tempo out of the scope")
    report.expect(
        session.selectedNotes.isEmpty, cppID: id,
        message: "A030 label activation keeps the note selection empty")
    fixture.activate(fixture.volumeLane)
    report.expectEqual(
        expected: Tick(5760), actual: session.timeSelection?.range.startTick,
        cppID: id, what: "A038 Return activation keeps the selection start")
    report.expectEqual(
        expected: Tick(5784), actual: session.timeSelection?.range.endTick,
        cppID: id, what: "A038 Return activation keeps the selection end")
    report.expect(
        session.timeSelection?.scope == .lanes, cppID: id,
        message: "A038 Return activation keeps the lanes scope")
    report.expectEqual(
        expected: selectedLanes, actual: session.timeSelection?.lanes,
        cppID: id, what: "A038 Return activation keeps both selected CC lanes")
    report.expect(
        session.timeSelection?.tempo == false, cppID: id,
        message: "A038 Return activation keeps Tempo out of the scope")
    report.expect(
        session.selectedNotes.isEmpty, cppID: id,
        message: "A038 Return activation keeps the note selection empty")
    report.expectEqual(
        expected: undoBefore,
        actual: try? coreEditHistoryCountAtTip(document, report: report, cppID: id),
        cppID: id, what: "A035 label activation keeps the exact undo index")
    let beforeUp = document.state
    router.perform(.transposeUp)
    report.expectEqual(
        expected: beforeUp, actual: document.state, cppID: id,
        what: "A041 Up with a lane range leaves song contents unchanged")
    report.expectEqual(
        expected: Tick(5760), actual: session.timeSelection?.range.startTick,
        cppID: id, what: "A041 Up keeps the selection start")
    report.expectEqual(
        expected: Tick(5784), actual: session.timeSelection?.range.endTick,
        cppID: id, what: "A041 Up keeps the selection end")
    report.expect(
        session.timeSelection?.scope == .lanes, cppID: id,
        message: "A041 Up keeps the lanes scope")
    report.expectEqual(
        expected: selectedLanes, actual: session.timeSelection?.lanes,
        cppID: id, what: "A041 Up keeps both selected CC lanes")
    report.expect(
        session.timeSelection?.tempo == false, cppID: id,
        message: "A041 Up keeps Tempo out of the scope")
    report.expect(
        session.selectedNotes.isEmpty, cppID: id,
        message: "A041 Up keeps the note selection empty")
    let beforePrompt = document.state
    report.expect(
        page.openPrompt(tick: 5808, value: 48), cppID: id,
        message: "the active Volume parameter opens its value prompt")
    report.expectEqual(
        expected: beforePrompt, actual: document.state, cppID: id,
        what: "A052 prompt draft leaves song contents unchanged")
    report.expectEqual(
        expected: Tick(5760), actual: session.timeSelection?.range.startTick,
        cppID: id, what: "A053 prompt draft keeps the selection start")
    report.expectEqual(
        expected: Tick(5784), actual: session.timeSelection?.range.endTick,
        cppID: id, what: "A053 prompt draft keeps the selection end")
    report.expect(
        session.timeSelection?.scope == .lanes, cppID: id,
        message: "A053 prompt draft keeps the lanes scope")
    report.expectEqual(
        expected: selectedLanes, actual: session.timeSelection?.lanes,
        cppID: id, what: "A053 prompt draft keeps both selected CC lanes")
    report.expect(
        session.timeSelection?.tempo == false, cppID: id,
        message: "A053 prompt draft keeps Tempo excluded")
    report.expect(
        session.selectedNotes.isEmpty, cppID: id,
        message: "A053 prompt draft keeps the note selection empty")
    page.cancelPrompt()
    report.expectEqual(
        expected: undoBefore,
        actual: try? coreEditHistoryCountAtTip(document, report: report, cppID: id),
        cppID: id, what: "A035 prompt Escape keeps the exact undo index")
    report.expectEqual(
        expected: Tick(5760), actual: session.timeSelection?.range.startTick,
        cppID: id, what: "A056 prompt Escape keeps the selection start")
    report.expectEqual(
        expected: Tick(5784), actual: session.timeSelection?.range.endTick,
        cppID: id, what: "A056 prompt Escape keeps the selection end")
    report.expect(
        session.timeSelection?.scope == .lanes, cppID: id,
        message: "A056 prompt Escape keeps the lanes scope")
    report.expectEqual(
        expected: selectedLanes, actual: session.timeSelection?.lanes,
        cppID: id, what: "A056 prompt Escape keeps both selected CC lanes")
    report.expect(
        session.timeSelection?.tempo == false, cppID: id,
        message: "A056 prompt Escape keeps Tempo excluded")
    report.expect(
        session.selectedNotes.isEmpty, cppID: id,
        message: "A056 prompt Escape keeps the note selection empty")
    let tapIndex = document.history.undoIndex
    let tapCount = document.history.undoCount
    page.tapTempoTap(atMilliseconds: 1_000)
    page.tapTempoTap(atMilliseconds: 1_500)
    report.expect(
        page.tapTempoTapCount == 2 && page.tapTempoDraftBpm > 0,
        cppID: id, message: "two tempo taps publish a draft without committing it")
    report.expect(
        document.history.undoIndex == tapIndex, cppID: id,
        message: "two direct tempo taps preserve the exact undo index")
    report.expect(
        document.history.undoCount == tapCount, cppID: id,
        message: "two direct tempo taps preserve the exact undo count")
    page.resetTapTempo()
    router.perform(.copy)
    let clip = GridClipboard().read()?.clip
    report.expectEqual(
        expected: [ClipLanePoint(relTick: 0, value: 32)],
        actual: clip?.lanes.first(where: { $0.cc == TimeDefaults.ccPan })?.points,
        cppID: id, what: "A061 window Copy captures the Pan value at the selected tick")
    report.expectEqual(
        expected: [ClipLanePoint(relTick: 0, value: 96)],
        actual: clip?.lanes.first(where: { $0.cc == TimeDefaults.ccModulation })?.points,
        cppID: id, what: "A061 window Copy captures the Modulation value at the selected tick")
    report.expectEqual(
        expected: beforePrompt, actual: document.state, cppID: id,
        what: "A061 window Copy leaves the song unchanged")
    report.expectEqual(
        expected: Tick(5760), actual: session.timeSelection?.range.startTick,
        cppID: id, what: "A061 window Copy keeps the selection start")
    report.expectEqual(
        expected: Tick(5784), actual: session.timeSelection?.range.endTick,
        cppID: id, what: "A061 window Copy keeps the selection end")
    report.expect(
        session.timeSelection?.scope == .lanes, cppID: id,
        message: "A061 window Copy keeps the lanes scope")
    report.expectEqual(
        expected: selectedLanes, actual: session.timeSelection?.lanes,
        cppID: id, what: "A061 window Copy keeps both selected CC lanes")
    report.expect(
        session.timeSelection?.tempo == false, cppID: id,
        message: "A061 window Copy keeps Tempo excluded")
    report.expect(
        session.selectedNotes.isEmpty, cppID: id,
        message: "A061 window Copy keeps the note selection empty")
    router.perform(.delete)
    report.expect(
        fixture.lanePoints(fixture.panLane).allSatisfy { $0.tick != 5760 },
        cppID: id, message: "A062 Delete removes the selected Pan point")
    report.expect(
        fixture.lanePoints(fixture.modulationLane).allSatisfy { $0.tick != 5760 },
        cppID: id, message: "A063 Delete removes the selected Modulation point")
    report.expectEqual(
        expected: ["5760:48"], actual: fixture.values(fixture.volumeLane),
        cppID: id, what: "A064 Delete retains the unselected Volume point")
    report.expectEqual(
        expected: first, actual: document.note(pair[0]), cppID: id,
        what: "A065 Delete retains the first reserved note by identity")
    report.expectEqual(
        expected: second, actual: document.note(pair[1]), cppID: id,
        what: "A065 Delete retains the second reserved note by identity")
    router.perform(.selectAll)
    report.expect(
        session.selectedNotes.contains(pair[0]), cppID: id,
        message: "A067 Select All includes the first reserved note by ID")
    report.expect(
        session.selectedNotes.contains(pair[1]), cppID: id,
        message: "A068 Select All includes the second reserved note by ID")
    session.setSelectedNotes([])
    session.editCursor = 7680
    router.perform(.paste)
    let pastedPan = fixture.lanePoints(fixture.panLane).first { $0.tick == 7680 }
    let pastedModulation = fixture.lanePoints(fixture.modulationLane).first { $0.tick == 7680 }
    report.expectEqual(
        expected: 32, actual: pastedPan?.value, cppID: id,
        what: "A071 Paste lands Pan value 32 at the committed cursor")
    report.expectEqual(
        expected: 96, actual: pastedModulation?.value, cppID: id,
        what: "A073 Paste lands Modulation value 96 at the committed cursor")
    report.expect(
        fixture.lanePoints(fixture.volumeLane).allSatisfy { $0.tick != 7680 },
        cppID: id, message: "A074 Paste keeps the unselected Volume lane empty at the cursor")
    report.expectEqual(
        expected: first, actual: document.note(pair[0]), cppID: id,
        what: "A075 Paste retains the first reserved note unchanged")
    report.expectEqual(
        expected: second, actual: document.note(pair[1]), cppID: id,
        what: "A075 Paste retains the second reserved note unchanged")
    report.expectEqual(
        expected: fixture.volumeLane, actual: page.activeParameter, cppID: id,
        what: "A076 Paste keeps Volume as the active parameter")
    session.setSelectedNotes(pair)
    let step = Tick(grid.snapTicks)
    router.perform(.nudgeRight)
    router.perform(.transposeUp)
    report.expect(
        document.note(pair[0])?.tick == first.tick + step, cppID: id,
        message: "A078 routed Right advances the first reserved note one snap by ID")
    report.expect(
        document.note(pair[1])?.tick == second.tick + step, cppID: id,
        message: "A078 routed Right advances the second reserved note one snap by ID")
    report.expect(
        document.note(pair[0])?.pitch == first.pitch + 1, cppID: id,
        message: "A078 routed Up raises the first reserved note one semitone by ID")
    report.expect(
        document.note(pair[1])?.pitch == second.pitch + 1, cppID: id,
        message: "A078 routed Up raises the second reserved note one semitone by ID")
    report.expectEqual(
        expected: Set(pair), actual: session.selectedNotes, cppID: id,
        what: "A078 routed arrows preserve the pair selection")
}

@MainActor
func coreEditingKeyboardOutcomes(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let rangeID = "selectionkey/SelectionKeyCoreTest::automationRangeAndReboundDelete"
    let moveID = "selectionkey/SelectionKeyCoreTest::laneScopedHorizontalArrowNudgesPointsAndInterval"
    let pasteID = "selectionkey/SelectionKeyCoreTest::keyboardClipboardParity"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, pan: [(48, 80), (72, 64), (96, 40), (144, 80)])
    let document = fixture.document
    let session = fixture.session
    let page = fixture.page
    let grid = PianoGrid(viewport: fixture.viewport)
    let ruler = RulerMenuPresenter(viewport: fixture.viewport, grid: grid, automation: page)
    let router = EditorCommandRouter(session: session, grid: grid, automation: page, rulerMenu: ruler)
    let existing = document.notes(in: 0).map(\.id)
    guard !existing.isEmpty else {
        report.fail(rangeID, "the lane-range fixture has no competing note selection")
        return
    }
    session.setSelectedNotes(existing)
    page.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 48, endTick: 144), scope: .lanes,
            lanes: [fixture.panLane]))
    report.expectEqual(
        expected: Tick(48), actual: session.timeSelection?.range.startTick,
        cppID: rangeID, what: "A013 the committed lane range starts at tick 48")
    report.expectEqual(
        expected: Tick(144), actual: session.timeSelection?.range.endTick,
        cppID: rangeID, what: "A013 the committed lane range ends at tick 144")
    report.expect(
        session.timeSelection?.scope == .lanes, cppID: rangeID,
        message: "A013 the committed selection has lanes scope")
    report.expectEqual(
        expected: Set([fixture.panLane]), actual: session.timeSelection?.lanes,
        cppID: rangeID, what: "A013 the committed scope contains only Pan")
    report.expect(
        session.selectedNotes.isEmpty, cppID: rangeID,
        message: "A013 committing the lane range replaces selected notes")
    page.applyTimeSelection(
        AutomationTimeSelection(
            range: TimeRange(startTick: 96, endTick: 144), scope: .lanes,
            lanes: [fixture.panLane]))
    let destination = Tick(96 + grid.snapTicks)
    router.perform(.nudgeRight)
    report.expect(
        fixture.lanePoints(fixture.panLane).contains { $0.tick == destination && $0.value == 40 },
        cppID: moveID, message: "A033 Right moves the covered Pan point to the snapped destination")
    report.expect(
        fixture.lanePoints(fixture.panLane).allSatisfy { $0.tick != 96 },
        cppID: moveID, message: "A033 Right removes the point from its original tick")
    report.expectEqual(
        expected: destination, actual: session.timeSelection?.range.startTick,
        cppID: moveID, what: "A033 Right translates the interval start by the same delta")
    report.expectEqual(
        expected: Tick(144) + destination - Tick(96),
        actual: session.timeSelection?.range.endTick, cppID: moveID,
        what: "A033 Right translates the interval end by the same delta")

    let savedClipboard = drawerAutomationPorydawSelectionClipboardState()
    defer { savedClipboard.restore() }
    page.clearTimeSelection()
    guard let source = document.notes(in: 0).first(where: { $0.tick == 0 }) else {
        report.fail(pasteID, "the roll-copy source note at tick zero is unavailable")
        return
    }
    session.setSelectedNotes([source.id])
    router.perform(.copy)
    session.setSelectedNotes([])
    session.editCursor = 7680
    router.perform(.paste)
    report.expect(
        document.notes(in: 0).contains { $0.tick == 7680 && $0.pitch == 60 },
        cppID: pasteID,
        message: "A041 keyboard Paste lands the roll-copied pitch-60 note at the committed cursor")
}
