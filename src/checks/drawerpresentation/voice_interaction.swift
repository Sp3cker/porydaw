import Foundation
@testable import PorydawApp
import PorydawCore

// Existing scenarios paired with voice.cpp.
// Entry order remains in VoiceChangesPageChecks.swift.

@MainActor
func drawerVoiceMarkerDragTransactions(_ report: CheckReport, suite: DocumentSession,
                                    service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot

    // Crossing/tied markers can propagate stair placement beyond the moved
    // label. A camera redraw must agree with the incremental drag projection.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1,
                          button: 1, modifiers: 0)
    for tick in [Tick(120), 180, 0, 48, 96] {
        _ = page.pointerMove(x: fixture.markerX(tick), y: 10, buttons: 1)
        let incremental = page.publishedMarkers
        page.refreshCamera()
        let redrawn = page.publishedMarkers
        report.expectEqual(incremental.map(\.identity), redrawn.map(\.identity),
                           cppID: drawerVoiceMoveID, what: "drag and redraw preserve tied marker order")
        report.expectEqual(incremental.map(\.label), redrawn.map(\.label),
                           cppID: drawerVoiceMoveID, what: "drag and redraw agree on label elision")
        for (before, after) in zip(incremental, redrawn) {
            for component in ["x", "y", "width", "height"] {
                report.expectEqual(before.labelRect[component] as? Double,
                                   after.labelRect[component] as? Double, cppID: drawerVoiceMoveID,
                                   what: "drag and redraw agree on label \(component)")
            }
            report.expectEqual(before.offscreen, after.offscreen, cppID: drawerVoiceMoveID,
                               what: "drag and redraw agree on offscreen labels")
        }
    }
    page.cancelSectionInteraction()

    // Below the activation distance: a press and a release commit nothing.
    let startX = fixture.markerX(48)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 4, y: 10, buttons: 1)
    report.expect(!page.dragActive, cppID: drawerVoiceMoveID,
                  message: "a move below the activation distance stays pending")
    _ = page.pointerRelease(x: startX + 4, y: 10, button: 1)
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceMoveID,
                       what: "a drag below the activation distance commits nothing")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: drawerVoiceMoveID,
                       what: "the untouched occurrence keeps its tick")

    // An activated drag commits exactly one move at the tick it previewed.
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    report.expect(page.hasGesture, cppID: drawerVoiceMoveID, message: "the press owns a gesture")
    report.expectEqual(48, page.frozenOccurrence?.tick, cppID: drawerVoiceMoveID,
                       what: "the frozen occurrence is the pressed marker")
    report.expect(page.interactionActive, cppID: drawerVoiceMoveID,
                  message: "the live gesture reports an active interaction")
    _ = page.pointerMove(x: startX + 60, y: 10, buttons: 1)
    report.expect(page.dragActive, cppID: drawerVoiceMoveID,
                  message: "the drag activates past its activation distance")
    guard let preview = page.dragPreviewTick else {
        report.fail(drawerVoiceMoveID, "the activated drag published no preview tick")
        return
    }
    report.expect(preview != 48, cppID: drawerVoiceMoveID,
                  message: "the preview tick drafts away from the frozen tick")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceMoveID,
                       what: "motion is preview only and mutates nothing")
    report.expectEqual(preview, page.markerTicks[1], cppID: drawerVoiceMoveID,
                       what: "the projection draws the marker at the preview tick")
    _ = page.pointerRelease(x: startX + 60, y: 10, button: 1)
    report.expect(!page.hasGesture && !page.interactionActive, cppID: drawerVoiceMoveID,
                  message: "the release ends the gesture and its interaction")
    report.expectEqual(preview, fixture.lanePoints()[1].tick, cppID: drawerVoiceMoveID,
                       what: "the release commits the preview tick")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: drawerVoiceMoveID,
                       what: "the move is one revision")
    report.expect(fixture.snapshot.canUndo, cppID: drawerVoiceMoveID,
                  message: "the move records one history entry")
    report.expect(VoiceLanePolicy.occurrence(at: 48, in: fixture.lanePoints()) == nil,
                  cppID: drawerVoiceMoveID, message: "the source tick no longer holds the occurrence")

    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(drawerVoiceMoveID, "undo failed: \(error)")
        return
    }
    report.expectEqual(48, fixture.lanePoints()[1].tick, cppID: drawerVoiceMoveID,
                       what: "undo restores the moved occurrence's tick")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: drawerVoiceMoveID,
                       what: "undo rebuilds the projection at the restored tick")
    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.redo() }
    } catch {
        report.fail(drawerVoiceMoveID, "redo failed: \(error)")
        return
    }
    report.expectEqual(preview, fixture.lanePoints()[1].tick, cppID: drawerVoiceMoveID,
                       what: "redo reapplies the move")

    // A release back on the frozen tick is a no-op.
    let settled = fixture.snapshot
    let movedX = fixture.markerX(preview)
    _ = page.pointerPress(x: movedX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: movedX + 60, y: 10, buttons: 1)
    _ = page.pointerMove(x: movedX, y: 10, buttons: 1)
    report.expectEqual(preview, page.dragPreviewTick, cppID: drawerVoiceMoveID,
                       what: "the draft returns to the frozen tick")
    _ = page.pointerRelease(x: movedX, y: 10, button: 1)
    report.expectEqual(settled, fixture.snapshot, cppID: drawerVoiceMoveID,
                       what: "a release back on the frozen tick commits nothing")

    // A drag whose document moved under it refuses the commit instead of
    // retargeting the occurrence it now finds there.
    _ = page.pointerPress(x: movedX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: movedX + 60, y: 10, buttons: 1)
    let staleDraft = page.dragPreviewTick
    fixture.document.writeLane(track: 0, lane: .voice, from: 0, through: 0,
                               points: [LaneWrite(tick: 0, value: programs[2])])
    let rewritten = fixture.snapshot
    _ = page.pointerRelease(x: movedX + 60, y: 10, button: 1)
    report.expect(staleDraft != nil && staleDraft != preview, cppID: drawerVoiceMoveID,
                  message: "the stale drag had drafted another tick before the release")
    report.expectEqual(rewritten, fixture.snapshot, cppID: drawerVoiceMoveID,
                       what: "a drag whose revision moved under it commits nothing")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: 0, in: fixture.lanePoints())?.value,
                       cppID: drawerVoiceMoveID, what: "the concurrent rewrite is the one that stands")
}

