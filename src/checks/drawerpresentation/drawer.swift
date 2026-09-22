import PorydawApp

// Existing scenarios paired with drawer.cpp.
// Entry order remains in EditorDrawerChecks.swift.

@MainActor
func drawerLayoutCheckDrawerMetricsAndKinds(_ report: CheckReport) {
    let metrics = drawerLayoutDrawerMetrics()
    report.expectEqual(
        EditorDrawerMetrics(barHeight: drawerLayoutDrawerBarHeight, handleHeight: drawerLayoutDrawerHandleHeight,
                            minimumBody: drawerLayoutDrawerMinimumBody, pianoRollReserve: 130,
                            toggleInset: 3, resizeStep: drawerLayoutDrawerResizeStep, pixel: 1),
        metrics, cppID: drawerLayoutMetricsID,
        what: "resolved metrics derive the production bar row, handle, body floor, reserve, inset, step and hairline")
    report.expectEqual(
        6, EditorDrawerMetrics.resolve(baseFontPx: 13, appFontLineSpacing: -8).barHeight,
        cppID: drawerLayoutMetricsID,
        what: "a negative application line spacing does not shrink the bar below its own padding")
    report.expectEqual(270, metrics.maximumDefaultBodyHeight(hostHeight: 400), cppID: drawerLayoutMetricsID,
                       what: "the piano-roll reserve bounds a default body height")
    report.expectEqual(173, metrics.maximumDefaultBodyHeight(hostHeight: 173), cppID: drawerLayoutMetricsID,
                       what: "a host shorter than reserve plus floor keeps the whole host height")
    report.expectEqual(44, metrics.maximumDefaultBodyHeight(hostHeight: 174), cppID: drawerLayoutMetricsID,
                       what: "the reserve bound meets the body floor exactly at its boundary")

    report.expect(DrawerSectionKind.automation.rawValue == 0 &&
                  DrawerSectionKind.velocity.rawValue == 1 &&
                  DrawerSectionKind.voiceChanges.rawValue == 2 &&
                  DrawerSectionKind.stackOrder == [.velocity, .voiceChanges, .automation] &&
                  DrawerSectionKind.toggleOrder == [.voiceChanges, .automation, .velocity],
                  cppID: drawerLayoutMetricsID,
                  message: "section identities keep production raw values and the fixed stack and toggle orders")
    report.expect(DrawerSectionKind.allCases.map(\.name) == ["automations", "velocity", "voiceChanges"] &&
                  DrawerSectionKind.allCases.map(\.keyName) == ["automation", "velocity", "voiceChanges"] &&
                  DrawerSectionKind.automation.iconResource == "qrc:/icons/automation.svg" &&
                  DrawerSectionKind.velocity.iconResource == "qrc:/icons/velocity.svg" &&
                  DrawerSectionKind.voiceChanges.iconResource == "qrc:/icons/flat-music.svg",
                  cppID: drawerLayoutMetricsID,
                  message: "preference key names and toggle icon resources follow the historical formats")
}

