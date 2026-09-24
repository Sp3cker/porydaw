import Foundation
import PorydawApp
import PorydawCore

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
    report.expect((page.readoutRect["width"] as? Double ?? 0) > 0 &&
                  (page.readoutRect["height"] as? Double ?? 0) > 0, cppID: drawerVoiceProjectionID,
                  message: "the context readout publishes a usable rect")
    report.expectEqual(VoiceChangesPagePolicy.readoutAlignment, page.readoutAlignment,
                       cppID: drawerVoiceProjectionID,
                       what: "the readout publishes the legacy right alignment the composition draws")

    let hitX = fixture.markerX(48)
    _ = page.pointerPress(x: hitX + 9, y: 10, surface: 1, button: 1, modifiers: 0)
    report.expectEqual(48, page.frozenOccurrence?.tick, cppID: drawerVoiceProjectionID,
                       what: "a press inside the marker hit radius takes that marker")
    page.cancelSectionInteraction()
    _ = page.pointerPress(x: hitX + 12, y: 10, surface: 1, button: 1, modifiers: 0)
    report.expect(!page.hasGesture, cppID: drawerVoiceProjectionID,
                  message: "a press beyond the marker hit radius starts no marker gesture")
    _ = page.pointerRelease(x: hitX + 12, y: 10, button: 1)

    let before = page.publishedMarkers.map(\.label)
    _ = page.pointerMove(x: fixture.markerX(96), y: 10, buttons: 0)
    report.expect(page.hoverVisible, cppID: drawerVoiceProjectionID,
                  message: "a background hover publishes its slot label")
    report.expect(page.hoverText.hasPrefix("→ "), cppID: drawerVoiceProjectionID,
                  message: "the hover label keeps the legacy arrow prefix")
    report.expectEqual(before, page.publishedMarkers.map(\.label), cppID: drawerVoiceProjectionID,
                       what: "a hover repaints no marker label")
    report.expect((page.hoverLabelRect["width"] as? Double ?? 0) > 0 &&
                  (page.hoverLabelRect["height"] as? Double ?? 0) > 0, cppID: drawerVoiceProjectionID,
                  message: "the background hover publishes a usable label rect")

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
