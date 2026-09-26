import PorydawApp

let drawerLayoutMetricsID = "swiftcore/EditorDrawer::metricsAndKinds"
let drawerLayoutAvailabilityID = "swiftcore/EditorDrawer::noPageAndAvailability"
let drawerLayoutStackingID = "swiftcore/EditorDrawer::stackingAndToggleSlots"
let drawerLayoutVisibilityID = "swiftcore/EditorDrawer::visibilityAndStoredHeights"
let drawerLayoutResizeID = "swiftcore/EditorDrawer::resizeClampsAndSessions"
let drawerLayoutSpillID = "swiftcore/EditorDrawer::voiceChangesSpill"
let drawerLayoutClampID = "swiftcore/EditorDrawer::hostClampAndAllocation"
let drawerLayoutFocusID = "swiftcore/EditorDrawer::focusRequests"
let drawerLayoutCancelID = "swiftcore/EditorDrawer::cancellationSetAndOrder"
let drawerLayoutPersistenceID = "swiftcore/EditorDrawer::restoreAndPreferenceRecords"

// Hand-derived from the two pushed facts base font 13 and application line
// spacing 16: bar 22, handle 4, minimum body 44, reserve 130, inset 3, step 7.
let drawerLayoutDrawerHostWidth = 800
let drawerLayoutDrawerHostHeight = 400
let drawerLayoutDrawerGutterWidth = 56
let drawerLayoutDrawerBarHeight = 22
let drawerLayoutDrawerHandleHeight = 4
let drawerLayoutDrawerMinimumBody = 44
let drawerLayoutDrawerResizeStep = 7
let drawerLayoutDrawerVelocityUrl = "file:///drawer/velocity.qml"
let drawerLayoutDrawerVoiceChangesUrl = "file:///drawer/voice-changes.qml"
let drawerLayoutDrawerAutomationUrl = "file:///drawer/automation.qml"

/// Cancellation order observed through the pages themselves: every page appends
/// its kind when the container cancels it.
@MainActor
final class drawerLayoutDrawerCancelTrace {
    private(set) var kinds: [DrawerSectionKind] = []

    func record(_ kind: DrawerSectionKind) { kinds.append(kind) }

    func reset() { kinds.removeAll() }
}

/// Owns the layout the way the presenter does: the caller-visible publication is
/// replaced only after an operation returns, so a page callback still observes the
/// publication that preceded the transition.
@MainActor
final class drawerLayoutDrawerHarness {
    private(set) var layout = EditorDrawerLayout()
    let trace = drawerLayoutDrawerCancelTrace()

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
final class drawerLayoutDrawerStubPage: EditorDrawerPage {
    let sectionKind: DrawerSectionKind
    let contentUrl: String
    let bodyPolicy: EditorDrawerBodyPolicy

    private(set) var cancelCount = 0
    private(set) var publishedHeightsAtCancel: [Int] = []
    /// This stub owns no gesture of its own: layout and cancellation are what
    /// these checks exercise, so it reports no interaction.
    var interactionActive: Bool { false }

    private let harness: drawerLayoutDrawerHarness