@MainActor
func drawerLayoutCheckDrawerNoPageAndAvailability(_ report: CheckReport) {
    let harness = drawerLayoutMakeDrawerHarness()
    let empty = harness.layout.snapshot
    report.expect(empty.height == 0 && !empty.barVisible && empty.plotOrigin == drawerLayoutDrawerGutterWidth &&
                  empty.plotWidth == drawerLayoutDrawerHostWidth - drawerLayoutDrawerGutterWidth &&
                  empty.barWidth == 0 && empty.barHeight == 0, cppID: drawerLayoutAvailabilityID,
                  message: "a container with no attached page contributes zero height and no bar")
    for kind in DrawerSectionKind.allCases {
        let geometry = empty[kind]
        report.expect(!geometry.available && geometry.contentUrl.isEmpty &&
                      geometry.bodyWidth == 0 && geometry.bodyHeight == 0 &&
                      geometry.handleHeight == 0 && geometry.toggleSize == 0,
                      cppID: drawerLayoutAvailabilityID,
                      message: "\(kind.name) publishes no control, no body and an empty URL with no page attached")
    }

    let restored = harness.apply {
        $0.restorePreferences(velocityVisible: 1, velocityHeight: 220, automationVisible: -1,
                              automationHeight: 0, voiceChangesVisible: -1, voiceChangesHeight: 0,
                              activePage: -1)
    }
    report.expect(harness.layout.isVisible(.velocity) &&
                  harness.layout.storedBodyHeight(.velocity) == 220 &&
                  harness.layout.isVisible(.automation) &&
                  harness.layout.storedBodyHeight(.automation) == nil &&
                  !harness.layout.isVisible(.voiceChanges) &&
                  harness.layout.activePage == .automation && harness.layout.snapshot.height == 0,
                  cppID: drawerLayoutAvailabilityID,
                  message: "restored section intent is retained as stored preference while no page is attached")
    drawerLayoutExpectNoDrawerRecords(report, cppID: drawerLayoutAvailabilityID, restored,
                          message: "restoring stored preferences records no preference change")

    let velocity = drawerLayoutDrawerStubPage(kind: .velocity, url: drawerLayoutDrawerVelocityUrl,
                                  policy: drawerLayoutDrawerStubPolicy(divisor: 6), harness: harness)
    let attached = harness.apply { $0.attachPage(velocity) }
    report.expect(attached.published && harness.layout.isAvailable(.velocity) &&
                  attached.snapshot[.velocity].contentUrl == drawerLayoutDrawerVelocityUrl &&
                  attached.snapshot[.velocity].bodyHeight == 220 &&
                  attached.snapshot[.velocity].available && attached.snapshot[.velocity].visible &&
                  attached.snapshot.height == drawerLayoutDrawerBarHeight + drawerLayoutDrawerHandleHeight + 220,
                  cppID: drawerLayoutAvailabilityID,
                  message: "attaching a page turns a stored visible section into visible content in the same publication")

    let duplicate = harness.apply { $0.attachPage(velocity) }
    report.expect(!duplicate.published && duplicate.isEmpty &&
                  harness.layout.attachedPage(.velocity) === velocity &&
                  duplicate.snapshot.height == drawerLayoutDrawerBarHeight + drawerLayoutDrawerHandleHeight + 220,
                  cppID: drawerLayoutAvailabilityID,
                  message: "a kind that already holds a page rejects a second attach and publishes nothing")

    let emptyUrl = drawerLayoutDrawerStubPage(kind: .voiceChanges, url: "", policy: drawerLayoutDrawerStubPolicy(),
                                  harness: harness)
    let rejected = harness.apply { $0.attachPage(emptyUrl) }
    report.expect(!rejected.published && rejected.isEmpty &&
                  !harness.layout.isAvailable(.voiceChanges) &&
                  harness.layout.attachedPage(.voiceChanges) == nil &&
                  rejected.snapshot.height == drawerLayoutDrawerBarHeight + drawerLayoutDrawerHandleHeight + 220,
                  cppID: drawerLayoutAvailabilityID,
                  message: "an empty content URL is rejected without changing any state")

    let detachedToggle = harness.apply { $0.toggleSection(.voiceChanges, drawerOwnsFocus: true) }
    let detachedHeight = harness.apply { $0.setSectionBodyHeight(.voiceChanges, height: 150) }
    let detachedVisible = harness.apply {
        $0.setSectionVisible(.voiceChanges, visible: true, drawerOwnsFocus: false)
    }
    let detachedResize = harness.apply { $0.beginResize(.voiceChanges) }
    report.expect(!detachedToggle.published && !detachedHeight.published &&
                  !detachedVisible.published && !detachedResize.published &&
                  detachedToggle.isEmpty && detachedResize.isEmpty &&
                  harness.layout.resizeKind == nil && !harness.layout.isVisible(.voiceChanges) &&
                  harness.layout.storedBodyHeight(.voiceChanges) == nil &&
                  harness.layout.activePage == .automation && emptyUrl.cancelCount == 0,
                  cppID: drawerLayoutAvailabilityID,
                  message: "visibility, height and resize calls are ignored for a kind with no attached page")

    let detached = harness.apply { $0.detachPage(velocity) }
    report.expect(detached.published && !harness.layout.isAvailable(.velocity) &&
                  harness.layout.attachedPage(.velocity) == nil &&
                  harness.layout.isVisible(.velocity) &&
                  harness.layout.storedBodyHeight(.velocity) == 220 &&
                  detached.snapshot.height == 0 && detached.cancelledSections == [.velocity] &&
                  velocity.cancelCount == 1 && velocity.publishedHeightsAtCancel == [246],
                  cppID: drawerLayoutAvailabilityID,
                  message: "detaching cancels its page synchronously and drops its controls while stored visibility and height survive")
    drawerLayoutExpectNoDrawerRecords(report, cppID: drawerLayoutAvailabilityID, detached,
                          message: "detaching records no preference change")
}

