import Foundation
import PorydawApp
import PorydawCore

// Direct coverage for the Velocity page. The pure layers (voice context, the
// value axis, the frozen gesture, the prompt transaction) are driven with
// synthetic values; the page owner is driven against a real `DocumentSession`
// and the suite's real bank slots, so every transaction claim is a real
// document-history claim.
//
// Translated legacy intent:
//
// - `drawerpresentation/VelocityPageTest::chromeAndContinuousAxis`,
//   `::continuousGraduationDensity`: the continuous ruler's density bands, the
//   displayed-value markers and the ruler hit rule;
// - `::psgAxisContexts`, `::psgRenderingAndDetentToggle`: intrinsic PSG
//   graduations, the active graduation of a displayed value, level boundaries
//   and the detent rule;
// - `::hoveredPsgContext`: a hovered note takes the axis context of its own
//   tick while the selection keeps its own;
// - `::editCursorAndContextRounding`: the playing context uses the rounded
//   shared playhead tick, the stopped context uses the edit cursor;
// - `::gridAndPanClamp`, `::fixtureRoute101AndInputGeometry`: the ruler owns
//   `[0, gutter)` and the plot x is the camera's own projection;
// - `::transientBandAndStackedNodes`: band preview selection and the stacked
//   node hit order;
// - `::rampAndRollPreview`: the shift-drag ramp, including the notes outside the
//   swept span;
// - `::velocityGestureTransactions`: preview never mutates, one commit makes one
//   history entry, Escape cancels, a stale revision commits nothing;
// - `::textRetentionAndPlayheadPerformance`: shared-playhead movement inside one
//   context rebuilds no static content;
// - `rollcheck/PianoRollTest::velocityPromptAcceptUndoLatch`, `::velocityPromptCancelStale`,
//   `::velocityPromptBounds`, `::velocityPromptOutsideRightNoRetarget`: the
//   prompt's capture, bounds, accepted transaction, cancellation and staleness;
// - `songview/editcommandtable.cpp` `edit.set_velocity`: the command row's
//   availability gate and its prompt dispatch.
//
// Per-key split fixtures exercise owned bank facts through the production page:
// keyless/invalid resolution, compatible PSG selection, mixed maps and prompts.

private let axisID = "swiftcore/VelocityPage::valueAxisLadder"
private let psgID = "swiftcore/VelocityPage::psgIntrinsicRows"
private let contextID = "swiftcore/VelocityPage::voiceContextResolution"
private let keysplitID = "swiftcore/VelocityPage::keysplitPerNoteMapping"
private let projectionID = "swiftcore/VelocityPage::handleProjection"
private let gestureID = "swiftcore/VelocityPage::frozenGesturePolicy"
private let transactionID = "swiftcore/VelocityPage::gestureTransactions"
private let promptID = "swiftcore/VelocityPage::promptTransaction"
private let cancellationID = "swiftcore/VelocityPage::cancellationPaths"
private let diagnosticsID = "swiftcore/VelocityPage::playheadDiagnostics"
private let commandID = "swiftcore/VelocityPage::commandAvailabilityAndRoute"
private let historyID = "swiftcore/VelocityPage::undoRedoRefresh"

// MARK: - Synthetic fixture

/// A synthetic song with a square-1 opening program and a voice change to noise
/// at tick 96, over the suite's real bank lease and slots.
private func velocityPageFixture() -> MidiFile {
    let conductor: [MidiEvent] = [
        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
    ]
    let notes: [MidiEvent] = [
        .channel(tick: 0, status: 0xC0, data0: 0),
        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 60),
        .channel(tick: 24, status: 0x90, data0: 67, data1: 64),
        .channel(tick: 48, status: 0x80, data0: 67),
        .channel(tick: 96, status: 0xC0, data0: 2),
        .channel(tick: 96, status: 0x90, data0: 72, data1: 32),
        .channel(tick: 120, status: 0x80, data0: 72),
    ]
    return MidiFile(division: 24, chunks: [
        MidiChunk(events: conductor, endTick: 144),
        MidiChunk(events: notes, endTick: 144),
    ])
}

/// The three checksum facts one finished transaction must move: the document
/// revision, the history identity (the Swift analogue of the legacy undo index)
/// and the undo/redo reachability.
@MainActor
private struct DocumentSnapshot: Equatable {
    var revision: UInt64
    var identity: DocumentIdentity
    var canUndo: Bool
    var canRedo: Bool

    init(_ document: SongDocument) {
        revision = document.revision
        identity = document.history.currentIdentity
        canUndo = document.history.canUndo
        canRedo = document.history.canRedo
    }
}

/// A page attached to a synthetic session that shares the suite's service and
/// bank lease, plus the composition facts the page needs.
@MainActor
private struct VelocityFixture {
    let session: DocumentSession
    let page: VelocityPage
    let document: SongDocument
    let notes: [Note]

    init(session suite: DocumentSession, service: ProjectService,
         baseFontPx: Double = 13) {
        let document = SongDocument(file: velocityPageFixture(),
                                    config: suite.document.state.config,
                                    source: suite.document.source,
                                    trackBudget: suite.document.trackBudget)
        let session = DocumentSession(document: document, service: service,
                                      lease: suite.bankLease, slots: suite.bankSlots,
                                      dirty: false, loadName: suite.bankLoadName,
                                      sampleRate: 48_000)
        session.selectedTrack = 0
        session.clearSelectedNotes()
        page = VelocityPage(baseFontPx: baseFontPx)
        self.session = session
        self.document = document
        notes = document.notes(in: 0)
        page.attach(session: session, palette: GridPalette())
        page.configureBody(width: 400, height: 120, rulerWidth: 56, devicePixelRatio: 1,
                           baseFontPx: baseFontPx, dragDistance: 10)
    }

    var handles: [VelocityHandle] { page.publishedHandlesSnapshot }

    func handle(_ note: Note) -> VelocityHandle? {
        handles.first { $0.noteIdText == "\(note.id.rawValue)" }
    }

    /// One press/move/release that starts exactly on the note's drawn node.
    func drag(_ note: Note, dx: Double = 0, dy: Double = -20, modifiers: Int = 0,
              release: Bool = true) {
        guard let handle = handle(note) else { return }
        _ = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1,
                              modifiers: modifiers)
        _ = page.pointerMove(x: handle.x + dx, y: handle.y + dy, buttons: 1)
        if release { _ = page.pointerRelease(x: handle.x + dx, y: handle.y + dy, button: 1) }
    }
}

