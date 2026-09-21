import Foundation
import PorydawApp
import PorydawCore

// Direct coverage for the Voice Changes page. The pure layer (labels, context
// resolution, hit testing and occurrence identity) is driven with synthetic
// values; the page owner is driven against a real `DocumentSession` over the
// suite's real bank slots, so every transaction claim is a real
// document-history claim.
//
// Translated legacy intent:
//
// - `drawerpresentation/VoiceChangesTest::voiceSurfaceAndPaintLifecycle`: the
//   markers of `DOC_CC_VOICE` at their ticks with their labels, the held program
//   spans, the right-aligned context readout, the marker hit radius, and the
//   insert → one revision plus one history entry → undo restores the markers;
// - `::voiceHoverLifecycle`: a background hover publishes the snapped tick's
//   slot label while the marker texts stay unchanged, and a marker hover
//   publishes its own tick with no label;
// - `::voiceRefreshLifecycle`: a track switch re-derives the whole projection,
//   and the labels always come from the current bank's slots;
// - `::voicePickerTransactions`: the picker arm this suite can reproduce —
//   double-click capture, filtering, cancel/escape writing nothing, the accepted
//   value replacement at a marker tick, the insertion at an empty tick, the
//   same-value no-op, and the insert → undo → redo round trip;
// - `::voiceMarkerDragTransactions`: a press-and-release below the activation
//   distance commits nothing, an activated drag commits exactly one move at the
//   tick it previewed, and undo/redo follow the document;
// - `::voiceCameraTransactions` and `drawerpresentation/VoiceMenuTest`: a camera
//   scroll after a menu opens neither drifts the captured target nor closes it,
//   and a rewrite between the open and the activation rejects the pick while the
//   rewrite itself stands (including the outside-right dismissal that carries no
//   retarget);
// - `::voiceContextMenuTransactions`: the typed rows per target — Change voice
//   and Delete for a marker, Insert voice change for the empty lane — driven
//   through the page's own dispatch;
// - `::textRetentionAndPlayheadPerformance`: shared-playhead movement inside one
//   voice span rebuilds no static content, while crossing a span updates the
//   readout once.
//
// Audition checks observe the typed owner callback and document history; native
// audio integration is verified separately on the production workspace.

private let projectionID = "swiftcore/VoiceChangesPage::markerProjection"
private let labelID = "swiftcore/VoiceChangesPage::slotLabelsAndBlankSlots"
private let contextID = "swiftcore/VoiceChangesPage::currentVoiceContext"
private let identityID = "swiftcore/VoiceChangesPage::occurrenceIdentity"
private let insertionID = "swiftcore/VoiceChangesPage::pickerInsertion"
private let replacementID = "swiftcore/VoiceChangesPage::pickerValueReplacement"
private let moveID = "swiftcore/VoiceChangesPage::markerDragTransactions"
private let menuID = "swiftcore/VoiceChangesPage::contextMenuTransactions"
private let keyboardID = "swiftcore/VoiceChangesPage::pickerKeyboardPolicy"
private let cancellationID = "swiftcore/VoiceChangesPage::cancellationPaths"
private let historyID = "swiftcore/VoiceChangesPage::undoRedoRefresh"
private let diagnosticsID = "swiftcore/VoiceChangesPage::playheadDiagnostics"
private let auditionID = "swiftcore/VoiceChangesPage::auditionCapability"
private let fineSnapID = "swiftcore/VoiceChangesPage::altFineClockLattice"
private let collisionID = "swiftcore/VoiceChangesPage::collisionAndBlankSlotCommit"

// MARK: - Fixture

/// A synthetic song whose primary track opens on `programs[0]` and changes voice
/// at ticks 48 and 120, plus a second track for the track-switch cases. Every
/// program names a real editable slot of the suite's bank, so the labels the
/// page publishes are the project's own.
private func voiceChangesPageFixture(programs: [Int], division: UInt16 = 24) -> MidiFile {
    func clamped(_ value: Int) -> UInt8 { UInt8(min(max(value, 0), 127)) }
    let conductor: [MidiEvent] = [
        .meta(tick: 0, type: 0x51, data: [0x07, 0xA1, 0x20]),
    ]
    let primary: [MidiEvent] = [
        .channel(tick: 0, status: 0xC0, data0: clamped(programs[0])),
        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 60),
        .channel(tick: 48, status: 0xC0, data0: clamped(programs[1])),
        .channel(tick: 96, status: 0x90, data0: 64, data1: 90),
        .channel(tick: 120, status: 0x80, data0: 64),
        .channel(tick: 120, status: 0xC0, data0: clamped(programs[2])),
    ]
    let secondary: [MidiEvent] = [
        .channel(tick: 0, status: 0xC0, data0: clamped(programs[2])),
        .channel(tick: 0, status: 0x90, data0: 67, data1: 80),
        .channel(tick: 48, status: 0x80, data0: 67),
    ]
    return MidiFile(division: division, chunks: [
        MidiChunk(events: conductor, endTick: 192),
        MidiChunk(events: primary, endTick: 192),
        MidiChunk(events: secondary, endTick: 192),
    ])
}

/// The document facts one transaction claim compares against.
@MainActor
private struct VoiceDocumentSnapshot: Equatable {
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

/// The page attached to its own synthetic session over the suite's service and
/// bank, plus the composition facts the page needs to project at all.
@MainActor
private struct VoiceChangesFixture {
    let session: DocumentSession
    let page: VoiceChangesPage
    let document: SongDocument

    init(suite: DocumentSession, service: ProjectService, programs: [Int],
         division: UInt16 = 24, baseFontPx: Double = 13) {
        let document = SongDocument(file: voiceChangesPageFixture(programs: programs,
                                                                  division: division),
                                    config: suite.document.state.config,
                                    source: suite.document.source,
                                    trackBudget: suite.document.trackBudget)
        let session = DocumentSession(document: document, service: service,
                                      lease: suite.bankLease, slots: suite.bankSlots,
                                      dirty: false, loadName: suite.bankLoadName,
                                      sampleRate: 48_000)
        session.selectedTrack = 0
        session.clearSelectedNotes()
        session.editCursor = 0
        self.session = session
        self.document = document
        page = VoiceChangesPage(baseFontPx: baseFontPx)
        page.attach(session: session, palette: GridPalette())
        page.configureBody(width: 400, height: 46, gutter: 56, devicePixelRatio: 1,
                           baseFontPx: baseFontPx, dragDistance: 10)
        // Mirror the workspace's domain routing: cursor publication updates only
        // the stopped readout; document-derived domains rebuild content.
        session.onChange = { [weak page] change in
            let content: SessionChangeDomains = [.document, .selection, .bank]
            if !change.domains.intersection(content).isEmpty {
                page?.refreshFromDocument()
            } else if change.domains.contains(.cursor) {
                page?.refreshEditCursor()
            }
        }
        session.onCameraChange = { [weak page] _ in page?.refreshCamera() }
    }

    var snapshot: VoiceDocumentSnapshot { VoiceDocumentSnapshot(document) }

    func lanePoints() -> [LanePoint] { document.lanePoints(track: 0, lane: .voice) }

    /// Plot-local x of one tick through the shared camera, which is the space
    /// the page's own input arrives in.
    func markerX(_ tick: Tick) -> Double {
        session.camera.displayX(tick: Double(tick), origin: 0, dpr: 1)
    }

