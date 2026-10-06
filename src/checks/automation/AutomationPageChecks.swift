import Foundation
@testable import PorydawApp
@testable import PorydawAppPresentation
import PorydawCore
@testable import PorydawDocument
import PorydawNativeHost

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

// MARK: - Suite entry

/// Preserves only the canonical Porydaw selection MIME within the offscreen lane.
public final class drawerAutomationPorydawSelectionClipboardState {
    private var bytes: Data?

    public init() {
        _ = pd_clipboard_read(Unmanaged.passUnretained(self).toOpaque()) { context, bytes, count in
            guard let context, let bytes else { return }
            Unmanaged<drawerAutomationPorydawSelectionClipboardState>.fromOpaque(context)
                .takeUnretainedValue().bytes = Data(bytes: bytes, count: count)
        }
    }

    public func restore() {
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
public func runAutomationPageChecks(
    _ report: CheckReport, viewport: DocumentViewport,
    service: ProjectService
) {
    let session = viewport.session
    let clipboardState = drawerAutomationPorydawSelectionClipboardState()
    defer { clipboardState.restore() }
    drawerAutomationParameterCatalogAndMetadata(report)
    drawerAutomationLaneProjection(report, suite: session, service: service)
    drawerAutomationDrawingContentChecks(report, suite: session, service: service)
    drawerAutomationDrawPreviewChecks(report, suite: session, service: service)
    drawerAutomationPointIdentityAndStaleness(report, suite: session, service: service)
    drawerAutomationScaleLabelsAndLaneCounts(report, suite: session, service: service)
    drawerAutomationRowStackAndSelectionIndicators(report, suite: session, service: service)
    drawerAutomationPresentationPaintingModel(report, suite: session, service: service)
    drawerAutomationRasterHalfOpenGeometry(report, suite: session, service: service)
    drawerAutomationRasterScrolledPhantom(report, suite: session, service: service)
    drawerAutomationParameterSwitchAndGhosts(report, suite: session, service: service)
    drawerAutomationPencilCursorKind(report, suite: session, service: service)
    drawerAutomationHitGeometry(report, suite: session, service: service)
    drawerAutomationTempoPromptInsertion(report, suite: session, service: service)
    drawerAutomationPromptTransactions(report, suite: session, service: service)
    drawerAutomationPointMenuDeleteAndStale(report, suite: session, service: service)
    drawerAutomationSharedPopupArbitration(report, suite: session, service: service)
    drawerAutomationDuplicatePromptAndParameterSwitch(report, suite: session, service: service)
    drawerAutomationLaneDeleteConfirmation(report, suite: session, service: service)
    drawerAutomationOutsidePressRetarget(report, suite: session, service: service)
    drawerAutomationSelectionInvalidation(report, suite: session, service: service)
    drawerAutomationTrackSwitchInvalidation(report, suite: session, service: service)
    drawerAutomationDeleteTransactions(report, suite: session, service: service)
    drawerAutomationRangeEditAndClipboard(report, suite: session, service: service)
    drawerAutomationTrackScopedSelectionClipboard(report, suite: session, service: service)
    drawerAutomationCrossLanePasteClamps(report, suite: session, service: service)
    drawerAutomationCancellationAndNoOps(report, suite: session, service: service)
    drawerAutomationInflightDragInvalidation(report, suite: session, service: service)
    drawerAutomationKeyboardIngress(report, suite: session, service: service)
    drawerAutomationBandEscape(report, suite: session, service: service)
    drawerAutomationHistoryUndoRedo(report, suite: session, service: service)
    drawerAutomationCcPointerDragPlayback(report, suite: session, service: service)
    drawerAutomationHoverModel(report, suite: session, service: service)
    drawerAutomationGhostRightClickPrompt(report, suite: session, service: service)
    drawerAutomationMenuHintMuting(report, suite: session, service: service)
    drawerAutomationHoverResidual(report, suite: session, service: service)
    drawerAutomationFocusLossRetainsGesture(report, suite: session, service: service)
    drawerAutomationFocusLossKeepsPress(report, suite: session, service: service)
    drawerAutomationContextAndPublicationDiagnostics(report, suite: session, service: service)
    drawerAutomationSweepSteppingAndRampFinish(report, suite: session, service: service)
    drawerAutomationSweepFinishRestoresTrailingHeldValue(report, suite: session, service: service)
    drawerAutomationShiftRampEndpoints(report, suite: session, service: service)
    drawerAutomationPanNeutralSnap(report, suite: session, service: service)
    drawerAutomationNodeDragAndPhantomOutcomes(report, suite: session, service: service)
    drawerAutomationPointRangeAndPencilReplacements(report, suite: session, service: service)
    drawerAutomationEmptyLanePencilCommit(report, suite: session, service: service)
    drawerAutomationPencilStrokeFilters(report, suite: session, service: service)
    drawerAutomationPencilStrokeModifiers(report, suite: session, service: service)
    drawerAutomationGestureContractParity(report, suite: session, service: service)
    drawerAutomationStagedGestureSnapshots(report, suite: session, service: service)
    drawerAutomationCompletedGestureOneEditLaw(report, suite: session, service: service)
    drawerAutomationParkedGestureUnchangedLaw(report, suite: session, service: service)
    drawerAutomationXcmdParity(report, suite: session, service: service)
    drawerAutomationXcmdLaneEdits(report)
    drawerAutomationTapTempoCadenceAndCommit(report, suite: session, service: service)
    drawerAutomationTapTempoForkBoundaries(report, suite: session, service: service)
    drawerAutomationTapHintCatalog(report)
    drawerAutomationTapTempoStrayAndEmptyStream(report, suite: session, service: service)
    drawerAutomationQtModifierMapping(report, suite: session, service: service)
    drawerAutomationProjectionValueBounds(report, suite: session, service: service)
    drawerAutomationRestoredInteractionContracts(report, suite: session, service: service)
    drawerAutomationBandIsolatesTempoAndCc(report, suite: session, service: service)
    drawerAutomationMultiCcDragExcludesOthers(report, suite: session, service: service)
    drawerAutomationSelectionDeleteCommand(report, suite: session, service: service)
    drawerAutomationTempoOnlyHorizontalPlayback(report, suite: session, service: service)
    drawerAutomationMixedSelectionDragPlayback(report, suite: session, service: service)
    drawerAutomationMixedSelectionHoverSnapshot(report, suite: session, service: service)
    drawerAutomationMixedDragTempoRow(report, suite: session, service: service)
    drawerAutomationMixedSelectionDeletePlayback(report, suite: session, service: service)
    drawerAutomationMixedDragRebuildCancellation(report, suite: session, service: service)
    drawerAutomationCcOnlyExactIntervalDrag(report, suite: session, service: service)
    drawerAutomationGhostViewOnlyAndSurvives(report, suite: session, service: service)
    drawerAutomationPencilOwnershipAndShift(report, suite: session, service: service)
    drawerAutomationDetailThresholdPrecedence(report, suite: session, service: service)
    drawerAutomationTempoBendClickRestore(report, suite: session, service: service)
    drawerAutomationMiddlePanIsolation(report, suite: session, service: service)
    drawerAutomationViewStatePreservation(report, suite: session, service: service)
    drawerAutomationOriginalClearMenus(report, suite: session, service: service)
    drawerAutomationOriginalRangeMenu(report, suite: session, service: service)
    drawerAutomationLegacyResolverRows(report, camera: viewport.camera.snapshot)
    drawerAutomationLegacyMetadataRows(report, camera: viewport.camera.snapshot)
    drawerAutomationLegacyDefaultPromotion(report, camera: viewport.camera.snapshot)
    drawerAutomationLegacySpanRows(report, camera: viewport.camera.snapshot)
    do {
        try runBlocking {
            try await coreAutomationPanUndoRegression(report, suite: session, service: service)
        }
    } catch {
        report.fail("swiftcore/Automation::supplementalAwaitedPanUndo", "history regression failed: \(error)")
    }
}

@MainActor
func drawerAutomationTapHintCatalog(_ report: CheckReport) {
    let id = "swiftcore/AutomationPage::tapHintCatalog"
    let hints = MouseHints()
    let token = hints.allocateSourceToken()
    hints.setWindowActive(active: true)
    hints.claim(sourceToken: token, profile: 27)
    let tap = hints.text
    report.expect(
        !tap.isEmpty, cppID: id,
        message: "the tap hint publishes its catalog text")
    hints.claim(sourceToken: token, profile: 25)
    report.expect(
        !hints.text.isEmpty && hints.text != tap, cppID: id,
        message: "the tap and ghost hints stay distinct")
}

@MainActor
func drawerAutomationTempoPromptInsertion(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::tempoPromptInsertion"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service)
    fixture.activate(.tempo)
    let before = fixture.snapshot
    let originalTempo = fixture.tempoValues
    let undoCount = fixture.document.history.undoCount
    report.expect(
        fixture.page.openPrompt(tick: 96, value: 120)
            && fixture.page.promptOpen && fixture.snapshot == before, cppID: id,
        message: "the tempo insertion prompt opens without a write")
    report.expect(
        fixture.page.promptTitle == "Set tempo"
            && fixture.page.promptLabel == "BPM:"
            && fixture.page.promptMinimum == TimeDefaults.minimumTempoBPM
            && fixture.page.promptMaximum == TimeDefaults.maximumTempoBPM
            && fixture.page.promptDraft == "120", cppID: id,
        message: "the tempo insertion prompt publishes its displayed domain")
    report.expect(
        fixture.page.acceptPrompt(displayedValue: 90)
            && fixture.tempoValues.contains("96:90")
            && fixture.document.revision == before.revision + 1
            && fixture.document.history.undoCount == undoCount + 1
            && fixture.document.history.canUndo, cppID: id,
        message: "the typed tempo draft commits at the prompt's tick")
    let undone = fixture.undo()
    report.expect(
        undone && fixture.tempoValues == originalTempo, cppID: id,
        message: "undo restores the pre-insertion tempo")
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
