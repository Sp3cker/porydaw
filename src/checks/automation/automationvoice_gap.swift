import Foundation
@testable import PorydawApp
import PorydawCore
import PorydawProjectService

@MainActor
func drawerAutomationVoiceGapChecks(
    _ report: CheckReport,
    suite: DocumentSession,
    service: ProjectService
) {
    let id = "automation/AutomationEditingTest::portableVoiceGap"
    let editable = suite.bankSlots.indices.filter { suite.bankSlots[$0].voice != nil }
    guard editable.count >= 3 else {
        report.fail(id, "voice GAP checks require three editable bank programs")
        return
    }
    let programs = Array(editable.prefix(3))

    let moved = drawerVoiceVoiceChangesFixture(
        suite: suite, service: service, programs: programs
    )
    let movedBefore = moved.snapshot
    let movedState = moved.document.state
    let sourceX = moved.markerX(48)
    let targetX = moved.markerX(72)
    report.expect(moved.page.plotWidth > 0 && moved.page.publishedMarkers.count == 3,
                  cppID: id, message: "A001-A007 voice plot publishes every staged occurrence")
    report.expect(moved.page.pointerPress(x: sourceX, y: 10, surface: VoiceInputSurface.plot.rawValue,
                                          button: 1, modifiers: 0),
                  cppID: id, message: "A008-A013 marker press captures one source occurrence")
    _ = moved.page.pointerMove(x: targetX, y: 10, buttons: 1, modifiers: 0)
    let previewTick = moved.page.dragPreviewTick
    report.expect(moved.page.dragActive && previewTick != nil && previewTick != 48,
                  cppID: id, message: "A014-A017 horizontal motion publishes a different snapped preview tick")
    report.expect(moved.snapshot == movedBefore && moved.document.state == movedState,
                  cppID: id, message: "A018-A020 drag preview freezes document content and history")
    _ = moved.page.pointerRelease(x: targetX, y: 10, button: 1, modifiers: 0)
    report.expect(!moved.page.hasGesture && !moved.page.interactionActive,
                  cppID: id, message: "A021-A023 release clears the voice gesture")
    report.expect(moved.document.revision == movedBefore.revision + 1
                      && moved.document.history.canUndo,
                  cppID: id, message: "A024-A027 release commits exactly one undoable document revision")
    report.expect(moved.lanePoints().contains(where: { $0.tick == previewTick })
                      && !moved.lanePoints().contains(where: { $0.tick == 48 }),
                  cppID: id, message: "A028-A029 release moves only the captured occurrence to its preview tick")
    do {
        _ = try drawerVoiceRunBlocking { try await moved.session.undo() }
    } catch {
        report.fail(id, "A030 undo failed: \(error)")
        return
    }
    report.expect(moved.document.state == movedState && moved.lanePoints().contains(where: { $0.tick == 48 }),
                  cppID: id, message: "A030-A031 undo restores exact source content")

    let stationary = drawerVoiceVoiceChangesFixture(
        suite: suite, service: service, programs: programs
    )
    let stationaryBefore = stationary.snapshot
    let stationaryState = stationary.document.state
    let stationaryX = stationary.markerX(48)
    _ = stationary.page.pointerPress(x: stationaryX, y: 10,
                                     surface: VoiceInputSurface.plot.rawValue,
                                     button: 1, modifiers: 0)
    _ = stationary.page.pointerMove(x: stationaryX, y: 40, buttons: 1, modifiers: 0)
    report.expect(stationary.page.dragPreviewTick == 48,
                  cppID: id, message: "A032-A037 vertical-only jitter keeps the frozen voice tick")
    _ = stationary.page.pointerRelease(x: stationaryX, y: 40, button: 1, modifiers: 0)
    report.expect(stationary.snapshot == stationaryBefore && stationary.document.state == stationaryState,
                  cppID: id, message: "A038-A041 stationary vertical release commits no revision or history")
    let blankX = stationary.markerX(84)
    _ = stationary.page.pointerPress(x: blankX, y: 40, surface: VoiceInputSurface.plot.rawValue,
                                     button: 1, modifiers: 0)
    _ = stationary.page.pointerRelease(x: blankX, y: 40, button: 1, modifiers: 0)
    report.expect(stationary.snapshot == stationaryBefore && !stationary.page.dragActive,
                  cppID: id, message: "A042-A044 empty-space press and release commits nothing")

    let fine = drawerVoiceVoiceChangesFixture(
        suite: suite, service: service, programs: programs, division: 96
    )
    let fineBefore = fine.snapshot
    let fineX = fine.markerX(48)
    let fineTargetX = fineX + 61
    _ = fine.page.pointerPress(x: fineX, y: 10, surface: VoiceInputSurface.plot.rawValue,
                               button: 1, modifiers: 0)
    _ = fine.page.pointerMove(x: fineTargetX, y: 10, buttons: 1,
                              modifiers: DrawerModifiers.altBit)
    let clockTicks = TimelineSnapPolicy.clockTicks(
        division: fine.document.ticksPerBeat,
        extendedClocks: fine.document.state.config.extendedClocks
    )
    let expectedFine = TimelineSnapPolicy.fineSnap(
        fine.session.camera.tickAtContentX(fineTargetX), clockTicks: clockTicks
    )
    report.expect(fine.page.dragPreviewTick == expectedFine
                      && expectedFine % Tick(clockTicks) == 0,
                  cppID: id, message: "A045-A061 Alt drag previews on the document's fine clock lattice")
    _ = fine.page.pointerRelease(x: fineTargetX, y: 10, button: 1,
                                 modifiers: DrawerModifiers.altBit)
    report.expect(fine.lanePoints().contains(where: { $0.tick == expectedFine })
                      && fine.document.revision == fineBefore.revision + 1,
                  cppID: id, message: "A045-A061 Alt release commits the exact fine-snapped tick once")

    let collision = drawerVoiceVoiceChangesFixture(
        suite: suite, service: service, programs: programs
    )
    let collisionBefore = collision.snapshot
    _ = collision.page.pointerPress(x: collision.markerX(48), y: 10,
                                    surface: VoiceInputSurface.plot.rawValue,
                                    button: 1, modifiers: 0)
    _ = collision.page.pointerMove(x: collision.markerX(120), y: 10, buttons: 1)
    report.expect(collision.page.dragPreviewTick == 120 && collision.snapshot == collisionBefore,
                  cppID: id, message: "A062-A070 occupied destination previews while document remains frozen")
    _ = collision.page.pointerRelease(x: collision.markerX(120), y: 10, button: 1)
    report.expect(collision.lanePoints().count == 2
                      && VoiceLanePolicy.occurrence(at: 48, in: collision.lanePoints()) == nil
                      && VoiceLanePolicy.occurrence(at: 120, in: collision.lanePoints())?.value == programs[1],
                  cppID: id, message: "A071-A078 collision removes the source and lets the moved occurrence win")
    report.expect(collision.document.revision == collisionBefore.revision + 1
                      && collision.document.history.canUndo,
                  cppID: id, message: "A079-A081 collision is exactly one undoable revision")
    do {
        _ = try drawerVoiceRunBlocking { try await collision.session.undo() }
    } catch {
        report.fail(id, "A082 collision undo failed: \(error)")
        return
    }
    report.expect(collision.lanePoints().count == 3
                      && VoiceLanePolicy.occurrence(at: 48, in: collision.lanePoints())?.value == programs[1]
                      && VoiceLanePolicy.occurrence(at: 120, in: collision.lanePoints())?.value == programs[2],
                  cppID: id, message: "A082-A086 one undo restores both collision participants")

    let stale = drawerVoiceVoiceChangesFixture(
        suite: suite, service: service, programs: programs
    )
    _ = stale.page.pointerPress(x: stale.markerX(48), y: 10,
                                surface: VoiceInputSurface.plot.rawValue,
                                button: 1, modifiers: 0)
    _ = stale.page.pointerMove(x: stale.markerX(72), y: 10, buttons: 1)
    stale.document.writeLane(track: 0, lane: .voice, from: 0, through: 0,
                             points: [LaneWrite(tick: 0, value: programs[2])])
    let rewritten = stale.snapshot
    let rewrittenState = stale.document.state
    _ = stale.page.pointerRelease(x: stale.markerX(72), y: 10, button: 1)
    report.expect(stale.snapshot == rewritten && stale.document.state == rewrittenState,
                  cppID: id, message: "A087-A090 stale drag release preserves the concurrent rewrite exactly")

    for route in ["escape", "ungrab"] {
        let cancelled = drawerVoiceVoiceChangesFixture(
            suite: suite, service: service, programs: programs
        )
        let frozen = cancelled.snapshot
        let frozenState = cancelled.document.state
        let x = cancelled.markerX(48)
        _ = cancelled.page.pointerPress(x: x, y: 10, surface: VoiceInputSurface.plot.rawValue,
                                        button: 1, modifiers: 0)
        _ = cancelled.page.pointerMove(x: cancelled.markerX(72), y: 10, buttons: 1)
        report.expect(cancelled.page.dragActive,
                      cppID: id, message: "A091-A096-\(route) cancellation begins from a live voice preview")
        if route == "escape" {
            report.expect(cancelled.page.handleEscape(), cppID: id,
                          message: "A097-A101-escape Escape is consumed by the voice gesture")
        } else {
            cancelled.page.cancelSectionInteraction()
        }
        _ = cancelled.page.pointerRelease(x: cancelled.markerX(72), y: 10, button: 1)
        report.expect(!cancelled.page.hasGesture && !cancelled.page.interactionActive,
                      cppID: id, message: "A098-A107-\(route) cancellation clears gesture and interaction state")
        report.expect(cancelled.snapshot == frozen && cancelled.document.state == frozenState,
                      cppID: id, message: "A097-A108-\(route) release after cancellation commits nothing")
    }

    let duplicate = drawerVoiceVoiceChangesFixture(
        suite: suite, service: service, programs: programs
    )
    duplicate.document.writeLane(
        track: 0, lane: .voice, from: 0, through: TimeDefaults.noTick,
        points: [LaneWrite(tick: 48, value: programs[1]),
                 LaneWrite(tick: 48, value: programs[1])]
    )
    let duplicateBefore = duplicate.snapshot
    let duplicateState = duplicate.document.state
    report.expect(duplicate.lanePoints().count == 2
                      && duplicate.page.publishedMarkers.count(where: { Tick($0.tick) == 48 }) == 2,
                  cppID: id, message: "A109-A114 two identical source occurrences retain two published identities")
    _ = duplicate.page.pointerPress(x: duplicate.markerX(48), y: 10,
                                    surface: VoiceInputSurface.plot.rawValue,
                                    button: 1, modifiers: 0)
    _ = duplicate.page.pointerMove(x: duplicate.markerX(72), y: 10, buttons: 1)
    let duplicatePreview = duplicate.page.dragPreviewTick
    report.expect(duplicatePreview != nil
                      && duplicate.page.publishedMarkers.count(where: { Tick($0.tick) == 48 }) == 1
                      && duplicate.page.publishedMarkers.count(where: { Tick($0.tick) == duplicatePreview }) == 1
                      && duplicate.snapshot == duplicateBefore,
                  cppID: id, message: "A115-A121 preview moves one duplicate identity and freezes document state")
    _ = duplicate.page.pointerRelease(x: duplicate.markerX(72), y: 10, button: 1)
    report.expect(duplicate.lanePoints().count == 2
                      && duplicate.lanePoints().count(where: { $0.tick == 48 }) == 1
                      && duplicate.lanePoints().count(where: { $0.tick == duplicatePreview }) == 1,
                  cppID: id, message: "A122-A132 release moves exactly one duplicate occurrence")
    report.expect(duplicate.document.revision == duplicateBefore.revision + 1
                      && duplicate.document.history.canUndo,
                  cppID: id, message: "A122-A132 duplicate move is one undoable revision")
    do {
        _ = try drawerVoiceRunBlocking { try await duplicate.session.undo() }
    } catch {
        report.fail(id, "A133 duplicate undo failed: \(error)")
        return
    }
    report.expect(duplicate.document.state == duplicateState
                      && duplicate.lanePoints().count(where: { $0.tick == 48 }) == 2,
                  cppID: id, message: "A133-A134 undo restores exact duplicate source content")
}
