import Foundation
import PorydawApp
import PorydawCore

@MainActor
func drawerVelocityVoiceContextResolution(_ report: CheckReport, session: DocumentSession) {
    let macros: [(Int32, VoiceKind)] = [
        (BankVoiceMacro.directSound, .directSound),
        (BankVoiceMacro.directSoundNoResample, .directSound),
        (BankVoiceMacro.directSoundAlt, .directSound),
        (BankVoiceMacro.square1, .square1),
        (BankVoiceMacro.square1Alt, .square1),
        (BankVoiceMacro.square2, .square2),
        (BankVoiceMacro.square2Alt, .square2),
        (BankVoiceMacro.programmableWave, .wave),
        (BankVoiceMacro.programmableWaveAlt, .wave),
        (BankVoiceMacro.noise, .noise),
        (BankVoiceMacro.noiseAlt, .noise),
    ]
    for (macro, expected) in macros {
        report.expect(VelocityContextPolicy.voiceKind(macro: macro) == expected, cppID: drawerVelocityContextID,
                      message: "macro \(macro) names \(expected)")
    }
    report.expect(VelocityContextPolicy.voiceKind(macro: BankVoiceMacro.keysplit) == nil,
                  cppID: drawerVelocityContextID, message: "a keysplit macro names no exact top-level map")
    report.expect(VelocityContextPolicy.voiceKind(macro: BankVoiceMacro.keysplitAll) == nil,
                  cppID: drawerVelocityContextID, message: "a drumkit macro names no exact top-level map")

    let changes = [
        LanePoint(chunk: 0, eventIndex: 4, tick: 0, value: 5),
        LanePoint(chunk: 0, eventIndex: 8, tick: 96, value: 2),
    ]
    let early = VelocityContextPolicy.slot(firstProgram: 0, tick: 24, voiceChanges: changes)
    report.expectEqual(expected: 5, actual: early.slot, cppID: drawerVelocityContextID,
                       what: "the last voice change at or before the tick wins")
    report.expectEqual(expected: Tick(96), actual: early.endTick ?? 0, cppID: drawerVelocityContextID,
                       what: "the section ends at the next voice change")
    let late = VelocityContextPolicy.slot(firstProgram: 0, tick: 200, voiceChanges: changes)
    report.expectEqual(expected: 2, actual: late.slot, cppID: drawerVelocityContextID, what: "the later change takes over")
    report.expect(late.endTick == nil, cppID: drawerVelocityContextID,
                  message: "a context with no later change runs to the song's end")
    let opening = VelocityContextPolicy.slot(firstProgram: 7, tick: 0, voiceChanges: [])
    report.expectEqual(expected: 7, actual: opening.slot, cppID: drawerVelocityContextID,
                       what: "an unchanged program is the track's first program")

    let slots = [
        BankSlotView(kind: BankSlotKind.editable,
                     voice: BankVoice(macro: BankVoiceMacro.square1)),
        BankSlotView(kind: BankSlotKind.editable,
                     voice: BankVoice(macro: BankVoiceMacro.programmableWave)),
        BankSlotView(kind: BankSlotKind.readOnlyVoice, voice: nil),
        BankSlotView(kind: BankSlotKind.editable,
                     voice: BankVoice(macro: BankVoiceMacro.keysplit)),
    ]
    let square = VelocityContextPolicy.resolve(slot: 0, endTick: Tick(96), slots: slots)
    report.expectEqual(expected: VelocityContextStatus.resolved.rawValue, actual: square.status.rawValue,
                       cppID: drawerVelocityContextID, what: "an editable square-1 slot resolves exactly")
    report.expect(square.map == VelocityMap(voiceKind: .square1), cppID: drawerVelocityContextID,
                  message: "the resolved map is the slot's top-level voice")
    report.expectEqual(expected: Tick(96), actual: square.endTick ?? 0, cppID: drawerVelocityContextID,
                       what: "the context keeps its section boundary")
    report.expect(square.editable, cppID: drawerVelocityContextID, message: "a resolved context is editable")
    let readOnly = VelocityContextPolicy.resolve(slot: 2, endTick: nil, slots: slots)
    report.expectEqual(expected: VelocityContextStatus.unresolvedVoice.rawValue, actual: readOnly.status.rawValue,
                       cppID: drawerVelocityContextID,
                       what: "a slot that publishes no parsed voice is unresolved")
    report.expect(!readOnly.editable && !readOnly.diagnostic.isEmpty, cppID: drawerVelocityContextID,
                  message: "an unresolved voice publishes a diagnostic and refuses editing")
    let missing = VelocityContextPolicy.resolve(slot: 99, endTick: nil, slots: slots)
    report.expectEqual(expected: VelocityContextStatus.unresolvedVoice.rawValue, actual: missing.status.rawValue,
                       cppID: drawerVelocityContextID, what: "a program outside the bank is unresolved")

    let firstEditable = session.bankSlots.firstIndex { $0.voice != nil } ?? -1
    report.expect(firstEditable >= 0, cppID: drawerVelocityContextID,
                  message: "the staged bank publishes at least one parsed voice")
    let real = VelocityContextPolicy.resolve(slot: firstEditable, endTick: nil,
                                             slots: session.bankSlots)
    report.expectEqual(expected: VelocityContextStatus.resolved.rawValue, actual: real.status.rawValue, cppID: drawerVelocityContextID,
                       what: "the staged bank's first parsed slot resolves exactly")
    report.expectEqual(expected: BankSlotKind.editable, actual: session.bankSlots[firstEditable].kind, cppID: drawerVelocityContextID,
                       what: "the resolved slot is the editable line kind")
}

