import Foundation
import PorydawApp
import PorydawCore
import PorydawDocument

// Existing scenarios paired with voice.cpp.
// Entry order remains in VoiceChangesPageChecks.swift.

@MainActor
func drawerVoiceMarkerDragTransactions(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService, programs: [Int]
) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let automation = AutomationPage(baseFontPx: 13)
    automation.attach(viewport: fixture.viewport, palette: GridPalette())
    automation.configureBody(
        width: 400, height: 46, gutter: 56, devicePixelRatio: 1,
        baseFontPx: 13, dragDistance: 10)
    let baseline = fixture.snapshot
    let originalBytes: [UInt8]
    do {
        originalBytes = try fixture.document.captureSave().bytes
    } catch {
        report.fail(drawerVoiceMoveID, "cannot capture drag baseline: \(error)")
        return
    }
    let undoBefore = fixture.document.history.undoIndex

    // Crossing/tied markers can propagate stair placement beyond the moved
    // label. A camera redraw must agree with the incremental drag projection.
    _ = page.pointerPress(
        x: fixture.markerX(48), y: 10, surface: 1,
        button: 1, modifiers: 0)
    for tick in [Tick(120), 180, 0, 48, 96] {
        _ = page.pointerMove(x: fixture.markerX(tick), y: 10, buttons: 1)
        let incremental = page.publishedMarkers
        page.refreshCamera()
        let redrawn = page.publishedMarkers
        report.expectEqual(
            expected: incremental.map(\.identity), actual: redrawn.map(\.identity),
            cppID: drawerVoiceMoveID, what: "drag and redraw preserve tied marker order")
        report.expectEqual(
            expected: incremental.map(\.label), actual: redrawn.map(\.label),
            cppID: drawerVoiceMoveID, what: "drag and redraw agree on label elision")
        for (before, after) in zip(incremental, redrawn) {
            let components: [(String, Double, Double)] = [
                ("x", before.labelX, after.labelX),
                ("y", before.labelY, after.labelY),
                ("width", before.labelWidth, after.labelWidth),
                ("height", before.labelHeight, after.labelHeight),
            ]
            for (component, expected, actual) in components {
                report.expectEqual(
                    expected: expected, actual: actual, cppID: drawerVoiceMoveID,
                    what: "drag and redraw agree on label \(component)")
            }
            report.expectEqual(
                expected: before.offscreen, actual: after.offscreen, cppID: drawerVoiceMoveID,
                what: "drag and redraw agree on offscreen labels")
        }
    }
    page.cancelSectionInteraction()

    // Below the activation distance: a press and a release commit nothing.
    let startX = fixture.markerX(48)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 4, y: 10, buttons: 1)
    report.expect(
        !page.dragActive, cppID: drawerVoiceMoveID,
        message: "a move below the activation distance stays pending")
    _ = page.pointerRelease(x: startX + 4, y: 10, button: 1)
    report.expectEqual(
        expected: baseline, actual: fixture.snapshot, cppID: drawerVoiceMoveID,
        what: "a drag below the activation distance commits nothing")
    report.expectEqual(
        expected: [0, 48, 120], actual: page.markerTicks, cppID: drawerVoiceMoveID,
        what: "the untouched occurrence keeps its tick")

    // An activated drag commits exactly one move at the tick it previewed.
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    report.expect(page.hasGesture, cppID: drawerVoiceMoveID, message: "the press owns a gesture")
    report.expectEqual(
        expected: 48, actual: page.frozenOccurrence?.tick, cppID: drawerVoiceMoveID,
        what: "the frozen occurrence is the pressed marker")
    report.expect(
        page.interactionActive, cppID: drawerVoiceMoveID,
        message: "the live gesture reports an active interaction")
    _ = page.pointerMove(x: startX + 60, y: 10, buttons: 1)
    report.expectEqual(
        expected: 3, actual: page.cursorKind, cppID: drawerVoiceMoveID,
        what: "a horizontal marker drag publishes the horizontal cursor")
    report.expect(
        page.dragActive, cppID: drawerVoiceMoveID,
        message: "the drag activates past its activation distance")
    guard let preview = page.dragPreviewTick else {
        report.fail(drawerVoiceMoveID, "the activated drag published no preview tick")
        return
    }
    report.expect(
        preview != 48, cppID: drawerVoiceMoveID,
        message: "the preview tick drafts away from the frozen tick")
    report.expectEqual(
        expected: baseline, actual: fixture.snapshot, cppID: drawerVoiceMoveID,
        what: "motion is preview only and mutates nothing")
    report.expectEqual(
        expected: preview, actual: page.markerTicks[1], cppID: drawerVoiceMoveID,
        what: "the projection draws the marker at the preview tick")
    _ = page.pointerRelease(x: startX + 60, y: 10, button: 1)
    report.expectEqual(
        expected: 0, actual: page.cursorKind, cppID: drawerVoiceMoveID,
        what: "releasing the voice drag restores the arrow cursor")
    report.expect(
        !automation.bandVisible, cppID: drawerVoiceMoveID,
        message: "the released voice drag leaves the automation band clear")
    report.expect(
        !page.hasGesture && !page.interactionActive, cppID: drawerVoiceMoveID,
        message: "the release ends the gesture and its interaction")
    report.expectEqual(
        expected: preview, actual: fixture.lanePoints()[1].tick, cppID: drawerVoiceMoveID,
        what: "the release commits the preview tick")
    report.expectEqual(
        expected: baseline.revision + 1, actual: fixture.snapshot.revision, cppID: drawerVoiceMoveID,
        what: "the move is one revision")
    report.expect(
        fixture.snapshot.canUndo, cppID: drawerVoiceMoveID,
        message: "the move records one history entry")
    report.expectEqual(
        expected: undoBefore + 1, actual: fixture.document.history.undoIndex,
        cppID: drawerVoiceMoveID, what: "the committed drag advances the undo index by one")
    report.expect(
        VoiceLanePolicy.occurrence(at: 48, in: fixture.lanePoints()) == nil,
        cppID: drawerVoiceMoveID, message: "the source tick no longer holds the occurrence")
    let committedBytes: [UInt8]
    do {
        committedBytes = try fixture.document.captureSave().bytes
    } catch {
        report.fail(drawerVoiceMoveID, "cannot capture committed drag: \(error)")
        return
    }
    let committedRevision = fixture.snapshot.revision

    do {
        _ = try runBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(drawerVoiceMoveID, "undo failed: \(error)")
        return
    }
    report.expectEqual(
        expected: 48, actual: fixture.lanePoints()[1].tick, cppID: drawerVoiceMoveID,
        what: "undo restores the moved occurrence's tick")
    report.expectEqual(
        expected: [0, 48, 120], actual: page.markerTicks, cppID: drawerVoiceMoveID,
        what: "undo rebuilds the projection at the restored tick")
    do {
        let undoneBytes = try fixture.document.captureSave().bytes
        report.expect(
            undoneBytes == originalBytes
                && fixture.document.history.undoIndex == undoBefore, cppID: drawerVoiceMoveID,
            message: "undo restores the drag's bytes and index")
    } catch {
        report.fail(drawerVoiceMoveID, "cannot capture undone drag: \(error)")
        return
    }
    let undoneRevision = fixture.snapshot.revision
    report.expectEqual(
        expected: committedRevision + 1, actual: undoneRevision,
        cppID: drawerVoiceMoveID,
        what: "undo advances the document revision after the drag")
    do {
        _ = try runBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(drawerVoiceMoveID, "redo failed: \(error)")
        return
    }
    report.expectEqual(
        expected: preview, actual: fixture.lanePoints()[1].tick, cppID: drawerVoiceMoveID,
        what: "redo reapplies the move")
    do {
        let redoneBytes = try fixture.document.captureSave().bytes
        report.expect(
            fixture.document.history.undoIndex == undoBefore + 1
                && redoneBytes == committedBytes,
            cppID: drawerVoiceMoveID, message: "redo restores the committed drag")
    } catch {
        report.fail(drawerVoiceMoveID, "cannot capture redone drag: \(error)")
        return
    }
    report.expectEqual(
        expected: undoneRevision + 1, actual: fixture.snapshot.revision,
        cppID: drawerVoiceMoveID,
        what: "redo advances the document revision after the drag")

    // A release back on the frozen tick is a no-op.
    let settled = fixture.snapshot
    let movedX = fixture.markerX(preview)
    _ = page.pointerPress(x: movedX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: movedX + 60, y: 10, buttons: 1)
    _ = page.pointerMove(x: movedX, y: 10, buttons: 1)
    report.expectEqual(
        expected: preview, actual: page.dragPreviewTick, cppID: drawerVoiceMoveID,
        what: "the draft returns to the frozen tick")
    _ = page.pointerRelease(x: movedX, y: 10, button: 1)
    report.expectEqual(
        expected: settled, actual: fixture.snapshot, cppID: drawerVoiceMoveID,
        what: "a release back on the frozen tick commits nothing")

    // A drag whose document moved under it refuses the commit instead of
    // retargeting the occurrence it now finds there.
    _ = page.pointerPress(x: movedX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: movedX + 60, y: 10, buttons: 1)
    let staleDraft = page.dragPreviewTick
    fixture.document.writeLane(
        track: 0, lane: .voice, from: 0, through: 0,
        points: [LaneWrite(tick: 0, value: programs[2])])
    let rewritten = fixture.snapshot
    _ = page.pointerRelease(x: movedX + 60, y: 10, button: 1)
    report.expect(
        staleDraft != nil && staleDraft != preview, cppID: drawerVoiceMoveID,
        message: "the stale drag had drafted another tick before the release")
    report.expectEqual(
        expected: rewritten, actual: fixture.snapshot, cppID: drawerVoiceMoveID,
        what: "a drag whose revision moved under it commits nothing")
    report.expectEqual(
        expected: programs[2],
        actual:
            VoiceLanePolicy.occurrence(at: 0, in: fixture.lanePoints())?.value,
        cppID: drawerVoiceMoveID, what: "the concurrent rewrite is the one that stands")
}

