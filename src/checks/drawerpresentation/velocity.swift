import Foundation
import PorydawApp
import PorydawCore

// Existing scenarios paired with velocity.cpp.
// Entry order remains in VelocityPageChecks.swift.

@MainActor
func drawerVelocityValueAxisLadder(_ report: CheckReport) {
    var geometry = VelocityAxisGeometry()
    geometry.height = 120
    geometry.verticalInset = 5
    geometry.labelHeight = 14
    geometry.continuousDensityD1 = 78
    geometry.continuousDensityD2 = 108
    geometry.continuousDensityD3 = 156
    geometry.continuousDensityD4 = 312
    let continuous = VelocityAxisModel(map: VelocityMap(voiceKind: .unresolved),
                                       geometry: geometry, activeValues: [100, 64])
    report.expectEqual(VelocityAxisModel.Mode.continuous.rawValue, continuous.mode.rawValue,
                       cppID: drawerVelocityAxisID,
                       what: "an unresolved voice uses the continuous 1-127 ruler")
    report.expect(continuous.labels.count == 5 && continuous.ticks.count == 9, cppID: drawerVelocityAxisID,
                  message: "the mid density band publishes 9 ticks and 5 labels")
    report.expect(continuous.labels.map(\.velocity) == [127, 96, 64, 32, 1], cppID: drawerVelocityAxisID,
                  message: "the density band's labels descend from 127 to 1")
    report.expect(continuous.ticks.map(\.velocity) == [127, 112, 96, 80, 64, 48, 32, 16, 1],
                  cppID: drawerVelocityAxisID, message: "the density band's ticks step by sixteen")
    report.expectEqual(2, continuous.markers.count, cppID: drawerVelocityAxisID,
                       what: "one marker per distinct displayed value")
    report.expectEqual(64, continuous.markers[0].velocity, cppID: drawerVelocityAxisID,
                       what: "the lowest displayed value names the first marker")
    report.expectEqual(100, continuous.markers[1].velocity, cppID: drawerVelocityAxisID,
                       what: "the highest displayed value names the second marker")
    report.expect(continuous.markers[0].y > continuous.markers[1].y, cppID: drawerVelocityAxisID,
                  message: "a lower velocity draws lower on the ruler")
    let single = VelocityAxisModel(map: VelocityMap(voiceKind: .unresolved), geometry: geometry,
                                   activeValues: [76, 76])
    report.expectEqual(1, single.markers.count, cppID: drawerVelocityAxisID,
                       what: "equal displayed values collapse to one marker")
    report.expectEqual(127, continuous.yToVelocity(continuous.top), cppID: drawerVelocityAxisID,
                       what: "the ruler's top is velocity 127")
    report.expectEqual(1, continuous.yToVelocity(continuous.bottom), cppID: drawerVelocityAxisID,
                       what: "the ruler's bottom is velocity 1")
    report.expectEqual(127, continuous.yToVelocity(-500), cppID: drawerVelocityAxisID,
                       what: "a pointer above the ruler clamps to the maximum velocity")

    var short = geometry
    short.height = 40
    let dense = VelocityAxisModel(map: VelocityMap(voiceKind: .unresolved), geometry: short)
    report.expect(dense.ticks.count == 5 && dense.labels.count == 3, cppID: drawerVelocityAxisID,
                  message: "a 40px body uses the first density band")
    report.expect(dense.labels.map(\.velocity) == [127, 64, 1], cppID: drawerVelocityAxisID,
                  message: "the first band labels 127/64/1 only")
    report.expect(dense.hasLabel(64) && !dense.hasLabel(96), cppID: drawerVelocityAxisID,
                  message: "the first band omits the mid values")
    var tall = geometry
    tall.height = 400
    let finest = VelocityAxisModel(map: VelocityMap(voiceKind: .unresolved), geometry: tall)
    report.expect(finest.ticks.count == 32 && finest.labels.count == 17, cppID: drawerVelocityAxisID,
                  message: "a 400px body reaches the finest band's tick and label caps")

    let labelY = continuous.labels[2].y
    report.expectEqual(64, continuous.rulerVelocityAt(y: labelY, labelHeight: 14), cppID: drawerVelocityAxisID,
                       what: "a ruler press inside a label row takes its value")
    let betweenRows = (continuous.labels[0].y + continuous.labels[1].y) / 2
    report.expectEqual(-1, continuous.rulerVelocityAt(y: betweenRows, labelHeight: 2),
                       cppID: drawerVelocityAxisID, what: "a ruler press between rows reports no value")
    report.expect(continuous.inRuler(x: 0, rulerWidth: 56), cppID: drawerVelocityAxisID,
                  message: "the ruler owns x = 0")
    report.expect(!continuous.inRuler(x: 56, rulerWidth: 56), cppID: drawerVelocityAxisID,
                  message: "the ruler ends at the gutter width")
    report.expectEqual("Velocity", continuous.accessibleDescription, cppID: drawerVelocityAxisID,
                       what: "the continuous ruler's description is the plain domain")
}

