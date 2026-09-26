import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawBankLease

// Direct coverage for the pure Swift Automation domain and its page owner. The
// projection, parameter metadata, snapping and frozen transactions are driven
// with synthetic values; the page owner and every commit path run against a real
// `DocumentSession`, so each transaction claim is a real document-history claim.
//
// Translated legacy intent (`src/checks/automation/`), by observable category:
//
// - `automation-domain/AutomationDomainTest::sweepSteppingAndRampFinish`: the
//   drag sweep steps every lattice tick between its samples and a ramp sweep
//   fills every lattice tick between its anchor and its release;
// - `::sweepFinishRestoresTrailingHeldValue`: drawing over a flat lane re-anchors
//   the original held value one lattice step past the release, for a drag sweep
//   and for a ramp sweep;
// - `::panNeutralSnap`: a value drag inside the neutral radius lands exactly on
//   Pan's neutral 64 and never moves the tick;
// - `::nodeDragAndPhantomOutcomes`: an empty finish is a no-op, a stationary
//   release deletes only without Shift, a stroke past the slop commits once, a
//   multi-node set shares one delta that clamps at tick zero, and a phantom drag
//   restores its source on reset and clamps into the lane's domain;
// - `::pointRangeAndPencilReplacements`: a point-range replacement that matches
//   the lane is unchanged, a held-span replacement restores the boundary
//   endpoint, a flat replacement is unchanged, and an empty replacement deletes;
// - the domain's `effectivePoints`, `rangesAndSelection`, `deletes`, `moves`,
//   `replaceSpans` and `defaultNodePromotion`: the projected point list of a lane
//   (engine default node, held values, same-tick occupants), the parameter
//   catalog and its ranges, one-commit moves and deletes, span replacement, and
//   the promotion of a projected node into a written event;
// - the domain's `xcmd*` rows: XCMD parameters are the same identities through
//   the same lane APIs, with their descriptor labels;
// - `automation-presentation` `parameterLabelsFitGutterAtDerivedMinimum`,
//   `selectedInactiveParametersKeepScopeIndicators`,
//   `laneEventCountsFollowActiveGutterRow` and `laneScaleLabelsRenderAtLeftEdge`:
//   the selector labels, the per-row event counts, the selected inactive
//   parameter indicators, and the min/max/neutral scale labels;
// - `automation-presentation` `parameterLabelClicksSwitchActivePlot`,
//   `tempoUsesFullSharedPlotBody` and `ghostTempoPaintsUnderActiveLane`:
//   switching the active parameter mutates nothing and keeps the explicit
//   selection, Tempo projects through the same plot, and ghosts keep their pins
//   while they carry events;
// - `drawerpresentation` gesture transactions and content-build diagnostics: a
//   gesture previews without mutating, commits one document revision and one
//   history entry, cancels synchronously, and a shared-playhead-only update
//   rebuilds no static content.
//
// Selection clipboard cases exercise the native shared payload; lane-menu copy
// remains an independent absolute tick/value stream, as in the original canvas.

/// The QML modifier flags a check's `AutomationModifiers` stand for, so every
/// case drives the production input route instead of a Swift-only shorthand.
func drawerAutomationQtModifiers(_ modifiers: AutomationModifiers) -> Int {
    (modifiers.shift ? AutomationQtModifier.shift : 0)
        | (modifiers.fine ? AutomationQtModifier.alt : 0)
        | (modifiers.snapValue ? AutomationQtModifier.control : 0)
}

let drawerAutomationCatalogID = "swiftcore/AutomationPage::parameterCatalogAndMetadata"
let drawerAutomationProjectionID = "swiftcore/AutomationPage::laneProjection"
let drawerAutomationIdentityID = "swiftcore/AutomationPage::pointIdentityAndStaleness"
let drawerAutomationLabelsID = "swiftcore/AutomationPage::scaleLabelsAndLaneCounts"
let drawerAutomationRowsID = "swiftcore/AutomationPage::rowStackAndSelectionIndicators"
let drawerAutomationSwitchID = "swiftcore/AutomationPage::parameterSwitchAndGhosts"
let drawerAutomationLayoutID = "swiftcore/AutomationPage::hitGeometry"
let drawerAutomationPromptID = "swiftcore/AutomationPage::promptTransactions"
let drawerAutomationDeleteID = "swiftcore/AutomationPage::deleteTransactions"
let drawerAutomationRangeID = "swiftcore/AutomationPage::rangeEditAndClipboard"
let drawerAutomationHistoryID = "swiftcore/AutomationPage::historyUndoRedo"
let drawerAutomationCancelID = "swiftcore/AutomationPage::cancellationAndNoOps"
let drawerAutomationContextID = "swiftcore/AutomationPage::contextAndPublicationDiagnostics"