@MainActor
func drawerVelocityProjectionRefresh(_ report: CheckReport, session: DocumentSession,
                               service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let page = fixture.page
    let note = fixture.notes[1]
    let before = fixture.handle(note)!
    let oldX = before.x
    let oldY = before.y
    let oldValue = before.value
    fixture.session.mutateCamera { camera in
        camera.setTimeZoom(camera.snapshot.pixelsPerBeat * 2)
    }
    page.refreshCamera()
    let moved = fixture.handle(note)!
    let expectedX = fixture.session.camera.displayX(tick: Double(note.tick), origin: 0, dpr: 1)
    report.expect(moved.x == expectedX && moved.x != oldX && moved.y == oldY
                      && moved.value == oldValue,
                  cppID: drawerVelocityProjectionID, message: "camera refresh moves the handle without changing its value axis")
    let row = page.handles[1]
    report.expect(row.x == expectedX, cppID: drawerVelocityProjectionID,
                  message: "the QML model receives the moved handle")
    report.expectEqual(expected: oldY, actual: row.y, cppID: drawerVelocityProjectionID,
                       what: "camera refresh preserves the node's marker-y value")
    report.expect(page.rulerWidth > page.axisModel.geometry.labelWidth
                      && page.plotWidth > page.rulerWidth
                      && page.plotHeight == page.axisModel.geometry.height,
                  cppID: drawerVelocityProjectionID,
                  message: "the live velocity body publishes its ruler and plot layout geometry")
    _ = page.pointerMove(x: moved.x, y: moved.y, buttons: 0)
    report.expect(page.hoveredNoteText == "\(note.id.rawValue)", cppID: drawerVelocityProjectionID,
                  message: "hit testing follows the camera-refreshed handle")
    report.expect(page.axisModel.markers.contains { $0.velocity == Int(note.velocity) }
                      && page.axisGraduationsVisible,
                  cppID: drawerVelocityProjectionID,
                  message: "hovering a node presents its velocity marker and intrinsic graduations")
    report.expect(page.axisModel.markers.contains {
        $0.velocity == Int(note.velocity)
            && abs($0.y - page.axisModel.velocityToY(Int(note.velocity))) <= 1
    }, cppID: drawerVelocityProjectionID,
    message: "the live ruler marker aligns with its underlying note's stored velocity")
    page.pointerLeave()
    report.expect(!page.axisModel.markers.contains { $0.velocity == Int(note.velocity) },
                  cppID: drawerVelocityProjectionID,
                  message: "leaving the node removes its hover-only velocity marker")
    _ = fixture.document.setVelocities([NoteVelocity(noteID: note.id, velocity: 127)],
                                       expectedRevision: fixture.document.revision)
    page.refreshFromDocument()
    report.expect(fixture.handle(note)?.value == 127, cppID: drawerVelocityProjectionID,
                  message: "document edits invalidate cached note values")
    report.expectEqual(expected: 127, actual: drawerVelocityTimelineVelocity(fixture.session, note.id),
                       cppID: drawerVelocityProjectionID,
                       what: "document edits rebuild the live timeline projection")
    _ = try? runBlocking { try await fixture.session.undo() }
    page.refreshFromDocument()
    report.expect(fixture.handle(note)?.value == oldValue, cppID: drawerVelocityProjectionID,
                  message: "undo invalidates cached note values again")
    report.expectEqual(expected: oldValue, actual: drawerVelocityTimelineVelocity(fixture.session, note.id),
                       cppID: drawerVelocityProjectionID,
                       what: "undo rebuilds the original timeline projection")
    fixture.session.setSelectedNotes([fixture.notes[0].id])
    page.refreshFromDocument()
    page.setUseDetents(enabled: false)
    if let handle = fixture.handle(fixture.notes[0]) {
        let destination = page.axisModel.velocityToY(74)
        _ = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1,
                              modifiers: 0x0400_0000)
        _ = page.pointerMove(x: handle.x, y: destination, buttons: 1)
        report.expectEqual(expected: 74, actual: fixture.handle(fixture.notes[0])?.value ?? -1,
                           cppID: drawerVelocityProjectionID,
                           what: "a held raw drag displays velocity 74 before committing")
        report.expect(page.axisModel.markers.contains { $0.velocity == 74 },
                      cppID: drawerVelocityProjectionID,
                      message: "the held raw-74 drag paints its live ruler marker at 74")
        report.expect(page.axisModel.markers.contains {
            $0.velocity == 74 && abs($0.y - page.axisModel.velocityToY(74)) <= 1
        }, cppID: drawerVelocityProjectionID,
        message: "the live preview marker aligns with the independently requested raw velocity")
        page.cancelSectionInteraction()
    }
    page.detach()
}

