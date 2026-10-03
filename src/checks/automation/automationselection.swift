import Foundation
@testable import PorydawApp
import PorydawCore

// Existing scenarios paired with automationselection.cpp.
// Entry order remains in AutomationPageChecks.swift.

@MainActor
func drawerAutomationRestoredInteractionContracts(_ report: CheckReport, suite: DocumentSession,
                                          service: ProjectService) {
    let id = "swiftcore/AutomationPage::restoredInteractionContracts"
    hostTempoRangeAndBandRows(report, suite: suite, service: service)
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    volume: [(48, 70)], pan: [(24, 60)],
                                    tempo: [(0, 500_000), (36, 400_000)])
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(from: 20, to: 60,
                             lanes: [fixture.panLane, fixture.volumeLane, .tempo])
    let before = fixture.snapshot
    fixture.drag(fixture.panLane, from: (24, 60), to: 70, modifiers: AutomationQtModifier.alt)
    report.expectEqual(expected: ["24:70"], actual: fixture.values(fixture.panLane), cppID: id,
                       what: "selected drag moves the grabbed lane")
    report.expectEqual(expected: ["48:80"], actual: fixture.values(fixture.volumeLane), cppID: id,
                       what: "selected drag resolves a disjoint CC snapshot")
    report.expectEqual(expected: ["0:120", "36:160"], actual: fixture.tempoValues, cppID: id,
                       what: "selected drag resolves Tempo through its own stream")
    report.expectEqual(expected: before.revision + 1, actual: fixture.document.revision, cppID: id,
                       what: "heterogeneous selected drag is one revision")
    report.expect(fixture.undo(), cppID: id, message: "one undo restores all selected lanes")
    report.expectEqual(expected: ["48:70"], actual: fixture.values(fixture.volumeLane), cppID: id,
                       what: "undo restores secondary CC lane")
    report.expectEqual(expected: ["0:120", "36:150"], actual: fixture.tempoValues, cppID: id,
                       what: "undo restores secondary Tempo lane")
    let redone = (try? runBlocking { try await fixture.session.redo() }) ?? false
    report.expect(redone, cppID: id, message: "the heterogeneous drag is redoable")
    report.expectEqual(expected: ["0:120", "36:160"], actual: fixture.tempoValues, cppID: id,
                       what: "redo restores the committed Tempo stream")
    report.expectEqual(expected: ["48:80"], actual: fixture.values(fixture.volumeLane), cppID: id,
                       what: "redo restores the committed secondary CC lane")
    report.expect(fixture.undo(), cppID: id, message: "a second undo parks the drag again")
    report.expect(!fixture.document.history.canUndo, cppID: id,
                  message: "the drag records exactly one history entry")

    let page = fixture.page
    let x = fixture.x(24)
    let y = fixture.y(fixture.panLane, 60)
    _ = page.pointerPress(x: x, y: y, surface: 1, button: AutomationQtButton.left)
    _ = page.pointerRelease(x: x, y: y, button: AutomationQtButton.left)
    report.expectEqual(expected: [String](), actual: fixture.values(fixture.panLane), cppID: id,
                       what: "stationary selection click deletes grabbed node only")
    report.expectEqual(expected: ["48:70"], actual: fixture.values(fixture.volumeLane), cppID: id,
                       what: "stationary selection click preserves other lanes")
    _ = page.pointerPress(x: 400, y: 90, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerRelease(x: 400, y: 90, button: AutomationQtButton.right)
    report.expect(page.selection == nil, cppID: id,
                  message: "outside right press clears selection before opening a menu")
    page.dismissMenu()
    page.selectRange(from: 0, to: fixture.songEndTick, lanes: [fixture.panLane])
    _ = page.pointerPress(x: 400, y: 90, surface: 1, button: AutomationQtButton.right)
    _ = page.pointerMove(x: 404, y: 86, buttons: AutomationQtButton.right)
    report.expect(!page.bandVisible && page.selection?.range == TimeRange(
        startTick: 0, endTick: fixture.songEndTick), cppID: id,
                  message: "a pending band preserves selection below the Manhattan threshold")
    _ = page.pointerMove(x: 405, y: 85, buttons: AutomationQtButton.right)
    report.expect(page.bandVisible, cppID: id,
                  message: "diagonal travel activates at Manhattan ten before Euclidean ten")
    _ = page.pointerMove(x: 400, y: 60, buttons: AutomationQtButton.right)
    _ = page.pointerRelease(x: 400, y: 60, button: AutomationQtButton.right)
    report.expect(page.selection == nil, cppID: id,
                  message: "activated zero-width band clears selection")

    fixture.activate(fixture.volumeLane)
    let rangeBefore = fixture.snapshot
    _ = page.openParameterMenu(index: page.catalogIndex(of: fixture.volumeLane), x: 0, y: 0)
    report.expect(page.consumeMenuAction(actionId: AutomationMenuAction.range64.rawValue),
                  cppID: id, message: "zoomable lane consumes range choice")
    report.expectEqual(expected: 64, actual: page.scaleLabels.first?.value, cppID: id,
                       what: "range choice changes displayed maximum")
    report.expectEqual(expected: rangeBefore, actual: fixture.snapshot, cppID: id,
                       what: "range choice changes neither document nor history")
    fixture.activate(fixture.panLane)
    _ = page.openParameterMenu(index: page.catalogIndex(of: fixture.panLane), x: 0, y: 0)
    report.expect(!page.menuRowActions.contains(AutomationMenuAction.valueRange.rawValue),
                  cppID: id, message: "centered lane has no value range submenu")
    page.dismissMenu()
    fixture.activate(fixture.volumeLane)
    report.expectEqual(expected: 64, actual: page.scaleLabels.first?.value, cppID: id,
                       what: "range persists independently across parameter switches")
    let synthetic = drawerAutomationAutomationFixture(suite: suite, service: service)
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
        report.expectEqual(expected: ["0:80"], actual: synthetic.values(synthetic.volumeLane), cppID: id,
                           what: "promoted value is a written tick-zero event")
        _ = synthetic.page.openPrompt(tick: 0, value: 80)
        synthetic.session.selectedTrack = nil
        let stale = synthetic.snapshot
        report.expect(!synthetic.page.acceptPrompt(displayedValue: 70), cppID: id,
                      message: "a prompt cannot follow a primary-track change")
        report.expectEqual(expected: stale, actual: synthetic.snapshot, cppID: id,
                           what: "stale prompt leaves document and history untouched")
    } else {
        report.fail(id, "synthetic default projection missing")
    }

    let hover = drawerAutomationAutomationFixture(suite: suite, service: service, volume: [(48, 70)])
    hover.activate(hover.volumeLane)
    hover.page.plotFocused = true
    hover.page.isPencilMode = true
    _ = hover.page.pointerMove(x: 400, y: 70, buttons: 0)
    let hoverBefore = hover.snapshot
    report.expect(hover.page.consumeHoverDelete(), cppID: id,
                  message: "pencil blank hover consumes deletion without falling through")
    report.expectEqual(expected: hoverBefore, actual: hover.snapshot, cppID: id,
                       what: "blank hover deletion changes nothing")
    hover.page.selectRange(from: 0, to: 100, lanes: [hover.volumeLane])
    report.expect(!hover.page.consumeHoverDelete(), cppID: id,
                  message: "time selection retains semantic delete priority")
    hover.page.clearTimeSelection()
    hover.page.isPencilMode = false
    report.expect(!hover.page.consumeHoverDelete(), cppID: id,
                  message: "arrow hover cannot claim pencil deletion")
    hover.page.isPencilMode = true
    _ = hover.page.pointerMove(x: hover.x(48), y: hover.y(hover.volumeLane, 70), buttons: 0)
    report.expect(hover.page.consumeHoverDelete(), cppID: id,
                  message: "pencil hover deletion consumes the written point")
    report.expectEqual(expected: [String](), actual: hover.values(hover.volumeLane), cppID: id,
                       what: "hover deletion removes the actual written point")
    report.expectEqual(expected: hoverBefore.revision + 1, actual: hover.document.revision, cppID: id,
                       what: "hover deletion publishes one revision")
    report.expect(hover.undo() && !hover.document.history.canUndo, cppID: id,
                  message: "hover deletion is exactly one undo entry")
    report.expectEqual(expected: ["48:70"], actual: hover.values(hover.volumeLane), cppID: id,
                       what: "undo restores the hover-deleted point")

    _ = hover.page.pointerPress(x: hover.x(48), y: hover.y(hover.volumeLane, 70),
                                 surface: 1, button: AutomationQtButton.right)
    _ = hover.page.pointerRelease(x: hover.x(48), y: hover.y(hover.volumeLane, 70),
                                   button: AutomationQtButton.right)
    report.expect(hover.page.menuTargetIsPoint, cppID: id,
                  message: "the written point owns its captured menu target")
    _ = hover.page.openParameterMenu(index: hover.page.catalogIndex(of: hover.volumeLane),
                                     x: 0, y: 0)
    let superseded = hover.snapshot
    report.expect(!hover.page.consumeMenuAction(actionId: AutomationMenuAction.deleteNode.rawValue),
                  cppID: id, message: "a replacement lane menu invalidates the old point action")
    report.expectEqual(expected: superseded, actual: hover.snapshot, cppID: id,
                       what: "a superseded point command cannot edit the lane")

    let emptyRange = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    emptyRange.page.selectRange(from: 48, to: 96, lanes: [emptyRange.panLane])
    let emptyBefore = emptyRange.snapshot
    report.expect(emptyRange.page.consumeSelectionCommand(command: .nudgeRight), cppID: id,
                  message: "an empty range owns its nudge command")
    report.expect((emptyRange.page.selection?.range.startTick ?? 0) > 48
                      && emptyRange.page.selection?.range.span == 48, cppID: id,
                  message: "an empty range advances on the camera grid without changing its span")
    report.expectEqual(expected: emptyBefore, actual: emptyRange.snapshot, cppID: id,
                       what: "empty-band movement creates no document edit or history")

    let duplicate = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 30)])
    duplicate.page.selectRange(from: 0, to: 48, lanes: [duplicate.panLane])
    report.expect(duplicate.page.consumeSelectionCommand(command: .duplicate), cppID: id,
                  message: "range duplicate is consumed through the canonical command seam")
    report.expectEqual(expected: TimeRange(startTick: 48, endTick: 96), actual: duplicate.page.selection?.range,
                       cppID: id, what: "duplicate moves the band onto the inserted span")
    report.expectEqual(expected: Tick(96), actual: duplicate.session.editCursor, cppID: id,
                       what: "duplicate advances the edit cursor to the new span end")
    report.expect(duplicate.undo() && !duplicate.document.history.canUndo, cppID: id,
                  message: "duplicate remains one undo entry")
    report.expectEqual(expected: ["24:30"], actual: duplicate.values(duplicate.panLane), cppID: id,
                       what: "undo restores the original range contents")
}