@MainActor
func drawerLayoutCheckDrawerStackingAndToggles(_ report: CheckReport) {
    let stored = drawerLayoutMakeStoredDrawerHarness()
    let snapshot = stored.harness.layout.snapshot
    report.expect(snapshot.height == drawerLayoutDrawerBarHeight + 3 * drawerLayoutDrawerHandleHeight + 60 + 50 + 100 &&
                  snapshot.barVisible && snapshot.plotOrigin == drawerLayoutDrawerGutterWidth &&
                  snapshot.plotWidth == drawerLayoutDrawerHostWidth - drawerLayoutDrawerGutterWidth,
                  cppID: drawerLayoutStackingID,
                  message: "three visible sections stack their bodies, handles and bar into one container height")

    let velocity = snapshot[.velocity]
    let voiceChanges = snapshot[.voiceChanges]
    let automation = snapshot[.automation]
    drawerLayoutExpectDrawerBody(report, cppID: drawerLayoutStackingID,
                     message: "velocity takes the top body slot at the full host width",
                     velocity, x: 0, y: drawerLayoutDrawerHandleHeight, width: drawerLayoutDrawerHostWidth, height: 60)
    drawerLayoutExpectDrawerHandle(report, cppID: drawerLayoutStackingID,
                       message: "the velocity handle sits directly above its body",
                       velocity, velocity, y: 0, height: drawerLayoutDrawerHandleHeight)
    drawerLayoutExpectDrawerBody(report, cppID: drawerLayoutStackingID,
                     message: "voice changes follow velocity below their own handle",
                     voiceChanges, x: 0, y: drawerLayoutDrawerHandleHeight + 60 + drawerLayoutDrawerHandleHeight,
                     width: drawerLayoutDrawerHostWidth, height: 50)
    drawerLayoutExpectDrawerHandle(report, cppID: drawerLayoutStackingID,
                       message: "the voice-change handle sits directly above its body",
                       voiceChanges, voiceChanges, y: drawerLayoutDrawerHandleHeight + 60,
                       height: drawerLayoutDrawerHandleHeight)
    drawerLayoutExpectDrawerBody(report, cppID: drawerLayoutStackingID,
                     message: "automations follow voice changes below their own handle",
                     automation, x: 0,
                     y: voiceChanges.bodyY + voiceChanges.bodyHeight + drawerLayoutDrawerHandleHeight,
                     width: drawerLayoutDrawerHostWidth, height: 100)
    report.expect(snapshot.barX == 0 && snapshot.barY == snapshot.height - drawerLayoutDrawerBarHeight &&
                  snapshot.barWidth == drawerLayoutDrawerHostWidth && snapshot.barHeight == drawerLayoutDrawerBarHeight &&
                  snapshot.barY == automation.bodyY + automation.bodyHeight,
                  cppID: drawerLayoutStackingID,
                  message: "the bar spans the host width as the last row, directly below the lowest body")

    let buttonSize = drawerLayoutDrawerBarHeight - 2 * 3
    report.expect(buttonSize == 16 && velocity.toggleSize == buttonSize &&
                  voiceChanges.toggleSize == buttonSize && automation.toggleSize == buttonSize,
                  cppID: drawerLayoutStackingID,
                  message: "toggle buttons take the production size for the resolved bar row")
    drawerLayoutExpectDrawerToggle(report, cppID: drawerLayoutStackingID,
                       message: "voice changes occupy the first production toggle slot",
                       voiceChanges, x: 1, y: snapshot.barY + 3, size: buttonSize)
    drawerLayoutExpectDrawerToggle(report, cppID: drawerLayoutStackingID,
                       message: "automations occupy the second production toggle slot",
                       automation, x: 1 + buttonSize + 3, y: snapshot.barY + 3, size: buttonSize)
    drawerLayoutExpectDrawerToggle(report, cppID: drawerLayoutStackingID,
                       message: "velocity occupies the third production toggle slot",
                       velocity, x: 1 + 2 * (buttonSize + 3), y: snapshot.barY + 3, size: buttonSize)
    report.expect(snapshot.detentX == 0 && snapshot.detentY == 48 &&
                  snapshot.detentSize == 16 && snapshot.detentIconInset == 1.5,
                  cppID: drawerLayoutStackingID,
                  message: "detents occupy the velocity body's lower-left corner, not the bar")
    let narrow = stored.harness.apply {
        $0.configureHost(hostWidth: 9, hostHeight: drawerLayoutDrawerHostHeight, gutterWidth: drawerLayoutDrawerGutterWidth)
    }.snapshot
    report.expect(narrow.detentSize == 9 && narrow.detentY == 55,
                  cppID: drawerLayoutStackingID,
                  message: "detent hit geometry is bounded by the visible velocity gutter")

    let slots = drawerLayoutMakeStoredDrawerHarness()
    let detached = slots.harness.apply { $0.detachPage(slots.pages[.voiceChanges]!) }
    let afterDetach = slots.harness.layout.snapshot
    report.expect(detached.published && afterDetach[.automation].toggleX == 1 + buttonSize + 3 &&
                  afterDetach[.velocity].toggleX == 1 + 2 * (buttonSize + 3) &&
                  afterDetach[.voiceChanges].toggleSize == 0 &&
                  afterDetach[.voiceChanges].contentUrl.isEmpty,
                  cppID: drawerLayoutStackingID,
                  message: "detaching one kind leaves the surviving toggle slots and their controls unmoved")
}