@MainActor
func drawerVoiceCancellationPaths(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService, programs: [Int]
) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let automation = AutomationPage(baseFontPx: 13)
    automation.attach(viewport: fixture.viewport, palette: GridPalette())
    automation.configureBody(
        width: 400, height: 46, gutter: 56, devicePixelRatio: 1,
        baseFontPx: 13, dragDistance: 10)
    let baseline = fixture.snapshot

    // A picker cancelled by the container's own path releases the interaction.
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.cancelSectionInteraction()
    report.expect(
        !page.hasPicker, cppID: drawerVoiceCancellationID,
        message: "the container's cancellation closes the picker")
    report.expect(
        !page.interactionActive, cppID: drawerVoiceCancellationID,
        message: "cancellation releases the follow-scroll gate")
    report.expectEqual(
        expected: baseline, actual: fixture.snapshot, cppID: drawerVoiceCancellationID,
        what: "the cancelled picker wrote nothing")

    let jitterX = fixture.markerX(48)
    _ = page.pointerPress(x: jitterX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: jitterX, y: 22, buttons: 1)
    report.expectEqual(
        expected: 0, actual: page.cursorKind,
        cppID: "automation/AutomationEditingTest::voiceStationaryVerticalJitterAndEmptySpaceDoNotCommit",
        what: "vertical-only marker jitter keeps the arrow cursor")
    _ = page.pointerRelease(x: jitterX, y: 22, button: 1)
    report.expect(
        !automation.bandVisible,
        cppID: "automation/AutomationEditingTest::voiceStationaryVerticalJitterAndEmptySpaceDoNotCommit",
        message: "vertical-only voice jitter leaves the automation band clear")

    // A live drag cancelled mid-motion restores presentation and commits nothing.
    let startX = fixture.markerX(48)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 60, y: 10, buttons: 1)
    report.expect(page.dragActive, cppID: drawerVoiceCancellationID, message: "the drag is live")
    page.cancelSectionInteraction()
    report.expect(
        !automation.bandVisible, cppID: drawerVoiceCancellationID,
        message: "cancelling the voice drag leaves the automation band clear")
    report.expectEqual(
        expected: 0, actual: page.cursorKind, cppID: drawerVoiceCancellationID,
        what: "cancelling the voice drag restores the arrow cursor")
    report.expect(
        !page.hasGesture && !page.interactionActive, cppID: drawerVoiceCancellationID,
        message: "cancellation ends the live drag")
    report.expectEqual(
        expected: [0, 48, 120], actual: page.markerTicks, cppID: drawerVoiceCancellationID,
        what: "the cancelled drag restores the projection from the document")
    report.expectEqual(
        expected: baseline, actual: fixture.snapshot, cppID: drawerVoiceCancellationID,
        what: "the cancelled drag commits nothing")

    // The canvas keeps drawing after a cancellation.
    fixture.viewport.mutateCamera { $0.setHScroll($0.snapshot.scrollX + 20) }
    report.expectEqual(
        expected: 3, actual: page.publishedMarkers.count, cppID: drawerVoiceCancellationID,
        what: "the projection survives the cancellation")

    // A track switch invalidates an open modal instead of retargeting it.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expect(page.hasMenu, cppID: drawerVoiceCancellationID, message: "the menu is open")
    fixture.session.selectedTrack = 1
    page.refreshFromDocument()
    report.expect(
        !page.hasMenu, cppID: drawerVoiceCancellationID,
        message: "a track switch cancels the captured menu")
    report.expect(
        !page.activateMenuAction(actionId: VoiceChangesPagePolicy.deleteMarkerAction),
        cppID: drawerVoiceCancellationID, message: "the cancelled menu fires no row")
    report.expectEqual(
        expected: baseline, actual: fixture.snapshot, cppID: drawerVoiceCancellationID,
        what: "the track switch wrote nothing")
    report.expectEqual(
        expected: [0], actual: page.markerTicks, cppID: drawerVoiceCancellationID,
        what: "the projection re-derives for the new track")
    fixture.session.selectedTrack = 0
    page.refreshFromDocument()

    // A hide cancels a live gesture through the same synchronous path.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 30, y: 10, buttons: 1)
    page.cancelSectionInteraction()
    report.expect(
        !page.dragActive, cppID: drawerVoiceCancellationID,
        message: "a hide cancels the in-flight drag")
    report.expectEqual(
        expected: 48, actual: page.markerTicks[1], cppID: drawerVoiceCancellationID,
        what: "the hidden page's projection is back on the document")

    // Detach ends everything and publishes no marker.
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.detach()
    report.expect(
        !page.hasPicker && !page.hasMenu && !page.hasGesture, cppID: drawerVoiceCancellationID,
        message: "detach cancels every interaction")
    report.expectEqual(
        expected: 0, actual: page.markerIdentities.count, cppID: drawerVoiceCancellationID,
        what: "detach publishes no marker")
    report.expectEqual(
        expected: 0, actual: velocityDisplayRects(page.displayList(list: 0))?.count ?? -1,
        cppID: drawerVoiceCancellationID,
        what: "detach publishes no held span")
    report.expectEqual(
        expected: baseline, actual: fixture.snapshot, cppID: drawerVoiceCancellationID,
        what: "detach wrote nothing")

    // The gutter never edits and opens no modal.
    let gutterFixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    report.expect(
        !gutterFixture.page.pointerPress(
            x: 10, y: 10, surface: 0, button: 1,
            modifiers: 0),
        cppID: drawerVoiceCancellationID,
        message: "a gutter press is not consumed by the page")
    report.expect(
        !gutterFixture.page.hasGesture, cppID: drawerVoiceCancellationID,
        message: "a gutter press starts no gesture")
    report.expect(
        !gutterFixture.page.hasPicker, cppID: drawerVoiceCancellationID,
        message: "a gutter press opens no picker")
    report.expect(
        !gutterFixture.page.interactionActive, cppID: drawerVoiceCancellationID,
        message: "a gutter press reports no interaction")
    drawerVoiceScopedWorkspaceEdits(report, suite: suite, service: service, programs: programs)
}