    func marker(at tick: Tick) -> VoiceMarkerHandle? {
        page.publishedMarkers.first { Tick($0.tick) == tick }
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
        if Date() > deadline { throw VoiceCheckTimeout.timeout }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    return try outcome!.get()
}

private enum VoiceCheckTimeout: Error {
    case timeout
}

// MARK: - Suite entry

@MainActor
internal func runVoiceChangesPageChecks(_ report: CheckReport, session: DocumentSession,
                                        service: ProjectService) {
    let editable = session.bankSlots.indices.filter { session.bankSlots[$0].voice != nil }
    guard editable.count >= 3 else {
        report.fail(projectionID,
                    "the staged bank exposes \(editable.count) parsed slots; the Voice "
                    + "Changes cases need three")
        return
    }
    let programs = [editable[0], editable[1], editable[2]]
    markerProjection(report, suite: session, service: service, programs: programs)
    slotLabels(report, session: session, service: service, programs: programs)
    currentVoiceContext(report, suite: session, service: service, programs: programs)
    occurrenceIdentity(report, suite: session, service: service, programs: programs)
    pickerInsertion(report, suite: session, service: service, programs: programs)
    pickerValueReplacement(report, suite: session, service: service, programs: programs)
    markerDragTransactions(report, suite: session, service: service, programs: programs)
    contextMenuTransactions(report, suite: session, service: service, programs: programs)
    pickerKeyboardPolicy(report, suite: session, service: service, programs: programs)
    cancellationPaths(report, suite: session, service: service, programs: programs)
    undoRedoRefresh(report, suite: session, service: service, programs: programs)
    playheadDiagnostics(report, suite: session, service: service, programs: programs)
    altFineClockLattice(report, suite: session, service: service, programs: programs)
    collisionDragOutcome(report, suite: session, service: service, programs: programs)
    blankSlotCommit(report, suite: session, service: service, programs: programs)
    auditionCapability(report, suite: session, service: service, programs: programs)
}

// MARK: - Projection

@MainActor
private func markerProjection(_ report: CheckReport, suite: DocumentSession,
                              service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: projectionID,
                       what: "every DOC_CC_VOICE event of the primary track publishes a marker")
    report.expectEqual(3, page.publishedMarkers.count, cppID: projectionID,
                       what: "the projection keeps one marker per change")
    report.expect(page.publishedMarkers.allSatisfy { !$0.identity.isEmpty }, cppID: projectionID,
                  message: "every marker carries its occurrence identity")
    report.expectEqual(3, Set(page.markerIdentities).count, cppID: projectionID,
                       what: "the identities are distinct per occurrence")

    let ticks: [Tick] = [0, 48, 120]
    for (index, tick) in ticks.enumerated() {
        let marker = page.publishedMarkers[index]
        let expectedProgram = programs[index]
        report.expectEqual(fixture.markerX(tick), marker.x, cppID: projectionID,
                           what: "marker \(tick) draws at the shared camera's projection")
        report.expect(marker.label.hasPrefix(String(format: "%03d", expectedProgram)),
                      cppID: projectionID,
                      message: "marker \(tick) labels its own program slot "
                          + "(\"\(marker.label)\")")
        report.expect(marker.lineBottom > marker.lineTop, cppID: projectionID,
                      message: "marker \(tick) draws a vertical rule")
        report.expect(marker.lineWidth > 0, cppID: projectionID,
                      message: "marker \(tick) draws a rule of a real width")
        report.expect((marker.labelRect["width"] as? Double ?? 0) > 0, cppID: projectionID,
                      message: "marker \(tick) publishes a label box with a real width")
        report.expect(!marker.offscreen, cppID: projectionID,
                      message: "marker \(tick) is inside the visible plot")
    }
    // The span walk closes each section at the next change and runs the last one
    // to the timeline's end, so the tail exists only when the song extends past
    // the final change.
    let tail = fixture.session.timeline.lengthTicks > 120 ? 1 : 0
    report.expectEqual(2 + tail, page.heldSpans.count, cppID: projectionID,
                       what: "each program section publishes one held span "
                           + "(timeline ends at \(fixture.session.timeline.lengthTicks))")
    report.expect(page.trackAvailable, cppID: projectionID,
                  message: "a resolved track publishes the band's tracking facts")
    report.expect(!page.readoutText.isEmpty, cppID: projectionID,
                  message: "the context readout names the program at the context tick")
    report.expect(page.readoutVisible, cppID: projectionID,
                  message: "the readout is published for a presented track")

    // The hit radius is the legacy font-relative one: a press inside it takes
    // that marker, a press beyond it takes none.
    let hitX = fixture.markerX(48)
    _ = page.pointerPress(x: hitX + 9, y: 10, surface: 1, button: 1, modifiers: 0)
    report.expectEqual(48, page.frozenOccurrence?.tick, cppID: projectionID,
                       what: "a press inside the marker hit radius takes that marker")
    page.cancelSectionInteraction()
    _ = page.pointerPress(x: hitX + 12, y: 10, surface: 1, button: 1, modifiers: 0)
    report.expect(!page.hasGesture, cppID: projectionID,
                  message: "a press beyond the marker hit radius starts no marker gesture")
    _ = page.pointerRelease(x: hitX + 12, y: 10, button: 1)

    // A hover over the empty lane publishes the snapped tick's slot label and
    // leaves the marker texts alone.
    let before = page.publishedMarkers.map(\.label)
    _ = page.pointerMove(x: fixture.markerX(96), y: 10, buttons: 0)
    report.expect(page.hoverVisible, cppID: projectionID,
                  message: "a background hover publishes its slot label")
    report.expect(page.hoverText.hasPrefix("→ "), cppID: projectionID,
                  message: "the hover label keeps the legacy arrow prefix")
    report.expectEqual(before, page.publishedMarkers.map(\.label), cppID: projectionID,
                       what: "a hover repaints no marker label")

    // A hover directly over a marker publishes its tick and no label.
    _ = page.pointerMove(x: fixture.markerX(48), y: 10, buttons: 0)
    report.expect(!page.hoverVisible, cppID: projectionID,
                  message: "a marker hover publishes no background label")
    report.expectEqual(48, Tick(page.hoverTick), cppID: projectionID,
                       what: "the marker hover publishes its own tick")
    page.pointerLeave()
    report.expect(!page.hoverVisible, cppID: projectionID,
                  message: "leaving the plot clears the hover")