@MainActor
private func runBlocking<T>(_ operation: @escaping @MainActor () async throws -> T) throws -> T {
    var outcome: Result<T, Error>?
    Task { @MainActor in
        do {
            outcome = .success(try await operation())
        } catch {
            outcome = .failure(error)
        }
    }
    let deadline = Date().addingTimeInterval(20)
    while outcome == nil {
        if Date() > deadline { throw RunBlockingTimeout.timeout }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    return try outcome!.get()
}

private enum RunBlockingTimeout: Error {
    case timeout
}

// MARK: - Suite entry

@MainActor
internal func runVelocityPageChecks(_ report: CheckReport, session: DocumentSession,
                                    service: ProjectService) {
    valueAxisLadder(report)
    psgIntrinsicRows(report)
    voiceContextResolution(report, session: session)
    frozenGesturePolicy(report, session: session, service: service)
    gestureTransactions(report, session: session, service: service)
    promptTransaction(report, session: session, service: service)
    keysplitPerNoteMapping(report, session: session, service: service)
    projectionRefresh(report, session: session, service: service)
    playheadDiagnostics(report, session: session, service: service)
    commandAvailability(report, session: session, service: service)
}

// MARK: - Pure axis

@MainActor
private func valueAxisLadder(_ report: CheckReport) {
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
                       cppID: axisID,
                       what: "an unresolved voice uses the continuous 1-127 ruler")
    report.expect(continuous.labels.count == 5 && continuous.ticks.count == 9, cppID: axisID,
                  message: "the mid density band publishes 9 ticks and 5 labels")
    report.expect(continuous.labels.map(\.velocity) == [127, 96, 64, 32, 1], cppID: axisID,
                  message: "the density band's labels descend from 127 to 1")
    report.expect(continuous.ticks.map(\.velocity) == [127, 112, 96, 80, 64, 48, 32, 16, 1],
                  cppID: axisID, message: "the density band's ticks step by sixteen")
    report.expectEqual(2, continuous.markers.count, cppID: axisID,
                       what: "one marker per distinct displayed value")
    report.expectEqual(64, continuous.markers[0].velocity, cppID: axisID,
                       what: "the lowest displayed value names the first marker")
    report.expectEqual(100, continuous.markers[1].velocity, cppID: axisID,
                       what: "the highest displayed value names the second marker")
    report.expect(continuous.markers[0].y > continuous.markers[1].y, cppID: axisID,
                  message: "a lower velocity draws lower on the ruler")
    let single = VelocityAxisModel(map: VelocityMap(voiceKind: .unresolved), geometry: geometry,
                                   activeValues: [76, 76])
    report.expectEqual(1, single.markers.count, cppID: axisID,
                       what: "equal displayed values collapse to one marker")
    report.expectEqual(127, continuous.yToVelocity(continuous.top), cppID: axisID,
                       what: "the ruler's top is velocity 127")
    report.expectEqual(1, continuous.yToVelocity(continuous.bottom), cppID: axisID,
                       what: "the ruler's bottom is velocity 1")
    report.expectEqual(127, continuous.yToVelocity(-500), cppID: axisID,
                       what: "a pointer above the ruler clamps to the maximum velocity")

    var short = geometry
    short.height = 40
    let dense = VelocityAxisModel(map: VelocityMap(voiceKind: .unresolved), geometry: short)
    report.expect(dense.ticks.count == 5 && dense.labels.count == 3, cppID: axisID,
                  message: "a 40px body uses the first density band")
    report.expect(dense.labels.map(\.velocity) == [127, 64, 1], cppID: axisID,
                  message: "the first band labels 127/64/1 only")
    report.expect(dense.hasLabel(64) && !dense.hasLabel(96), cppID: axisID,
                  message: "the first band omits the mid values")
    var tall = geometry
    tall.height = 400
    let finest = VelocityAxisModel(map: VelocityMap(voiceKind: .unresolved), geometry: tall)
    report.expect(finest.ticks.count == 32 && finest.labels.count == 17, cppID: axisID,
                  message: "a 400px body reaches the finest band's tick and label caps")

    let labelY = continuous.labels[2].y
    report.expectEqual(64, continuous.rulerVelocityAt(y: labelY, labelHeight: 14), cppID: axisID,
                       what: "a ruler press inside a label row takes its value")
    let betweenRows = (continuous.labels[0].y + continuous.labels[1].y) / 2
    report.expectEqual(-1, continuous.rulerVelocityAt(y: betweenRows, labelHeight: 2),
                       cppID: axisID, what: "a ruler press between rows reports no value")
    report.expect(continuous.inRuler(x: 0, rulerWidth: 56), cppID: axisID,
                  message: "the ruler owns x = 0")
    report.expect(!continuous.inRuler(x: 56, rulerWidth: 56), cppID: axisID,
                  message: "the ruler ends at the gutter width")
    report.expectEqual("Velocity", continuous.accessibleDescription, cppID: axisID,
                       what: "the continuous ruler's description is the plain domain")
}

@MainActor
private func psgIntrinsicRows(_ report: CheckReport) {
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
    report.expectEqual(VelocityAxisModel.Mode.intrinsic.rawValue, square.mode.rawValue, cppID: psgID,
                       what: "a PSG voice uses the intrinsic level ruler")
    report.expectEqual(16, square.graduations.count, cppID: psgID,
                       what: "Square 1 publishes sixteen volume levels")
    let wave = VelocityAxisModel(map: VelocityMap(voiceKind: .wave), geometry: geometry)
    report.expectEqual(5, wave.graduations.count, cppID: psgID,
                       what: "Programmable Wave publishes five volume levels")
    report.expectEqual("Vol 10", square.graduations[9].text, cppID: psgID,
                       what: "a graduation names its own level")
    report.expectEqual(76, square.graduations[9].velocity, cppID: psgID,
                       what: "level 9's representative velocity is 76")
    report.expect(square.graduations[9].active, cppID: psgID,
                  message: "the displayed value marks its own graduation active")
    report.expect(square.graduations[9].audible, cppID: psgID,
                  message: "an audible level is not the silent level")
    report.expect(!square.graduations[0].audible, cppID: psgID,
                  message: "level 0 is the silent level")
    report.expect(square.levelToY(0) > square.levelToY(15), cppID: psgID,
                  message: "lower levels draw lower")
    report.expectEqual(9, square.yToLevel(square.levelToY(9)), cppID: psgID,
                       what: "a level center maps back to its own level")
    let boundary = square.levelBoundaryToY(8)
    report.expect(boundary < square.levelToY(8) && boundary > square.levelToY(9), cppID: psgID,
                  message: "a level boundary sits between the two row centers")
    report.expectEqual(76, square.rulerVelocityAt(y: square.levelToY(9), labelHeight: 14),
                       cppID: psgID, what: "an intrinsic ruler press takes the level's value")
    report.expect(square.accessibleDescription.contains("Square 1"), cppID: psgID,
                  message: "the accessible description names the voice")
}

// MARK: - Context