@MainActor
func drawerLayoutCheckDrawerVisibilityAndStoredHeights(_ report: CheckReport) {
    let harness = drawerLayoutMakeStoredDrawerHarness().harness
    let hidden = harness.apply {
        $0.setSectionVisible(.automation, visible: false, drawerOwnsFocus: false)
    }
    let hiddenGeometry = harness.layout.snapshot[.automation]
    report.expect(hidden.published && harness.layout.storedBodyHeight(.automation) == 100 &&
                  harness.layout.snapshot.height ==
                      drawerLayoutDrawerBarHeight + 2 * drawerLayoutDrawerHandleHeight + 60 + 50 &&
                  hiddenGeometry.bodyHeight == 0 && hiddenGeometry.handleHeight == 0 &&
                  hiddenGeometry.available && !hiddenGeometry.visible &&
                  hiddenGeometry.contentUrl == drawerLayoutDrawerAutomationUrl &&
                  hiddenGeometry.toggleSize == 16 &&
                  hiddenGeometry.toggleY == harness.layout.snapshot.barY + 3,
                  cppID: drawerLayoutVisibilityID,
                  message: "hiding a section releases its body and handle while its toggle, URL and stored height stay")
    drawerLayoutExpectDrawerPreference(report, cppID: drawerLayoutVisibilityID, hidden, .automation, visible: false,
                           storedBodyHeight: 100,
                           message: "an interactive hide records the kind visibility and stored height")

    let shown = harness.apply {
        $0.setSectionVisible(.automation, visible: true, drawerOwnsFocus: false)
    }
    report.expect(shown.published && harness.layout.snapshot.height ==
                      drawerLayoutDrawerBarHeight + 3 * drawerLayoutDrawerHandleHeight + 60 + 50 + 100 &&
                      harness.layout.snapshot[.automation].bodyHeight == 100,
                  cppID: drawerLayoutVisibilityID,
                  message: "re-showing a hidden section restores its stored body height")

    let equalVisibility = harness.apply {
        $0.setSectionVisible(.velocity, visible: true, drawerOwnsFocus: true)
    }
    let equalHeight = harness.apply { $0.setSectionBodyHeight(.automation, height: 100) }
    let zeroDirection = harness.apply { $0.adjustResizeHandle(.automation, direction: 0) }
    report.expect(!equalVisibility.published && equalVisibility.isEmpty &&
                  equalVisibility.focusRequest == nil && !equalHeight.published &&
                  equalHeight.isEmpty && !zeroDirection.published && zeroDirection.isEmpty,
                  cppID: drawerLayoutVisibilityID,
                  message: "equal visibility and height setters publish nothing and request no focus")

    let toggled = harness.apply { $0.toggleSection(.velocity, drawerOwnsFocus: false) }
    report.expect(toggled.published && !harness.layout.isVisible(.velocity) &&
                  harness.layout.storedBodyHeight(.velocity) == 60 &&
                  harness.layout.activePage == .velocity &&
                  harness.layout.snapshot.height ==
                      drawerLayoutDrawerBarHeight + 2 * drawerLayoutDrawerHandleHeight + 50 + 100 &&
                  toggled.activePagePreference == .velocity,
                  cppID: drawerLayoutVisibilityID,
                  message: "toggling hides the section, keeps its stored height, moves the active page and records both")

    let restoredHeight = harness.apply { $0.toggleSection(.velocity, drawerOwnsFocus: false) }
    report.expect(restoredHeight.published && harness.layout.isVisible(.velocity) &&
                  harness.layout.snapshot[.velocity].bodyHeight == 60 &&
                  restoredHeight.activePagePreference == nil &&
                  restoredHeight.sectionPreferences.count == 1,
                  cppID: drawerLayoutVisibilityID,
                  message: "re-showing through the toggle restores the height and records no page change")

    let unset = harness.apply { $0.setSectionBodyHeight(.automation, height: 0) }
    report.expect(unset.published && harness.layout.storedBodyHeight(.automation) == nil &&
                  harness.layout.snapshot[.automation].bodyHeight == 80,
                  cppID: drawerLayoutVisibilityID,
                  message: "a height below one maps to the unset marker and the page default takes over")
    drawerLayoutExpectDrawerPreference(report, cppID: drawerLayoutVisibilityID, unset, .automation, visible: true,
                           storedBodyHeight: nil,
                           message: "an unset height is recorded as the unset marker")

    let floored = harness.apply { $0.setSectionBodyHeight(.velocity, height: 20) }
    report.expect(floored.published && harness.layout.storedBodyHeight(.velocity) == 20 &&
                  harness.layout.snapshot[.velocity].bodyHeight == drawerLayoutDrawerMinimumBody,
                  cppID: drawerLayoutVisibilityID,
                  message: "a drawn body never falls below the font-relative minimum body")
}

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