// The five reopened exclusion rows, under their legacy domain row ids.
let drawerAutomationSweepStepsID = "automation-domain/AutomationDomainTest::sweepSteppingAndRampFinish"
let drawerAutomationSweepTailID =
    "automation-domain/AutomationDomainTest::sweepFinishRestoresTrailingHeldValue"
let drawerAutomationNeutralSnapID = "automation-domain/AutomationDomainTest::panNeutralSnap"
let drawerAutomationNodeDragID = "automation-domain/AutomationDomainTest::nodeDragAndPhantomOutcomes"
let drawerAutomationPointRangeID =
    "automation-domain/AutomationDomainTest::pointRangeAndPencilReplacements"

// MARK: - Fixture

func drawerAutomationAutomationMidi(division: UInt16 = 24, volume: [(Tick, UInt8)] = [],
                            pan: [(Tick, UInt8)] = [], modulation: [(Tick, UInt8)] = [],
                            echo: [(Tick, UInt8)] = [], tempo: [(Tick, UInt32)] = [(0, 500_000)],
                            endTick: Tick = 192, tailTick: Tick? = nil) -> MidiFile {
    var conductor: [MidiEvent] = tempo.map { tick, microseconds in
        .meta(tick: tick, type: 0x51, data: [UInt8((microseconds >> 16) & 0xFF),
                                             UInt8((microseconds >> 8) & 0xFF),
                                             UInt8(microseconds & 0xFF)])
    }
    conductor.append(.meta(tick: 0, type: 0x58, data: [4, 2, 24, 8]))
    var events: [MidiEvent] = [
        .channel(tick: 0, status: 0x90, data0: 60, data1: 100),
        .channel(tick: 24, status: 0x80, data0: 60),
    ]
    events += volume.map { .channel(tick: $0.0, status: 0xB0, data0: 0x07, data1: $0.1) }
    events += pan.map { .channel(tick: $0.0, status: 0xB0, data0: 0x0A, data1: $0.1) }
    events += modulation.map { .channel(tick: $0.0, status: 0xB0, data0: 0x01, data1: $0.1) }
    // A note ending at the requested tail keeps the document's musical length
    // at least that long, which every lane stroke's restored seam is measured
    // against.
    let resolvedEnd = tailTick ?? endTick
    if let tailTick {
        events.append(.channel(tick: tailTick - 24, status: 0x90, data0: 67, data1: 100))
        events.append(.channel(tick: tailTick, status: 0x80, data0: 67))
    }
    events.sort { $0.tick < $1.tick }
    conductor.sort { $0.tick < $1.tick }
    return MidiFile(division: division, chunks: [
        MidiChunk(events: conductor, endTick: resolvedEnd),
        MidiChunk(events: events, endTick: resolvedEnd),
    ])
}

@MainActor
struct drawerAutomationAutomationFixture {
    let session: DocumentSession
    let page: AutomationPage
    let document: SongDocument