    // Losing the track publishes the band's unavailable state.
    fixture.session.selectedTrack = nil
    page.refreshFromDocument()
    report.expect(!page.trackAvailable, cppID: projectionID,
                  message: "no selected track publishes the unavailable state")
    report.expectEqual(0, page.markerIdentities.count, cppID: projectionID,
                       what: "no selected track publishes no marker")
    report.expectEqual("No track selected", page.plotMessage, cppID: projectionID,
                       what: "the plot names the missing track")
}

// MARK: - Labels and blank slots

@MainActor
private func slotLabels(_ report: CheckReport, session: DocumentSession,
                        service: ProjectService, programs: [Int]) {
    let slot = programs[0]
    let view = session.bankSlots[slot]
    let label = VoiceLanePolicy.label(slot: slot, view: view)
    report.expect(label.hasPrefix(String(format: "%03d ", slot)), cppID: labelID,
                  message: "a slot label starts with its zero-padded program number "
                      + "(\"\(label)\")")
    let type = voiceTypeName(macro: view.voice?.macro)
    if let symbol = view.voice?.symbol, !symbol.isEmpty {
        report.expect(label.contains(symbol), cppID: labelID,
                      message: "a named slot label carries its source symbol")
        report.expect(label.contains("(\(type))"), cppID: labelID,
                      message: "a named slot label carries its declared type in parentheses")
    } else {
        report.expect(label.contains(type), cppID: labelID,
                      message: "a slot with no source symbol names its declared type "
                          + "(\"\(label)\")")
    }
    report.expectEqual("→ \(label)", VoiceLanePolicy.hoverLabel(label), cppID: labelID,
                       what: "the hover spelling is the label with the legacy arrow")
    report.expectEqual("", VoiceLanePolicy.hoverLabel(""), cppID: labelID,
                       what: "an unresolvable slot publishes no hover label at all")

    report.expectEqual("Sample", voiceTypeName(macro: BankVoiceMacro.directSound),
                       cppID: labelID, what: "Direct Sound is the Sample type")
    report.expectEqual("Sample (fixed pitch)",
                       voiceTypeName(macro: BankVoiceMacro.directSoundNoResample),
                       cppID: labelID, what: "the no-resample form names its fixed pitch")
    report.expectEqual("Sample (reverse)", voiceTypeName(macro: BankVoiceMacro.directSoundAlt),
                       cppID: labelID, what: "the alternate form names its reverse playback")
    report.expectEqual("Square 1", voiceTypeName(macro: BankVoiceMacro.square1), cppID: labelID,
                       what: "the square-1 macro names Square 1")
    report.expectEqual("Square 2", voiceTypeName(macro: BankVoiceMacro.square2), cppID: labelID,
                       what: "the square-2 macro names Square 2")
    report.expectEqual("Wave", voiceTypeName(macro: BankVoiceMacro.programmableWave),
                       cppID: labelID, what: "the wave macro names Wave")
    report.expectEqual("Noise", voiceTypeName(macro: BankVoiceMacro.noise), cppID: labelID,
                       what: "the noise macro names Noise")
    report.expectEqual("Drumkit", voiceTypeName(macro: BankVoiceMacro.keysplitAll),
                       cppID: labelID, what: "the drumkit macro names Drumkit")
    report.expectEqual("", voiceTypeName(macro: nil), cppID: labelID,
                       what: "no macro names no type")

    // A blank slot keeps its program number and gains no invented name.
    let blank = BankSlotView(kind: BankSlotKind.none, voice: nil)
    report.expectEqual(String(format: "%03d", 7), VoiceLanePolicy.label(slot: 7, view: blank),
                       cppID: labelID,
                       what: "a blank slot publishes only its program number")
    report.expectEqual("", VoiceLanePolicy.label(slot: -1, view: blank), cppID: labelID,
                       what: "a missing slot publishes no label at all")
    report.expectEqual("", VoiceLanePolicy.label(slot: session.bankSlots.count, view: nil),
                       cppID: labelID, what: "an out-of-range slot publishes no label")

    // The page's own blank-slot truth, driven through a real lane: a change into
    // a slot with no parsed voice stays explicit.
    guard let blankIndex = session.bankSlots.indices.first(where: {
        session.bankSlots[$0].voice == nil
    }) else {
        report.expect(true, cppID: labelID,
                      message: "the staged bank publishes no blank slot to drive")
        return
    }
    let fixture = VoiceChangesFixture(suite: session, service: service,
                                      programs: [programs[0], blankIndex, programs[2]])
    guard let marker = fixture.marker(at: 48) else {
        report.fail(labelID, "the blank-slot fixture published no marker at tick 48")
        return
    }
    report.expect(marker.slotBlank, cppID: labelID,
                  message: "a change into a blank slot publishes blank truth")
    report.expectEqual("", marker.symbol, cppID: labelID,
                       what: "a blank slot publishes no symbol")
    report.expectEqual(String(format: "%03d", blankIndex), marker.label, cppID: labelID,
                       what: "a blank slot's marker label is its program number")
    fixture.session.editCursor = 48
    report.expect(fixture.page.contextBlank, cppID: labelID,
                  message: "the context readout publishes the blank truth too")
    report.expectEqual(blankIndex, fixture.page.contextSlot, cppID: labelID,
                       what: "the blank context names the blank slot")
    report.expectEqual("", fixture.page.contextSymbol, cppID: labelID,
                       what: "the blank context publishes no symbol")
}

// MARK: - Context

@MainActor
private func currentVoiceContext(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let points = fixture.lanePoints()

    report.expectEqual(programs[0], VoiceLanePolicy.slot(firstProgram: programs[0], tick: 0,
                                                         points: points),
                       cppID: contextID, what: "tick 0 resolves the opening program")
    report.expectEqual(programs[1], VoiceLanePolicy.slot(firstProgram: programs[0], tick: 48,
                                                         points: points),
                       cppID: contextID, what: "a change takes effect at its own tick")
    report.expectEqual(programs[1], VoiceLanePolicy.slot(firstProgram: programs[0], tick: 119,
                                                         points: points),
                       cppID: contextID, what: "the context holds until the next change")
    report.expectEqual(programs[2], VoiceLanePolicy.slot(firstProgram: programs[0], tick: 120,
                                                         points: points),
                       cppID: contextID, what: "the late change takes effect at its tick")
    report.expectEqual(48, VoiceLanePolicy.endTick(after: 0, points: points), cppID: contextID,
                       what: "the opening span ends at the first change")
    report.expectEqual(nil, VoiceLanePolicy.endTick(after: 120, points: points), cppID: contextID,
                       what: "the last span runs to the song's end")

    // Cursor-only publication updates the stopped readout, not static content
    // or document/history state.
    let cursorBuilds = page.contentBuildCount
    let cursorDocument = fixture.snapshot
    fixture.session.editCursor = 60
    report.expectEqual(programs[1], page.contextSlot, cppID: contextID,
                       what: "the stopped context resolves at the published edit cursor")
    report.expectEqual(VoiceLanePolicy.label(slot: programs[1],
                                             view: fixture.session.bankSlots[programs[1]]),
                       page.readoutText, cppID: contextID,
                       what: "the readout names the edit cursor's program")
    report.expectEqual(cursorBuilds, page.contentBuildCount, cppID: contextID,
                       what: "cursor-only publication rebuilds no marker content")
    report.expectEqual(cursorDocument, fixture.snapshot, cppID: contextID,
                       what: "cursor-only publication changes no document or history state")

    // Playing: the same document resolves at the rounded shared-playhead tick.
    page.refreshPlayhead(tick: 8, playing: true)
    report.expectEqual(programs[0], page.presentedContextSlot, cppID: contextID,
                       what: "the playing context resolves at the shared tick, not the cursor")
    report.expect(page.presentedPlaying, cppID: contextID,
                  message: "the presentation publishes its own playing state")
    page.refreshPlayhead(tick: 96.4, playing: true)
    report.expectEqual(programs[1], page.presentedContextSlot, cppID: contextID,
                       what: "a rounded playing tick crosses into the next span")
    report.expectEqual(96, page.presentedContextTick, cppID: contextID,
                       what: "the presented tick is the rounded shared tick")

    // Back to stopped: the edit cursor owns the context again.
    page.refreshPlayhead(tick: 96, playing: false)
    report.expectEqual(programs[1], page.contextSlot, cppID: contextID,
                       what: "the stopped context returns to the edit cursor")
    let laterCursorBuilds = page.contentBuildCount
    fixture.session.editCursor = 130
    report.expectEqual(programs[2], page.contextSlot, cppID: contextID,
                       what: "a moved edit cursor re-resolves the stopped context")
    report.expectEqual(laterCursorBuilds, page.contentBuildCount, cppID: contextID,
                       what: "a later cursor-only publication remains readout-only")

    // A track switch re-derives the projection against the new track's lane.
    fixture.session.selectedTrack = 1
    page.refreshFromDocument()
    report.expectEqual([0], page.markerTicks, cppID: contextID,
                       what: "the secondary track publishes only its own change")
    report.expectEqual(programs[2], page.contextSlot, cppID: contextID,
                       what: "the readout follows the newly selected track")
    fixture.session.selectedTrack = 0
    page.refreshFromDocument()
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: contextID,
                       what: "returning to the primary track restores its markers")
}

// MARK: - Identity

@MainActor
private func occurrenceIdentity(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let points = fixture.lanePoints()
    report.expectEqual(points.map { VoiceOccurrence($0).text }, page.markerIdentities,
                       cppID: identityID,
                       what: "a marker's identity is its lane occurrence's own identity")
    report.expect(page.markerIdentities.allSatisfy {
        $0.split(separator: ".").count == 4
    }, cppID: identityID,
                  message: "an identity names chunk, event index, tick and value")

    // Two occurrences that share a tick are still distinct: identity is not a
    // list position and not a tick.
    let first = LanePoint(chunk: 1, eventIndex: 3, tick: 48, value: programs[0])
    let second = LanePoint(chunk: 1, eventIndex: 9, tick: 48, value: programs[0])
    report.expectEqual(VoiceOccurrence(first),
                       VoiceLanePolicy.occurrence(VoiceOccurrence(first), in: [first, second]),
                       cppID: identityID,
                       what: "the identity resolves the occurrence it names")
    report.expectEqual(VoiceOccurrence(second),
                       VoiceLanePolicy.occurrence(at: 48, in: [first, second]),
                       cppID: identityID,
                       what: "the tick lookup takes the document's last event at that tick")
    let mutated = VoiceOccurrence(chunk: first.chunk, eventIndex: first.eventIndex,
                                  tick: first.tick, value: first.value + 1)
    report.expect(VoiceLanePolicy.occurrence(mutated, in: [first, second]) == nil,
                  cppID: identityID,
                  message: "a different value is never accepted as the frozen occurrence")
    report.expectEqual(first.eventIndex,
                       VoiceLanePolicy.occurrence(VoiceOccurrence(first),
                                                  in: points + [first])?.eventIndex,
                       cppID: identityID,
                       what: "the resolved occurrence keeps the document's event index")

    // Camera-only refreshes keep the identity and move only the projection.
    let before = page.markerIdentities
    let x = page.publishedMarkers[1].x
    _ = page.pointerPress(x: x, y: 10, surface: 1, button: 1, modifiers: 0)
    let frozen = page.frozenOccurrence
    report.expectEqual(VoiceOccurrence(points[1]), frozen, cppID: identityID,
                       what: "the press freezes the marker's own occurrence")
    fixture.session.mutateCamera { $0.setHScroll($0.snapshot.scrollX + 40) }
    report.expectEqual(before, page.markerIdentities, cppID: identityID,
                       what: "a camera scroll changes no marker identity")
    report.expect(page.publishedMarkers[1].x != x, cppID: identityID,
                  message: "a camera scroll does move the projection")
    report.expectEqual(frozen, page.frozenOccurrence, cppID: identityID,
                       what: "the frozen occurrence survives a camera scroll")
    _ = page.pointerRelease(x: x, y: 10, button: 1)
    report.expect(!page.hasGesture, cppID: identityID,
                  message: "the release ends the gesture without a draft")

    // A real insertion joins the lane. The occurrences the insert follows keep
    // the document's own identity; the ones after it shift their event index,
    // which is exactly why the capture carries the revision beside the identity.
    let earlier = page.publishedMarkers.filter { Tick($0.tick) <= 48 }.map(\.identity)
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.setPickerFilter(text: String(format: "%03d", programs[2]))
    page.selectPickerRow(index: 0)
    report.expect(page.acceptPicker(), cppID: identityID,
                  message: "an insertion between the changes lands in the document")
    report.expectEqual(4, page.markerIdentities.count, cppID: identityID,
                       what: "the inserted occurrence joins the projection")
    report.expectEqual(4, Set(page.markerIdentities).count, cppID: identityID,
                       what: "the inserted occurrence has an identity of its own")
    report.expectEqual(earlier,
                       page.publishedMarkers.filter { Tick($0.tick) <= 48 }.map(\.identity),
                       cppID: identityID,
                       what: "the occurrences before the edit keep their identity")
}

