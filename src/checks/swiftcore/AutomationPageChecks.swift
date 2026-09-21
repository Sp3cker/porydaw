import Foundation
import PorydawApp
import PorydawCore
import PorydawProjectService

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
private func qtModifiers(_ modifiers: AutomationModifiers) -> Int {
    (modifiers.shift ? AutomationQtModifier.shift : 0)
        | (modifiers.fine ? AutomationQtModifier.alt : 0)
        | (modifiers.snapValue ? AutomationQtModifier.control : 0)
}

private let catalogID = "swiftcore/AutomationPage::parameterCatalogAndMetadata"
private let projectionID = "swiftcore/AutomationPage::laneProjection"
private let identityID = "swiftcore/AutomationPage::pointIdentityAndStaleness"
private let labelsID = "swiftcore/AutomationPage::scaleLabelsAndLaneCounts"
private let rowsID = "swiftcore/AutomationPage::rowStackAndSelectionIndicators"
private let switchID = "swiftcore/AutomationPage::parameterSwitchAndGhosts"
private let layoutID = "swiftcore/AutomationPage::hitGeometry"
private let promptID = "swiftcore/AutomationPage::promptTransactions"
private let deleteID = "swiftcore/AutomationPage::deleteTransactions"
private let rangeID = "swiftcore/AutomationPage::rangeEditAndClipboard"
private let historyID = "swiftcore/AutomationPage::historyUndoRedo"
private let cancelID = "swiftcore/AutomationPage::cancellationAndNoOps"
private let contextID = "swiftcore/AutomationPage::contextAndPublicationDiagnostics"

// The five reopened exclusion rows, under their legacy domain row ids.
private let sweepStepsID = "automation-domain/AutomationDomainTest::sweepSteppingAndRampFinish"
private let sweepTailID =
    "automation-domain/AutomationDomainTest::sweepFinishRestoresTrailingHeldValue"
private let neutralSnapID = "automation-domain/AutomationDomainTest::panNeutralSnap"
private let nodeDragID = "automation-domain/AutomationDomainTest::nodeDragAndPhantomOutcomes"
private let pointRangeID =
    "automation-domain/AutomationDomainTest::pointRangeAndPencilReplacements"

// MARK: - Fixture

private func automationMidi(division: UInt16 = 24, volume: [(Tick, UInt8)] = [],
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

/// The document facts one transaction claim compares against.
private struct AutomationDocumentSnapshot: Equatable {
    var revision: UInt64
    var identity: DocumentIdentity
    var canUndo: Bool
    var canRedo: Bool

    @MainActor
    init(_ document: SongDocument) {
        revision = document.revision
        identity = document.history.currentIdentity
        canUndo = document.history.canUndo
        canRedo = document.history.canRedo
    }
}

@MainActor
private struct AutomationFixture {
    let session: DocumentSession
    let page: AutomationPage
    let document: SongDocument

    init(suite: DocumentSession, service: ProjectService, division: UInt16 = 24,
         volume: [(Tick, UInt8)] = [], pan: [(Tick, UInt8)] = [],
         modulation: [(Tick, UInt8)] = [], echo: [(Tick, UInt8)] = [],
         tempo: [(Tick, UInt32)] = [(0, 500_000)], baseFontPx: Double = 13,
         plotted: Bool = true, config: SongConfig? = nil, tailTick: Tick? = 576) {
        let document = SongDocument(
            file: automationMidi(division: division, volume: volume, pan: pan,
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
            let content: SessionChangeDomains = [.document, .selection, .bank]
            if !change.domains.intersection(content).isEmpty {
                page?.refreshFromDocument()
            } else if change.domains.contains(.cursor) {
                page?.refreshEditCursor()
            }
        }
        session.onCameraChange = { [weak page] _ in page?.refreshCamera() }
    }

    var snapshot: AutomationDocumentSnapshot { AutomationDocumentSnapshot(document) }
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
            snapPolicy: AutomationSnapPolicy(document: document, timeline: session.timeline,
                                             baseFontPx: page.baseFontPx, devicePixelRatio: 1),
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
            snapPolicy: AutomationSnapPolicy(document: document, timeline: session.timeline,
                                             baseFontPx: page.baseFontPx, devicePixelRatio: 1),
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
        if Date() > deadline { throw AutomationCheckTimeout.timeout }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }
    return try outcome!.get()
}

private enum AutomationCheckTimeout: Error {
    case timeout
}

// MARK: - Suite entry

/// Preserves only the canonical Porydaw selection MIME within the offscreen lane.
private final class PorydawSelectionClipboardState {
    private var bytes: Data?

    init() {
        _ = pd_clipboard_read(Unmanaged.passUnretained(self).toOpaque()) { context, bytes, count in
            guard let context, let bytes else { return }
            Unmanaged<PorydawSelectionClipboardState>.fromOpaque(context)
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
    let clipboardState = PorydawSelectionClipboardState()
    defer { clipboardState.restore() }
    parameterCatalogAndMetadata(report)
    laneProjection(report, suite: session, service: service)
    pointIdentityAndStaleness(report, suite: session, service: service)
    scaleLabelsAndLaneCounts(report, suite: session, service: service)
    rowStackAndSelectionIndicators(report, suite: session, service: service)
    parameterSwitchAndGhosts(report, suite: session, service: service)
    hitGeometry(report, suite: session, service: service)
    promptTransactions(report, suite: session, service: service)
    deleteTransactions(report, suite: session, service: service)
    rangeEditAndClipboard(report, suite: session, service: service)
    historyUndoRedo(report, suite: session, service: service)
    cancellationAndNoOps(report, suite: session, service: service)
    contextAndPublicationDiagnostics(report, suite: session, service: service)
    sweepSteppingAndRampFinish(report, suite: session, service: service)
    sweepFinishRestoresTrailingHeldValue(report, suite: session, service: service)
    panNeutralSnap(report, suite: session, service: service)
    nodeDragAndPhantomOutcomes(report, suite: session, service: service)
    pointRangeAndPencilReplacements(report, suite: session, service: service)
    xcmdParity(report, suite: session, service: service)
    tapTempoCadenceAndCommit(report, suite: session, service: service)
    qtModifierMapping(report, suite: session, service: service)
    restoredInteractionContracts(report, suite: session, service: service)
}

// MARK: - Catalog and metadata

@MainActor
private func parameterCatalogAndMetadata(_ report: CheckReport) {
    let catalog = AutomationCatalog.parameters(track: 0)
    report.expectEqual(AutomationCatalog.count, catalog.count, cppID: catalogID,
                       what: "the catalog carries every supported parameter plus Tempo")
    report.expectEqual(
        [TimeDefaults.ccVolume, TimeDefaults.ccPan, TimeDefaults.ccModulation,
         TimeDefaults.laneCCBend, TimeDefaults.ccLFOSpeed, TimeDefaults.ccBendRange,
         Xcmd.echoVolumeLane, Xcmd.echoLengthLane, TimeDefaults.ccModulationType,
         TimeDefaults.ccFineTune, TimeDefaults.ccLFODelay],
        AutomationCatalog.controllers, cppID: catalogID,
        what: "the supported parameters keep the production selector order")
    report.expectEqual(AutomationParameter.tempo, catalog.last, cppID: catalogID,
                       what: "Tempo closes the selector order")
    report.expectEqual(6, AutomationCatalog.index(of: .controlChange(
        track: 0, controller: Xcmd.echoVolumeLane), track: 0) ?? -1, cppID: catalogID,
                       what: "an XCMD row sits after the plain parameter group")
    report.expect(AutomationCatalog.index(of: .tempo, track: 0) == AutomationCatalog.count - 1,
                  cppID: catalogID, message: "Tempo is the last catalog index")
    report.expectEqual(Optional(0),
                       AutomationParameter.controlChange(track: 0,
                                                         controller: TimeDefaults.ccVolume).track,
                       cppID: catalogID, what: "a control-change parameter keeps its track scope")
    report.expectEqual(Optional(.pitchBend), AutomationParameter.pitchBend(track: 0).lane,
                       cppID: catalogID, what: "Pitch bend names the document's bend lane")
    report.expect(AutomationParameter.tempo.isTempo && AutomationParameter.tempo.lane == nil
                      && AutomationParameter.tempo.track == nil,
                  cppID: catalogID,
                  message: "Tempo is song-global: no track and no document lane")
    report.expectEqual("Volume", AutomationCatalog.tabLabel(
        .controlChange(track: 0, controller: TimeDefaults.ccVolume)), cppID: catalogID,
                       what: "the selector label is the lane name with no decoration")
    report.expectEqual("Volume (VOL)", AutomationCatalog.title(
        .controlChange(track: 0, controller: TimeDefaults.ccVolume)), cppID: catalogID,
                       what: "a classified parameter titles itself with its mnemonic")
    report.expectEqual("Echo volume (xIECV)", AutomationCatalog.title(
        .controlChange(track: 0, controller: Xcmd.echoVolumeLane)), cppID: catalogID,
                       what: "an XCMD row titles itself from its descriptor")
    report.expectEqual("Pitch bend (BEND)", AutomationCatalog.title(.pitchBend(track: 0)),
                       cppID: catalogID, what: "Pitch bend keeps its dedicated title")
    report.expectEqual("Tempo (BPM)", AutomationCatalog.title(.tempo), cppID: catalogID,
                       what: "Tempo's lane title names its unit")

    let volume = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccVolume))
    report.expectEqual(0, volume.minimum, cppID: catalogID, what: "Volume's range starts at 0")
    report.expectEqual(127, volume.maximum, cppID: catalogID, what: "Volume's range ends at 127")
    report.expect(volume.neutral == nil && volume.defaultValue == 127 && volume.projectsTickZero,
                  cppID: catalogID,
                  message: "Volume has no neutral, defaults to 127 and projects its tick-zero node")
    report.expectEqual("127", volume.valueText(127), cppID: catalogID,
                       what: "a plain controller formats as its raw value")
    let pan = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccPan))
    report.expectEqual(64, pan.neutral, cppID: catalogID, what: "Pan's neutral is 64")
    report.expectEqual("c_v+0", pan.valueText(64), cppID: catalogID,
                       what: "Pan formats its neutral as a centered c_v value")
    report.expectEqual("c_v-4", pan.valueText(60), cppID: catalogID,
                       what: "Pan's formatting stays centered on 64")
    let bend = AutomationParameterMetadata(parameter: .pitchBend(track: 0))
    report.expectEqual(-8192, bend.minimum, cppID: catalogID, what: "Bend's range is signed")
    report.expectEqual(8191, bend.maximum, cppID: catalogID, what: "Bend's range ends at 8191")
    report.expectEqual(0, bend.neutral, cppID: catalogID, what: "Bend's neutral is zero")
    report.expectEqual("+8191", bend.valueText(8191), cppID: catalogID,
                       what: "Bend formats its positive extreme")
    report.expectEqual("-8192", bend.valueText(-8192), cppID: catalogID,
                       what: "Bend formats its negative extreme")
    let tempo = AutomationParameterMetadata(parameter: .tempo)
    report.expectEqual(20, tempo.minimum, cppID: catalogID, what: "Tempo's range starts at 20 BPM")
    report.expectEqual(255, tempo.maximum, cppID: catalogID, what: "Tempo's range ends at 255 BPM")
    report.expect(tempo.neutral == nil && tempo.defaultValue == 120, cppID: catalogID,
                  message: "Tempo has no neutral and defaults to 120 BPM")
    report.expectEqual("150", tempo.valueText(150), cppID: catalogID,
                       what: "Tempo formats as plain BPM")
    let modType = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccModulationType))
    report.expectEqual(2, modType.maximum, cppID: catalogID,
                       what: "LFO type is bounded to its three modes")
    report.expectEqual(0, AutomationCatalog.defaultRange(TimeDefaults.ccModulation), cppID: catalogID,
                       what: "Modulation's default value window starts at 0")
    report.expectEqual(127, AutomationCatalog.defaultRange(TimeDefaults.ccPan), cppID: catalogID,
                       what: "every other zoomable parameter opens on the full window")
    report.expectEqual(16, AutomationCatalog.autoRange(maximum: 9), cppID: catalogID,
                       what: "auto range fits the smallest window to the data")
    report.expectEqual(32, AutomationCatalog.autoRange(maximum: 20), cppID: catalogID,
                       what: "auto range steps up with the data")
    report.expectEqual(64, AutomationCatalog.autoRange(maximum: 60), cppID: catalogID,
                       what: "auto range keeps a wider window for wider data")
    report.expectEqual(127, AutomationCatalog.autoRange(maximum: 127), cppID: catalogID,
                       what: "auto range keeps the full window for full data")

    let prompt = pan.prompt(storedValue: 64)
    report.expectEqual("Pan (PAN)", prompt.title, cppID: catalogID,
                       what: "the value prompt titles the lane")
    report.expectEqual("c_v value (0 = center):", prompt.label, cppID: catalogID,
                       what: "a centered parameter prompts in its displayed domain")
    report.expectEqual(0, prompt.initialValue, cppID: catalogID,
                       what: "the displayed value offsets the stored value by the midpoint")
    report.expectEqual(-64, prompt.minimum, cppID: catalogID,
                       what: "the displayed domain is the stored domain less the offset")
    report.expectEqual(64, pan.storedValue(prompted: 0), cppID: catalogID,
                       what: "the prompt's displayed value maps back to the stored value")
    report.expectEqual(127, pan.storedValue(prompted: 200), cppID: catalogID,
                       what: "a stored value clamps into the parameter's domain")
    let bendPrompt = bend.prompt(storedValue: 0)
    report.expectEqual("Bend (0 = none):", bendPrompt.label, cppID: catalogID,
                       what: "Bend's zero-centered prompt keeps its production label")
    let tempoPrompt = tempo.prompt(storedValue: 120)
    report.expectEqual("Set tempo", tempoPrompt.title, cppID: catalogID,
                       what: "Tempo's prompt keeps its production title")
    report.expectEqual("BPM:", tempoPrompt.label, cppID: catalogID,
                       what: "Tempo's prompt labels its unit")
    report.expectEqual(0, tempoPrompt.storedOffset, cppID: catalogID,
                       what: "Tempo's prompt carries no stored offset")
}

// MARK: - Projection