    init(suite: DocumentSession, service: ProjectService, division: UInt16 = 24,
         volume: [(Tick, UInt8)] = [], pan: [(Tick, UInt8)] = [],
         modulation: [(Tick, UInt8)] = [], echo: [(Tick, UInt8)] = [],
         tempo: [(Tick, UInt32)] = [(0, 500_000)], baseFontPx: Double = 13,
         plotted: Bool = true, config: SongConfig? = nil, tailTick: Tick? = 576) {
        let document = SongDocument(
            file: drawerAutomationAutomationMidi(division: division, volume: volume, pan: pan,
                                 modulation: modulation, echo: echo, tempo: tempo,
                                 tailTick: tailTick),
            config: config ?? suite.document.state.config, source: suite.document.source,
            trackBudget: suite.document.trackBudget)
        let session = DocumentSession(document: document, service: service,
                                      lease: suite.bankLease, slots: suite.bankSlots,
                                      dirty: false, loadName: suite.bankLoadName,
                                      sampleRate: 48_000)
        if !echo.isEmpty {
            // XCMD lanes are selector/payload traffic, not raw controller
            // events: they are written through the document's own lane API.
            document.writeLane(track: 0, lane: .controller(Xcmd.echoVolumeLane), from: 0,
                               through: TimeDefaults.noTick,
                               points: echo.map { LaneWrite(tick: $0.0, value: Int($0.1)) })
        }
        session.selectedTrack = 0
        self.session = session
        self.document = document
        page = AutomationPage(baseFontPx: baseFontPx)
        page.attach(session: session, palette: GridPalette())
        if plotted {
            page.configureBody(width: 480, height: 120, gutter: 0, devicePixelRatio: 1,
                               baseFontPx: baseFontPx, dragDistance: 10)
        }
        session.onChange = { [weak page] change in
            let content: SessionChangeDomains = [.document, .bank]
            if !change.domains.intersection(content).isEmpty {
                page?.refreshFromDocument()
            } else if change.domains.contains(.cursor) {
                page?.refreshEditCursor()
            }
        }
        session.onCameraChange = { [weak page] _ in page?.refreshCamera() }
    }

    var snapshot: DocumentSnapshot { DocumentSnapshot(document) }
    var songEndTick: Tick { session.timeline.lengthTicks }
    var volumeLane: AutomationParameter {
        .controlChange(track: 0, controller: TimeDefaults.ccVolume)
    }
    var panLane: AutomationParameter { .controlChange(track: 0, controller: TimeDefaults.ccPan) }
    var modulationLane: AutomationParameter {
        .controlChange(track: 0, controller: TimeDefaults.ccModulation)
    }
    var bendLane: AutomationParameter { .pitchBend(track: 0) }
    var echoLane: AutomationParameter { .controlChange(track: 0, controller: Xcmd.echoVolumeLane) }

    func lanePoints(_ parameter: AutomationParameter) -> [LanePoint] {
        guard let track = parameter.track, let lane = parameter.lane else { return [] }
        return document.lanePoints(track: track, lane: lane)
    }

    func values(_ parameter: AutomationParameter) -> [String] {
        lanePoints(parameter).map { "\($0.tick):\($0.value)" }
    }

    func laneValues(_ values: [AutomationLanePoint]) -> [String] {
        values.map { "\($0.tick):\($0.value)" }
    }

    var tempoValues: [String] {
        document.state.tempo.map { point in
            let bpm = Int(TimeDefaults.tempoBPM(
                forMicrosecondsPerQuarterNote: point.microsecondsPerQuarterNote).rounded())
            return "\(point.tick):\(bpm)"
        }
    }

    func laneSnapshot(_ parameter: AutomationParameter) -> AutomationLaneSnapshot {
        AutomationLaneSnapshot(parameter: parameter, in: document, songEndTick: songEndTick)
    }

    /// The frozen facts of one parameter at the current revision, exactly as a
    /// press freezes them.
    func facts(_ parameter: AutomationParameter,
               modifiers: AutomationModifiers = .init()) -> AutomationFrozenFacts {
        AutomationFrozenFacts(parameter: parameter, snapshot: laneSnapshot(parameter),
                              camera: session.camera.snapshot, selection: page.selection,
                              modifiers: modifiers, songEndTick: songEndTick)
    }

    func makeProjection(_ parameter: AutomationParameter,
                        selection: AutomationTimeSelection? = nil,
                        width: Double = 480, height: Double = 120) -> AutomationLaneProjection {
        let facts = facts(parameter)
        let projection = AutomationProjection(
            camera: session.camera,
            bounds: AutomationPlotBounds(width: width, height: height, devicePixelRatio: 1),
            geometry: page.geometry,
            snapPolicy: AutomationProjectionCache().snapPolicy(session: session, font: page.baseFontPx, dpr: 1),
            songEndTick: songEndTick)
        return projection.project(facts.snapshot, selection: selection,
                                  usedTracks: Set(0..<document.engineTracks.usedTrackCount))
    }

    func projection(_ parameter: AutomationParameter) -> AutomationLaneProjection {
        makeProjection(parameter)
    }

    /// Plot-local x of one tick through the shared camera.
    func x(_ tick: Tick) -> Double { session.camera.contentX(tick: Double(tick)) }

