import Foundation
import PorydawApp
import PorydawCore

// Existing scenarios paired with voice.cpp.
// Entry order remains in VoiceChangesPageChecks.swift.

@MainActor
func drawerVoicePickerInsertion(_ report: CheckReport, suite: DocumentSession,
                             service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot
    report.expect(!baseline.canUndo, cppID: drawerVoiceInsertionID,
                  message: "the fixture starts with no undoable edit")

    report.expect(page.pointerDoubleClick(x: fixture.markerX(96), y: 10), cppID: drawerVoiceInsertionID,
                  message: "the double-click on the empty lane opens the picker")
    report.expect(page.hasPicker, cppID: drawerVoiceInsertionID,
                  message: "the double-click on the empty lane opens the picker")
    report.expectEqual(expected: "Insert voice change", actual: page.pickerTitle, cppID: drawerVoiceInsertionID,
                       what: "an empty-lane target opens the insertion title")
    report.expectEqual(expected: 96, actual: page.pickerTargetTick, cppID: drawerVoiceInsertionID,
                       what: "the captured tick is the press's snapped tick")
    report.expect(page.pickerTargetIdentity == nil, cppID: drawerVoiceInsertionID,
                  message: "an empty-lane target carries no occurrence")
    report.expectEqual(expected: programs[1], actual: page.pickerProgram, cppID: drawerVoiceInsertionID,
                       what: "the picker opens on the slot the context resolves to")
    report.expect(page.interactionActive, cppID: drawerVoiceInsertionID,
                  message: "an open picker reports an active interaction")
    report.expectEqual(expected: 3, actual: page.markerIdentities.count, cppID: drawerVoiceInsertionID,
                       what: "the open picker publishes no marker of its own")

    // Filter, then accept: one insertion, one revision, one history entry.
    let filter = String(format: "%03d", programs[2])
    page.setPickerFilter(text: filter)
    report.expect(page.pickerRowPrograms.contains(programs[2]), cppID: drawerVoiceInsertionID,
                  message: "the filter keeps the row it names")
    report.expect(!page.pickerRowValues.isEmpty, cppID: drawerVoiceInsertionID,
                  message: "the filter publishes the rows it matched")
    report.expect(page.pickerRowValues.allSatisfy {
        $0.label.range(of: filter, options: .caseInsensitive) != nil
    }, cppID: drawerVoiceInsertionID, message: "every visible row matches the filter")
    page.selectPickerRow(index: 0)
    report.expectEqual(expected: programs[2], actual: page.pickerProgram, cppID: drawerVoiceInsertionID,
                       what: "the row press selects the filtered program")
    report.expect(page.acceptPicker(), cppID: drawerVoiceInsertionID,
                  message: "accepting the picker writes the captured target")
    report.expectEqual(expected: 4, actual: fixture.lanePoints().count, cppID: drawerVoiceInsertionID,
                       what: "the insertion adds exactly one lane event")
    report.expectEqual(expected: programs[2], actual: 
                       VoiceLanePolicy.occurrence(at: 96, in: fixture.lanePoints())?.value,
                       cppID: drawerVoiceInsertionID, what: "the inserted event carries the chosen slot")
    report.expectEqual(expected: baseline.revision + 1, actual: fixture.snapshot.revision, cppID: drawerVoiceInsertionID,
                       what: "the insertion is one revision")
    report.expect(fixture.snapshot.canUndo, cppID: drawerVoiceInsertionID,
                  message: "the insertion records one history entry")
    report.expectEqual(expected: [0, 48, 96, 120], actual: page.markerTicks, cppID: drawerVoiceInsertionID,
                       what: "the projection rebuilds around the new occurrence")
    report.expect(!page.hasPicker, cppID: drawerVoiceInsertionID,
                  message: "acceptance closes the picker")
    report.expect(!page.interactionActive, cppID: drawerVoiceInsertionID,
                  message: "acceptance releases the follow-scroll gate")

    // Undo and redo follow the document.
    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(drawerVoiceInsertionID, "undo failed: \(error)")
        return
    }
    report.expect(VoiceLanePolicy.occurrence(at: 96, in: fixture.lanePoints()) == nil,
                  cppID: drawerVoiceInsertionID, message: "undo removes the inserted occurrence")
    report.expectEqual(expected: [0, 48, 120], actual: page.markerTicks, cppID: drawerVoiceInsertionID,
                       what: "undo rebuilds the projection without the insertion")
    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(drawerVoiceInsertionID, "redo failed: \(error)")
        return
    }
    report.expectEqual(expected: programs[2], actual: 
                       VoiceLanePolicy.occurrence(at: 96, in: fixture.lanePoints())?.value,
                       cppID: drawerVoiceInsertionID, what: "redo restores the inserted occurrence")
    report.expect(page.markerTicks.contains(96), cppID: drawerVoiceInsertionID,
                  message: "redo republishes the restored marker")

    // A same-value acceptance is a no-op.
    let settled = fixture.snapshot
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.setPickerFilter(text: filter)
    page.selectPickerRow(index: 0)
    report.expect(!page.acceptPicker(), cppID: drawerVoiceInsertionID,
                  message: "accepting the value the document already holds writes nothing")
    report.expectEqual(expected: settled, actual: fixture.snapshot, cppID: drawerVoiceInsertionID,
                       what: "the same-value acceptance leaves the document untouched")

    // A filter that matches nothing cannot be accepted.
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.setPickerFilter(text: "zzz-no-such-voice")
    report.expect(!page.pickerHasMatch, cppID: drawerVoiceInsertionID,
                  message: "an unmatched filter publishes no match")
    report.expectEqual(expected: 0, actual: page.pickerRowValues.count, cppID: drawerVoiceInsertionID,
                       what: "an unmatched filter publishes no row")
    report.expectEqual(expected: -1, actual: page.pickerIndex, cppID: drawerVoiceInsertionID,
                       what: "an unmatched filter publishes no current row")
    report.expect(!page.acceptPicker(), cppID: drawerVoiceInsertionID,
                  message: "an unmatched filter cannot be accepted")
    report.expectEqual(expected: settled, actual: fixture.snapshot, cppID: drawerVoiceInsertionID,
                       what: "the refused acceptance leaves the document untouched")
}

