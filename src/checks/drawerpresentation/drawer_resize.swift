import PorydawApp

// Existing scenarios paired with drawer.cpp.
// Entry order remains in EditorDrawerChecks.swift.

@MainActor
func drawerLayoutCheckDrawerResizeClampsAndSessions(_ report: CheckReport) {
    let harness = drawerLayoutMakeStoredDrawerHarness().harness
    harness.apply { $0.beginResize(.automation) }
    report.expect(harness.layout.resizeKind == .automation, cppID: drawerLayoutResizeID,
                  message: "beginning a resize claims the session for its kind")

    let crossKind = harness.apply { $0.applyResize(.velocity, delta: 10) }
    let crossEnd = harness.apply { $0.endResize(.velocity) }
    report.expect(!crossKind.published && !crossEnd.published && crossKind.isEmpty &&
                  harness.layout.resizeKind == .automation &&
                  harness.layout.storedBodyHeight(.velocity) == 60,
                  cppID: drawerLayoutResizeID,
                  message: "a resize session belongs to one kind and ignores other kinds")

    let grown = harness.apply { $0.applyResize(.automation, delta: 30.4) }
    report.expect(grown.published && harness.layout.storedBodyHeight(.automation) == 130 &&
                  harness.layout.snapshot[.automation].bodyHeight == 130,
                  cppID: drawerLayoutResizeID,
                  message: "a positive drag delta grows the body by the rounded delta, above the reserve bound")
    drawerLayoutExpectNoDrawerRecords(report, cppID: drawerLayoutResizeID, grown,
                          message: "an applied drag step records no preference change of its own")

    let ended = harness.apply { $0.endResize(.automation) }
    report.expect(harness.layout.resizeKind == nil &&
                  harness.layout.storedBodyHeight(.automation) == 130 &&
                  ended.sectionPreferences.count == 1, cppID: drawerLayoutResizeID,
                  message: "ending the resize records the changed section preference once")
    drawerLayoutExpectDrawerPreference(report, cppID: drawerLayoutResizeID, ended, .automation, visible: true,
                           storedBodyHeight: 130,
                           message: "end records the resized kind visibility and stored height")

    let sessionless = harness.apply { $0.applyResize(.automation, delta: 5) }
    let sessionlessEnd = harness.apply { $0.endResize(.automation) }
    report.expect(!sessionless.published && !sessionlessEnd.published &&
                  harness.layout.storedBodyHeight(.automation) == 130,
                  cppID: drawerLayoutResizeID,
                  message: "apply and end without a live session are ignored")

    harness.apply { $0.beginResize(.automation) }
    let shrunk = harness.apply { $0.applyResize(.automation, delta: -1_000) }
    report.expect(shrunk.published &&
                  harness.layout.storedBodyHeight(.automation) == drawerLayoutDrawerMinimumBody,
                  cppID: drawerLayoutResizeID,
                  message: "a shrink clamps at the minimum body height")
    let returned = harness.apply { $0.applyResize(.automation, delta: 0) }
    report.expect(returned.published && harness.layout.storedBodyHeight(.automation) == 130,
                  cppID: drawerLayoutResizeID,
                  message: "returning to the drag-start height restores the original stored height")

    let unsetReturn = drawerLayoutMakeStoredDrawerHarness().harness
    unsetReturn.apply { $0.setSectionBodyHeight(.automation, height: 0) }
    unsetReturn.apply { $0.beginResize(.automation) }
    unsetReturn.apply { $0.applyResize(.automation, delta: 25) }
    let returnedToUnset = unsetReturn.apply { $0.applyResize(.automation, delta: 0) }
    report.expect(returnedToUnset.published &&
                  unsetReturn.layout.storedBodyHeight(.automation) == nil &&
                  unsetReturn.layout.snapshot[.automation].bodyHeight == 80,
                  cppID: drawerLayoutResizeID,
                  message: "returning to the drag start restores the unset marker, not a concrete height")

    let available = drawerLayoutMakeStoredDrawerHarness().harness
    available.apply { $0.beginResize(.velocity) }
    let clamped = available.apply { $0.applyResize(.velocity, delta: 1_000) }
    report.expect(clamped.published && available.layout.storedBodyHeight(.velocity) == 216 &&
                  available.layout.snapshot[.velocity].bodyHeight == 216 &&
                  available.layout.snapshot.height == drawerLayoutDrawerHostHeight,
                  cppID: drawerLayoutResizeID,
                  message: "the available-height clamp fills the host exactly and never overflows it")

    let declared = drawerLayoutMakeStoredDrawerHarness().harness
    declared.apply { $0.setSectionVisible(.automation, visible: false, drawerOwnsFocus: false) }
    declared.apply { $0.beginResize(.voiceChanges) }
    let cappedResize = declared.apply { $0.applyResize(.voiceChanges, delta: 1_000) }
    report.expect(cappedResize.published &&
                  declared.layout.storedBodyHeight(.voiceChanges) == 110 &&
                  declared.layout.snapshot[.voiceChanges].bodyHeight == 110,
                  cppID: drawerLayoutResizeID,
                  message: "a page-declared maximum applies after the available-height clamp without a spill partner")

    let cancelled = drawerLayoutMakeStoredDrawerHarness().harness
    cancelled.apply { $0.beginResize(.voiceChanges) }
    cancelled.apply { $0.applyResize(.voiceChanges, delta: 40) }
    let cancelChange = cancelled.apply { $0.cancelResize() }
    report.expect(!cancelChange.published && cancelChange.isEmpty &&
                  cancelled.layout.resizeKind == nil &&
                  cancelled.layout.storedBodyHeight(.voiceChanges) == 90 &&
                  cancelled.layout.snapshot[.voiceChanges].bodyHeight == 90,
                  cppID: drawerLayoutResizeID,
                  message: "cancelling a resize drops the session, keeps the applied height and records nothing")

    let interrupted = drawerLayoutMakeStoredDrawerHarness().harness
    interrupted.apply { $0.beginResize(.voiceChanges) }
    interrupted.apply { $0.applyResize(.voiceChanges, delta: 20) }
    interrupted.apply { $0.cancelInteractions() }
    report.expect(interrupted.layout.resizeKind == nil &&
                  interrupted.layout.storedBodyHeight(.voiceChanges) == 70,
                  cppID: drawerLayoutResizeID,
                  message: "global cancellation drops a live resize session and keeps the applied height")

    let stepped = drawerLayoutMakeStoredDrawerHarness().harness
    let step = stepped.apply { $0.adjustResizeHandle(.automation, direction: 1) }
    report.expect(step.published &&
                  stepped.layout.storedBodyHeight(.automation) == 100 + drawerLayoutDrawerResizeStep &&
                  stepped.layout.resizeKind == nil, cppID: drawerLayoutResizeID,
                  message: "a handle step applies one resize step through the resize path and ends its own session")
    drawerLayoutExpectDrawerPreference(report, cppID: drawerLayoutResizeID, step, .automation, visible: true,
                           storedBodyHeight: 107,
                           message: "a handle step records the changed section preference")

    let flooredStep = drawerLayoutMakeStoredDrawerHarness().harness
    flooredStep.apply { $0.setSectionBodyHeight(.automation, height: drawerLayoutDrawerMinimumBody) }
    let floorStep = flooredStep.apply { $0.adjustResizeHandle(.automation, direction: -1) }
    report.expect(!floorStep.published && floorStep.isEmpty &&
                  flooredStep.layout.storedBodyHeight(.automation) == drawerLayoutDrawerMinimumBody,
                  cppID: drawerLayoutResizeID,
                  message: "a handle step that resolves to the drag start publishes nothing")
}