    /// Plot-local y of one value through the page's own geometry.
    func y(_ parameter: AutomationParameter, _ value: Int) -> Double {
        let projection = AutomationProjection(
            camera: session.camera,
            bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
            geometry: page.geometry,
            snapPolicy: AutomationProjectionCache().snapPolicy(session: session, font: page.baseFontPx, dpr: 1),
            songEndTick: songEndTick)
        return projection.y(value, metadata: AutomationParameterMetadata(parameter: parameter))
    }

    func activate(_ parameter: AutomationParameter) {
        _ = page.activateParameter(index: AutomationCatalog.index(of: parameter, track: 0) ?? 0)
    }

    func undo() -> Bool { (try? runBlocking { try await session.undo() }) ?? false }

    /// One node drag through the page's public pointer route, in plot
    /// coordinates, carrying the raw Qt modifier bits a QML event supplies. The
    /// pointer arms the drag with a travel past the activation distance and then
    /// settles, so the drag's own delta lands the mapped value on `target` while
    /// the tick keeps the press's column; `true` means the press itself was
    /// taken. A release's return value is the commit's outcome, so a caller
    /// asserts the lane it produced.
    @discardableResult
    func drag(_ parameter: AutomationParameter, from: (tick: Tick, value: Int),
              to target: Int, armPixels: Double = 30, modifiers: Int) -> Bool {
        let surface = AutomationInputSurface.plot.rawValue
        let button = AutomationQtButton.left
        let pressX = x(from.tick)
        let pressY = y(parameter, from.value)
        let targetY = y(parameter, target)
        let pressed = page.pointerPress(x: pressX, y: pressY, surface: surface, button: button,
                                        modifiers: modifiers)
        let armY = pressY - armPixels
        _ = page.pointerMove(x: pressX, y: armY, buttons: button, modifiers: modifiers)
        _ = page.pointerMove(x: pressX, y: armY + (targetY - pressY), buttons: button,
                             modifiers: modifiers)
        _ = page.pointerRelease(x: pressX, y: armY + (targetY - pressY), button: button,
                                modifiers: modifiers)
        return pressed
    }
}

// MARK: - Suite entry

/// Preserves only the canonical Porydaw selection MIME within the offscreen lane.
final class drawerAutomationPorydawSelectionClipboardState {
    private var bytes: Data?

    init() {
        _ = pd_clipboard_read(Unmanaged.passUnretained(self).toOpaque()) { context, bytes, count in
            guard let context, let bytes else { return }
            Unmanaged<drawerAutomationPorydawSelectionClipboardState>.fromOpaque(context)
                .takeUnretainedValue().bytes = Data(bytes: bytes, count: count)
        }
    }

