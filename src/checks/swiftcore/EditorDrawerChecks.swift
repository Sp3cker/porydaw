import PorydawApp

private let metricsID = "swiftcore/EditorDrawer::metricsAndKinds"
private let availabilityID = "swiftcore/EditorDrawer::noPageAndAvailability"
private let stackingID = "swiftcore/EditorDrawer::stackingAndToggleSlots"
private let visibilityID = "swiftcore/EditorDrawer::visibilityAndStoredHeights"
private let resizeID = "swiftcore/EditorDrawer::resizeClampsAndSessions"
private let spillID = "swiftcore/EditorDrawer::voiceChangesSpill"
private let clampID = "swiftcore/EditorDrawer::hostClampAndAllocation"
private let focusID = "swiftcore/EditorDrawer::focusRequests"
private let cancelID = "swiftcore/EditorDrawer::cancellationSetAndOrder"
private let persistenceID = "swiftcore/EditorDrawer::restoreAndPreferenceRecords"

// Hand-derived from the two pushed facts base font 13 and application line
// spacing 16: bar 22, handle 4, minimum body 44, reserve 130, inset 3, step 7.
private let drawerHostWidth = 800
private let drawerHostHeight = 400
private let drawerGutterWidth = 56
private let drawerBarHeight = 22
private let drawerHandleHeight = 4
private let drawerMinimumBody = 44
private let drawerResizeStep = 7
private let drawerVelocityUrl = "file:///drawer/velocity.qml"
private let drawerVoiceChangesUrl = "file:///drawer/voice-changes.qml"
private let drawerAutomationUrl = "file:///drawer/automation.qml"

/// Cancellation order observed through the pages themselves: every page appends
/// its kind when the container cancels it.
@MainActor
private final class DrawerCancelTrace {
    private(set) var kinds: [DrawerSectionKind] = []

    func record(_ kind: DrawerSectionKind) { kinds.append(kind) }

    func reset() { kinds.removeAll() }
}

/// Owns the layout the way the presenter does: the caller-visible publication is
/// replaced only after an operation returns, so a page callback still observes the
/// publication that preceded the transition.
@MainActor
private final class DrawerHarness {
    private(set) var layout = EditorDrawerLayout()
    let trace = DrawerCancelTrace()

    @discardableResult
    func apply(_ operation: (inout EditorDrawerLayout) -> EditorDrawerChangeSet)
        -> EditorDrawerChangeSet
    {
        var working = layout
        let change = operation(&working)
        layout = working
        return change
    }
}

@MainActor
private final class DrawerStubPage: EditorDrawerPage {
    let sectionKind: DrawerSectionKind
    let contentUrl: String
    let bodyPolicy: EditorDrawerBodyPolicy

    private(set) var cancelCount = 0
    private(set) var publishedHeightsAtCancel: [Int] = []
    /// This stub owns no gesture of its own: layout and cancellation are what
    /// these checks exercise, so it reports no interaction.
    var interactionActive: Bool { false }

    private let harness: DrawerHarness

    init(kind: DrawerSectionKind, url: String, policy: EditorDrawerBodyPolicy,
         harness: DrawerHarness)
    {
        sectionKind = kind
        contentUrl = url
        bodyPolicy = policy
        self.harness = harness
    }

    func cancelSectionInteraction() {
        cancelCount += 1
        publishedHeightsAtCancel.append(harness.layout.snapshot.height)
        harness.trace.record(sectionKind)
    }
}

/// Test-owned page policy: a default body height bounded by the container's
/// piano-roll reserve, exactly like the production automation default.
private func drawerStubPolicy(declaredMaximum: Int? = nil,
                              divisor: Int = 5) -> EditorDrawerBodyPolicy
{
    EditorDrawerBodyPolicy(maximumBodyHeight: declaredMaximum) { hostHeight, metrics in
        min(max(hostHeight / divisor, metrics.minimumBody),
            metrics.maximumDefaultBodyHeight(hostHeight: hostHeight))
    }
}

@MainActor
private func drawerMetrics() -> EditorDrawerMetrics {
    EditorDrawerMetrics.resolve(baseFontPx: 13, appFontLineSpacing: 16)
}

@MainActor
private func makeDrawerHarness(hostHeight: Int = drawerHostHeight) -> DrawerHarness {
    let harness = DrawerHarness()
    harness.apply {
        $0.configureHost(hostWidth: drawerHostWidth, hostHeight: hostHeight,
                         gutterWidth: drawerGutterWidth)
    }
    harness.apply { $0.configureMetrics(drawerMetrics()) }
    return harness
}

@MainActor
private func makeDrawerPage(_ kind: DrawerSectionKind, harness: DrawerHarness) -> DrawerStubPage {
    switch kind {
    case .velocity:
        DrawerStubPage(kind: .velocity, url: drawerVelocityUrl,
                       policy: drawerStubPolicy(divisor: 6), harness: harness)
    case .voiceChanges:
        DrawerStubPage(kind: .voiceChanges, url: drawerVoiceChangesUrl,
                       policy: drawerStubPolicy(declaredMaximum: drawerMinimumBody * 5 / 2),
                       harness: harness)
    case .automation:
        DrawerStubPage(kind: .automation, url: drawerAutomationUrl,
                       policy: drawerStubPolicy(), harness: harness)
    }
}

@MainActor
private func attachDrawerPages(_ harness: DrawerHarness)
    -> [DrawerSectionKind: DrawerStubPage]
{
    var pages: [DrawerSectionKind: DrawerStubPage] = [:]
    for kind in DrawerSectionKind.stackOrder {
        let page = makeDrawerPage(kind, harness: harness)
        pages[kind] = page
        harness.apply { $0.attachPage(page) }
    }
    return pages
}

@MainActor
private func showEveryDrawerSection(_ harness: DrawerHarness) {
    for kind in DrawerSectionKind.stackOrder {
        harness.apply { $0.setSectionVisible(kind, visible: true, drawerOwnsFocus: false) }
    }
}

@MainActor
private func storeDrawerHeight(_ harness: DrawerHarness, _ kind: DrawerSectionKind, _ height: Int) {
    harness.apply { $0.setSectionBodyHeight(kind, height: height) }
}

