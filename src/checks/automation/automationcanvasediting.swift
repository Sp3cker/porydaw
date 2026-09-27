import Foundation
@testable import PorydawApp
@testable import PorydawAppCommands
import PorydawCore

// Existing scenarios paired with automationcanvasediting.cpp.
// Entry order remains in AutomationPageChecks.swift.



@MainActor
func drawerAutomationCancellationAndNoOps(_ report: CheckReport, suite: DocumentSession,
                                  service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64), (120, 40)])
    fixture.activate(fixture.panLane)
    let before = fixture.snapshot

    // A press and cancel writes nothing and ends every owned interaction.
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a press on a node grabs it")
    report.expect(fixture.page.hasGesture && fixture.page.interactionActive, cppID: drawerAutomationCancelID,
                  message: "the page publishes the live gesture")
    report.expect(fixture.page.handleEscape(), cppID: drawerAutomationCancelID,
                  message: "Escape claims the live gesture")
    report.expect(!fixture.page.hasGesture && !fixture.page.interactionActive, cppID: drawerAutomationCancelID,
                  message: "cancelling ends the gesture synchronously")
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: drawerAutomationCancelID,
                       what: "a cancelled gesture mutates nothing")
    report.expect(!fixture.page.handleEscape(), cppID: drawerAutomationCancelID,
                  message: "Escape with nothing to claim stays unhandled")

    // A stroke that never travelled commits nothing.
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a second press grabs the node")
    _ = fixture.page.pointerMove(x: fixture.x(24) + 12, y: fixture.y(fixture.panLane, 64), buttons: 1)
    _ = fixture.page.pointerRelease(x: fixture.x(24) + 12, y: fixture.y(fixture.panLane, 64), button: 1)
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: drawerAutomationCancelID,
                       what: "an armed stroke that moved no node writes nothing")

    // Shift-held stationary release is a no-op; plain stationary release deletes.
    report.expect(fixture.page.pointerPress(x: fixture.x(120), y: fixture.y(fixture.panLane, 40),
                                            surface: 1, button: 1, modifiers: drawerAutomationQtModifiers(.init(shift: true))), cppID: drawerAutomationCancelID,
                  message: "a Shift-held press grabs the node")
    _ = fixture.page.pointerRelease(x: fixture.x(120), y: fixture.y(fixture.panLane, 40),
                                    button: 1, modifiers: drawerAutomationQtModifiers(.init(shift: true)))
    report.expectEqual(expected: before, actual: fixture.snapshot, cppID: drawerAutomationCancelID,
                       what: "a Shift-held stationary release deletes nothing")
    report.expect(fixture.page.pointerPress(x: fixture.x(120), y: fixture.y(fixture.panLane, 40), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a plain press grabs the node")
    _ = fixture.page.pointerRelease(x: fixture.x(120), y: fixture.y(fixture.panLane, 40), button: 1)
    report.expectEqual(expected: ["24:64"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationCancelID,
                       what: "a plain stationary release deletes the grabbed node")
    report.expect(fixture.undo(), cppID: drawerAutomationCancelID, message: "the stationary delete is undoable")
    report.expectEqual(expected: ["24:64", "120:40"], actual: fixture.values(fixture.panLane), cppID: drawerAutomationCancelID,
                       what: "one undo restores the deleted node")
    report.expect(!fixture.document.history.canUndo, cppID: drawerAutomationCancelID,
                  message: "the stationary delete recorded exactly one history entry")

    // A stale revision cancels the frozen interaction instead of retargeting it.
    let pressRevision = fixture.document.revision
    report.expect(fixture.page.pointerPress(x: fixture.x(24), y: fixture.y(fixture.panLane, 64), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a press freezes the current revision")
    report.expectEqual(expected: pressRevision, actual: fixture.page.frozenRevision ?? 0, cppID: drawerAutomationCancelID,
                       what: "the frozen facts carry the revision")
    fixture.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 168,
                               through: 168, points: [LaneWrite(tick: 168, value: 5)])
    report.expect(!fixture.page.hasGesture, cppID: drawerAutomationCancelID,
                  message: "a document change outside the gesture cancels it")
    let afterStale = fixture.snapshot
    _ = fixture.page.pointerMove(x: fixture.x(24) + 40, y: fixture.y(fixture.panLane, 64), buttons: 1)
    _ = fixture.page.pointerRelease(x: fixture.x(24) + 40, y: fixture.y(fixture.panLane, 64), button: 1)
    report.expectEqual(expected: afterStale, actual: fixture.snapshot, cppID: drawerAutomationCancelID,
                       what: "a cancelled stale gesture never writes on release")

    // An empty-lane press parks the edit cursor instead of writing.
    let empty = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [])
    empty.activate(empty.panLane)
    let emptyBefore = empty.snapshot
    let pressX = empty.x(72)
    let cursorBeforeBodyPress = empty.session.editCursor
    report.expect(empty.page.pointerPress(x: pressX, y: 60, surface: 1, button: 1), cppID: drawerAutomationCancelID,
                  message: "a press on an empty lane starts a sweep")
    report.expect(!empty.page.bandVisible, cppID: "automation/AutomationEditingTest::defaultBodyClickSetsCursorOnly",
                  message: "the default body press previews no range")
    report.expectEqual(expected: cursorBeforeBodyPress, actual: empty.session.editCursor,
                       cppID: "automation/AutomationEditingTest::defaultBodyClickSetsCursorOnly",
                       what: "the edit cursor stays parked while the body press is held")
    report.expect(!empty.page.pointerRelease(x: pressX, y: 60, button: 1), cppID: drawerAutomationCancelID,
                  message: "a press that never travelled commits nothing")
    report.expect(!empty.page.isPanning, cppID: "automation/AutomationEditingTest::defaultBodyClickSetsCursorOnly",
                  message: "the released body press has no pan")
    report.expect(!empty.page.bandVisible, cppID: "automation/AutomationEditingTest::defaultBodyClickSetsCursorOnly",
                  message: "the released body press leaves no range preview")
    report.expectEqual(expected: emptyBefore, actual: empty.snapshot, cppID: drawerAutomationCancelID,
                       what: "the parked press leaves the document alone")
    let policy = AutomationProjectionCache().snapPolicy(session: empty.session, font: 13, dpr: 1)
    let snapped = policy.snap(min(max(0, empty.session.camera.tickAtContentX(pressX)),
                                  Double(empty.songEndTick)),
                              fine: false, camera: empty.session.camera)
    report.expectEqual(expected: snapped, actual: empty.session.editCursor, cppID: drawerAutomationCancelID,
                       what: "the press parks the edit cursor at the snapped tick")

    let voiceID = "automation/AutomationEditingTest::voicePressIsolated"
    let voice = VoiceChangesPage(baseFontPx: 13)
    voice.attach(session: empty.session, palette: GridPalette())
    voice.configureBody(width: 480, height: 120, gutter: 0, devicePixelRatio: 1,
                        baseFontPx: 13, dragDistance: 10)
    let beforeVoicePress = empty.snapshot
    let cursorBeforeVoicePress = empty.session.editCursor
    _ = voice.pointerPress(x: empty.x(72), y: 60, surface: 1, button: 1, modifiers: 0)
    report.expectEqual(expected: beforeVoicePress, actual: empty.snapshot, cppID: voiceID,
                       what: "pressing the voice input leaves the automation document frozen")
    report.expectEqual(expected: cursorBeforeVoicePress, actual: empty.session.editCursor, cppID: voiceID,
                       what: "pressing the voice input leaves the edit cursor parked")
    _ = voice.pointerRelease(x: empty.x(72), y: 60, button: 1)

    // A sub-threshold move leaves a frozen gesture alive but unchanged.
    let jitter = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    jitter.activate(jitter.panLane)
    report.expect(jitter.page.pointerPress(x: jitter.x(24), y: jitter.y(jitter.panLane, 64), surface: 1, button: 1),
                  cppID: drawerAutomationCancelID, message: "a press grabs the node")
    _ = jitter.page.pointerMove(x: jitter.x(24) + 2, y: jitter.y(jitter.panLane, 64) + 2, buttons: 1)
    report.expectEqual(expected: [Tick(24): 64], actual: [jitter.page.previewPoints.first?.tick ?? 0:
                                            jitter.page.previewPoints.first?.value ?? 0],
                       cppID: drawerAutomationCancelID,
                       what: "a sub-threshold move previews the untouched target")
    report.expectEqual(expected: jitter.snapshot, actual: DocumentSnapshot(jitter.document), cppID: drawerAutomationCancelID,
                       what: "a sub-threshold move writes nothing")
}

@MainActor
func drawerAutomationContextAndPublicationDiagnostics(_ report: CheckReport, suite: DocumentSession,
                                              service: ProjectService) {
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service,
                                    volume: [(0, 127), (96, 64)])
    fixture.activate(fixture.volumeLane)
    let builds = fixture.page.contentBuildCount
    let selectionBuilds = fixture.page.selectionBuildCount
    let contextChanges = fixture.page.contextChangeCount
    report.expectEqual(expected: Tick(0), actual: fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a stopped page presents the edit cursor")

    // A cursor-only publication updates the stopped context without rebuilding
    // document-derived content or changing document/history state.
    let cursorDocument = fixture.snapshot
    fixture.session.editCursor = 100
    report.expectEqual(expected: Tick(100), actual: fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a stopped context consumes the published edit cursor")
    report.expectEqual(expected: 64, actual: fixture.page.contextValue ?? -1, cppID: drawerAutomationContextID,
                       what: "the context readout is the lane's held value there")
    report.expect(fixture.page.contextChangeCount > contextChanges, cppID: drawerAutomationContextID,
                  message: "a cursor-only context move is counted")
    report.expectEqual(expected: builds, actual: fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a cursor-only publication rebuilds no static content")
    report.expectEqual(expected: cursorDocument, actual: fixture.snapshot, cppID: drawerAutomationContextID,
                       what: "a cursor-only publication changes no document or history state")

    // A shared-playhead presentation retargets the context and rebuilds nothing.
    let buildsBeforePlayhead = fixture.page.contentBuildCount
    let presentations = fixture.page.playheadPresentationCount
    fixture.page.refreshPlayhead(tick: 50, playing: true)
    report.expect(fixture.page.playing, cppID: drawerAutomationContextID, message: "the page consumes playing")
    report.expectEqual(expected: Tick(50), actual: fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a playing context consumes the shared playhead tick")
    report.expectEqual(expected: 127, actual: fixture.page.contextValue ?? -1, cppID: drawerAutomationContextID,
                       what: "the playing context reads the held value at its own tick")
    report.expectEqual(expected: presentations + 1, actual: fixture.page.playheadPresentationCount, cppID: drawerAutomationContextID,
                       what: "the presentation is counted once")
    report.expectEqual(expected: buildsBeforePlayhead, actual: fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a playhead-only update rebuilds no static content")
    fixture.page.refreshPlayhead(tick: 50, playing: true)
    report.expectEqual(expected: presentations + 1, actual: fixture.page.playheadPresentationCount, cppID: drawerAutomationContextID,
                       what: "an equal presentation is dropped")
    fixture.page.refreshPlayhead(tick: 60, playing: true)
    report.expectEqual(expected: presentations + 2, actual: fixture.page.playheadPresentationCount, cppID: drawerAutomationContextID,
                       what: "a moved playhead presents again")
    report.expectEqual(expected: buildsBeforePlayhead, actual: fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "repeated playhead movement still rebuilds nothing")
    fixture.page.refreshPlayhead(tick: 60, playing: false)
    report.expectEqual(expected: Tick(100), actual: fixture.page.contextTick, cppID: drawerAutomationContextID,
                       what: "a stopped transport returns to the edit cursor")

    // A camera-only publication reprojects the curve, which is a content build.
    let buildsBeforeCamera = fixture.page.contentBuildCount
    _ = fixture.session.mutateCamera { _ = $0.setTimeZoom(90) }
    report.expectEqual(expected: buildsBeforeCamera + 1, actual: fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a camera change reprojects the curve once")

    // A selection change rebuilds and is counted apart from content builds.
    let buildsBeforeSelection = fixture.page.contentBuildCount
    fixture.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 96), scope: .lanes, lanes: [fixture.volumeLane]))
    report.expectEqual(expected: buildsBeforeSelection + 1, actual: fixture.page.contentBuildCount, cppID: drawerAutomationContextID,
                       what: "a selection change rebuilds the content it displays")
    report.expectEqual(expected: selectionBuilds + 1, actual: fixture.page.selectionBuildCount, cppID: drawerAutomationContextID,
                       what: "the selection build is counted on its own")
    let points = fixture.page.projection?.points ?? []
    report.expect(points.contains { $0.selected } && points.contains { !$0.selected },
                  cppID: drawerAutomationContextID,
                  message: "the projection marks the points inside the selection")
    report.expectEqual(expected: ["0:127"], actual: fixture.laneValues(points.filter(\.selected).map {
        AutomationLanePoint(tick: $0.tick, value: $0.value)
    }).count == 1 ? ["0:127"] : [], cppID: drawerAutomationContextID,
                       what: "the selection marks exactly the points inside its range")
    fixture.page.applyTimeSelection(nil)
    let cleared = fixture.page.projection?.points ?? []
    report.expect(!cleared.isEmpty, cppID: drawerAutomationContextID,
                  message: "clearing the selection keeps the lane's points")
    report.expect(cleared.allSatisfy { !$0.selected },
                  cppID: drawerAutomationContextID, message: "clearing the selection clears every indicator")
    report.expect(fixture.page.contentBuildCount > builds, cppID: drawerAutomationContextID,
                  message: "the content builds accumulated across the case")

    // Hover: a node publishes its own value text, the background the held value.
    let hoverBuilds = fixture.page.hoverBuildCount
    _ = fixture.page.pointerMove(x: fixture.x(96), y: fixture.y(fixture.volumeLane, 64),
                                 buttons: 0)
    report.expect(fixture.page.hover?.hasPoint == true, cppID: drawerAutomationContextID,
                  message: "a hover on a node publishes the node")
    report.expectEqual(expected: "64", actual: fixture.page.hover?.text ?? "", cppID: drawerAutomationContextID,
                       what: "a node hover reads out the node's value")
    report.expectEqual(expected: AutomationHintProfile.node, actual: fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
                       what: "a written node advertises node movement")
    _ = fixture.page.pointerMove(x: fixture.x(150), y: fixture.y(fixture.volumeLane, 20),
                                 buttons: 0)
    report.expect(fixture.page.hover?.hasPoint == false, cppID: drawerAutomationContextID,
                  message: "a hover on the background publishes the tick")
    report.expectEqual(expected: "64", actual: fixture.page.hover?.text ?? "", cppID: drawerAutomationContextID,
                       what: "a background hover reads the value the lane holds there")
    report.expect(fixture.page.hoverBuildCount > hoverBuilds, cppID: drawerAutomationContextID,
                  message: "the hover publications are counted")
    report.expectEqual(expected: AutomationHintProfile.sweep, actual: fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
                       what: "the background advertises sweep and ramp input")
    fixture.page.isPencilMode = true
    report.expectEqual(expected: AutomationHintProfile.pencil, actual: fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
                       what: "switching tools updates stationary hover instructions")
    fixture.page.isPencilMode = false
    report.expectEqual(expected: AutomationHintProfile.sweep, actual: fixture.page.hoverHintProfile, cppID: drawerAutomationContextID,
                       what: "leaving pencil mode restores sweep instructions")
    fixture.page.pointerLeave()
    report.expect(fixture.page.hover == nil, cppID: drawerAutomationContextID,
                  message: "leaving the plot clears the hover")

    // Detach drops everything the page published.
    var copyAvailable = false
    fixture.page.onCommandAvailabilityChanged = { [weak page = fixture.page] in
        copyAvailable = page?.selectionCommandAvailable(command: .copy) ?? false
    }
    fixture.page.detach()
    report.expect(fixture.page.projection == nil && fixture.page.rows.isEmpty
                      && fixture.page.selection == nil,
                  cppID: drawerAutomationContextID, message: "detaching drops every published value")
    fixture.page.attach(session: fixture.session, palette: GridPalette())
    fixture.activate(fixture.volumeLane)
    fixture.page.applyTimeSelection(AutomationTimeSelection(
        range: TimeRange(startTick: 0, endTick: 96), scope: .lanes, lanes: [fixture.volumeLane]))
    report.expect(copyAvailable, cppID: drawerAutomationContextID,
                  message: "a retained command subscriber observes selection after page reattachment")
}

@MainActor
func drawerAutomationInflightDragInvalidation(_ report: CheckReport, suite: DocumentSession,
                                              service: ProjectService) {
    let rebuildID = "automation/AutomationEditingTest::rebuildCancelsAdapterDragAndRecovers"
    let rebuilt = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 64), (120, 40)])
    rebuilt.activate(rebuilt.panLane)
    let page = rebuilt.page
    report.expect(page.pointerPress(x: rebuilt.x(24), y: rebuilt.y(rebuilt.panLane, 64),
                                     surface: 1, button: 1),
                  cppID: rebuildID, message: "a press grabs the node")
    _ = page.pointerMove(x: rebuilt.x(24) + 30, y: rebuilt.y(rebuilt.panLane, 64), buttons: 1)
    report.expect(page.hasGesture, cppID: rebuildID, message: "the drag is live past the slop")
    rebuilt.document.writeLane(track: 0, lane: .controller(TimeDefaults.ccPan), from: 168,
                               through: 168, points: [LaneWrite(tick: 168, value: 5)])
    report.expect(!page.hasGesture, cppID: rebuildID,
                  message: "the document rebuild cancels the drag synchronously")
    let afterRebuild = rebuilt.snapshot
    _ = page.pointerRelease(x: rebuilt.x(24) + 30, y: rebuilt.y(rebuilt.panLane, 64), button: 1)
    report.expectEqual(expected: afterRebuild, actual: rebuilt.snapshot, cppID: rebuildID,
                       what: "releasing the cancelled drag commits nothing")
    report.expect(page.pointerPress(x: rebuilt.x(24), y: rebuilt.y(rebuilt.panLane, 64),
                                     surface: 1, button: 1),
                  cppID: rebuildID, message: "a fresh press grabs the node after the rebuild")
    _ = page.pointerMove(x: rebuilt.x(24) + 30, y: rebuilt.y(rebuilt.panLane, 64), buttons: 1)
    _ = page.pointerMove(x: rebuilt.x(24) + 30, y: rebuilt.y(rebuilt.panLane, 90), buttons: 1)
    _ = page.pointerRelease(x: rebuilt.x(24) + 30, y: rebuilt.y(rebuilt.panLane, 90), button: 1)
    report.expectEqual(expected: ["24:90", "120:40", "168:5"], actual: rebuilt.values(rebuilt.panLane),
                       cppID: rebuildID, what: "the recovery drag commits normally")

    let switchID = "automation/AutomationEditingTest::parameterSwitchCancelsNodeDrag"
    let switched = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                     pan: [(24, 64), (120, 40)])
    switched.activate(switched.panLane)
    let switchedBefore = switched.snapshot
    report.expect(switched.page.pointerPress(
        x: switched.x(24), y: switched.y(switched.panLane, 64), surface: 1, button: 1),
                  cppID: switchID, message: "a press grabs the node")
    _ = switched.page.pointerMove(x: switched.x(24) + 30, y: switched.y(switched.panLane, 64),
                                   buttons: 1)
    report.expect(switched.page.hasGesture, cppID: switchID, message: "the drag is live")
    switched.activate(switched.volumeLane)
    report.expect(!switched.page.hasGesture, cppID: switchID,
                  message: "switching parameters cancels the drag")
    report.expectEqual(expected: switchedBefore, actual: switched.snapshot, cppID: switchID,
                       what: "the cancelled drag writes nothing")
    _ = switched.page.pointerRelease(x: switched.x(24) + 30,
                                      y: switched.y(switched.panLane, 64), button: 1)
    report.expectEqual(expected: switchedBefore, actual: switched.snapshot, cppID: switchID,
                       what: "releasing after the switch commits nothing")
    switched.activate(switched.panLane)
    report.expect(switched.page.pointerPress(
        x: switched.x(24), y: switched.y(switched.panLane, 64), surface: 1, button: 1),
                  cppID: switchID, message: "a fresh press grabs the node after the switch")
    _ = switched.page.pointerMove(x: switched.x(24) + 30, y: switched.y(switched.panLane, 64),
                                   buttons: 1)
    _ = switched.page.pointerMove(x: switched.x(24) + 30, y: switched.y(switched.panLane, 90),
                                   buttons: 1)
    _ = switched.page.pointerRelease(x: switched.x(24) + 30, y: switched.y(switched.panLane, 90),
                                      button: 1)
    report.expectEqual(expected: ["24:90", "120:40"], actual: switched.values(switched.panLane), cppID: switchID,
                       what: "the recovery drag commits normally")
}

