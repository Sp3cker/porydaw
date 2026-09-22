import Foundation
import PorydawApp
import PorydawCore

// Existing scenarios paired with voice.cpp.
// Entry order remains in VoiceChangesPageChecks.swift.

@MainActor
func drawerVoiceMarkerProjection(_ report: CheckReport, suite: DocumentSession,
                              service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: drawerVoiceProjectionID,
                       what: "every DOC_CC_VOICE event of the primary track publishes a marker")
    report.expectEqual(3, page.publishedMarkers.count, cppID: drawerVoiceProjectionID,
                       what: "the projection keeps one marker per change")
    report.expect(page.publishedMarkers.allSatisfy { !$0.identity.isEmpty }, cppID: drawerVoiceProjectionID,
                  message: "every marker carries its occurrence identity")
    report.expectEqual(3, Set(page.markerIdentities).count, cppID: drawerVoiceProjectionID,
                       what: "the identities are distinct per occurrence")

    let ticks: [Tick] = [0, 48, 120]
    for (index, tick) in ticks.enumerated() {
        let marker = page.publishedMarkers[index]
        let expectedProgram = programs[index]
        report.expectEqual(fixture.markerX(tick), marker.x, cppID: drawerVoiceProjectionID,
                           what: "marker \(tick) draws at the shared camera's projection")
        report.expect(marker.label.hasPrefix(String(format: "%03d", expectedProgram)),
                      cppID: drawerVoiceProjectionID,
                      message: "marker \(tick) labels its own program slot "
                          + "(\"\(marker.label)\")")
        report.expect(marker.lineBottom > marker.lineTop, cppID: drawerVoiceProjectionID,
                      message: "marker \(tick) draws a vertical rule")
        report.expect(marker.lineWidth > 0, cppID: drawerVoiceProjectionID,
                      message: "marker \(tick) draws a rule of a real width")
        report.expect((marker.labelRect["width"] as? Double ?? 0) > 0, cppID: drawerVoiceProjectionID,
                      message: "marker \(tick) publishes a label box with a real width")
        report.expect(!marker.offscreen, cppID: drawerVoiceProjectionID,
                      message: "marker \(tick) is inside the visible plot")
    }
    // The span walk closes each section at the next change and runs the last one
    // to the timeline's end, so the tail exists only when the song extends past
    // the final change.
    let tail = fixture.session.timeline.lengthTicks > 120 ? 1 : 0
    report.expectEqual(2 + tail, page.heldSpans.count, cppID: drawerVoiceProjectionID,
                       what: "each program section publishes one held span "
                           + "(timeline ends at \(fixture.session.timeline.lengthTicks))")
    report.expect(page.trackAvailable, cppID: drawerVoiceProjectionID,
                  message: "a resolved track publishes the band's tracking facts")
    report.expect(!page.readoutText.isEmpty, cppID: drawerVoiceProjectionID,
                  message: "the context readout names the program at the context tick")
    report.expect(page.readoutVisible, cppID: drawerVoiceProjectionID,
                  message: "the readout is published for a presented track")

    // The hit radius is the legacy font-relative one: a press inside it takes
    // that marker, a press beyond it takes none.
    let hitX = fixture.markerX(48)
    _ = page.pointerPress(x: hitX + 9, y: 10, surface: 1, button: 1, modifiers: 0)
    report.expectEqual(48, page.frozenOccurrence?.tick, cppID: drawerVoiceProjectionID,
                       what: "a press inside the marker hit radius takes that marker")
    page.cancelSectionInteraction()
    _ = page.pointerPress(x: hitX + 12, y: 10, surface: 1, button: 1, modifiers: 0)
    report.expect(!page.hasGesture, cppID: drawerVoiceProjectionID,
                  message: "a press beyond the marker hit radius starts no marker gesture")
    _ = page.pointerRelease(x: hitX + 12, y: 10, button: 1)

    // A hover over the empty lane publishes the snapped tick's slot label and
    // leaves the marker texts alone.
    let before = page.publishedMarkers.map(\.label)
    _ = page.pointerMove(x: fixture.markerX(96), y: 10, buttons: 0)
    report.expect(page.hoverVisible, cppID: drawerVoiceProjectionID,
                  message: "a background hover publishes its slot label")
    report.expect(page.hoverText.hasPrefix("→ "), cppID: drawerVoiceProjectionID,
                  message: "the hover label keeps the legacy arrow prefix")
    report.expectEqual(before, page.publishedMarkers.map(\.label), cppID: drawerVoiceProjectionID,
                       what: "a hover repaints no marker label")

    // A hover directly over a marker publishes its tick and no label.
    _ = page.pointerMove(x: fixture.markerX(48), y: 10, buttons: 0)
    report.expect(!page.hoverVisible, cppID: drawerVoiceProjectionID,
                  message: "a marker hover publishes no background label")
    report.expectEqual(48, Tick(page.hoverTick), cppID: drawerVoiceProjectionID,
                       what: "the marker hover publishes its own tick")
    report.expectEqual(21, page.hoverHintProfile, cppID: drawerVoiceProjectionID,
                       what: "a marker hover advertises fine marker movement")
    _ = page.pointerMove(x: fixture.markerX(96), y: 10, buttons: 0)
    report.expectEqual(12, page.hoverHintProfile, cppID: drawerVoiceProjectionID,
                       what: "leaving the marker restores horizontal-scroll instructions")
    page.pointerLeave()
    report.expect(!page.hoverVisible, cppID: drawerVoiceProjectionID,
                  message: "leaving the plot clears the hover")

    // Losing the track publishes the band's unavailable state.
    fixture.session.selectedTrack = nil
    page.refreshFromDocument()
    report.expect(!page.trackAvailable, cppID: drawerVoiceProjectionID,
                  message: "no selected track publishes the unavailable state")
    report.expectEqual(0, page.markerIdentities.count, cppID: drawerVoiceProjectionID,
                       what: "no selected track publishes no marker")
    report.expectEqual("No track selected", page.plotMessage, cppID: drawerVoiceProjectionID,
                       what: "the plot names the missing track")
}