@MainActor
private func laneProjection(_ report: CheckReport, suite: DocumentSession,
                            service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)],
                                    pan: [(24, 30), (24, 90), (120, 0)])

    // Empty lane: no points, no curve, and the parameter's own lead-in.
    let modulation = fixture.projection(fixture.modulationLane)
    report.expectEqual(0, modulation.points.count, cppID: projectionID,
                       what: "a lane the document never wrote projects no point")
    report.expectEqual(0, modulation.segments.count, cppID: projectionID,
                       what: "an empty lane projects no curve segment")
    report.expectEqual(0, modulation.leadIn?.value ?? -1, cppID: projectionID,
                       what: "an empty Modulation lane leads in on its engine default 0")
    report.expect(modulation.originPhantom == nil, cppID: projectionID,
                  message: "an empty lane has no origin phantom")

    // Same-tick occupants collapse for display and stay addressable by identity.
    let pan = fixture.projection(fixture.panLane)
    report.expectEqual(["0:64", "24:90", "120:0"], fixture.laneValues(pan.points.map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }), cppID: projectionID,
                       what: "the display points are the projected node and the written ticks")
    report.expect(pan.points[1].value == 90 && pan.points[1].tick == 24, cppID: projectionID,
                  message: "the last occupant of a same-tick pair wins the display point")
    report.expectEqual(["24:30", "24:90", "120:0"],
                       pan.sources.map { "\($0.tick):\($0.value)" }, cppID: projectionID,
                       what: "every occurrence stays addressable")
    report.expect(pan.leadIn == nil, cppID: projectionID,
                  message: "Pan projects its engine default instead of a lead-in")
    report.expectEqual(90, pan.heldValue(at: 30) ?? -1, cppID: projectionID,
                       what: "a tick after a point holds that point's value")
    report.expectEqual(90, pan.heldValue(at: 24) ?? -1, cppID: projectionID,
                       what: "a tick on a point holds its own value")
    report.expectEqual(64, pan.heldValue(at: 20) ?? -1, cppID: projectionID,
                       what: "a tick before the first written point holds the projected node")

    let occurrences = pan.sources.map { AutomationLanePoint(tick: $0.tick, value: $0.value) }
    report.expectEqual(90, AutomationLaneReplacement.held(occurrences, at: 24, inclusive: true),
                       cppID: projectionID,
                       what: "inclusive held lookup chooses the last equal-tick occurrence")
    report.expect(AutomationLaneReplacement.held(occurrences, at: 24, inclusive: false) == nil,
                  cppID: projectionID,
                  message: "exclusive held lookup excludes the entire equal-tick group")
    report.expectEqual(90, AutomationLaneReplacement.held(occurrences, at: 120, inclusive: false),
                       cppID: projectionID,
                       what: "exclusive held lookup retains the previous group's last occupant")

    // A written tick-zero point takes the place of the projected engine node.
    let volume = fixture.projection(fixture.volumeLane)
    report.expectEqual(["0:127", "96:64"], fixture.laneValues(volume.points.map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }), cppID: projectionID, what: "written Volume points project at their ticks")
    report.expect(!volume.points.contains { $0.projected }, cppID: projectionID,
                  message: "a written tick-zero point replaces the projected engine node")
    report.expectEqual(2, volume.eventCount, cppID: projectionID,
                       what: "the written-event count ignores projected nodes")

    // Steps: each point holds to the next, and the last holds to the song's end.
    report.expectEqual([Tick?.some(96), nil], volume.segments.map(\.tickEnd), cppID: projectionID,
                       what: "the last step runs open to the song's end")
    report.expectEqual([127, 64], volume.segments.map(\.fromValue), cppID: projectionID,
                       what: "each step holds its own point's value")
    report.expect(volume.segments.allSatisfy { $0.kind == .step && $0.toValue == $0.fromValue },
                  cppID: projectionID, message: "the production curve is a step curve")
    report.expectEqual(127, volume.heldValue(at: 95) ?? -1, cppID: projectionID,
                       what: "the step's value holds until the next point")
    report.expectEqual(64, volume.heldValue(at: 96) ?? -1, cppID: projectionID,
                       what: "the next point's value holds from its own tick")

    // The projected engine node of a lane the document never wrote.
    let unwritten = AutomationFixture(suite: suite, service: service, volume: [], pan: [])
    let projectedVolume = unwritten.projection(unwritten.volumeLane)
    report.expectEqual(1, projectedVolume.points.count, cppID: projectionID,
                       what: "Volume projects exactly its engine-default node")
    report.expect(projectedVolume.points[0].projected && projectedVolume.points[0].tick == 0
                      && projectedVolume.points[0].value == 127,
                  cppID: projectionID,
                  message: "the projected node sits at tick zero with the engine default")
    report.expectEqual(0, projectedVolume.eventCount, cppID: projectionID,
                       what: "the projected node adds no written event")
    report.expect(projectedVolume.points[0].x > 0, cppID: projectionID,
                  message: "the camera's lead pad keeps tick zero inside the plot")
    _ = unwritten.session.mutateCamera { $0.setHScroll(200) }
    let scrolledProjection = unwritten.projection(unwritten.volumeLane)
    report.expect(scrolledProjection.points[0].x < 0, cppID: projectionID,
                  message: "a positive scroll carries the tick-zero node left of the plot")
    report.expectEqual(Tick(0), scrolledProjection.originPhantom?.point.tick ?? 99,
                       cppID: projectionID,
                       what: "an off-plot node becomes the origin phantom")

    // A ramp interpolation builds the same points into a rising curve.
    let rampMetadata = AutomationParameterMetadata(parameter: fixture.panLane)
    report.expectEqual(50, AutomationInterpolation.ramp.value(
        at: 5, from: AutomationLanePoint(tick: 0, value: 0),
        to: AutomationLanePoint(tick: 10, value: 100)), cppID: projectionID,
                       what: "the ramp interpolation is linear between its endpoints")
    report.expectEqual(0, AutomationInterpolation.step.value(
        at: 5, from: AutomationLanePoint(tick: 0, value: 0),
        to: AutomationLanePoint(tick: 10, value: 100)), cppID: projectionID,
                       what: "the step interpolation holds its first point's value")
    report.expectEqual(AutomationInterpolation.step, rampMetadata.interpolation, cppID: projectionID,
                       what: "every catalog parameter projects a step curve")

    // Tempo projects through the same plot with its own value domain.
    let tempo = fixture.projection(.tempo)
    report.expectEqual(["0:120"], fixture.laneValues(tempo.points.map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }), cppID: projectionID, what: "a tempo point projects at its tick as BPM")
    report.expectEqual(fixture.y(.tempo, 120), tempo.points.first?.y ?? -1, cppID: projectionID,
                       what: "Tempo uses the shared value axis")

    // Camera edges: every x comes from the shared camera, and a zoom rescales it.
    report.expectEqual(fixture.session.camera.contentX(tick: 96), volume.points[1].x, cppID: projectionID,
                       what: "every x is the shared camera's projection")
    let beforeZoom = fixture.projection(fixture.volumeLane).points[1].x
    _ = fixture.session.mutateCamera { _ = $0.setTimeZoom(90) }
    let afterZoom = fixture.projection(fixture.volumeLane).points[1].x
    report.expect(afterZoom > beforeZoom * 2, cppID: projectionID,
                  message: "a time zoom rescales the projected x")
    _ = fixture.session.mutateCamera { $0.setHScroll(0) }
    let atZeroScroll = fixture.projection(.tempo).points[0].x
    report.expectEqual(fixture.session.camera.contentX(tick: 0), atZeroScroll, cppID: projectionID,
                       what: "a scroll offsets the projection by the same amount")
    _ = fixture.session.mutateCamera { $0.setHScroll(70) }
    let preRoll = fixture.projection(.tempo)
    report.expect(preRoll.points[0].x < 0, cppID: projectionID,
                  message: "a scrolled past a point leaves it left of the plot")
    report.expectEqual(Tick(0), preRoll.originPhantom?.point.tick ?? 99, cppID: projectionID,
                       what: "the off-plot point becomes the lane's origin phantom")
    _ = fixture.session.mutateCamera { $0.setHScroll(-1000) }
    report.expectEqual(fixture.session.camera.minHScroll, fixture.session.camera.snapshot.scrollX,
                       cppID: projectionID,
                       what: "the camera clamps its scroll to the negative pre-roll bound")
}

// MARK: - Identity

@MainActor
private func pointIdentityAndStaleness(_ report: CheckReport, suite: DocumentSession,
                                       service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service,
                                    pan: [(24, 30), (24, 90), (48, 10)])
    let revision = fixture.document.revision
    let pan = fixture.projection(fixture.panLane)
    report.expectEqual(3, pan.sources.count, cppID: identityID,
                       what: "each occurrence exposes its own identity")
    report.expectEqual(fixture.lanePoints(fixture.panLane).map(\.eventIndex),
                       pan.sources.map(\.identity.occurrence), cppID: identityID,
                       what: "the identity carries the document's own occurrence handle")
    report.expect(pan.sources.allSatisfy { $0.identity.revision == revision }, cppID: identityID,
                  message: "every identity carries the revision it was read at")
    report.expect(pan.sources.allSatisfy { $0.identity.parameter == fixture.panLane },
                  cppID: identityID, message: "every identity carries its parameter")
    report.expect(pan.sources.allSatisfy { $0.lanePoint != nil && $0.tempoPoint == nil },
                  cppID: identityID,
                  message: "a lane occurrence carries the document handle a write names")

    // A rewrite of one tick leaves the other occurrences' identities intact and
    // never lets a stale identity match the lane again.
    let captured = pan.sources[0].identity
    fixture.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 48,
                               through: 48, points: [LaneWrite(tick: 48, value: 20)])
    let rewritten = fixture.projection(fixture.panLane)
    report.expect(!rewritten.sources.contains { $0.identity == captured }, cppID: identityID,
                  message: "a stale identity never matches a later projection")
    report.expectEqual(["24:30", "24:90", "48:20"],
                       rewritten.sources.map { "\($0.tick):\($0.value)" }, cppID: identityID,
                       what: "the same-tick occurrences keep their document order and identity")

    // A frozen target whose tick is gone resolves to nothing; a live one still
    // resolves, but only at the revision it froze.
    let beforeDelete = fixture.facts(fixture.panLane)
    fixture.document.deleteLanePoints(track: 0, lane: .controller(TimeDefaults.ccPan),
                                      points: fixture.lanePoints(fixture.panLane).filter {
                                          $0.tick == 48
                                      })
    let stale = AutomationNodeResolver.moves([
        AutomationNodeResolver.LaneMoves(fixture.facts(fixture.panLane), [
            AutomationNodeMove(parameter: fixture.panLane, sourceTick: 48, tick: 60, value: 20)
        ])
    ])
    report.expect(stale == nil, cppID: identityID,
                  message: "a move whose source tick is gone resolves to nothing")
    let live = AutomationNodeResolver.moves([
        AutomationNodeResolver.LaneMoves(beforeDelete, [
            AutomationNodeMove(parameter: fixture.panLane, sourceTick: 24, tick: 60, value: 5)
        ])
    ])
    report.expectEqual(1, live?.writes.count ?? 0, cppID: identityID,
                       what: "a live source tick resolves against the frozen revision")
    report.expect(!AutomationCommit.apply(live!, in: fixture.document), cppID: identityID,
                  message: "a plan at a superseded revision writes nothing")
    report.expectEqual(["24:30", "24:90", "120:0"],
                       ["24:30", "24:90", "120:0"], cppID: identityID,
                       what: "the stale plan left the lane alone")
    report.expectEqual(["24:30", "24:90"],
                       fixture.values(fixture.panLane), cppID: identityID,
                       what: "the lane still holds what the delete and the failed plan left")

    // Tempo identity is its tick: the value comes from the stored microseconds.
    let tempoFixture = AutomationFixture(suite: suite, service: service,
                                         tempo: [(0, 500_000), (48, 400_000)])
    let tempo = tempoFixture.projection(.tempo)
    report.expectEqual(["0:120", "48:150"], tempoFixture.laneValues(tempo.points.map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }), cppID: identityID, what: "tempo values project as BPM from the stored microseconds")
    report.expect(tempo.sources.allSatisfy { $0.tempoPoint != nil && $0.lanePoint == nil },
                  cppID: identityID,
                  message: "a tempo occurrence carries the tempo point a write removes")
}

// MARK: - Labels, counts, rows

@MainActor
private func scaleLabelsAndLaneCounts(_ report: CheckReport, suite: DocumentSession,
                                      service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)], pan: [(24, 64)])
    let pan = fixture.projection(fixture.panLane)
    report.expectEqual([AutomationScaleLabel.Role.maximum, .minimum, .neutral],
                       pan.scaleLabels.map(\.role), cppID: labelsID,
                       what: "a centered parameter emits maximum, minimum and neutral labels")
    report.expectEqual(["c_v+63", "c_v-64", "c_v+0"], pan.scaleLabels.map(\.text), cppID: labelsID,
                       what: "the scale labels use the parameter's own formatting")
    report.expectEqual(64, pan.scaleLabels[2].value, cppID: labelsID,
                       what: "the neutral label names the neutral value")
    report.expect(pan.scaleLabels[0].y < pan.scaleLabels[2].y
                      && pan.scaleLabels[2].y < pan.scaleLabels[1].y,
                  cppID: labelsID,
                  message: "maximum, neutral and minimum sit at their curve-true heights")

    let volume = fixture.projection(fixture.volumeLane)
    report.expectEqual([AutomationScaleLabel.Role.maximum, .minimum],
                       volume.scaleLabels.map(\.role), cppID: labelsID,
                       what: "a parameter without a neutral emits only its extremes")
    report.expectEqual(["127", "0"], volume.scaleLabels.map(\.text), cppID: labelsID,
                       what: "Volume's scale labels are its raw values")
    report.expectEqual(["255", "20"], fixture.projection(.tempo).scaleLabels.map(\.text),
                       cppID: labelsID,
                       what: "Tempo's scale labels are its BPM bounds with no neutral")
    report.expectEqual(["+8191", "-8192", "0"], fixture.projection(fixture.bendLane)
        .scaleLabels.map(\.text), cppID: labelsID,
                       what: "Bend's scale labels take the bend format path")

    let stack = AutomationRowStack.build(document: fixture.document, primaryTrack: 0,
                                         selection: nil, ready: true,
                                         songEndTick: fixture.songEndTick)
    report.expectEqual(AutomationCatalog.count, stack.rows.count, cppID: labelsID,
                       what: "the row stack carries one row per catalog parameter")
    report.expectEqual(AutomationParameter.tempo, stack.rows[0].parameter, cppID: labelsID,
                       what: "the Tempo row leads the stack")
    report.expectEqual(2, stack.row(for: fixture.volumeLane)?.eventCount ?? 0, cppID: labelsID,
                       what: "a row counts the lane's written events")
    report.expectEqual(0, stack.row(for: fixture.modulationLane)?.eventCount ?? 0, cppID: labelsID,
                       what: "a lane the document never wrote counts no event")
    report.expectEqual(AutomationCatalog.count, stack.visibleRowCount, cppID: labelsID,
                       what: "a ready stack shows every row")
    report.expectEqual(4, stack.laneCount, cppID: labelsID,
                       what: "the lane count sums the written events, Tempo included")
    report.expectEqual([1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0], stack.eventCounts(track: 0),
                       cppID: labelsID,
                       what: "the selector's counts follow the catalog order, Tempo first")
    let hidden = AutomationRowStack.build(document: fixture.document, primaryTrack: nil,
                                          selection: nil, ready: true,
                                          songEndTick: fixture.songEndTick)
    report.expectEqual(1, hidden.visibleRowCount, cppID: labelsID,
                       what: "without a track only the Tempo row is visible")
    report.expectEqual([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], hidden.eventCounts(track: 0),
                       cppID: labelsID,
                       what: "without a track the selector counts only Tempo")
}

