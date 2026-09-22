import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

@MainActor
func drawerAutomationMiddlePanIsolationGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::middlePanIsolationGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        pan: [(24, 32), (120, 64)]
    )
    fixture.activate(fixture.panLane)

    let beforeSnapshot = fixture.snapshot
    let beforeState = fixture.document.state
    let beforeCursor = fixture.session.editCursor
    let beforeWidth = fixture.page.plotWidth
    let beforeHeight = fixture.page.plotHeight
    report.expect(fixture.page.trackAvailable, cppID: id, message: "A001 track is available")
    report.expect(fixture.page.plotWidth > 0 && fixture.page.plotHeight > 0, cppID: id, message: "A002-A003 drawer and automation plot are available")

    let pressHandled = fixture.page.pointerPress(
        x: 240,
        y: 60,
        surface: AutomationInputSurface.plot.rawValue,
        button: 4,
        modifiers: 0
    )
    report.expect(pressHandled, cppID: id, message: "A004 middle press is handled")
    report.expect(fixture.page.isPanning && fixture.page.interactionActive, cppID: id, message: "A004-A005 middle press enters pan mode and owns the gesture")
    report.expect(!fixture.page.hasBand, cppID: id, message: "A006 middle pan does not create a band preview")
    report.expect(fixture.page.observation.pointerKind == .pan, cppID: id, message: "middle press is routed to automation pan")
    report.expect(fixture.page.pointerMove(x: 270, y: 72), cppID: id, message: "A008 middle drag is handled")
    report.expect(fixture.page.plotWidth == beforeWidth && fixture.page.plotHeight == beforeHeight, cppID: id, message: "A008 middle drag keeps the automation plot geometry")
    report.expect(fixture.document.state == beforeState && fixture.snapshot == beforeSnapshot,
                  cppID: id, message: "A007 middle drag leaves document and history frozen")
    report.expect(fixture.session.editCursor == beforeCursor, cppID: id, message: "A009 middle drag does not move the shared cursor")

    let releaseHandled = fixture.page.pointerRelease(
        x: 270,
        y: 72,
        surface: AutomationInputSurface.plot.rawValue,
        button: 4,
        modifiers: 0
    )
    report.expect(releaseHandled, cppID: id, message: "A011 middle release is handled")
    report.expect(!fixture.page.isPanning && !fixture.page.interactionActive
                      && fixture.page.observation.pointerKind == nil && !fixture.page.hasBand,
                  cppID: id, message: "A010-A012 middle release returns automation to idle without a band")
}

@MainActor
func drawerAutomationVoicePressIsolationGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::voicePressIsolationGap"
    let editablePrograms = suite.bankSlots.indices.filter { suite.bankSlots[$0].voice != nil }
    guard editablePrograms.count >= 3 else {
        report.fail(id, "fixture has three editable voice programs")
        return
    }
    let fixture = drawerVoiceVoiceChangesFixture(
        suite: suite,
        service: service,
        programs: Array(editablePrograms.prefix(3))
    )

    let automation = AutomationPage(baseFontPx: 13)
    automation.attach(session: fixture.session, palette: GridPalette())
    automation.configureBody(width: 480, height: 120, gutter: 0, devicePixelRatio: 1,
                             baseFontPx: 13, dragDistance: 10)
    let pan = AutomationParameter.controlChange(track: 0, controller: TimeDefaults.ccPan)
    _ = automation.activateParameter(index: automation.catalogIndex(of: pan))

    let beforeState = fixture.document.state
    let beforeRevision = fixture.document.revision
    let beforeIdentity = fixture.document.history.currentIdentity
    let beforeCursor = fixture.session.editCursor
    let beforeAutomationWidth = automation.plotWidth
    let beforeAutomationHeight = automation.plotHeight
    let markerX = fixture.markerX(48)
    report.expect(fixture.page.trackAvailable && markerX >= 0 && markerX <= fixture.page.plotWidth, cppID: id, message: "A013-A014 voice marker is inside the voice plot")
    report.expect(automation.trackAvailable && automation.activeParameter == pan,
                  cppID: id, message: "A014-A015 Pan lane is valid in automation on the same session")

    let handled = fixture.page.pointerPress(
        x: markerX,
        y: 22,
        surface: VoiceInputSurface.plot.rawValue,
        button: 1,
        modifiers: 0
    )
    report.expect(handled, cppID: id, message: "A016 voice marker press is handled")
    report.expect(automation.observation.pointerKind == nil, cppID: id, message: "A017 voice press does not enter an automation gesture")
    report.expect(!automation.interactionActive && !automation.pointerGestureActive, cppID: id, message: "A018 voice press leaves automation idle")
    report.expect(!automation.isPanning && !automation.hasBand, cppID: id, message: "A019 voice press creates neither automation pan nor band state")
    report.expect(fixture.document.state == beforeState && fixture.document.revision == beforeRevision, cppID: id, message: "A020 voice press does not edit automation or document state")
    report.expect(fixture.document.history.currentIdentity == beforeIdentity, cppID: id, message: "A020 voice press does not add history")
    report.expect(fixture.session.editCursor == beforeCursor, cppID: id, message: "A021 voice press does not move the shared cursor")
    report.expect(automation.plotWidth == beforeAutomationWidth
                      && automation.plotHeight == beforeAutomationHeight,
                  cppID: id, message: "A020 voice press preserves automation geometry")
    _ = fixture.page.pointerRelease(
        x: markerX,
        y: 22,
        surface: VoiceInputSurface.plot.rawValue,
        button: 1,
        modifiers: 0
    )
}