@MainActor
func drawerLayoutCheckDrawerVoiceChangesSpill(_ report: CheckReport) {
    let harness = drawerLayoutMakeStoredDrawerHarness().harness
    harness.apply { $0.beginResize(.voiceChanges) }
    let spilled = harness.apply { $0.applyResize(.voiceChanges, delta: 90) }
    report.expect(spilled.published && harness.layout.storedBodyHeight(.voiceChanges) == 110 &&
                  harness.layout.storedBodyHeight(.automation) == 130 &&
                  harness.layout.snapshot[.automation].bodyHeight == 130 &&
                  harness.layout.snapshot.height ==
                      drawerLayoutDrawerBarHeight + 3 * drawerLayoutDrawerHandleHeight + 60 + 110 + 130,
                  cppID: drawerLayoutSpillID,
                  message: "a voice-change drag past its declared maximum moves the automations stored height by the excess")

    let stationary = harness.apply { $0.applyResize(.voiceChanges, delta: 90) }
    report.expect(!stationary.published && harness.layout.storedBodyHeight(.automation) == 130,
                  cppID: drawerLayoutSpillID,
                  message: "a stationary pointer cannot add the same spill twice")

    let spilledEnd = harness.apply { $0.endResize(.voiceChanges) }
    report.expect(spilledEnd.sectionPreferences.count == 2 &&
                  spilledEnd.sectionPreferences.contains {
                      $0.kind == .voiceChanges && $0.storedBodyHeight == 110
                  } &&
                  spilledEnd.sectionPreferences.contains {
                      $0.kind == .automation && $0.storedBodyHeight == 130
                  } && harness.layout.resizeKind == nil,
                  cppID: drawerLayoutSpillID,
                  message: "ending a spilled resize records both changed kinds")

    let reverted = drawerLayoutMakeStoredDrawerHarness().harness
    reverted.apply { $0.beginResize(.voiceChanges) }
    reverted.apply { $0.applyResize(.voiceChanges, delta: 90) }
    let returned = reverted.apply { $0.applyResize(.voiceChanges, delta: 0) }
    report.expect(returned.published &&
                  reverted.layout.storedBodyHeight(.voiceChanges) == 50 &&
                  reverted.layout.storedBodyHeight(.automation) == 100 &&
                  reverted.layout.snapshot.height ==
                      drawerLayoutDrawerBarHeight + 3 * drawerLayoutDrawerHandleHeight + 60 + 50 + 100,
                  cppID: drawerLayoutSpillID,
                  message: "returning to the drag start restores both original stored heights")

    let crowded = drawerLayoutMakeStoredDrawerHarness(hostHeight: 200).harness
    crowded.apply { $0.beginResize(.voiceChanges) }
    let floored = crowded.apply { $0.applyResize(.voiceChanges, delta: 200) }
    report.expect(floored.published &&
                  crowded.layout.storedBodyHeight(.voiceChanges) == 106 &&
                  crowded.layout.storedBodyHeight(.automation) == drawerLayoutDrawerMinimumBody,
                  cppID: drawerLayoutSpillID,
                  message: "spilled automations stop at the minimum body when the available height is exhausted")

    let unspilled = drawerLayoutMakeStoredDrawerHarness().harness
    unspilled.apply { $0.setSectionVisible(.automation, visible: false, drawerOwnsFocus: false) }
    unspilled.apply { $0.beginResize(.voiceChanges) }
    let withoutPartner = unspilled.apply { $0.applyResize(.voiceChanges, delta: 90) }
    report.expect(withoutPartner.published &&
                  unspilled.layout.storedBodyHeight(.voiceChanges) == 110 &&
                  unspilled.layout.storedBodyHeight(.automation) == 100,
                  cppID: drawerLayoutSpillID,
                  message: "a voice-change drag without a visible automations partner keeps the automations height")

    let uncapped = drawerLayoutMakeStoredDrawerHarness().harness
    uncapped.apply { $0.beginResize(.velocity) }
    let velocityGrowth = uncapped.apply { $0.applyResize(.velocity, delta: 30) }
    report.expect(velocityGrowth.published &&
                  uncapped.layout.storedBodyHeight(.velocity) == 90 &&
                  uncapped.layout.storedBodyHeight(.automation) == 100,
                  cppID: drawerLayoutSpillID,
                  message: "a kind with no declared maximum never spills into the automations section")
}