@MainActor
func drawerVoiceOriginalPickerRows(_ report: CheckReport, suite: DocumentSession,
                                          service: ProjectService) {
    // [drawerpresentation/fixtures.cpp:44-62,406] Preserve the original notes,
    // channels, end ticks and marker3 at48; project bank labels remain live.
    let document = SongDocument(file: MidiFile(division: 24, chunks: [
        MidiChunk(events: [.meta(type: 0x51, data: [0x07, 0xA1, 0x20])], endTick: 384),
        MidiChunk(events: [.channel(status: 0xC0, data0: 0),
                           .channel(status: 0x90, data0: 60, data1: 100),
                           .channel(tick: 48, status: 0x80, data0: 60),
                           .channel(tick: 48, status: 0xC0, data0: 3)], endTick: 384),
        MidiChunk(events: [.channel(status: 0xC1, data0: 5),
                           .channel(status: 0x91, data0: 48, data1: 100),
                           .channel(tick: 48, status: 0x81, data0: 48)], endTick: 384),
    ]), config: suite.document.state.config, source: suite.document.source,
       trackBudget: suite.document.trackBudget)
    let session = DocumentSession(document: document, service: service, lease: suite.bankLease,
                                  slots: suite.bankSlots, dirty: false,
                                  loadName: suite.bankLoadName, sampleRate: 48_000)
    session.selectedTrack = 0
    let page = VoiceChangesPage(baseFontPx: 13)
    page.attach(session: session, palette: GridPalette())
    page.configureBody(width: 400, height: 160, gutter: 56, devicePixelRatio: 1,
                       baseFontPx: 13, dragDistance: 10)
    session.onChange = { [weak page] change in
        if !change.domains.intersection([.document, .selection, .bank]).isEmpty {
            page?.refreshFromDocument()
        }
    }
    func open(_ tick: Tick) {
        _ = page.pointerDoubleClick(x: session.camera.displayX(tick: Double(tick), origin: 0, dpr: 1), y: 10)
    }
    func expect(_ condition: @autoclosure () -> Bool, _ line: Int) {
        report.expect(condition(), cppID: "drawerpresentation/DrawerPresentationTest::voicePickerTransactions",
                      message: "voice.cpp:\(line)")
    }
    func value(_ tick: Tick) -> Int? {
        document.lanePoints(track: 0, lane: .voice).first { $0.tick == tick }?.value
    }
    let baseline = drawerVoiceVoiceDocumentSnapshot(document)
    let baselineBytes = try! document.captureSave().bytes
    open(48)
    expect(page.pickerOpen, 309)
    expect(page.pickerIndex == 3, 311)
    page.setPickerFilter(text: "005")
    expect(page.pickerRowPrograms == [5] && page.pickerIndex == 0, 313)
    _ = page.acceptPicker()
    expect(!page.pickerOpen, 315)
    expect(value(48) != nil, 317)
    expect(value(48) == 5, 318)
    expect(document.revision == baseline.revision + 1, 319)
    // One undo must restore the full pre-edit document and history position;
    // this observes the original stack-index delta without private Qt indices.
    let writtenBytes = try! document.captureSave().bytes
    let writtenIdentity = document.history.currentIdentity
    _ = document.history.undoDocument()
    let oneUndoRestored = (try! document.captureSave().bytes) == baselineBytes
        && document.history.currentIdentity == baseline.identity
        && document.history.canUndo == baseline.canUndo
    _ = document.history.redoDocument()
    expect(oneUndoRestored && (try! document.captureSave().bytes) == writtenBytes
        && document.history.currentIdentity == writtenIdentity, 320)
    let changed = drawerVoiceVoiceDocumentSnapshot(document)
    open(48)
    expect(page.pickerOpen, 324)
    page.setPickerFilter(text: "005")
    expect(page.pickerRowPrograms == [5] && page.pickerIndex == 0, 326)
    _ = page.acceptPicker()
    expect(!page.pickerOpen, 328)
    expect(drawerVoiceVoiceDocumentSnapshot(document) == changed, 329)
    open(48)
    expect(page.pickerOpen, 332)
    page.setPickerFilter(text: "not-a-voice")
    expect(!page.pickerHasMatch && page.pickerRowPrograms.isEmpty && page.pickerIndex == -1, 334)
    page.setPickerFilter(text: "007")
    expect(page.pickerRowPrograms == [7] && page.pickerIndex == 0, 336)
    page.cancelPicker()
    expect(!page.pickerOpen, 338)
    expect(drawerVoiceVoiceDocumentSnapshot(document) == changed, 339)
    open(96)
    expect(page.pickerOpen, 407)
    expect(page.pickerIndex == 5, 408)
    page.setPickerFilter(text: "003")
    expect(page.pickerRowPrograms == [3] && page.pickerIndex == 0, 410)
    _ = page.acceptPicker()
    expect(!page.pickerOpen, 412)
    expect(value(96) != nil, 413)
    expect(value(96) == 3, 414)
    _ = document.history.undoDocument()
    expect(value(96) == nil, 416)
    _ = document.history.redoDocument()
    expect(value(96) != nil, 418)

    // Supplementary boundary regression: a last-row Down cannot select128.
    // The original ListView confines navigation to its128 program rows.
    open(48)
    page.selectPickerRow(index: 127)
    page.movePickerSelection(delta: 1)
    report.expect(page.pickerIndex == 127 && page.pickerProgram == 127,
                  cppID: "voice-picker/navigation-boundaries",
                  message: "Down at the final row preserves program127")
    page.movePickerSelection(delta: -1)
    report.expect(page.pickerIndex == 126 && page.pickerProgram == 126,
                  cppID: "voice-picker/navigation-boundaries",
                  message: "Up from the final row selects the preceding program")
    page.selectPickerRow(index: 0)
    page.movePickerSelection(delta: -1)
    report.expect(page.pickerIndex == 0 && page.pickerProgram == 0,
                  cppID: "voice-picker/navigation-boundaries",
                  message: "Up at the first row preserves program0")
    page.movePickerSelection(delta: 1)
    report.expect(page.pickerIndex == 1 && page.pickerProgram == 1,
                  cppID: "voice-picker/navigation-boundaries",
                  message: "Down from the first row selects the following program")
    page.cancelPicker()
}