@MainActor
func drawerVoiceAltFineClockLattice(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService, programs: [Int]
) {
    // `SongDocument::ticksPerClock`: one clock is `division / (24 * (extended ? 2 : 1))`
    // ticks, floored at one.
    report.expectEqual(
        expected: 1, actual: TimelineSnapPolicy.clockTicks(division: 24, extendedClocks: false),
        cppID: drawerVoiceFineSnapID,
        what: "a 24-tick division names one tick per clock")
    report.expectEqual(
        expected: 4, actual: TimelineSnapPolicy.clockTicks(division: 96, extendedClocks: false),
        cppID: drawerVoiceFineSnapID,
        what: "a 96-tick division names four ticks per clock")
    report.expectEqual(
        expected: 2, actual: TimelineSnapPolicy.clockTicks(division: 96, extendedClocks: true),
        cppID: drawerVoiceFineSnapID,
        what: "extended clocks halve the ticks per clock")
    report.expectEqual(
        expected: 1, actual: TimelineSnapPolicy.clockTicks(division: 1, extendedClocks: false),
        cppID: drawerVoiceFineSnapID, what: "the clock stride never falls below one tick")

    // `Grid::snapTick(tick, fine: true)`: the absolute clock lattice, rounded
    // half-up, clamped to the song's tick domain.
    report.expectEqual(
        expected: 4, actual: TimelineSnapPolicy.fineSnap(5.9, clockTicks: 4), cppID: drawerVoiceFineSnapID,
        what: "a position inside a clock cell snaps to its floor")
    report.expectEqual(
        expected: 8, actual: TimelineSnapPolicy.fineSnap(6, clockTicks: 4), cppID: drawerVoiceFineSnapID,
        what: "an exact tie rounds up, as the legacy lattice does")
    report.expectEqual(
        expected: 8, actual: TimelineSnapPolicy.fineSnap(6.1, clockTicks: 4), cppID: drawerVoiceFineSnapID,
        what: "a position past the midpoint snaps up")
    report.expectEqual(
        expected: 0, actual: TimelineSnapPolicy.fineSnap(-3, clockTicks: 4), cppID: drawerVoiceFineSnapID,
        what: "the lattice is anchored at zero")
    report.expectEqual(
        expected: TimeDefaults.maxTick,
        actual:
            TimelineSnapPolicy.fineSnap(Double(TimeDefaults.maxTick), clockTicks: 4),
        cppID: drawerVoiceFineSnapID, what: "the lattice clamps to the song's tick domain")

    // The page's own drag: with the alt modifier the preview snaps on the clock
    // lattice of the document in front of it, not on the editing lattice.
    let fixture = drawerVoiceVoiceChangesFixture(
        suite: suite, service: service, programs: programs,
        division: 96)
    let automation = AutomationPage(baseFontPx: 13)
    automation.attach(viewport: fixture.viewport, palette: GridPalette())
    automation.configureBody(
        width: 400, height: 46, gutter: 56, devicePixelRatio: 1,
        baseFontPx: 13, dragDistance: 10)
    let revisionBefore = fixture.snapshot.revision
    let historyCountBefore = fixture.document.history.undoCount
    let historyIndexBefore = fixture.document.history.undoIndex
    let page = fixture.page
    let clock = TimelineSnapPolicy.clockTicks(
        division: fixture.document.ticksPerBeat,
        extendedClocks: fixture.document.state.config.extendedClocks)
    report.expect(
        clock >= 1, cppID: drawerVoiceFineSnapID,
        message: "the fixture document publishes its own clock stride")
    let dragged = VoiceOccurrence(fixture.lanePoints()[1])
    let startX = fixture.markerX(dragged.tick)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    let altX = startX + 60
    _ = page.pointerMove(x: altX, y: 10, buttons: 1, modifiers: VoiceModifier.alt)
    let raw = fixture.viewport.camera.tickAtContentX(altX)
    report.expectEqual(
        expected: TimelineSnapPolicy.fineSnap(raw, clockTicks: clock), actual: page.dragPreviewTick,
        cppID: drawerVoiceFineSnapID,
        what: "the alt drag previews the legacy clock lattice")
    report.expect(
        (page.dragPreviewTick ?? 1) % Tick(clock) == 0, cppID: drawerVoiceFineSnapID,
        message: "the alt preview lands on the clock lattice itself")
    _ = page.pointerRelease(x: altX, y: 10, button: 1)
    report.expectEqual(
        expected: revisionBefore + 1, actual: fixture.snapshot.revision,
        cppID: drawerVoiceFineSnapID, what: "the Alt drag advances one revision")
    report.expectEqual(
        expected: historyCountBefore + 1, actual: fixture.document.history.undoCount,
        cppID: drawerVoiceFineSnapID, what: "the Alt drag records one undo entry")
    report.expectEqual(
        expected: historyIndexBefore + 1, actual: fixture.document.history.undoIndex,
        cppID: drawerVoiceFineSnapID, what: "the Alt drag advances one undo position")
    report.expect(
        !automation.bandVisible, cppID: drawerVoiceFineSnapID,
        message: "the released Alt drag leaves the automation band clear")
    report.expectEqual(
        expected: TimelineSnapPolicy.fineSnap(raw, clockTicks: clock),
        actual:
            fixture.lanePoints().first { $0.value == dragged.value }?.tick,
        cppID: drawerVoiceFineSnapID,
        what: "the released alt drag commits the clock-lattice tick")
}