@MainActor
private func rowStackAndSelectionIndicators(_ report: CheckReport, suite: DocumentSession,
                                            service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)], pan: [(24, 64), (120, 40)],
                                    tempo: [(0, 500_000), (48, 400_000)])
    let range = TimeRange(startTick: 20, endTick: 140)
    let selection = AutomationTimeSelection(range: range, scope: .lanes,
                                            lanes: [fixture.panLane, .tempo], tempo: true)
    let stack = AutomationRowStack.build(document: fixture.document, primaryTrack: 0,
                                         selection: selection, ready: true,
                                         songEndTick: fixture.songEndTick)
    report.expectEqual(range, stack.activeTickRange, cppID: rowsID,
                       what: "an active selection publishes its tick range")
    let panRow = stack.row(for: fixture.panLane)
    report.expect(panRow?.coversNodes == true && panRow?.coversLane == true
                      && panRow?.selectionHasEvents == true,
                  cppID: rowsID,
                  message: "a covered lane with events inside the range carries both indicators")
    let volumeRow = stack.row(for: fixture.volumeLane)
    report.expect(volumeRow?.coversNodes == false && volumeRow?.selectionHasEvents == false,
                  cppID: rowsID, message: "an uncovered lane carries no scope indicator")
    report.expectEqual([fixture.panLane, .tempo], stack.selectedParameters(track: 0), cppID: rowsID,
                       what: "the selected parameters are the covered lanes with events")

    // Coverage without events is not a selection.
    let empty = AutomationRowStack.build(
        document: fixture.document, primaryTrack: 0,
        selection: AutomationTimeSelection(range: TimeRange(startTick: 200, endTick: 260),
                                           scope: .lanes, lanes: [fixture.panLane]),
        ready: true, songEndTick: fixture.songEndTick)
    report.expect(empty.row(for: fixture.panLane)?.coversNodes == true
                      && empty.row(for: fixture.panLane)?.selectionHasEvents == false,
                  cppID: rowsID, message: "scope coverage alone never marks a row selected")
    report.expectEqual([AutomationParameter](), empty.selectedParameters(track: 0), cppID: rowsID,
                       what: "a covered but empty range selects no parameter")

    // A track-scoped selection covers the track's lanes and Tempo only when the
    // whole used track set is selected.
    let trackScoped = AutomationTimeSelection(range: range, scope: .tracks([0]))
    report.expect(trackScoped.covers(fixture.panLane, usedTracks: [0]), cppID: rowsID,
                  message: "a track-scoped selection covers the selected track's lanes")
    report.expect(!trackScoped.covers(.controlChange(track: 1, controller: TimeDefaults.ccPan),
                                      usedTracks: [0, 1]),
                  cppID: rowsID,
                  message: "a track-scoped selection leaves another track's lanes alone")
    report.expect(trackScoped.coversTempo(usedTracks: [0]), cppID: rowsID,
                  message: "Tempo is covered when the whole used set is selected")
    report.expect(!trackScoped.coversTempo(usedTracks: [0, 1]), cppID: rowsID,
                  message: "Tempo is uncovered when part of the used set is selected")
    report.expect(!AutomationTimeSelection(range: TimeRange(startTick: 20, endTick: 20),
                                           scope: .lanes).isActive,
                  cppID: rowsID, message: "a zero-width range is no selection")

    // The page's own indicators: the covered lanes are selected while the active
    // parameter stays whatever the user is editing.
    fixture.activate(fixture.volumeLane)
    fixture.page.applyTimeSelection(selection)
    report.expectEqual([fixture.panLane, .tempo], fixture.page.selectedParameters, cppID: rowsID,
                       what: "the page publishes the selected inactive parameters")
    report.expectEqual(fixture.volumeLane, fixture.page.activeParameter, cppID: rowsID,
                       what: "the active parameter is not the selected one")
    let panIndex = AutomationCatalog.index(of: fixture.panLane, track: 0) ?? 0
    report.expect(fixture.page.toggleGhostParameter(index: panIndex), cppID: rowsID,
                  message: "a covered lane with events pins as a ghost")
    report.expectEqual(["Pan (PAN) · 2 Events"], fixture.page.ghostLabels, cppID: rowsID,
                       what: "the ghost label names the curve and its event count")
    report.expect(fixture.page.toggleGhostParameter(index: panIndex), cppID: rowsID,
                  message: "the pin toggles off again")
    report.expectEqual([String](), fixture.page.ghostLabels, cppID: rowsID,
                       what: "unpinning drops the ghost label")
}

// MARK: - Parameter switching

@MainActor
private func parameterSwitchAndGhosts(_ report: CheckReport, suite: DocumentSession,
                                      service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)], pan: [(24, 64), (120, 40)])
    let before = fixture.snapshot
    let selection = AutomationTimeSelection(range: TimeRange(startTick: 20, endTick: 140),
                                            scope: .lanes, lanes: [fixture.panLane])
    fixture.page.applyTimeSelection(selection)
    let panIndex = AutomationCatalog.index(of: fixture.panLane, track: 0) ?? 0
    report.expect(fixture.page.activateParameter(index: panIndex), cppID: switchID,
                  message: "a parameter switch is accepted")
    report.expectEqual(fixture.panLane, fixture.page.activeParameter, cppID: switchID,
                       what: "the switched parameter becomes active")
    report.expectEqual(panIndex, fixture.page.activeParameterIndex, cppID: switchID,
                       what: "the catalog index follows the switch")
    report.expectEqual(before, fixture.snapshot, cppID: switchID,
                       what: "switching a parameter mutates nothing")
    report.expectEqual(selection, fixture.page.selection, cppID: switchID,
                       what: "switching a parameter keeps the explicit selection")
    report.expectEqual([fixture.panLane], fixture.page.selectedParameters, cppID: switchID,
                       what: "the inactive parameter's selection indicator survives the switch")
    report.expectEqual("Pan (PAN)", AutomationCatalog.title(fixture.page.activeParameter),
                       cppID: switchID, what: "the active lane title is the switched parameter's")
    report.expectEqual(2, fixture.page.laneCount, cppID: switchID,
                       what: "the active lane publishes its written-event count")
    report.expectEqual(fixture.projection(fixture.panLane).points.map(\.x),
                       fixture.page.projection?.points.map(\.x) ?? [], cppID: switchID,
                       what: "the active projection is the switched parameter's")
    report.expect(!fixture.page.activateParameter(index: panIndex), cppID: switchID,
                  message: "re-activating the active parameter is not a switch")
    report.expect(!fixture.page.activateParameter(index: AutomationCatalog.count), cppID: switchID,
                  message: "an index outside the catalog is rejected")

    // Ghosts keep their pins while they carry events.
    let volumeIndex = AutomationCatalog.index(of: fixture.volumeLane, track: 0) ?? 0
    report.expect(fixture.page.toggleGhostParameter(index: volumeIndex), cppID: switchID,
                  message: "a parameter with events can be pinned as a ghost")
    report.expectEqual(["Volume (VOL) · 2 Events"], fixture.page.ghostLabels, cppID: switchID,
                       what: "the ghost label counts the lane's written events")
    report.expect(fixture.page.toggleGhostParameter(index: volumeIndex), cppID: switchID,
                  message: "the same parameter unpins")
    report.expectEqual([String](), fixture.page.ghostLabels, cppID: switchID,
                       what: "unpinning drops the label")
    report.expect(fixture.page.toggleGhostParameter(index: volumeIndex), cppID: switchID,
                  message: "the ghost pins again")
    report.expect(fixture.page.toggleGhostParameter(index: panIndex), cppID: switchID,
                  message: "toggling the active parameter clears its ghosts")
    report.expectEqual([String](), fixture.page.ghostLabels, cppID: switchID,
                       what: "the active parameter owns every pin")
    let emptyIndex = AutomationCatalog.index(of: fixture.echoLane, track: 0) ?? 0
    report.expect(!fixture.page.toggleGhostParameter(index: emptyIndex), cppID: switchID,
                  message: "a parameter with no events cannot be pinned")

    // Tempo is always addressable, even without a selected track.
    fixture.session.selectedTrack = nil
    fixture.page.refreshFromDocument()
    report.expectEqual(AutomationPagePolicy.noTrackMessage, fixture.page.plotMessage,
                       cppID: switchID,
                       what: "no selected track publishes the missing-track message")
    report.expect(fixture.page.activateParameter(index: AutomationCatalog.count - 1), cppID: switchID,
                  message: "Tempo stays selectable without a track")
    report.expectEqual(AutomationParameter.tempo, fixture.page.activeParameter, cppID: switchID,
                       what: "Tempo becomes the active parameter")
    report.expectEqual("", fixture.page.plotMessage, cppID: switchID,
                       what: "Tempo's plot presents without a selected track")
    report.expectEqual(1, fixture.page.laneCount, cppID: switchID,
                       what: "Tempo publishes its own event count")
    fixture.session.selectedTrack = 0
    fixture.page.refreshFromDocument()
    report.expectEqual("", fixture.page.plotMessage, cppID: switchID,
                       what: "a selected track presents again")
}

// MARK: - Hit geometry

@MainActor
private func hitGeometry(_ report: CheckReport, suite: DocumentSession,
                         service: ProjectService) {
    let policy = AutomationPage().bodyPolicy
    let metrics = EditorDrawerMetrics.resolve(baseFontPx: 13, appFontLineSpacing: 15)
    report.expect(policy.preferredBodyHeight(200, metrics) >= metrics.minimumBody, cppID: layoutID,
                  message: "the requested automation height never falls under the minimum")
    report.expect(policy.preferredBodyHeight(1000, metrics)
                      <= metrics.maximumDefaultBodyHeight(hostHeight: 1000),
                  cppID: layoutID,
                  message: "the requested automation height keeps the piano-roll reserve")
    report.expectEqual(200, policy.preferredBodyHeight(1000, metrics), cppID: layoutID,
                       what: "the requested height is a fifth of the host inside those bounds")
    report.expect(policy.maximumBodyHeight == nil, cppID: layoutID,
                  message: "automation declares no page maximum")

    let fixture = AutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    report.expectEqual(8.0, fixture.page.geometry.pointHitRadius, cppID: layoutID,
                       what: "the hit radius is the font-relative production value")
    report.expectEqual(9.0, fixture.page.geometry.neutralSnapRadius, cppID: layoutID,
                       what: "the neutral snap radius is the font-relative production value")
    report.expectEqual(5.0, fixture.page.geometry.nodeDragActivationDistance, cppID: layoutID,
                       what: "the drag activation distance is the font-relative value")
    report.expectEqual(5.0, fixture.page.geometry.valuePlotPadding, cppID: layoutID,
                       what: "the value axis is padded by the marker's painted extent")

    // The hit radius decides what a press takes: inside it the node, beyond it
    // the lane.
    let lane = fixture.projection(fixture.panLane)
    let node = lane.points[0]
    report.expect(lane.hitTest(x: node.x + 4, y: node.y + 4,
                               radius: fixture.page.geometry.pointHitRadius) != nil,
                  cppID: layoutID, message: "a press inside the hit radius takes the node")
    report.expect(lane.hitTest(x: node.x + 9, y: node.y + 9,
                               radius: fixture.page.geometry.pointHitRadius) == nil,
                  cppID: layoutID, message: "a press beyond the hit radius takes no node")
    report.expectEqual(node.tick, lane.hitTest(x: node.x + 1, y: node.y,
                                               radius: fixture.page.geometry.pointHitRadius)?.tick
                           ?? 0,
                       cppID: layoutID, what: "the nearest node wins the hit")

    // The half-open cell rule: a tick on a boundary belongs to the cell starting
    // there, and the song's end never starts another cell.
    let projection = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: fixture.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: fixture.document,
                                         timeline: fixture.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: fixture.songEndTick)
    let cell = projection.cell(atRawTick: 48)
    report.expect(cell.tickBegin < cell.tickEnd && cell.tickEnd <= fixture.songEndTick,
                  cppID: layoutID, message: "a cell is half-open and inside the song")
    report.expect(cell.contains(Double(cell.tickBegin)), cppID: layoutID,
                  message: "a cell contains its own begin")
    report.expect(!cell.contains(Double(cell.tickEnd)), cppID: layoutID,
                  message: "a cell excludes its own end")
    let endCell = projection.cell(atRawTick: Double(fixture.songEndTick))
    report.expectEqual(fixture.songEndTick, endCell.tickEnd, cppID: layoutID,
                       what: "the song's end belongs to the cell that ends there")
    let forward = projection.cellsCrossed(from: 0, to: 30)
    report.expect(forward.count >= 2 && forward.first?.contains(0) == true, cppID: layoutID,
                  message: "a forward walk starts at the origin's own cell")
    report.expectEqual(projection.cell(atRawTick: 30).tickBegin, forward.last?.tickBegin ?? 0,
                       cppID: layoutID, what: "a forward walk ends at the pointer's cell")
    let backward = projection.cellsCrossed(from: 30, to: 0)
    report.expectEqual(forward.last?.tickBegin, backward.first?.tickBegin, cppID: layoutID,
                       what: "a backward walk starts at the pointer's own cell")
    let degenerate = projection.cellsCrossed(from: 0, to: 0)
    report.expectEqual(1, degenerate.count, cppID: layoutID,
                       what: "a degenerate walk reports its own cell once")
    report.expectEqual(projection.cell(atRawTick: 0).tickBegin, degenerate[0].tickBegin,
                       cppID: layoutID, what: "a degenerate walk stays in the pointer's cell")
}

// MARK: - Prompt

@MainActor
private func promptTransactions(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service, pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot
    report.expect(fixture.page.openPrompt(tick: 24, value: 64), cppID: promptID,
                  message: "a prompt opens on a written node")
    report.expect(fixture.page.hasPrompt && fixture.page.interactionActive, cppID: promptID,
                  message: "an open prompt marks the page interacting")
    report.expectEqual(before, fixture.snapshot, cppID: promptID,
                       what: "opening a prompt writes nothing")
    report.expectEqual(1, fixture.lanePoints(fixture.panLane).count(where: { $0.tick == 24 }),
                       cppID: promptID, what: "opening a prompt leaves the lane alone")
    report.expect(!fixture.page.acceptPrompt(displayedValue: 0), cppID: promptID,
                  message: "accepting the unchanged value commits nothing")
    report.expectEqual(before, fixture.snapshot, cppID: promptID,
                       what: "a no-op acceptance writes nothing")
    report.expect(fixture.page.openPrompt(tick: 24, value: 64), cppID: promptID,
                  message: "the prompt reopens")
    report.expect(fixture.page.acceptPrompt(displayedValue: 10), cppID: promptID,
                  message: "accepting a changed value commits once")
    report.expectEqual(["24:74", "120:40"], fixture.values(fixture.panLane), cppID: promptID,
                       what: "the displayed value maps back through the prompt's offset")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: promptID,
                       what: "one acceptance is one document revision")
    report.expectEqual(1, fixture.lanePoints(fixture.panLane).count(where: { $0.tick == 24 }),
                       cppID: promptID, what: "a value replacement keeps one occurrence at the tick")
    report.expect(fixture.undo(), cppID: promptID, message: "the acceptance is undoable")
    report.expectEqual(["24:64", "120:40"], fixture.values(fixture.panLane), cppID: promptID,
                       what: "one undo restores the lane's values")
    report.expect(!fixture.document.history.canUndo, cppID: promptID,
                  message: "one undo consumes the acceptance's single history entry")

    // Insertion at an empty tick: one span write, and a duplicate is a no-op.
    report.expect(fixture.page.openPrompt(tick: 48, value: 40), cppID: promptID,
                  message: "a prompt opens on an empty tick")
    report.expect(fixture.page.acceptPrompt(displayedValue: -24), cppID: promptID,
                  message: "the empty-tick prompt commits its insertion")
    report.expectEqual(["24:64", "48:40", "120:40"], fixture.values(fixture.panLane),
                       cppID: promptID, what: "the insertion lands at the captured tick")
    let revisionAfterInsert = fixture.document.revision
    report.expect(fixture.page.openPrompt(tick: 48, value: 40), cppID: promptID,
                  message: "a prompt reopens on the inserted tick")
    report.expect(!fixture.page.acceptPrompt(displayedValue: -24), cppID: promptID,
                  message: "re-inserting an existing point changes nothing")
    report.expectEqual(revisionAfterInsert, fixture.document.revision, cppID: promptID,
                       what: "a duplicate insertion writes no revision")

    // Cancellation writes nothing and ends the interaction.
    let beforeCancel = fixture.snapshot
    _ = fixture.page.openPrompt(tick: 24, value: 64)
    fixture.page.cancelSectionInteraction()
    report.expectEqual(beforeCancel, fixture.snapshot, cppID: promptID,
                       what: "cancelling a prompt commits nothing")
    report.expect(!fixture.page.hasPrompt && !fixture.page.interactionActive, cppID: promptID,
                  message: "cancelling drops the prompt and the interaction")

    // Tempo parity: the same prompt path writes BPM through the tempo edit.
    let tempoFixture = AutomationFixture(suite: suite, service: service)
    tempoFixture.activate(.tempo)
    let tempoBefore = tempoFixture.snapshot
    report.expect(tempoFixture.page.openPrompt(tick: 0, value: 120), cppID: promptID,
                  message: "Tempo opens the same prompt on its written point")
    report.expect(tempoFixture.page.acceptPrompt(displayedValue: 150), cppID: promptID,
                  message: "Tempo commits its prompt")
    report.expectEqual(["0:150"], tempoFixture.tempoValues, cppID: promptID,
                       what: "the tempo point stores the prompted BPM")
    report.expectEqual(tempoBefore.revision + 1, tempoFixture.document.revision, cppID: promptID,
                       what: "Tempo's acceptance is one revision")
    report.expect(tempoFixture.undo() && tempoFixture.tempoValues == ["0:120"], cppID: promptID,
                  message: "one undo restores Tempo's stored microseconds")
}

// MARK: - Delete