// MARK: - Picker insertion

@MainActor
private func pickerInsertion(_ report: CheckReport, suite: DocumentSession,
                             service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot
    report.expect(!baseline.canUndo, cppID: insertionID,
                  message: "the fixture starts with no undoable edit")

    report.expect(page.pointerDoubleClick(x: fixture.markerX(96), y: 10), cppID: insertionID,
                  message: "the double-click on the empty lane opens the picker")
    report.expect(page.hasPicker, cppID: insertionID,
                  message: "the double-click on the empty lane opens the picker")
    report.expectEqual("Insert voice change", page.pickerTitle, cppID: insertionID,
                       what: "an empty-lane target opens the insertion title")
    report.expectEqual(96, page.pickerTargetTick, cppID: insertionID,
                       what: "the captured tick is the press's snapped tick")
    report.expect(page.pickerTargetIdentity == nil, cppID: insertionID,
                  message: "an empty-lane target carries no occurrence")
    report.expectEqual(programs[1], page.pickerProgram, cppID: insertionID,
                       what: "the picker opens on the slot the context resolves to")
    report.expect(page.interactionActive, cppID: insertionID,
                  message: "an open picker reports an active interaction")
    report.expectEqual(3, page.markerIdentities.count, cppID: insertionID,
                       what: "the open picker publishes no marker of its own")

    // Filter, then accept: one insertion, one revision, one history entry.
    let filter = String(format: "%03d", programs[2])
    page.setPickerFilter(text: filter)
    report.expect(page.pickerRowPrograms.contains(programs[2]), cppID: insertionID,
                  message: "the filter keeps the row it names")
    report.expect(!page.pickerRowValues.isEmpty, cppID: insertionID,
                  message: "the filter publishes the rows it matched")
    report.expect(page.pickerRowValues.allSatisfy {
        $0.label.range(of: filter, options: .caseInsensitive) != nil
    }, cppID: insertionID, message: "every visible row matches the filter")
    page.selectPickerRow(index: 0)
    report.expectEqual(programs[2], page.pickerProgram, cppID: insertionID,
                       what: "the row press selects the filtered program")
    report.expect(page.acceptPicker(), cppID: insertionID,
                  message: "accepting the picker writes the captured target")
    report.expectEqual(4, fixture.lanePoints().count, cppID: insertionID,
                       what: "the insertion adds exactly one lane event")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: 96, in: fixture.lanePoints())?.value,
                       cppID: insertionID, what: "the inserted event carries the chosen slot")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: insertionID,
                       what: "the insertion is one revision")
    report.expect(fixture.snapshot.canUndo, cppID: insertionID,
                  message: "the insertion records one history entry")
    report.expectEqual([0, 48, 96, 120], page.markerTicks, cppID: insertionID,
                       what: "the projection rebuilds around the new occurrence")
    report.expect(!page.hasPicker, cppID: insertionID,
                  message: "acceptance closes the picker")
    report.expect(!page.interactionActive, cppID: insertionID,
                  message: "acceptance releases the follow-scroll gate")

    // Undo and redo follow the document.
    do {
        _ = try runBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(insertionID, "undo failed: \(error)")
        return
    }
    report.expect(VoiceLanePolicy.occurrence(at: 96, in: fixture.lanePoints()) == nil,
                  cppID: insertionID, message: "undo removes the inserted occurrence")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: insertionID,
                       what: "undo rebuilds the projection without the insertion")
    do {
        _ = try runBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(insertionID, "redo failed: \(error)")
        return
    }
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: 96, in: fixture.lanePoints())?.value,
                       cppID: insertionID, what: "redo restores the inserted occurrence")
    report.expect(page.markerTicks.contains(96), cppID: insertionID,
                  message: "redo republishes the restored marker")

    // A same-value acceptance is a no-op.
    let settled = fixture.snapshot
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.setPickerFilter(text: filter)
    page.selectPickerRow(index: 0)
    report.expect(!page.acceptPicker(), cppID: insertionID,
                  message: "accepting the value the document already holds writes nothing")
    report.expectEqual(settled, fixture.snapshot, cppID: insertionID,
                       what: "the same-value acceptance leaves the document untouched")

    // A filter that matches nothing cannot be accepted.
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.setPickerFilter(text: "zzz-no-such-voice")
    report.expect(!page.pickerHasMatch, cppID: insertionID,
                  message: "an unmatched filter publishes no match")
    report.expectEqual(0, page.pickerRowValues.count, cppID: insertionID,
                       what: "an unmatched filter publishes no row")
    report.expectEqual(-1, page.pickerIndex, cppID: insertionID,
                       what: "an unmatched filter publishes no current row")
    report.expect(!page.acceptPicker(), cppID: insertionID,
                  message: "an unmatched filter cannot be accepted")
    report.expectEqual(settled, fixture.snapshot, cppID: insertionID,
                       what: "the refused acceptance leaves the document untouched")
}

// MARK: - Picker value replacement

@MainActor
private func pickerValueReplacement(_ report: CheckReport, suite: DocumentSession,
                                    service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot
    let target = VoiceOccurrence(fixture.lanePoints()[1])
    let markerX = fixture.markerX(48)

    _ = page.pointerDoubleClick(x: markerX, y: 10)
    report.expectEqual("Change voice", page.pickerTitle, cppID: replacementID,
                       what: "a marker target opens the change title")
    report.expectEqual(target.text, page.pickerTargetIdentity, cppID: replacementID,
                       what: "the captured identity is the pressed occurrence")
    report.expectEqual(48, page.pickerTargetTick, cppID: replacementID,
                       what: "the captured tick is the marker's own tick")
    report.expectEqual(target.value, page.pickerProgram, cppID: replacementID,
                       what: "the picker opens on the marker's current program")

    page.setPickerFilter(text: String(format: "%03d", programs[2]))
    page.selectPickerRow(index: 0)
    report.expect(page.acceptPicker(), cppID: replacementID,
                  message: "accepting the picker replaces the captured occurrence's value")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: 48, in: fixture.lanePoints())?.value,
                       cppID: replacementID, what: "the change at tick 48 carries the new slot")
    report.expectEqual(3, fixture.lanePoints().count, cppID: replacementID,
                       what: "a value replacement adds no event")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: replacementID,
                       what: "the replacement is one revision")
    report.expect(fixture.snapshot.canUndo && !baseline.canUndo, cppID: replacementID,
                  message: "the replacement records one history entry")
    report.expect(page.publishedMarkers.contains {
        Tick($0.tick) == 48 && $0.label.hasPrefix(String(format: "%03d", programs[2]))
    }, cppID: replacementID,
       message: "the projection's marker label follows the replaced slot")

    // Escape and a pointer dismissal both write nothing.
    let settled = fixture.snapshot
    _ = page.pointerDoubleClick(x: markerX, y: 10)
    report.expect(page.hasPicker, cppID: replacementID, message: "the picker reopens")
    report.expect(page.handleEscape(), cppID: replacementID,
                  message: "Escape claims the key while the picker is open")
    report.expect(!page.hasPicker, cppID: replacementID, message: "Escape closes the picker")
    report.expectEqual(settled, fixture.snapshot, cppID: replacementID,
                       what: "Escape writes nothing")
    report.expect(!page.handleEscape(), cppID: replacementID,
                  message: "Escape is unhandled once nothing is open")

    _ = page.pointerDoubleClick(x: markerX, y: 10)
    _ = page.pointerPress(x: fixture.markerX(200), y: 10, surface: 1, button: 1, modifiers: 0)
    report.expect(!page.hasPicker, cppID: replacementID,
                  message: "an outside press dismisses the picker")
    report.expect(!page.hasGesture, cppID: replacementID,
                  message: "the dismissing press starts no gesture")
    _ = page.pointerRelease(x: fixture.markerX(200), y: 10, button: 1)
    report.expectEqual(settled, fixture.snapshot, cppID: replacementID,
                       what: "the dismissed press and its release write nothing")

    // A stale capture — the document moved under the open picker — writes
    // nothing and never retargets another occurrence.
    _ = page.pointerDoubleClick(x: markerX, y: 10)
    let staleTarget = page.pickerTargetIdentity
    let heldAtCapture = VoiceLanePolicy.occurrence(
        at: 48, in: fixture.document.lanePoints(track: 0, lane: .voice)).map { $0.text }
    report.expectEqual(heldAtCapture, staleTarget, cppID: replacementID,
                       what: "the capture names the occurrence the document held then")
    fixture.document.writeLane(track: 0, lane: .voice, from: 0, through: 0,
                               points: [LaneWrite(tick: 0, value: programs[2])])
    report.expect(!page.hasPicker, cppID: replacementID,
                  message: "a document change cancels the open picker")
    let rewrote = fixture.snapshot
    report.expect(!page.acceptPicker(), cppID: replacementID,
                  message: "an acceptance after the cancellation writes nothing")
    report.expectEqual(rewrote, fixture.snapshot, cppID: replacementID,
                       what: "the stale acceptance leaves the rewrite as the only change")
    report.expect(page.pickerTargetIdentity == nil, cppID: replacementID,
                  message: "the cancelled capture is gone instead of retargeted")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: 0, in: fixture.lanePoints())?.value,
                       cppID: replacementID, what: "the rewrite itself stands")
}