@MainActor
func drawerVoiceCollisionDragOutcome(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService, programs: [Int]
) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let automation = AutomationPage(baseFontPx: 13)
    automation.attach(viewport: fixture.viewport, palette: GridPalette())
    automation.configureBody(
        width: 400, height: 46, gutter: 56, devicePixelRatio: 1,
        baseFontPx: 13, dragDistance: 10)
    let baseline = fixture.snapshot
    let moving = VoiceOccurrence(fixture.lanePoints()[1])
    let occupied = VoiceOccurrence(fixture.lanePoints()[2])
    let startX = fixture.markerX(moving.tick)

    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: fixture.markerX(occupied.tick), y: 10, buttons: 1)
    report.expectEqual(
        expected: occupied.tick, actual: page.dragPreviewTick, cppID: drawerVoiceCollisionID,
        what: "the dragged preview lands on the occupied tick")
    _ = page.pointerRelease(x: fixture.markerX(occupied.tick), y: 10, button: 1)
    report.expectEqual(
        expected: 0, actual: page.cursorKind, cppID: drawerVoiceCollisionID,
        what: "the collision release restores the arrow cursor")
    report.expect(
        !automation.bandVisible, cppID: drawerVoiceCollisionID,
        message: "the collision release leaves the automation band clear")

    let points = fixture.lanePoints()
    report.expectEqual(
        expected: 2, actual: points.count, cppID: drawerVoiceCollisionID,
        what: "a move onto an occupied tick leaves one occurrence there")
    report.expectEqual(
        expected: moving.value,
        actual:
            VoiceLanePolicy.occurrence(at: occupied.tick, in: points)?.value,
        cppID: drawerVoiceCollisionID, what: "the moved occurrence wins the destination")
    report.expect(
        VoiceLanePolicy.occurrence(at: moving.tick, in: points) == nil,
        cppID: drawerVoiceCollisionID, message: "the source tick no longer holds a change")
    report.expectEqual(
        expected: baseline.revision + 1, actual: fixture.snapshot.revision, cppID: drawerVoiceCollisionID,
        what: "the collision is one revision")
    report.expect(
        fixture.snapshot.canUndo && !baseline.canUndo, cppID: drawerVoiceCollisionID,
        message: "the collision records exactly one history entry")

    // One history entry, both sides restored: an unintended second entry would
    // leave one of the two occurrences behind.
    do {
        _ = try runBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(drawerVoiceCollisionID, "undo failed: \(error)")
        return
    }
    let restored = fixture.lanePoints()
    report.expectEqual(
        expected: 3, actual: restored.count, cppID: drawerVoiceCollisionID,
        what: "a single undo restores both occurrences")
    report.expectEqual(
        expected: programs[1], actual: VoiceLanePolicy.occurrence(at: 48, in: restored)?.value,
        cppID: drawerVoiceCollisionID, what: "the moved occurrence is back at its tick")
    report.expectEqual(
        expected: programs[2],
        actual:
            VoiceLanePolicy.occurrence(at: occupied.tick, in: restored)?.value,
        cppID: drawerVoiceCollisionID, what: "the displaced occurrence is back too")
}