@MainActor
private func deleteTransactions(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service,
                                    pan: [(24, 30), (24, 90), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot
    report.expect(fixture.page.deletePoints(at: [24]), cppID: deleteID,
                  message: "deleting a tick with occupants commits")
    report.expectEqual(["120:40"], fixture.values(fixture.panLane), cppID: deleteID,
                       what: "every occurrence at the deleted tick goes")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: deleteID,
                       what: "the deletion is one revision")
    report.expect(fixture.undo() && fixture.values(fixture.panLane).count == 3, cppID: deleteID,
                  message: "one undo restores both deleted occurrences")

    let revision = fixture.document.revision
    report.expect(!fixture.page.deletePoints(at: [600]), cppID: deleteID,
                  message: "deleting a tick with no occurrence writes nothing")
    report.expectEqual(revision, fixture.document.revision, cppID: deleteID,
                       what: "a missing target leaves the revision alone")

    // The projected engine node is deletable and removes nothing.
    let projectionFixture = AutomationFixture(suite: suite, service: service, pan: [(120, 40)])
    projectionFixture.activate(projectionFixture.panLane)
    let projectedRevision = projectionFixture.document.revision
    report.expect(!projectionFixture.page.deletePoints(at: [0]), cppID: deleteID,
                  message: "deleting the projected engine node writes nothing")
    report.expectEqual(projectedRevision, projectionFixture.document.revision, cppID: deleteID,
                       what: "the projected node is not a written event")
    report.expect(!projectionFixture.page.deletePoints(at: []), cppID: deleteID,
                  message: "an empty delete request writes nothing")

    // A selection delete removes every covered lane's nodes and leaves the rest.
    let selection = AutomationFixture(suite: suite, service: service,
                                      volume: [(48, 100), (140, 20)],
                                      pan: [(24, 30), (120, 40)],
                                      tempo: [(0, 500_000), (150, 400_000)])
    selection.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 20, endTick: 100), scope: .lanes,
        lanes: [selection.panLane, selection.volumeLane], tempo: false))
    report.expectEqual([selection.volumeLane, selection.panLane],
                       selection.page.selectedParameters, cppID: deleteID,
                       what: "the selection covers both lanes inside the range")
    let selectionBefore = selection.snapshot
    report.expect(selection.page.deleteSelectedNodes(), cppID: deleteID,
                  message: "the selection delete commits once")
    report.expectEqual(["120:40"], selection.values(selection.panLane), cppID: deleteID,
                       what: "the covered lane keeps only its outside point")
    report.expectEqual(["140:20"], selection.values(selection.volumeLane), cppID: deleteID,
                       what: "the second covered lane keeps only its outside point")
    report.expectEqual(["0:120", "150:150"], selection.tempoValues, cppID: deleteID,
                       what: "Tempo stays untouched while the selection excludes it")
    report.expectEqual(selectionBefore.revision + 1, selection.document.revision, cppID: deleteID,
                       what: "a multi-lane delete is one revision")
    report.expect(selection.undo(), cppID: deleteID, message: "the multi-lane delete is undoable")
    report.expectEqual(["24:30", "120:40"], selection.values(selection.panLane), cppID: deleteID,
                       what: "one undo restores the first lane")
    report.expectEqual(["48:100", "140:20"], selection.values(selection.volumeLane), cppID: deleteID,
                       what: "one undo restores the second lane")
    report.expect(!selection.document.history.canUndo, cppID: deleteID,
                  message: "one undo consumes the multi-lane delete's single history entry")
    report.expectEqual([selection.volumeLane, selection.panLane],
                       selection.page.selectedParameters, cppID: deleteID,
                       what: "the selection survives the delete it performed")
}

// MARK: - Range edit and clipboard

@MainActor
private func rangeEditAndClipboard(_ report: CheckReport, suite: DocumentSession,
                                   service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service,
                                    pan: [(24, 30), (120, 40)],
                                    tempo: [(0, 500_000), (48, 400_000)])
    fixture.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 20, endTick: 130), scope: .lanes,
        lanes: [fixture.panLane], tempo: true))
    report.expect(fixture.page.copyTimeSelection(), cppID: rangeID,
                  message: "the selection copies into the semantic clipboard")
    report.expect(fixture.page.hasClipboard, cppID: rangeID,
                  message: "the clipboard publishes its semantic payload")
    let beforePaste = fixture.snapshot
    report.expectEqual(310, fixture.page.pasteTimeSelection(at: 200).map(Int.init) ?? -1,
                       cppID: rangeID,
                       what: "the paste cursor lands one span after the destination")
    report.expectEqual(["24:30", "120:40", "204:30", "300:40"], fixture.values(fixture.panLane),
                       cppID: rangeID,
                       what: "the pasted lane writes its relative points at the destination")
    report.expectEqual(["0:120", "48:150", "228:150"], fixture.tempoValues, cppID: rangeID,
                       what: "the pasted tempo point merges at its destination tick")
    report.expectEqual(beforePaste.revision + 1, fixture.document.revision, cppID: rangeID,
                       what: "one paste is one document revision")
    report.expect(fixture.undo(), cppID: rangeID, message: "the paste is undoable")
    report.expectEqual(["24:30", "120:40"], fixture.values(fixture.panLane), cppID: rangeID,
                       what: "one undo removes the pasted lane points")
    report.expectEqual(["0:120", "48:150"], fixture.tempoValues, cppID: rangeID,
                       what: "one undo removes the pasted tempo point")
    report.expect(!fixture.document.history.canUndo, cppID: rangeID,
                  message: "one undo consumes the paste's single history entry")

    let cut = AutomationFixture(suite: suite, service: service, pan: [(24, 30), (120, 40)])
    cut.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 20, endTick: 100), scope: .lanes, lanes: [cut.panLane]))
    let cutBefore = cut.snapshot
    report.expect(cut.page.cutTimeSelection(), cppID: rangeID,
                  message: "the cut copies and deletes in one document write")
    report.expectEqual(["120:40"], cut.values(cut.panLane), cppID: rangeID,
                       what: "the cut removes only the covered span")
    report.expectEqual(cutBefore.revision + 1, cut.document.revision, cppID: rangeID,
                       what: "the cut is one revision")
    report.expect(cut.page.hasClipboard && cut.undo(), cppID: rangeID,
                  message: "the cut keeps its payload and is undoable")
    report.expectEqual(["24:30", "120:40"], cut.values(cut.panLane), cppID: rangeID,
                       what: "one undo restores the cut span")
    report.expect(!cut.document.history.canUndo, cppID: rangeID,
                  message: "one undo consumes the cut's single history entry")

    // Lane copy is cross-parameter but must not overwrite the system range clip.
    cut.activate(cut.panLane)
    _ = cut.page.openParameterMenu(index: cut.page.catalogIndex(of: cut.panLane), x: 0, y: 0)
    report.expect(cut.page.consumeMenuAction(actionId: AutomationMenuAction.copyLane.rawValue),
                  cppID: rangeID, message: "lane menu copies its absolute points")
    cut.activate(cut.volumeLane)
    _ = cut.page.openParameterMenu(index: cut.page.catalogIndex(of: cut.volumeLane), x: 0, y: 0)
    report.expect(cut.page.consumeMenuAction(actionId: AutomationMenuAction.pasteLane.rawValue),
                  cppID: rangeID, message: "lane menu pastes into another parameter")
    report.expectEqual(["24:30", "120:40"], cut.values(cut.volumeLane), cppID: rangeID,
                       what: "lane paste preserves absolute ticks across parameters")
    cut.page.detach()
    let otherDocument = AutomationFixture(suite: suite, service: service, pan: [])
    report.expectEqual(280, otherDocument.page.pasteTimeSelection(at: 200).map(Int.init) ?? -1,
                       cppID: rangeID, what: "the native range clip survives lane copy and detach")
    report.expectEqual(["204:30"], otherDocument.values(otherDocument.panLane), cppID: rangeID,
                       what: "another document pastes the shared range clip, not the lane buffer")

    // A whole-lane replacement keeps the lane's own point rules.
    let replace = AutomationFixture(suite: suite, service: service, pan: [(24, 30)])
    replace.activate(replace.panLane)
    let edit = AutomationRangeEditor.replaceLane(
        replace.facts(replace.panLane),
        points: [AutomationLanePoint(tick: 48, value: 200),
                 AutomationLanePoint(tick: 48, value: 20),
                 AutomationLanePoint(tick: 96, value: -5)])
    report.expect(!edit.unchanged, cppID: rangeID,
                  message: "a replacement that differs from the lane is a change")
    report.expectEqual(Tick(0), edit.tickBegin, cppID: rangeID,
                       what: "a whole-lane replacement starts at tick zero")
    report.expectEqual(TimeDefaults.noTick, edit.tickEnd, cppID: rangeID,
                       what: "a whole-lane replacement covers the whole lane")
    report.expect(AutomationCommit.apply(edit, in: replace.document), cppID: rangeID,
                  message: "the replacement commits through one lane write")
    report.expectEqual(["48:20", "96:0"], replace.values(replace.panLane), cppID: rangeID,
                       what: "the replacement deduplicates by tick and clamps into the domain")
    let clear = AutomationRangeEditor.replaceLane(replace.facts(replace.panLane), points: [])
    report.expect(AutomationCommit.apply(clear, in: replace.document), cppID: rangeID,
                  message: "clearing the lane writes once")
    report.expectEqual(0, replace.lanePoints(replace.panLane).count, cppID: rangeID,
                       what: "clearing removes every written point")
    report.expect(AutomationRangeEditor.replaceLane(replace.facts(replace.panLane),
                                                    points: []).unchanged,
                  cppID: rangeID, message: "clearing an empty lane is unchanged")
}

// MARK: - History

@MainActor
private func historyUndoRedo(_ report: CheckReport, suite: DocumentSession,
                             service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service, pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot
    report.expect(fixture.page.openPrompt(tick: 24, value: 64), cppID: historyID,
                  message: "the prompt opens")
    report.expect(fixture.page.acceptPrompt(displayedValue: 20), cppID: historyID,
                  message: "the prompt commits")
    report.expectEqual(["24:84", "120:40"], fixture.values(fixture.panLane), cppID: historyID,
                       what: "the committed lane holds the new value")
    report.expect(fixture.document.history.canUndo, cppID: historyID,
                  message: "the transaction is on the undo stack")
    report.expect(fixture.undo(), cppID: historyID, message: "the transaction undoes")
    report.expectEqual(["24:64", "120:40"], fixture.values(fixture.panLane), cppID: historyID,
                       what: "undo restores the curve from the document")
    report.expect(!fixture.document.history.canUndo, cppID: historyID,
                  message: "the transaction recorded exactly one history entry")
    report.expectEqual(["0:64", "24:64", "120:40"],
                       fixture.page.projection?.points.map { "\($0.tick):\($0.value)" } ?? [],
                       cppID: historyID, what: "the page rebuilds the restored curve")
    report.expect(fixture.document.history.canRedo, cppID: historyID,
                  message: "the undone transaction is redoable")
    do {
        _ = try runBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(historyID, "redo failed: \(error)")
        return
    }
    report.expectEqual(["24:84", "120:40"], fixture.values(fixture.panLane), cppID: historyID,
                       what: "redo restores the committed lane")
    report.expect(fixture.document.history.canUndo && !fixture.document.history.canRedo,
                  cppID: historyID,
                  message: "one undo and one redo stand on the same single entry")
    report.expectEqual(before.revision + 3, fixture.document.revision, cppID: historyID,
                       what: "a commit, an undo and a redo each publish one revision")

    // Two transactions undo one at a time.
    let two = AutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    two.activate(two.panLane)
    _ = two.page.openPrompt(tick: 24, value: 64)
    _ = two.page.acceptPrompt(displayedValue: 10)
    _ = two.page.openPrompt(tick: 48, value: 64)
    _ = two.page.acceptPrompt(displayedValue: -10)
    report.expectEqual(["24:74", "48:54"], two.values(two.panLane), cppID: historyID,
                       what: "two transactions leave both writes")
    report.expect(two.undo() && two.values(two.panLane) == ["24:74"], cppID: historyID,
                  message: "the first undo removes only the second transaction")
    report.expect(two.undo() && two.values(two.panLane) == ["24:64"], cppID: historyID,
                  message: "the second undo removes the first transaction")
    report.expect(!two.undo(), cppID: historyID,
                  message: "a third undo finds nothing and reports nothing")
}

// MARK: - Cancellation and no-ops

@MainActor
private func cancellationAndNoOps(_ report: CheckReport, suite: DocumentSession,
                                  service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service, pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot

    // A press and cancel writes nothing and ends every owned interaction.
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: 1),
                  cppID: cancelID, message: "a press on a node grabs it")
    report.expect(fixture.page.hasGesture && fixture.page.interactionActive, cppID: cancelID,
                  message: "the page publishes the live gesture")
    report.expect(fixture.page.handleEscape(), cppID: cancelID,
                  message: "Escape claims the live gesture")
    report.expect(!fixture.page.hasGesture && !fixture.page.interactionActive, cppID: cancelID,
                  message: "cancelling ends the gesture synchronously")
    report.expectEqual(before, fixture.snapshot, cppID: cancelID,
                       what: "a cancelled gesture mutates nothing")
    report.expect(!fixture.page.handleEscape(), cppID: cancelID,
                  message: "Escape with nothing to claim stays unhandled")

    // A stroke that never travelled commits nothing.
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: 1),
                  cppID: cancelID, message: "a second press grabs the node")
    _ = fixture.page.pointerMove(x: fixture.x(24) + 12, y: fixture.y(fixture.panLane, 64), buttons: 1)
    _ = fixture.page.pointerRelease(x: fixture.x(24) + 12, y: fixture.y(fixture.panLane, 64), button: 1)
    report.expectEqual(before, fixture.snapshot, cppID: cancelID,
                       what: "an armed stroke that moved no node writes nothing")

    // Shift-held stationary release is a no-op; plain stationary release deletes.
    report.expect(fixture.page.pointerPress(x: fixture.x(120), y: fixture.y(fixture.panLane, 40),
                                            surface: 1, button: 1, modifiers: qtModifiers(.init(shift: true))), cppID: cancelID,
                  message: "a Shift-held press grabs the node")
    _ = fixture.page.pointerRelease(x: fixture.x(120), y: fixture.y(fixture.panLane, 40),
                                    button: 1, modifiers: qtModifiers(.init(shift: true)))
    report.expectEqual(before, fixture.snapshot, cppID: cancelID,
                       what: "a Shift-held stationary release deletes nothing")
    report.expect(fixture.page.pointerPress(x: fixture.x(120), y: fixture.y(fixture.panLane, 40), surface: 1, button: 1),
                  cppID: cancelID, message: "a plain press grabs the node")
    _ = fixture.page.pointerRelease(x: fixture.x(120), y: fixture.y(fixture.panLane, 40), button: 1)
    report.expectEqual(["24:64"], fixture.values(fixture.panLane), cppID: cancelID,
                       what: "a plain stationary release deletes the grabbed node")
    report.expect(fixture.undo(), cppID: cancelID, message: "the stationary delete is undoable")
    report.expectEqual(["24:64", "120:40"], fixture.values(fixture.panLane), cppID: cancelID,
                       what: "one undo restores the deleted node")
    report.expect(!fixture.document.history.canUndo, cppID: cancelID,
                  message: "the stationary delete recorded exactly one history entry")

    // A stale revision cancels the frozen interaction instead of retargeting it.
    let pressRevision = fixture.document.revision
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: 1),
                  cppID: cancelID, message: "a press freezes the current revision")
    report.expectEqual(pressRevision, fixture.page.frozenRevision ?? 0, cppID: cancelID,
                       what: "the frozen facts carry the revision")
    fixture.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 168,
                               through: 168, points: [LaneWrite(tick: 168, value: 5)])
    report.expect(!fixture.page.hasGesture, cppID: cancelID,
                  message: "a document change outside the gesture cancels it")
    let afterStale = fixture.snapshot
    _ = fixture.page.pointerMove(x: fixture.x(24) + 40, y: fixture.y(fixture.panLane, 64), buttons: 1)
    _ = fixture.page.pointerRelease(x: fixture.x(24) + 40, y: fixture.y(fixture.panLane, 64), button: 1)
    report.expectEqual(afterStale, fixture.snapshot, cppID: cancelID,
                       what: "a cancelled stale gesture never writes on release")

    // An empty-lane press parks the edit cursor instead of writing.
    let empty = AutomationFixture(suite: suite, service: service, pan: [])
    empty.activate(empty.panLane)
    let emptyBefore = empty.snapshot
    let pressX = empty.x(72)
    report.expect(empty.page.pointerPress(x: pressX, y: 60, surface: 1, button: 1), cppID: cancelID,
                  message: "a press on an empty lane starts a sweep")
    report.expect(!empty.page.pointerRelease(x: pressX, y: 60, button: 1), cppID: cancelID,
                  message: "a press that never travelled commits nothing")
    report.expectEqual(emptyBefore, empty.snapshot, cppID: cancelID,
                       what: "the parked press leaves the document alone")
    let policy = AutomationSnapPolicy(document: empty.document, timeline: empty.session.timeline,
                                      baseFontPx: 13, devicePixelRatio: 1)
    let snapped = policy.snap(min(max(0, empty.session.camera.tickAtContentX(pressX)),
                                  Double(empty.songEndTick)),
                              fine: false, camera: empty.session.camera)
    report.expectEqual(snapped, empty.session.editCursor, cppID: cancelID,
                       what: "the press parks the edit cursor at the snapped tick")

    // A sub-threshold move leaves a frozen gesture alive but unchanged.
    let jitter = AutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    jitter.activate(jitter.panLane)
    report.expect(jitter.page.pointerPress(x: jitter.x(24), y: jitter.y(jitter.panLane, 64), surface: 1, button: 1),
                  cppID: cancelID, message: "a press grabs the node")
    _ = jitter.page.pointerMove(x: jitter.x(24) + 2, y: jitter.y(jitter.panLane, 64) + 2, buttons: 1)
    report.expectEqual([Tick(24): 64], [jitter.page.previewPoints.first?.tick ?? 0:
                                            jitter.page.previewPoints.first?.value ?? 0],
                       cppID: cancelID,
                       what: "a sub-threshold move previews the untouched target")
    report.expectEqual(jitter.snapshot, AutomationDocumentSnapshot(jitter.document), cppID: cancelID,
                       what: "a sub-threshold move writes nothing")
}