    init(kind: DrawerSectionKind, url: String, policy: EditorDrawerBodyPolicy,
         harness: drawerLayoutDrawerHarness)
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
func drawerLayoutDrawerStubPolicy(declaredMaximum: Int? = nil,
                              divisor: Int = 5) -> EditorDrawerBodyPolicy
{
    EditorDrawerBodyPolicy(maximumBodyHeight: declaredMaximum) { hostHeight, metrics in
        min(max(hostHeight / divisor, metrics.minimumBody),
            metrics.maximumDefaultBodyHeight(hostHeight: hostHeight))
    }
}

@MainActor
func drawerLayoutDrawerMetrics() -> EditorDrawerMetrics {
    EditorDrawerMetrics.resolve(baseFontPx: 13, appFontLineSpacing: 16)
}

@MainActor
func drawerLayoutMakeDrawerHarness(hostHeight: Int = drawerLayoutDrawerHostHeight) -> drawerLayoutDrawerHarness {
    let harness = drawerLayoutDrawerHarness()
    harness.apply {
        $0.configureHost(hostWidth: drawerLayoutDrawerHostWidth, hostHeight: hostHeight,
                         gutterWidth: drawerLayoutDrawerGutterWidth)
    }
    harness.apply { $0.configureMetrics(drawerLayoutDrawerMetrics()) }
    return harness
}

@MainActor
func drawerLayoutMakeDrawerPage(_ kind: DrawerSectionKind, harness: drawerLayoutDrawerHarness) -> drawerLayoutDrawerStubPage {
    switch kind {
    case .velocity:
        drawerLayoutDrawerStubPage(kind: .velocity, url: drawerLayoutDrawerVelocityUrl,
                       policy: drawerLayoutDrawerStubPolicy(divisor: 6), harness: harness)
    case .voiceChanges:
        drawerLayoutDrawerStubPage(kind: .voiceChanges, url: drawerLayoutDrawerVoiceChangesUrl,
                       policy: drawerLayoutDrawerStubPolicy(declaredMaximum: drawerLayoutDrawerMinimumBody * 5 / 2),
                       harness: harness)
    case .automation:
        drawerLayoutDrawerStubPage(kind: .automation, url: drawerLayoutDrawerAutomationUrl,
                       policy: drawerLayoutDrawerStubPolicy(), harness: harness)
    }
}

@MainActor
func drawerLayoutAttachDrawerPages(_ harness: drawerLayoutDrawerHarness)
    -> [DrawerSectionKind: drawerLayoutDrawerStubPage]
{
    var pages: [DrawerSectionKind: drawerLayoutDrawerStubPage] = [:]
    for kind in DrawerSectionKind.stackOrder {
        let page = drawerLayoutMakeDrawerPage(kind, harness: harness)
        pages[kind] = page
        harness.apply { $0.attachPage(page) }
    }
    return pages
}

@MainActor
func drawerLayoutShowEveryDrawerSection(_ harness: drawerLayoutDrawerHarness) {
    for kind in DrawerSectionKind.stackOrder {
        harness.apply { $0.setSectionVisible(kind, visible: true, drawerOwnsFocus: false) }
    }
}

@MainActor
func drawerLayoutStoreDrawerHeight(_ harness: drawerLayoutDrawerHarness, _ kind: DrawerSectionKind, _ height: Int) {
    harness.apply { $0.setSectionBodyHeight(kind, height: height) }
}

/// Three attached, visible sections with stored heights 60 (velocity), 50 (voice
/// changes) and 100 (automations).
@MainActor
func drawerLayoutMakeStoredDrawerHarness(hostHeight: Int = drawerLayoutDrawerHostHeight)
    -> (harness: drawerLayoutDrawerHarness, pages: [DrawerSectionKind: drawerLayoutDrawerStubPage])
{
    let harness = drawerLayoutMakeDrawerHarness(hostHeight: hostHeight)
    let pages = drawerLayoutAttachDrawerPages(harness)
    drawerLayoutShowEveryDrawerSection(harness)
    drawerLayoutStoreDrawerHeight(harness, .velocity, 60)
    drawerLayoutStoreDrawerHeight(harness, .voiceChanges, 50)
    drawerLayoutStoreDrawerHeight(harness, .automation, 100)
    return (harness, pages)
}

@MainActor
func drawerLayoutExpectDrawerBody(_ report: CheckReport, cppID: String, message: String,
                              _ geometry: EditorDrawerSectionGeometry,
                              x: Int, y: Int, width: Int, height: Int)
{
    report.expect(geometry.bodyX == x && geometry.bodyY == y && geometry.bodyWidth == width &&
                  geometry.bodyHeight == height, cppID: cppID, message: message)
}

@MainActor
func drawerLayoutExpectDrawerHandle(_ report: CheckReport, cppID: String, message: String,
                                _ geometry: EditorDrawerSectionGeometry,
                                _ body: EditorDrawerSectionGeometry,
                                y: Int, height: Int)
{
    report.expect(geometry.handleY == y && geometry.handleHeight == height &&
                  geometry.bodyX == body.bodyX && geometry.bodyWidth == body.bodyWidth,
                  cppID: cppID, message: message)
}

@MainActor
func drawerLayoutExpectDrawerToggle(_ report: CheckReport, cppID: String, message: String,
                                _ geometry: EditorDrawerSectionGeometry,
                                x: Int, y: Int, size: Int)
{
    report.expect(geometry.toggleX == x && geometry.toggleY == y && geometry.toggleSize == size,
                  cppID: cppID, message: message)
}

@MainActor
func drawerLayoutExpectDrawerPreference(_ report: CheckReport, cppID: String,
                                    _ change: EditorDrawerChangeSet,
                                    _ kind: DrawerSectionKind, visible: Bool,
                                    storedBodyHeight: Int?, message: String)
{
    report.expect(change.sectionPreferences.contains {
        $0.kind == kind && $0.visible == visible && $0.storedBodyHeight == storedBodyHeight
    }, cppID: cppID, message: message)
}

@MainActor
func drawerLayoutExpectNoDrawerRecords(_ report: CheckReport, cppID: String,
                                   _ change: EditorDrawerChangeSet, message: String)
{
    report.expect(change.sectionPreferences.isEmpty && change.activePagePreference == nil,
                  cppID: cppID, message: message)
}

@MainActor
func runEditorDrawerChecks(_ report: CheckReport) {
    drawerLayoutCheckDrawerMetricsAndKinds(report)
    drawerLayoutCheckDrawerNoPageAndAvailability(report)
    drawerLayoutCheckDrawerStackingAndToggles(report)
    drawerLayoutCheckDrawerVisibilityAndStoredHeights(report)
    drawerLayoutCheckDrawerResizeClampsAndSessions(report)
    drawerLayoutCheckDrawerVoiceChangesSpill(report)
    drawerLayoutCheckDrawerHostClampAndAllocation(report)
    drawerLayoutCheckDrawerFocusRequests(report)
    drawerLayoutCheckDrawerCancellation(report)
    drawerLayoutCheckDrawerRestoreAndPreferenceRecords(report)
    runOtherEventsBandChecks(report)
}