@MainActor
func drawerVoiceCancellationPaths(_ report: CheckReport, suite: DocumentSession,
                               service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot

    // A picker cancelled by the container's own path releases the interaction.
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.cancelSectionInteraction()
    report.expect(!page.hasPicker, cppID: drawerVoiceCancellationID,
                  message: "the container's cancellation closes the picker")
    report.expect(!page.interactionActive, cppID: drawerVoiceCancellationID,
                  message: "cancellation releases the follow-scroll gate")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceCancellationID,
                       what: "the cancelled picker wrote nothing")

    // A live drag cancelled mid-motion restores presentation and commits nothing.
    let startX = fixture.markerX(48)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 60, y: 10, buttons: 1)
    report.expect(page.dragActive, cppID: drawerVoiceCancellationID, message: "the drag is live")
    page.cancelSectionInteraction()
    report.expect(!page.hasGesture && !page.interactionActive, cppID: drawerVoiceCancellationID,
                  message: "cancellation ends the live drag")
    report.expectEqual([0, 48, 120], page.markerTicks, cppID: drawerVoiceCancellationID,
                       what: "the cancelled drag restores the projection from the document")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceCancellationID,
                       what: "the cancelled drag commits nothing")

    // The canvas keeps drawing after a cancellation.
    fixture.session.mutateCamera { $0.setHScroll($0.snapshot.scrollX + 20) }
    report.expectEqual(3, page.publishedMarkers.count, cppID: drawerVoiceCancellationID,
                       what: "the projection survives the cancellation")

    // A track switch invalidates an open modal instead of retargeting it.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 2, modifiers: 0)
    report.expect(page.hasMenu, cppID: drawerVoiceCancellationID, message: "the menu is open")
    fixture.session.selectedTrack = 1
    page.refreshFromDocument()
    report.expect(!page.hasMenu, cppID: drawerVoiceCancellationID,
                  message: "a track switch cancels the captured menu")
    report.expect(!page.activateMenuAction(actionId: VoiceChangesPagePolicy.deleteMarkerAction),
                  cppID: drawerVoiceCancellationID, message: "the cancelled menu fires no row")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceCancellationID,
                       what: "the track switch wrote nothing")
    report.expectEqual([0], page.markerTicks, cppID: drawerVoiceCancellationID,
                       what: "the projection re-derives for the new track")
    fixture.session.selectedTrack = 0
    page.refreshFromDocument()

    // A hide cancels a live gesture through the same synchronous path.
    _ = page.pointerPress(x: fixture.markerX(48), y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: startX + 30, y: 10, buttons: 1)
    page.cancelSectionInteraction()
    report.expect(!page.dragActive, cppID: drawerVoiceCancellationID,
                  message: "a hide cancels the in-flight drag")
    report.expectEqual(48, page.markerTicks[1], cppID: drawerVoiceCancellationID,
                       what: "the hidden page's projection is back on the document")

    // Detach ends everything and publishes no marker.
    _ = page.pointerDoubleClick(x: fixture.markerX(96), y: 10)
    page.detach()
    report.expect(!page.hasPicker && !page.hasMenu && !page.hasGesture, cppID: drawerVoiceCancellationID,
                  message: "detach cancels every interaction")
    report.expectEqual(0, page.markerIdentities.count, cppID: drawerVoiceCancellationID,
                       what: "detach publishes no marker")
    report.expectEqual(0, page.heldSpans.count, cppID: drawerVoiceCancellationID,
                       what: "detach publishes no held span")
    report.expectEqual(baseline, fixture.snapshot, cppID: drawerVoiceCancellationID,
                       what: "detach wrote nothing")

    // The gutter never edits and opens no modal.
    let gutterFixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    report.expect(!gutterFixture.page.pointerPress(x: 10, y: 10, surface: 0, button: 1,
                                                   modifiers: 0),
                  cppID: drawerVoiceCancellationID,
                  message: "a gutter press is not consumed by the page")
    report.expect(!gutterFixture.page.hasGesture, cppID: drawerVoiceCancellationID,
                  message: "a gutter press starts no gesture")
    report.expect(!gutterFixture.page.hasPicker, cppID: drawerVoiceCancellationID,
                  message: "a gutter press opens no picker")
    report.expect(!gutterFixture.page.interactionActive, cppID: drawerVoiceCancellationID,
                  message: "a gutter press reports no interaction")
}