@MainActor
private func drawerVoiceScopedWorkspaceEdits(
    _ report: CheckReport, suite: DocumentSession,
    service: ProjectService, programs: [Int]
) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    fixture.document.writeLane(
        track: 0, lane: .controller(7), from: 36, through: 36,
        points: [LaneWrite(tick: 36, value: 80)])
    let audio: NativeAudio
    do {
        audio = try runBlocking { try await NativeAudio() }
    } catch {
        report.fail(drawerVoiceCancellationID, "scoped workspace edits cannot create audio: \(error)")
        return
    }
    let presenters = WorkspacePresenterFixture(
        viewport: fixture.viewport, audio: audio,
        callbacks: DocumentWorkspace.Callbacks(
            changeTrackVoiceRequested: { _ in }, revealTrackVoiceRequested: { _ in },
            gridCommandAvailabilityChanged: {}, sessionStateChanged: {},
            publicationFailed: { error in
                report.fail(drawerVoiceCancellationID, "scoped workspace playback publication failed: \(error)")
            }, timeSignaturePromptInvalidated: { _, _ in }))
    let workspace = presenters.workspace
    defer {
        workspace.teardown()
        withExtendedLifetime((audio, presenters)) {}
    }
    workspace.activate()
    presenters.eventList.setVisible(visible: true)
    let page = workspace.voiceChangesPage
    let automation = workspace.automationPage
    page.configureBody(
        width: 400, height: 46, gutter: 56, devicePixelRatio: 1,
        baseFontPx: 13, dragDistance: 10)
    automation.configureBody(
        width: 400, height: 120, gutter: 56, devicePixelRatio: 1,
        baseFontPx: 13, dragDistance: 10)
    workspace.velocityPage.configureBody(
        width: 400, height: 120, rulerWidth: 56, devicePixelRatio: 1,
        baseFontPx: 13, dragDistance: 10)
    let lane = AutomationParameter.controlChange(track: 0, controller: 7)
    _ = automation.activateParameter(lane)
    guard let primary = fixture.document.notes(in: 0).first,
        let secondary = fixture.document.notes(in: 1).first,
        let marker = page.publishedMarkers.first(where: { $0.tick == 48 }),
        let oldPoint = fixture.session.projectionCache.lanePoints(track: 0, lane: .voice)
            .first(where: { $0.tick == 48 })
    else {
        report.fail(drawerVoiceCancellationID, "the workspace exposes its notes and program marker")
        return
    }
    let staticBytes = page.displayList(list: 0)
    report.expect(
        page.pointerDoubleClick(x: fixture.markerX(48), y: 10) && page.pickerOpen,
        cppID: drawerVoiceCancellationID, message: "the program marker opens a real captured picker")
    fixture.document.moveNotes([primary.id], byTicks: 60, byKeys: 0)
    report.expect(
        !page.pickerOpen && !page.hasPicker && !page.interactionActive
            && page.displayList(list: 0) == staticBytes
            && page.publishedMarkers.first(where: { $0.tick == 48 }) === marker,
        cppID: drawerVoiceCancellationID,
        message: "a note crossing cancels the visible picker while retaining voice marker geometry")
    guard
        let point = fixture.session.projectionCache.lanePoints(track: 0, lane: .voice)
            .first(where: { $0.tick == 48 })
    else {
        report.fail(drawerVoiceCancellationID, "the program occurrence survives the note crossing")
        return
    }
    _ = page.pointerMove(x: fixture.markerX(48), y: 10, buttons: 0)
    report.expect(
        point.eventIndex != oldPoint.eventIndex && marker.identity == VoiceOccurrence(point).text
            && marker.hovered,
        cppID: drawerVoiceCancellationID,
        message: "rebased marker identity agrees with fresh hit-testing and hover after the note crossing")
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 1, modifiers: 0)
    report.expectEqual(
        expected: VoiceOccurrence(point), actual: page.frozenOccurrence, cppID: drawerVoiceCancellationID,
        what: "a fresh press captures the shifted program event, not its former raw offset")
    _ = page.pointerMove(x: fixture.markerX(72), y: 10, buttons: 1)
    report.expect(page.dragActive, cppID: drawerVoiceCancellationID, message: "the fresh voice drag previews")
    fixture.document.moveNotes([secondary.id], byTicks: 0, byKeys: 1)
    let afterExternalNote = fixture.snapshot
    report.expect(
        !page.hasGesture && !page.previewVisible && page.cursorKind == 0
            && page.markerTicks == [0, 48, 120],
        cppID: drawerVoiceCancellationID,
        message: "an unrelated chunk note edit immediately cancels the visible voice drag and preview")
    _ = page.pointerRelease(x: fixture.markerX(72), y: 10, button: 1)
    report.expectEqual(
        expected: afterExternalNote, actual: fixture.snapshot, cppID: drawerVoiceCancellationID,
        what: "the cancelled voice drag cannot write on stale release")
    _ = page.pointerDoubleClick(x: fixture.markerX(48), y: 10)
    page.setPickerFilter(text: String(format: "%03d", programs[2]))
    report.expect(
        page.acceptPicker()
            && fixture.document.lanePoints(track: 0, lane: .voice).first(where: { $0.tick == 48 })?.value
                == programs[2]
            && fixture.document.note(primary.id)?.tick == 60
            && fixture.document.note(primary.id)?.pitch == primary.pitch,
        cppID: drawerVoiceCancellationID,
        message: "a fresh picker edits the correct program after note movement, leaving the note intact")

    let automationBytes = automation.displayList(list: 1)
    report.expect(
        automation.openPrompt(tick: 36, value: 80) && automation.promptOpen,
        cppID: drawerVoiceCancellationID, message: "the automation node opens its captured value prompt")
    fixture.document.moveNotes([secondary.id], byTicks: 0, byKeys: 1)
    let afterPromptCancellation = fixture.snapshot
    report.expect(
        !automation.promptOpen && !automation.hasPrompt && !automation.interactionActive
            && automation.displayList(list: 1) == automationBytes
            && !automation.acceptPrompt(displayedValue: 90)
            && fixture.snapshot == afterPromptCancellation,
        cppID: drawerVoiceCancellationID,
        message: "an unrelated note revision visibly cancels the automation prompt without rebuilding its curve")
    report.expect(
        automation.openParameterMenu(index: automation.catalogIndex(of: lane), x: 0, y: 0)
            && automation.menuOpen,
        cppID: drawerVoiceCancellationID, message: "the automation lane opens a captured menu")
    fixture.document.moveNotes([secondary.id], byTicks: 0, byKeys: 1)
    report.expect(
        !automation.menuOpen && !automation.hasMenu && !automation.interactionActive,
        cppID: drawerVoiceCancellationID, message: "an unrelated note revision immediately closes automation menu rows")
    _ = automation.pointerPress(x: fixture.markerX(24), y: 10, surface: 1, button: 2)
    _ = automation.pointerMove(x: fixture.markerX(120), y: 10, buttons: 2)
    report.expect(
        automation.hasBand && automation.bandVisible,
        cppID: drawerVoiceCancellationID, message: "the automation range band is visibly active before revision")
    fixture.document.moveNotes([secondary.id], byTicks: 0, byKeys: 1)
    let afterBandCancellation = fixture.snapshot
    report.expect(
        !automation.hasBand && !automation.bandVisible && !automation.interactionActive,
        cppID: drawerVoiceCancellationID,
        message: "an unrelated note revision synchronously hides the active range band")
    _ = automation.pointerRelease(x: fixture.markerX(120), y: 10, button: 2)
    report.expectEqual(
        expected: afterBandCancellation, actual: fixture.snapshot, cppID: drawerVoiceCancellationID,
        what: "the cancelled range release cannot write")
    guard let node = automation.publishedNodes.first(where: { $0.tick == 36 }) else {
        report.fail(drawerVoiceCancellationID, "the automation node survives scoped edits")
        return
    }
    _ = automation.pointerPress(x: fixture.markerX(36), y: node.y, surface: 1, button: 1)
    _ = automation.pointerMove(x: fixture.markerX(36), y: node.y + 20, buttons: 1)
    report.expect(
        automation.hasGesture && !automation.previewPoints.isEmpty,
        cppID: drawerVoiceCancellationID, message: "the automation node drag has a visible draft")
    fixture.document.moveNotes([secondary.id], byTicks: 0, byKeys: 1)
    report.expect(
        !automation.hasGesture && automation.previewPoints.isEmpty && automation.previewNodes.count == 0
            && automation.cursorKind == 0 && !automation.interactionActive,
        cppID: drawerVoiceCancellationID, message: "an unrelated note revision visibly cancels automation drag geometry"
    )
    report.expect(
        automation.openPrompt(tick: 36, value: 80) && automation.acceptPrompt(displayedValue: 90)
            && fixture.document.lanePoints(track: 0, lane: .controller(7)).first?.value == 90
            && fixture.document.note(primary.id)?.tick == 60
            && fixture.document.note(primary.id)?.velocity == primary.velocity,
        cppID: drawerVoiceCancellationID,
        message:
            "a fresh automation edit after note crossing resolves current raw offsets and changes only its controller")
    func expectMovementAligned(tick: Tick, pitch: UInt8, message: String) {
        struct RollNote: Decodable {
            let id: UInt64
            let tick: Tick
            let pitch: UInt8
        }
        let rows: [RollNote]
        do {
            rows = try JSONDecoder().decode(
                [RollNote].self, from: Data(workspace.grid.fetchNoteSummary().utf8))
        } catch {
            report.fail(drawerVoiceCancellationID, "the roll note probe cannot be decoded: \(error)")
            return
        }
        let roll = rows.first { $0.id == primary.id.rawValue }
        let velocity = workspace.velocityPage.publishedHandlesSnapshot.first {
            $0.noteIdText == String(primary.id.rawValue)
        }
        let event = presenters.eventList.model.chunk.events.first {
            $0.noteID == primary.id && $0.typeNibble == 0x9
        }
        report.expect(
            roll?.tick == tick && roll?.pitch == pitch && velocity?.tick == Double(tick)
                && velocity?.value == Int(primary.velocity) && event?.tick == tick
                && event?.payload == .channel(status: 0x90, data0: pitch, data1: primary.velocity),
            cppID: drawerVoiceCancellationID, message: message)
    }
    fixture.document.nudgeNotes([primary.id], byTicks: 12, byKeys: 1)
    fixture.document.nudgeNotes([primary.id], byTicks: 12, byKeys: 1)
    expectMovementAligned(
        tick: 84, pitch: primary.pitch + 2,
        message: "merged note nudges publish aligned roll, velocity and event-list data")
    report.expect(
        fixture.document.history.undoDocument(), cppID: drawerVoiceCancellationID,
        message: "the merged workspace movement undoes in one step")
    expectMovementAligned(
        tick: 60, pitch: primary.pitch,
        message: "merged movement undo restores the roll, velocity and raw-event presentation")
    report.expect(
        fixture.document.history.redoDocument(), cppID: drawerVoiceCancellationID,
        message: "the merged workspace movement redoes in one step")
    expectMovementAligned(
        tick: 84, pitch: primary.pitch + 2,
        message: "merged movement redo restores aligned roll, velocity and event-list data")
    let currentRow = presenters.eventList.rowHandle(row: 0)
    automation.selectRange(from: 24, to: 72, lanes: [lane])
    report.expect(
        fixture.session.timeSelection?.lanes == [lane] && automation.selectedParameters == [lane]
            && workspace.velocityPage.selectedCount == 0
            && presenters.eventList.rowHandle(row: 0) === currentRow,
        cppID: drawerVoiceCancellationID,
        message: "lane time selection updates the automation scope without selecting notes or replacing event-list rows"
    )
    fixture.session.selectPrimaryTrack(1)
    report.expect(
        page.markerTicks == [0] && workspace.velocityPage.publishedNoteCount == 1
            && automation.activeTrackIndex == 1 && presenters.eventList.chunkIndex == 2,
        cppID: drawerVoiceCancellationID,
        message: "primary-track changes still align all scoped pages and the event list")
}
