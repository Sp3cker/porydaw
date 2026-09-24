import PorydawApp

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

    let fresh = drawerLayoutMakeDrawerHarness()
    fresh.apply {
        $0.attachPage(drawerLayoutDrawerStubPage(kind: .velocity, url: drawerLayoutDrawerVelocityUrl,
                                     policy: drawerLayoutDrawerStubPolicy(divisor: 6), harness: fresh))
    }
    report.expect(!fresh.layout.isVisible(.velocity),
                  cppID: drawerLayoutAvailabilityID,
                  message: "an attached velocity section keeps its hidden default until restored or shown")
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

    let zeroed = harness.apply { $0.setSectionBodyHeight(.velocity, height: 0) }
    report.expect(zeroed.published && harness.layout.storedBodyHeight(.velocity) == nil &&
                  harness.layout.snapshot[.velocity].bodyHeight == 66,
                  cppID: drawerLayoutVisibilityID,
                  message: "a zero height clears the stored height and the page default takes over")
    drawerLayoutExpectDrawerPreference(report, cppID: drawerLayoutVisibilityID, zeroed, .velocity, visible: true,
                           storedBodyHeight: nil,
                           message: "a cleared height is recorded as the unset marker")
    harness.apply { $0.toggleSection(.velocity, drawerOwnsFocus: false) }
    let zeroedShown = harness.apply { $0.toggleSection(.velocity, drawerOwnsFocus: false) }
    report.expect(zeroedShown.published && harness.layout.isVisible(.velocity) &&
                  harness.layout.snapshot[.velocity].bodyHeight == 66,
                  cppID: drawerLayoutVisibilityID,
                  message: "re-showing a zeroed section restores the page default body, not the cleared height")

    harness.apply { $0.setSectionVisible(.velocity, visible: false, drawerOwnsFocus: false) }
    report.expect(harness.layout.snapshot.detentSize == 0,
                  cppID: drawerLayoutVisibilityID,
                  message: "a hidden velocity section publishes no detent")
    harness.apply { $0.setSectionVisible(.velocity, visible: true, drawerOwnsFocus: false) }
    let detent = harness.layout.snapshot
    report.expect(detent.detentSize == 16 && detent.detentX == 0 &&
                  detent.detentY == detent[.velocity].bodyY + detent[.velocity].bodyHeight - 16,
                  cppID: drawerLayoutVisibilityID,
                  message: "a shown velocity section returns the detent to the body's lower-left corner")

    harness.apply { $0.toggleSection(.velocity, drawerOwnsFocus: false) }
    harness.apply { $0.toggleSection(.voiceChanges, drawerOwnsFocus: false) }
    let collapsed = harness.apply { $0.toggleSection(.automation, drawerOwnsFocus: false) }
    report.expect(!harness.layout.isVisible(.velocity) && !harness.layout.isVisible(.voiceChanges) &&
                  !harness.layout.isVisible(.automation) &&
                  harness.layout.snapshot.height == drawerLayoutDrawerBarHeight &&
                  harness.layout.snapshot.barVisible &&
                  harness.layout.activePage == .automation &&
                  harness.layout.storedBodyHeight(.velocity) == nil &&
                  harness.layout.storedBodyHeight(.voiceChanges) == 50 &&
                  harness.layout.storedBodyHeight(.automation) == nil,
                  cppID: drawerLayoutVisibilityID,
                  message: "hiding every section leaves the bar row, keeps every stored height and the active page")
    report.expect(collapsed.activePagePreference == .automation,
                  cppID: drawerLayoutVisibilityID,
                  message: "hiding the last section records the active page it keeps")
    let reopened = harness.apply { $0.toggleSection(.automation, drawerOwnsFocus: false) }
    report.expect(reopened.published && harness.layout.isVisible(.automation) &&
                  harness.layout.snapshot[.automation].bodyHeight == 80,
                  cppID: drawerLayoutVisibilityID,
                  message: "re-showing after a collapse restores the default body for a cleared height")
    let voiceRestored = harness.apply { $0.toggleSection(.voiceChanges, drawerOwnsFocus: false) }
    report.expect(voiceRestored.published &&
                  harness.layout.snapshot[.voiceChanges].bodyHeight == 50,
                  cppID: drawerLayoutVisibilityID,
                  message: "re-showing after a collapse restores the retained stored height")

    let voiceHidden = harness.apply { $0.toggleSection(.voiceChanges, drawerOwnsFocus: false) }
    report.expect(voiceHidden.published && !harness.layout.isVisible(.voiceChanges) &&
                  harness.layout.storedBodyHeight(.voiceChanges) == 50,
                  cppID: drawerLayoutVisibilityID,
                  message: "toggling hides the voice-changes section and keeps its stored height")
    let voiceShown = harness.apply { $0.toggleSection(.voiceChanges, drawerOwnsFocus: false) }
    report.expect(voiceShown.published && harness.layout.isVisible(.voiceChanges) &&
                  harness.layout.snapshot[.voiceChanges].bodyHeight == 50,
                  cppID: drawerLayoutVisibilityID,
                  message: "re-showing the voice-changes section restores its stored height")
}