// MARK: - Marker drag

@MainActor
private func markerDragTransactions(_ report: CheckReport, suite: DocumentSession,
                                    service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
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
                           cppID: moveID, what: "drag and redraw preserve tied marker order")
        report.expectEqual(incremental.map(\.label), redrawn.map(\.label),
                           cppID: moveID, what: "drag and redraw agree on label elision")
        for (before, after) in zip(incremental, redrawn) {
            for component in ["x", "y", "width", "height"] {
                report.expectEqual(before.labelRect[component] as? Double,
                                   after.labelRect[component] as? Double, cppID: moveID,
                                   what: "drag and redraw agree on label \(component)")
            }
            report.expectEqual(before.offscreen, after.offscreen, cppID: moveID,
                               what: "drag and redraw agree on offscreen labels")
        }
    }
    page.cancelSectionInteraction()

    // Below the activation distance: a press and a release commit nothing.
    let startX = fixture.markerX(48)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 4, y: 10, buttons: 1)
    report.expect(!page.dragActive, cppID: moveID,
                  message: "a move below the activation distance stays pending")
    _ = page.pointerRelease(x: startX + 4, y: 10, button: 1)
    report.expectEqual(baseline, fixture.snapshot, cppID: moveID,
                       what: "a drag below the activation distance commits nothing")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: moveID,
                       what: "the untouched occurrence keeps its tick")

    // An activated drag commits exactly one move at the tick it previewed.
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    report.expect(page.hasGesture, cppID: moveID, message: "the press owns a gesture")
    report.expectEqual(48, page.frozenOccurrence?.tick, cppID: moveID,
                       what: "the frozen occurrence is the pressed marker")
    report.expect(page.interactionActive, cppID: moveID,
                  message: "the live gesture reports an active interaction")
    _ = page.pointerMove(x: startX + 60, y: 10, buttons: 1)
    report.expect(page.dragActive, cppID: moveID,
                  message: "the drag activates past its activation distance")
    guard let preview = page.dragPreviewTick else {
        report.fail(moveID, "the activated drag published no preview tick")
        return
    }
    report.expect(preview != 48, cppID: moveID,
                  message: "the preview tick drafts away from the frozen tick")
    report.expectEqual(baseline, fixture.snapshot, cppID: moveID,
                       what: "motion is preview only and mutates nothing")
    report.expectEqual(preview, page.markerTicks[1], cppID: moveID,
                       what: "the projection draws the marker at the preview tick")
    _ = page.pointerRelease(x: startX + 60, y: 10, button: 1)
    report.expect(!page.hasGesture && !page.interactionActive, cppID: moveID,
                  message: "the release ends the gesture and its interaction")
    report.expectEqual(preview, fixture.lanePoints()[1].tick, cppID: moveID,
                       what: "the release commits the preview tick")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: moveID,
                       what: "the move is one revision")
    report.expect(fixture.snapshot.canUndo, cppID: moveID,
                  message: "the move records one history entry")
    report.expect(VoiceLanePolicy.occurrence(at: 48, in: fixture.lanePoints()) == nil,
                  cppID: moveID, message: "the source tick no longer holds the occurrence")

    do {
        _ = try runBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(moveID, "undo failed: \(error)")
        return
    }
    report.expectEqual(48, fixture.lanePoints()[1].tick, cppID: moveID,
                       what: "undo restores the moved occurrence's tick")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: moveID,
                       what: "undo rebuilds the projection at the restored tick")
    do {
        _ = try runBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(moveID, "redo failed: \(error)")
        return
    }
    report.expectEqual(preview, fixture.lanePoints()[1].tick, cppID: moveID,
                       what: "redo reapplies the move")

    // A release back on the frozen tick is a no-op.
    let settled = fixture.snapshot
    let movedX = fixture.markerX(preview)
    _ = page.pointerPress(x: movedX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: movedX + 60, y: 10, buttons: 1)
    _ = page.pointerMove(x: movedX, y: 10, buttons: 1)
    report.expectEqual(preview, page.dragPreviewTick, cppID: moveID,
                       what: "the draft returns to the frozen tick")
    _ = page.pointerRelease(x: movedX, y: 10, button: 1)
    report.expectEqual(settled, fixture.snapshot, cppID: moveID,
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
    report.expect(staleDraft != nil && staleDraft != preview, cppID: moveID,
                  message: "the stale drag had drafted another tick before the release")
    report.expectEqual(rewritten, fixture.snapshot, cppID: moveID,
                       what: "a drag whose revision moved under it commits nothing")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: 0, in: fixture.lanePoints())?.value,
                       cppID: moveID, what: "the concurrent rewrite is the one that stands")
}

// MARK: - Context menu