@MainActor
func drawerAutomationKeyboardIngress(_ report: CheckReport, suite: DocumentSession,
                                     service: ProjectService) {
    let selID = "automation/AutomationEditingTest::selectionClearingAndMultilaneReplacement"
    let fixture = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    fixture.activate(fixture.panLane)
    fixture.page.selectRange(from: 20, to: 60, lanes: [fixture.panLane])
    let selected = fixture.snapshot
    report.expect(fixture.page.handleEscape(), cppID: selID,
                  message: "Escape with only an explicit selection claims it")
    report.expect(fixture.page.selection == nil, cppID: selID,
                  message: "Escape clears the explicit time selection")
    report.expectEqual(expected: selected, actual: fixture.snapshot, cppID: selID,
                       what: "clearing the selection writes nothing")
    fixture.page.refreshFromDocument()
    report.expect(fixture.page.selection == nil
                      && fixture.session.timeSelection == nil
                      && fixture.page.projection?.points.allSatisfy({ !$0.selected }) == true,
                  cppID: selID, message: "Escape clears the selection and the rebuilt selection is empty")
    let outside = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                    pan: [(24, 64)])
    outside.activate(outside.panLane)
    outside.page.selectRange(from: 20, to: 60, lanes: [outside.panLane])
    _ = outside.page.pointerPress(x: outside.x(120), y: outside.y(outside.panLane, 64),
                                  surface: AutomationInputSurface.plot.rawValue,
                                  button: AutomationQtButton.left)
    report.expect(outside.page.selection == nil && outside.session.timeSelection == nil,
                  cppID: selID, message: "a plain left press clears the time selection")
    _ = outside.page.pointerRelease(x: outside.x(120), y: outside.y(outside.panLane, 64),
                                    button: AutomationQtButton.left)

    let precedence = drawerAutomationAutomationFixture(suite: suite, service: service,
                                                       pan: [(24, 64)])
    precedence.activate(precedence.panLane)
    precedence.page.selectRange(from: 20, to: 60, lanes: [precedence.panLane])
    report.expect(precedence.page.pointerPress(x: precedence.x(24),
                                                y: precedence.y(precedence.panLane, 64),
                                                surface: 1, button: 1),
                  cppID: selID, message: "a press inside the selection grabs the node")
    let grabbed = precedence.snapshot
    _ = precedence.page.pointerMove(x: precedence.x(24) + 30,
                                    y: precedence.y(precedence.panLane, 64),
                                    buttons: AutomationQtButton.left)
    _ = precedence.page.pointerMove(x: precedence.x(24) + 60,
                                    y: precedence.y(precedence.panLane, 64),
                                    buttons: AutomationQtButton.left)
    report.expect(precedence.page.hasGesture, cppID: selID,
                  message: "the adapter drag arms before Escape")
    report.expect(precedence.page.handleEscape(), cppID: selID,
                  message: "Escape with a live gesture claims it")
    report.expect(!precedence.page.hasGesture, cppID: selID,
                  message: "Escape cancels the gesture first")
    report.expect(precedence.page.selection != nil, cppID: selID,
                  message: "the selection survives a gesture-first Escape")
    report.expectEqual(expected: grabbed, actual: precedence.snapshot, cppID: selID,
                       what: "a gesture-first Escape writes nothing")
    _ = precedence.page.pointerRelease(x: precedence.x(24) + 60,
                                       y: precedence.y(precedence.panLane, 64),
                                       button: AutomationQtButton.left)
    report.expectEqual(expected: grabbed, actual: precedence.snapshot, cppID: selID,
                       what: "escape cancels the adapter drag without mutation")

    let keyID = "automation/AutomationEditingTest::selectedRangeDragAndDelete"
    let armed = EditSurfaceState(pointerGestureActive: false, timeSelectionActive: true,
                                 noteSelectionEmpty: true, origin: .timeline, autoRepeat: false,
                                 commandAvailable: true)
    report.expectEqual(expected: EditKeyDecision.execute, actual: EditKeyArbiter.decide(command: .delete, surface: armed),
                       cppID: keyID, what: "the Delete key routes to the active time selection")
    report.expectEqual(expected: EditKeyDecision.decline, actual:
                       EditKeyArbiter.decide(command: nil, surface: armed), cppID: keyID,
                       what: "an unbound key stays host-owned")
    let held = EditSurfaceState(pointerGestureActive: true, timeSelectionActive: true,
                                 noteSelectionEmpty: true, origin: .timeline, autoRepeat: false,
                                 commandAvailable: true)
    report.expectEqual(expected: EditKeyDecision.consume, actual:
                       EditKeyArbiter.decide(command: .delete, surface: held), cppID: keyID,
                       what: "a live gesture swallows the Delete key without acting")
    let quietID = "automation/AutomationEditingTest::cleanup"
    let quiet = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    quiet.activate(quiet.panLane)
    let quietBefore = quiet.snapshot
    quiet.page.cancelSectionInteraction()
    report.expectEqual(expected: quietBefore, actual: quiet.snapshot, cppID: quietID,
                       what: "quiescing an idle page writes nothing")
}

