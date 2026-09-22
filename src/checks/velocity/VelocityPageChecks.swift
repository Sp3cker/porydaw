import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

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

let drawerVelocityAxisID = "swiftcore/VelocityPage::valueAxisLadder"
let drawerVelocityPsgID = "swiftcore/VelocityPage::psgIntrinsicRows"
let drawerVelocityContextID = "swiftcore/VelocityPage::voiceContextResolution"
let drawerVelocityKeysplitID = "swiftcore/VelocityPage::keysplitPerNoteMapping"
let drawerVelocityProjectionID = "swiftcore/VelocityPage::handleProjection"
let drawerVelocityGestureID = "swiftcore/VelocityPage::frozenGesturePolicy"
let drawerVelocityTransactionID = "swiftcore/VelocityPage::gestureTransactions"
let drawerVelocityPromptID = "swiftcore/VelocityPage::promptTransaction"
let drawerVelocityCancellationID = "swiftcore/VelocityPage::cancellationPaths"
let drawerVelocityDiagnosticsID = "swiftcore/VelocityPage::playheadDiagnostics"
let drawerVelocityCommandID = "swiftcore/VelocityPage::commandAvailabilityAndRoute"
let drawerVelocityHistoryID = "swiftcore/VelocityPage::undoRedoRefresh"
let drawerVelocitySceneID = "swiftcore/VelocityPage::plainValueScene"
let drawerVelocityModelSyncID = "swiftcore/VelocityPage::valueRowModelSync"
let drawerVelocityExactClicksID = "swiftcore/VelocityPage::exactClickSequences"

// MARK: - Synthetic fixture