@MainActor
private func contextMenuTransactions(_ report: CheckReport, suite: DocumentSession,
                                     service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let target = VoiceOccurrence(fixture.lanePoints()[1])

    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expect(page.hasMenu && page.menuOpen, cppID: menuID,
                  message: "a right press on a marker opens the context menu")
    report.expectEqual([VoiceChangesPagePolicy.changeVoiceAction,
                        VoiceChangesPagePolicy.deleteMarkerAction],
                       page.menuRowActions, cppID: menuID,
                       what: "a marker target publishes the change and delete rows")
    report.expectEqual(target.text, page.menuTargetIdentity, cppID: menuID,
                       what: "the menu captured the pressed occurrence")
    report.expectEqual(48, page.menuTargetTick, cppID: menuID,
                       what: "the menu captured the marker's own tick")
    report.expect(page.interactionActive, cppID: menuID,
                  message: "an open menu reports an active interaction")

    // A camera scroll after the open neither drifts the capture nor closes it.
    fixture.session.mutateCamera { $0.setHScroll($0.snapshot.scrollX + 80) }
    report.expect(page.hasMenu, cppID: menuID, message: "a camera scroll keeps the menu open")
    report.expectEqual(target.text, page.menuTargetIdentity, cppID: menuID,
                       what: "a camera scroll does not drift the captured identity")
    report.expectEqual(48, page.menuTargetTick, cppID: menuID,
                       what: "a camera scroll does not drift the captured tick")

    // Outside dismissal writes nothing.
    let baseline = fixture.snapshot
    page.dismissVoiceMenu()
    report.expect(!page.hasMenu && !page.menuOpen, cppID: menuID,
                  message: "the outside dismissal closes the menu")
    report.expect(!page.interactionActive, cppID: menuID,
                  message: "the dismissal releases the follow-scroll gate")
    report.expectEqual(baseline, fixture.snapshot, cppID: menuID,
                       what: "the dismissal writes nothing")

    // The delete row removes exactly the captured occurrence.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expect(page.activateMenuAction(actionId: VoiceChangesPagePolicy.deleteMarkerAction),
                  cppID: menuID, message: "the delete row deletes the captured marker")
    report.expect(VoiceLanePolicy.occurrence(at: 48, in: fixture.lanePoints()) == nil,
                  cppID: menuID, message: "the deleted tick no longer holds a change")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: menuID,
                       what: "the deletion is one revision")
    report.expect(fixture.snapshot.canUndo && !baseline.canUndo, cppID: menuID,
                  message: "the deletion records one history entry")
    report.expectEqual([0, 120], page.markerTicks, cppID: menuID,
                       what: "the projection drops exactly the deleted marker")

    // An empty-lane target offers the insertion row, which hands the same
    // captured target to the picker.
    _ = page.pointerPress(x: fixture.markerX(96), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expectEqual([VoiceChangesPagePolicy.insertVoiceChangeAction], page.menuRowActions,
                       cppID: menuID, what: "an empty-lane target publishes the insert row")
    report.expect(page.menuTargetIdentity == nil, cppID: menuID,
                  message: "the empty-lane target carries no occurrence")
    report.expect(page.activateMenuAction(actionId: VoiceChangesPagePolicy.insertVoiceChangeAction),
                  cppID: menuID, message: "the insert row opens the picker")
    report.expect(page.hasPicker, cppID: menuID, message: "the picker opens on the capture")
    report.expectEqual(96, page.pickerTargetTick, cppID: menuID,
                       what: "the picker inherits the menu's captured tick")
    report.expectEqual("Insert voice change", page.pickerTitle, cppID: menuID,
                       what: "the inherited empty-lane capture keeps the insertion title")
    report.expect(!page.hasMenu, cppID: menuID, message: "the activation consumed the menu")
    page.cancelPicker()

    // A stale menu — a rewrite between the open and the activation — writes
    // nothing, and its rows never fire.
    _ = page.pointerPress(x: fixture.markerX(120), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expect(page.hasMenu, cppID: menuID, message: "the menu reopened on the third marker")
    fixture.document.writeLane(track: 0, lane: .voice, from: 0, through: 0,
                               points: [LaneWrite(tick: 0, value: programs[2])])
    page.refreshFromDocument()
    report.expect(!page.hasMenu, cppID: menuID,
                  message: "a document change cancels the open menu")
    let rewritten = fixture.snapshot
    report.expect(!page.activateMenuAction(actionId: VoiceChangesPagePolicy.deleteMarkerAction),
                  cppID: menuID, message: "an activation after the cancellation writes nothing")
    report.expectEqual(rewritten, fixture.snapshot, cppID: menuID,
                       what: "the stale activation leaves the rewrite as the only change")
}

// MARK: - Picker keyboard policy

@MainActor
private func pickerKeyboardPolicy(_ report: CheckReport, suite: DocumentSession,
                                  service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    guard page.hasPicker else {
        report.fail(keyboardID, "the picker did not open")
        return
    }
    report.expectEqual(suite.bankSlots.count, page.pickerRowValues.count, cppID: keyboardID,
                       what: "an empty filter publishes every bank row")
    report.expectEqual(programs[1], page.pickerProgram, cppID: keyboardID,
                       what: "the picker opens on the context slot the target captured")
    report.expectEqual(programs[1], page.pickerIndex, cppID: keyboardID,
                       what: "the published row index follows the current program")
    let first = page.pickerProgram
    page.movePickerSelection(delta: 1)
    report.expectEqual(first + 1, page.pickerProgram, cppID: keyboardID,
                       what: "the down arrow moves to the next visible program")
    page.movePickerSelection(delta: -1)
    report.expectEqual(first, page.pickerProgram, cppID: keyboardID,
                       what: "the up arrow returns to the previous program")
    page.movePickerSelection(delta: -5)
    report.expectEqual(page.pickerRowPrograms.first ?? -1, page.pickerProgram, cppID: keyboardID,
                       what: "the navigation clamps at the first row")
    page.movePickerSelection(delta: 500)
    report.expectEqual(page.pickerRowPrograms.last ?? -1, page.pickerProgram, cppID: keyboardID,
                       what: "the navigation clamps at the last row")
    report.expectEqual(page.pickerRowPrograms.count - 1, page.pickerIndex, cppID: keyboardID,
                       what: "the row index follows the clamped program")
    page.selectPickerRow(index: 1)
    report.expectEqual(page.pickerRowPrograms[1], page.pickerProgram, cppID: keyboardID,
                       what: "a row press selects exactly that row's program")
    report.expect(page.pickerRowValues[1].selected, cppID: keyboardID,
                  message: "the selected row publishes its own state")
    report.expectEqual(1, page.pickerRowValues.filter(\.selected).count, cppID: keyboardID,
                       what: "exactly one row is selected")

    // Filtering by name text follows the labels the bank publishes.
    let name = suite.bankSlots[programs[0]].voice?.symbol ?? ""
    if !name.isEmpty {
        page.setPickerFilter(text: name)
        report.expect(page.pickerRowPrograms.contains(programs[0]), cppID: keyboardID,
                      message: "a name filter keeps the slot that carries it")
        report.expect(page.pickerRowValues.allSatisfy {
            $0.label.lowercased().contains(name.lowercased())
        }, cppID: keyboardID, message: "every row matched by name really carries the name")
    }
    page.cancelPicker()
    report.expect(!page.hasPicker, cppID: keyboardID, message: "the picker closes")
}

// MARK: - Cancellation

@MainActor
private func cancellationPaths(_ report: CheckReport, suite: DocumentSession,
                               service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot

    // A picker cancelled by the container's own path releases the interaction.
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.cancelSectionInteraction()
    report.expect(!page.hasPicker, cppID: cancellationID,
                  message: "the container's cancellation closes the picker")
    report.expect(!page.interactionActive, cppID: cancellationID,
                  message: "cancellation releases the follow-scroll gate")
    report.expectEqual(baseline, fixture.snapshot, cppID: cancellationID,
                       what: "the cancelled picker wrote nothing")

    // A live drag cancelled mid-motion restores presentation and commits nothing.
    let startX = fixture.markerX(48)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 60, y: 10, buttons: 1)
    report.expect(page.dragActive, cppID: cancellationID, message: "the drag is live")
    page.cancelSectionInteraction()
    report.expect(!page.hasGesture && !page.interactionActive, cppID: cancellationID,
                  message: "cancellation ends the live drag")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: cancellationID,
                       what: "the cancelled drag restores the projection from the document")
    report.expectEqual(baseline, fixture.snapshot, cppID: cancellationID,
                       what: "the cancelled drag commits nothing")

    // The canvas keeps drawing after a cancellation.
    fixture.session.mutateCamera { $0.setHScroll($0.snapshot.scrollX + 20) }
    report.expectEqual(3, page.publishedMarkers.count, cppID: cancellationID,
                       what: "the projection survives the cancellation")

    // A track switch invalidates an open modal instead of retargeting it.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expect(page.hasMenu, cppID: cancellationID, message: "the menu is open")
    fixture.session.selectedTrack = 1
    page.refreshFromDocument()
    report.expect(!page.hasMenu, cppID: cancellationID,
                  message: "a track switch cancels the captured menu")
    report.expect(!page.activateMenuAction(actionId: VoiceChangesPagePolicy.deleteMarkerAction),
                  cppID: cancellationID, message: "the cancelled menu fires no row")
    report.expectEqual(baseline, fixture.snapshot, cppID: cancellationID,
                       what: "the track switch wrote nothing")
    report.expectEqual([0], page.markerTicks, cppID: cancellationID,
                       what: "the projection re-derives for the new track")
    fixture.session.selectedTrack = 0
    page.refreshFromDocument()

    // A hide cancels a live gesture through the same synchronous path.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 30, y: 10, buttons: 1)
    page.cancelSectionInteraction()
    report.expect(!page.dragActive, cppID: cancellationID,
                  message: "a hide cancels the in-flight drag")
    report.expectEqual(48, page.markerTicks[1], cppID: cancellationID,
                       what: "the hidden page's projection is back on the document")

    // Detach ends everything and publishes no marker.
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.detach()
    report.expect(!page.hasPicker && !page.hasMenu && !page.hasGesture, cppID: cancellationID,
                  message: "detach cancels every interaction")
    report.expectEqual(0, page.markerIdentities.count, cppID: cancellationID,
                       what: "detach publishes no marker")
    report.expectEqual(0, page.heldSpans.count, cppID: cancellationID,
                       what: "detach publishes no held span")
    report.expectEqual(baseline, fixture.snapshot, cppID: cancellationID,
                       what: "detach wrote nothing")

    // The gutter never edits and opens no modal.
    let gutterFixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    report.expect(!gutterFixture.page.pointerPress(x: 10, y: 10, surface: 0, button: 1,
                                                   modifiers: 0),
                  cppID: cancellationID,
                  message: "a gutter press is not consumed by the page")
    report.expect(!gutterFixture.page.hasGesture, cppID: cancellationID,
                  message: "a gutter press starts no gesture")
    report.expect(!gutterFixture.page.hasPicker, cppID: cancellationID,
                  message: "a gutter press opens no picker")
    report.expect(!gutterFixture.page.interactionActive, cppID: cancellationID,
                  message: "a gutter press reports no interaction")
}