@MainActor
func drawerLayoutCheckDrawerFocusRequests(_ report: CheckReport) {
    let harness = drawerLayoutMakeStoredDrawerHarness().harness
    let hiddenActive = harness.apply { $0.toggleSection(.automation, drawerOwnsFocus: true) }
    report.expect(hiddenActive.focusRequest?.target == DrawerSectionKind.velocity.rawValue &&
                  hiddenActive.focusRequest?.revision == 1 && hiddenActive.published &&
                  harness.layout.activePage == .automation,
                  cppID: drawerLayoutFocusID,
                  message: "hiding the active section requests focus for the first remaining visible section")

    let unobserved = harness.apply {
        $0.setSectionVisible(.voiceChanges, visible: false, drawerOwnsFocus: false)
    }
    report.expect(unobserved.focusRequest == nil &&
                  unobserved.cancelledSections == [.voiceChanges] &&
                  !harness.layout.isVisible(.voiceChanges),
                  cppID: drawerLayoutFocusID,
                  message: "a transition that does not own focus cancels content but publishes no focus request")

    let observed = harness.apply {
        $0.setSectionVisible(.voiceChanges, visible: true, drawerOwnsFocus: true)
    }
    report.expect(observed.focusRequest?.target == DrawerSectionKind.velocity.rawValue &&
                  observed.focusRequest?.revision == 2, cppID: drawerLayoutFocusID,
                  message: "focus revisions advance monotonically for real requests only")
    report.expect(observed.focusRequest?.target != DrawerSectionKind.voiceChanges.rawValue,
                  cppID: drawerLayoutFocusID,
                  message: "a request prefers the active visible section over the section just shown")

    let noTransition = harness.apply {
        $0.setSectionVisible(.voiceChanges, visible: true, drawerOwnsFocus: true)
    }
    report.expect(noTransition.focusRequest == nil && !noTransition.published &&
                  noTransition.isEmpty, cppID: drawerLayoutFocusID,
                  message: "an unchanged visibility transition publishes no focus request")

    harness.apply { $0.setSectionVisible(.velocity, visible: false, drawerOwnsFocus: false) }
    harness.apply { $0.setSectionVisible(.voiceChanges, visible: false, drawerOwnsFocus: false) }
    harness.apply { $0.setSectionVisible(.automation, visible: false, drawerOwnsFocus: false) }
    let fullHide = harness.apply {
        $0.setSectionVisible(.automation, visible: false, drawerOwnsFocus: true)
    }
    report.expect(fullHide.focusRequest == nil && fullHide.isEmpty, cppID: drawerLayoutFocusID,
                  message: "hiding an already hidden section is no transition and requests no focus")

    let shownAgain = harness.apply {
        $0.setSectionVisible(.voiceChanges, visible: true, drawerOwnsFocus: true)
    }
    report.expect(shownAgain.focusRequest?.target == DrawerSectionKind.voiceChanges.rawValue,
                  cppID: drawerLayoutFocusID,
                  message: "showing a section with the drawer focused targets that visible section")

    let last = harness.apply {
        $0.setSectionVisible(.voiceChanges, visible: false, drawerOwnsFocus: true)
    }
    report.expect(last.focusRequest?.target == -1 && harness.layout.snapshot.barVisible &&
                  harness.layout.snapshot.height == drawerLayoutDrawerBarHeight &&
                  harness.layout.snapshot[.velocity].toggleSize == 16 &&
                  harness.layout.snapshot[.automation].toggleSize == 16 &&
                  harness.layout.snapshot[.velocity].handleHeight == 0 &&
                  harness.layout.snapshot[.voiceChanges].bodyHeight == 0,
                  cppID: drawerLayoutFocusID,
                  message: "hiding the last visible section requests the roll while the bar and its toggles stay without any body or handle")

    let unavailable = drawerLayoutMakeDrawerHarness()
    unavailable.apply {
        $0.attachPage(drawerLayoutDrawerStubPage(kind: .velocity, url: drawerLayoutDrawerVelocityUrl,
                                     policy: drawerLayoutDrawerStubPolicy(divisor: 6), harness: unavailable))
    }
    unavailable.apply {
        $0.attachPage(drawerLayoutDrawerStubPage(kind: .automation, url: drawerLayoutDrawerAutomationUrl,
                                     policy: drawerLayoutDrawerStubPolicy(), harness: unavailable))
    }
    unavailable.apply {
        $0.restorePreferences(velocityVisible: 1, velocityHeight: 0, automationVisible: 1,
                              automationHeight: 0, voiceChangesVisible: -1, voiceChangesHeight: 0,
                              activePage: DrawerSectionKind.voiceChanges.rawValue)
    }
    let skipped = unavailable.apply { $0.toggleSection(.velocity, drawerOwnsFocus: true) }
    report.expect(skipped.focusRequest?.target == DrawerSectionKind.automation.rawValue &&
                  unavailable.layout.activePage == .velocity,
                  cppID: drawerLayoutFocusID,
                  message: "a request never targets a kind that is not available and visible")

    let retargeted = drawerLayoutMakeStoredDrawerHarness().harness
    retargeted.apply {
        $0.setSectionVisible(.voiceChanges, visible: false, drawerOwnsFocus: false)
    }
    let retarget = retargeted.apply { $0.toggleSection(.voiceChanges, drawerOwnsFocus: true) }
    report.expect(retarget.focusRequest?.target == DrawerSectionKind.voiceChanges.rawValue &&
                  retarget.focusRequest?.revision == 1 &&
                  retarget.cancelledSections == [.automation],
                  cppID: drawerLayoutFocusID,
                  message: "an active-page change requests the new active visible section in the same transition")
}