@MainActor
func drawerVoiceSlotLabels(_ report: CheckReport, session: DocumentSession,
                        service: ProjectService, programs: [Int]) {
    let slot = programs[0]
    let view = session.bankSlots[slot]
    let label = VoiceLanePolicy.label(slot: slot, view: view)
    report.expect(label.hasPrefix(String(format: "%03d ", slot)), cppID: drawerVoiceLabelID,
                  message: "a slot label starts with its zero-padded program number "
                      + "(\"\(label)\")")
    let type = voiceTypeName(macro: view.voice?.macro)
    if let symbol = view.voice?.symbol, !symbol.isEmpty {
        report.expect(label.contains(symbol), cppID: drawerVoiceLabelID,
                      message: "a named slot label carries its source symbol")
        report.expect(label.contains("(\(type))"), cppID: drawerVoiceLabelID,
                      message: "a named slot label carries its declared type in parentheses")
    } else {
        report.expect(label.contains(type), cppID: drawerVoiceLabelID,
                      message: "a slot with no source symbol names its declared type "
                          + "(\"\(label)\")")
    }
    report.expectEqual("→ \(label)", VoiceLanePolicy.hoverLabel(label), cppID: drawerVoiceLabelID,
                       what: "the hover spelling is the label with the legacy arrow")
    report.expectEqual("", VoiceLanePolicy.hoverLabel(""), cppID: drawerVoiceLabelID,
                       what: "an unresolvable slot publishes no hover label at all")

    report.expectEqual("Sample", voiceTypeName(macro: BankVoiceMacro.directSound),
                       cppID: drawerVoiceLabelID, what: "Direct Sound is the Sample type")
    report.expectEqual("Sample (fixed pitch)",
                       voiceTypeName(macro: BankVoiceMacro.directSoundNoResample),
                       cppID: drawerVoiceLabelID, what: "the no-resample form names its fixed pitch")
    report.expectEqual("Sample (reverse)", voiceTypeName(macro: BankVoiceMacro.directSoundAlt),
                       cppID: drawerVoiceLabelID, what: "the alternate form names its reverse playback")
    report.expectEqual("Square 1", voiceTypeName(macro: BankVoiceMacro.square1), cppID: drawerVoiceLabelID,
                       what: "the square-1 macro names Square 1")
    report.expectEqual("Square 2", voiceTypeName(macro: BankVoiceMacro.square2), cppID: drawerVoiceLabelID,
                       what: "the square-2 macro names Square 2")
    report.expectEqual("Wave", voiceTypeName(macro: BankVoiceMacro.programmableWave),
                       cppID: drawerVoiceLabelID, what: "the wave macro names Wave")
    report.expectEqual("Noise", voiceTypeName(macro: BankVoiceMacro.noise), cppID: drawerVoiceLabelID,
                       what: "the noise macro names Noise")
    report.expectEqual("Drumkit", voiceTypeName(macro: BankVoiceMacro.keysplitAll),
                       cppID: drawerVoiceLabelID, what: "the drumkit macro names Drumkit")
    report.expectEqual("", voiceTypeName(macro: nil), cppID: drawerVoiceLabelID,
                       what: "no macro names no type")

    // A blank slot keeps its program number and gains no invented name.
    let blank = BankSlotView(kind: BankSlotKind.none, voice: nil)
    report.expectEqual(String(format: "%03d", 7), VoiceLanePolicy.label(slot: 7, view: blank),
                       cppID: drawerVoiceLabelID,
                       what: "a blank slot publishes only its program number")
    report.expectEqual("", VoiceLanePolicy.label(slot: -1, view: blank), cppID: drawerVoiceLabelID,
                       what: "a missing slot publishes no label at all")
    report.expectEqual("", VoiceLanePolicy.label(slot: session.bankSlots.count, view: nil),
                       cppID: drawerVoiceLabelID, what: "an out-of-range slot publishes no label")

    // The page's own blank-slot truth, driven through a real lane: a change into
    // a slot with no parsed voice stays explicit.
    guard let blankIndex = session.bankSlots.indices.first(where: {
        session.bankSlots[$0].voice == nil
    }) else {
        report.expect(true, cppID: drawerVoiceLabelID,
                      message: "the staged bank publishes no blank slot to drive")
        return
    }
    let fixture = drawerVoiceVoiceChangesFixture(suite: session, service: service,
                                      programs: [programs[0], blankIndex, programs[2]])
    guard let marker = fixture.marker(at: 48) else {
        report.fail(drawerVoiceLabelID, "the blank-slot fixture published no marker at tick 48")
        return
    }
    report.expect(marker.slotBlank, cppID: drawerVoiceLabelID,
                  message: "a change into a blank slot publishes blank truth")
    report.expectEqual("", marker.symbol, cppID: drawerVoiceLabelID,
                       what: "a blank slot publishes no symbol")
    report.expectEqual(String(format: "%03d", blankIndex), marker.label, cppID: drawerVoiceLabelID,
                       what: "a blank slot's marker label is its program number")
    fixture.session.editCursor = 48
    report.expect(fixture.page.contextBlank, cppID: drawerVoiceLabelID,
                  message: "the context readout publishes the blank truth too")
    report.expectEqual(blankIndex, fixture.page.contextSlot, cppID: drawerVoiceLabelID,
                       what: "the blank context names the blank slot")
    report.expectEqual("", fixture.page.contextSymbol, cppID: drawerVoiceLabelID,
                       what: "the blank context publishes no symbol")
}