@MainActor
func drawerAutomationFirstControlChangeOriginGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::firstControlChangeOriginGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        volume: []
    )

    let firstIndex = fixture.page.catalogIndex(of: fixture.volumeLane)
    report.expect(fixture.page.trackAvailable && fixture.page.publishedTabs.count > 1, cppID: id, message: "A080-A081 automation catalog exposes tempo and a first control-change row")
    report.expect(firstIndex == 0, cppID: id, message: "A082 Volume is the first control-change catalog row")
    fixture.activate(fixture.volumeLane)
    report.expect(fixture.page.activeParameterIndex == firstIndex, cppID: id, message: "A083 first control-change row activates")
    report.expect(fixture.page.projection?.points.isEmpty == false,
                  cppID: id, message: "A083 first control-change row has a synthetic origin projection")
    report.expect(fixture.page.plotHeight == 120, cppID: id, message: "A084 first row uses the configured plot origin and height")
    report.expect(fixture.volumeLane == .controlChange(track: 0, controller: TimeDefaults.ccVolume),
                  cppID: id, message: "A085 first row is a control-change parameter")

    let x = 144.0
    let y = 112.0
    report.expect(x >= 0 && x <= fixture.page.plotWidth && y >= 0 && y <= fixture.page.plotHeight, cppID: id, message: "A086 pencil coordinate is inside the first row plot")
    let beforeSnapshot = fixture.snapshot
    let beforeState = fixture.document.state
    let beforeBytes = try? fixture.document.state.file.encoded()
    fixture.page.setPencilMode(true)
    let pressHandled = fixture.page.pointerPress(
        x: x,
        y: y,
        surface: AutomationInputSurface.plot.rawValue,
        button: 1,
        modifiers: 0
    )
    let releaseHandled = fixture.page.pointerRelease(
        x: x,
        y: y,
        surface: AutomationInputSurface.plot.rawValue,
        button: 1,
        modifiers: 0
    )
    fixture.page.setPencilMode(false)
    let inserted = fixture.values(fixture.volumeLane)
    report.expect(pressHandled && releaseHandled, cppID: id, message: "A087 pencil press and release are handled")
    report.expect(inserted.count == 1, cppID: id, message: "A088 pencil gesture inserts one first-row event")
    report.expect(fixture.page.projection?.points.count == 1, cppID: id, message: "A089 first-row projection publishes the inserted point")
    let committedPoints = fixture.lanePoints(fixture.volumeLane)
    report.expect(committedPoints.count == 1
                      && fixture.page.projection?.points.first?.tick == committedPoints[0].tick
                      && fixture.page.projection?.points.first?.value == committedPoints[0].value,
                  cppID: id, message: "A088 projection and document publish the same committed point")
    report.expect(fixture.snapshot.revision == beforeSnapshot.revision + 1, cppID: id, message: "A090 pencil gesture commits one document revision")
    report.expect(fixture.snapshot.identity != beforeSnapshot.identity && fixture.snapshot.canUndo, cppID: id, message: "A090 pencil gesture creates one undoable history entry")

    fixture.page.refreshFromDocument()
    report.expect(fixture.page.activeParameterIndex == firstIndex && fixture.page.activeParameter == fixture.volumeLane, cppID: id, message: "A091 refresh retains the first control-change row")
    report.expect(fixture.values(fixture.volumeLane) == inserted, cppID: id, message: "A092 refresh rebuilds the first-row values from the document")
    report.expect(fixture.page.projection?.points.count == 1, cppID: id, message: "A093 refresh rebuilds the first-row projection")

    report.expect(fixture.undo(), cppID: id, message: "A093 inserted first-row point is undoable")
    report.expect(fixture.document.state == beforeState && !fixture.document.history.canUndo
                      && (try? fixture.document.state.file.encoded()) == beforeBytes,
                  cppID: id, message: "A094 undo restores the exact serialized document and history")
    report.expect(fixture.values(fixture.volumeLane).isEmpty,
                  cppID: id, message: "A095 undo rebuilds the first control-change lane empty")
    report.expect(fixture.page.activeParameterIndex == firstIndex
                      && fixture.page.projection?.points.isEmpty == false,
                  cppID: id, message: "A096 undo keeps the first row active with its synthetic origin")
}