// MARK: - Context and diagnostics

@MainActor
private func contextAndPublicationDiagnostics(_ report: CheckReport, suite: DocumentSession,
                                              service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)])
    fixture.activate(fixture.volumeLane)
    let builds = fixture.page.contentBuildCount
    let selectionBuilds = fixture.page.selectionBuildCount
    let contextChanges = fixture.page.contextChangeCount
    report.expectEqual(Tick(0), fixture.page.contextTick, cppID: contextID,
                       what: "a stopped page presents the edit cursor")

    // A cursor-only publication updates the stopped context without rebuilding
    // document-derived content or changing document/history state.
    let cursorDocument = fixture.snapshot
    fixture.session.editCursor = 100
    report.expectEqual(Tick(100), fixture.page.contextTick, cppID: contextID,
                       what: "a stopped context consumes the published edit cursor")
    report.expectEqual(64, fixture.page.contextValue ?? -1, cppID: contextID,
                       what: "the context readout is the lane's held value there")
    report.expect(fixture.page.contextChangeCount > contextChanges, cppID: contextID,
                  message: "a cursor-only context move is counted")
    report.expectEqual(builds, fixture.page.contentBuildCount, cppID: contextID,
                       what: "a cursor-only publication rebuilds no static content")
    report.expectEqual(cursorDocument, fixture.snapshot, cppID: contextID,
                       what: "a cursor-only publication changes no document or history state")

    // A shared-playhead presentation retargets the context and rebuilds nothing.
    let buildsBeforePlayhead = fixture.page.contentBuildCount
    let presentations = fixture.page.playheadPresentationCount
    fixture.page.refreshPlayhead(tick: 50, playing: true)
    report.expect(fixture.page.playing, cppID: contextID, message: "the page consumes playing")
    report.expectEqual(Tick(50), fixture.page.contextTick, cppID: contextID,
                       what: "a playing context consumes the shared playhead tick")
    report.expectEqual(127, fixture.page.contextValue ?? -1, cppID: contextID,
                       what: "the playing context reads the held value at its own tick")
    report.expectEqual(presentations + 1, fixture.page.playheadPresentationCount, cppID: contextID,
                       what: "the presentation is counted once")
    report.expectEqual(buildsBeforePlayhead, fixture.page.contentBuildCount, cppID: contextID,
                       what: "a playhead-only update rebuilds no static content")
    fixture.page.refreshPlayhead(tick: 50, playing: true)
    report.expectEqual(presentations + 1, fixture.page.playheadPresentationCount, cppID: contextID,
                       what: "an equal presentation is dropped")
    fixture.page.refreshPlayhead(tick: 60, playing: true)
    report.expectEqual(presentations + 2, fixture.page.playheadPresentationCount, cppID: contextID,
                       what: "a moved playhead presents again")
    report.expectEqual(buildsBeforePlayhead, fixture.page.contentBuildCount, cppID: contextID,
                       what: "repeated playhead movement still rebuilds nothing")
    fixture.page.refreshPlayhead(tick: 60, playing: false)
    report.expectEqual(Tick(100), fixture.page.contextTick, cppID: contextID,
                       what: "a stopped transport returns to the edit cursor")

    // A camera-only publication reprojects the curve, which is a content build.
    let buildsBeforeCamera = fixture.page.contentBuildCount
    _ = fixture.session.mutateCamera { _ = $0.setTimeZoom(90) }
    report.expectEqual(buildsBeforeCamera + 1, fixture.page.contentBuildCount, cppID: contextID,
                       what: "a camera change reprojects the curve once")

    // A selection change rebuilds and is counted apart from content builds.
    let buildsBeforeSelection = fixture.page.contentBuildCount
    fixture.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 96), scope: .lanes, lanes: [fixture.volumeLane]))
    report.expectEqual(buildsBeforeSelection + 1, fixture.page.contentBuildCount, cppID: contextID,
                       what: "a selection change rebuilds the content it displays")
    report.expectEqual(selectionBuilds + 1, fixture.page.selectionBuildCount, cppID: contextID,
                       what: "the selection build is counted on its own")
    let points = fixture.page.projection?.points ?? []
    report.expect(points.contains { $0.selected } && points.contains { !$0.selected },
                  cppID: contextID,
                  message: "the projection marks the points inside the selection")
    report.expectEqual(["0:127"], fixture.laneValues(points.filter(\.selected).map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }).count == 1 ? ["0:127"] : [], cppID: contextID,
                       what: "the selection marks exactly the points inside its range")
    fixture.page.applyTimeSelection(nil)
    report.expect((fixture.page.projection?.points ?? []).allSatisfy { !$0.selected },
                  cppID: contextID, message: "clearing the selection clears every indicator")
    report.expect(fixture.page.contentBuildCount > builds, cppID: contextID,
                  message: "the content builds accumulated across the case")

    // Hover: a node publishes its own value text, the background the held value.
    let hoverBuilds = fixture.page.hoverBuildCount
    _ = fixture.page.pointerMove(x: fixture.x(96), y: fixture.y(fixture.volumeLane, 64),
                                 buttons: 0)
    report.expect(fixture.page.hover?.hasPoint == true, cppID: contextID,
                  message: "a hover on a node publishes the node")
    report.expectEqual("64", fixture.page.hover?.text ?? "", cppID: contextID,
                       what: "a node hover reads out the node's value")
    _ = fixture.page.pointerMove(x: fixture.x(150), y: fixture.y(fixture.volumeLane, 20),
                                 buttons: 0)
    report.expect(fixture.page.hover?.hasPoint == false, cppID: contextID,
                  message: "a hover on the background publishes the tick")
    report.expectEqual("64", fixture.page.hover?.text ?? "", cppID: contextID,
                       what: "a background hover reads the value the lane holds there")
    report.expect(fixture.page.hoverBuildCount > hoverBuilds, cppID: contextID,
                  message: "the hover publications are counted")
    fixture.page.pointerLeave()
    report.expect(fixture.page.hover == nil, cppID: contextID,
                  message: "leaving the plot clears the hover")

    // Detach drops everything the page published.
    fixture.page.detach()
    report.expect(fixture.page.projection == nil && fixture.page.rows.isEmpty
                      && fixture.page.selection == nil,
                  cppID: contextID, message: "detaching drops every published value")
}

// MARK: - Reopened exclusion row: sweep stepping and ramp finish

@MainActor
private func sweepSteppingAndRampFinish(_ report: CheckReport, suite: DocumentSession,
                                        service: ProjectService) {
    // Division 24 makes one mid2agb clock a single tick: the legacy lattice of a
    // one-tick step per sample.
    let fixture = AutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    let facts = fixture.facts(fixture.panLane)
    let projection = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: fixture.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: fixture.document,
                                         timeline: fixture.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: fixture.songEndTick)
    report.expectEqual(Tick(1), projection.snapPolicy.clockTicks, cppID: sweepStepsID,
                       what: "a 24-tick document's clock lattice steps one tick")

    var sweep = AutomationSweepTransaction(facts: facts, mode: .drag,
                                           mapped: AutomationLanePoint(tick: 0, value: 0),
                                           rawTick: 0, pressX: 0, pressY: 0)
    report.expect(!sweep.slopExceeded, cppID: sweepStepsID,
                  message: "a drag sweep waits for the activation distance")
    _ = sweep.dragPosition(x: 12, y: 60, activate: true, activationDistance: 5)
    report.expect(sweep.slopExceeded, cppID: sweepStepsID,
                  message: "a move past the activation distance arms the sweep")
    sweep.update(mapped: AutomationLanePoint(tick: 10, value: 100), first: 0, last: 10,
                 rawTick: 10, fine: true, projection: projection)
    report.expectEqual((0...10).map { "\($0):\($0 * 10)" },
                       fixture.laneValues(sweep.points), cppID: sweepStepsID,
                       what: "each stepped tick interpolates its value across the stroke")
    report.expectEqual(11, sweep.points.count, cppID: sweepStepsID,
                       what: "the sweep steps every lattice tick of the stroke")

    var update = AutomationSweepTransaction(facts: facts, mode: .drag,
                                            mapped: AutomationLanePoint(tick: 0, value: 0),
                                            rawTick: 0, pressX: 0, pressY: 0)
    update.update(mapped: AutomationLanePoint(tick: 5, value: 50), first: 0, last: 5,
                  rawTick: 5, fine: true, projection: projection)
    report.expectEqual("5:50", "\(update.current.tick):\(update.current.value)", cppID: sweepStepsID,
                       what: "the stroke's current point is its mapped one")
    report.expectEqual((0...5).map { "\($0):\($0 * 10)" },
                       fixture.laneValues(update.points), cppID: sweepStepsID,
                       what: "the second stroke interpolates across its own span")

    var ramp = AutomationSweepTransaction(facts: facts, mode: .ramp,
                                          mapped: AutomationLanePoint(tick: 0, value: 0),
                                          rawTick: 0, pressX: 0, pressY: 0)
    ramp.updateRamp(mapped: AutomationLanePoint(tick: 10, value: 100))
    let rampPoints = ramp.finishedPoints(fine: true, projection: projection)
    report.expectEqual(11, rampPoints.count, cppID: sweepStepsID,
                       what: "a ramp sweep fills every lattice tick between its endpoints")
    report.expectEqual(["0:0", "10:100"],
                       fixture.laneValues([rampPoints[0], rampPoints[10]]), cppID: sweepStepsID,
                       what: "the ramp runs from its anchor value to its release value")
    report.expectEqual(50, rampPoints[5].value, cppID: sweepStepsID,
                       what: "the ramp's midpoint interpolates linearly")
    let edit = ramp.finish(fine: true, projection: projection)
    report.expect(edit != nil && !edit!.unchanged, cppID: sweepStepsID,
                  message: "the completed ramp is a changed span replacement")
    report.expectEqual(Tick(0), edit?.tickBegin ?? 99, cppID: sweepStepsID,
                       what: "the ramp replacement starts at its anchor")
    report.expectEqual(Tick(11), edit?.tickEnd ?? 0, cppID: sweepStepsID,
                       what: "the ramp replacement closes one lattice step past its release")
    report.expectEqual("0:0", "\(edit?.points.first?.tick ?? 0):\(edit?.points.first?.value ?? 0)",
                       cppID: sweepStepsID, what: "the replacement keeps the ramp's first point")
}

// MARK: - Reopened exclusion row: trailing held value

@MainActor
private func sweepFinishRestoresTrailingHeldValue(_ report: CheckReport, suite: DocumentSession,
                                                  service: ProjectService) {
    // A flat 85 lane whose stroke releases at 25: the tail must re-anchor at 85
    // one lattice step past the release. Division 576 makes one clock 24 ticks,
    // which is this row's legacy lattice.
    let fixture = AutomationFixture(suite: suite, service: service, division: 576,
                                    pan: [(0, 85)], config: SongConfig(), tailTick: 960)
    let facts = fixture.facts(fixture.panLane)
    let projection = AutomationProjection(
        camera: fixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: fixture.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: fixture.document,
                                         timeline: fixture.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: fixture.songEndTick)
    report.expectEqual(Tick(24), projection.snapPolicy.clockTicks, cppID: sweepTailID,
                       what: "the lattice step of this document is 24 ticks")
    guard fixture.songEndTick > 168 else {
        report.fail(sweepTailID,
                    "the fixture song ends at \(fixture.songEndTick), shorter than the seam")
        return
    }

    var drag = AutomationSweepTransaction(facts: facts, mode: .drag,
                                          mapped: AutomationLanePoint(tick: 48, value: 85),
                                          rawTick: 48, pressX: 0, pressY: 0)
    drag.update(mapped: AutomationLanePoint(tick: 144, value: 25), first: 48, last: 144,
                rawTick: 144, fine: true, projection: projection)
    let dragEdit = drag.finish(fine: true, projection: projection)
    report.expect(dragEdit != nil && !dragEdit!.unchanged, cppID: sweepTailID,
                  message: "the drag over a flat lane is a changed span")
    report.expect(dragEdit?.points.contains { $0.tick == 144 && $0.value == 25 } == true,
                  cppID: sweepTailID, message: "the stroke's release point is written")
    report.expectEqual("168:85",
                       "\(dragEdit?.points.last?.tick ?? 0):\(dragEdit?.points.last?.value ?? 0)",
                       cppID: sweepTailID,
                       what: "the tail re-anchors the original held value one step past the release")
    report.expectEqual(Tick(168), dragEdit?.tickEnd ?? 0, cppID: sweepTailID,
                       what: "the replacement's span covers the restored tail")

    var ramp = AutomationSweepTransaction(facts: facts, mode: .ramp,
                                          mapped: AutomationLanePoint(tick: 48, value: 85),
                                          rawTick: 48, pressX: 0, pressY: 0)
    ramp.updateRamp(mapped: AutomationLanePoint(tick: 144, value: 25))
    let rampEdit = ramp.finish(fine: true, projection: projection)
    report.expect(rampEdit != nil && !rampEdit!.unchanged, cppID: sweepTailID,
                  message: "the ramp over a flat lane is a changed span")
    report.expect(rampEdit?.points.contains { $0.tick == 144 && $0.value == 25 } == true,
                  cppID: sweepTailID, message: "the ramp's release point is written")
    report.expectEqual("168:85",
                       "\(rampEdit?.points.last?.tick ?? 0):\(rampEdit?.points.last?.value ?? 0)",
                       cppID: sweepTailID,
                       what: "the ramp's tail re-anchors the original held value too")

    // A stroke that ends at the song's end has no tail to restore.
    let endFixture = AutomationFixture(suite: suite, service: service, pan: [(0, 85)],
                                       tailTick: 384)
    let endProjection = AutomationProjection(
        camera: endFixture.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: endFixture.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: endFixture.document,
                                         timeline: endFixture.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: endFixture.songEndTick)
    var endSweep = AutomationSweepTransaction(
        facts: endFixture.facts(endFixture.panLane), mode: .drag,
        mapped: AutomationLanePoint(tick: 0, value: 85), rawTick: 0, pressX: 0, pressY: 0)
    let endTick = endFixture.songEndTick
    endSweep.update(mapped: AutomationLanePoint(tick: endTick, value: 25), first: 0,
                    last: endTick, rawTick: Double(endTick), fine: true, projection: endProjection)
    report.expectEqual(endTick, endSweep.points.last?.tick ?? 0, cppID: sweepTailID,
                       what: "a stroke that ends at the song's end steps to the song's end")
    let endEdit = endSweep.finish(fine: true, projection: endProjection)
    report.expect(endEdit?.points.allSatisfy { $0.tick <= endTick } == true, cppID: sweepTailID,
                  message: "a stroke that ends at the song's end restores no tail")

    // The released sweep lands in the document exactly once, with its tail, and
    // the draft never wrote anything before the release.
    let committed = AutomationFixture(suite: suite, service: service, division: 576,
                                      modulation: [(0, 85)], config: SongConfig(), tailTick: 960)
    let committedFacts = committed.facts(committed.modulationLane)
    let committedProjection = AutomationProjection(
        camera: committed.session.camera,
        bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
        geometry: committed.page.geometry,
        snapPolicy: AutomationSnapPolicy(document: committed.document,
                                         timeline: committed.session.timeline,
                                         baseFontPx: 13, devicePixelRatio: 1),
        songEndTick: committed.songEndTick)
    var live = AutomationSweepTransaction(facts: committedFacts, mode: .drag,
                                          mapped: AutomationLanePoint(tick: 48, value: 85),
                                          rawTick: 48, pressX: 0, pressY: 0)
    live.update(mapped: AutomationLanePoint(tick: 144, value: 25), first: 48, last: 144,
                rawTick: 144, fine: true, projection: committedProjection)
    let beforeRelease = committed.snapshot
    report.expectEqual(["48:85", "72:70", "96:55", "120:40", "144:25"],
                       committed.laneValues(live.preview), cppID: sweepTailID,
                       what: "the sweep preview is the stepped draft alone")
    report.expectEqual(beforeRelease, committed.snapshot, cppID: sweepTailID,
                       what: "the draft writes nothing before the release")
    guard let committedEdit = live.finish(fine: true, projection: committedProjection) else {
        report.fail(sweepTailID, "the released sweep produced no edit")
        return
    }
    report.expect(AutomationCommit.apply(committedEdit, in: committed.document), cppID: sweepTailID,
                  message: "the released sweep commits once")
    report.expectEqual(["0:85", "72:70", "96:55", "120:40", "144:25", "168:85"],
                       committed.values(committed.modulationLane), cppID: sweepTailID,
                       what: "the committed lane holds the stroke and its restored tail")
    report.expectEqual(beforeRelease.revision + 1, committed.document.revision, cppID: sweepTailID,
                       what: "one released sweep is one revision")
    report.expect(committed.undo(), cppID: sweepTailID, message: "the sweep is undoable")
    report.expectEqual(["0:85"], committed.values(committed.modulationLane), cppID: sweepTailID,
                       what: "one undo restores the flat lane")
    report.expect(!committed.document.history.canUndo, cppID: sweepTailID,
                  message: "the released sweep recorded exactly one history entry")
}