@MainActor
func drawerVoiceCurrentVoiceContext(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let points = fixture.lanePoints()

    report.expectEqual(programs[0], VoiceLanePolicy.slot(firstProgram: programs[0], tick: 0,
                                                         points: points),
                       cppID: drawerVoiceContextID, what: "tick 0 resolves the opening program")
    report.expectEqual(programs[1], VoiceLanePolicy.slot(firstProgram: programs[0], tick: 48,
                                                         points: points),
                       cppID: drawerVoiceContextID, what: "a change takes effect at its own tick")
    report.expectEqual(programs[1], VoiceLanePolicy.slot(firstProgram: programs[0], tick: 119,
                                                         points: points),
                       cppID: drawerVoiceContextID, what: "the context holds until the next change")
    report.expectEqual(programs[2], VoiceLanePolicy.slot(firstProgram: programs[0], tick: 120,
                                                         points: points),
                       cppID: drawerVoiceContextID, what: "the late change takes effect at its tick")
    report.expectEqual(48, VoiceLanePolicy.endTick(after: 0, points: points), cppID: drawerVoiceContextID,
                       what: "the opening span ends at the first change")
    report.expectEqual(nil, VoiceLanePolicy.endTick(after: 120, points: points), cppID: drawerVoiceContextID,
                       what: "the last span runs to the song's end")

    // Cursor-only publication updates the stopped readout, not static content
    // or document/history state.
    let cursorBuilds = page.contentBuildCount
    let cursorDocument = fixture.snapshot
    fixture.session.editCursor = 60
    report.expectEqual(programs[1], page.contextSlot, cppID: drawerVoiceContextID,
                       what: "the stopped context resolves at the published edit cursor")
    report.expectEqual(VoiceLanePolicy.label(slot: programs[1],
                                             view: fixture.session.bankSlots[programs[1]]),
                       page.readoutText, cppID: drawerVoiceContextID,
                       what: "the readout names the edit cursor's program")
    report.expectEqual(cursorBuilds, page.contentBuildCount, cppID: drawerVoiceContextID,
                       what: "cursor-only publication rebuilds no marker content")
    report.expectEqual(cursorDocument, fixture.snapshot, cppID: drawerVoiceContextID,
                       what: "cursor-only publication changes no document or history state")

    // Playing: the same document resolves at the rounded shared-playhead tick.
    page.refreshPlayhead(tick: 8, playing: true)
    report.expectEqual(programs[0], page.presentedContextSlot, cppID: drawerVoiceContextID,
                       what: "the playing context resolves at the shared tick, not the cursor")
    report.expect(page.presentedPlaying, cppID: drawerVoiceContextID,
                  message: "the presentation publishes its own playing state")
    page.refreshPlayhead(tick: 96.4, playing: true)
    report.expectEqual(programs[1], page.presentedContextSlot, cppID: drawerVoiceContextID,
                       what: "a rounded playing tick crosses into the next span")
    report.expectEqual(96, page.presentedContextTick, cppID: drawerVoiceContextID,
                       what: "the presented tick is the rounded shared tick")

    // Back to stopped: the edit cursor owns the context again.
    page.refreshPlayhead(tick: 96, playing: false)
    report.expectEqual(programs[1], page.contextSlot, cppID: drawerVoiceContextID,
                       what: "the stopped context returns to the edit cursor")
    let laterCursorBuilds = page.contentBuildCount
    fixture.session.editCursor = 130
    report.expectEqual(programs[2], page.contextSlot, cppID: drawerVoiceContextID,
                       what: "a moved edit cursor re-resolves the stopped context")
    report.expectEqual(laterCursorBuilds, page.contentBuildCount, cppID: drawerVoiceContextID,
                       what: "a later cursor-only publication remains readout-only")

    // A track switch re-derives the projection against the new track's lane.
    fixture.session.selectedTrack = 1
    page.refreshFromDocument()
    report.expectEqual([0], page.markerTicks, cppID: drawerVoiceContextID,
                       what: "the secondary track publishes only its own change")
    report.expectEqual(programs[2], page.contextSlot, cppID: drawerVoiceContextID,
                       what: "the readout follows the newly selected track")
    fixture.session.selectedTrack = 0
    page.refreshFromDocument()
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: drawerVoiceContextID,
                       what: "returning to the primary track restores its markers")
}