@MainActor
func drawerVoicePickerValueReplacement(_ report: CheckReport, suite: DocumentSession,
                                    service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot
    let target = VoiceOccurrence(fixture.lanePoints()[1])
    let markerX = fixture.markerX(48)

    _ = page.pointerDoubleClick(x: markerX, y: 10)
    report.expectEqual(expected: "Change voice", actual: page.pickerTitle, cppID: drawerVoiceReplacementID,
                       what: "a marker target opens the change title")
    report.expectEqual(expected: target.text, actual: page.pickerTargetIdentity, cppID: drawerVoiceReplacementID,
                       what: "the captured identity is the pressed occurrence")
    report.expectEqual(expected: 48, actual: page.pickerTargetTick, cppID: drawerVoiceReplacementID,
                       what: "the captured tick is the marker's own tick")
    report.expectEqual(expected: target.value, actual: page.pickerProgram, cppID: drawerVoiceReplacementID,
                       what: "the picker opens on the marker's current program")

    page.setPickerFilter(text: String(format: "%03d", programs[2]))
    page.selectPickerRow(index: 0)
    report.expect(page.acceptPicker(), cppID: drawerVoiceReplacementID,
                  message: "accepting the picker replaces the captured occurrence's value")
    report.expectEqual(expected: programs[2], actual: 
                       VoiceLanePolicy.occurrence(at: 48, in: fixture.lanePoints())?.value,
                       cppID: drawerVoiceReplacementID, what: "the change at tick 48 carries the new slot")
    report.expectEqual(expected: 3, actual: fixture.lanePoints().count, cppID: drawerVoiceReplacementID,
                       what: "a value replacement adds no event")
    report.expectEqual(expected: baseline.revision + 1, actual: fixture.snapshot.revision, cppID: drawerVoiceReplacementID,
                       what: "the replacement is one revision")
    report.expect(fixture.snapshot.canUndo && !baseline.canUndo, cppID: drawerVoiceReplacementID,
                  message: "the replacement records one history entry")
    report.expect(page.publishedMarkers.contains {
        Tick($0.tick) == 48 && $0.label.hasPrefix(String(format: "%03d", programs[2]))
    }, cppID: drawerVoiceReplacementID,
       message: "the projection's marker label follows the replaced slot")

    // Escape and a pointer dismissal both write nothing.
    let settled = fixture.snapshot
    _ = page.pointerDoubleClick(x: markerX, y: 10)
    report.expect(page.hasPicker, cppID: drawerVoiceReplacementID, message: "the picker reopens")
    report.expect(page.handleEscape(), cppID: drawerVoiceReplacementID,
                  message: "Escape claims the key while the picker is open")
    report.expect(!page.hasPicker, cppID: drawerVoiceReplacementID, message: "Escape closes the picker")
    report.expectEqual(expected: settled, actual: fixture.snapshot, cppID: drawerVoiceReplacementID,
                       what: "Escape writes nothing")
    report.expect(!page.handleEscape(), cppID: drawerVoiceReplacementID,
                  message: "Escape is unhandled once nothing is open")

    _ = page.pointerDoubleClick(x: markerX, y: 10)
    _ = page.pointerPress(x: fixture.markerX(200), y: 10, surface: 1, button: 1, modifiers: 0)
    report.expect(!page.hasPicker, cppID: drawerVoiceReplacementID,
                  message: "an outside press dismisses the picker")
    report.expect(!page.hasGesture, cppID: drawerVoiceReplacementID,
                  message: "the dismissing press starts no gesture")
    _ = page.pointerRelease(x: fixture.markerX(200), y: 10, button: 1)
    report.expectEqual(expected: settled, actual: fixture.snapshot, cppID: drawerVoiceReplacementID,
                       what: "the dismissed press and its release write nothing")

    // A stale capture — the document moved under the open picker — writes
    // nothing and never retargets another occurrence.
    _ = page.pointerDoubleClick(x: markerX, y: 10)
    let staleTarget = page.pickerTargetIdentity
    let heldAtCapture = VoiceLanePolicy.occurrence(
        at: 48, in: fixture.document.lanePoints(track: 0, lane: .voice)).map { $0.text }
    report.expectEqual(expected: heldAtCapture, actual: staleTarget, cppID: drawerVoiceReplacementID,
                       what: "the capture names the occurrence the document held then")
    fixture.document.writeLane(track: 0, lane: .voice, from: 0, through: 0,
                               points: [LaneWrite(tick: 0, value: programs[2])])
    report.expect(!page.hasPicker, cppID: drawerVoiceReplacementID,
                  message: "a document change cancels the open picker")
    let rewrote = fixture.snapshot
    report.expect(!page.acceptPicker(), cppID: drawerVoiceReplacementID,
                  message: "an acceptance after the cancellation writes nothing")
    report.expectEqual(expected: rewrote, actual: fixture.snapshot, cppID: drawerVoiceReplacementID,
                       what: "the stale acceptance leaves the rewrite as the only change")
    report.expect(page.pickerTargetIdentity == nil, cppID: drawerVoiceReplacementID,
                  message: "the cancelled capture is gone instead of retargeted")
    report.expectEqual(expected: programs[2], actual: 
                       VoiceLanePolicy.occurrence(at: 0, in: fixture.lanePoints())?.value,
                       cppID: drawerVoiceReplacementID, what: "the rewrite itself stands")
}