/// A synthetic song with a square-1 opening program and a voice change to noise
/// at tick 96, over the suite's real bank lease and slots.
func drawerVelocityVelocityPageFixture() -> MidiFile {
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
struct drawerVelocityDocumentSnapshot: Equatable {
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
struct drawerVelocityVelocityFixture {
    let session: DocumentSession
    let page: VelocityPage
    let document: SongDocument
    let notes: [Note]

    init(session suite: DocumentSession, service: ProjectService,
         baseFontPx: Double = 13) {
        let document = SongDocument(file: drawerVelocityVelocityPageFixture(),
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

    var handles: [VelocityHandleValue] { page.publishedHandlesSnapshot }

    func handle(_ note: Note) -> VelocityHandleValue? {
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
func drawerVelocityRunBlocking<T>(_ operation: @escaping @MainActor () async throws -> T) throws -> T {
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
        if Date() > deadline { throw drawerVelocityRunBlockingTimeout.timeout }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    return try outcome!.get()
}

enum drawerVelocityRunBlockingTimeout: Error {
    case timeout
}

// MARK: - Suite entry

@MainActor
internal func runVelocityPageChecks(_ report: CheckReport, session: DocumentSession,
                                    service: ProjectService) {
    drawerVelocityValueAxisLadder(report)
    drawerVelocityPsgIntrinsicRows(report)
    drawerVelocityPlainScene(report, session: session, service: service)
    drawerVelocityValueRowModelSync(report)
    drawerVelocityVoiceContextResolution(report, session: session)
    drawerVelocityFrozenGesturePolicy(report, session: session, service: service)
    drawerVelocityGestureTransactions(report, session: session, service: service)
    drawerVelocityExactClickSequences(report, session: session, service: service)
    drawerVelocityPromptTransaction(report, session: session, service: service)
    drawerVelocityKeysplitPerNoteMapping(report, session: session, service: service)
    drawerVelocityProjectionRefresh(report, session: session, service: service)
    drawerVelocityVoiceContextInvalidation(report, session: session, service: service)
    drawerVelocityPlayheadDiagnostics(report, session: session, service: service)
    drawerVelocityCommandAvailability(report, session: session, service: service)
}


// Camera-only refresh must update both the rendered model and hit geometry;
// document refresh must discard the raw-note cache after an edit and undo.


@MainActor
func drawerVelocityCommandAvailability(_ report: CheckReport, session: DocumentSession,
                                 service: ProjectService) {
    let fixture = drawerVelocityVelocityFixture(session: session, service: service)
    let grid = PianoGrid(session: fixture.session)
    let setVelocity = EditCommand.setVelocity.rawValue
    report.expect(!grid.commandAvailable(command: setVelocity), cppID: drawerVelocityCommandID,
                  message: "Set Velocity is unavailable with no selection")

    var requested = 0
    var page: VelocityPage?
    grid.onSetVelocityRequested = {
        requested += 1
        return page?.openSelectedVelocityPrompt() ?? false
    }
    let document = fixture.document
    let baseline = drawerVelocityDocumentSnapshot(document)

    fixture.session.setSelectedNotes([fixture.notes[0].id])
    grid.setEditCursorTick(tick: Int(fixture.session.editCursor))
    report.expect(grid.commandAvailable(command: setVelocity), cppID: drawerVelocityCommandID,
                  message: "Set Velocity becomes available with a selection")

    grid.performCommand(command: setVelocity)
    report.expectEqual(1, requested, cppID: drawerVelocityCommandID,
                       what: "the existing command row asks its owner for the prompt")
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityCommandID,
                  message: "the command commits no value before prompt acceptance")

    page = fixture.page
    grid.performCommand(command: setVelocity)
    report.expectEqual(2, requested, cppID: drawerVelocityCommandID,
                       what: "the command routes every execution through the same owner")
    report.expect(fixture.page.promptOpen, cppID: drawerVelocityCommandID,
                  message: "the routed command opened the page's captured prompt")
    fixture.page.cancelPrompt()
    report.expect(drawerVelocityDocumentSnapshot(document) == baseline, cppID: drawerVelocityCommandID,
                  message: "cancelling the routed prompt still commits nothing")

    let row = editCommandTable.first { $0.command == .setVelocity }
    report.expectEqual(EditNotesOperation.setVelocity.rawValue,
                       row?.notesOperation.rawValue ?? -1, cppID: drawerVelocityCommandID,
                       what: "the command table keeps Set Velocity on the notes arm")
    report.expectEqual(EditKeyRoute.alwaysConsume.rawValue, row?.keyRoute.rawValue ?? -1,
                       cppID: drawerVelocityCommandID,
                       what: "the command table keeps Set Velocity's consume route")
}

@MainActor
func drawerVelocityValueRowModelSync(_ report: CheckReport) {
    var first = VelocityHandleValue()
    first.noteID = NoteID(1)
    first.noteIdText = "1"
    first.value = 32
    var second = VelocityHandleValue()
    second.noteID = NoteID(2)
    second.noteIdText = "2"
    second.value = 64

    let model = QListModel<VelocityHandle>()
    var previous: [VelocityHandleValue] = []
    syncModel(model, previous: &previous, [first, second], makeRow: VelocityHandle.init)
    let firstObject = model[0]
    let secondObject = model[1]

    syncModel(model, previous: &previous, [first, second], makeRow: VelocityHandle.init)
    report.expect(model[0] === firstObject && model[1] === secondObject,
                  cppID: drawerVelocityModelSyncID,
                  message: "equal plain rows allocate and publish nothing")

    var changed = second
    changed.value = 96
    syncModel(model, previous: &previous, [first, changed], makeRow: VelocityHandle.init)
    report.expect(model[0] === firstObject && model[1] !== secondObject,
                  cppID: drawerVelocityModelSyncID,
                  message: "a changed descriptor replaces only its positional row")
    report.expectEqual(96, model[1].value, cppID: drawerVelocityModelSyncID,
                       what: "the changed QListModel row publishes its new value")

    var third = VelocityHandleValue()
    third.noteID = NoteID(3)
    third.noteIdText = "3"
    syncModel(model, previous: &previous, [first, changed, third],
              makeRow: VelocityHandle.init)
    report.expectEqual(3, model.count, cppID: drawerVelocityModelSyncID,
                       what: "a descriptor tail inserts through QListModel")
    report.expect(model[0] === firstObject, cppID: drawerVelocityModelSyncID,
                  message: "tail insertion preserves the common positional prefix")

    syncModel(model, previous: &previous, [first], makeRow: VelocityHandle.init)
    report.expectEqual(1, model.count, cppID: drawerVelocityModelSyncID,
                       what: "a removed descriptor tail removes QListModel rows")
    report.expect(model[0] === firstObject, cppID: drawerVelocityModelSyncID,
                  message: "tail removal preserves the remaining row instance")
}