@MainActor
func drawerAutomationRightBandIsolationGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::rightBandIsolationGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        pan: [(48, 64)]
    )
    fixture.activate(fixture.panLane)
    let baseline = fixture.snapshot
    let baselineState = fixture.document.state
    let baselineCursor = fixture.session.editCursor
    let baselineSize = (fixture.page.plotWidth, fixture.page.plotHeight)
    report.expect(fixture.page.activeParameter == fixture.panLane
                      && fixture.page.projection != nil,
                  cppID: id, message: "A022-A024 Pan row and automation projection are active")

    let surface = AutomationInputSurface.plot.rawValue
    _ = fixture.page.pointerPress(
        x: fixture.x(24), y: 100, surface: surface, button: 2, modifiers: 0
    )
    report.expect(fixture.page.hasGesture
                      && fixture.page.observation.pointerKind == .pendingRange
                      && !fixture.page.isPanning,
                  cppID: id, message: "A025-A027 right press arms only the range preview")
    report.expect(fixture.document.state == baselineState && fixture.snapshot == baseline
                      && fixture.session.editCursor == baselineCursor
                      && fixture.page.plotWidth == baselineSize.0
                      && fixture.page.plotHeight == baselineSize.1,
                  cppID: id, message: "A028-A030 right press preserves document, geometry, and cursor")

    _ = fixture.page.pointerMove(
        x: fixture.x(96), y: 100, surface: surface, button: 2, modifiers: 0
    )
    report.expect(fixture.page.observation.pointerKind == .range
                      && fixture.page.observation.frozenParameter == fixture.panLane,
                  cppID: id, message: "A031 dragged range preview contains only Pan")
    report.expect(fixture.document.state == baselineState && fixture.snapshot == baseline
                      && fixture.session.editCursor == baselineCursor
                      && fixture.page.plotWidth == baselineSize.0
                      && fixture.page.plotHeight == baselineSize.1,
                  cppID: id, message: "A032-A034 range preview preserves document, geometry, and cursor")

    _ = fixture.page.pointerRelease(
        x: fixture.x(96), y: 100, surface: surface, button: 2, modifiers: 0
    )
    report.expect(!fixture.page.hasGesture && !fixture.page.isPanning
                      && fixture.page.observation.pointerKind == nil,
                  cppID: id, message: "A035-A037 release clears preview and gesture state")
}

