import Foundation
@testable import PorydawApp
import PorydawCore
@testable import PorydawDocument

@MainActor
func drawerAutomationPencilOwnershipAndShift(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::pencilStrokeOutsideSelectionClearsSelection"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        volume: [(48, 80)], pan: [(24, 64)],
        modulation: [(48, 70)])
    fixture.activate(fixture.panLane)
    let page = fixture.page
    let otherLanes = [
        fixture.volumeLane, fixture.modulationLane,
        .controlChange(track: 0, controller: TimeDefaults.ccLFOSpeed),
        fixture.bendLane,
    ]
    fixture.document.writeLane(
        track: 0, lane: .controller(TimeDefaults.ccLFOSpeed),
        from: 48, through: 48, points: [LaneWrite(tick: 48, value: 45)])
    fixture.document.writeLane(
        track: 0, lane: .voice,
        from: 48, through: 48, points: [LaneWrite(tick: 48, value: 2)])
    fixture.document.writeLane(
        track: 0, lane: .pitchBend,
        from: 48, through: 48, points: [LaneWrite(tick: 48, value: 100)])
    let otherBefore = otherLanes.map { fixture.values($0) }
    let voiceBefore = fixture.document.lanePoints(track: 0, lane: .voice)
    let tempoBefore = fixture.tempoValues
    let cursorBefore = fixture.session.editCursor
    let revisionBefore = page.documentRevision
    fixture.page.selectRange(from: 20, to: 60, lanes: [fixture.panLane])
    fixture.page.isPencilMode = true
    report.expect(
        fixture.page.pointerPress(
            x: fixture.x(120), y: 60, surface: 1,
            button: AutomationQtButton.left),
        cppID: id, message: "a pencil press outside the selection starts")
    report.expect(
        page.isPainting && page.isPencilMode && !page.isPanning && !page.hasBand,
        cppID: id, message: "a pencil press owns the stroke and starts no pan or band")
    report.expect(
        page.documentRevision == revisionBefore
            && page.frozenRevision == revisionBefore
            && fixture.session.editCursor == cursorBefore,
        cppID: id, message: "a pencil press leaves the document revision and edit cursor untouched")
    _ = page.pointerMove(
        x: fixture.x(144), y: fixture.y(fixture.panLane, 90),
        buttons: AutomationQtButton.left)
    report.expect(
        page.documentRevision == revisionBefore
            && page.frozenRevision == revisionBefore
            && fixture.session.editCursor == cursorBefore,
        cppID: id, message: "a pending pencil stroke leaves the document revision and edit cursor untouched")
    report.expect(
        fixture.page.selection == nil, cppID: id,
        message: "starting a pencil stroke outside clears the selection")
    _ = page.pointerRelease(
        x: fixture.x(144), y: fixture.y(fixture.panLane, 90),
        button: AutomationQtButton.left)
    report.expect(
        otherLanes.map { fixture.values($0) } == otherBefore
            && fixture.document.lanePoints(track: 0, lane: .voice) == voiceBefore
            && fixture.tempoValues == tempoBefore,
        cppID: id, message: "a pencil stroke leaves the LFO, Volume, Voice, bend and tempo lanes untouched")

    let lockID = "automation/AutomationEditingTest::nodeDragShiftAxisLocks"
    let horizontal = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)])
    horizontal.activate(horizontal.panLane)
    let shift = drawerAutomationQtModifiers(AutomationModifiers(shift: true))
    _ = horizontal.page.pointerPress(
        x: horizontal.x(24), y: horizontal.y(horizontal.panLane, 64),
        surface: 1, button: 1, modifiers: shift)
    _ = horizontal.page.pointerMove(
        x: horizontal.x(24) + 30, y: horizontal.y(horizontal.panLane, 64),
        buttons: 1, modifiers: shift)
    _ = horizontal.page.pointerMove(
        x: horizontal.x(24) + 60, y: horizontal.y(horizontal.panLane, 64),
        buttons: 1, modifiers: shift)
    _ = horizontal.page.pointerRelease(
        x: horizontal.x(24) + 60,
        y: horizontal.y(horizontal.panLane, 64),
        button: 1, modifiers: shift)
    let moved = horizontal.lanePoints(horizontal.panLane)
    report.expect(
        moved.count == 2 && moved[0].value == 64 && moved[0].tick > 24, cppID: lockID,
        message: "a horizontal Shift drag locks the value and moves the tick")
    let vertical = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)])
    vertical.activate(vertical.panLane)
    _ = vertical.page.pointerPress(
        x: vertical.x(24), y: vertical.y(vertical.panLane, 64),
        surface: 1, button: 1, modifiers: shift)
    _ = vertical.page.pointerMove(
        x: vertical.x(24), y: vertical.y(vertical.panLane, 64) - 20,
        buttons: 1, modifiers: shift)
    _ = vertical.page.pointerMove(
        x: vertical.x(24), y: vertical.y(vertical.panLane, 64) - 40,
        buttons: 1, modifiers: shift)
    _ = vertical.page.pointerRelease(
        x: vertical.x(24), y: vertical.y(vertical.panLane, 64) - 40,
        button: 1, modifiers: shift)
    let shifted = vertical.lanePoints(vertical.panLane)
    report.expect(
        shifted.count == 2 && shifted[0].tick == 24 && shifted[0].value != 64,
        cppID: lockID,
        message: "a vertical Shift drag locks the tick and moves the value")

    let doubleID = "automation/AutomationEditingTest::doubleClickDeletesOnceWithoutValuePrompt"
    for parameter in [
        AutomationParameter.tempo,
        .controlChange(track: 0, controller: TimeDefaults.ccPan),
    ] {
        let twice = drawerAutomationAutomationFixture(
            suite: suite, service: service,
            pan: [(0, 80), (96, 100), (288, 64)],
            tempo: [(0, 750_000), (96, 600_000), (288, 937_500)])
        twice.activate(parameter)
        let before = twice.snapshot
        let nodeX = twice.x(96)
        let nodeY = twice.y(parameter, 100)
        report.expect(
            twice.page.pointerDoubleClick(x: nodeX, y: nodeY),
            cppID: doubleID, message: "a double-click on the node is handled")
        report.expect(
            !twice.page.hasPrompt, cppID: doubleID,
            message: "a double-click never opens the value prompt")
        report.expectEqual(
            expected: before.revision + 1, actual: twice.document.revision, cppID: doubleID,
            what: "the double-click publishes exactly one revision")
        let expected = ["0:80", "288:64"]
        let actual = parameter == .tempo ? twice.tempoValues : twice.values(twice.panLane)
        report.expectEqual(
            expected: expected, actual: actual, cppID: doubleID,
            what: "only the clicked node is deleted from the active adapter")
        report.expect(
            twice.document.history.canUndo, cppID: doubleID,
            message: "the deletion records an undo entry")
        report.expect(
            twice.undo(), cppID: doubleID,
            message: "the double-click deletion can be undone")
        report.expect(
            !twice.document.history.canUndo, cppID: doubleID,
            message: "one undo consumes the double-click's single history entry")
        let restored = parameter == .tempo ? twice.tempoValues : twice.values(twice.panLane)
        report.expectEqual(
            expected: ["0:80", "96:100", "288:64"], actual: restored, cppID: doubleID,
            what: "one undo restores the deleted node and its two neighbours")
    }
}

