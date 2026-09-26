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

let drawerVoiceProjectionID = "swiftcore/VoiceChangesPage::markerProjection"
let drawerVoiceLabelID = "swiftcore/VoiceChangesPage::slotLabelsAndBlankSlots"
let drawerVoiceContextID = "swiftcore/VoiceChangesPage::currentVoiceContext"
let drawerVoiceIdentityID = "swiftcore/VoiceChangesPage::occurrenceIdentity"
let drawerVoiceInsertionID = "swiftcore/VoiceChangesPage::pickerInsertion"
let drawerVoiceReplacementID = "swiftcore/VoiceChangesPage::pickerValueReplacement"
let drawerVoiceMoveID = "swiftcore/VoiceChangesPage::markerDragTransactions"
let drawerVoiceMenuID = "swiftcore/VoiceChangesPage::contextMenuTransactions"
let drawerVoiceKeyboardID = "swiftcore/VoiceChangesPage::pickerKeyboardPolicy"
let drawerVoiceCancellationID = "swiftcore/VoiceChangesPage::cancellationPaths"
let drawerVoiceHistoryID = "swiftcore/VoiceChangesPage::undoRedoRefresh"
let drawerVoiceDiagnosticsID = "swiftcore/VoiceChangesPage::playheadDiagnostics"
let drawerVoiceAuditionID = "swiftcore/VoiceChangesPage::auditionCapability"
let drawerVoiceFineSnapID = "swiftcore/VoiceChangesPage::altFineClockLattice"
let drawerVoiceCollisionID = "swiftcore/VoiceChangesPage::collisionAndBlankSlotCommit"

// MARK: - Fixture

/// A synthetic song whose primary track opens on `programs[0]` and changes voice
/// at ticks 48 and 120, plus a second track for the track-switch cases. Every
/// program names a real editable slot of the suite's bank, so the labels the
/// page publishes are the project's own.
func drawerVoiceVoiceChangesPageFixture(programs: [Int], division: UInt16 = 24) -> MidiFile {
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

/// The page attached to its own synthetic session over the suite's service and
/// bank, plus the composition facts the page needs to project at all.
@MainActor
struct drawerVoiceVoiceChangesFixture {
    let session: DocumentSession
    let page: VoiceChangesPage
    let document: SongDocument

    init(suite: DocumentSession, service: ProjectService, programs: [Int],
         division: UInt16 = 24, baseFontPx: Double = 13) {
        let document = SongDocument(file: drawerVoiceVoiceChangesPageFixture(programs: programs,
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

    var snapshot: DocumentSnapshot { DocumentSnapshot(document) }

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

// MARK: - Suite entry

@MainActor
internal func runVoiceChangesPageChecks(_ report: CheckReport, session _: DocumentSession,
                                        service _: ProjectService) {
    guard let fixtureRoot = CheckEnvironment.fixtureRoot else {
        report.fail(drawerVoiceProjectionID, "the staged rich bank fixture is unavailable")
        return
    }
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("swiftcore-voice-rich-\(UUID().uuidString)", isDirectory: true)
    let service = ProjectService()
    defer {
        do {
            try runBlocking { await service.close() }
        } catch {
            report.fail(drawerVoiceProjectionID, "could not close the rich bank fixture: \(error)")
        }
        try? FileManager.default.removeItem(at: scratch)
    }
    let session: DocumentSession
    do {
        try FileManager.default.copyItem(at: URL(filePath: fixtureRoot), to: scratch)
        try runBlocking { try await service.open(root: scratch.path) }
        let loaded = try runBlocking { try await service.openSong(label: "mus_gym") }
        let document = SongDocument(file: drawerVoiceVoiceChangesPageFixture(programs: [0, 1, 2]),
                                    config: loaded.config, source: loaded.source,
                                    trackBudget: loaded.trackBudget)
        session = DocumentSession(document: document, service: service,
                                  lease: loaded.bank, slots: loaded.bankSlots,
                                  dirty: loaded.bankDirty, loadName: loaded.bankLoadName)
    } catch {
        report.fail(drawerVoiceProjectionID, "could not load the rich bank fixture: \(error)")
        return
    }
    let editable = session.bankSlots.indices.filter { session.bankSlots[$0].voice != nil }
    let namedCount = editable.filter { !(session.bankSlots[$0].voice?.symbol.isEmpty ?? true) }.count
    guard editable.count >= 3 && namedCount > 0 else {
        report.fail(drawerVoiceProjectionID,
                    "the staged bank exposes \(editable.count) parsed slots and \(namedCount) named "
                    + "editable slots; the Voice Changes cases need three parsed and one named")
        return
    }
    let programs = [editable[0], editable[1], editable[2]]
    drawerVoiceMarkerProjection(report, suite: session, service: service, programs: programs)
    drawerVoiceSlotLabels(report, session: session, service: service, programs: programs)
    drawerVoiceCurrentVoiceContext(report, suite: session, service: service, programs: programs)
    drawerVoiceOccurrenceIdentity(report, suite: session, service: service, programs: programs)
    drawerVoicePickerInsertion(report, suite: session, service: service, programs: programs)
    drawerVoicePickerReattachment(report, suite: session, service: service, programs: programs)
    drawerVoiceOriginalPickerRows(report, suite: session, service: service)
    drawerVoicePickerValueReplacement(report, suite: session, service: service, programs: programs)
    drawerVoiceMarkerDragTransactions(report, suite: session, service: service, programs: programs)
    drawerVoiceContextMenuTransactions(report, suite: session, service: service, programs: programs)
    drawerVoiceScrolledMenuPick(report, suite: session, service: service, programs: programs)
    drawerVoiceOriginalMenuTransactions(report, suite: session, service: service)
    drawerVoicePickerKeyboardPolicy(report, suite: session, service: service, programs: programs)
    drawerVoiceCancellationPaths(report, suite: session, service: service, programs: programs)
    drawerVoiceUndoRedoRefresh(report, suite: session, service: service, programs: programs)
    drawerVoicePlayheadDiagnostics(report, suite: session, service: service, programs: programs)
    drawerVoiceHoverAndBankRefresh(report, suite: session, service: service, programs: programs)
    drawerVoiceAltFineClockLattice(report, suite: session, service: service, programs: programs)
    drawerVoiceCollisionDragOutcome(report, suite: session, service: service, programs: programs)
    drawerVoiceBlankSlotCommit(report, suite: session, service: service, programs: programs)
    drawerVoiceAuditionCapability(report, suite: session, service: service, programs: programs)
}