@MainActor
func drawerVoiceOccurrenceIdentity(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let points = fixture.lanePoints()
    report.expectEqual(points.map { VoiceOccurrence($0).text }, page.markerIdentities,
                       cppID: drawerVoiceIdentityID,
                       what: "a marker's identity is its lane occurrence's own identity")
    report.expect(page.markerIdentities.allSatisfy {
        $0.split(separator: ".").count == 4
    }, cppID: drawerVoiceIdentityID,
                  message: "an identity names chunk, event index, tick and value")

    // Two occurrences that share a tick are still distinct: identity is not a
    // list position and not a tick.
    let first = LanePoint(chunk: 1, eventIndex: 3, tick: 48, value: programs[0])
    let second = LanePoint(chunk: 1, eventIndex: 9, tick: 48, value: programs[0])
    report.expectEqual(VoiceOccurrence(first),
                       VoiceLanePolicy.occurrence(VoiceOccurrence(first), in: [first, second]),
                       cppID: drawerVoiceIdentityID,
                       what: "the identity resolves the occurrence it names")
    report.expectEqual(VoiceOccurrence(second),
                       VoiceLanePolicy.occurrence(at: 48, in: [first, second]),
                       cppID: drawerVoiceIdentityID,
                       what: "the tick lookup takes the document's last event at that tick")
    let mutated = VoiceOccurrence(chunk: first.chunk, eventIndex: first.eventIndex,
                                  tick: first.tick, value: first.value + 1)
    report.expect(VoiceLanePolicy.occurrence(mutated, in: [first, second]) == nil,
                  cppID: drawerVoiceIdentityID,
                  message: "a different value is never accepted as the frozen occurrence")
    report.expectEqual(first.eventIndex,
                       VoiceLanePolicy.occurrence(VoiceOccurrence(first),
                                                  in: points + [first])?.eventIndex,
                       cppID: drawerVoiceIdentityID,
                       what: "the resolved occurrence keeps the document's event index")

    // Camera-only refreshes keep the identity and move only the projection.
    let before = page.markerIdentities
    let x = page.publishedMarkers[1].x
    _ = page.pointerPress(x: x, y: 10, surface: 1, button: 1, modifiers: 0)
    let frozen = page.frozenOccurrence
    report.expectEqual(VoiceOccurrence(points[1]), frozen, cppID: drawerVoiceIdentityID,
                       what: "the press freezes the marker's own occurrence")
    fixture.session.mutateCamera { $0.setHScroll($0.snapshot.scrollX + 40) }
    report.expectEqual(before, page.markerIdentities, cppID: drawerVoiceIdentityID,
                       what: "a camera scroll changes no marker identity")
    report.expect(page.publishedMarkers[1].x != x, cppID: drawerVoiceIdentityID,
                  message: "a camera scroll does move the projection")
    report.expectEqual(frozen, page.frozenOccurrence, cppID: drawerVoiceIdentityID,
                       what: "the frozen occurrence survives a camera scroll")
    _ = page.pointerRelease(x: x, y: 10, button: 1)
    report.expect(!page.hasGesture, cppID: drawerVoiceIdentityID,
                  message: "the release ends the gesture without a draft")

    // A real insertion joins the lane. The occurrences the insert follows keep
    // the document's own identity; the ones after it shift their event index,
    // which is exactly why the capture carries the revision beside the identity.
    let earlier = page.publishedMarkers.filter { Tick($0.tick) <= 48 }.map(\.identity)
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.setPickerFilter(text: String(format: "%03d", programs[2]))
    page.selectPickerRow(index: 0)
    report.expect(page.acceptPicker(), cppID: drawerVoiceIdentityID,
                  message: "an insertion between the changes lands in the document")
    report.expectEqual(4, page.markerIdentities.count, cppID: drawerVoiceIdentityID,
                       what: "the inserted occurrence joins the projection")
    report.expectEqual(4, Set(page.markerIdentities).count, cppID: drawerVoiceIdentityID,
                       what: "the inserted occurrence has an identity of its own")
    report.expectEqual(earlier,
                       page.publishedMarkers.filter { Tick($0.tick) <= 48 }.map(\.identity),
                       cppID: drawerVoiceIdentityID,
                       what: "the occurrences before the edit keep their identity")
}

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
    report.expectEqual("Insert voice change", page.pickerTitle, cppID: drawerVoiceInsertionID,
                       what: "an empty-lane target opens the insertion title")
    report.expectEqual(96, page.pickerTargetTick, cppID: drawerVoiceInsertionID,
                       what: "the captured tick is the press's snapped tick")
    report.expect(page.pickerTargetIdentity == nil, cppID: drawerVoiceInsertionID,
                  message: "an empty-lane target carries no occurrence")
    report.expectEqual(programs[1], page.pickerProgram, cppID: drawerVoiceInsertionID,
                       what: "the picker opens on the slot the context resolves to")
    report.expect(page.interactionActive, cppID: drawerVoiceInsertionID,
                  message: "an open picker reports an active interaction")
    report.expectEqual(3, page.markerIdentities.count, cppID: drawerVoiceInsertionID,
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
    report.expectEqual(programs[2], page.pickerProgram, cppID: drawerVoiceInsertionID,
                       what: "the row press selects the filtered program")
    report.expect(page.acceptPicker(), cppID: drawerVoiceInsertionID,
                  message: "accepting the picker writes the captured target")
    report.expectEqual(4, fixture.lanePoints().count, cppID: drawerVoiceInsertionID,
                       what: "the insertion adds exactly one lane event")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: 96, in: fixture.lanePoints())?.value,
                       cppID: drawerVoiceInsertionID, what: "the inserted event carries the chosen slot")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: drawerVoiceInsertionID,
                       what: "the insertion is one revision")
    report.expect(fixture.snapshot.canUndo, cppID: drawerVoiceInsertionID,
                  message: "the insertion records one history entry")
    report.expectEqual([0, 48, 96, 120], page.markerTicks, cppID: drawerVoiceInsertionID,
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
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: drawerVoiceInsertionID,
                       what: "undo rebuilds the projection without the insertion")
    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(drawerVoiceInsertionID, "redo failed: \(error)")
        return
    }
    report.expectEqual(programs[2],
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
    report.expectEqual(settled, fixture.snapshot, cppID: drawerVoiceInsertionID,
                       what: "the same-value acceptance leaves the document untouched")

    // A filter that matches nothing cannot be accepted.
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.setPickerFilter(text: "zzz-no-such-voice")
    report.expect(!page.pickerHasMatch, cppID: drawerVoiceInsertionID,
                  message: "an unmatched filter publishes no match")
    report.expectEqual(0, page.pickerRowValues.count, cppID: drawerVoiceInsertionID,
                       what: "an unmatched filter publishes no row")
    report.expectEqual(-1, page.pickerIndex, cppID: drawerVoiceInsertionID,
                       what: "an unmatched filter publishes no current row")
    report.expect(!page.acceptPicker(), cppID: drawerVoiceInsertionID,
                  message: "an unmatched filter cannot be accepted")
    report.expectEqual(settled, fixture.snapshot, cppID: drawerVoiceInsertionID,
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
    report.expectEqual("Change voice", page.pickerTitle, cppID: drawerVoiceReplacementID,
                       what: "a marker target opens the change title")
    report.expectEqual(target.text, page.pickerTargetIdentity, cppID: drawerVoiceReplacementID,
                       what: "the captured identity is the pressed occurrence")
    report.expectEqual(48, page.pickerTargetTick, cppID: drawerVoiceReplacementID,
                       what: "the captured tick is the marker's own tick")
    report.expectEqual(target.value, page.pickerProgram, cppID: drawerVoiceReplacementID,
                       what: "the picker opens on the marker's current program")

    page.setPickerFilter(text: String(format: "%03d", programs[2]))
    page.selectPickerRow(index: 0)
    report.expect(page.acceptPicker(), cppID: drawerVoiceReplacementID,
                  message: "accepting the picker replaces the captured occurrence's value")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: 48, in: fixture.lanePoints())?.value,
                       cppID: drawerVoiceReplacementID, what: "the change at tick 48 carries the new slot")
    report.expectEqual(3, fixture.lanePoints().count, cppID: drawerVoiceReplacementID,
                       what: "a value replacement adds no event")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: drawerVoiceReplacementID,
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
    report.expectEqual(settled, fixture.snapshot, cppID: drawerVoiceReplacementID,
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
    report.expectEqual(settled, fixture.snapshot, cppID: drawerVoiceReplacementID,
                       what: "the dismissed press and its release write nothing")

    // A stale capture — the document moved under the open picker — writes
    // nothing and never retargets another occurrence.
    _ = page.pointerDoubleClick(x: markerX, y: 10)
    let staleTarget = page.pickerTargetIdentity
    let heldAtCapture = VoiceLanePolicy.occurrence(
        at: 48, in: fixture.document.lanePoints(track: 0, lane: .voice)).map { $0.text }
    report.expectEqual(heldAtCapture, staleTarget, cppID: drawerVoiceReplacementID,
                       what: "the capture names the occurrence the document held then")
    fixture.document.writeLane(track: 0, lane: .voice, from: 0, through: 0,
                               points: [LaneWrite(tick: 0, value: programs[2])])
    report.expect(!page.hasPicker, cppID: drawerVoiceReplacementID,
                  message: "a document change cancels the open picker")
    let rewrote = fixture.snapshot
    report.expect(!page.acceptPicker(), cppID: drawerVoiceReplacementID,
                  message: "an acceptance after the cancellation writes nothing")
    report.expectEqual(rewrote, fixture.snapshot, cppID: drawerVoiceReplacementID,
                       what: "the stale acceptance leaves the rewrite as the only change")
    report.expect(page.pickerTargetIdentity == nil, cppID: drawerVoiceReplacementID,
                  message: "the cancelled capture is gone instead of retargeted")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: 0, in: fixture.lanePoints())?.value,
                       cppID: drawerVoiceReplacementID, what: "the rewrite itself stands")
}