@MainActor
func drawerAutomationDetailThresholdPrecedence(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::detailThresholdHiddenVisibleNodePrecedence"
    let fixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    fixture.page.isPencilMode = true
    func markersVisible() -> Bool {
        AutomationProjection(
            camera: fixture.session.camera,
            bounds: AutomationPlotBounds(width: 480, height: 120, devicePixelRatio: 1),
            geometry: fixture.page.geometry,
            snapPolicy: AutomationProjectionCache().snapPolicy(session: fixture.session, font: 13, dpr: 1),
            songEndTick: fixture.songEndTick
        ).markersVisible()
    }
    report.expect(markersVisible(), cppID: id, message: "markers are visible at default zoom")
    let zoomAnchor = fixture.x(24)
    _ = fixture.session.mutateCamera {
        report.expect(
            $0.zoomAroundContentX(factor: 0.25, anchorContentX: zoomAnchor).zoomChanged,
            cppID: id, message: "quarter-scale zoom changes the camera")
    }
    report.expect(
        markersVisible(), cppID: id,
        message: "markers stay visible at a quarter of the default zoom")
    _ = fixture.session.mutateCamera {
        report.expect(
            $0.zoomAroundContentX(factor: 0.02, anchorContentX: zoomAnchor).zoomChanged,
            cppID: id, message: "detail-threshold zoom changes the camera")
    }
    report.expect(
        !markersVisible(), cppID: id,
        message: "markers hide below the detail threshold")
    report.expect(
        fixture.page.pointerPress(
            x: fixture.x(24), y: fixture.y(fixture.panLane, 70),
            surface: 1, button: 1),
        cppID: id, message: "the pencil press through hidden markers starts a stroke")
    report.expect(
        fixture.page.pointerRelease(
            x: fixture.x(24), y: fixture.y(fixture.panLane, 70),
            button: 1),
        cppID: id, message: "the stroke through hidden markers commits")
    let hidden = fixture.lanePoints(fixture.panLane)
    report.expect(
        hidden.count == 3 && hidden.contains(where: { $0.tick == 24 && $0.value == 70 }),
        cppID: id,
        message: "the hidden-marker stroke inserts instead of grabbing the node")
    let zoomBack = fixture.x(120)
    _ = fixture.session.mutateCamera {
        report.expect(
            $0.zoomAroundContentX(factor: 50, anchorContentX: zoomBack).zoomChanged,
            cppID: id, message: "zooming back changes the camera")
    }
    report.expect(markersVisible(), cppID: id, message: "markers return above the threshold")

    let shownFixture = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(24, 64), (120, 40)])
    shownFixture.activate(shownFixture.panLane)
    shownFixture.page.isPencilMode = true
    report.expect(
        shownFixture.page.pointerPress(
            x: shownFixture.x(24), y: shownFixture.y(shownFixture.panLane, 64),
            surface: 1, button: 1),
        cppID: id, message: "the pencil press on a visible node grabs it")
    _ = shownFixture.page.pointerRelease(
        x: shownFixture.x(24),
        y: shownFixture.y(shownFixture.panLane, 64), button: 1)
    report.expectEqual(
        expected: ["120:40"], actual: shownFixture.values(shownFixture.panLane), cppID: id,
        what: "a stationary release on the grabbed node deletes exactly it")
}