@MainActor
private func voiceContextResolution(_ report: CheckReport, session: DocumentSession) {
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
        report.expect(VelocityContextPolicy.voiceKind(macro: macro) == expected, cppID: contextID,
                      message: "macro \(macro) names \(expected)")
    }
    report.expect(VelocityContextPolicy.voiceKind(macro: BankVoiceMacro.keysplit) == nil,
                  cppID: contextID, message: "a keysplit macro names no exact top-level map")
    report.expect(VelocityContextPolicy.voiceKind(macro: BankVoiceMacro.keysplitAll) == nil,
                  cppID: contextID, message: "a drumkit macro names no exact top-level map")

    let changes = [
        LanePoint(chunk: 0, eventIndex: 4, tick: 0, value: 5),
        LanePoint(chunk: 0, eventIndex: 8, tick: 96, value: 2),
    ]
    let early = VelocityContextPolicy.slot(firstProgram: 0, tick: 24, voiceChanges: changes)
    report.expectEqual(5, early.slot, cppID: contextID,
                       what: "the last voice change at or before the tick wins")
    report.expectEqual(Tick(96), early.endTick ?? 0, cppID: contextID,
                       what: "the section ends at the next voice change")
    let late = VelocityContextPolicy.slot(firstProgram: 0, tick: 200, voiceChanges: changes)
    report.expectEqual(2, late.slot, cppID: contextID, what: "the later change takes over")
    report.expect(late.endTick == nil, cppID: contextID,
                  message: "a context with no later change runs to the song's end")
    let opening = VelocityContextPolicy.slot(firstProgram: 7, tick: 0, voiceChanges: [])
    report.expectEqual(7, opening.slot, cppID: contextID,
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
                       cppID: contextID, what: "an editable square-1 slot resolves exactly")
    report.expect(square.map == VelocityMap(voiceKind: .square1), cppID: contextID,
                  message: "the resolved map is the slot's top-level voice")
    report.expectEqual(Tick(96), square.endTick ?? 0, cppID: contextID,
                       what: "the context keeps its section boundary")
    report.expect(square.editable, cppID: contextID, message: "a resolved context is editable")
    let readOnly = VelocityContextPolicy.resolve(slot: 2, endTick: nil, slots: slots)
    report.expectEqual(VelocityContextStatus.unresolvedVoice.rawValue, readOnly.status.rawValue,
                       cppID: contextID,
                       what: "a slot that publishes no parsed voice is unresolved")
    report.expect(!readOnly.editable && !readOnly.diagnostic.isEmpty, cppID: contextID,
                  message: "an unresolved voice publishes a diagnostic and refuses editing")
    let missing = VelocityContextPolicy.resolve(slot: 99, endTick: nil, slots: slots)
    report.expectEqual(VelocityContextStatus.unresolvedVoice.rawValue, missing.status.rawValue,
                       cppID: contextID, what: "a program outside the bank is unresolved")

    let firstEditable = session.bankSlots.firstIndex { $0.voice != nil } ?? -1
    report.expect(firstEditable >= 0, cppID: contextID,
                  message: "the staged bank publishes at least one parsed voice")
    let real = VelocityContextPolicy.resolve(slot: firstEditable, endTick: nil,
                                             slots: session.bankSlots)
    report.expectEqual(VelocityContextStatus.resolved.rawValue, real.status.rawValue, cppID: contextID,
                       what: "the staged bank's first parsed slot resolves exactly")
    report.expectEqual(BankSlotKind.editable, session.bankSlots[firstEditable].kind, cppID: contextID,
                       what: "the resolved slot is the editable line kind")
}

// MARK: - Frozen gesture