@MainActor
func drawerVoiceMarkerDragTransactions(_ report: CheckReport, suite: DocumentSession,
                                    service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot

    // Crossing/tied markers can propagate stair placement beyond the moved
    // label. A camera redraw must agree with the incremental drag projection.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1,
                          button: 1, modifiers: 0)
    for tick in [Tick(120), 180, 0, 48, 96] {
        _ = page.pointerMove(x: fixture.markerX(tick), y: 10, buttons: 1)
        let incremental = page.publishedMarkers
        page.refreshCamera()
        let redrawn = page.publishedMarkers
        report.expectEqual(incremental.map(\.identity), redrawn.map(\.identity),
                           cppID: drawerVoiceMoveID, what: "drag and redraw preserve tied marker order")
        report.expectEqual(incremental.map(\.label), redrawn.map(\.label),
                           cppID: drawerVoiceMoveID, what: "drag and redraw agree on label elision")
        for (before, after) in zip(incremental, redrawn) {
            for component in ["x", "y", "width", "height"] {
                report.expectEqual(before.labelRect[component] as? Double,
                                   after.labelRect[component] as? Double, cppID: drawerVoiceMoveID,
                                   what: "drag and redraw agree on label \(component)")
            }
            report.expectEqual(before.offscreen, after.offscreen, cppID: drawerVoiceMoveID,
                               what: "drag and redraw agree on offscreen labels")
        }
    }
    page.cancelSectionInteraction()

    // Below the activation distance: a press and a release commit nothing.
    let startX = fixture.markerX(48)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 4, y: 10, buttons: 1)
    report.expect(!page.dragActive, cppID: drawerVoiceMoveID,
                  message: "a move below the activation distance stays pending")
    _ = page.pointerRelease(x: startX + 4, y: 10, button: 1)
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceMoveID,
                       what: "a drag below the activation distance commits nothing")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: drawerVoiceMoveID,
                       what: "the untouched occurrence keeps its tick")

    // An activated drag commits exactly one move at the tick it previewed.
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    report.expect(page.hasGesture, cppID: drawerVoiceMoveID, message: "the press owns a gesture")
    report.expectEqual(48, page.frozenOccurrence?.tick, cppID: drawerVoiceMoveID,
                       what: "the frozen occurrence is the pressed marker")
    report.expect(page.interactionActive, cppID: drawerVoiceMoveID,
                  message: "the live gesture reports an active interaction")
    _ = page.pointerMove(x: startX + 60, y: 10, buttons: 1)
    report.expect(page.dragActive, cppID: drawerVoiceMoveID,
                  message: "the drag activates past its activation distance")
    guard let preview = page.dragPreviewTick else {
        report.fail(drawerVoiceMoveID, "the activated drag published no preview tick")
        return
    }
    report.expect(preview != 48, cppID: drawerVoiceMoveID,
                  message: "the preview tick drafts away from the frozen tick")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceMoveID,
                       what: "motion is preview only and mutates nothing")
    report.expectEqual(preview, page.markerTicks[1], cppID: drawerVoiceMoveID,
                       what: "the projection draws the marker at the preview tick")
    _ = page.pointerRelease(x: startX + 60, y: 10, button: 1)
    report.expect(!page.hasGesture && !page.interactionActive, cppID: drawerVoiceMoveID,
                  message: "the release ends the gesture and its interaction")
    report.expectEqual(preview, fixture.lanePoints()[1].tick, cppID: drawerVoiceMoveID,
                       what: "the release commits the preview tick")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: drawerVoiceMoveID,
                       what: "the move is one revision")
    report.expect(fixture.snapshot.canUndo, cppID: drawerVoiceMoveID,
                  message: "the move records one history entry")
    report.expect(VoiceLanePolicy.occurrence(at: 48, in: fixture.lanePoints()) == nil,
                  cppID: drawerVoiceMoveID, message: "the source tick no longer holds the occurrence")

    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(drawerVoiceMoveID, "undo failed: \(error)")
        return
    }
    report.expectEqual(48, fixture.lanePoints()[1].tick, cppID: drawerVoiceMoveID,
                       what: "undo restores the moved occurrence's tick")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: drawerVoiceMoveID,
                       what: "undo rebuilds the projection at the restored tick")
    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(drawerVoiceMoveID, "redo failed: \(error)")
        return
    }
    report.expectEqual(preview, fixture.lanePoints()[1].tick, cppID: drawerVoiceMoveID,
                       what: "redo reapplies the move")

    // A release back on the frozen tick is a no-op.
    let settled = fixture.snapshot
    let movedX = fixture.markerX(preview)
    _ = page.pointerPress(x: movedX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: movedX + 60, y: 10, buttons: 1)
    _ = page.pointerMove(x: movedX, y: 10, buttons: 1)
    report.expectEqual(preview, page.dragPreviewTick, cppID: drawerVoiceMoveID,
                       what: "the draft returns to the frozen tick")
    _ = page.pointerRelease(x: movedX, y: 10, button: 1)
    report.expectEqual(settled, fixture.snapshot, cppID: drawerVoiceMoveID,
                       what: "a release back on the frozen tick commits nothing")

    // A drag whose document moved under it refuses the commit instead of
    // retargeting the occurrence it now finds there.
    _ = page.pointerPress(x: movedX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: movedX + 60, y: 10, buttons: 1)
    let staleDraft = page.dragPreviewTick
    fixture.document.writeLane(track: 0, lane: .voice, from: 0, through: 0,
                               points: [LaneWrite(tick: 0, value: programs[2])])
    let rewritten = fixture.snapshot
    _ = page.pointerRelease(x: movedX + 60, y: 10, button: 1)
    report.expect(staleDraft != nil && staleDraft != preview, cppID: drawerVoiceMoveID,
                  message: "the stale drag had drafted another tick before the release")
    report.expectEqual(rewritten, fixture.snapshot, cppID: drawerVoiceMoveID,
                       what: "a drag whose revision moved under it commits nothing")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: 0, in: fixture.lanePoints())?.value,
                       cppID: drawerVoiceMoveID, what: "the concurrent rewrite is the one that stands")
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
    report.expectEqual(suite.bankSlots.count, page.pickerRowValues.count, cppID: drawerVoiceKeyboardID,
                       what: "an empty filter publishes every bank row")
    report.expectEqual(programs[1], page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "the picker opens on the context slot the target captured")
    report.expectEqual(programs[1], page.pickerIndex, cppID: drawerVoiceKeyboardID,
                       what: "the published row index follows the current program")
    let first = page.pickerProgram
    page.movePickerSelection(delta: 1)
    report.expectEqual(first + 1, page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "the down arrow moves to the next visible program")
    page.movePickerSelection(delta: -1)
    report.expectEqual(first, page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "the up arrow returns to the previous program")
    page.movePickerSelection(delta: -5)
    report.expectEqual(page.pickerRowPrograms.first ?? -1, page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "the navigation clamps at the first row")
    page.movePickerSelection(delta: 500)
    report.expectEqual(page.pickerRowPrograms.last ?? -1, page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "the navigation clamps at the last row")
    report.expectEqual(page.pickerRowPrograms.count - 1, page.pickerIndex, cppID: drawerVoiceKeyboardID,
                       what: "the row index follows the clamped program")
    page.selectPickerRow(index: 1)
    report.expectEqual(page.pickerRowPrograms[1], page.pickerProgram, cppID: drawerVoiceKeyboardID,
                       what: "a row press selects exactly that row's program")
    report.expect(page.pickerRowValues[1].selected, cppID: drawerVoiceKeyboardID,
                  message: "the selected row publishes its own state")
    report.expectEqual(1, page.pickerRowValues.filter(\.selected).count, cppID: drawerVoiceKeyboardID,
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
func drawerVoiceCancellationPaths(_ report: CheckReport, suite: DocumentSession,
                               service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot

    // A picker cancelled by the container's own path releases the interaction.
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.cancelSectionInteraction()
    report.expect(!page.hasPicker, cppID: drawerVoiceCancellationID,
                  message: "the container's cancellation closes the picker")
    report.expect(!page.interactionActive, cppID: drawerVoiceCancellationID,
                  message: "cancellation releases the follow-scroll gate")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceCancellationID,
                       what: "the cancelled picker wrote nothing")

    // A live drag cancelled mid-motion restores presentation and commits nothing.
    let startX = fixture.markerX(48)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 60, y: 10, buttons: 1)
    report.expect(page.dragActive, cppID: drawerVoiceCancellationID, message: "the drag is live")
    page.cancelSectionInteraction()
    report.expect(!page.hasGesture && !page.interactionActive, cppID: drawerVoiceCancellationID,
                  message: "cancellation ends the live drag")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: drawerVoiceCancellationID,
                       what: "the cancelled drag restores the projection from the document")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceCancellationID,
                       what: "the cancelled drag commits nothing")

    // The canvas keeps drawing after a cancellation.
    fixture.session.mutateCamera { $0.setHScroll($0.snapshot.scrollX + 20) }
    report.expectEqual(3, page.publishedMarkers.count, cppID: drawerVoiceCancellationID,
                       what: "the projection survives the cancellation")

    // A track switch invalidates an open modal instead of retargeting it.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expect(page.hasMenu, cppID: drawerVoiceCancellationID, message: "the menu is open")
    fixture.session.selectedTrack = 1
    page.refreshFromDocument()
    report.expect(!page.hasMenu, cppID: drawerVoiceCancellationID,
                  message: "a track switch cancels the captured menu")
    report.expect(!page.activateMenuAction(actionId: VoiceChangesPagePolicy.deleteMarkerAction),
                  cppID: drawerVoiceCancellationID, message: "the cancelled menu fires no row")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceCancellationID,
                       what: "the track switch wrote nothing")
    report.expectEqual([0], page.markerTicks, cppID: drawerVoiceCancellationID,
                       what: "the projection re-derives for the new track")
    fixture.session.selectedTrack = 0
    page.refreshFromDocument()

    // A hide cancels a live gesture through the same synchronous path.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 30, y: 10, buttons: 1)
    page.cancelSectionInteraction()
    report.expect(!page.dragActive, cppID: drawerVoiceCancellationID,
                  message: "a hide cancels the in-flight drag")
    report.expectEqual(48, page.markerTicks[1], cppID: drawerVoiceCancellationID,
                       what: "the hidden page's projection is back on the document")

    // Detach ends everything and publishes no marker.
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.detach()
    report.expect(!page.hasPicker && !page.hasMenu && !page.hasGesture, cppID: drawerVoiceCancellationID,
                  message: "detach cancels every interaction")
    report.expectEqual(0, page.markerIdentities.count, cppID: drawerVoiceCancellationID,
                       what: "detach publishes no marker")
    report.expectEqual(0, page.heldSpans.count, cppID: drawerVoiceCancellationID,
                       what: "detach publishes no held span")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceCancellationID,
                       what: "detach wrote nothing")

    // The gutter never edits and opens no modal.
    let gutterFixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    report.expect(!gutterFixture.page.pointerPress(x: 10, y: 10, surface: 0, button: 1,
                                                   modifiers: 0),
                  cppID: drawerVoiceCancellationID,
                  message: "a gutter press is not consumed by the page")
    report.expect(!gutterFixture.page.hasGesture, cppID: drawerVoiceCancellationID,
                  message: "a gutter press starts no gesture")
    report.expect(!gutterFixture.page.hasPicker, cppID: drawerVoiceCancellationID,
                  message: "a gutter press opens no picker")
    report.expect(!gutterFixture.page.interactionActive, cppID: drawerVoiceCancellationID,
                  message: "a gutter press reports no interaction")
}