@MainActor
func drawerVoiceAltFineClockLattice(_ report: CheckReport, suite: DocumentSession,
                                 service: ProjectService, programs: [Int]) {
    // `SongDocument::ticksPerClock`: one clock is `division / (24 * (extended ? 2 : 1))`
    // ticks, floored at one.
    report.expectEqual(1, TimelineSnapPolicy.clockTicks(division: 24, extendedClocks: false),
                       cppID: drawerVoiceFineSnapID,
                       what: "a 24-tick division names one tick per clock")
    report.expectEqual(4, TimelineSnapPolicy.clockTicks(division: 96, extendedClocks: false),
                       cppID: drawerVoiceFineSnapID,
                       what: "a 96-tick division names four ticks per clock")
    report.expectEqual(2, TimelineSnapPolicy.clockTicks(division: 96, extendedClocks: true),
                       cppID: drawerVoiceFineSnapID,
                       what: "extended clocks halve the ticks per clock")
    report.expectEqual(1, TimelineSnapPolicy.clockTicks(division: 1, extendedClocks: false),
                       cppID: drawerVoiceFineSnapID, what: "the clock stride never falls below one tick")

    // `Grid::snapTick(tick, fine: true)`: the absolute clock lattice, rounded
    // half-up, clamped to the song's tick domain.
    report.expectEqual(4, TimelineSnapPolicy.fineSnap(5.9, clockTicks: 4), cppID: drawerVoiceFineSnapID,
                       what: "a position inside a clock cell snaps to its floor")
    report.expectEqual(8, TimelineSnapPolicy.fineSnap(6, clockTicks: 4), cppID: drawerVoiceFineSnapID,
                       what: "an exact tie rounds up, as the legacy lattice does")
    report.expectEqual(8, TimelineSnapPolicy.fineSnap(6.1, clockTicks: 4), cppID: drawerVoiceFineSnapID,
                       what: "a position past the midpoint snaps up")
    report.expectEqual(0, TimelineSnapPolicy.fineSnap(-3, clockTicks: 4), cppID: drawerVoiceFineSnapID,
                       what: "the lattice is anchored at zero")
    report.expectEqual(TimeDefaults.maxTick,
                       TimelineSnapPolicy.fineSnap(Double(TimeDefaults.maxTick), clockTicks: 4),
                       cppID: drawerVoiceFineSnapID, what: "the lattice clamps to the song's tick domain")

    // The page's own drag: with the alt modifier the preview snaps on the clock
    // lattice of the document in front of it, not on the editing lattice.
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs,
                                      division: 96)
    let page = fixture.page
    let clock = TimelineSnapPolicy.clockTicks(
        division: fixture.document.ticksPerBeat,
        extendedClocks: fixture.document.state.config.extendedClocks)
    report.expect(clock >= 1, cppID: drawerVoiceFineSnapID,
                  message: "the fixture document publishes its own clock stride")
    let dragged = VoiceOccurrence(fixture.lanePoints()[1])
    let startX = fixture.markerX(dragged.tick)
    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    let altX = startX + 60
    _ = page.pointerMove(x: altX, y: 10, buttons: 1, modifiers: DrawerModifiers.altBit)
    let raw = fixture.session.camera.tickAtContentX(altX)
    report.expectEqual(TimelineSnapPolicy.fineSnap(raw, clockTicks: clock), page.dragPreviewTick,
                       cppID: drawerVoiceFineSnapID,
                       what: "the alt drag previews the legacy clock lattice")
    report.expect((page.dragPreviewTick ?? 1) % Tick(clock) == 0, cppID: drawerVoiceFineSnapID,
                  message: "the alt preview lands on the clock lattice itself")
    _ = page.pointerRelease(x: altX, y: 10, button: 1)
    report.expectEqual(TimelineSnapPolicy.fineSnap(raw, clockTicks: clock),
                       fixture.lanePoints().first { $0.value == dragged.value }?.tick,
                       cppID: drawerVoiceFineSnapID,
                       what: "the released alt drag commits the clock-lattice tick")
}