@MainActor
func drawerAutomationPencilLaneIsolationGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::pencilLaneIsolationGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        volume: [(24, 90)],
        pan: [],
        modulation: [(36, 11)],
        tempo: [(0, 500_000), (72, 400_000)]
    )
    let voiceLane = AutomationParameter.controlChange(
        track: 0,
        controller: TimeDefaults.laneCCVoice
    )
    fixture.activate(fixture.panLane)
    fixture.page.setPencilMode(true)
    let baseline = fixture.snapshot
    let baselineState = fixture.document.state
    let modulationBefore = fixture.values(fixture.modulationLane)
    let volumeBefore = fixture.values(fixture.volumeLane)
    let voiceBefore = fixture.values(voiceLane)
    let bendBefore = fixture.values(fixture.bendLane)
    let tempoBefore = fixture.tempoValues
    let cursorBefore = fixture.session.editCursor
    let baselineSize = (fixture.page.plotWidth, fixture.page.plotHeight)
    report.expect(fixture.page.activeParameter == fixture.panLane
                      && fixture.page.catalogIndex(of: fixture.panLane) >= 0
                      && fixture.page.plotWidth > 0 && fixture.page.plotHeight > 0,
                  cppID: id, message: "A038-A041 Pan pencil target and delivered viewport are valid")

    let surface = AutomationInputSurface.plot.rawValue
    _ = fixture.page.pointerPress(
        x: fixture.x(48),
        y: fixture.y(fixture.panLane, 96),
        surface: surface,
        button: 1,
        modifiers: 0
    )
    report.expect(fixture.page.hasGesture
                      && fixture.page.observation.pointerKind == .pencilStroke
                      && !fixture.page.isPanning,
                  cppID: id, message: "A042-A044 pencil press owns only the Pan stroke")
    report.expect(fixture.document.state == baselineState && fixture.snapshot == baseline
                      && fixture.session.editCursor == cursorBefore
                      && fixture.page.plotWidth == baselineSize.0
                      && fixture.page.plotHeight == baselineSize.1,
                  cppID: id, message: "A045-A047 pencil press preserves frozen state, geometry, and cursor")

    _ = fixture.page.pointerRelease(
        x: fixture.x(48),
        y: fixture.y(fixture.panLane, 96),
        surface: surface,
        button: 1,
        modifiers: 0
    )
    report.expectEqual(["48:96"], fixture.values(fixture.panLane),
                       cppID: id, what: "A048-A049 pencil writes the mapped Pan point")
    report.expect(fixture.document.state != baselineState
                      && fixture.document.revision == baseline.revision + 1
                      && fixture.snapshot.canUndo
                      && fixture.snapshot.identity != baseline.identity,
                  cppID: id, message: "A050-A053 pencil creates one document revision and history entry")
    report.expect(fixture.values(fixture.modulationLane) == modulationBefore
                      && fixture.values(fixture.volumeLane) == volumeBefore
                      && fixture.values(voiceLane) == voiceBefore
                      && fixture.values(fixture.bendLane) == bendBefore
                      && fixture.tempoValues == tempoBefore,
                  cppID: id, message: "A054-A058 pencil preserves every non-Pan lane")
    report.expect(fixture.page.plotWidth == baselineSize.0
                      && fixture.page.plotHeight == baselineSize.1
                      && fixture.session.editCursor == cursorBefore,
                  cppID: id, message: "A059-A060 pencil release preserves geometry and cursor")
    report.expect(!fixture.page.hasGesture && !fixture.page.isPanning
                      && fixture.page.observation.pointerKind == nil,
                  cppID: id, message: "A061-A063 pencil release clears gesture and preview state")
}

@MainActor
func drawerAutomationBodyCursorIsolationGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "swiftcore/AutomationPage::bodyCursorIsolationGap"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite,
        service: service,
        pan: [(48, 64)]
    )
    fixture.activate(fixture.panLane)
    let baseline = fixture.snapshot
    let baselineState = fixture.document.state
    let cursorBefore = fixture.session.editCursor
    let expectedCursor: Tick = 96
    let baselineSize = (fixture.page.plotWidth, fixture.page.plotHeight)
    report.expect(fixture.page.activeParameter == fixture.panLane
                      && fixture.page.projection != nil
                      && expectedCursor != cursorBefore,
                  cppID: id, message: "A064-A067 Pan row and distinct cursor target are valid")

    let surface = AutomationInputSurface.plot.rawValue
    _ = fixture.page.pointerPress(
        x: fixture.x(expectedCursor), y: 100,
        surface: surface, button: 1, modifiers: 0
    )
    report.expect(fixture.page.hasGesture && !fixture.page.isPanning
                      && fixture.page.observation.pointerKind == .sweep,
                  cppID: id, message: "A068-A070 body press owns no pan or range preview")
    report.expect(fixture.document.state == baselineState && fixture.snapshot == baseline
                      && fixture.session.editCursor == cursorBefore
                      && fixture.page.plotWidth == baselineSize.0
                      && fixture.page.plotHeight == baselineSize.1,
                  cppID: id, message: "A071-A073 body press preserves document, geometry, and cursor")

    _ = fixture.page.pointerRelease(
        x: fixture.x(expectedCursor), y: 100,
        surface: surface, button: 1, modifiers: 0
    )
    report.expect(fixture.session.editCursor == expectedCursor,
                  cppID: id, message: "A074 body release commits only the mapped cursor")
    report.expect(fixture.document.state == baselineState && fixture.snapshot == baseline
                      && fixture.page.plotWidth == baselineSize.0
                      && fixture.page.plotHeight == baselineSize.1,
                  cppID: id, message: "A075-A076 cursor commit preserves document and geometry")
    report.expect(!fixture.page.hasGesture && !fixture.page.isPanning
                      && fixture.page.observation.pointerKind == nil,
                  cppID: id, message: "A077-A079 cursor release clears gesture and preview state")
}