@MainActor
func drawerAutomationBandEscape(_ report: CheckReport, suite: DocumentSession,
                                service: ProjectService) {
    let bandID = "automation/AutomationEditingTest::rightBandPreviewIsolated"
    let band = drawerAutomationAutomationFixture(suite: suite, service: service, pan: [(24, 64)])
    band.activate(band.panLane)
    _ = band.page.pointerPress(x: band.x(24), y: 60, surface: 1, button: AutomationQtButton.right)
    report.expect(!band.page.isPanning, cppID: bandID,
                  message: "a right press starts no pan before moving")
    _ = band.page.pointerMove(x: band.x(120), y: 60, buttons: AutomationQtButton.right)
    report.expect(band.page.bandVisible, cppID: bandID, message: "the right drag arms the band")
    let bandBefore = band.snapshot
    report.expect(band.page.handleEscape(), cppID: bandID, message: "Escape claims the live band")
    report.expect(!band.page.bandVisible, cppID: bandID, message: "Escape drops the band")
    report.expect(!band.page.isPanning, cppID: bandID,
                  message: "no pan owns the band scenario")
    report.expect(!band.page.hasGesture, cppID: bandID,
                  message: "no gesture owns the band scenario")
    report.expectEqual(expected: bandBefore, actual: band.snapshot, cppID: bandID,
                       what: "dropping the band writes nothing")
}