// MARK: - History refresh

@MainActor
private func undoRedoRefresh(_ report: CheckReport, suite: DocumentSession,
                             service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let builds = page.contentBuildCount
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.setPickerFilter(text: String(format: "%03d", programs[2]))
    page.selectPickerRow(index: 0)
    _ = page.acceptPicker()
    report.expectEqual(builds + 1, page.contentBuildCount, cppID: historyID,
                       what: "one committed edit rebuilds the projection exactly once")
    let editedBuilds = page.contentBuildCount
    do {
        _ = try runBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(historyID, "undo failed: \(error)")
        return
    }
    report.expect(page.contentBuildCount > editedBuilds, cppID: historyID,
                  message: "undo rebuilds every affected page")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: historyID,
                       what: "undo removes the inserted marker")
    report.expectEqual(VoiceLanePolicy.label(slot: programs[0],
                                             view: fixture.session.bankSlots[programs[0]]),
                       page.contextLabel(at: page.contextSlot), cppID: historyID,
                       what: "undo restores the context the readout resolves")
    let undoneBuilds = page.contentBuildCount
    do {
        _ = try runBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(historyID, "redo failed: \(error)")
        return
    }
    report.expect(page.contentBuildCount > undoneBuilds, cppID: historyID,
                  message: "redo rebuilds the projection again")
    report.expectEqual([0, 48, 96, 120], page.markerTicks, cppID: historyID,
                       what: "redo republishes the full marker set")

    // An equal refresh leaves every marker exactly as it was: the rebuild runs,
    // and no published row is replaced.
    let identities = page.markerIdentities
    let publishedMarkers = page.markers.asArray
    page.refreshFromDocument()
    report.expectEqual(identities, page.markerIdentities, cppID: historyID,
                       what: "an equal refresh leaves every marker identity in place")
    report.expectEqual(publishedMarkers.count, page.markers.count, cppID: historyID,
                       what: "an equal refresh publishes the same marker count")
    report.expect(zip(publishedMarkers, page.markers.asArray).allSatisfy { $0 === $1 },
                  cppID: historyID,
                  message: "an equal refresh replaces no published marker row")
}

// MARK: - Playhead diagnostics

@MainActor
private func playheadDiagnostics(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let documentFacts = fixture.snapshot
    page.refreshPlayhead(tick: 0, playing: true)
    let builds = page.contentBuildCount
    let presentations = page.playheadPresentationCount
    let contextChanges = page.contextChangeCount
    let readout = page.readoutText
    report.expectEqual(programs[0], page.presentedContextSlot, cppID: diagnosticsID,
                       what: "the playing context opens on the first program span")

    // Every other distinct shared tick inside the same span: the page consumes
    // each of them and rebuilds no static content.
    var ticks: [Double] = []
    for step in 1..<48 { ticks.append(Double(step)) }
    for tick in ticks {
        page.refreshPlayhead(tick: tick, playing: true)
    }
    report.expectEqual(presentations + UInt64(ticks.count), page.playheadPresentationCount,
                       cppID: diagnosticsID,
                       what: "every distinct shared presentation is consumed once")
    // A shared position that rounds to a tick the page already presented is not
    // a presentation of its own, and neither is an equal one.
    let roundingBase = page.playheadPresentationCount
    page.refreshPlayhead(tick: 47.4, playing: true)
    report.expectEqual(roundingBase, page.playheadPresentationCount, cppID: diagnosticsID,
                       what: "a position rounding to an already presented tick presents nothing")
    page.refreshPlayhead(tick: 47, playing: true)
    report.expectEqual(roundingBase, page.playheadPresentationCount, cppID: diagnosticsID,
                       what: "an equal presentation is not consumed twice")
    report.expectEqual(builds, page.contentBuildCount, cppID: diagnosticsID,
                       what: "playhead-only movement inside one span rebuilds no content")
    report.expectEqual(contextChanges, page.contextChangeCount, cppID: diagnosticsID,
                       what: "no span was crossed inside the span itself")
    report.expectEqual(programs[0], page.presentedContextSlot, cppID: diagnosticsID,
                       what: "the presented context stayed in its own span")
    report.expectEqual(readout, page.readoutText, cppID: diagnosticsID,
                       what: "the readout names the same program throughout the span")
    report.expectEqual(documentFacts, fixture.snapshot, cppID: diagnosticsID,
                       what: "playhead movement mutates no document and consumes no redo")

    // An equal presentation publishes nothing.
    let settled = page.playheadPresentationCount
    page.refreshPlayhead(tick: ticks.last ?? 0, playing: true)
    report.expectEqual(settled, page.playheadPresentationCount, cppID: diagnosticsID,
                       what: "an equal presentation is not consumed twice")

    // Crossing into the next span updates the readout and rebuilds once.
    page.refreshPlayhead(tick: 60, playing: true)
    report.expectEqual(programs[1], page.presentedContextSlot, cppID: diagnosticsID,
                       what: "crossing a span updates the context indicator")
    report.expectEqual(builds + 1, page.contentBuildCount, cppID: diagnosticsID,
                       what: "crossing a span rebuilds the projection exactly once")
    report.expectEqual(contextChanges + 1, page.contextChangeCount, cppID: diagnosticsID,
                       what: "one context change is counted")
    report.expect(page.readoutText.hasPrefix(String(format: "%03d", programs[1])),
                  cppID: diagnosticsID, message: "the readout names the new span's program")

    // Stopping returns the context to the edit cursor.
    fixture.session.editCursor = 200
    page.refreshPlayhead(tick: 60, playing: false)
    report.expectEqual(programs[2], page.presentedContextSlot, cppID: diagnosticsID,
                       what: "the stopped context follows the edit cursor")
    report.expectEqual(builds + 2, page.contentBuildCount, cppID: diagnosticsID,
                       what: "the playing-to-stopped transition rebuilds once")
}

// MARK: - Alt fine-snap lattice

@MainActor
private func altFineClockLattice(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService, programs: [Int]) {
    // `SongDocument::ticksPerClock`: one clock is `division / (24 * (extended ? 2 : 1))`
    // ticks, floored at one.
    report.expectEqual(1, TimelineSnapPolicy.clockTicks(division: 24, extendedClocks: false),
                       cppID: fineSnapID,
                       what: "a 24-tick division names one tick per clock")
    report.expectEqual(4, TimelineSnapPolicy.clockTicks(division: 96, extendedClocks: false),
                       cppID: fineSnapID,
                       what: "a 96-tick division names four ticks per clock")
    report.expectEqual(2, TimelineSnapPolicy.clockTicks(division: 96, extendedClocks: true),
                       cppID: fineSnapID,
                       what: "extended clocks halve the ticks per clock")
    report.expectEqual(1, TimelineSnapPolicy.clockTicks(division: 1, extendedClocks: false),
                       cppID: fineSnapID, what: "the clock stride never falls below one tick")

    // `Grid::snapTick(tick, fine: true)`: the absolute clock lattice, rounded
    // half-up, clamped to the song's tick domain.
    report.expectEqual(4, TimelineSnapPolicy.fineSnap(5.9, clockTicks: 4), cppID: fineSnapID,
                       what: "a position inside a clock cell snaps to its floor")
    report.expectEqual(8, TimelineSnapPolicy.fineSnap(6, clockTicks: 4), cppID: fineSnapID,
                       what: "an exact tie rounds up, as the legacy lattice does")
    report.expectEqual(8, TimelineSnapPolicy.fineSnap(6.1, clockTicks: 4), cppID: fineSnapID,
                       what: "a position past the midpoint snaps up")
    report.expectEqual(0, TimelineSnapPolicy.fineSnap(-3, clockTicks: 4), cppID: fineSnapID,
                       what: "the lattice is anchored at zero")
    report.expectEqual(TimeDefaults.maxTick,
                       TimelineSnapPolicy.fineSnap(Double(TimeDefaults.maxTick), clockTicks: 4),
                       cppID: fineSnapID, what: "the lattice clamps to the song's tick domain")

    // The page's own drag: with the alt modifier the preview snaps on the clock
    // lattice of the document in front of it, not on the editing lattice.
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs,
                                      division: 96)
    let page = fixture.page
    let clock = TimelineSnapPolicy.clockTicks(
        division: fixture.document.ticksPerBeat,
        extendedClocks: fixture.document.state.config.extendedClocks)
    report.expect(clock >= 1, cppID: fineSnapID,
                  message: "the fixture document publishes its own clock stride")
    let dragged = VoiceOccurrence(fixture.lanePoints()[1])
    let startX = fixture.markerX(dragged.tick)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    let altX = startX + 60
    _ = page.pointerMove(x: altX, y: 10, buttons: 1, modifiers: VoiceModifier.alt)
    let raw = fixture.session.camera.tickAtContentX(altX)
    report.expectEqual(TimelineSnapPolicy.fineSnap(raw, clockTicks: clock), page.dragPreviewTick,
                       cppID: fineSnapID,
                       what: "the alt drag previews the legacy clock lattice")
    report.expect((page.dragPreviewTick ?? 1) % Tick(clock) == 0, cppID: fineSnapID,
                  message: "the alt preview lands on the clock lattice itself")
    _ = page.pointerRelease(x: altX, y: 10, button: 1)
    report.expectEqual(TimelineSnapPolicy.fineSnap(raw, clockTicks: clock),
                       fixture.lanePoints().first { $0.value == dragged.value }?.tick,
                       cppID: fineSnapID,
                       what: "the released alt drag commits the clock-lattice tick")
}