@MainActor
private func hostTempoRangeAndBandRows(_ report: CheckReport, suite: DocumentSession,
                                      service: ProjectService) {
    let tempoID = "host/HostAdapterTest::automationTempoRangeDelegatesTheSelectionScope"
    let seamsID = "host/HostSeamsTest::automationPlotFillsHostViewport"
    let voiceID = "host/HostAdapterTest::voiceChangesRefreshWithoutInvalidatingAutomationRaster"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service, volume: [(48, 70)], pan: [(24, 60)],
        tempo: [(0, 500_000), (36, 400_000)])
    let page = fixture.page
    let font = GridCameraPolicy.seedBaseFontPx
    let width = Int(fontPx(font, 70))
    let gutter = Int(fontPx(font, 8))
    let drawer = EditorDrawerPresenter()
    let voice = VoiceChangesPage(baseFontPx: font)
    voice.attach(session: fixture.session, palette: GridPalette())
    drawer.attachSection(page)
    drawer.attachSection(voice)
    drawer.configureLayout(hostWidth: width, hostHeight: Int(fontPx(font, 60)),
                           gutterWidth: gutter, fontPx: font,
                           appFontLineSpacing: fontPx(font, 1))
    drawer.setSectionBodyHeight(kind: DrawerSectionKind.automation.rawValue, height: 180)
    let automation = drawer.automationSection
    report.expect(automation.available && automation.visible
                  && automation.bodyWidth > 0 && automation.bodyHeight > 0,
                  cppID: seamsID,
                  message: "A006 the visible automation band publishes nonempty geometry")
    drawer.setSectionVisible(kind: DrawerSectionKind.voiceChanges.rawValue,
                             visible: true, drawerOwnsFocus: false)
    let bothAutomation = drawer.automationSection
    let voiceBand = drawer.voiceChangesSection
    report.expect(bothAutomation.available && bothAutomation.visible
                  && bothAutomation.bodyWidth > 0 && bothAutomation.bodyHeight > 0,
                  cppID: voiceID,
                  message: "A177 the automation band remains present beside voice changes")
    report.expect(voiceBand.available && voiceBand.visible
                  && voiceBand.bodyWidth > 0 && voiceBand.bodyHeight > 0,
                  cppID: voiceID,
                  message: "A178 the voice-change band remains present beside automation")

    let expectedWidth = Double(width - gutter)
    let expectedHeight = 180.0
    page.configureBody(width: Double(drawer.plotWidth), height: Double(bothAutomation.bodyHeight),
                       gutter: Double(drawer.plotOrigin), devicePixelRatio: 1,
                       baseFontPx: font, dragDistance: AutomationPagePolicy.dragDistance)
    guard page.activateParameter(.tempo) else {
        report.fail(tempoID, "the tempo parameter did not activate for the host range drag")
        return
    }
    report.expect(page.plotOrigin == Double(gutter)
                  && page.plotWidth == expectedWidth && page.plotHeight == expectedHeight
                  && bothAutomation.bodyWidth == width && bothAutomation.bodyHeight == 180,
                  cppID: seamsID,
                  message: "A010 the tempo lane body fills the font-derived plot from its local origin at section height 180")
    report.expect(page.plotWidth > 0 && page.plotHeight > 0, cppID: tempoID,
                  message: "A147 the activated tempo lane body has nonempty bounds")
    let y = page.plotHeight / 2
    let startX = fontPx(font, 1)
    let endX = startX + fontPx(font, 12)
    _ = page.pointerPress(x: startX, y: y, surface: AutomationInputSurface.plot.rawValue,
                          button: AutomationQtButton.right)
    _ = page.pointerMove(x: endX, y: y, buttons: AutomationQtButton.right)
    _ = page.pointerRelease(x: endX, y: y, button: AutomationQtButton.right)
    report.expect(fixture.session.timeSelection?.isActive == true, cppID: tempoID,
                  message: "A148 the right-button tempo drag publishes an active time selection")
    report.expect(fixture.session.timeSelection?.scope == .lanes, cppID: tempoID,
                  message: "A149 the right-button tempo drag selects lane scope")
    report.expect(fixture.session.timeSelection?.tempo == true, cppID: tempoID,
                  message: "A150 the right-button tempo drag includes tempo")
    report.expect(fixture.session.timeSelection?.lanes == [], cppID: tempoID,
                  message: "A151 the right-button tempo drag includes no controller lanes")

    page.clearTimeSelection()
    func row(_ parameter: AutomationParameter, count: Int) -> AutomationRow {
        AutomationRow(parameter: parameter, eventCount: count,
                      coversNodes: false, coversLane: false, selectionHasEvents: false)
    }
    let expectedRows: [AutomationRow] = [
        row(.tempo, count: 2),
        row(.controlChange(track: 0, controller: TimeDefaults.ccVolume), count: 1),
        row(.controlChange(track: 0, controller: TimeDefaults.ccPan), count: 1),
        row(.controlChange(track: 0, controller: TimeDefaults.ccModulation), count: 0),
        row(.pitchBend(track: 0), count: 0),
        row(.controlChange(track: 0, controller: TimeDefaults.ccLFOSpeed), count: 0),
        row(.controlChange(track: 0, controller: TimeDefaults.ccBendRange), count: 0),
        row(.controlChange(track: 0, controller: Xcmd.echoVolumeLane), count: 0),
        row(.controlChange(track: 0, controller: Xcmd.echoLengthLane), count: 0),
        row(.controlChange(track: 0, controller: TimeDefaults.ccModulationType), count: 0),
        row(.controlChange(track: 0, controller: TimeDefaults.ccFineTune), count: 0),
        row(.controlChange(track: 0, controller: TimeDefaults.ccLFODelay), count: 0),
    ]
    fixture.document.writeLane(track: 0, lane: .voice, from: 24, through: 24,
                               points: [LaneWrite(tick: 24, value: 1)])
    let before = page.rows
    report.expect(before == expectedRows, cppID: voiceID,
                  message: "the seeded automation canvas rows match all twelve expected lane identities and counts")
    let playedSample = fixture.session.timeline.sample(for: 24)
    let playedTick = fixture.session.timeline.tick(for: playedSample)
    voice.refreshPlayhead(tick: playedTick, playing: true)
    report.expect(voice.presentedContextSlot == 1 && voice.presentedContextTick == 24,
                  cppID: voiceID,
                  message: "the played sample reaches the seeded tick-24 voice change")
    page.refreshPlayhead(tick: playedTick, playing: true)
    report.expect(page.rows == expectedRows && page.rows == before, cppID: voiceID,
                  message: "A182 the tick-24 voice presentation preserves every seeded automation canvas row")
}
let drawerAutomationMixedHoverID = "swiftcore/AutomationPage::mixedSelectionHoverSnapshot"
let drawerAutomationMixedTempoRowID = "swiftcore/AutomationPage::mixedDragTempoRow"