/// Three attached, visible sections with stored heights 60 (velocity), 50 (voice
/// changes) and 100 (automations).
@MainActor
private func makeStoredDrawerHarness(hostHeight: Int = drawerHostHeight)
    -> (harness: DrawerHarness, pages: [DrawerSectionKind: DrawerStubPage])
{
    let harness = makeDrawerHarness(hostHeight: hostHeight)
    let pages = attachDrawerPages(harness)
    showEveryDrawerSection(harness)
    storeDrawerHeight(harness, .velocity, 60)
    storeDrawerHeight(harness, .voiceChanges, 50)
    storeDrawerHeight(harness, .automation, 100)
    return (harness, pages)
}

@MainActor
private func expectDrawerBody(_ report: CheckReport, cppID: String, message: String,
                              _ geometry: EditorDrawerSectionGeometry,
                              x: Int, y: Int, width: Int, height: Int)
{
    report.expect(geometry.bodyX == x && geometry.bodyY == y && geometry.bodyWidth == width &&
                  geometry.bodyHeight == height, cppID: cppID, message: message)
}

@MainActor
private func expectDrawerHandle(_ report: CheckReport, cppID: String, message: String,
                                _ geometry: EditorDrawerSectionGeometry,
                                _ body: EditorDrawerSectionGeometry,
                                y: Int, height: Int)
{
    report.expect(geometry.handleY == y && geometry.handleHeight == height &&
                  geometry.bodyX == body.bodyX && geometry.bodyWidth == body.bodyWidth,
                  cppID: cppID, message: message)
}

@MainActor
private func expectDrawerToggle(_ report: CheckReport, cppID: String, message: String,
                                _ geometry: EditorDrawerSectionGeometry,
                                x: Int, y: Int, size: Int)
{
    report.expect(geometry.toggleX == x && geometry.toggleY == y && geometry.toggleSize == size,
                  cppID: cppID, message: message)
}

@MainActor
private func expectDrawerPreference(_ report: CheckReport, cppID: String,
                                    _ change: EditorDrawerChangeSet,
                                    _ kind: DrawerSectionKind, visible: Bool,
                                    storedBodyHeight: Int?, message: String)
{
    report.expect(change.sectionPreferences.contains {
        $0.kind == kind && $0.visible == visible && $0.storedBodyHeight == storedBodyHeight
    }, cppID: cppID, message: message)
}

@MainActor
private func expectNoDrawerRecords(_ report: CheckReport, cppID: String,
                                   _ change: EditorDrawerChangeSet, message: String)
{
    report.expect(change.sectionPreferences.isEmpty && change.activePagePreference == nil,
                  cppID: cppID, message: message)
}

@MainActor
func runEditorDrawerChecks(_ report: CheckReport) {
    checkDrawerMetricsAndKinds(report)
    checkDrawerNoPageAndAvailability(report)
    checkDrawerStackingAndToggles(report)
    checkDrawerVisibilityAndStoredHeights(report)
    checkDrawerResizeClampsAndSessions(report)
    checkDrawerVoiceChangesSpill(report)
    checkDrawerHostClampAndAllocation(report)
    checkDrawerFocusRequests(report)
    checkDrawerCancellation(report)
    checkDrawerRestoreAndPreferenceRecords(report)
}

@MainActor
private func checkDrawerMetricsAndKinds(_ report: CheckReport) {
    let metrics = drawerMetrics()
    report.expectEqual(
        EditorDrawerMetrics(barHeight: drawerBarHeight, handleHeight: drawerHandleHeight,
                            minimumBody: drawerMinimumBody, pianoRollReserve: 130,
                            toggleInset: 3, resizeStep: drawerResizeStep, pixel: 1),
        metrics, cppID: metricsID,
        what: "resolved metrics derive the production bar row, handle, body floor, reserve, inset, step and hairline")
    report.expectEqual(
        6, EditorDrawerMetrics.resolve(baseFontPx: 13, appFontLineSpacing: -8).barHeight,
        cppID: metricsID,
        what: "a negative application line spacing does not shrink the bar below its own padding")
    report.expectEqual(270, metrics.maximumDefaultBodyHeight(hostHeight: 400), cppID: metricsID,
                       what: "the piano-roll reserve bounds a default body height")
    report.expectEqual(173, metrics.maximumDefaultBodyHeight(hostHeight: 173), cppID: metricsID,
                       what: "a host shorter than reserve plus floor keeps the whole host height")
    report.expectEqual(44, metrics.maximumDefaultBodyHeight(hostHeight: 174), cppID: metricsID,
                       what: "the reserve bound meets the body floor exactly at its boundary")

    report.expect(DrawerSectionKind.automation.rawValue == 0 &&
                  DrawerSectionKind.velocity.rawValue == 1 &&
                  DrawerSectionKind.voiceChanges.rawValue == 2 &&
                  DrawerSectionKind.stackOrder == [.velocity, .voiceChanges, .automation] &&
                  DrawerSectionKind.toggleOrder == [.voiceChanges, .automation, .velocity],
                  cppID: metricsID,
                  message: "section identities keep production raw values and the fixed stack and toggle orders")
    report.expect(DrawerSectionKind.allCases.map(\.name) == ["automations", "velocity", "voiceChanges"] &&
                  DrawerSectionKind.allCases.map(\.keyName) == ["automation", "velocity", "voiceChanges"] &&
                  DrawerSectionKind.automation.iconResource == "qrc:/icons/automation.svg" &&
                  DrawerSectionKind.velocity.iconResource == "qrc:/icons/velocity.svg" &&
                  DrawerSectionKind.voiceChanges.iconResource == "qrc:/icons/flat-music.svg",
                  cppID: metricsID,
                  message: "preference key names and toggle icon resources follow the historical formats")
}