@MainActor
func drawerLayoutCheckDrawerCancellation(_ report: CheckReport) {
    let stored = drawerLayoutMakeStoredDrawerHarness()
    let harness = stored.harness
    let pages = stored.pages
    let preHideHeight = harness.layout.snapshot.height

    let hidden = harness.apply {
        $0.setSectionVisible(.velocity, visible: false, drawerOwnsFocus: false)
    }
    report.expect(hidden.cancelledSections == [.velocity] && hidden.published &&
                  pages[.velocity]!.cancelCount == 1 &&
                  pages[.voiceChanges]!.cancelCount == 0 && pages[.automation]!.cancelCount == 0 &&
                  harness.trace.kinds == [.velocity] &&
                  pages[.velocity]!.publishedHeightsAtCancel == [preHideHeight],
                  cppID: drawerLayoutCancelID,
                  message: "a transition cancels exactly the kind it hides, inside the call and before the caller sees the new publication")

    harness.trace.reset()
    let moved = harness.apply { $0.toggleSection(.voiceChanges, drawerOwnsFocus: false) }
    report.expect(moved.cancelledSections == [.voiceChanges, .automation] &&
                  harness.trace.kinds == [.voiceChanges, .automation] &&
                  moved.activePagePreference == .voiceChanges &&
                  pages[.voiceChanges]!.cancelCount == 1 && pages[.automation]!.cancelCount == 1,
                  cppID: drawerLayoutCancelID,
                  message: "one transition cancels its hidden kind and the kind losing the active slot, in stack order")

    harness.trace.reset()
    let fanOut = harness.apply { $0.cancelInteractions() }
    report.expect(pages[.velocity]!.cancelCount == 2 && pages[.voiceChanges]!.cancelCount == 2 &&
                  pages[.automation]!.cancelCount == 2 &&
                  Set(harness.trace.kinds) == Set(DrawerSectionKind.allCases) &&
                  harness.trace.kinds.count == 3,
                  cppID: drawerLayoutCancelID,
                  message: "global cancellation fans out to every attached page once, including hidden kinds")
    drawerLayoutExpectNoDrawerRecords(report, cppID: drawerLayoutCancelID, fanOut,
                          message: "global cancellation records no preference change")

    let heightBefore = harness.layout.storedBodyHeight(.automation)
    let hostChange = harness.apply {
        $0.configureHost(hostWidth: drawerLayoutDrawerHostWidth, hostHeight: 320,
                         gutterWidth: drawerLayoutDrawerGutterWidth)
    }
    let metricChange = harness.apply { $0.configureMetrics(drawerLayoutDrawerMetrics()) }
    let unrelated = harness.apply { $0.setSectionBodyHeight(.automation, height: 90) }
    report.expect(hostChange.cancelledSections.isEmpty && metricChange.cancelledSections.isEmpty &&
                  unrelated.cancelledSections.isEmpty && pages[.automation]!.cancelCount == 2 &&
                  harness.layout.storedBodyHeight(.automation) == 90 && heightBefore == 100,
                  cppID: drawerLayoutCancelID,
                  message: "host, metric and height changes cancel nothing again")

    let resizing = drawerLayoutMakeStoredDrawerHarness()
    resizing.harness.apply { $0.beginResize(.voiceChanges) }
    resizing.harness.apply { $0.applyResize(.voiceChanges, delta: 20) }
    resizing.harness.apply { $0.cancelInteractions() }
    report.expect(resizing.harness.layout.resizeKind == nil &&
                  resizing.pages[.voiceChanges]!.cancelCount == 1 &&
                  resizing.pages[.velocity]!.cancelCount == 1 &&
                  resizing.harness.layout.storedBodyHeight(.voiceChanges) == 70,
                  cppID: drawerLayoutCancelID,
                  message: "global cancellation ends a live resize session and cancels every page in the same call")

    let detached = harness.apply { $0.detachPage(pages[.velocity]!) }
    report.expect(detached.cancelledSections == [.velocity] &&
                  pages[.velocity]!.cancelCount == 3 &&
                  !harness.layout.isAvailable(.velocity),
                  cppID: drawerLayoutCancelID,
                  message: "detaching cancels its own page exactly once and drops the attachment")
    drawerLayoutExpectNoDrawerRecords(report, cppID: drawerLayoutCancelID, detached,
                          message: "detachment records no preference change")
}