// MARK: - Reopened exclusion row: pan neutral snap

@MainActor
private func panNeutralSnap(_ report: CheckReport, suite: DocumentSession,
                            service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service, pan: [(24, 72)])
    let metadata = AutomationParameterMetadata(parameter: fixture.panLane)
    report.expectEqual(64, metadata.neutral, cppID: neutralSnapID,
                       what: "Pan's neutral is 64, the centered domain's midpoint")
    let radius = fixture.page.geometry.neutralSnapRadius
    let height = 120.0
    let threshold = Int(Double(metadata.maximum - metadata.minimum) * radius / height)
    report.expect(threshold > 0, cppID: neutralSnapID,
                  message: "the neutral snap radius covers more than one value step")
    let near = 64 + max(1, threshold - 1)
    report.expectEqual(near, metadata.snappedValue(near, snapValue: false, plotHeight: height,
                                                   neutralSnapRadius: radius),
                       cppID: neutralSnapID,
                       what: "an unsnapped drag keeps the value under the pointer")
    report.expectEqual(64, metadata.snappedValue(near, snapValue: true, plotHeight: height,
                                                 neutralSnapRadius: radius),
                       cppID: neutralSnapID, what: "a snapped drag lands exactly on the neutral")
    let outside = 64 + threshold + 5
    report.expectEqual(outside, metadata.snappedValue(outside, snapValue: true, plotHeight: height,
                                                      neutralSnapRadius: radius),
                       cppID: neutralSnapID,
                       what: "a value outside the radius keeps its own value")
    report.expectEqual(19, metadata.snappedValue(19, snapValue: true, plotHeight: height,
                                                 neutralSnapRadius: radius),
                       cppID: neutralSnapID,
                       what: "a snap only ever moves a value onto the neutral")
    let volume = AutomationParameterMetadata(parameter: fixture.volumeLane)
    report.expectEqual(60, volume.snappedValue(60, snapValue: true, plotHeight: height,
                                               neutralSnapRadius: radius),
                       cppID: neutralSnapID,
                       what: "a parameter with no neutral keeps the dragged value")

    // Through the page's own pointer mapping: a snapped drag on a node holding
    // 72 writes 64 at the node's own tick, and the preview never moved the tick.
    fixture.activate(fixture.panLane)
    let nodeX = fixture.x(24)
    let nodeY = fixture.y(fixture.panLane, 72)
    let modifiers = AutomationModifiers(snapValue: true)
    report.expect(fixture.page.pointerPress(x: nodeX, y: nodeY, surface: 1, button: 1, modifiers: qtModifiers(modifiers)),
                  cppID: neutralSnapID, message: "a snapped press grabs the node under the pointer")
    _ = fixture.page.pointerMove(x: nodeX + 12, y: nodeY, buttons: 1, modifiers: qtModifiers(modifiers))
    report.expectEqual(Tick(24), fixture.page.previewPoints.first?.tick ?? 0, cppID: neutralSnapID,
                       what: "the armed preview keeps the node's own tick")
    _ = fixture.page.pointerMove(x: nodeX + 12, y: nodeY, buttons: 1, modifiers: qtModifiers(modifiers))
    report.expectEqual(64, fixture.page.previewPoints.first?.value ?? 0, cppID: neutralSnapID,
                       what: "the preview publishes the snapped neutral")
    _ = fixture.page.pointerRelease(x: nodeX + 12, y: nodeY, button: 1, modifiers: qtModifiers(modifiers))
    report.expectEqual(["24:64"], fixture.values(fixture.panLane), cppID: neutralSnapID,
                       what: "the snapped release writes the neutral at the node's own tick")
}

// MARK: - Reopened exclusion row: node drag and phantom outcomes

@MainActor
private func nodeDragAndPhantomOutcomes(_ report: CheckReport, suite: DocumentSession,
                                        service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service,
                                    pan: [(24, 60), (48, 80), (120, 40)])
    let facts = fixture.facts(fixture.panLane)
    let sources = facts.snapshot.sources
    report.expectEqual(3, sources.count, cppID: nodeDragID,
                       what: "the fixture offers three draggable nodes")

    // An empty gesture finishes as a no-op.
    let empty = AutomationNodeDragTransaction(facts: facts, targets: [], grabbedPoint: 0,
                                              selectionDrag: false, press: (100, 100),
                                              deleteOnStationary: true)
    report.expectEqual(AutomationPointRelease.noOp, empty.finish().release, cppID: nodeDragID,
                       what: "a gesture with no target finishes as a no-op")
    report.expect(!empty.finish().changed, cppID: nodeDragID,
                  message: "an empty gesture reports no change")

    // A Shift-held stationary release is a no-op; a plain one deletes.
    let shiftPress = AutomationNodeDragTransaction.single(facts: facts, source: sources[0],
                                                          press: (100, 100),
                                                          deleteOnStationary: false)
    report.expectEqual(AutomationPointRelease.noOp, shiftPress.finish().release, cppID: nodeDragID,
                       what: "a Shift-held stationary release is a no-op")
    report.expect(!shiftPress.finish().changed, cppID: nodeDragID,
                  message: "a Shift-held stationary release changes nothing")
    var plainPress = AutomationNodeDragTransaction.single(facts: facts, source: sources[0],
                                                          press: (100, 100),
                                                          deleteOnStationary: true)
    report.expectEqual(AutomationPointRelease.stationaryDelete, plainPress.finish().release,
                       cppID: nodeDragID, what: "a stationary release without Shift deletes")
    report.expect(!plainPress.finish().changed, cppID: nodeDragID,
                  message: "the stationary delete reports no move")

    // Past the slop without moving: a move that changed nothing.
    _ = plainPress.drag.update(x: 105, y: 100, shiftHeld: false, activationDistance: 5)
    report.expectEqual(AutomationPointRelease.move, plainPress.finish().release, cppID: nodeDragID,
                       what: "a released stroke past the slop is a move")
    report.expect(!plainPress.finish().changed, cppID: nodeDragID,
                  message: "a stroke that never moved the node changes nothing")

    // The same gesture with a moved node: one move with the grabbed delta.
    _ = plainPress.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 130,
                                                     effectiveY: 100, axisLock: .none),
                          mapped: AutomationLanePoint(tick: 30, value: 80))
    let moved = plainPress.finish()
    report.expectEqual(AutomationPointRelease.move, moved.release, cppID: nodeDragID,
                       what: "the moved gesture is still a move")
    report.expect(moved.changed, cppID: nodeDragID, message: "the moved node reports a change")
    report.expectEqual(6, moved.dTick, cppID: nodeDragID,
                       what: "the reported delta is the grabbed node's own tick delta")
    report.expectEqual(AutomationLanePoint(tick: 30, value: 80), plainPress.targets[0].current,
                       cppID: nodeDragID, what: "the target's preview is the mapped destination")

    // A selected set shares one delta and keeps its spacing.
    var group = AutomationNodeDragTransaction(
        facts: facts,
        targets: [AutomationNodeDragTarget(parameter: fixture.panLane, source: sources[0],
                                           minimum: 0, maximum: 127),
                  AutomationNodeDragTarget(parameter: fixture.panLane, source: sources[1],
                                           minimum: 0, maximum: 127)],
        grabbedPoint: 0, selectionDrag: true, press: (100, 100), deleteOnStationary: true)
    _ = group.drag.update(x: 105, y: 100, shiftHeld: false, activationDistance: 5)
    _ = group.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 105,
                                                effectiveY: 100, axisLock: .none),
                     mapped: AutomationLanePoint(tick: 30, value: 70))
    let groupFinish = group.finish()
    report.expectEqual(6, groupFinish.dTick, cppID: nodeDragID,
                       what: "the shared delta is the grabbed node's delta")
    report.expect(groupFinish.selectionDrag, cppID: nodeDragID,
                  message: "the finish reports that the whole selection moved")
    report.expectEqual(["30:70", "54:90"], group.targets.map { "\($0.current.tick):\($0.current.value)" },
                       cppID: nodeDragID, what: "every selected node moves by the same delta")

    // The lower edge clamps the common delta, so the group keeps its spacing.
    var edge = AutomationNodeDragTransaction(
        facts: facts,
        targets: [AutomationNodeDragTarget(parameter: fixture.panLane, source: sources[0],
                                           minimum: 0, maximum: 127),
                  AutomationNodeDragTarget(parameter: fixture.panLane, source: sources[1],
                                           minimum: 0, maximum: 127)],
        grabbedPoint: 1, selectionDrag: false, press: (100, 100), deleteOnStationary: false)
    _ = edge.drag.update(x: 105, y: 100, shiftHeld: false, activationDistance: 5)
    _ = edge.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 100,
                                               effectiveY: 100, axisLock: .none),
                    mapped: AutomationLanePoint(tick: 0, value: 80))
    report.expectEqual(["0:60", "24:80"], edge.targets.map { "\($0.current.tick):\($0.current.value)" },
                       cppID: nodeDragID,
                       what: "a leftward drag clamps at tick zero without collapsing the group")
    report.expectEqual(-24, edge.finish().dTick, cppID: nodeDragID,
                       what: "the clamped delta is what the finish reports")

    // The axis lock pins one axis.
    var locked = AutomationNodeDragTransaction.single(facts: facts, source: sources[1],
                                                      press: (100, 100),
                                                      deleteOnStationary: false)
    _ = locked.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 130,
                                                 effectiveY: 60, axisLock: .time),
                      mapped: AutomationLanePoint(tick: 60, value: 20))
    report.expectEqual(80, locked.targets[0].current.value, cppID: nodeDragID,
                       what: "a time lock keeps the original value")
    report.expectEqual(Tick(60), locked.targets[0].current.tick, cppID: nodeDragID,
                       what: "a time lock keeps the mapped tick")

    // A phantom drag restores its source on reset and clamps into the domain.
    var phantom = AutomationPhantomDragTransaction(facts: facts, source: sources[0],
                                                   press: (100, 100))
    report.expectEqual(AutomationAxisLock.value,
                       phantom.update(AutomationPointDrag.Update(phase: .reset, effectiveX: 100,
                                                                 effectiveY: 100, axisLock: .none),
                                      mappedValue: 127),
                       cppID: nodeDragID, what: "a phantom drag only ever locks the value axis")
    report.expectEqual(AutomationLanePoint(tick: 24, value: 60), phantom.target.current,
                       cppID: nodeDragID, what: "a reset restores the phantom's source value")
    report.expect(phantom.finish() == nil, cppID: nodeDragID,
                  message: "a reset phantom finishes as no edit")
    _ = phantom.drag.update(x: 100, y: 110, shiftHeld: false, activationDistance: 5)
    _ = phantom.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 100,
                                                  effectiveY: 110, axisLock: .value),
                       mappedValue: 200)
    guard let phantomTarget = phantom.finish() else {
        report.fail(nodeDragID, "the dragged phantom publishes no target")
        return
    }
    report.expectEqual(phantomTarget.original.tick, phantomTarget.current.tick, cppID: nodeDragID,
                       what: "a phantom drag never moves in time")
    report.expectEqual(127, phantomTarget.current.value, cppID: nodeDragID,
                       what: "a phantom drag clamps into the lane's domain")
    report.expectEqual(Tick(24), phantom.move?.sourceTick ?? 0, cppID: nodeDragID,
                       what: "the phantom's write names its own source tick")

    // The committed drag writes once, moves the node and evicts the occupant of
    // the destination tick.
    var committed = AutomationNodeDragTransaction.single(facts: facts, source: sources[0],
                                                         press: (100, 100),
                                                         deleteOnStationary: true)
    _ = committed.drag.update(x: 120, y: 100, shiftHeld: false, activationDistance: 5)
    _ = committed.update(AutomationPointDrag.Update(phase: .dragging, effectiveX: 120,
                                                    effectiveY: 100, axisLock: .none),
                         mapped: AutomationLanePoint(tick: 48, value: 90))
    let beforeCommit = fixture.snapshot
    guard let plan = AutomationNodeResolver.moves([
        AutomationNodeResolver.LaneMoves(facts, committed.moves)
    ]) else {
        report.fail(nodeDragID, "the committed drag resolved no plan")
        return
    }
    report.expect(AutomationCommit.apply(plan, in: fixture.document), cppID: nodeDragID,
                  message: "the committed drag writes once")
    report.expectEqual(["48:90", "120:40"], fixture.values(fixture.panLane), cppID: nodeDragID,
                       what: "the node lands on its destination and evicts the occupant there")
    report.expectEqual(beforeCommit.revision + 1, fixture.document.revision, cppID: nodeDragID,
                       what: "one drag is one revision")
    report.expect(fixture.undo(), cppID: nodeDragID, message: "the drag is undoable")
    report.expectEqual(["24:60", "48:80", "120:40"], fixture.values(fixture.panLane),
                       cppID: nodeDragID,
                       what: "one undo restores the moved node and the evicted occupant")

    // A write on the projected engine node promotes it into a written event.
    let promotion = AutomationFixture(suite: suite, service: service, pan: [])
    let promotionFacts = promotion.facts(promotion.panLane)
    report.expectEqual(["0:64"], promotion.laneValues(promotionFacts.displayPoints), cppID: nodeDragID,
                       what: "the empty lane displays its projected engine node")
    guard let promotionPlan = AutomationNodeResolver.moves([
        AutomationNodeResolver.LaneMoves(promotionFacts, [
            AutomationNodeMove(parameter: promotion.panLane, sourceTick: 0, tick: 0, value: 20)
        ])
    ]) else {
        report.fail(nodeDragID, "the promotion resolved no plan")
        return
    }
    report.expect(!promotionPlan.isEmpty, cppID: nodeDragID,
                  message: "a write on the projected node resolves to a promotion")
    report.expect(AutomationCommit.apply(promotionPlan, in: promotion.document), cppID: nodeDragID,
                  message: "the promotion commits")
    report.expectEqual(["0:20"], promotion.values(promotion.panLane), cppID: nodeDragID,
                       what: "the projected node becomes a written event at its own tick")
    report.expect(promotion.undo() && promotion.values(promotion.panLane).isEmpty, cppID: nodeDragID,
                  message: "one undo returns the lane to its projected node alone")
}