@MainActor
func drawerVoiceUndoRedoRefresh(_ report: CheckReport, suite: DocumentSession,
                             service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let builds = page.contentBuildCount
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.setPickerFilter(text: String(format: "%03d", programs[2]))
    page.selectPickerRow(index: 0)
    _ = page.acceptPicker()
    report.expectEqual(builds + 1, page.contentBuildCount, cppID: drawerVoiceHistoryID,
                       what: "one committed edit rebuilds the projection exactly once")
    let editedBuilds = page.contentBuildCount
    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(drawerVoiceHistoryID, "undo failed: \(error)")
        return
    }
    report.expect(page.contentBuildCount > editedBuilds, cppID: drawerVoiceHistoryID,
                  message: "undo rebuilds every affected page")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: drawerVoiceHistoryID,
                       what: "undo removes the inserted marker")
    report.expectEqual(VoiceLanePolicy.label(slot: programs[0],
                                             view: fixture.session.bankSlots[programs[0]]),
                       page.contextLabel(at: page.contextSlot), cppID: drawerVoiceHistoryID,
                       what: "undo restores the context the readout resolves")
    let undoneBuilds = page.contentBuildCount
    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(drawerVoiceHistoryID, "redo failed: \(error)")
        return
    }
    report.expect(page.contentBuildCount > undoneBuilds, cppID: drawerVoiceHistoryID,
                  message: "redo rebuilds the projection again")
    report.expectEqual([0, 48, 96, 120], page.markerTicks, cppID: drawerVoiceHistoryID,
                       what: "redo republishes the full marker set")

    // An equal refresh leaves every marker exactly as it was: the rebuild runs,
    // and no published row is replaced.
    let identities = page.markerIdentities
    let publishedMarkers = page.markers.asArray
    page.refreshFromDocument()
    report.expectEqual(identities, page.markerIdentities, cppID: drawerVoiceHistoryID,
                       what: "an equal refresh leaves every marker identity in place")
    report.expectEqual(publishedMarkers.count, page.markers.count, cppID: drawerVoiceHistoryID,
                       what: "an equal refresh publishes the same marker count")
    report.expect(zip(publishedMarkers, page.markers.asArray).allSatisfy { $0 === $1 },
                  cppID: drawerVoiceHistoryID,
                  message: "an equal refresh replaces no published marker row")
}