@MainActor
func drawerVelocityVoiceContextInvalidation(_ report: CheckReport, session: DocumentSession,
                                           service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let page = fixture.page
    let note = fixture.notes[1]
    fixture.session.setSelectedNotes([note.id])
    page.refreshFromDocument()
    report.expect(!page.contextUnsupported && page.contextSlot == 0,
                  cppID: drawerVelocityProjectionID,
                  message: "the selected note starts with a parsed, editable opening voice")
    fixture.document.writeLane(track: 0, lane: .voice, from: 0, through: 0,
                               points: [LaneWrite(tick: 0, value: 127)])
    page.refreshFromDocument()
    report.expect(page.contextUnsupported && page.contextSlot == 127,
                  cppID: drawerVelocityProjectionID,
                  message: "an unresolved program change invalidates the selected velocity context")
    report.expect(!page.openSelectedVelocityPrompt(), cppID: drawerVelocityProjectionID,
                  message: "an unresolved selected voice cannot open the velocity prompt")
    fixture.drag(note, release: false)
    report.expect(!page.interactionActive, cppID: drawerVelocityProjectionID,
                  message: "an unresolved selected voice cannot start a velocity drag")
    page.cancelSectionInteraction()
    do {
        _ = try runBlocking { try await fixture.session.undo() }
    } catch {
        report.expect(false, cppID: drawerVelocityProjectionID,
                      message: "undoing the unresolved program must succeed: \(error)")
    }
    page.refreshFromDocument()
    report.expect(!page.contextUnsupported && page.contextSlot == 0,
                  cppID: drawerVelocityProjectionID,
                  message: "undo restores the parsed context rather than retaining the unresolved projection")
    report.expect(page.openSelectedVelocityPrompt(), cppID: drawerVelocityProjectionID,
                  message: "the restored voice makes the selected velocity prompt available again")
    page.cancelPrompt()
    fixture.drag(note, release: false)
    report.expect(page.interactionActive, cppID: drawerVelocityProjectionID,
                  message: "the restored voice makes the selected velocity drag available again")
    page.cancelSectionInteraction()
    page.detach()
}