    func restore() {
        guard let bytes else {
            _ = pd_clipboard_write(nil, 0)
            return
        }
        bytes.withUnsafeBytes {
            _ = pd_clipboard_write($0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
    }
}

@MainActor
internal func runAutomationPageChecks(_ report: CheckReport, session: DocumentSession,
                                      service: ProjectService) {
    let clipboardState = drawerAutomationPorydawSelectionClipboardState()
    defer { clipboardState.restore() }
    drawerAutomationParameterCatalogAndMetadata(report)
    drawerAutomationLaneProjection(report, suite: session, service: service)
    drawerAutomationPointIdentityAndStaleness(report, suite: session, service: service)
    drawerAutomationScaleLabelsAndLaneCounts(report, suite: session, service: service)
    drawerAutomationRowStackAndSelectionIndicators(report, suite: session, service: service)
    drawerAutomationPresentationPaintingModel(report, suite: session, service: service)
    drawerAutomationParameterSwitchAndGhosts(report, suite: session, service: service)
    drawerAutomationPencilCursorKind(report, suite: session, service: service)
    drawerAutomationHitGeometry(report, suite: session, service: service)
    drawerAutomationPromptTransactions(report, suite: session, service: service)
    drawerAutomationPointMenuDeleteAndStale(report, suite: session, service: service)
    drawerAutomationDuplicatePromptAndParameterSwitch(report, suite: session, service: service)
    drawerAutomationLaneDeleteConfirmation(report, suite: session, service: service)
    drawerAutomationOutsidePressRetarget(report, suite: session, service: service)
    drawerAutomationDeleteTransactions(report, suite: session, service: service)
    drawerAutomationRangeEditAndClipboard(report, suite: session, service: service)
    drawerAutomationCrossLanePasteClamps(report, suite: session, service: service)
    drawerAutomationCancellationAndNoOps(report, suite: session, service: service)
    drawerAutomationInflightDragInvalidation(report, suite: session, service: service)
    drawerAutomationKeyboardIngress(report, suite: session, service: service)
    drawerAutomationBandEscape(report, suite: session, service: service)
    drawerAutomationHistoryUndoRedo(report, suite: session, service: service)
    drawerAutomationHoverModel(report, suite: session, service: service)
    drawerAutomationMenuHintMuting(report, suite: session, service: service)
    drawerAutomationHoverResidual(report, suite: session, service: service)
    drawerAutomationContextAndPublicationDiagnostics(report, suite: session, service: service)
    drawerAutomationSweepSteppingAndRampFinish(report, suite: session, service: service)
    drawerAutomationSweepFinishRestoresTrailingHeldValue(report, suite: session, service: service)
    drawerAutomationPanNeutralSnap(report, suite: session, service: service)
    drawerAutomationNodeDragAndPhantomOutcomes(report, suite: session, service: service)
    drawerAutomationPointRangeAndPencilReplacements(report, suite: session, service: service)
    drawerAutomationPencilStrokeFilters(report, suite: session, service: service)
    drawerAutomationPencilStrokeModifiers(report, suite: session, service: service)
    drawerAutomationGestureContractParity(report, suite: session, service: service)
    drawerAutomationXcmdParity(report, suite: session, service: service)
    drawerAutomationXcmdLaneEdits(report)
    drawerAutomationTapTempoCadenceAndCommit(report, suite: session, service: service)
    drawerAutomationTapTempoStrayAndEmptyStream(report, suite: session, service: service)
    drawerAutomationQtModifierMapping(report, suite: session, service: service)
    drawerAutomationProjectionValueBounds(report, suite: session, service: service)
    drawerAutomationRestoredInteractionContracts(report, suite: session, service: service)
    drawerAutomationBandIsolatesTempoAndCc(report, suite: session, service: service)
    drawerAutomationMultiCcDragExcludesOthers(report, suite: session, service: service)
    drawerAutomationSelectionDeleteCommand(report, suite: session, service: service)
    drawerAutomationGhostViewOnlyAndSurvives(report, suite: session, service: service)
    drawerAutomationPencilOwnershipAndShift(report, suite: session, service: service)
    drawerAutomationDetailThresholdPrecedence(report, suite: session, service: service)
    drawerAutomationTempoBendClickRestore(report, suite: session, service: service)
    drawerAutomationMiddlePanIsolation(report, suite: session, service: service)
    drawerAutomationViewStatePreservation(report, suite: session, service: service)
    drawerAutomationOriginalClearMenus(report, suite: session, service: service)
    drawerAutomationOriginalRangeMenu(report, suite: session, service: service)
    drawerAutomationLegacyResolverRows(report, camera: session.camera.snapshot)
    drawerAutomationLegacyMetadataRows(report, camera: session.camera.snapshot)
    drawerAutomationLegacyDefaultPromotion(report, camera: session.camera.snapshot)
    drawerAutomationLegacySpanRows(report, camera: session.camera.snapshot)
    do {
        try runBlocking {
            try await coreAutomationPanUndoRegression(report, suite: session, service: service)
        }
    } catch {
        report.fail("swiftcore/Automation::supplementalAwaitedPanUndo", "history regression failed: \(error)")
    }
}


let drawerAutomationTapTempoID = "swiftcore/AutomationPage::tapTempoCadenceAndCommit"
let drawerAutomationModifierMappingID = "swiftcore/AutomationPage::qtModifierMapping"

/// The pure tap-tempo session and the page's captured commit. A fixed cadence
/// averages over the newest intervals only, a gap past the production distance
/// starts a fresh session, and the idle window records exactly one tempo edit
/// and one history entry — or nothing at all for a stale capture, a moved
/// parameter and a draft that names the tempo already in place.


/// The Qt modifier bits QML carries and the policy they arm, both directions,
/// plus one real pointer route driven by the raw bits a QML event supplies.