@MainActor
private func checkDrawerNoPageAndAvailability(_ report: CheckReport) {
    let harness = makeDrawerHarness()
    let empty = harness.layout.snapshot
    report.expect(empty.height == 0 && !empty.barVisible && empty.plotOrigin == drawerGutterWidth &&
                  empty.plotWidth == drawerHostWidth - drawerGutterWidth &&
                  empty.barWidth == 0 && empty.barHeight == 0, cppID: availabilityID,
                  message: "a container with no attached page contributes zero height and no bar")
    for kind in DrawerSectionKind.allCases {
        let geometry = empty[kind]
        report.expect(!geometry.available && geometry.contentUrl.isEmpty &&
                      geometry.bodyWidth == 0 && geometry.bodyHeight == 0 &&
                      geometry.handleHeight == 0 && geometry.toggleSize == 0,
                      cppID: availabilityID,
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
                  cppID: availabilityID,
                  message: "restored section intent is retained as stored preference while no page is attached")
    expectNoDrawerRecords(report, cppID: availabilityID, restored,
                          message: "restoring stored preferences records no preference change")

    let velocity = DrawerStubPage(kind: .velocity, url: drawerVelocityUrl,
                                  policy: drawerStubPolicy(divisor: 6), harness: harness)
    let attached = harness.apply { $0.attachPage(velocity) }
    report.expect(attached.published && harness.layout.isAvailable(.velocity) &&
                  attached.snapshot[.velocity].contentUrl == drawerVelocityUrl &&
                  attached.snapshot[.velocity].bodyHeight == 220 &&
                  attached.snapshot[.velocity].available && attached.snapshot[.velocity].visible &&
                  attached.snapshot.height == drawerBarHeight + drawerHandleHeight + 220,
                  cppID: availabilityID,
                  message: "attaching a page turns a stored visible section into visible content in the same publication")

    let duplicate = harness.apply { $0.attachPage(velocity) }
    report.expect(!duplicate.published && duplicate.isEmpty &&
                  harness.layout.attachedPage(.velocity) === velocity &&
                  duplicate.snapshot.height == drawerBarHeight + drawerHandleHeight + 220,
                  cppID: availabilityID,
                  message: "a kind that already holds a page rejects a second attach and publishes nothing")

    let emptyUrl = DrawerStubPage(kind: .voiceChanges, url: "", policy: drawerStubPolicy(),
                                  harness: harness)
    let rejected = harness.apply { $0.attachPage(emptyUrl) }
    report.expect(!rejected.published && rejected.isEmpty &&
                  !harness.layout.isAvailable(.voiceChanges) &&
                  harness.layout.attachedPage(.voiceChanges) == nil &&
                  rejected.snapshot.height == drawerBarHeight + drawerHandleHeight + 220,
                  cppID: availabilityID,
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
                  cppID: availabilityID,
                  message: "visibility, height and resize calls are ignored for a kind with no attached page")

    let detached = harness.apply { $0.detachPage(velocity) }
    report.expect(detached.published && !harness.layout.isAvailable(.velocity) &&
                  harness.layout.attachedPage(.velocity) == nil &&
                  harness.layout.isVisible(.velocity) &&
                  harness.layout.storedBodyHeight(.velocity) == 220 &&
                  detached.snapshot.height == 0 && detached.cancelledSections == [.velocity] &&
                  velocity.cancelCount == 1 && velocity.publishedHeightsAtCancel == [246],
                  cppID: availabilityID,
                  message: "detaching cancels its page synchronously and drops its controls while stored visibility and height survive")
    expectNoDrawerRecords(report, cppID: availabilityID, detached,
                          message: "detaching records no preference change")
}

@MainActor
private func checkDrawerStackingAndToggles(_ report: CheckReport) {
    let stored = makeStoredDrawerHarness()
    let snapshot = stored.harness.layout.snapshot
    report.expect(snapshot.height == drawerBarHeight + 3 * drawerHandleHeight + 60 + 50 + 100 &&
                  snapshot.barVisible && snapshot.plotOrigin == drawerGutterWidth &&
                  snapshot.plotWidth == drawerHostWidth - drawerGutterWidth,
                  cppID: stackingID,
                  message: "three visible sections stack their bodies, handles and bar into one container height")

    let velocity = snapshot[.velocity]
    let voiceChanges = snapshot[.voiceChanges]
    let automation = snapshot[.automation]
    expectDrawerBody(report, cppID: stackingID,
                     message: "velocity takes the top body slot at the full host width",
                     velocity, x: 0, y: drawerHandleHeight, width: drawerHostWidth, height: 60)
    expectDrawerHandle(report, cppID: stackingID,
                       message: "the velocity handle sits directly above its body",
                       velocity, velocity, y: 0, height: drawerHandleHeight)
    expectDrawerBody(report, cppID: stackingID,
                     message: "voice changes follow velocity below their own handle",
                     voiceChanges, x: 0, y: drawerHandleHeight + 60 + drawerHandleHeight,
                     width: drawerHostWidth, height: 50)
    expectDrawerHandle(report, cppID: stackingID,
                       message: "the voice-change handle sits directly above its body",
                       voiceChanges, voiceChanges, y: drawerHandleHeight + 60,
                       height: drawerHandleHeight)
    expectDrawerBody(report, cppID: stackingID,
                     message: "automations follow voice changes below their own handle",
                     automation, x: 0,
                     y: voiceChanges.bodyY + voiceChanges.bodyHeight + drawerHandleHeight,
                     width: drawerHostWidth, height: 100)
    report.expect(snapshot.barX == 0 && snapshot.barY == snapshot.height - drawerBarHeight &&
                  snapshot.barWidth == drawerHostWidth && snapshot.barHeight == drawerBarHeight &&
                  snapshot.barY == automation.bodyY + automation.bodyHeight,
                  cppID: stackingID,
                  message: "the bar spans the host width as the last row, directly below the lowest body")

    let buttonSize = drawerBarHeight - 2 * 3
    report.expect(buttonSize == 16 && velocity.toggleSize == buttonSize &&
                  voiceChanges.toggleSize == buttonSize && automation.toggleSize == buttonSize,
                  cppID: stackingID,
                  message: "toggle buttons take the production size for the resolved bar row")
    expectDrawerToggle(report, cppID: stackingID,
                       message: "voice changes occupy the first production toggle slot",
                       voiceChanges, x: 1, y: snapshot.barY + 3, size: buttonSize)
    expectDrawerToggle(report, cppID: stackingID,
                       message: "automations occupy the second production toggle slot",
                       automation, x: 1 + buttonSize + 3, y: snapshot.barY + 3, size: buttonSize)
    expectDrawerToggle(report, cppID: stackingID,
                       message: "velocity occupies the third production toggle slot",
                       velocity, x: 1 + 2 * (buttonSize + 3), y: snapshot.barY + 3, size: buttonSize)

    let slots = makeStoredDrawerHarness()
    let detached = slots.harness.apply { $0.detachPage(slots.pages[.voiceChanges]!) }
    let afterDetach = slots.harness.layout.snapshot
    report.expect(detached.published && afterDetach[.automation].toggleX == 1 + buttonSize + 3 &&
                  afterDetach[.velocity].toggleX == 1 + 2 * (buttonSize + 3) &&
                  afterDetach[.voiceChanges].toggleSize == 0 &&
                  afterDetach[.voiceChanges].contentUrl.isEmpty,
                  cppID: stackingID,
                  message: "detaching one kind leaves the surviving toggle slots and their controls unmoved")
}

@MainActor
private func checkDrawerVisibilityAndStoredHeights(_ report: CheckReport) {
    let harness = makeStoredDrawerHarness().harness
    let hidden = harness.apply {
        $0.setSectionVisible(.automation, visible: false, drawerOwnsFocus: false)
    }
    let hiddenGeometry = harness.layout.snapshot[.automation]
    report.expect(hidden.published && harness.layout.storedBodyHeight(.automation) == 100 &&
                  harness.layout.snapshot.height ==
                      drawerBarHeight + 2 * drawerHandleHeight + 60 + 50 &&
                  hiddenGeometry.bodyHeight == 0 && hiddenGeometry.handleHeight == 0 &&
                  hiddenGeometry.available && !hiddenGeometry.visible &&
                  hiddenGeometry.contentUrl == drawerAutomationUrl &&
                  hiddenGeometry.toggleSize == 16 &&
                  hiddenGeometry.toggleY == harness.layout.snapshot.barY + 3,
                  cppID: visibilityID,
                  message: "hiding a section releases its body and handle while its toggle, URL and stored height stay")
    expectDrawerPreference(report, cppID: visibilityID, hidden, .automation, visible: false,
                           storedBodyHeight: 100,
                           message: "an interactive hide records the kind visibility and stored height")

    let shown = harness.apply {
        $0.setSectionVisible(.automation, visible: true, drawerOwnsFocus: false)
    }
    report.expect(shown.published && harness.layout.snapshot.height ==
                      drawerBarHeight + 3 * drawerHandleHeight + 60 + 50 + 100 &&
                      harness.layout.snapshot[.automation].bodyHeight == 100,
                  cppID: visibilityID,
                  message: "re-showing a hidden section restores its stored body height")

    let equalVisibility = harness.apply {
        $0.setSectionVisible(.velocity, visible: true, drawerOwnsFocus: true)
    }
    let equalHeight = harness.apply { $0.setSectionBodyHeight(.automation, height: 100) }
    let zeroDirection = harness.apply { $0.adjustResizeHandle(.automation, direction: 0) }
    report.expect(!equalVisibility.published && equalVisibility.isEmpty &&
                  equalVisibility.focusRequest == nil && !equalHeight.published &&
                  equalHeight.isEmpty && !zeroDirection.published && zeroDirection.isEmpty,
                  cppID: visibilityID,
                  message: "equal visibility and height setters publish nothing and request no focus")

    let toggled = harness.apply { $0.toggleSection(.velocity, drawerOwnsFocus: false) }
    report.expect(toggled.published && !harness.layout.isVisible(.velocity) &&
                  harness.layout.storedBodyHeight(.velocity) == 60 &&
                  harness.layout.activePage == .velocity &&
                  harness.layout.snapshot.height ==
                      drawerBarHeight + 2 * drawerHandleHeight + 50 + 100 &&
                  toggled.activePagePreference == .velocity,
                  cppID: visibilityID,
                  message: "toggling hides the section, keeps its stored height, moves the active page and records both")

    let restoredHeight = harness.apply { $0.toggleSection(.velocity, drawerOwnsFocus: false) }
    report.expect(restoredHeight.published && harness.layout.isVisible(.velocity) &&
                  harness.layout.snapshot[.velocity].bodyHeight == 60 &&
                  restoredHeight.activePagePreference == nil &&
                  restoredHeight.sectionPreferences.count == 1,
                  cppID: visibilityID,
                  message: "re-showing through the toggle restores the height and records no page change")

    let unset = harness.apply { $0.setSectionBodyHeight(.automation, height: 0) }
    report.expect(unset.published && harness.layout.storedBodyHeight(.automation) == nil &&
                  harness.layout.snapshot[.automation].bodyHeight == 80,
                  cppID: visibilityID,
                  message: "a height below one maps to the unset marker and the page default takes over")
    expectDrawerPreference(report, cppID: visibilityID, unset, .automation, visible: true,
                           storedBodyHeight: nil,
                           message: "an unset height is recorded as the unset marker")

    let floored = harness.apply { $0.setSectionBodyHeight(.velocity, height: 20) }
    report.expect(floored.published && harness.layout.storedBodyHeight(.velocity) == 20 &&
                  harness.layout.snapshot[.velocity].bodyHeight == drawerMinimumBody,
                  cppID: visibilityID,
                  message: "a drawn body never falls below the font-relative minimum body")
}

@MainActor
private func checkDrawerResizeClampsAndSessions(_ report: CheckReport) {
    let harness = makeStoredDrawerHarness().harness
    harness.apply { $0.beginResize(.automation) }
    report.expect(harness.layout.resizeKind == .automation, cppID: resizeID,
                  message: "beginning a resize claims the session for its kind")

    let crossKind = harness.apply { $0.applyResize(.velocity, delta: 10) }
    let crossEnd = harness.apply { $0.endResize(.velocity) }
    report.expect(!crossKind.published && !crossEnd.published && crossKind.isEmpty &&
                  harness.layout.resizeKind == .automation &&
                  harness.layout.storedBodyHeight(.velocity) == 60,
                  cppID: resizeID,
                  message: "a resize session belongs to one kind and ignores other kinds")

    let grown = harness.apply { $0.applyResize(.automation, delta: 30.4) }
    report.expect(grown.published && harness.layout.storedBodyHeight(.automation) == 130 &&
                  harness.layout.snapshot[.automation].bodyHeight == 130,
                  cppID: resizeID,
                  message: "a positive drag delta grows the body by the rounded delta, above the reserve bound")
    expectNoDrawerRecords(report, cppID: resizeID, grown,
                          message: "an applied drag step records no preference change of its own")

    let ended = harness.apply { $0.endResize(.automation) }
    report.expect(harness.layout.resizeKind == nil &&
                  harness.layout.storedBodyHeight(.automation) == 130 &&
                  ended.sectionPreferences.count == 1, cppID: resizeID,
                  message: "ending the resize records the changed section preference once")
    expectDrawerPreference(report, cppID: resizeID, ended, .automation, visible: true,
                           storedBodyHeight: 130,
                           message: "end records the resized kind visibility and stored height")

    let sessionless = harness.apply { $0.applyResize(.automation, delta: 5) }
    let sessionlessEnd = harness.apply { $0.endResize(.automation) }
    report.expect(!sessionless.published && !sessionlessEnd.published &&
                  harness.layout.storedBodyHeight(.automation) == 130,
                  cppID: resizeID,
                  message: "apply and end without a live session are ignored")

    harness.apply { $0.beginResize(.automation) }
    let shrunk = harness.apply { $0.applyResize(.automation, delta: -1_000) }
    report.expect(shrunk.published &&
                  harness.layout.storedBodyHeight(.automation) == drawerMinimumBody,
                  cppID: resizeID,
                  message: "a shrink clamps at the minimum body height")
    let returned = harness.apply { $0.applyResize(.automation, delta: 0) }
    report.expect(returned.published && harness.layout.storedBodyHeight(.automation) == 130,
                  cppID: resizeID,
                  message: "returning to the drag-start height restores the original stored height")

    let unsetReturn = makeStoredDrawerHarness().harness
    unsetReturn.apply { $0.setSectionBodyHeight(.automation, height: 0) }
    unsetReturn.apply { $0.beginResize(.automation) }
    unsetReturn.apply { $0.applyResize(.automation, delta: 25) }
    let returnedToUnset = unsetReturn.apply { $0.applyResize(.automation, delta: 0) }
    report.expect(returnedToUnset.published &&
                  unsetReturn.layout.storedBodyHeight(.automation) == nil &&
                  unsetReturn.layout.snapshot[.automation].bodyHeight == 80,
                  cppID: resizeID,
                  message: "returning to the drag start restores the unset marker, not a concrete height")

    let available = makeStoredDrawerHarness().harness
    available.apply { $0.beginResize(.velocity) }
    let clamped = available.apply { $0.applyResize(.velocity, delta: 1_000) }
    report.expect(clamped.published && available.layout.storedBodyHeight(.velocity) == 216 &&
                  available.layout.snapshot[.velocity].bodyHeight == 216 &&
                  available.layout.snapshot.height == drawerHostHeight,
                  cppID: resizeID,
                  message: "the available-height clamp fills the host exactly and never overflows it")

    let declared = makeStoredDrawerHarness().harness
    declared.apply { $0.setSectionVisible(.automation, visible: false, drawerOwnsFocus: false) }
    declared.apply { $0.beginResize(.voiceChanges) }
    let cappedResize = declared.apply { $0.applyResize(.voiceChanges, delta: 1_000) }
    report.expect(cappedResize.published &&
                  declared.layout.storedBodyHeight(.voiceChanges) == 110 &&
                  declared.layout.snapshot[.voiceChanges].bodyHeight == 110,
                  cppID: resizeID,
                  message: "a page-declared maximum applies after the available-height clamp without a spill partner")

    let cancelled = makeStoredDrawerHarness().harness
    cancelled.apply { $0.beginResize(.voiceChanges) }
    cancelled.apply { $0.applyResize(.voiceChanges, delta: 40) }
    let cancelChange = cancelled.apply { $0.cancelResize() }
    report.expect(!cancelChange.published && cancelChange.isEmpty &&
                  cancelled.layout.resizeKind == nil &&
                  cancelled.layout.storedBodyHeight(.voiceChanges) == 90 &&
                  cancelled.layout.snapshot[.voiceChanges].bodyHeight == 90,
                  cppID: resizeID,
                  message: "cancelling a resize drops the session, keeps the applied height and records nothing")

    let interrupted = makeStoredDrawerHarness().harness
    interrupted.apply { $0.beginResize(.voiceChanges) }
    interrupted.apply { $0.applyResize(.voiceChanges, delta: 20) }
    interrupted.apply { $0.cancelInteractions() }
    report.expect(interrupted.layout.resizeKind == nil &&
                  interrupted.layout.storedBodyHeight(.voiceChanges) == 70,
                  cppID: resizeID,
                  message: "global cancellation drops a live resize session and keeps the applied height")

    let stepped = makeStoredDrawerHarness().harness
    let step = stepped.apply { $0.adjustResizeHandle(.automation, direction: 1) }
    report.expect(step.published &&
                  stepped.layout.storedBodyHeight(.automation) == 100 + drawerResizeStep &&
                  stepped.layout.resizeKind == nil, cppID: resizeID,
                  message: "a handle step applies one resize step through the resize path and ends its own session")
    expectDrawerPreference(report, cppID: resizeID, step, .automation, visible: true,
                           storedBodyHeight: 107,
                           message: "a handle step records the changed section preference")

    let flooredStep = makeStoredDrawerHarness().harness
    flooredStep.apply { $0.setSectionBodyHeight(.automation, height: drawerMinimumBody) }
    let floorStep = flooredStep.apply { $0.adjustResizeHandle(.automation, direction: -1) }
    report.expect(!floorStep.published && floorStep.isEmpty &&
                  flooredStep.layout.storedBodyHeight(.automation) == drawerMinimumBody,
                  cppID: resizeID,
                  message: "a handle step that resolves to the drag start publishes nothing")
}

@MainActor
private func checkDrawerVoiceChangesSpill(_ report: CheckReport) {
    let harness = makeStoredDrawerHarness().harness
    harness.apply { $0.beginResize(.voiceChanges) }
    let spilled = harness.apply { $0.applyResize(.voiceChanges, delta: 90) }
    report.expect(spilled.published && harness.layout.storedBodyHeight(.voiceChanges) == 110 &&
                  harness.layout.storedBodyHeight(.automation) == 130 &&
                  harness.layout.snapshot[.automation].bodyHeight == 130 &&
                  harness.layout.snapshot.height ==
                      drawerBarHeight + 3 * drawerHandleHeight + 60 + 110 + 130,
                  cppID: spillID,
                  message: "a voice-change drag past its declared maximum moves the automations stored height by the excess")

    let stationary = harness.apply { $0.applyResize(.voiceChanges, delta: 90) }
    report.expect(!stationary.published && harness.layout.storedBodyHeight(.automation) == 130,
                  cppID: spillID,
                  message: "a stationary pointer cannot add the same spill twice")

    let spilledEnd = harness.apply { $0.endResize(.voiceChanges) }
    report.expect(spilledEnd.sectionPreferences.count == 2 &&
                  spilledEnd.sectionPreferences.contains {
                      $0.kind == .voiceChanges && $0.storedBodyHeight == 110
                  } &&
                  spilledEnd.sectionPreferences.contains {
                      $0.kind == .automation && $0.storedBodyHeight == 130
                  } && harness.layout.resizeKind == nil,
                  cppID: spillID,
                  message: "ending a spilled resize records both changed kinds")

    let reverted = makeStoredDrawerHarness().harness
    reverted.apply { $0.beginResize(.voiceChanges) }
    reverted.apply { $0.applyResize(.voiceChanges, delta: 90) }
    let returned = reverted.apply { $0.applyResize(.voiceChanges, delta: 0) }
    report.expect(returned.published &&
                  reverted.layout.storedBodyHeight(.voiceChanges) == 50 &&
                  reverted.layout.storedBodyHeight(.automation) == 100 &&
                  reverted.layout.snapshot.height ==
                      drawerBarHeight + 3 * drawerHandleHeight + 60 + 50 + 100,
                  cppID: spillID,
                  message: "returning to the drag start restores both original stored heights")

    let crowded = makeStoredDrawerHarness(hostHeight: 200).harness
    crowded.apply { $0.beginResize(.voiceChanges) }
    let floored = crowded.apply { $0.applyResize(.voiceChanges, delta: 200) }
    report.expect(floored.published &&
                  crowded.layout.storedBodyHeight(.voiceChanges) == 106 &&
                  crowded.layout.storedBodyHeight(.automation) == drawerMinimumBody,
                  cppID: spillID,
                  message: "spilled automations stop at the minimum body when the available height is exhausted")

    let unspilled = makeStoredDrawerHarness().harness
    unspilled.apply { $0.setSectionVisible(.automation, visible: false, drawerOwnsFocus: false) }
    unspilled.apply { $0.beginResize(.voiceChanges) }
    let withoutPartner = unspilled.apply { $0.applyResize(.voiceChanges, delta: 90) }
    report.expect(withoutPartner.published &&
                  unspilled.layout.storedBodyHeight(.voiceChanges) == 110 &&
                  unspilled.layout.storedBodyHeight(.automation) == 100,
                  cppID: spillID,
                  message: "a voice-change drag without a visible automations partner keeps the automations height")

    let uncapped = makeStoredDrawerHarness().harness
    uncapped.apply { $0.beginResize(.velocity) }
    let velocityGrowth = uncapped.apply { $0.applyResize(.velocity, delta: 30) }
    report.expect(velocityGrowth.published &&
                  uncapped.layout.storedBodyHeight(.velocity) == 90 &&
                  uncapped.layout.storedBodyHeight(.automation) == 100,
                  cppID: spillID,
                  message: "a kind with no declared maximum never spills into the automations section")
}

@MainActor
private func checkDrawerHostClampAndAllocation(_ report: CheckReport) {
    let harness = makeStoredDrawerHarness().harness
    let shrunk = harness.apply {
        $0.configureHost(hostWidth: drawerHostWidth, hostHeight: 120,
                         gutterWidth: drawerGutterWidth)
    }
    let snapshot = harness.layout.snapshot
    report.expect(shrunk.published && snapshot.height == 120 && snapshot.barY == 98 &&
                  harness.layout.storedBodyHeight(.velocity) == 60 &&
                  harness.layout.storedBodyHeight(.voiceChanges) == 50 &&
                  harness.layout.storedBodyHeight(.automation) == 100,
                  cppID: clampID,
                  message: "a host shrink re-clamps the container without rewriting stored heights")
    report.expect(snapshot[.voiceChanges].bodyHeight == 50 &&
                  snapshot[.automation].bodyHeight == 36 &&
                  snapshot[.velocity].bodyHeight == 0 &&
                  snapshot[.velocity].handleHeight == drawerHandleHeight,
                  cppID: clampID,
                  message: "the clamped allocation fills voice changes first, automations second and velocity with the remainder")
    report.expect(snapshot[.automation].bodyY ==
                      snapshot[.velocity].bodyY + snapshot[.velocity].bodyHeight +
                      snapshot[.voiceChanges].handleHeight + snapshot[.voiceChanges].bodyHeight +
                      drawerHandleHeight &&
                  snapshot.barY == snapshot[.automation].bodyY + snapshot[.automation].bodyHeight,
                  cppID: clampID,
                  message: "a constrained container keeps every drawn rectangle ordered and non-negative")

    let reserved = makeDrawerHarness()
    reserved.apply {
        $0.attachPage(DrawerStubPage(kind: .automation, url: drawerAutomationUrl,
                                     policy: drawerStubPolicy(), harness: reserved))
    }
    reserved.apply { $0.setSectionBodyHeight(.automation, height: 350) }
    report.expect(reserved.layout.snapshot.height == drawerBarHeight + drawerHandleHeight + 350 &&
                  reserved.layout.snapshot[.automation].bodyHeight == 350,
                  cppID: clampID,
                  message: "the piano-roll reserve never caps a stored body or the aggregate height")

    reserved.apply { $0.beginResize(.automation) }
    let grown = reserved.apply { $0.applyResize(.automation, delta: 30) }
    report.expect(grown.published && reserved.layout.storedBodyHeight(.automation) == 374 &&
                  reserved.layout.snapshot.height == drawerHostHeight,
                  cppID: clampID,
                  message: "the reserve never caps a resize, and the aggregate may fill the host exactly")

    let defaults = makeDrawerHarness()
    defaults.apply {
        $0.attachPage(DrawerStubPage(kind: .automation, url: drawerAutomationUrl,
                                     policy: drawerStubPolicy(), harness: defaults))
    }
    report.expect(defaults.layout.snapshot[.automation].bodyHeight == 80 &&
                  defaults.layout.snapshot.height == drawerBarHeight + drawerHandleHeight + 80,
                  cppID: clampID,
                  message: "a page default is bounded by the reserve through maximumDefaultBodyHeight")
    defaults.apply {
        $0.configureHost(hostWidth: drawerHostWidth, hostHeight: 100,
                         gutterWidth: drawerGutterWidth)
    }
    report.expect(defaults.layout.snapshot[.automation].bodyHeight == drawerMinimumBody &&
                  defaults.layout.snapshot.height ==
                      drawerBarHeight + drawerHandleHeight + drawerMinimumBody,
                  cppID: clampID,
                  message: "a short host keeps the default body at its minimum instead of the reserve bound")
}

@MainActor
private func checkDrawerFocusRequests(_ report: CheckReport) {
    let harness = makeStoredDrawerHarness().harness
    let hiddenActive = harness.apply { $0.toggleSection(.automation, drawerOwnsFocus: true) }
    report.expect(hiddenActive.focusRequest?.target == DrawerSectionKind.velocity.rawValue &&
                  hiddenActive.focusRequest?.revision == 1 && hiddenActive.published &&
                  harness.layout.activePage == .automation,
                  cppID: focusID,
                  message: "hiding the active section requests focus for the first remaining visible section")

    let unobserved = harness.apply {
        $0.setSectionVisible(.voiceChanges, visible: false, drawerOwnsFocus: false)
    }
    report.expect(unobserved.focusRequest == nil &&
                  unobserved.cancelledSections == [.voiceChanges] &&
                  !harness.layout.isVisible(.voiceChanges),
                  cppID: focusID,
                  message: "a transition that does not own focus cancels content but publishes no focus request")

    let observed = harness.apply {
        $0.setSectionVisible(.voiceChanges, visible: true, drawerOwnsFocus: true)
    }
    report.expect(observed.focusRequest?.target == DrawerSectionKind.velocity.rawValue &&
                  observed.focusRequest?.revision == 2, cppID: focusID,
                  message: "focus revisions advance monotonically for real requests only")
    report.expect(observed.focusRequest?.target != DrawerSectionKind.voiceChanges.rawValue,
                  cppID: focusID,
                  message: "a request prefers the active visible section over the section just shown")

    let noTransition = harness.apply {
        $0.setSectionVisible(.voiceChanges, visible: true, drawerOwnsFocus: true)
    }
    report.expect(noTransition.focusRequest == nil && !noTransition.published &&
                  noTransition.isEmpty, cppID: focusID,
                  message: "an unchanged visibility transition publishes no focus request")

    harness.apply { $0.setSectionVisible(.velocity, visible: false, drawerOwnsFocus: false) }
    harness.apply { $0.setSectionVisible(.voiceChanges, visible: false, drawerOwnsFocus: false) }
    harness.apply { $0.setSectionVisible(.automation, visible: false, drawerOwnsFocus: false) }
    let fullHide = harness.apply {
        $0.setSectionVisible(.automation, visible: false, drawerOwnsFocus: true)
    }
    report.expect(fullHide.focusRequest == nil && fullHide.isEmpty, cppID: focusID,
                  message: "hiding an already hidden section is no transition and requests no focus")

    let shownAgain = harness.apply {
        $0.setSectionVisible(.voiceChanges, visible: true, drawerOwnsFocus: true)
    }
    report.expect(shownAgain.focusRequest?.target == DrawerSectionKind.voiceChanges.rawValue,
                  cppID: focusID,
                  message: "showing a section with the drawer focused targets that visible section")

    let last = harness.apply {
        $0.setSectionVisible(.voiceChanges, visible: false, drawerOwnsFocus: true)
    }
    report.expect(last.focusRequest?.target == -1 && harness.layout.snapshot.barVisible &&
                  harness.layout.snapshot.height == drawerBarHeight &&
                  harness.layout.snapshot[.velocity].toggleSize == 16 &&
                  harness.layout.snapshot[.automation].toggleSize == 16 &&
                  harness.layout.snapshot[.velocity].handleHeight == 0 &&
                  harness.layout.snapshot[.voiceChanges].bodyHeight == 0,
                  cppID: focusID,
                  message: "hiding the last visible section requests the roll while the bar and its toggles stay without any body or handle")

    let unavailable = makeDrawerHarness()
    unavailable.apply {
        $0.attachPage(DrawerStubPage(kind: .velocity, url: drawerVelocityUrl,
                                     policy: drawerStubPolicy(divisor: 6), harness: unavailable))
    }
    unavailable.apply {
        $0.attachPage(DrawerStubPage(kind: .automation, url: drawerAutomationUrl,
                                     policy: drawerStubPolicy(), harness: unavailable))
    }
    unavailable.apply {
        $0.restorePreferences(velocityVisible: 1, velocityHeight: 0, automationVisible: 1,
                              automationHeight: 0, voiceChangesVisible: -1, voiceChangesHeight: 0,
                              activePage: DrawerSectionKind.voiceChanges.rawValue)
    }
    let skipped = unavailable.apply { $0.toggleSection(.velocity, drawerOwnsFocus: true) }
    report.expect(skipped.focusRequest?.target == DrawerSectionKind.automation.rawValue &&
                  unavailable.layout.activePage == .velocity,
                  cppID: focusID,
                  message: "a request never targets a kind that is not available and visible")

    let retargeted = makeStoredDrawerHarness().harness
    retargeted.apply {
        $0.setSectionVisible(.voiceChanges, visible: false, drawerOwnsFocus: false)
    }
    let retarget = retargeted.apply { $0.toggleSection(.voiceChanges, drawerOwnsFocus: true) }
    report.expect(retarget.focusRequest?.target == DrawerSectionKind.voiceChanges.rawValue &&
                  retarget.focusRequest?.revision == 1 &&
                  retarget.cancelledSections == [.automation],
                  cppID: focusID,
                  message: "an active-page change requests the new active visible section in the same transition")
}

@MainActor
private func checkDrawerCancellation(_ report: CheckReport) {
    let stored = makeStoredDrawerHarness()
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
                  cppID: cancelID,
                  message: "a transition cancels exactly the kind it hides, inside the call and before the caller sees the new publication")

    harness.trace.reset()
    let moved = harness.apply { $0.toggleSection(.voiceChanges, drawerOwnsFocus: false) }
    report.expect(moved.cancelledSections == [.voiceChanges, .automation] &&
                  harness.trace.kinds == [.voiceChanges, .automation] &&
                  moved.activePagePreference == .voiceChanges &&
                  pages[.voiceChanges]!.cancelCount == 1 && pages[.automation]!.cancelCount == 1,
                  cppID: cancelID,
                  message: "one transition cancels its hidden kind and the kind losing the active slot, in stack order")

    harness.trace.reset()
    let fanOut = harness.apply { $0.cancelInteractions() }
    report.expect(pages[.velocity]!.cancelCount == 2 && pages[.voiceChanges]!.cancelCount == 2 &&
                  pages[.automation]!.cancelCount == 2 &&
                  Set(harness.trace.kinds) == Set(DrawerSectionKind.allCases) &&
                  harness.trace.kinds.count == 3,
                  cppID: cancelID,
                  message: "global cancellation fans out to every attached page once, including hidden kinds")
    expectNoDrawerRecords(report, cppID: cancelID, fanOut,
                          message: "global cancellation records no preference change")

    let heightBefore = harness.layout.storedBodyHeight(.automation)
    let hostChange = harness.apply {
        $0.configureHost(hostWidth: drawerHostWidth, hostHeight: 320,
                         gutterWidth: drawerGutterWidth)
    }
    let metricChange = harness.apply { $0.configureMetrics(drawerMetrics()) }
    let unrelated = harness.apply { $0.setSectionBodyHeight(.automation, height: 90) }
    report.expect(hostChange.cancelledSections.isEmpty && metricChange.cancelledSections.isEmpty &&
                  unrelated.cancelledSections.isEmpty && pages[.automation]!.cancelCount == 2 &&
                  harness.layout.storedBodyHeight(.automation) == 90 && heightBefore == 100,
                  cppID: cancelID,
                  message: "host, metric and height changes cancel nothing again")

    let resizing = makeStoredDrawerHarness()
    resizing.harness.apply { $0.beginResize(.voiceChanges) }
    resizing.harness.apply { $0.applyResize(.voiceChanges, delta: 20) }
    resizing.harness.apply { $0.cancelInteractions() }
    report.expect(resizing.harness.layout.resizeKind == nil &&
                  resizing.pages[.voiceChanges]!.cancelCount == 1 &&
                  resizing.pages[.velocity]!.cancelCount == 1 &&
                  resizing.harness.layout.storedBodyHeight(.voiceChanges) == 70,
                  cppID: cancelID,
                  message: "global cancellation ends a live resize session and cancels every page in the same call")

    let detached = harness.apply { $0.detachPage(pages[.velocity]!) }
    report.expect(detached.cancelledSections == [.velocity] &&
                  pages[.velocity]!.cancelCount == 3 &&
                  !harness.layout.isAvailable(.velocity),
                  cppID: cancelID,
                  message: "detaching cancels its own page exactly once and drops the attachment")
    expectNoDrawerRecords(report, cppID: cancelID, detached,
                          message: "detachment records no preference change")
}