// MARK: - Collision and blank-slot commits

@MainActor
private func collisionDragOutcome(_ report: CheckReport, suite: DocumentSession,
                                  service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot
    let moving = VoiceOccurrence(fixture.lanePoints()[1])
    let occupied = VoiceOccurrence(fixture.lanePoints()[2])
    let startX = fixture.markerX(moving.tick)

    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: fixture.markerX(occupied.tick), y: 10, buttons: 1)
    report.expectEqual(occupied.tick, page.dragPreviewTick, cppID: collisionID,
                       what: "the dragged preview lands on the occupied tick")
    _ = page.pointerRelease(x: fixture.markerX(occupied.tick), y: 10, button: 1)

    let points = fixture.lanePoints()
    report.expectEqual(2, points.count, cppID: collisionID,
                       what: "a move onto an occupied tick leaves one occurrence there")
    report.expectEqual(moving.value,
                       VoiceLanePolicy.occurrence(at: occupied.tick, in: points)?.value,
                       cppID: collisionID, what: "the moved occurrence wins the destination")
    report.expect(VoiceLanePolicy.occurrence(at: moving.tick, in: points) == nil,
                  cppID: collisionID, message: "the source tick no longer holds a change")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: collisionID,
                       what: "the collision is one revision")
    report.expect(fixture.snapshot.canUndo && !baseline.canUndo, cppID: collisionID,
                  message: "the collision records exactly one history entry")

    // One history entry, both sides restored: an unintended second entry would
    // leave one of the two occurrences behind.
    do {
        _ = try runBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(collisionID, "undo failed: \(error)")
        return
    }
    let restored = fixture.lanePoints()
    report.expectEqual(3, restored.count, cppID: collisionID,
                       what: "a single undo restores both occurrences")
    report.expectEqual(programs[1], VoiceLanePolicy.occurrence(at: 48, in: restored)?.value,
                       cppID: collisionID, what: "the moved occurrence is back at its tick")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: occupied.tick, in: restored)?.value,
                       cppID: collisionID, what: "the displaced occurrence is back too")
}

@MainActor
private func blankSlotCommit(_ report: CheckReport, suite: DocumentSession,
                             service: ProjectService, programs: [Int]) {
    guard let blankIndex = suite.bankSlots.indices.first(where: {
        suite.bankSlots[$0].voice == nil
    }) else {
        report.expect(true, cppID: collisionID,
                      message: "the staged bank publishes no blank slot to commit")
        return
    }
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    guard page.hasPicker else {
        report.fail(collisionID, "the picker did not open for the blank-slot commit")
        return
    }
    page.setPickerFilter(text: String(format: "%03d", blankIndex))
    guard let row = page.pickerRowPrograms.firstIndex(of: blankIndex) else {
        report.fail(collisionID,
                    "the blank slot \(blankIndex) publishes no row for its own number")
        page.cancelPicker()
        return
    }
    page.selectPickerRow(index: row)
    report.expect(page.acceptPicker(), cppID: collisionID,
                  message: "the picker commits the slot the bank holds no parsed voice for")
    report.expectEqual(blankIndex,
                       VoiceLanePolicy.occurrence(at: 96, in: fixture.lanePoints())?.value,
                       cppID: collisionID, what: "the lane holds the blank slot's number")

    guard let marker = fixture.marker(at: 96) else {
        report.fail(collisionID, "the blank-slot change publishes no marker")
        return
    }
    report.expect(marker.slotBlank, cppID: collisionID,
                  message: "the committed blank slot publishes blank truth")
    report.expectEqual("", marker.symbol, cppID: collisionID,
                       what: "the committed blank slot publishes no symbol")
    report.expectEqual(String(format: "%03d", blankIndex), marker.label, cppID: collisionID,
                       what: "the committed blank slot's label stays its program number")

    fixture.session.editCursor = 96
    report.expect(fixture.page.contextBlank, cppID: collisionID,
                  message: "the readout publishes the blank truth for that context")
    report.expectEqual(String(format: "%03d", blankIndex), fixture.page.readoutText,
                       cppID: collisionID,
                       what: "the readout of a blank context is the program number alone")
}

// MARK: - Audition capability

@MainActor
private func auditionCapability(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService, programs: [Int]) {
    let fixture = VoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    var calls: [[UInt8]] = []
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    let baseline = fixture.snapshot
    let first = UInt8(programs[0])
    let second = UInt8(programs[1])

    func hold(_ program: Int) {
        guard let row = page.pickerRowPrograms.firstIndex(of: program) else {
            report.fail(auditionID, "the audition program is absent from the picker")
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
                       cppID: auditionID, what: "held program replacement releases once before the next note")

    calls.removeAll()
    hold(programs[0])
    page.setPickerFilter(text: "__no_voice_can_match__")
    page.cancelPicker()
    report.expectEqual([[first, 60, 112], [first, 60, 0]], calls,
                       cppID: auditionID, what: "filter invalidation releases the sounding program")

    calls.removeAll()
    _ = page.pointerDoubleClick(x: fixture.markerX(48), y: 10)
    hold(programs[1])
    _ = page.acceptPicker()
    report.expectEqual([[second, 60, 112], [second, 60, 0]], calls,
                       cppID: auditionID, what: "same-value acceptance releases without a musical edit")
    report.expectEqual(baseline, fixture.snapshot, cppID: auditionID,
                       what: "audition, filtering and same-value acceptance leave document/history unchanged")

    calls.removeAll()
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    hold(programs[0])
    _ = page.pointerDoubleClick(x: fixture.markerX(48), y: 10)
    hold(programs[1])
    page.onAuditionVoice = nil
    report.expectEqual([[first, 60, 112], [first, 60, 0],
                        [second, 60, 112], [second, 60, 0]], calls,
                       cppID: auditionID, what: "picker and callback replacement release through the old owner")
    report.expect(!page.auditionAvailable, cppID: auditionID,
                  message: "removing the real callback removes audition availability")

    calls.removeAll()
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    hold(programs[0])
    fixture.session.selectedTrack = 1
    page.releasePickerAudition()
    report.expectEqual([[first, 60, 112], [first, 60, 0]], calls,
                       cppID: auditionID, what: "stale track cancellation releases without a duplicate note-off")
    fixture.session.selectedTrack = 0
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    calls.removeAll()
    hold(programs[1])
    page.cancelSectionInteraction()
    report.expectEqual([[second, 60, 112], [second, 60, 0]], calls,
                       cppID: auditionID, what: "workspace cancellation releases its held voice")
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)

    calls.removeAll()
    page.onAuditionVoice = { calls.append([$0, $1, $2]) }
    hold(programs[0])
    page.detach()
    report.expectEqual([[first, 60, 112], [first, 60, 0]], calls,
                       cppID: auditionID, what: "document teardown releases the final held program")
    report.expectEqual(baseline, fixture.snapshot, cppID: auditionID,
                       what: "picker replacement and teardown write no musical state")
}