@MainActor
func drawerVoicePlayheadDiagnostics(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let documentFacts = fixture.snapshot
    page.refreshPlayhead(tick: 0, playing: true)
    let builds = page.contentBuildCount
    let presentations = page.playheadPresentationCount
    let contextChanges = page.contextChangeCount
    let readout = page.readoutText
    report.expectEqual(programs[0], page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "the playing context opens on the first program span")

    // Every other distinct shared tick inside the same span: the page consumes
    // each of them and rebuilds no static content.
    var ticks: [Double] = []
    for step in 1..<48 { ticks.append(Double(step)) }
    for tick in ticks {
        page.refreshPlayhead(tick: tick, playing: true)
    }
    report.expectEqual(presentations + UInt64(ticks.count), page.playheadPresentationCount,
                       cppID: drawerVoiceDiagnosticsID,
                       what: "every distinct shared presentation is consumed once")
    // A shared position that rounds to a tick the page already presented is not
    // a presentation of its own, and neither is an equal one.
    let roundingBase = page.playheadPresentationCount
    page.refreshPlayhead(tick: 47.4, playing: true)
    report.expectEqual(roundingBase, page.playheadPresentationCount, cppID: drawerVoiceDiagnosticsID,
                       what: "a position rounding to an already presented tick presents nothing")
    page.refreshPlayhead(tick: 47, playing: true)
    report.expectEqual(roundingBase, page.playheadPresentationCount, cppID: drawerVoiceDiagnosticsID,
                       what: "an equal presentation is not consumed twice")
    report.expectEqual(builds, page.contentBuildCount, cppID: drawerVoiceDiagnosticsID,
                       what: "playhead-only movement inside one span rebuilds no content")
    report.expectEqual(contextChanges, page.contextChangeCount, cppID: drawerVoiceDiagnosticsID,
                       what: "no span was crossed inside the span itself")
    report.expectEqual(programs[0], page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "the presented context stayed in its own span")
    report.expectEqual(readout, page.readoutText, cppID: drawerVoiceDiagnosticsID,
                       what: "the readout names the same program throughout the span")
    report.expectEqual(documentFacts, fixture.snapshot, cppID: drawerVoiceDiagnosticsID,
                       what: "playhead movement mutates no document and consumes no redo")

    // An equal presentation publishes nothing.
    let settled = page.playheadPresentationCount
    page.refreshPlayhead(tick: ticks.last ?? 0, playing: true)
    report.expectEqual(settled, page.playheadPresentationCount, cppID: drawerVoiceDiagnosticsID,
                       what: "an equal presentation is not consumed twice")

    // Crossing into the next span updates the readout and rebuilds once.
    page.refreshPlayhead(tick: 60, playing: true)
    report.expectEqual(programs[1], page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "crossing a span updates the context indicator")
    report.expectEqual(builds + 1, page.contentBuildCount, cppID: drawerVoiceDiagnosticsID,
                       what: "crossing a span rebuilds the projection exactly once")
    report.expectEqual(contextChanges + 1, page.contextChangeCount, cppID: drawerVoiceDiagnosticsID,
                       what: "one context change is counted")
    report.expect(page.readoutText.hasPrefix(String(format: "%03d", programs[1])),
                  cppID: drawerVoiceDiagnosticsID, message: "the readout names the new span's program")

    // Stopping returns the context to the edit cursor.
    fixture.session.editCursor = 200
    page.refreshPlayhead(tick: 60, playing: false)
    report.expectEqual(programs[2], page.presentedContextSlot, cppID: drawerVoiceDiagnosticsID,
                       what: "the stopped context follows the edit cursor")
    report.expectEqual(builds + 2, page.contentBuildCount, cppID: drawerVoiceDiagnosticsID,
                       what: "the playing-to-stopped transition rebuilds once")
}

@MainActor
func drawerVoiceAltFineClockLattice(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService, programs: [Int]) {
    // `SongDocument::ticksPerClock`: one clock is `division / (24 * (extended ? 2 : 1))`
    // ticks, floored at one.
    report.expectEqual(1, TimelineSnapPolicy.clockTicks(division: 24, extendedClocks: false),
                       cppID: drawerVoiceFineSnapID,
                       what: "a 24-tick division names one tick per clock")
    report.expectEqual(4, TimelineSnapPolicy.clockTicks(division: 96, extendedClocks: false),
                       cppID: drawerVoiceFineSnapID,
                       what: "a 96-tick division names four ticks per clock")
    report.expectEqual(2, TimelineSnapPolicy.clockTicks(division: 96, extendedClocks: true),
                       cppID: drawerVoiceFineSnapID,
                       what: "extended clocks halve the ticks per clock")
    report.expectEqual(1, TimelineSnapPolicy.clockTicks(division: 1, extendedClocks: false),
                       cppID: drawerVoiceFineSnapID, what: "the clock stride never falls below one tick")

    // `Grid::snapTick(tick, fine: true)`: the absolute clock lattice, rounded
    // half-up, clamped to the song's tick domain.
    report.expectEqual(4, TimelineSnapPolicy.fineSnap(5.9, clockTicks: 4), cppID: drawerVoiceFineSnapID,
                       what: "a position inside a clock cell snaps to its floor")
    report.expectEqual(8, TimelineSnapPolicy.fineSnap(6, clockTicks: 4), cppID: drawerVoiceFineSnapID,
                       what: "an exact tie rounds up, as the legacy lattice does")
    report.expectEqual(8, TimelineSnapPolicy.fineSnap(6.1, clockTicks: 4), cppID: drawerVoiceFineSnapID,
                       what: "a position past the midpoint snaps up")
    report.expectEqual(0, TimelineSnapPolicy.fineSnap(-3, clockTicks: 4), cppID: drawerVoiceFineSnapID,
                       what: "the lattice is anchored at zero")
    report.expectEqual(TimeDefaults.maxTick,
                       TimelineSnapPolicy.fineSnap(Double(TimeDefaults.maxTick), clockTicks: 4),
                       cppID: drawerVoiceFineSnapID, what: "the lattice clamps to the song's tick domain")

    // The page's own drag: with the alt modifier the preview snaps on the clock
    // lattice of the document in front of it, not on the editing lattice.
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs,
                                      division: 96)
    let page = fixture.page
    let clock = TimelineSnapPolicy.clockTicks(
        division: fixture.document.ticksPerBeat,
        extendedClocks: fixture.document.state.config.extendedClocks)
    report.expect(clock >= 1, cppID: drawerVoiceFineSnapID,
                  message: "the fixture document publishes its own clock stride")
    let dragged = VoiceOccurrence(fixture.lanePoints()[1])
    let startX = fixture.markerX(dragged.tick)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    let altX = startX + 60
    _ = page.pointerMove(x: altX, y: 10, buttons: 1, modifiers: VoiceModifier.alt)
    let raw = fixture.session.camera.tickAtContentX(altX)
    report.expectEqual(TimelineSnapPolicy.fineSnap(raw, clockTicks: clock), page.dragPreviewTick,
                       cppID: drawerVoiceFineSnapID,
                       what: "the alt drag previews the legacy clock lattice")
    report.expect((page.dragPreviewTick ?? 1) % Tick(clock) == 0, cppID: drawerVoiceFineSnapID,
                  message: "the alt preview lands on the clock lattice itself")
    _ = page.pointerRelease(x: altX, y: 10, button: 1)
    report.expectEqual(TimelineSnapPolicy.fineSnap(raw, clockTicks: clock),
                       fixture.lanePoints().first { $0.value == dragged.value }?.tick,
                       cppID: drawerVoiceFineSnapID,
                       what: "the released alt drag commits the clock-lattice tick")
}