@MainActor
private func checkDrawerRestoreAndPreferenceRecords(_ report: CheckReport) {
    let harness = makeDrawerHarness()
    let pages = attachDrawerPages(harness)
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
                      drawerBarHeight + 3 * drawerHandleHeight + 120 + 80 + 96 &&
                  harness.layout.snapshot[.automation].bodyHeight == 80,
                  cppID: persistenceID,
                  message: "restored values apply visibility, heights, active page and geometry in one publication")
    expectNoDrawerRecords(report, cppID: persistenceID, restored,
                          message: "restoring stored preferences writes nothing back")

    let absent = harness.apply {
        $0.restorePreferences(velocityVisible: -1, velocityHeight: 120, automationVisible: -1,
                              automationHeight: 0, voiceChangesVisible: -1, voiceChangesHeight: 96,
                              activePage: -1)
    }
    report.expect(!absent.published && absent.isEmpty, cppID: persistenceID,
                  message: "an absent-only restore publishes nothing")
    report.expect(harness.layout.isVisible(.velocity) && harness.layout.isVisible(.automation) &&
                  harness.layout.isVisible(.voiceChanges) &&
                  harness.layout.activePage == .voiceChanges, cppID: persistenceID,
                  message: "absent visibility and page values leave the current section state untouched")
    expectNoDrawerRecords(report, cppID: persistenceID, absent,
                          message: "an absent or invalid restore key records no preference change")

    let toggled = harness.apply { $0.toggleSection(.automation, drawerOwnsFocus: false) }
    report.expect(toggled.activePagePreference == .automation &&
                  toggled.sectionPreferences.count == 1 && toggled.published &&
                  harness.layout.activePage == .automation, cppID: persistenceID,
                  message: "an interactive toggle records its own visibility and the active-page slot")

    let suppressedPage = harness.apply { $0.toggleSection(.automation, drawerOwnsFocus: false) }
    report.expect(suppressedPage.activePagePreference == nil &&
                  suppressedPage.sectionPreferences.count == 1, cppID: persistenceID,
                  message: "an interactive call that does not move the active page records only the section preference")

    let hidden = harness.apply {
        $0.setSectionVisible(.velocity, visible: false, drawerOwnsFocus: false)
    }
    expectDrawerPreference(report, cppID: persistenceID, hidden, .velocity, visible: false,
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
                  cppID: persistenceID,
                  message: "an unavailable kind never has its keys written and keeps its stored preference")
}