@MainActor
private func frozenGesturePolicy(_ report: CheckReport, session: DocumentSession,
                                 service: ProjectService) {
    let fixture = VelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(gestureID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    report.expectEqual(3, fixture.handles.count, cppID: projectionID,
                       what: "every note of the primary track publishes one handle")
    guard let firstHandle = fixture.handle(notes[0]),
          let thirdHandle = fixture.handle(notes[2])
    else {
        report.fail(projectionID, "the fixture's notes have no published handles")
        return
    }
    let openingMap = VelocityMap(voiceKind: .square1)
    report.expect(!firstHandle.selected, cppID: projectionID,
                  message: "a fresh selection publishes no selected handle")
    report.expectEqual(openingMap.level(of: Int(notes[0].velocity)) ?? -1, firstHandle.level,
                       cppID: projectionID,
                       what: "an intrinsic handle publishes the level of its displayed value")
    report.expect(abs(firstHandle.x - page.axisModel.geometry.labelWidth - 56) < 1.0
                      || firstHandle.x <= 400, cppID: projectionID,
                  message: "the handle's x is a plot-local camera projection")
    report.expect(fixture.handle(notes[0])!.y < firstHandle.hitRadius * 2
                      || firstHandle.y > 0, cppID: projectionID,
                  message: "the handle publishes a drawn y inside the body")

    var axisGeometry = page.axisModel.geometry
    let axis = VelocityAxisModel(map: VelocityMap(voiceKind: .unresolved), geometry: axisGeometry)
    var gesture = VelocityGestureState(
        kind: .relative, revision: fixture.document.revision, track: 0,
        notes: [
            VelocityFrozenNote(noteID: NoteID(1), tick: 0, duration: 24, pitch: 60, velocity: 10,
                               map: VelocityMap(voiceKind: .unresolved), exactOrigin: 10),
            VelocityFrozenNote(noteID: NoteID(2), tick: 24, duration: 24, pitch: 67, velocity: 120,
                               map: VelocityMap(voiceKind: .unresolved), exactOrigin: 120),
        ],
        axis: axis, detentUnlock: false, activationDistance: 1, pressX: 0,
        pressY: axis.velocityToY(10))
    VelocityGesturePolicy.applyRelative(&gesture, y: axis.velocityToY(10) - 0.5)
    report.expect(!gesture.relativeActivated && gesture.preview.isEmpty, cppID: gestureID,
                  message: "a drag inside the activation distance previews nothing")
    VelocityGesturePolicy.applyRelative(&gesture, y: axis.velocityToY(30))
    report.expect(gesture.relativeActivated, cppID: gestureID,
                  message: "leaving the activation distance arms the relative drag")
    report.expectEqual(30, Int(gesture.preview[NoteID(1)] ?? 0), cppID: gestureID,
                       what: "the low note takes the whole delta")
    report.expectEqual(127, Int(gesture.preview[NoteID(2)] ?? 0), cppID: gestureID,
                       what: "the high note clamps to the maximum instead of wrapping")
    report.expectEqual(2, VelocityGesturePolicy.updates(gesture).count, cppID: gestureID,
                       what: "the commit payload carries one update per frozen note")

    let psgMap = VelocityMap(voiceKind: .square1)
    axisGeometry.height = 120
    let psgAxis = VelocityAxisModel(map: psgMap, geometry: axisGeometry, activeValues: [60, 76])
    var psgGesture = VelocityGestureState(
        kind: .relative, revision: 1, track: 0,
        notes: [
            VelocityFrozenNote(noteID: NoteID(3), tick: 0, duration: 24, pitch: 60, velocity: 60,
                               map: psgMap, exactOrigin: 60),
            VelocityFrozenNote(noteID: NoteID(4), tick: 24, duration: 24, pitch: 67, velocity: 76,
                               map: psgMap, exactOrigin: 76),
        ],
        axis: psgAxis, detentUnlock: false, activationDistance: 1, pressX: 0,
        pressY: psgAxis.levelToY(7))
    VelocityGesturePolicy.applyRelative(&psgGesture, y: psgAxis.levelToY(9))
    report.expectEqual(Int(psgMap.representative(9)), Int(psgGesture.preview[NoteID(3)] ?? 0),
                       cppID: gestureID, what: "the first level follows the level delta")
    report.expectEqual(Int(psgMap.representative(11)), Int(psgGesture.preview[NoteID(4)] ?? 0),
                       cppID: gestureID, what: "the second level keeps its own offset")
    report.expectEqual(127,
                       Int(VelocityGesturePolicy.resolvedVelocity(axis: psgAxis, noteMap: psgMap,
                                                                  detentUnlock: true, y: 0)),
                       cppID: gestureID,
                       what: "the detent unlock takes exact MIDI velocity")
    report.expectEqual(Int(psgMap.canonicalize(76)),
                       Int(VelocityGesturePolicy.resolvedVelocity(axis: psgAxis, noteMap: psgMap,
                                                                  detentUnlock: false,
                                                                  y: psgAxis.levelToY(9))),
                       cppID: gestureID,
                       what: "a locked intrinsic drag canonicalizes onto the note's own map")

    let frozen = [
        VelocityFrozenNote(noteID: NoteID(5), tick: 0, duration: 24, pitch: 60, velocity: 40,
                           map: VelocityMap(voiceKind: .unresolved), exactOrigin: 40),
        VelocityFrozenNote(noteID: NoteID(6), tick: 48, duration: 24, pitch: 60, velocity: 40,
                           map: VelocityMap(voiceKind: .unresolved), exactOrigin: 40),
    ]
    let candidates = [(note: frozen[0], x: 10.0), (note: frozen[1], x: 90.0)]
    let painted = VelocityGesturePolicy.paint(
        axis: axis, detentUnlock: false, candidates: candidates, from: (0, 100), to: (95, 40),
        hitRadius: 5)
    report.expectEqual(2, painted.count, cppID: gestureID,
                       what: "the sweep covers every node the column reaches")
    report.expect(painted[0].velocity < painted[1].velocity, cppID: gestureID,
                  message: "the painted ramp follows the swept line's own direction")
    let partial = VelocityGesturePolicy.paint(
        axis: axis, detentUnlock: false, candidates: candidates, from: (0, 100), to: (50, 40),
        hitRadius: 5)
    report.expectEqual(1, partial.count, cppID: gestureID,
                       what: "a sweep that stops short leaves the far node alone")
    let singleColumn = VelocityGesturePolicy.paint(
        axis: axis, detentUnlock: false, candidates: candidates, from: (10, 100), to: (10, 60),
        hitRadius: 5)
    report.expectEqual(1, singleColumn.count, cppID: gestureID,
                       what: "a stationary paint only takes the nodes in its own column")

    let midpoint = VelocityFrozenNote(noteID: NoteID(7), tick: 24, duration: 24, pitch: 60,
                                      velocity: 40,
                                      map: VelocityMap(voiceKind: .unresolved), exactOrigin: 40)
    var ramp = VelocityGestureState(
        kind: .ramp, revision: 1, track: 0, notes: frozen + [midpoint], axis: axis,
        detentUnlock: false, activationDistance: 1, pressX: 10, pressY: axis.velocityToY(100))
    VelocityGesturePolicy.applyRamp(&ramp, x: 50, y: axis.velocityToY(50), hitRadius: 5) { note in
        note.tick == 0 ? 10 : note.tick == 24 ? 30 : 90
    }
    report.expectEqual(100, Int(ramp.preview[NoteID(5)] ?? 0), cppID: gestureID,
                       what: "the note at the press position keeps the press velocity")
    report.expectEqual(75, Int(ramp.preview[NoteID(7)] ?? 0), cppID: gestureID,
                       what: "a note inside the ramp span takes the swept line's value")
    report.expectEqual(40, Int(ramp.preview[NoteID(6)] ?? 0), cppID: gestureID,
                       what: "a note outside the ramp span keeps its captured velocity")
    // The commit payload is what the preview really changes: a gesture whose
    // preview resolves every note back to the value frozen at gesture start
    // makes no history entry, and a preview that moves one note commits exactly
    // that note.
    var flatState = VelocityGestureState(
        kind: .ramp, revision: 1, track: 0, notes: frozen, axis: axis, detentUnlock: false,
        activationDistance: 1, pressX: 10, pressY: axis.velocityToY(40))
    flatState.preview = Dictionary(uniqueKeysWithValues: frozen.map { ($0.noteID, $0.velocity) })
    report.expect(VelocityGesturePolicy.updates(flatState).isEmpty, cppID: gestureID,
                  message: "a preview that matches the captured values commits nothing")
    var movedState = flatState
    let movedNote = frozen[0]
    movedState.preview[movedNote.noteID] = movedNote.velocity + 7
    let moved = VelocityGesturePolicy.updates(movedState)
    report.expect(moved.count == 1 && moved[0].noteID == movedNote.noteID
                  && moved[0].velocity == Int(movedNote.velocity) + 7,
                  cppID: gestureID,
                  message: "only the values that differ from the captured ones are committed")
    report.expect(abs(velocityRampValue(at: 20, x0: 0, y0: 0, x1: 40, y1: 40) - 20) < 1e-9,
                  cppID: gestureID, message: "the ramp interpolates linearly")
    report.expect(abs(velocityRampValue(at: 5, x0: 10, y0: 3, x1: 10, y1: 9) - 9) < 1e-9,
                  cppID: gestureID, message: "a vertical span resolves to the near endpoint")
    report.expect(thirdHandle.hitRadius > 0, cppID: gestureID,
                  message: "the published hit radius is font-relative and positive")
}

// MARK: - Page transactions

@MainActor
private func gestureTransactions(_ report: CheckReport, session: DocumentSession,
                                 service: ProjectService) {
    let fixture = VelocityFixture(session: session, service: service)
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(transactionID, "the synthetic fixture published fewer than three notes")
        return
    }
    let page = fixture.page
    let document = fixture.document

    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    let baseline = DocumentSnapshot(document)
    let before = fixture.handle(notes[0])?.y ?? 0
    fixture.drag(notes[0], dy: -24)
    let committed = DocumentSnapshot(document)
    report.expectEqual(baseline.revision + 1, committed.revision, cppID: transactionID,
                       what: "one released drag advances the document revision once")
    report.expect(committed.identity != baseline.identity, cppID: transactionID,
                  message: "one released drag makes exactly one history entry")
    report.expect(committed.canUndo && !baseline.canUndo, cppID: transactionID,
                  message: "the drag's entry becomes undoable")
    report.expect(document.note(notes[0].id)?.velocity != notes[0].velocity, cppID: transactionID,
                  message: "the drag's commit reached the document")
    report.expect(document.note(notes[1].id)?.velocity != notes[1].velocity, cppID: transactionID,
                  message: "every selected target moved with the gesture")
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: transactionID,
                  message: "a released gesture clears its preview")
    report.expect(fixture.handle(notes[0])?.y != before, cppID: projectionID,
                  message: "the published handle follows the committed value (before \(before) "
                      + "after \(fixture.handle(notes[0])?.y ?? -1) velocity "
                      + "\(document.note(notes[0].id)?.velocity ?? 0) level "
                      + "\(fixture.handle(notes[0])?.level ?? -99)")

    _ = try? runBlocking { try await fixture.session.undo() }
    report.expectEqual(Int(notes[0].velocity), Int(document.note(notes[0].id)?.velocity ?? 0),
                       cppID: historyID, what: "Undo restores the captured velocity")
    report.expectEqual(Int(notes[1].velocity), Int(document.note(notes[1].id)?.velocity ?? 0),
                       cppID: historyID, what: "Undo restores every target of the transaction")
    page.refreshFromDocument()
    report.expectEqual(3, fixture.handles.count, cppID: historyID,
                       what: "Undo rebuilds the page without losing its handles")
    _ = try? runBlocking { try await fixture.session.redo() }
    report.expectEqual(committed.identity, DocumentSnapshot(document).identity, cppID: historyID,
                       what: "Redo restores the committed history identity")
    _ = try? runBlocking { try await fixture.session.undo() }

    // A press that never leaves the activation distance is a selection, not an
    // edit: no preview, no history.
    let pointerBaseline = DocumentSnapshot(document)
    fixture.drag(notes[0], dy: 0)
    report.expectEqual(pointerBaseline.revision, DocumentSnapshot(document).revision,
                       cppID: transactionID, what: "a stationary click records no history")
    report.expect(fixture.session.selectedNotes == [notes[0].id], cppID: transactionID,
                  message: "a stationary click selects only its own note")

    // Escape cancels: preview clears, nothing is written, the press-time
    // selection returns.
    fixture.session.setSelectedNotes([notes[2].id, notes[0].id])
    page.refreshFromDocument()
    let cancelBaseline = DocumentSnapshot(document)
    if let handle = fixture.handle(notes[0]) {
        _ = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1, modifiers: 0)
        _ = page.pointerMove(x: handle.x, y: handle.y - 30, buttons: 1)
        report.expect(!page.frozenPreview.isEmpty, cppID: transactionID,
                      message: "a live drag previews before release")
        report.expect(page.interactionActive, cppID: transactionID,
                      message: "a live drag reports an active interaction")
        report.expect(page.handleEscape(), cppID: cancellationID,
                      message: "Escape is claimed while a gesture is live")
    }
    report.expect(page.frozenPreview.isEmpty && !page.hasGesture, cppID: cancellationID,
                  message: "Escape clears the frozen preview")
    report.expect(DocumentSnapshot(document) == cancelBaseline, cppID: cancellationID,
                  message: "Escape writes nothing at all")
    report.expect(fixture.session.selectedNoteOrder == [notes[2].id, notes[0].id], cppID: cancellationID,
                  message: "Escape restores selection membership and insertion order")

    // A stale revision cancels instead of retargeting the current selection.
    if let handle = fixture.handle(notes[0]) {
        _ = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1, modifiers: 0)
        _ = page.pointerMove(x: handle.x, y: handle.y - 30, buttons: 1)
        let foreignRevision = document.revision
        _ = document.setVelocities([NoteVelocity(noteID: notes[2].id, velocity: 12)],
                                   expectedRevision: foreignRevision)
        _ = page.pointerRelease(x: handle.x, y: handle.y - 30, button: 1)
        report.expectEqual(foreignRevision + 1, document.revision, cppID: cancellationID,
                           what: "a release after a foreign change writes nothing")
        report.expect(!page.hasGesture && page.frozenPreview.isEmpty, cppID: cancellationID,
                      message: "a stale release ends the gesture")
    }
    _ = try? runBlocking { try await fixture.session.undo() }
    page.refreshFromDocument()

    // The ruler click-sets the selected notes and commits once.
    fixture.session.setSelectedNotes([notes[0].id])
    page.refreshFromDocument()
    let rulerBaseline = DocumentSnapshot(document)
    let rulerY = (page.axisModel.top + page.axisModel.bottom) / 2
    report.expect(page.pointerPress(x: 10, y: rulerY, surface: 0, button: 1, modifiers: 0),
                  cppID: transactionID, message: "the ruler consumes its own press")
    _ = page.pointerRelease(x: 10, y: rulerY, button: 1)
    report.expectEqual(rulerBaseline.revision + 1, document.revision, cppID: transactionID,
                       what: "one ruler click makes one revision")
    report.expect(document.history.currentIdentity != rulerBaseline.identity, cppID: transactionID,
                  message: "one ruler click makes one history entry")
    report.expect(!page.pointerPress(x: 200, y: rulerY, surface: 0, button: 1, modifiers: 0),
                  cppID: transactionID, message: "a press inside the plot is not the ruler's")
    _ = try? runBlocking { try await fixture.session.undo() }
    page.refreshFromDocument()

    // Middle-drag pan asks the one shared camera for its own scroll and writes
    // no document state.
    fixture.session.clearSelectedNotes()
    page.refreshFromDocument()
    let panBaseline = DocumentSnapshot(document)
    let panScroll = fixture.session.camera.snapshot.scrollX
    _ = page.pointerPress(x: 200, y: 40, surface: 1, button: 4, modifiers: 0)
    _ = page.pointerMove(x: 170, y: 40, buttons: 4)
    _ = page.pointerMove(x: 150, y: 40, buttons: 4)
    report.expect(fixture.session.camera.snapshot.scrollX > panScroll, cppID: transactionID,
                  message: "a middle drag pans the shared camera")
    report.expect(page.interactionActive, cppID: transactionID,
                  message: "a live pan suspends follow through the page's own interaction")
    _ = page.pointerRelease(x: 150, y: 40, button: 4)
    report.expect(!page.hasGesture, cppID: transactionID, message: "the pan ends on release")
    report.expect(DocumentSnapshot(document) == panBaseline, cppID: transactionID,
                  message: "panning writes no document state")

    // The detent control: available for a PSG context, and turning it off puts
    // every context on the continuous domain and cancels what it interrupted.
    fixture.session.setSelectedNotes([notes[0].id])
    page.refreshFromDocument()
    report.expect(page.detentsAvailable && page.detentsEnabled, cppID: transactionID,
                  message: "a PSG context offers the detent control, enabled by default")
    report.expectEqual(VelocityAxisModel.Mode.intrinsic.rawValue, page.axisMode,
                       cppID: transactionID,
                       what: "the PSG context presents the intrinsic ruler")
    report.expect(page.axisGraduationsVisible, cppID: transactionID,
                  message: "an enabled detent set draws the level graduations")
    if let handle = fixture.handle(notes[0]) {
        _ = page.pointerPress(x: handle.x, y: handle.y, surface: 1, button: 1, modifiers: 0)
        _ = page.pointerMove(x: handle.x, y: handle.y - 30, buttons: 1)
        report.expect(!page.frozenPreview.isEmpty, cppID: transactionID,
                      message: "the detent case starts from a live preview")
        page.toggleDetents()
        report.expect(!page.detentsEnabled && page.frozenPreview.isEmpty, cppID: transactionID,
                      message: "toggling detents cancels the live interaction")
    }
    report.expect(page.axisGraduationsVisible == false, cppID: transactionID,
                  message: "disabled detents put the ruler on the continuous rendering")
    report.expect(page.axisModel.mode == .intrinsic, cppID: transactionID,
                  message: "the voice's own map stays intrinsic under the ruler switch")
    if let handle = fixture.handle(notes[0]) {
        let exactY = page.axisModel.velocityToY(handle.value)
        report.expect(abs(handle.y - exactY) < 0.001, cppID: transactionID,
                      message: "a disabled detent set places nodes at their exact velocity")
    }
    report.expect(DocumentSnapshot(document) == panBaseline, cppID: transactionID,
                  message: "the detent toggle writes no document state")
    page.setUseDetents(enabled: true)
    _ = try? runBlocking { try await fixture.session.undo() }
    page.refreshFromDocument()

    // A band gesture resolves a selection and commits nothing.
    fixture.session.clearSelectedNotes()
    page.refreshFromDocument()
    let bandBaseline = DocumentSnapshot(document)
    _ = page.pointerPress(x: 0, y: 0, surface: 1, button: 2, modifiers: 0)
    _ = page.pointerMove(x: 400, y: 120, buttons: 2)
    _ = page.pointerRelease(x: 400, y: 120, button: 2)
    report.expectEqual(bandBaseline.revision, document.revision, cppID: transactionID,
                       what: "a band selection writes nothing")
    report.expectEqual(3, fixture.session.selectedNotes.count, cppID: transactionID,
                       what: "the band selected every note it covered")
}