@MainActor
func drawerVoiceCollisionDragOutcome(_ report: CheckReport, suite: DocumentSession,
                                  service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot
    let moving = VoiceOccurrence(fixture.lanePoints()[1])
    let occupied = VoiceOccurrence(fixture.lanePoints()[2])
    let startX = fixture.markerX(moving.tick)

    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: fixture.markerX(occupied.tick), y: 10, buttons: 1)
    report.expectEqual(occupied.tick, page.dragPreviewTick, cppID: drawerVoiceCollisionID,
                       what: "the dragged preview lands on the occupied tick")
    _ = page.pointerRelease(x: fixture.markerX(occupied.tick), y: 10, button: 1)

    let points = fixture.lanePoints()
    report.expectEqual(2, points.count, cppID: drawerVoiceCollisionID,
                       what: "a move onto an occupied tick leaves one occurrence there")
    report.expectEqual(moving.value,
                       VoiceLanePolicy.occurrence(at: occupied.tick, in: points)?.value,
                       cppID: drawerVoiceCollisionID, what: "the moved occurrence wins the destination")
    report.expect(VoiceLanePolicy.occurrence(at: moving.tick, in: points) == nil,
                  cppID: drawerVoiceCollisionID, message: "the source tick no longer holds a change")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: drawerVoiceCollisionID,
                       what: "the collision is one revision")
    report.expect(fixture.snapshot.canUndo && !baseline.canUndo, cppID: drawerVoiceCollisionID,
                  message: "the collision records exactly one history entry")

    // One history entry, both sides restored: an unintended second entry would
    // leave one of the two occurrences behind.
    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(drawerVoiceCollisionID, "undo failed: \(error)")
        return
    }
    let restored = fixture.lanePoints()
    report.expectEqual(3, restored.count, cppID: drawerVoiceCollisionID,
                       what: "a single undo restores both occurrences")
    report.expectEqual(programs[1], VoiceLanePolicy.occurrence(at: 48, in: restored)?.value,
                       cppID: drawerVoiceCollisionID, what: "the moved occurrence is back at its tick")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: occupied.tick, in: restored)?.value,
                       cppID: drawerVoiceCollisionID, what: "the displaced occurrence is back too")
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
    report.expectEqual(blankIndex,
                       VoiceLanePolicy.occurrence(at: 96, in: fixture.lanePoints())?.value,
                       cppID: drawerVoiceCollisionID, what: "the lane holds the blank slot's number")

    guard let marker = fixture.marker(at: 96) else {
        report.fail(drawerVoiceCollisionID, "the blank-slot change publishes no marker")
        return
    }
    report.expect(marker.slotBlank, cppID: drawerVoiceCollisionID,
                  message: "the committed blank slot publishes blank truth")
    report.expectEqual("", marker.symbol, cppID: drawerVoiceCollisionID,
                       what: "the committed blank slot publishes no symbol")
    report.expectEqual(String(format: "%03d", blankIndex), marker.label, cppID: drawerVoiceCollisionID,
                       what: "the committed blank slot's label stays its program number")

    fixture.session.editCursor = 96
    report.expect(fixture.page.contextBlank, cppID: drawerVoiceCollisionID,
                  message: "the readout publishes the blank truth for that context")
    report.expectEqual(String(format: "%03d", blankIndex), fixture.page.readoutText,
                       cppID: drawerVoiceCollisionID,
                       what: "the readout of a blank context is the program number alone")
}

@MainActor
func drawerVoiceAuditionCapability(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    var calls: [[UInt8]] = []
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    let baseline = fixture.snapshot
    let first = UInt8(programs[0])
    let second = UInt8(programs[1])

    func hold(_ program: Int) {
        guard let row = page.pickerRowPrograms.firstIndex(of: program) else {
            report.fail(drawerVoiceAuditionID, "the audition program is absent from the picker")
            return
        }
        page.pressAndHoldPickerRow(index: row)
    }
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    hold(programs[0])
    hold(programs[0])
    hold(programs[1])
    page.releasePickerAudition()
    page.releasePickerAudition()
    report.expectEqual([[first, 60, 112], [first, 60, 0],
                        [first, 60, 112], [first, 60, 0],
                        [second, 60, 112], [second, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "held program replacement releases once before the next note")

    calls.removeAll()
    hold(programs[0])
    page.setPickerFilter(text: "__no_voice_can_match__")
    report.expectEqual([[first, 60, 112], [first, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "filter invalidation releases the sounding program")
    page.cancelPicker()

    calls.removeAll()
    _ = page.pointerDoubleClick(x: fixture.markerX(48), y: 10)
    hold(programs[1])
    _ = page.acceptPicker()
    report.expectEqual([[second, 60, 112], [second, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "same-value acceptance releases without a musical edit")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceAuditionID,
                       what: "audition, filtering and same-value acceptance leave document/history unchanged")

    calls.removeAll()
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    hold(programs[0])
    _ = page.pointerDoubleClick(x: fixture.markerX(48), y: 10)
    hold(programs[1])
    page.onAuditionVoice = nil
    report.expectEqual([[first, 60, 112], [first, 60, 0],
                        [second, 60, 112], [second, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "picker and callback replacement release through the old owner")
    report.expect(!page.auditionAvailable, cppID: drawerVoiceAuditionID,
                  message: "removing the real callback removes audition availability")

    calls.removeAll()
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    hold(programs[0])
    fixture.session.selectedTrack = 1
    page.releasePickerAudition()
    report.expectEqual([[first, 60, 112], [first, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "stale track cancellation releases without a duplicate note-off")
    fixture.session.selectedTrack = 0
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    calls.removeAll()
    hold(programs[1])
    page.cancelSectionInteraction()
    report.expectEqual([[second, 60, 112], [second, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "workspace cancellation releases its held voice")
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)

    calls.removeAll()
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    hold(programs[0])
    page.detach()
    report.expectEqual([[first, 60, 112], [first, 60, 0]], calls,
                       cppID: drawerVoiceAuditionID, what: "document teardown releases the final held program")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceAuditionID,
                       what: "picker replacement and teardown write no musical state")
}