@MainActor
func drawerVelocityPsgIntrinsicRows(_ report: CheckReport) {
    var geometry = VelocityAxisGeometry()
    geometry.height = 120
    geometry.verticalInset = 5
    geometry.labelHeight = 14
    geometry.continuousDensityD1 = 78
    geometry.continuousDensityD2 = 108
    geometry.continuousDensityD3 = 156
    geometry.continuousDensityD4 = 312
    let square = VelocityAxisModel(map: VelocityMap(voiceKind: .square1), geometry: geometry,
                                   activeValues: [76])
    report.expectEqual(VelocityAxisModel.Mode.intrinsic.rawValue, square.mode.rawValue, cppID: drawerVelocityPsgID,
                       what: "a PSG voice uses the intrinsic level ruler")
    report.expectEqual(16, square.graduations.count, cppID: drawerVelocityPsgID,
                       what: "Square 1 publishes sixteen volume levels")
    let wave = VelocityAxisModel(map: VelocityMap(voiceKind: .wave), geometry: geometry)
    report.expectEqual(5, wave.graduations.count, cppID: drawerVelocityPsgID,
                       what: "Programmable Wave publishes five volume levels")
    report.expectEqual("Vol 10", square.graduations[9].text, cppID: drawerVelocityPsgID,
                       what: "a graduation names its own level")
    report.expectEqual(76, square.graduations[9].velocity, cppID: drawerVelocityPsgID,
                       what: "level 9's representative velocity is 76")
    report.expect(square.graduations[9].active, cppID: drawerVelocityPsgID,
                  message: "the displayed value marks its own graduation active")
    report.expect(square.graduations[9].audible, cppID: drawerVelocityPsgID,
                  message: "an audible level is not the silent level")
    report.expect(!square.graduations[0].audible, cppID: drawerVelocityPsgID,
                  message: "level 0 is the silent level")
    report.expect(square.levelToY(0) > square.levelToY(15), cppID: drawerVelocityPsgID,
                  message: "lower levels draw lower")
    report.expectEqual(9, square.yToLevel(square.levelToY(9)), cppID: drawerVelocityPsgID,
                       what: "a level center maps back to its own level")
    let boundary = square.levelBoundaryToY(8)
    report.expect(boundary < square.levelToY(8) && boundary > square.levelToY(9), cppID: drawerVelocityPsgID,
                  message: "a level boundary sits between the two row centers")
    report.expectEqual(76, square.rulerVelocityAt(y: square.levelToY(9), labelHeight: 14),
                       cppID: drawerVelocityPsgID, what: "an intrinsic ruler press takes the level's value")
    report.expect(square.accessibleDescription.contains("Square 1"), cppID: drawerVelocityPsgID,
                  message: "the accessible description names the voice")
}

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
    report.expectEqual(5, early.slot, cppID: drawerVelocityContextID,
                       what: "the last voice change at or before the tick wins")
    report.expectEqual(Tick(96), early.endTick ?? 0, cppID: drawerVelocityContextID,
                       what: "the section ends at the next voice change")
    let late = VelocityContextPolicy.slot(firstProgram: 0, tick: 200, voiceChanges: changes)
    report.expectEqual(2, late.slot, cppID: drawerVelocityContextID, what: "the later change takes over")
    report.expect(late.endTick == nil, cppID: drawerVelocityContextID,
                  message: "a context with no later change runs to the song's end")
    let opening = VelocityContextPolicy.slot(firstProgram: 7, tick: 0, voiceChanges: [])
    report.expectEqual(7, opening.slot, cppID: drawerVelocityContextID,
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
    report.expectEqual(VelocityContextStatus.resolved.rawValue, square.status.rawValue,
                       cppID: drawerVelocityContextID, what: "an editable square-1 slot resolves exactly")
    report.expect(square.map == VelocityMap(voiceKind: .square1), cppID: drawerVelocityContextID,
                  message: "the resolved map is the slot's top-level voice")
    report.expectEqual(Tick(96), square.endTick ?? 0, cppID: drawerVelocityContextID,
                       what: "the context keeps its section boundary")
    report.expect(square.editable, cppID: drawerVelocityContextID, message: "a resolved context is editable")
    let readOnly = VelocityContextPolicy.resolve(slot: 2, endTick: nil, slots: slots)
    report.expectEqual(VelocityContextStatus.unresolvedVoice.rawValue, readOnly.status.rawValue,
                       cppID: drawerVelocityContextID,
                       what: "a slot that publishes no parsed voice is unresolved")
    report.expect(!readOnly.editable && !readOnly.diagnostic.isEmpty, cppID: drawerVelocityContextID,
                  message: "an unresolved voice publishes a diagnostic and refuses editing")
    let missing = VelocityContextPolicy.resolve(slot: 99, endTick: nil, slots: slots)
    report.expectEqual(VelocityContextStatus.unresolvedVoice.rawValue, missing.status.rawValue,
                       cppID: drawerVelocityContextID, what: "a program outside the bank is unresolved")

    let firstEditable = session.bankSlots.firstIndex { $0.voice != nil } ?? -1
    report.expect(firstEditable >= 0, cppID: drawerVelocityContextID,
                  message: "the staged bank publishes at least one parsed voice")
    let real = VelocityContextPolicy.resolve(slot: firstEditable, endTick: nil,
                                             slots: session.bankSlots)
    report.expectEqual(VelocityContextStatus.resolved.rawValue, real.status.rawValue, cppID: drawerVelocityContextID,
                       what: "the staged bank's first parsed slot resolves exactly")
    report.expectEqual(BankSlotKind.editable, session.bankSlots[firstEditable].kind, cppID: drawerVelocityContextID,
                       what: "the resolved slot is the editable line kind")
}