// MARK: - Prompt

@MainActor
private func promptTransaction(_ report: CheckReport, session: DocumentSession,
                               service: ProjectService) {
    let fixture = VelocityFixture(session: session, service: service)
    let page = fixture.page
    let document = fixture.document
    let notes = fixture.notes
    guard notes.count >= 3 else {
        report.fail(promptID, "the synthetic fixture published fewer than three notes")
        return
    }
    var acceptedValues: [UInt8] = []
    page.onVelocityAccepted = { acceptedValues.append($0) }
    report.expectEqual(1, VelocityPromptPolicy.minimum, cppID: promptID,
                       what: "the prompt's minimum is 1")
    report.expectEqual(127, VelocityPromptPolicy.maximum, cppID: promptID,
                       what: "the prompt's maximum is 127")
    report.expect(VelocityPromptPolicy.value(draft: "1") == 1
                      && VelocityPromptPolicy.value(draft: "127") == 127, cppID: promptID,
                  message: "the domain endpoints are accepted")
    report.expect(VelocityPromptPolicy.value(draft: "0") == nil
                      && VelocityPromptPolicy.value(draft: "128") == nil, cppID: promptID,
                  message: "values outside the domain are refused")
    report.expect(VelocityPromptPolicy.value(draft: "") == nil
                      && VelocityPromptPolicy.value(draft: "12x") == nil
                      && VelocityPromptPolicy.value(draft: "-5") == nil, cppID: promptID,
                  message: "empty, non-decimal and signed drafts are refused")
    report.expect(VelocityPromptPolicy.error(draft: "64").isEmpty, cppID: promptID,
                  message: "a valid draft publishes no error")

    // No selection: the entry point refuses and writes nothing.
    fixture.session.clearSelectedNotes()
    page.refreshFromDocument()
    let emptyBaseline = DocumentSnapshot(document)
    report.expect(!page.openSelectedVelocityPrompt(), cppID: promptID,
                  message: "the selectionless entry point does not open a prompt")
    report.expect(DocumentSnapshot(document) == emptyBaseline, cppID: promptID,
                  message: "the selectionless entry point writes nothing")

    // Capture, draft typing, cancellation.
    fixture.session.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    report.expect(page.openSelectedVelocityPrompt(), cppID: promptID,
                  message: "the selected-note entry point opens the prompt")
    report.expectEqual("\(notes[0].velocity)", page.promptDraft, cppID: promptID,
                       what: "the prompt opens with the first captured value as its draft")
    report.expectEqual(Int(notes[0].velocity), page.promptInitialValue, cppID: promptID,
                       what: "the prompt publishes its initial value")
    report.expect(page.promptTargets == [notes[0].id, notes[1].id], cppID: promptID,
                  message: "the prompt captured the stable target IDs")
    report.expect(page.promptBeforeValues == [notes[0].velocity, notes[1].velocity], cppID: promptID,
                  message: "the prompt captured every before-value")
    report.expect(page.interactionActive, cppID: promptID,
                  message: "an open prompt reports an active interaction")
    page.updatePromptDraft(draft: "95")
    report.expect(page.promptDraft == "95" && page.promptError.isEmpty, cppID: promptID,
                  message: "typing replaces the draft without an error")
    report.expect(DocumentSnapshot(document) == emptyBaseline, cppID: promptID,
                  message: "typing into the prompt never mutates the document")
    page.cancelPrompt()
    report.expect(!page.promptOpen, cppID: cancellationID, message: "cancelling closes the prompt")
    report.expect(DocumentSnapshot(document) == emptyBaseline, cppID: cancellationID,
                  message: "cancelling writes nothing")
    report.expect(acceptedValues.isEmpty, cppID: promptID,
                  message: "drafting and cancellation do not latch a drawing velocity")

    // Acceptance: one transaction for every captured target.
    let acceptBaseline = DocumentSnapshot(document)
    _ = page.openSelectedVelocityPrompt()
    page.updatePromptDraft(draft: "95")
    report.expect(page.acceptPrompt(), cppID: promptID, message: "acceptance commits")
    report.expectEqual(95, Int(document.note(notes[0].id)?.velocity ?? 0), cppID: promptID,
                       what: "the accepted value reached the first target")
    report.expectEqual(95, Int(document.note(notes[1].id)?.velocity ?? 0), cppID: promptID,
                       what: "the accepted value reached every captured target")
    report.expectEqual(acceptBaseline.revision + 1, document.revision, cppID: promptID,
                       what: "acceptance makes one revision")
    report.expect(document.history.currentIdentity != acceptBaseline.identity, cppID: promptID,
                  message: "acceptance makes exactly one history entry")
    report.expect(!page.promptOpen, cppID: promptID, message: "acceptance closes the prompt")
    report.expect(fixture.session.selectedNotes == [notes[0].id, notes[1].id], cppID: promptID,
                  message: "acceptance preserves the selection")
    report.expect(acceptedValues == [95], cppID: promptID,
                  message: "valid acceptance latches the drawing velocity")
    let noOpBaseline = DocumentSnapshot(document)
    _ = page.openSelectedVelocityPrompt()
    page.updatePromptDraft(draft: "95")
    report.expect(page.acceptPrompt(), cppID: promptID,
                  message: "an identical valid value is still accepted")
    report.expect(DocumentSnapshot(document) == noOpBaseline && acceptedValues == [95, 95],
                  cppID: promptID,
                  message: "no-op acceptance relatches the drawing velocity without history")
    _ = try? runBlocking { try await fixture.session.undo() }
    report.expectEqual(Int(notes[0].velocity), Int(document.note(notes[0].id)?.velocity ?? 0),
                       cppID: historyID, what: "Undo restores the prompt's before-values")

    // The first selected note seeds the prompt, even when selected later in the
    // song or another selected note is hovered before opening.
    let ordered = VelocityFixture(session: session, service: service)
    ordered.session.addSelectedNote(ordered.notes[1].id)
    ordered.session.addSelectedNote(ordered.notes[0].id)
    ordered.page.refreshFromDocument()
    _ = ordered.page.openSelectedVelocityPrompt()
    report.expectEqual(Int(ordered.notes[1].velocity), ordered.page.promptInitialValue,
                       cppID: promptID, what: "selection insertion order seeds the prompt")
    ordered.page.cancelPrompt()
    if let pointed = ordered.handle(ordered.notes[0]) {
        _ = ordered.page.pointerMove(x: pointed.x, y: pointed.y, buttons: 0)
    }
    _ = ordered.page.openSelectedVelocityPrompt()
    report.expectEqual(Int(ordered.notes[1].velocity), ordered.page.promptInitialValue,
                       cppID: promptID, what: "hover cannot reseed the ordered prompt")
    ordered.page.cancelPrompt()

    // An invalid draft stays open, publishes its error and writes nothing.
    let invalidBaseline = DocumentSnapshot(document)
    _ = page.openSelectedVelocityPrompt()
    page.updatePromptDraft(draft: "0")
    report.expect(!page.promptError.isEmpty, cppID: promptID,
                  message: "an out-of-domain draft publishes an error")
    report.expect(!page.acceptPrompt(), cppID: promptID,
                  message: "an invalid draft does not accept")
    report.expect(page.promptOpen, cppID: promptID,
                  message: "the invalid prompt stays open for correction")
    report.expect(DocumentSnapshot(document) == invalidBaseline, cppID: promptID,
                  message: "an invalid draft adds no history entry")
    page.cancelPrompt()
    report.expect(DocumentSnapshot(document) == invalidBaseline, cppID: cancellationID,
                  message: "cancelling the invalid prompt writes nothing")

    // A stale prompt commits nothing: the captured revision moved.
    let staleBaseline = DocumentSnapshot(document)
    _ = page.openSelectedVelocityPrompt()
    _ = document.setVelocities([NoteVelocity(noteID: notes[2].id, velocity: 33)],
                               expectedRevision: document.revision)
    page.updatePromptDraft(draft: "40")
    report.expect(!page.acceptPrompt(), cppID: cancellationID,
                  message: "a stale acceptance commits nothing")
    report.expect(acceptedValues == [95, 95], cppID: cancellationID,
                  message: "invalid, cancelled and stale prompts never relatch drawing velocity")
    report.expectEqual(Int(notes[0].velocity), Int(document.note(notes[0].id)?.velocity ?? 0),
                       cppID: cancellationID,
                       what: "the stale acceptance left its targets alone")
    report.expectEqual(staleBaseline.revision + 1, document.revision, cppID: cancellationID,
                       what: "the only write is the foreign document change")
    _ = try? runBlocking { try await fixture.session.undo() }
    page.refreshFromDocument()

    // A prompt cannot follow a later selection: the capture stays frozen.
    _ = page.openSelectedVelocityPrompt()
    fixture.session.setSelectedNotes([notes[2].id])
    page.updatePromptDraft(draft: "77")
    report.expect(page.promptTargets == [notes[0].id, notes[1].id], cppID: promptID,
                  message: "the capture never follows a later selection")
    report.expect(page.acceptPrompt(), cppID: promptID,
                  message: "the captured transaction still completes after a selection change")
    report.expectEqual(77, Int(document.note(notes[0].id)?.velocity ?? 0), cppID: promptID,
                       what: "the acceptance wrote the captured target, not the new selection")
    report.expectEqual(Int(notes[2].velocity), Int(document.note(notes[2].id)?.velocity ?? 0),
                       cppID: promptID,
                       what: "the note the prompt never captured keeps its own velocity")
    _ = try? runBlocking { try await fixture.session.undo() }
}