@MainActor
func drawerVoicePickerKeyboardPolicy(_ report: CheckReport, suite: DocumentSession,
                                  service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    guard page.hasPicker else {
        report.fail(drawerVoiceKeyboardID, "the picker did not open")
        return
    }
    report.expectEqual(expected: suite.bankSlots.count, actual: page.pickerRowValues.count, cppID: drawerVoiceKeyboardID,
                       what: "an empty filter publishes every bank row")
    report.expectEqual(expected: programs[1], actual: page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "the picker opens on the context slot the target captured")
    report.expectEqual(expected: programs[1], actual: page.pickerIndex, cppID: drawerVoiceKeyboardID,
                       what: "the published row index follows the current program")
    let first = page.pickerProgram
    page.movePickerSelection(delta: 1)
    report.expectEqual(expected: first + 1, actual: page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "the down arrow moves to the next visible program")
    page.movePickerSelection(delta: -1)
    report.expectEqual(expected: first, actual: page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "the up arrow returns to the previous program")
    page.movePickerSelection(delta: -5)
    report.expectEqual(expected: page.pickerRowPrograms.first ?? -1, actual: page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "the navigation clamps at the first row")
    page.movePickerSelection(delta: 500)
    report.expectEqual(expected: page.pickerRowPrograms.last ?? -1, actual: page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "the navigation clamps at the last row")
    report.expectEqual(expected: page.pickerRowPrograms.count - 1, actual: page.pickerIndex, cppID: drawerVoiceKeyboardID,
                       what: "the row index follows the clamped program")
    page.selectPickerRow(index: 1)
    report.expectEqual(expected: page.pickerRowPrograms[1], actual: page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "a row press selects exactly that row's program")
    report.expect(page.pickerRowValues[1].selected, cppID: drawerVoiceKeyboardID,
                  message: "the selected row publishes its own state")
    report.expectEqual(expected: 1, actual: page.pickerRowValues.filter(\.selected).count, cppID: drawerVoiceKeyboardID,
                       what: "exactly one row is selected")

    // Filtering by name text follows the labels the bank publishes.
    let name = suite.bankSlots[programs[0]].voice?.symbol ?? ""
    if !name.isEmpty {
        page.setPickerFilter(text: name)
        report.expect(page.pickerRowPrograms.contains(programs[0]), cppID: drawerVoiceKeyboardID,
                      message: "a name filter keeps the slot that carries it")
        report.expect(page.pickerRowValues.allSatisfy {
            $0.label.lowercased().contains(name.lowercased())
        }, cppID: drawerVoiceKeyboardID, message: "every row matched by name really carries the name")
    }
    page.cancelPicker()
    report.expect(!page.hasPicker, cppID: drawerVoiceKeyboardID, message: "the picker closes")
}