@MainActor
func drawerVoiceCollisionDragOutcome(_ report: CheckReport, suite: DocumentSession,
                                  service: ProjectService, programs: [Int]) {
    let fixture = drawerVoiceVoiceChangesFixture(suite: suite, service: service, programs: programs)
    let page = fixture.page
    let baseline = fixture.snapshot
    let moving = VoiceOccurrence(fixture.lanePoints()[1])
    let occupied = VoiceOccurrence(fixture.lanePoints()[2])
    let startX = fixture.markerX(moving.tick)

    _ = page.pointerPress(x: startX, y: 10, surface: 1, button: 1, modifiers: 0)
    _ = page.pointerMove(x: fixture.markerX(occupied.tick), y: 10, buttons: 1)
    report.expectEqual(occupied.tick, page.dragPreviewTick, cppID: drawerVoiceCollisionID,
                       what: "the dragged preview lands on the occupied tick")
    _ = page.pointerRelease(x: fixture.markerX(occupied.tick), y: 10, button: 1)

    let points = fixture.lanePoints()
    report.expectEqual(2, points.count, cppID: drawerVoiceCollisionID,
                       what: "a move onto an occupied tick leaves one occurrence there")
    report.expectEqual(moving.value,
                       VoiceLanePolicy.occurrence(at: occupied.tick, in: points)?.value,
                       cppID: drawerVoiceCollisionID, what: "the moved occurrence wins the destination")
    report.expect(VoiceLanePolicy.occurrence(at: moving.tick, in: points) == nil,
                  cppID: drawerVoiceCollisionID, message: "the source tick no longer holds a change")
    report.expectEqual(baseline.revision + 1, fixture.snapshot.revision, cppID: drawerVoiceCollisionID,
                       what: "the collision is one revision")
    report.expect(fixture.snapshot.canUndo && !baseline.canUndo, cppID: drawerVoiceCollisionID,
                  message: "the collision records exactly one history entry")

    // One history entry, both sides restored: an unintended second entry would
    // leave one of the two occurrences behind.
    do {
        _ = try drawerVoiceRunBlocking { try await fixture.session.undo() }
    } catch {
        report.fail(drawerVoiceCollisionID, "undo failed: \(error)")
        return
    }
    let restored = fixture.lanePoints()
    report.expectEqual(3, restored.count, cppID: drawerVoiceCollisionID,
                       what: "a single undo restores both occurrences")
    report.expectEqual(programs[1], VoiceLanePolicy.occurrence(at: 48, in: restored)?.value,
                       cppID: drawerVoiceCollisionID, what: "the moved occurrence is back at its tick")
    report.expectEqual(programs[2],
                       VoiceLanePolicy.occurrence(at: occupied.tick, in: restored)?.value,
                       cppID: drawerVoiceCollisionID, what: "the displaced occurrence is back too")
}