// A real hover over a staged mixed selection compares the full post-hover
// snapshot. The hover capture below is an opaque pre-stimulus snapshot.
@MainActor
func drawerAutomationMixedSelectionHoverSnapshot(_ report: CheckReport, suite: DocumentSession,
                                                 service: ProjectService) {
    let fixture = drawerAutomationMixedSelectionFixture(suite: suite, service: service)
    fixture.activate(.tempo)
    fixture.page.selectRange(from: 96, to: 144,
                             lanes: [fixture.panLane, fixture.lfoLane, .tempo])
    let hoverBefore = DrawerAutomationStagedSnapshot(fixture.document)
    _ = fixture.page.pointerMove(x: fixture.x(96), y: fixture.y(.tempo, 120), buttons: 0)
    guard fixture.page.hoverVisible else {
        report.fail(drawerAutomationMixedHoverID, "the mixed-selection hover publishes its hover")
        return
    }
    report.expectEqual(expected: hoverBefore, actual: DrawerAutomationStagedSnapshot(fixture.document),
                       cppID: drawerAutomationMixedHoverID,
                       what: "mixed-selection hover compares full-song bytes revision and undo index")
}

// The mixed Tempo/Pan/LFO drag lands the complete effective Tempo row with
// preserved endpoints.
@MainActor
func drawerAutomationMixedDragTempoRow(_ report: CheckReport, suite: DocumentSession,
                                       service: ProjectService) {
    let fixture = drawerAutomationMixedSelectionFixture(suite: suite, service: service)
    fixture.activate(.tempo)
    fixture.page.selectRange(from: 96, to: 144,
                             lanes: [fixture.panLane, fixture.lfoLane, .tempo])
    let endX = drawerAutomationArmHorizontalTempoDrag(fixture)
    _ = fixture.page.pointerRelease(x: endX, y: fixture.y(.tempo, 120),
                                    button: AutomationQtButton.left,
                                    modifiers: AutomationQtModifier.shift)
    report.expect(fixture.tempoValues == ["0:80", "144:120", "384:64"]
                  && fixture.document.state.tempo.first(where: { $0.tick == 144 })?
                      .microsecondsPerQuarterNote == 499_999,
                  cppID: drawerAutomationMixedTempoRowID,
                  message: "the mixed drag keeps the complete Tempo row with exact endpoints")
}
