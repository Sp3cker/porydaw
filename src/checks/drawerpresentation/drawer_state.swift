@testable import PorydawApp

// Existing scenarios paired with drawer.cpp.
// Entry order remains in EditorDrawerChecks.swift.

@MainActor
func drawerLayoutCheckDrawerFocusRequests(_ report: CheckReport) {
    let harness = drawerLayoutMakeStoredDrawerHarness().harness
    let hiddenActive = harness.apply {
        $0.toggleSection(.automation, drawerOwnsFocus: true, pages: $1)
    }
    report.expect(hiddenActive.focusRequest?.target == DrawerSectionKind.velocity.rawValue &&
                  hiddenActive.focusRequest?.revision == 1 && hiddenActive.published &&
                  harness.layout.activePage == .automation,
                  cppID: drawerLayoutFocusID,
                  message: "hiding the active section requests focus for the first remaining visible section")

    let unobserved = harness.apply {
        $0.setSectionVisible(
            .voiceChanges, visible: false, drawerOwnsFocus: false, pages: $1)
    }
    report.expect(unobserved.focusRequest == nil &&
                  unobserved.cancelledSections == [.voiceChanges] &&
                  !harness.layout.isVisible(.voiceChanges),
                  cppID: drawerLayoutFocusID,
                  message: "a transition that does not own focus cancels content but publishes no focus request")

    let observed = harness.apply {
        $0.setSectionVisible(
            .voiceChanges, visible: true, drawerOwnsFocus: true, pages: $1)
    }
    report.expect(observed.focusRequest?.target == DrawerSectionKind.velocity.rawValue &&
                  observed.focusRequest?.revision == 2, cppID: drawerLayoutFocusID,
                  message: "focus revisions advance monotonically for real requests only")
    report.expect(observed.focusRequest?.target != DrawerSectionKind.voiceChanges.rawValue,
                  cppID: drawerLayoutFocusID,
                  message: "a request prefers the active visible section over the section just shown")

    let noTransition = harness.apply {
        $0.setSectionVisible(
            .voiceChanges, visible: true, drawerOwnsFocus: true, pages: $1)
    }
    report.expect(noTransition.focusRequest == nil && !noTransition.published &&
                  noTransition.isEmpty, cppID: drawerLayoutFocusID,
                  message: "an unchanged visibility transition publishes no focus request")

    harness.apply {
        $0.setSectionVisible(
            .velocity, visible: false, drawerOwnsFocus: false, pages: $1)
    }
    harness.apply {
        $0.setSectionVisible(
            .voiceChanges, visible: false, drawerOwnsFocus: false, pages: $1)
    }
    harness.apply {
        $0.setSectionVisible(
            .automation, visible: false, drawerOwnsFocus: false, pages: $1)
    }
    let fullHide = harness.apply {
        $0.setSectionVisible(
            .automation, visible: false, drawerOwnsFocus: true, pages: $1)
    }
    report.expect(fullHide.focusRequest == nil && fullHide.isEmpty, cppID: drawerLayoutFocusID,
                  message: "hiding an already hidden section is no transition and requests no focus")

    let shownAgain = harness.apply {
        $0.setSectionVisible(
            .voiceChanges, visible: true, drawerOwnsFocus: true, pages: $1)
    }
    report.expect(shownAgain.focusRequest?.target == DrawerSectionKind.voiceChanges.rawValue,
                  cppID: drawerLayoutFocusID,
                  message: "showing a section with the drawer focused targets that visible section")

    let last = harness.apply {
        $0.setSectionVisible(
            .voiceChanges, visible: false, drawerOwnsFocus: true, pages: $1)
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
    unavailable.attachPage(.velocity)
    unavailable.attachPage(.automation)
    unavailable.apply {
        $0.restorePreferences(
            velocityVisible: 1, velocityHeight: 0,
            automationVisible: 1, automationHeight: 0,
            voiceChangesVisible: -1, voiceChangesHeight: 0,
            activePage: DrawerSectionKind.voiceChanges.rawValue, pages: $1)
    }
    let skipped = unavailable.apply {
        $0.toggleSection(.velocity, drawerOwnsFocus: true, pages: $1)
    }
    report.expect(skipped.focusRequest?.target == DrawerSectionKind.automation.rawValue &&
                  unavailable.layout.activePage == .velocity,
                  cppID: drawerLayoutFocusID,
                  message: "a request never targets a kind that is not available and visible")

    let retargeted = drawerLayoutMakeStoredDrawerHarness().harness
    retargeted.apply {
        $0.setSectionVisible(
            .voiceChanges, visible: false, drawerOwnsFocus: false, pages: $1)
    }
    let retarget = retargeted.apply {
        $0.toggleSection(.voiceChanges, drawerOwnsFocus: true, pages: $1)
    }
    report.expect(retarget.focusRequest?.target == DrawerSectionKind.voiceChanges.rawValue &&
                  retarget.focusRequest?.revision == 1 &&
                  retarget.cancelledSections == [.automation],
                  cppID: drawerLayoutFocusID,
                  message: "an active-page change requests the new active visible section in the same transition")
}

@MainActor
func drawerLayoutCheckDrawerCancellation(_ report: CheckReport) {
    let harness = drawerLayoutMakeStoredDrawerHarness().harness

    let hidden = harness.apply {
        $0.setSectionVisible(
            .velocity, visible: false, drawerOwnsFocus: false, pages: $1)
    }
    report.expect(hidden.cancelledSections == [.velocity] && hidden.published,
                  cppID: drawerLayoutCancelID,
                  message: "a pure transition returns exactly the kind it hides")

    let moved = harness.apply {
        $0.toggleSection(.voiceChanges, drawerOwnsFocus: false, pages: $1)
    }
    report.expect(moved.cancelledSections == [.voiceChanges, .automation] &&
                  moved.activePagePreference == .voiceChanges,
                  cppID: drawerLayoutCancelID,
                  message: "hidden and active-losing cancellation effects use stack order")

    let fanOut = harness.apply { $0.cancelInteractions(pages: $1) }
    report.expect(fanOut.cancelledSections == [.automation],
                  cppID: drawerLayoutCancelID,
                  message: "global cancellation returns visible available kinds only")
    drawerLayoutExpectNoDrawerRecords(
        report, cppID: drawerLayoutCancelID, fanOut,
        message: "global cancellation records no preference change")

    let heightBefore = harness.layout.storedBodyHeight(.automation)
    let hostChange = harness.configure(
        hostWidth: drawerLayoutDrawerHostWidth, hostHeight: 320,
        gutterWidth: drawerLayoutDrawerGutterWidth, metrics: drawerLayoutDrawerMetrics())
    let metricChange = harness.configure(
        hostWidth: drawerLayoutDrawerHostWidth, hostHeight: 320,
        gutterWidth: drawerLayoutDrawerGutterWidth, metrics: drawerLayoutDrawerMetrics())
    let unrelated = harness.apply {
        $0.setSectionBodyHeight(.automation, height: 90, pages: $1)
    }
    report.expect(hostChange.cancelledSections.isEmpty &&
                  metricChange.cancelledSections.isEmpty &&
                  unrelated.cancelledSections.isEmpty &&
                  harness.layout.storedBodyHeight(.automation) == 90 && heightBefore == 100,
                  cppID: drawerLayoutCancelID,
                  message: "host, metric and height changes return no cancellation effects")

    let resizing = drawerLayoutMakeStoredDrawerHarness().harness
    resizing.apply { $0.beginResize(.voiceChanges, pages: $1) }
    resizing.apply { $0.applyResize(.voiceChanges, delta: 20, pages: $1) }
    let resizeCancel = resizing.apply { $0.cancelInteractions(pages: $1) }
    report.expect(resizing.layout.resizeKind == nil &&
                  resizing.layout.storedBodyHeight(.voiceChanges) == 70 &&
                  resizeCancel.cancelledSections ==
                      [.voiceChanges, .velocity, .automation],
                  cppID: drawerLayoutCancelID,
                  message: "global cancellation ends a live resize in native call order")

    let detached = harness.detachPage(.velocity)
    report.expect(detached.cancelledSections == [.velocity] &&
                  !harness.layout.isAvailable(.velocity),
                  cppID: drawerLayoutCancelID,
                  message: "detaching returns one effect and drops the value-only page facts")
    drawerLayoutExpectNoDrawerRecords(
        report, cppID: drawerLayoutCancelID, detached,
        message: "detachment records no preference change")

    // The adapter remains the one reference-based check: it executes ordered
    // effects against retained pages while the old published height is visible.
    let presenter = EditorDrawerPresenter()
    presenter.configureLayout(
        hostWidth: drawerLayoutDrawerHostWidth, hostHeight: drawerLayoutDrawerHostHeight,
        gutterWidth: drawerLayoutDrawerGutterWidth, fontPx: 13, appFontLineSpacing: 16)
    let trace = drawerLayoutDrawerCancelTrace()
    let velocity = drawerLayoutDrawerStubPage(
        kind: .velocity, url: drawerLayoutDrawerVelocityUrl,
        policy: drawerLayoutDrawerStubPolicy(divisor: 6), presenter: presenter, trace: trace)
    let voiceChanges = drawerLayoutDrawerStubPage(
        kind: .voiceChanges, url: drawerLayoutDrawerVoiceChangesUrl,
        policy: drawerLayoutDrawerStubPolicy(
            declaredMaximum: drawerLayoutDrawerMinimumBody * 5 / 2),
        presenter: presenter, trace: trace)
    let automation = drawerLayoutDrawerStubPage(
        kind: .automation, url: drawerLayoutDrawerAutomationUrl,
        policy: drawerLayoutDrawerStubPolicy(), presenter: presenter, trace: trace)
    presenter.attachSection(velocity)
    presenter.attachSection(voiceChanges)
    presenter.attachSection(automation)
    presenter.restoreStoredPreferences(
        velocityVisible: 1, velocityHeight: 60,
        automationVisible: 1, automationHeight: 100,
        voiceChangesVisible: 1, voiceChangesHeight: 50,
        activePage: DrawerSectionKind.automation.rawValue)

    let preHideHeight = presenter.height
    velocity.interactionActive = true
    report.expect(presenter.interactionActive, cppID: drawerLayoutCancelID,
                  message: "aggregate interaction activity is a synchronous page read")
    presenter.setSectionVisible(
        kind: DrawerSectionKind.velocity.rawValue, visible: false, drawerOwnsFocus: false)
    report.expect(trace.kinds == [.velocity] && velocity.cancelCount == 1 &&
                  velocity.publishedHeightsAtCancel == [preHideHeight] &&
                  !presenter.interactionActive,
                  cppID: drawerLayoutCancelID,
                  message: "the presenter cancels the hidden page before publishing its new height")

    trace.reset()
    presenter.toggleSection(
        kind: DrawerSectionKind.voiceChanges.rawValue, drawerOwnsFocus: false)
    report.expect(trace.kinds == [.voiceChanges, .automation] &&
                  voiceChanges.cancelCount == 1 && automation.cancelCount == 1,
                  cppID: drawerLayoutCancelID,
                  message: "the presenter executes transition effects in stack order")

    trace.reset()
    presenter.inputCancelled(reason: 0)
    report.expect(trace.kinds == [.automation] &&
                  velocity.cancelCount == 1 && voiceChanges.cancelCount == 1 &&
                  automation.cancelCount == 2,
                  cppID: drawerLayoutCancelID,
                  message: "the presenter fans global cancellation out to visible slots only")

    let impostor = drawerLayoutDrawerStubPage(
        kind: .velocity, url: drawerLayoutDrawerVelocityUrl,
        policy: drawerLayoutDrawerStubPolicy(divisor: 6))
    presenter.detachSection(impostor)
    let mismatchIgnored = velocity.cancelCount == 1 && presenter.velocitySection.available
    presenter.detachSection(velocity)
    report.expect(mismatchIgnored && velocity.cancelCount == 2 &&
                  !presenter.velocitySection.available,
                  cppID: drawerLayoutCancelID,
                  message: "detach validates identity, retains the matching page for cancellation, then clears its slot")
}

@MainActor
func drawerLayoutCheckDrawerRestoreAndPreferenceRecords(_ report: CheckReport) {
    let harness = drawerLayoutMakeDrawerHarness()
    drawerLayoutAttachDrawerPages(harness)
    let restored = harness.apply {
        $0.restorePreferences(
            velocityVisible: 1, velocityHeight: 120,
            automationVisible: 1, automationHeight: 0,
            voiceChangesVisible: 1, voiceChangesHeight: 96,
            activePage: DrawerSectionKind.voiceChanges.rawValue, pages: $1)
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
        $0.restorePreferences(
            velocityVisible: -1, velocityHeight: 120,
            automationVisible: -1, automationHeight: 0,
            voiceChangesVisible: -1, voiceChangesHeight: 96,
            activePage: -1, pages: $1)
    }
    report.expect(!absent.published && absent.isEmpty, cppID: drawerLayoutPersistenceID,
                  message: "an absent-only restore publishes nothing")
    report.expect(harness.layout.isVisible(.velocity) && harness.layout.isVisible(.automation) &&
                  harness.layout.isVisible(.voiceChanges) &&
                  harness.layout.activePage == .voiceChanges, cppID: drawerLayoutPersistenceID,
                  message: "absent visibility and page values leave the current section state untouched")
    drawerLayoutExpectNoDrawerRecords(report, cppID: drawerLayoutPersistenceID, absent,
                          message: "an absent or invalid restore key records no preference change")

    let toggled = harness.apply {
        $0.toggleSection(.automation, drawerOwnsFocus: false, pages: $1)
    }
    report.expect(toggled.activePagePreference == .automation &&
                  toggled.sectionPreferences.count == 1 && toggled.published &&
                  harness.layout.activePage == .automation, cppID: drawerLayoutPersistenceID,
                  message: "an interactive toggle records its own visibility and the active-page slot")

    let suppressedPage = harness.apply {
        $0.toggleSection(.automation, drawerOwnsFocus: false, pages: $1)
    }
    report.expect(suppressedPage.activePagePreference == nil &&
                  suppressedPage.sectionPreferences.count == 1, cppID: drawerLayoutPersistenceID,
                  message: "an interactive call that does not move the active page records only the section preference")

    let hidden = harness.apply {
        $0.setSectionVisible(
            .velocity, visible: false, drawerOwnsFocus: false, pages: $1)
    }
    drawerLayoutExpectDrawerPreference(report, cppID: drawerLayoutPersistenceID, hidden, .velocity, visible: false,
                           storedBodyHeight: 120,
                           message: "an interactive hide records that kind visibility and stored height")

    let detached = harness.detachPage(.voiceChanges)
    let detachedToggle = harness.apply {
        $0.toggleSection(.voiceChanges, drawerOwnsFocus: false, pages: $1)
    }
    let detachedHeight = harness.apply {
        $0.setSectionBodyHeight(.voiceChanges, height: 40, pages: $1)
    }
    report.expect(detached.cancelledSections == [.voiceChanges] &&
                  detached.sectionPreferences.isEmpty &&
                  detached.activePagePreference == nil && !detachedToggle.published &&
                  !detachedHeight.published && detachedToggle.isEmpty && detachedHeight.isEmpty &&
                  harness.layout.storedBodyHeight(.voiceChanges) == 96,
                  cppID: drawerLayoutPersistenceID,
                  message: "an unavailable kind never has its keys written and keeps its stored preference")
}