@MainActor
func drawerVelocityPlayheadDiagnostics(_ report: CheckReport, session: DocumentSession,
                                 service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let page = fixture.page
    page.refreshPlayhead(tick: 0, playing: true)
    let handleCount = fixture.handles.count
    for tick in 1...128 {
        page.refreshPlayhead(tick: Double(tick) / 8, playing: true)
    }
    report.expectEqual(expected: Tick(16), actual: page.presentedContextTick, cppID: drawerVelocityDiagnosticsID,
                       what: "the presented context tick is the rounded playhead tick")
    report.expectEqual(expected: 0, actual: page.presentedContextSlot, cppID: drawerVelocityDiagnosticsID,
                       what: "the presented context slot is the bank slot at that tick")
    var roundedTicks: [Tick] = []
    var boundarySlots: [Int] = []
    for position in [-1.0, 0.49, 0.5, 0.51] {
        page.refreshPlayhead(tick: position, playing: true)
        roundedTicks.append(page.presentedContextTick)
        boundarySlots.append(page.presentedContextSlot)
    }
    report.expectEqual(expected: [Tick(0), 0, 1, 1], actual: roundedTicks,
                       cppID: drawerVelocityDiagnosticsID,
                       what: "four live playhead boundaries clamp and round to their exact ticks")
    report.expectEqual(expected: [0, 0, 0, 0], actual: boundarySlots,
                       cppID: drawerVelocityDiagnosticsID,
                       what: "each rounded playhead boundary resolves the real opening bank program")
    report.expectEqual(expected: handleCount, actual: fixture.handles.count, cppID: drawerVelocityDiagnosticsID,
                       what: "playhead movement preserves the displayed note count")

    // Crossing a voice change presents its slot; stopping follows the edit cursor.
    page.refreshPlayhead(tick: 96, playing: true)
    report.expectEqual(expected: 2, actual: page.presentedContextSlot, cppID: drawerVelocityDiagnosticsID,
                       what: "the new section resolves the slot of its own tick")
    page.refreshPlayhead(tick: 96, playing: false)
    page.refreshPlayhead(tick: 400, playing: false)

    // Cursor-only publication crosses into another voice context without a
    // document mutation or a broad document refresh.
    fixture.session.onChange = { [weak page] change in
        if change.domains.contains(.cursor) {
            page?.refreshEditCursor()
        }
    }
    let cursorDocument = DocumentSnapshot(fixture.document)
    fixture.session.editCursor = 100
    report.expectEqual(expected: 2, actual: page.context.slot, cppID: drawerVelocityDiagnosticsID,
                       what: "the stopped velocity context consumes the published edit cursor")
    report.expectEqual(expected: cursorDocument, actual: DocumentSnapshot(fixture.document), cppID: drawerVelocityDiagnosticsID,
                       what: "cursor-only publication changes no document or history state")

    fixture.session.setSelectedNotes([fixture.notes[0].id])
    page.refreshFromDocument()
    report.expectEqual(expected: 1, actual: page.selectedCount, cppID: drawerVelocityProjectionID,
                       what: "the selected handle publishes its own count")
    fixture.session.adjustTrackScope(track: 0, action: .plain)
    page.refreshFromDocument()
    report.expect(fixture.session.selectedNoteOrder.isEmpty && page.selectedCount == 0,
                  cppID: drawerVelocityDiagnosticsID,
                  message: "a plain track-header selection empties the velocity note selection")
    fixture.session.setSelectedNotes([fixture.notes[0].id])
    page.refreshFromDocument()
    if let handle = fixture.handle(fixture.notes[0]) {
        page.pointerMove(x: handle.x, y: handle.y, buttons: 0)
    }
    report.expectEqual(expected: fixture.handle(fixture.notes[0])?.label ?? "", actual: page.readoutText,
                       cppID: drawerVelocityProjectionID,
                       what: "the hovered handle publishes its displayed value as the readout")
    report.expectEqual(expected: "\(fixture.notes[0].id.rawValue)", actual: page.hoveredNoteText, cppID: drawerVelocityProjectionID,
                       what: "the hovered handle publishes its own identity")
    page.pointerMove(x: 3, y: 3, buttons: 0)
    report.expect(!page.readoutVisible, cppID: drawerVelocityProjectionID,
                  message: "hover leaving every handle hides the readout")
    let stableLabels = page.axisLabels.asArray
    let stableCount = page.handles.asArray.count
    page.refreshFromDocument()
    report.expectEqual(expected: stableLabels.count, actual: page.axisLabels.asArray.count,
                       cppID: drawerVelocityDiagnosticsID,
                       what: "song refresh preserves the velocity text row count")
    report.expect(zip(stableLabels, page.axisLabels.asArray).allSatisfy { $0 === $1 },
                  cppID: drawerVelocityDiagnosticsID,
                  message: "song refresh keeps unchanged velocity text rows in place")
    fixture.session.mutateCamera { camera in
        camera.setHScroll(camera.snapshot.scrollX + 12)
    }
    page.refreshHorizontalProjection()
    report.expect(page.axisLabels.asArray.count == stableLabels.count
                  && zip(stableLabels, page.axisLabels.asArray).allSatisfy { $0 === $1 }
                  && page.handles.asArray.count == stableCount,
                  cppID: drawerVelocityDiagnosticsID,
                  message: "horizontal scrolling leaves stable velocity text rows untouched")
}