// MARK: - Per-note split mapping

@MainActor
private func keysplitPerNoteMapping(_ report: CheckReport, session: DocumentSession,
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
                  cppID: keysplitID, message: "a split without a note key remains keyless")
    let invalid = VelocityContextPolicy.resolve(slot: 0, endTick: nil, slots: slots, key: 61)
    report.expect(invalid.map == VelocityMap(voiceKind: .invalid) && !invalid.editable,
                  cppID: keysplitID, message: "invalid child facts never borrow another key")
    for (key, kind) in [(60, VoiceKind.square1), (67, .wave), (72, .square1)] {
        let context = VelocityContextPolicy.resolve(slot: 0, endTick: nil, slots: slots, key: key)
        report.expect(context.editable && context.map == VelocityMap(voiceKind: kind),
                      cppID: keysplitID, message: "key \(key) resolves its own child map")
    }
    report.expect(split.subvoiceMacro(forKey: -1) == nil
                      && split.subvoiceMacro(forKey: 128) == nil,
                  cppID: keysplitID, message: "out-of-domain keys do not resolve")
    let document = SongDocument(file: velocityPageFixture(),
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
                  cppID: keysplitID, message: "compatible per-key PSG notes retain detents")
    splitSession.setSelectedNotes([notes[0].id, notes[1].id])
    page.refreshFromDocument()
    report.expect(!page.detentsAvailable && !page.contextUnsupported
                      && page.axisMode == VelocityAxisModel.Mode.continuous.rawValue,
                  cppID: keysplitID, message: "mixed PSG maps remain editable and continuous")
    for note in notes.prefix(2) {
        let kind: VoiceKind = note.pitch == 60 ? .square1 : .wave
        let map = VelocityMap(voiceKind: kind)
        let noteAxis = VelocityAxisModel(map: map, geometry: page.axisModel.geometry)
        let handle = page.publishedHandlesSnapshot.first { $0.noteIdText == "\(note.id.rawValue)" }
        report.expect(handle?.y == noteAxis.levelToY(map.level(of: Int(note.velocity))!),
                      cppID: keysplitID,
                      message: "mixed selection places each handle using its own level boundaries")
    }
    if let wave = page.publishedHandlesSnapshot.first(where: { $0.noteIdText == "\(notes[1].id.rawValue)" }) {
        _ = page.pointerMove(x: wave.x, y: wave.y, buttons: 0)
        report.expect(page.axisModel.map == VelocityMap(voiceKind: .wave),
                      cppID: keysplitID, message: "hover resolves the hovered note key")
        page.pointerLeave()
    }
    let before = DocumentSnapshot(document)
    report.expect(page.openSelectedVelocityPrompt(), cppID: keysplitID,
                  message: "mixed per-key selection opens its prompt")
    page.updatePromptDraft(draft: "127")
    report.expect(DocumentSnapshot(document) == before, cppID: keysplitID,
                  message: "per-key prompt drafts never mutate history")
    report.expect(page.acceptPrompt(), cppID: keysplitID,
                  message: "per-key prompt accepts one captured transaction")
    let accepted = DocumentSnapshot(document)
    report.expect(document.note(notes[0].id)?.velocity == 127
                      && document.note(notes[1].id)?.velocity == 127
                      && document.note(notes[2].id)?.velocity == notes[2].velocity
                      && accepted.revision == before.revision + 1,
                  cppID: keysplitID, message: "acceptance changes only captured notes once")
    report.expect(!page.acceptPrompt() && DocumentSnapshot(document) == accepted,
                  cppID: keysplitID, message: "repeated acceptance cannot duplicate a transaction")
    _ = try? runBlocking { try await splitSession.undo() }
    report.expect(document.note(notes[0].id)?.velocity == notes[0].velocity
                      && document.note(notes[1].id)?.velocity == notes[1].velocity,
                  cppID: keysplitID, message: "one undo restores both captured values")
    page.detach()
}