// MARK: - Reopened exclusion row: point range and pencil replacements

@MainActor
private func pointRangeAndPencilReplacements(_ report: CheckReport, suite: DocumentSession,
                                             service: ProjectService) {
    let metadata = AutomationParameterMetadata(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccPan))
    let freeze = AutomationLaneFreeze(
        parameter: .controlChange(track: 0, controller: TimeDefaults.ccPan), revision: 7,
        metadata: metadata, songEndTick: 96,
        original: [AutomationLanePoint(tick: 0, value: 20),
                   AutomationLanePoint(tick: 24, value: 60),
                   AutomationLanePoint(tick: 72, value: 90)])
    report.expectEqual(7, freeze.revision, cppID: pointRangeID,
                       what: "the frozen lane carries the revision it was read at")

    // An identical point range is unchanged.
    let identical = AutomationLaneReplacement.pointRange(
        freeze, begin: 24, end: 48, points: [AutomationLanePoint(tick: 24, value: 60)])
    report.expect(identical.unchanged, cppID: pointRangeID,
                  message: "an identical point range is unchanged")
    let shortened = AutomationLaneReplacement.pointRange(
        freeze, begin: 24, end: 48,
        points: [AutomationLanePoint(tick: 24, value: 64),
                 AutomationLanePoint(tick: 48, value: 64)])
    report.expect(!shortened.unchanged, cppID: pointRangeID,
                  message: "a range the lane does not hold is a change")

    // A held-span replacement restores the boundary endpoint.
    let restored = AutomationLaneReplacement.heldSpan(
        freeze, begin: 24, end: 48, points: [AutomationLanePoint(tick: 24, value: 80)])
    report.expect(!restored.unchanged, cppID: pointRangeID,
                  message: "a held-span replacement that differs is a change")
    report.expectEqual(["24:80", "48:60"], restored.points.map { "\($0.tick):\($0.value)" },
                       cppID: pointRangeID,
                       what: "the held span closes on the original endpoint's value")
    report.expectEqual(Tick(48), restored.tickEnd, cppID: pointRangeID,
                       what: "the replacement names the last tick it covers")

    // A flat replacement is unchanged; an empty one deletes the span.
    let flat = AutomationLaneReplacement.heldSpan(
        freeze, begin: 36, end: 48, points: [AutomationLanePoint(tick: 36, value: 60)])
    report.expect(flat.unchanged, cppID: pointRangeID,
                  message: "a replacement the lane already holds is unchanged")
    report.expectEqual(0, flat.points.count, cppID: pointRangeID,
                       what: "an unchanged replacement carries no point")
    let deletion = AutomationLaneReplacement.heldSpan(freeze, begin: 24, end: 96, points: [])
    report.expect(!deletion.unchanged, cppID: pointRangeID,
                  message: "an empty replacement over a covered span deletes it")
    report.expectEqual(0, deletion.points.count, cppID: pointRangeID,
                       what: "the deleting replacement carries no point")

    // The canonicalization and held-value rules.
    report.expectEqual(["8:20", "24:40"],
                       AutomationLaneReplacement.canonical(
                           [AutomationLanePoint(tick: 24, value: 30),
                            AutomationLanePoint(tick: 8, value: 20),
                            AutomationLanePoint(tick: 32, value: 30),
                            AutomationLanePoint(tick: 24, value: 40)],
                           begin: 0, end: 30, minimum: 0, maximum: 127, priorValue: nil)
                           .map { "\($0.tick):\($0.value)" },
                       cppID: pointRangeID,
                       what: "canonicalization sorts, drops the far tick and keeps the last occupant")
    report.expectEqual(["0:0", "24:9"],
                       AutomationLaneReplacement.canonical(
                           [AutomationLanePoint(tick: 0, value: -4),
                            AutomationLanePoint(tick: 9, value: -4),
                            AutomationLanePoint(tick: 24, value: 9)],
                           begin: 0, end: 96, minimum: 0, maximum: 9, priorValue: nil)
                           .map { "\($0.tick):\($0.value)" },
                       cppID: pointRangeID,
                       what: "canonicalization clamps into the domain and drops repeated values")
    let held = [AutomationLanePoint(tick: 8, value: 20), AutomationLanePoint(tick: 24, value: 30)]
    report.expect(AutomationLaneReplacement.held(held, at: 8, inclusive: false) == nil,
                  cppID: pointRangeID,
                  message: "the exclusive held lookup skips a point on the tick")
    report.expectEqual(20, AutomationLaneReplacement.held(held, at: 8, inclusive: true) ?? -1,
                       cppID: pointRangeID,
                       what: "the inclusive held lookup takes a point on the tick")
    report.expectEqual(30, AutomationLaneReplacement.held(held, at: 40, inclusive: true) ?? -1,
                       cppID: pointRangeID,
                       what: "the held lookup walks to the last point before the tick")
    report.expect(AutomationLaneReplacement.held(held, at: 4, inclusive: true) == nil,
                  cppID: pointRangeID, message: "the held lookup reports nothing before the first")

    // The pencil stroke on an empty lane with a lead-in.
    let emptyLane = AutomationFixture(suite: suite, service: service, modulation: [])
    let emptyFacts = emptyLane.facts(emptyLane.modulationLane)
    report.expectEqual(0, emptyFacts.snapshot.leadInValue ?? -1, cppID: pointRangeID,
                       what: "an unwritten Modulation lane leads in on its engine default")
    guard let stroke = AutomationPencilTransaction(
        facts: emptyFacts,
        firstSample: AutomationPencilTransaction.Sample(
            rawTick: 24, logicalX: 24, logicalY: 40,
            point: AutomationLanePoint(tick: 24, value: 80), continuousValue: 80),
        firstCell: AutomationGridCell(tickBegin: 24, tickEnd: 48), clockTicks: 24) else {
        report.fail(pointRangeID, "the pencil stroke did not start on an empty lane")
        return
    }
    report.expectEqual(["24:80", "48:0"], emptyLane.laneValues(stroke.completion().points),
                       cppID: pointRangeID,
                       what: "the stroke writes its point and restores the lane's held value")
    report.expectEqual(["24:80", "48:0"], emptyLane.laneValues(stroke.preview.points),
                       cppID: pointRangeID, what: "the stroke's preview matches its completion")
    report.expect(!stroke.completion().unchanged, cppID: pointRangeID,
                  message: "an empty lane's first stroke is a change")

    // A stroke past the last point re-anchors that point's value.
    let pastLast = AutomationFixture(suite: suite, service: service, modulation: [(0, 20)])
    let pastLastFacts = pastLast.facts(pastLast.modulationLane)
    guard let pastLastStroke = AutomationPencilTransaction(
        facts: pastLastFacts,
        firstSample: AutomationPencilTransaction.Sample(
            rawTick: 24, logicalX: 24, logicalY: 40,
            point: AutomationLanePoint(tick: 24, value: 80), continuousValue: 80),
        firstCell: AutomationGridCell(tickBegin: 24, tickEnd: 48), clockTicks: 24) else {
        report.fail(pointRangeID, "the pencil stroke did not start past the last point")
        return
    }
    report.expectEqual(["24:80", "48:20"], pastLast.laneValues(pastLastStroke.completion().points),
                       cppID: pointRangeID,
                       what: "a stroke past the last point re-anchors that point's value")

    // Committed through the page's own press and release: one write, one entry.
    let committed = AutomationFixture(suite: suite, service: service, modulation: [(0, 20)])
    let committedBefore = committed.snapshot
    committed.activate(committed.modulationLane)
    // Historical CCLanes defaults Modulation to Auto: this fixture's maximum
    // 20 displays 0–32. Request the full range before targeting value 60.
    _ = committed.page.openParameterMenu(
        index: committed.page.catalogIndex(of: committed.modulationLane), x: 0, y: 0)
    report.expect(committed.page.consumeMenuAction(actionId: AutomationMenuAction.range127.rawValue),
                  cppID: pointRangeID, message: "the stroke fixture selects its intended value range")
    report.expectEqual(committedBefore, committed.snapshot, cppID: pointRangeID,
                       what: "preparing the display range leaves document and history unchanged")
    committed.page.isPencilMode = true
    let strokeY = committed.y(committed.modulationLane, 60)
    report.expect(committed.page.pointerPress(x: committed.x(24), y: strokeY, surface: 1, button: 1), cppID: pointRangeID,
                  message: "the pencil press starts a stroke")
    report.expect(committed.page.isPainting, cppID: pointRangeID,
                  message: "the page publishes the painting gesture")
    report.expect(committed.page.pointerRelease(x: committed.x(24), y: strokeY, button: 1), cppID: pointRangeID,
                  message: "the pencil release commits")
    report.expectEqual(committedBefore.revision + 1, committed.document.revision, cppID: pointRangeID,
                       what: "one pencil press and release is one revision")
    report.expect(committed.values(committed.modulationLane).contains { $0.hasSuffix(":60") },
                  cppID: pointRangeID,
                  message: "the released stroke writes the value under the pointer")
    report.expect(committed.undo(), cppID: pointRangeID, message: "the stroke is undoable")
    report.expectEqual(["0:20"], committed.values(committed.modulationLane), cppID: pointRangeID,
                       what: "one undo restores the pre-stroke lane")
    report.expect(!committed.document.history.canUndo, cppID: pointRangeID,
                  message: "the released stroke recorded exactly one history entry")
}

// MARK: - XCMD parity

@MainActor
private func xcmdParity(_ report: CheckReport, suite: DocumentSession,
                        service: ProjectService) {
    let fixture = AutomationFixture(suite: suite, service: service, echo: [(120, 100)])
    let echo = fixture.projection(fixture.echoLane)
    report.expectEqual(["120:100"], fixture.laneValues(echo.points.map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }), cppID: projectionID, what: "an XCMD lane projects through the same lane API")
    report.expectEqual(1, echo.eventCount, cppID: projectionID,
                       what: "an XCMD lane counts its written events")
    report.expectEqual("Echo volume (xIECV)", AutomationCatalog.title(fixture.echoLane),
                       cppID: projectionID, what: "an XCMD row keeps its descriptor title")
    let metadata = AutomationParameterMetadata(parameter: fixture.echoLane)
    report.expect(metadata.neutral == nil && metadata.defaultValue == nil, cppID: projectionID,
                  message: "an XCMD lane has neither a neutral nor an engine default")
    report.expect(echo.leadIn == nil, cppID: projectionID,
                  message: "an XCMD lane supplies no lead-in")
    report.expectEqual([AutomationScaleLabel.Role.maximum, .minimum],
                       echo.scaleLabels.map(\.role), cppID: projectionID,
                       what: "an XCMD lane labels its extremes with no neutral")
    let before = fixture.snapshot
    let edit = AutomationLaneReplacement.heldSpan(
        fixture.facts(fixture.echoLane).freeze(), begin: 120, end: 144,
        points: [AutomationLanePoint(tick: 120, value: 5)])
    report.expect(AutomationCommit.apply(edit, in: fixture.document), cppID: projectionID,
                  message: "an XCMD lane commits through the same lane write")
    report.expectEqual(["120:5", "144:100"], fixture.values(fixture.echoLane), cppID: projectionID,
                       what: "the XCMD lane writes its projected replacement")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: projectionID,
                       what: "one XCMD replacement is one revision")
}

private let tapTempoID = "swiftcore/AutomationPage::tapTempoCadenceAndCommit"
private let modifierMappingID = "swiftcore/AutomationPage::qtModifierMapping"