@MainActor
func drawerLayoutCheckDrawerHostClampAndAllocation(_ report: CheckReport) {
    let harness = drawerLayoutMakeStoredDrawerHarness().harness
    let shrunk = harness.apply {
        $0.configureHost(hostWidth: drawerLayoutDrawerHostWidth, hostHeight: 120,
                         gutterWidth: drawerLayoutDrawerGutterWidth)
    }
    let snapshot = harness.layout.snapshot
    report.expect(shrunk.published && snapshot.height == 120 && snapshot.barY == 98 &&
                  harness.layout.storedBodyHeight(.velocity) == 60 &&
                  harness.layout.storedBodyHeight(.voiceChanges) == 50 &&
                  harness.layout.storedBodyHeight(.automation) == 100,
                  cppID: drawerLayoutClampID,
                  message: "a host shrink re-clamps the container without rewriting stored heights")
    report.expect(snapshot[.voiceChanges].bodyHeight == 50 &&
                  snapshot[.automation].bodyHeight == 36 &&
                  snapshot[.velocity].bodyHeight == 0 &&
                  snapshot[.velocity].handleHeight == drawerLayoutDrawerHandleHeight,
                  cppID: drawerLayoutClampID,
                  message: "the clamped allocation fills voice changes first, automations second and velocity with the remainder")
    report.expect(snapshot[.automation].bodyY ==
                      snapshot[.velocity].bodyY + snapshot[.velocity].bodyHeight +
                      snapshot[.voiceChanges].handleHeight + snapshot[.voiceChanges].bodyHeight +
                      drawerLayoutDrawerHandleHeight &&
                  snapshot.barY == snapshot[.automation].bodyY + snapshot[.automation].bodyHeight,
                  cppID: drawerLayoutClampID,
                  message: "a constrained container keeps every drawn rectangle ordered and non-negative")

    let reserved = drawerLayoutMakeDrawerHarness()
    reserved.apply {
        $0.attachPage(drawerLayoutDrawerStubPage(kind: .automation, url: drawerLayoutDrawerAutomationUrl,
                                     policy: drawerLayoutDrawerStubPolicy(), harness: reserved))
    }
    reserved.apply { $0.setSectionBodyHeight(.automation, height: 350) }
    report.expect(reserved.layout.snapshot.height == drawerLayoutDrawerBarHeight + drawerLayoutDrawerHandleHeight + 350 &&
                  reserved.layout.snapshot[.automation].bodyHeight == 350,
                  cppID: drawerLayoutClampID,
                  message: "the piano-roll reserve never caps a stored body or the aggregate height")

    reserved.apply { $0.beginResize(.automation) }
    let grown = reserved.apply { $0.applyResize(.automation, delta: 30) }
    report.expect(grown.published && reserved.layout.storedBodyHeight(.automation) == 374 &&
                  reserved.layout.snapshot.height == drawerLayoutDrawerHostHeight,
                  cppID: drawerLayoutClampID,
                  message: "the reserve never caps a resize, and the aggregate may fill the host exactly")

    let defaults = drawerLayoutMakeDrawerHarness()
    defaults.apply {
        $0.attachPage(drawerLayoutDrawerStubPage(kind: .automation, url: drawerLayoutDrawerAutomationUrl,
                                     policy: drawerLayoutDrawerStubPolicy(), harness: defaults))
    }
    report.expect(defaults.layout.snapshot[.automation].bodyHeight == 80 &&
                  defaults.layout.snapshot.height == drawerLayoutDrawerBarHeight + drawerLayoutDrawerHandleHeight + 80,
                  cppID: drawerLayoutClampID,
                  message: "a page default is bounded by the reserve through maximumDefaultBodyHeight")
    defaults.apply {
        $0.configureHost(hostWidth: drawerLayoutDrawerHostWidth, hostHeight: 100,
                         gutterWidth: drawerLayoutDrawerGutterWidth)
    }
    report.expect(defaults.layout.snapshot[.automation].bodyHeight == drawerLayoutDrawerMinimumBody &&
                  defaults.layout.snapshot.height ==
                      drawerLayoutDrawerBarHeight + drawerLayoutDrawerHandleHeight + drawerLayoutDrawerMinimumBody,
                  cppID: drawerLayoutClampID,
                  message: "a short host keeps the default body at its minimum instead of the reserve bound")
}