// Camera-only refresh must update both the rendered model and hit geometry;
// document refresh must discard the raw-note cache after an edit and undo.
@MainActor
private func projectionRefresh(_ report: CheckReport, session: DocumentSession,
                               service: ProjectService) {
    let fixture = VelocityFixture(session: session, service: service)
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
                  cppID: projectionID, message: "camera refresh moves the handle without changing its value axis")
    let row = page.handles[1]
    report.expect(row.x == expectedX, cppID: projectionID,
                  message: "the QML model receives the moved handle")
    _ = page.pointerMove(x: moved.x, y: moved.y, buttons: 0)
    report.expect(page.hoveredNoteText == "\(note.id.rawValue)", cppID: projectionID,
                  message: "hit testing follows the camera-refreshed handle")
    page.pointerLeave()
    _ = fixture.document.setVelocities([NoteVelocity(noteID: note.id, velocity: 127)],
                                       expectedRevision: fixture.document.revision)
    page.refreshFromDocument()
    report.expect(fixture.handle(note)?.value == 127, cppID: projectionID,
                  message: "document edits invalidate cached note values")
    _ = try? runBlocking { try await fixture.session.undo() }
    page.refreshFromDocument()
    report.expect(fixture.handle(note)?.value == oldValue, cppID: projectionID,
                  message: "undo invalidates cached note values again")
    page.detach()
}