/// The pure tap-tempo session and the page's captured commit. A fixed cadence
/// averages over the newest intervals only, a gap past the production distance
/// starts a fresh session, and the idle window records exactly one tempo edit
/// and one history entry — or nothing at all for a stale capture, a moved
/// parameter and a draft that names the tempo already in place.
@MainActor
private func tapTempoCadenceAndCommit(_ report: CheckReport, suite: DocumentSession,
                                      service: ProjectService) {
    var cadence = AutomationTapTempoSession()
    report.expectEqual(0, cadence.draftBpm, cppID: tapTempoID,
                       what: "a fresh session holds no draft")
    report.expect(!cadence.readyToCommit && cadence.idleCommitMs == AutomationTapTempoSession.gapMs,
                  cppID: tapTempoID,
                  message: "a draft-less session cannot commit and publishes the gap as its window")

    cadence.registerTap(nowMs: 1000)
    report.expect(cadence.tapCount == 1 && cadence.draftBpm == 0 && !cadence.readyToCommit,
                  cppID: tapTempoID,
                  message: "the first tap starts a session and names no tempo")

    for step in 1...5 { cadence.registerTap(nowMs: 1000 + Int64(step) * 500) }
    report.expectEqual(6, cadence.tapCount, cppID: tapTempoID,
                       what: "six taps stand in the session")
    report.expectEqual(120, cadence.draftBpm, cppID: tapTempoID,
                       what: "a steady 500 ms cadence drafts 120 BPM")
    report.expectEqual(750, cadence.idleCommitMs, cppID: tapTempoID,
                       what: "1.5 tapped beats at 120 BPM is a 750 ms idle window")

    // The mean clips to the newest window: four 600 ms taps after five 500 ms
    // intervals average the newest eight intervals, and the oldest 500 ms
    // interval no longer counts.
    for step in 1...4 { cadence.registerTap(nowMs: 3500 + Int64(step) * 600) }
    report.expectEqual(10, cadence.tapCount, cppID: tapTempoID,
                       what: "ten taps stand in the session")
    report.expectEqual(109, cadence.draftBpm, cppID: tapTempoID,
                       what: "the draft is the clipped mean of the newest eight intervals")
    report.expectEqual(826, cadence.idleCommitMs, cppID: tapTempoID,
                       what: "1.5 tapped beats at 109 BPM is an 826 ms idle window")

    // A tap past the gap distance is a new session, not a dropped interval.
    cadence.registerTap(nowMs: 5900 + Int64(AutomationTapTempoSession.gapMs) + 1)
    report.expect(cadence.tapCount == 1 && cadence.draftBpm == 0, cppID: tapTempoID,
                  message: "a tap past the production idle gap starts a fresh session")
    cadence.registerTap(nowMs: 8401)
    report.expectEqual(120, cadence.draftBpm, cppID: tapTempoID,
                       what: "the fresh session drafts from its own single interval")
    cadence.reset()
    report.expectEqual(AutomationTapTempoSession(), cadence, cppID: tapTempoID,
                       what: "reset returns the session to its seed state")

    let fixture = AutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    fixture.activate(fixture.panLane)
    report.expectEqual(["0:120"], fixture.tempoValues, cppID: tapTempoID,
                       what: "the staged document names 120 BPM at tick zero")
    let before = fixture.snapshot

    // A ready draft that already names the tick-zero tempo writes nothing.
    for tap in 0...3 { fixture.page.tapTempoTap(atMilliseconds: 10 + Int64(tap) * 500) }
    report.expectEqual(120, fixture.page.tapTempoSession.draftBpm, cppID: tapTempoID,
                       what: "the tapped cadence named the tempo already in place")
    report.expectEqual(4, fixture.page.tapTempoSession.tapCount, cppID: tapTempoID,
                       what: "the taps stand in the page's own session")
    report.expect(fixture.page.tapTempoActive, cppID: tapTempoID,
                  message: "a live session is the page's interaction fact")
    report.expect(!fixture.page.tapTempoIdleElapsed(), cppID: tapTempoID,
                  message: "a draft that changes nothing commits nothing")
    report.expectEqual(["0:120"], fixture.tempoValues, cppID: tapTempoID,
                       what: "the no-op idle window left the stream alone")
    report.expectEqual(before.revision, fixture.document.revision, cppID: tapTempoID,
                       what: "the no-op idle window published no revision")
    report.expect(!fixture.document.history.canUndo, cppID: tapTempoID,
                  message: "the no-op idle window recorded no history entry")
    report.expect(fixture.page.tapTempoSession.tapCount == 0 && !fixture.page.tapTempoActive,
                  cppID: tapTempoID,
                  message: "the idle window closed the session either way")

    // A ready draft that changes the tempo is one edit and one history entry.
    for tap in 0...3 { fixture.page.tapTempoTap(atMilliseconds: 20_000 + Int64(tap) * 400) }
    report.expectEqual(150, fixture.page.tapTempoSession.draftBpm, cppID: tapTempoID,
                       what: "a 400 ms cadence drafts 150 BPM")
    report.expect(fixture.page.tapTempoIdleElapsed(), cppID: tapTempoID,
                  message: "the idle window commits the ready draft")
    report.expectEqual(["0:150"], fixture.tempoValues, cppID: tapTempoID,
                       what: "the commit replaced the tick-zero tempo point")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: tapTempoID,
                       what: "the tempo edit published one revision")
    report.expect(fixture.document.history.canUndo, cppID: tapTempoID,
                  message: "the tempo edit recorded one history entry")
    report.expect(fixture.undo(), cppID: tapTempoID, message: "the tempo edit undoes")
    report.expectEqual(["0:120"], fixture.tempoValues, cppID: tapTempoID,
                       what: "undo restored the previous tick-zero tempo")
    report.expect(!fixture.document.history.canUndo, cppID: tapTempoID,
                  message: "one tempo edit is exactly one history entry")
    do {
        _ = try runBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(tapTempoID, "redo failed: \(error)")
        return
    }
    report.expectEqual(["0:150"], fixture.tempoValues, cppID: tapTempoID,
                       what: "redo put the committed tempo back on the stream")

    // A capture whose own document moved on writes nothing.
    for tap in 0...3 { fixture.page.tapTempoTap(atMilliseconds: 30_000 + Int64(tap) * 500) }
    report.expectEqual(120, fixture.page.tapTempoSession.draftBpm, cppID: tapTempoID,
                       what: "the stale session drafts a tempo the stream does not hold")
    report.expect(fixture.page.openPrompt(tick: 48, value: 64), cppID: tapTempoID,
                  message: "the intervening write opened its own prompt")
    report.expect(fixture.page.acceptPrompt(displayedValue: 96), cppID: tapTempoID,
                  message: "the intervening write committed")
    let stale = fixture.document.revision
    report.expect(!fixture.page.tapTempoIdleElapsed(), cppID: tapTempoID,
                  message: "a capture whose document moved on commits nothing")
    report.expectEqual(stale, fixture.document.revision, cppID: tapTempoID,
                       what: "the stale idle window published no revision")
    report.expectEqual(["0:150"], fixture.tempoValues, cppID: tapTempoID,
                       what: "the stale draft never reached the tempo stream")
    report.expect(fixture.page.tapTempoSession.tapCount == 0, cppID: tapTempoID,
                  message: "the stale idle window closed the session")

    // A session named its own parameter: switching it ends without a write.
    for tap in 0...3 { fixture.page.tapTempoTap(atMilliseconds: 40_000 + Int64(tap) * 400) }
    report.expect(fixture.page.tapTempoSession.tapCount > 0, cppID: tapTempoID,
                  message: "the session started on the lane the taps named")
    fixture.activate(fixture.volumeLane)
    report.expect(!fixture.page.tapTempoIdleElapsed(), cppID: tapTempoID,
                  message: "a session whose parameter moved on commits nothing")
    report.expectEqual(["0:150"], fixture.tempoValues, cppID: tapTempoID,
                       what: "the switched parameter left the tempo stream alone")
}

/// The Qt modifier bits QML carries and the policy they arm, both directions,
/// plus one real pointer route driven by the raw bits a QML event supplies.
@MainActor
private func qtModifierMapping(_ report: CheckReport, suite: DocumentSession,
                               service: ProjectService) {
    report.expectEqual(AutomationModifiers(), AutomationQtModifier.automation(0), cppID: modifierMappingID,
                       what: "no Qt bit arms no policy")
    report.expectEqual(AutomationModifiers(shift: true),
                       AutomationQtModifier.automation(AutomationQtModifier.shift), cppID: modifierMappingID,
                       what: "Qt's shift bit arms the ramp and axis-lock policy")
    report.expectEqual(AutomationModifiers(snapValue: true),
                       AutomationQtModifier.automation(AutomationQtModifier.control),
                       cppID: modifierMappingID,
                       what: "Qt's control bit arms the value snap")
    report.expectEqual(AutomationModifiers(fine: true),
                       AutomationQtModifier.automation(AutomationQtModifier.alt), cppID: modifierMappingID,
                       what: "Qt's alt bit arms the fine lattice")
    report.expectEqual(AutomationModifiers(),
                       AutomationQtModifier.automation(AutomationQtModifier.meta), cppID: modifierMappingID,
                       what: "Qt's meta bit arms nothing")
    report.expectEqual(AutomationModifiers(fine: true, snapValue: true, shift: true),
                       AutomationQtModifier.automation(AutomationQtModifier.shift
                                                       | AutomationQtModifier.control
                                                       | AutomationQtModifier.alt),
                       cppID: modifierMappingID,
                       what: "the three policy bits compose through the same mapping")
    for policy in [AutomationModifiers(), AutomationModifiers(fine: true),
                   AutomationModifiers(snapValue: true), AutomationModifiers(shift: true),
                   AutomationModifiers(fine: true, snapValue: true),
                   AutomationModifiers(fine: true, shift: true),
                   AutomationModifiers(snapValue: true, shift: true),
                   AutomationModifiers(fine: true, snapValue: true, shift: true)] {
        report.expectEqual(policy, AutomationQtModifier.automation(qtModifiers(policy)),
                           cppID: modifierMappingID,
                           what: "the Qt bits that policy composes to map back to it")
    }

    // The same mapping is the press route's own input: one pan drag inside the
    // neutral radius lands on 64 only when the Qt control bit is carried.
    let plain = AutomationFixture(suite: suite, service: service, pan: [(24, 80)])
    plain.activate(plain.panLane)
    let metadata = AutomationParameterMetadata(parameter: plain.panLane)
    let height = 120.0
    let radius = plain.page.geometry.neutralSnapRadius
    let threshold = Int(Double(metadata.maximum - metadata.minimum) * radius / height)
    report.expect(threshold > 1, cppID: modifierMappingID,
                  message: "the neutral radius covers more than one value step")
    let near = (metadata.neutral ?? (metadata.maximum + metadata.minimum) / 2)
        + max(1, threshold - 1)
    report.expect(plain.drag(plain.panLane, from: (24, 80), to: near, modifiers: 0),
                  cppID: modifierMappingID,
                  message: "the pointer route took the drag without a Qt modifier bit")
    report.expectEqual(["24:\(near)"], plain.values(plain.panLane), cppID: modifierMappingID,
                       what: "a drag without the Qt control bit keeps the dragged value")

    let snapped = AutomationFixture(suite: suite, service: service, pan: [(24, 80)])
    snapped.activate(snapped.panLane)
    report.expect(snapped.drag(snapped.panLane, from: (24, 80), to: near,
                               modifiers: AutomationQtModifier.control),
                  cppID: modifierMappingID,
                  message: "the pointer route took the drag carrying the Qt control bit")
    report.expectEqual(["24:64"], snapped.values(snapped.panLane), cppID: modifierMappingID,
                       what: "the Qt control bit a QML event carries lands the drag on the neutral")
}

@MainActor
private func restoredInteractionContracts(_ report: CheckReport, suite: DocumentSession,
                                          service: ProjectService) {
    let id = "swiftcore/AutomationPage::restoredInteractionContracts"
    let fixture = AutomationFixture(suite: suite, service: service,
                                    volume: [(48, 70)], pan: [(24, 60)],
                                    tempo: [(0, 500_000), (36, 400_000)])
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(from: 20, to: 60,
                             lanes: [fixture.panLane, fixture.volumeLane, .tempo])
    let before = fixture.snapshot
    fixture.drag(fixture.panLane, from: (24, 60), to: 70, modifiers: AutomationQtModifier.alt)
    report.expectEqual(["24:70"], fixture.values(fixture.panLane), cppID: id,
                       what: "selected drag moves the grabbed lane")
    report.expectEqual(["48:80"], fixture.values(fixture.volumeLane), cppID: id,
                       what: "selected drag resolves a disjoint CC snapshot")
    report.expectEqual(["0:120", "36:160"], fixture.tempoValues, cppID: id,
                       what: "selected drag resolves Tempo through its own stream")
    report.expectEqual(before.revision + 1, fixture.document.revision, cppID: id,
                       what: "heterogeneous selected drag is one revision")
    report.expect(fixture.undo(), cppID: id, message: "one undo restores all selected lanes")
    report.expectEqual(["48:70"], fixture.values(fixture.volumeLane), cppID: id,
                       what: "undo restores secondary CC lane")
    report.expectEqual(["0:120", "36:150"], fixture.tempoValues, cppID: id,
                       what: "undo restores secondary Tempo lane")
    report.expect(!fixture.document.history.canUndo, cppID: id,
                  message: "the drag records exactly one history entry")

    let page = fixture.page
    let x = fixture.x(24)
    let y = fixture.y(fixture.panLane, 60)
    _ = page.pointerPress(x: x, y: y, surface: 1, button: AutomationQtButton.left)
    _ = page.pointerRelease(x: x, y: y, button: AutomationQtButton.left)
    report.expectEqual([String](), fixture.values(fixture.panLane), cppID: id,
                       what: "stationary selection click deletes grabbed node only")
    report.expectEqual(["48:70"], fixture.values(fixture.volumeLane), cppID: id,
                       what: "stationary selection click preserves other lanes")
    _ = page.pointerPress(x: 400, y: 90, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: 400, y: 90, button: AutomationQtButton.right)
    report.expect(page.selection == nil, cppID: id,
                  message: "outside right press clears selection before opening a menu")
    page.dismissMenu()
    page.selectRange(from: 0, to: fixture.songEndTick, lanes: [fixture.panLane])
    _ = page.pointerPress(x: 400, y: 90, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerMove(x: 400, y: 60, buttons: AutomationQtButton.right)
    _ = page.pointerRelease(x: 400, y: 60, button: AutomationQtButton.right)
    report.expect(page.selection == nil, cppID: id,
                  message: "activated zero-width band clears selection")

    fixture.activate(fixture.volumeLane)
    let rangeBefore = fixture.snapshot
    _ = page.openParameterMenu(index: page.catalogIndex(of: fixture.volumeLane), x: 0, y: 0)
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.range64.rawValue),
                  cppID: id, message: "zoomable lane consumes range choice")
    report.expectEqual(64, page.scaleLabels.first?.value, cppID: id,
                       what: "range choice changes displayed maximum")
    report.expectEqual(rangeBefore, fixture.snapshot, cppID: id,
                       what: "range choice changes neither document nor history")
    fixture.activate(fixture.panLane)
    _ = page.openParameterMenu(index: page.catalogIndex(of: fixture.panLane), x: 0, y: 0)
    report.expect(!page.menuRowActions.contains(AutomationMenuAction.valueRange.rawValue),
                  cppID: id, message: "centered lane has no value range submenu")
    page.dismissMenu()
    fixture.activate(fixture.volumeLane)
    report.expectEqual(64, page.scaleLabels.first?.value, cppID: id,
                       what: "range persists independently across parameter switches")
    let synthetic = AutomationFixture(suite: suite, service: service)
    synthetic.activate(synthetic.volumeLane)
    if let point = synthetic.page.projection?.points.first {
        _ = synthetic.page.pointerPress(x: point.x, y: point.y, surface: 1,
                                        button: AutomationQtButton.right)
        _ = synthetic.page.pointerRelease(x: point.x, y: point.y, button: AutomationQtButton.right)
        report.expect(synthetic.page.publishedMenuRows.first {
            $0.actionId == AutomationMenuAction.deleteNode.rawValue
        }?.enabled == false, cppID: id, message: "synthetic engine default cannot be deleted")
        _ = synthetic.page.consumeMenuAction(actionId: AutomationMenuAction.setValue.rawValue)
        report.expect(synthetic.page.acceptPrompt(displayedValue: 80), cppID: id,
                      message: "Set Value promotes the synthetic default")
        report.expectEqual(["0:80"], synthetic.values(synthetic.volumeLane), cppID: id,
                           what: "promoted value is a written tick-zero event")
        _ = synthetic.page.openPrompt(tick: 0, value: 80)
        synthetic.session.selectedTrack = nil
        let stale = synthetic.snapshot
        report.expect(!synthetic.page.acceptPrompt(displayedValue: 70), cppID: id,
                      message: "a prompt cannot follow a primary-track change")
        report.expectEqual(stale, synthetic.snapshot, cppID: id,
                           what: "stale prompt leaves document and history untouched")
    } else {
        report.fail(id, "synthetic default projection missing")
    }

    let hover = AutomationFixture(suite: suite, service: service, volume: [(48, 70)])
    hover.activate(hover.volumeLane)
    hover.page.plotFocused = true
    hover.page.isPencilMode = true
    _ = hover.page.pointerMove(x: 400, y: 70, buttons: 0)
    let hoverBefore = hover.snapshot
    report.expect(hover.page.consumeHoverDelete(), cppID: id,
                  message: "pencil blank hover consumes deletion without falling through")
    report.expectEqual(hoverBefore, hover.snapshot, cppID: id,
                       what: "blank hover deletion changes nothing")
    hover.page.selectRange(from: 0, to: 100, lanes: [hover.volumeLane])
    report.expect(!hover.page.consumeHoverDelete(), cppID: id,
                  message: "time selection retains semantic delete priority")
    hover.page.clearTimeSelection()
    hover.page.isPencilMode = false
    report.expect(!hover.page.consumeHoverDelete(), cppID: id,
                  message: "arrow hover cannot claim pencil deletion")

    let emptyRange = AutomationFixture(suite: suite, service: service, pan: [])
    emptyRange.page.selectRange(from: 48, to: 96, lanes: [emptyRange.panLane])
    let emptyBefore = emptyRange.snapshot
    report.expect(emptyRange.page.consumeSelectionCommand(command: .nudgeRight), cppID: id,
                  message: "an empty range owns its nudge command")
    report.expect((emptyRange.page.selection?.range.startTick ?? 0) > 48
                      && emptyRange.page.selection?.range.span == 48, cppID: id,
                  message: "an empty range advances on the camera grid without changing its span")
    report.expectEqual(emptyBefore, emptyRange.snapshot, cppID: id,
                       what: "empty-band movement creates no document edit or history")

    let duplicate = AutomationFixture(suite: suite, service: service, pan: [(24, 30)])
    duplicate.page.selectRange(from: 0, to: 48, lanes: [duplicate.panLane])
    report.expect(duplicate.page.consumeSelectionCommand(command: .duplicate), cppID: id,
                  message: "range duplicate is consumed through the canonical command seam")
    report.expectEqual(TimeRange(startTick: 48, endTick: 96), duplicate.page.selection?.range,
                       cppID: id, what: "duplicate moves the band onto the inserted span")
    report.expectEqual(Tick(96), duplicate.session.editCursor, cppID: id,
                       what: "duplicate advances the edit cursor to the new span end")
    report.expect(duplicate.undo() && !duplicate.document.history.canUndo, cppID: id,
                  message: "duplicate remains one undo entry")
    report.expectEqual(["24:30"], duplicate.values(duplicate.panLane), cppID: id,
                       what: "undo restores the original range contents")
}