@MainActor
func drawerVelocityKeysplitPerNoteMapping(_ report: CheckReport, session: DocumentSession,
                                   service: ProjectService) {
    var macros = Array(repeating: Int32(-1), count: 128)
    macros[60] = BankVoiceMacro.square1
    macros[67] = BankVoiceMacro.programmableWave
    macros[72] = BankVoiceMacro.square1
    let split = BankSlotView(kind: BankSlotKind.editable,
                            voice: BankVoice(macro: BankVoiceMacro.keysplitAll),
                            subvoiceMacros: macros)
    let slots = [split, BankSlotView(), split]
    let keyless = VelocityContextPolicy.resolve(slot: 0, endTick: nil, slots: slots)
    report.expect(keyless.map == VelocityMap(voiceKind: .keyless) && !keyless.editable,
                  cppID: drawerVelocityKeysplitID, message: "a split without a note key remains keyless")
    let invalid = VelocityContextPolicy.resolve(slot: 0, endTick: nil, slots: slots, key: 61)
    report.expect(invalid.map == VelocityMap(voiceKind: .invalid) && !invalid.editable,
                  cppID: drawerVelocityKeysplitID, message: "invalid child facts never borrow another key")
    for (key, kind) in [(60, VoiceKind.square1), (67, .wave), (72, .square1)] {
        let context = VelocityContextPolicy.resolve(slot: 0, endTick: nil, slots: slots, key: key)
        report.expect(context.editable && context.map == VelocityMap(voiceKind: kind),
                      cppID: drawerVelocityKeysplitID, message: "key \(key) resolves its own child map")
    }
    report.expect(split.subvoiceMacro(forKey: -1) == nil
                      && split.subvoiceMacro(forKey: 128) == nil,
                  cppID: drawerVelocityKeysplitID, message: "out-of-domain keys do not resolve")
    let document = SongDocument(file: drawerVelocityVelocityPageFixture(),
                                config: session.document.state.config,
                                source: session.document.source,
                                trackBudget: session.document.trackBudget)
    let splitSession = DocumentSession(document: document, service: service,
                                       lease: session.bankLease, slots: slots,
                                       dirty: false, loadName: session.bankLoadName,
                                       sampleRate: 48_000)
    splitSession.selectedTrack = 0
    let page = VelocityPage(baseFontPx: 13)
    page.attach(session: splitSession, palette: GridPalette())
    page.configureBody(width: 400, height: 120, rulerWidth: 56, devicePixelRatio: 1,
                       baseFontPx: 13, dragDistance: 10)
    let notes = document.notes(in: 0)
    splitSession.setSelectedNotes([notes[0].id, notes[2].id])
    page.refreshFromDocument()
    report.expect(page.detentsAvailable && !page.contextUnsupported
                      && page.axisMode == VelocityAxisModel.Mode.intrinsic.rawValue,
                  cppID: drawerVelocityKeysplitID, message: "compatible per-key PSG notes retain detents")
    splitSession.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    report.expect(!page.detentsAvailable && !page.contextUnsupported
                      && page.axisMode == VelocityAxisModel.Mode.continuous.rawValue,
                  cppID: drawerVelocityKeysplitID, message: "mixed PSG maps remain editable and continuous")
    for note in notes.prefix(2) {
        let kind: VoiceKind = note.pitch == 60 ? .square1 : .wave
        let map = VelocityMap(voiceKind: kind)
        let noteAxis = VelocityAxisModel(map: map, geometry: page.axisModel.geometry)
        let handle = page.publishedHandlesSnapshot.first { $0.noteIdText == "\(note.id.rawValue)" }
        report.expect(handle?.y == noteAxis.levelToY(map.level(of: Int(note.velocity))!),
                      cppID: drawerVelocityKeysplitID,
                      message: "mixed selection places each handle using its own level boundaries")
    }
    if let wave = page.publishedHandlesSnapshot.first(where: { $0.noteIdText == "\(notes[1].id.rawValue)" }) {
        _ = page.pointerMove(x: wave.x, y: wave.y, buttons: 0)
        report.expect(page.axisModel.map == VelocityMap(voiceKind: .wave),
                      cppID: drawerVelocityKeysplitID, message: "hover resolves the hovered note key")
        page.pointerLeave()
    }
    let before = drawerVelocityDocumentSnapshot(document)
    report.expect(page.openSelectedVelocityPrompt(), cppID: drawerVelocityKeysplitID,
                  message: "mixed per-key selection opens its prompt")
    page.updatePromptDraft(draft: "127")
    report.expect(drawerVelocityDocumentSnapshot(document) == before, cppID: drawerVelocityKeysplitID,
                  message: "per-key prompt drafts never mutate history")
    report.expect(page.acceptPrompt(), cppID: drawerVelocityKeysplitID,
                  message: "per-key prompt accepts one captured transaction")
    let accepted = drawerVelocityDocumentSnapshot(document)
    report.expect(document.note(notes[0].id)?.velocity == 127
                      && document.note(notes[1].id)?.velocity == 127
                      && document.note(notes[2].id)?.velocity == notes[2].velocity
                      && accepted.revision == before.revision + 1,
                  cppID: drawerVelocityKeysplitID, message: "acceptance changes only captured notes once")
    report.expect(!page.acceptPrompt() && drawerVelocityDocumentSnapshot(document) == accepted,
                  cppID: drawerVelocityKeysplitID, message: "repeated acceptance cannot duplicate a transaction")
    _ = try? drawerVelocityRunBlocking { try await splitSession.undo() }
    report.expect(document.note(notes[0].id)?.velocity == notes[0].velocity
                      && document.note(notes[1].id)?.velocity == notes[1].velocity,
                  cppID: drawerVelocityKeysplitID, message: "one undo restores both captured values")
    page.detach()

    let invalidSession = DocumentSession(document: document, service: service,
                                         lease: session.bankLease, slots: [BankSlotView()],
                                         dirty: false, loadName: session.bankLoadName,
                                         sampleRate: 48_000)
    invalidSession.selectedTrack = 0
    page.attach(session: invalidSession, palette: GridPalette())
    report.expect(page.contextUnsupported, cppID: drawerVelocityKeysplitID,
                  message: "the invalid bank context advertises that velocity editing is unavailable")
    let invalidBefore = drawerVelocityDocumentSnapshot(document)
    _ = page.pointerPress(x: 399, y: 0, surface: VelocityInputSurface.plot.rawValue,
                          button: 1, modifiers: 0)
    report.expect(!page.interactionActive, cppID: drawerVelocityKeysplitID,
                  message: "an unsupported paint press never suspends follow or owns Escape")
    _ = page.pointerMove(x: 0, y: 60, buttons: 1)
    _ = page.pointerRelease(x: 0, y: 60, button: 1)
    report.expect(drawerVelocityDocumentSnapshot(document) == invalidBefore, cppID: drawerVelocityKeysplitID,
                  message: "dragging an unsupported velocity context cannot change notes or history")
    page.detach()
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
    _ = page.pointerMove(x: moved.x, y: moved.y, buttons: 0)
    report.expect(page.hoveredNoteText == "\(note.id.rawValue)", cppID: drawerVelocityProjectionID,
                  message: "hit testing follows the camera-refreshed handle")
    page.pointerLeave()
    _ = fixture.document.setVelocities([NoteVelocity(noteID: note.id, velocity: 127)],
                                       expectedRevision: fixture.document.revision)
    page.refreshFromDocument()
    report.expect(fixture.handle(note)?.value == 127, cppID: drawerVelocityProjectionID,
                  message: "document edits invalidate cached note values")
    _ = try? drawerVelocityRunBlocking { try await fixture.session.undo() }
    page.refreshFromDocument()
    report.expect(fixture.handle(note)?.value == oldValue, cppID: drawerVelocityProjectionID,
                  message: "undo invalidates cached note values again")
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
        _ = try drawerVelocityRunBlocking { try await fixture.session.undo() }
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
    report.expectEqual(Tick(16), page.presentedContextTick, cppID: drawerVelocityDiagnosticsID,
                       what: "the presented context tick is the rounded playhead tick")
    report.expectEqual(0, page.presentedContextSlot, cppID: drawerVelocityDiagnosticsID,
                       what: "the presented context slot is the bank slot at that tick")
    report.expectEqual(handleCount, fixture.handles.count, cppID: drawerVelocityDiagnosticsID,
                       what: "playhead movement preserves the displayed note count")

    // Crossing a voice change presents its slot; stopping follows the edit cursor.
    page.refreshPlayhead(tick: 96, playing: true)
    report.expectEqual(2, page.presentedContextSlot, cppID: drawerVelocityDiagnosticsID,
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
    let cursorDocument = drawerVelocityDocumentSnapshot(fixture.document)
    fixture.session.editCursor = 100
    report.expectEqual(2, page.context.slot, cppID: drawerVelocityDiagnosticsID,
                       what: "the stopped velocity context consumes the published edit cursor")
    report.expectEqual(cursorDocument, drawerVelocityDocumentSnapshot(fixture.document), cppID: drawerVelocityDiagnosticsID,
                       what: "cursor-only publication changes no document or history state")

    fixture.session.setSelectedNotes([fixture.notes[0].id])
    page.refreshFromDocument()
    report.expectEqual(1, page.selectedCount, cppID: drawerVelocityProjectionID,
                       what: "the selected handle publishes its own count")
    if let handle = fixture.handle(fixture.notes[0]) {
        page.pointerMove(x: handle.x, y: handle.y, buttons: 0)
    }
    report.expectEqual(fixture.handle(fixture.notes[0])?.label ?? "", page.readoutText,
                       cppID: drawerVelocityProjectionID,
                       what: "the hovered handle publishes its displayed value as the readout")
    report.expectEqual("\(fixture.notes[0].id.rawValue)", page.hoveredNoteText, cppID: drawerVelocityProjectionID,
                       what: "the hovered handle publishes its own identity")
    page.pointerMove(x: 3, y: 3, buttons: 0)
    report.expect(!page.readoutVisible, cppID: drawerVelocityProjectionID,
                  message: "hover leaving every handle hides the readout")
}