@MainActor
func drawerAutomationTempoBendClickRestore(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService
) {
    let tempoID = "automation/AutomationEditingTest::pencilSingleClickOnTempoLaneRestoresDefaultTempoAtCellEnd"
    let tempo = drawerAutomationAutomationFixture(suite: suite, service: service, tempo: [])
    tempo.activate(.tempo)
    tempo.page.isPencilMode = true
    let tempoBefore = tempo.snapshot
    let tempoIndex = tempo.document.history.undoIndex
    let tempoBytes = try? tempo.document.state.file.encoded()
    let tempoPan = tempo.values(tempo.panLane)
    report.expect(
        tempo.page.pointerPress(
            x: tempo.x(48), y: tempo.y(.tempo, 150),
            surface: 1, button: 1),
        cppID: tempoID, message: "the pencil press on the empty tempo lane starts")
    report.expect(
        tempo.page.pointerRelease(x: tempo.x(48), y: tempo.y(.tempo, 150), button: 1),
        cppID: tempoID, message: "the tempo click commits")
    report.expectEqual(
        expected: ["48:150", "54:120"], actual: tempo.tempoValues, cppID: tempoID,
        what: "the click writes its BPM at the cell start and restores default at the end")
    report.expectEqual(
        expected: tempoBefore.revision + 1,
        actual: tempo.document.revision, cppID: tempoID,
        what: "the tempo pencil click records one revision")
    report.expectEqual(
        expected: tempoIndex + 1, actual: tempo.document.history.undoIndex,
        cppID: tempoID, what: "the tempo click advances the undo index once")
    report.expectEqual(
        expected: tempoPan, actual: tempo.values(tempo.panLane),
        cppID: tempoID, what: "the tempo click leaves the Pan lane unchanged")
    report.expect(
        tempo.document.history.canUndo, cppID: tempoID,
        message: "the tempo pencil click records one undo entry")
    report.expect(tempo.undo(), cppID: tempoID, message: "the tempo pencil click undoes")
    report.expectEqual(
        expected: tempoBefore.identity,
        actual: tempo.snapshot.identity, cppID: tempoID,
        what: "one undo restores the empty tempo lane")
    report.expect(
        tempo.tempoValues.isEmpty, cppID: tempoID,
        message: "undo removes the tempo click's points")
    report.expect(
        tempo.document.history.undoIndex == tempoIndex
            && (try? tempo.document.state.file.encoded()) == tempoBytes,
        cppID: tempoID, message: "one tempo undo restores its original MIDI bytes")

    let bendID = "automation/AutomationEditingTest::pencilSingleClickOnPitchBendLaneRestoresCenterAtCellEnd"
    let bend = drawerAutomationAutomationFixture(suite: suite, service: service)
    bend.activate(bend.bendLane)
    bend.page.isPencilMode = true
    let bendBefore = bend.snapshot
    let bendIndex = bend.document.history.undoIndex
    let bendBytes = try? bend.document.state.file.encoded()
    let bendPan = bend.values(bend.panLane)
    report.expect(
        bend.page.pointerPress(
            x: bend.x(48), y: bend.y(bend.bendLane, 100),
            surface: 1, button: 1),
        cppID: bendID, message: "the pencil press on the empty bend lane starts")
    report.expect(
        bend.page.pointerRelease(x: bend.x(48), y: bend.y(bend.bendLane, 100), button: 1),
        cppID: bendID, message: "the bend click commits")
    report.expectEqual(
        expected: ["48:100", "54:0"], actual: bend.values(bend.bendLane), cppID: bendID,
        what: "the click writes its value at the cell start and restores center at the end")
    report.expectEqual(
        expected: bendBefore.revision + 1, actual: bend.document.revision,
        cppID: bendID, what: "the bend pencil click records one revision")
    report.expectEqual(
        expected: bendIndex + 1, actual: bend.document.history.undoIndex,
        cppID: bendID, what: "the bend click advances the undo index once")
    report.expectEqual(
        expected: bendPan, actual: bend.values(bend.panLane),
        cppID: bendID, what: "the bend click leaves the Pan lane unchanged")
    report.expect(
        bend.undo() && bend.document.history.undoIndex == bendIndex
            && (try? bend.document.state.file.encoded()) == bendBytes,
        cppID: bendID, message: "one bend undo restores its original MIDI bytes")

    let excursionID = "automation/AutomationEditingTest::pencilClickOnExcursionNodeDeletesExcursion"
    let excursion = drawerAutomationAutomationFixture(
        suite: suite, service: service,
        pan: [(0, 60), (48, 90), (54, 60)])
    excursion.activate(excursion.panLane)
    excursion.page.isPencilMode = true
    let excursionBefore = excursion.snapshot
    let excursionIndex = excursion.document.history.undoIndex
    let excursionBytes = try? excursion.document.state.file.encoded()
    let excursionTempo = excursion.tempoValues
    report.expect(
        excursion.page.pointerPress(
            x: excursion.x(48), y: excursion.y(excursion.panLane, 60),
            surface: 1, button: 1),
        cppID: excursionID, message: "the pencil press at baseline over the excursion starts")
    report.expect(
        excursion.page.pointerRelease(
            x: excursion.x(48),
            y: excursion.y(excursion.panLane, 60), button: 1),
        cppID: excursionID, message: "the baseline click commits")
    report.expectEqual(
        expected: ["0:60"], actual: excursion.values(excursion.panLane), cppID: excursionID,
        what: "collapsing the excursion leaves the baseline alone")
    report.expectEqual(
        expected: excursionBefore.revision + 1, actual: excursion.document.revision,
        cppID: excursionID, what: "the excursion click records one revision")
    report.expectEqual(
        expected: excursionIndex + 1, actual: excursion.document.history.undoIndex,
        cppID: excursionID, what: "the excursion click advances the undo index once")
    report.expectEqual(
        expected: excursionTempo, actual: excursion.tempoValues,
        cppID: excursionID, what: "the excursion click leaves Tempo unchanged")
    report.expect(
        excursion.undo() && excursion.document.history.undoIndex == excursionIndex
            && (try? excursion.document.state.file.encoded()) == excursionBytes,
        cppID: excursionID, message: "one excursion undo restores the original MIDI bytes")
}