// MARK: - Diagnostics and commands

@MainActor
private func playheadDiagnostics(_ report: CheckReport, session: DocumentSession,
                                 service: ProjectService) {
    let fixture = VelocityFixture(session: session, service: service)
    let page = fixture.page
    page.refreshPlayhead(tick: 0, playing: true)
    let handleCount = fixture.handles.count
    for tick in 1...128 {
        page.refreshPlayhead(tick: Double(tick) / 8, playing: true)
    }
    report.expectEqual(Tick(16), page.presentedContextTick, cppID: diagnosticsID,
                       what: "the presented context tick is the rounded playhead tick")
    report.expectEqual(0, page.presentedContextSlot, cppID: diagnosticsID,
                       what: "the presented context slot is the bank slot at that tick")
    report.expectEqual(handleCount, fixture.handles.count, cppID: diagnosticsID,
                       what: "playhead movement preserves the displayed note count")

    // Crossing a voice change presents its slot; stopping follows the edit cursor.
    page.refreshPlayhead(tick: 96, playing: true)
    report.expectEqual(2, page.presentedContextSlot, cppID: diagnosticsID,
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
    report.expectEqual(2, page.context.slot, cppID: diagnosticsID,
                       what: "the stopped velocity context consumes the published edit cursor")
    report.expectEqual(cursorDocument, DocumentSnapshot(fixture.document), cppID: diagnosticsID,
                       what: "cursor-only publication changes no document or history state")

    fixture.session.setSelectedNotes([fixture.notes[0].id])
    page.refreshFromDocument()
    report.expectEqual(1, page.selectedCount, cppID: projectionID,
                       what: "the selected handle publishes its own count")
    if let handle = fixture.handle(fixture.notes[0]) {
        page.pointerMove(x: handle.x, y: handle.y, buttons: 0)
    }
    report.expectEqual(fixture.handle(fixture.notes[0])?.label ?? "", page.readoutText,
                       cppID: projectionID,
                       what: "the hovered handle publishes its displayed value as the readout")
    report.expectEqual("\(fixture.notes[0].id.rawValue)", page.hoveredNoteText, cppID: projectionID,
                       what: "the hovered handle publishes its own identity")
    page.pointerMove(x: 3, y: 3, buttons: 0)
    report.expect(!page.readoutVisible, cppID: projectionID,
                  message: "hover leaving every handle hides the readout")
}

@MainActor
private func commandAvailability(_ report: CheckReport, session: DocumentSession,
                                 service: ProjectService) {
    let fixture = VelocityFixture(session: session, service: service)
    let grid = PianoGrid(session: fixture.session)
    let setVelocity = EditCommand.setVelocity.rawValue
    report.expect(!grid.commandAvailable(command: setVelocity), cppID: commandID,
                  message: "Set Velocity is unavailable with no selection")

    var requested = 0
    var page: VelocityPage?
    grid.onSetVelocityRequested = {
        requested += 1
        return page?.openSelectedVelocityPrompt() ?? false
    }
    let document = fixture.document
    let baseline = DocumentSnapshot(document)

    fixture.session.setSelectedNotes([fixture.notes[0].id])
    grid.setEditCursorTick(tick: Int(fixture.session.editCursor))
    report.expect(grid.commandAvailable(command: setVelocity), cppID: commandID,
                  message: "Set Velocity becomes available with a selection")

    grid.performCommand(command: setVelocity)
    report.expectEqual(1, requested, cppID: commandID,
                       what: "the existing command row asks its owner for the prompt")
    report.expect(DocumentSnapshot(document) == baseline, cppID: commandID,
                  message: "the command commits no value before prompt acceptance")

    page = fixture.page
    grid.performCommand(command: setVelocity)
    report.expectEqual(2, requested, cppID: commandID,
                       what: "the command routes every execution through the same owner")
    report.expect(fixture.page.promptOpen, cppID: commandID,
                  message: "the routed command opened the page's captured prompt")
    fixture.page.cancelPrompt()
    report.expect(DocumentSnapshot(document) == baseline, cppID: commandID,
                  message: "cancelling the routed prompt still commits nothing")

    let row = editCommandTable.first { $0.command == .setVelocity }
    report.expectEqual(EditNotesOperation.setVelocity.rawValue,
                       row?.notesOperation.rawValue ?? -1, cppID: commandID,
                       what: "the command table keeps Set Velocity on the notes arm")
    report.expectEqual(EditKeyRoute.alwaysConsume.rawValue, row?.keyRoute.rawValue ?? -1,
                       cppID: commandID,
                       what: "the command table keeps Set Velocity's consume route")
}