@MainActor
func drawerVoiceBlankSlotCommit(_ report: CheckReport, suite: DocumentSession,
                             service: ProjectService, programs: [Int]) {
    guard let blankIndex = suite.bankSlots.indices.first(where: {
        suite.bankSlots[$0].voice == nil
    }) else {
        report.expect(true, cppID: drawerVoiceCollisionID,
                      message: "the staged bank publishes no blank slot to commit")
        return
    }
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    guard page.hasPicker else {
        report.fail(drawerVoiceCollisionID, "the picker did not open for the blank-slot commit")
        return
    }
    page.setPickerFilter(text: String(format: "%03d", blankIndex))
    guard let row = page.pickerRowPrograms.firstIndex(of: blankIndex) else {
        report.fail(drawerVoiceCollisionID,
                    "the blank slot \(blankIndex) publishes no row for its own number")
        page.cancelPicker()
        return
    }
    page.selectPickerRow(index: row)
    report.expect(page.acceptPicker(), cppID: drawerVoiceCollisionID,
                  message: "the picker commits the slot the bank holds no parsed voice for")
    report.expectEqual(expected: blankIndex, actual: 
                       VoiceLanePolicy.occurrence(at: 96, in: fixture.lanePoints())?.value,
                       cppID: drawerVoiceCollisionID, what: "the lane holds the blank slot's number")

    guard let marker = fixture.marker(at: 96) else {
        report.fail(drawerVoiceCollisionID, "the blank-slot change publishes no marker")
        return
    }
    report.expect(marker.slotBlank, cppID: drawerVoiceCollisionID,
                  message: "the committed blank slot publishes blank truth")
    report.expectEqual(expected: "", actual: marker.symbol, cppID: drawerVoiceCollisionID,
                       what: "the committed blank slot publishes no symbol")
    report.expectEqual(expected: String(format: "%03d", blankIndex), actual: marker.label, cppID: drawerVoiceCollisionID,
                       what: "the committed blank slot's label stays its program number")

    fixture.session.editCursor = 96
    report.expect(fixture.page.contextBlank, cppID: drawerVoiceCollisionID,
                  message: "the readout publishes the blank truth for that context")
    report.expectEqual(expected: String(format: "%03d", blankIndex), actual: fixture.page.readoutText,
                       cppID: drawerVoiceCollisionID,
                       what: "the readout of a blank context is the program number alone")
}