@MainActor
func drawerLayoutCheckDrawerRestoreAndPreferenceRecords(_ report: CheckReport) {
    let harness = drawerLayoutMakeDrawerHarness()
    let pages = drawerLayoutAttachDrawerPages(harness)
    let restored = harness.apply {
        $0.restorePreferences(velocityVisible: 1, velocityHeight: 120, automationVisible: 1,
                              automationHeight: 0, voiceChangesVisible: 1, voiceChangesHeight: 96,
                              activePage: DrawerSectionKind.voiceChanges.rawValue)
    }
    report.expect(restored.published && harness.layout.isVisible(.velocity) &&
                  harness.layout.isVisible(.automation) &&
                  harness.layout.isVisible(.voiceChanges) &&
                  harness.layout.storedBodyHeight(.velocity) == 120 &&
                  harness.layout.storedBodyHeight(.automation) == nil &&
                  harness.layout.storedBodyHeight(.voiceChanges) == 96 &&
                  harness.layout.activePage == .voiceChanges &&
                  harness.layout.snapshot.height ==
                      drawerLayoutDrawerBarHeight + 3 * drawerLayoutDrawerHandleHeight + 120 + 80 + 96 &&
                  harness.layout.snapshot[.automation].bodyHeight == 80,
                  cppID: drawerLayoutPersistenceID,
                  message: "restored values apply visibility, heights, active page and geometry in one publication")
    drawerLayoutExpectNoDrawerRecords(report, cppID: drawerLayoutPersistenceID, restored,
                          message: "restoring stored preferences writes nothing back")

    let absent = harness.apply {
        $0.restorePreferences(velocityVisible: -1, velocityHeight: 120, automationVisible: -1,
                              automationHeight: 0, voiceChangesVisible: -1, voiceChangesHeight: 96,
                              activePage: -1)
    }
    report.expect(!absent.published && absent.isEmpty, cppID: drawerLayoutPersistenceID,
                  message: "an absent-only restore publishes nothing")
    report.expect(harness.layout.isVisible(.velocity) && harness.layout.isVisible(.automation) &&
                  harness.layout.isVisible(.voiceChanges) &&
                  harness.layout.activePage == .voiceChanges, cppID: drawerLayoutPersistenceID,
                  message: "absent visibility and page values leave the current section state untouched")
    drawerLayoutExpectNoDrawerRecords(report, cppID: drawerLayoutPersistenceID, absent,
                          message: "an absent or invalid restore key records no preference change")

    let toggled = harness.apply { $0.toggleSection(.automation, drawerOwnsFocus: false) }
    report.expect(toggled.activePagePreference == .automation &&
                  toggled.sectionPreferences.count == 1 && toggled.published &&
                  harness.layout.activePage == .automation, cppID: drawerLayoutPersistenceID,
                  message: "an interactive toggle records its own visibility and the active-page slot")

    let suppressedPage = harness.apply { $0.toggleSection(.automation, drawerOwnsFocus: false) }
    report.expect(suppressedPage.activePagePreference == nil &&
                  suppressedPage.sectionPreferences.count == 1, cppID: drawerLayoutPersistenceID,
                  message: "an interactive call that does not move the active page records only the section preference")

    let hidden = harness.apply {
        $0.setSectionVisible(.velocity, visible: false, drawerOwnsFocus: false)
    }
    drawerLayoutExpectDrawerPreference(report, cppID: drawerLayoutPersistenceID, hidden, .velocity, visible: false,
                           storedBodyHeight: 120,
                           message: "an interactive hide records that kind visibility and stored height")

    let detached = harness.apply { $0.detachPage(pages[.voiceChanges]!) }
    let detachedToggle = harness.apply { $0.toggleSection(.voiceChanges, drawerOwnsFocus: false) }
    let detachedHeight = harness.apply { $0.setSectionBodyHeight(.voiceChanges, height: 40) }
    report.expect(detached.cancelledSections == [.voiceChanges] &&
                  detached.sectionPreferences.isEmpty &&
                  detached.activePagePreference == nil && !detachedToggle.published &&
                  !detachedHeight.published && detachedToggle.isEmpty && detachedHeight.isEmpty &&
                  harness.layout.storedBodyHeight(.voiceChanges) == 96,
                  cppID: drawerLayoutPersistenceID,
                  message: "an unavailable kind never has its keys written and keeps its stored preference")
}
