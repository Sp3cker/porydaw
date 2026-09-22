import PorydawApp

// Existing scenarios paired with drawer.cpp.
// Entry order remains in EditorDrawerChecks.swift.

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
