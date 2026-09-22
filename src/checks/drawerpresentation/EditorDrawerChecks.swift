@testable import PorydawApp

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

// Hand-derived from base font 13 and application line spacing 16.
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

@MainActor
final class drawerLayoutDrawerCancelTrace {
    private(set) var kinds: [DrawerSectionKind] = []

    func record(_ kind: DrawerSectionKind) { kinds.append(kind) }
    func reset() { kinds.removeAll() }
}

/// Owns mutable layout state and the ordinary value facts supplied by each
/// scenario. It has no page objects or policy closures.
final class drawerLayoutDrawerHarness {
    private(set) var layout = EditorDrawerLayout()
    private(set) var pages = EditorDrawerPageFacts()

    @discardableResult
    func apply(_ operation: (inout EditorDrawerLayout, EditorDrawerPageFacts)
        -> EditorDrawerChangeSet) -> EditorDrawerChangeSet {
        let currentPages = pages
        return operation(&layout, currentPages)
    }

    @discardableResult
    func configure(hostWidth: Int, hostHeight: Int, gutterWidth: Int,
                   metrics: EditorDrawerMetrics,
                   pages: EditorDrawerPageFacts? = nil) -> EditorDrawerChangeSet {
        if let pages { self.pages = pages }
        return layout.configure(hostWidth: hostWidth, hostHeight: hostHeight,
                                gutterWidth: gutterWidth, metrics: metrics,
                                pages: self.pages)
    }

    @discardableResult
    func attachPage(_ kind: DrawerSectionKind) -> EditorDrawerChangeSet {
        guard pages[kind] == nil else { return layout.attachPage(pages: pages) }
        pages[kind] = drawerLayoutDrawerPageFact(
            kind, hostHeight: layout.hostHeight, metrics: layout.metrics)
        return layout.attachPage(pages: pages)
    }

    @discardableResult
    func detachPage(_ kind: DrawerSectionKind) -> EditorDrawerChangeSet {
        pages[kind] = nil
        return layout.detachPage(kind, pages: pages)
    }
}

struct drawerLayoutStoredDrawerHarness {
    let harness: drawerLayoutDrawerHarness
}

/// The only reference fixture: it verifies presenter-owned cancellation effects
/// and reads the presenter's still-published height from inside the callback.
@MainActor
final class drawerLayoutDrawerStubPage: EditorDrawerPage {
    let sectionKind: DrawerSectionKind
    let contentUrl: String
    let bodyPolicy: EditorDrawerBodyPolicy
    weak var presenter: EditorDrawerPresenter?
    var interactionActive = false
    private(set) var cancelCount = 0
    private(set) var publishedHeightsAtCancel: [Int] = []
    private let trace: drawerLayoutDrawerCancelTrace?

    init(kind: DrawerSectionKind, url: String, policy: EditorDrawerBodyPolicy,
         presenter: EditorDrawerPresenter? = nil,
         trace: drawerLayoutDrawerCancelTrace? = nil) {
        sectionKind = kind
        contentUrl = url
        bodyPolicy = policy
        self.presenter = presenter
        self.trace = trace
    }

    func cancelSectionInteraction() {
        cancelCount += 1
        publishedHeightsAtCancel.append(presenter?.height ?? -1)
        trace?.record(sectionKind)
        interactionActive = false
    }
}

func drawerLayoutDrawerStubPolicy(declaredMaximum: Int? = nil,
                                  divisor: Int = 5) -> EditorDrawerBodyPolicy {
    EditorDrawerBodyPolicy(maximumBodyHeight: declaredMaximum) { hostHeight, metrics in
        min(max(hostHeight / divisor, metrics.minimumBody),
            metrics.maximumDefaultBodyHeight(hostHeight: hostHeight))
    }
}

func drawerLayoutDrawerMetrics() -> EditorDrawerMetrics {
    EditorDrawerMetrics.resolve(baseFontPx: 13, appFontLineSpacing: 16)
}

func drawerLayoutDrawerUrl(_ kind: DrawerSectionKind) -> String {
    switch kind {
    case .velocity: return drawerLayoutDrawerVelocityUrl
    case .voiceChanges: return drawerLayoutDrawerVoiceChangesUrl
    case .automation: return drawerLayoutDrawerAutomationUrl
    }
}
func drawerLayoutDrawerPageFact(
    _ kind: DrawerSectionKind, hostHeight: Int = drawerLayoutDrawerHostHeight,
    metrics: EditorDrawerMetrics = drawerLayoutDrawerMetrics()
) -> EditorDrawerPageFacts.Page {
    let divisor = kind == .velocity ? 6 : 5
    let maximum = kind == .voiceChanges ? drawerLayoutDrawerMinimumBody * 5 / 2 : nil
    let preferred = min(max(hostHeight / divisor, metrics.minimumBody),
                        metrics.maximumDefaultBodyHeight(hostHeight: hostHeight))
    return EditorDrawerPageFacts.Page(
        resolvedContentUrl: drawerLayoutDrawerUrl(kind),
        preferredBodyHeight: preferred, maximumBodyHeight: maximum)
}

func drawerLayoutMakeDrawerHarness(
    hostHeight: Int = drawerLayoutDrawerHostHeight
) -> drawerLayoutDrawerHarness {
    let harness = drawerLayoutDrawerHarness()
    harness.configure(hostWidth: drawerLayoutDrawerHostWidth, hostHeight: hostHeight,
                      gutterWidth: drawerLayoutDrawerGutterWidth,
                      metrics: drawerLayoutDrawerMetrics())
    return harness
}

func drawerLayoutAttachDrawerPages(_ harness: drawerLayoutDrawerHarness) {
    for kind in DrawerSectionKind.stackOrder { harness.attachPage(kind) }
}

func drawerLayoutShowEveryDrawerSection(_ harness: drawerLayoutDrawerHarness) {
    for kind in DrawerSectionKind.stackOrder {
        harness.apply {
            $0.setSectionVisible(kind, visible: true, drawerOwnsFocus: false, pages: $1)
        }
    }
}

func drawerLayoutStoreDrawerHeight(_ harness: drawerLayoutDrawerHarness,
                                   _ kind: DrawerSectionKind, _ height: Int) {
    harness.apply { $0.setSectionBodyHeight(kind, height: height, pages: $1) }
}

func drawerLayoutMakeStoredDrawerHarness(
    hostHeight: Int = drawerLayoutDrawerHostHeight
) -> drawerLayoutStoredDrawerHarness {
    let harness = drawerLayoutMakeDrawerHarness(hostHeight: hostHeight)
    drawerLayoutAttachDrawerPages(harness)
    drawerLayoutShowEveryDrawerSection(harness)
    drawerLayoutStoreDrawerHeight(harness, .velocity, 60)
    drawerLayoutStoreDrawerHeight(harness, .voiceChanges, 50)
    drawerLayoutStoreDrawerHeight(harness, .automation, 100)
    return drawerLayoutStoredDrawerHarness(harness: harness)
}

func drawerLayoutExpectDrawerBody(_ report: CheckReport, cppID: String, message: String,
                                  _ geometry: EditorDrawerSectionGeometry,
                                  x: Int, y: Int, width: Int, height: Int) {
    report.expect(geometry.bodyX == x && geometry.bodyY == y && geometry.bodyWidth == width &&
                  geometry.bodyHeight == height, cppID: cppID, message: message)
}

func drawerLayoutExpectDrawerHandle(_ report: CheckReport, cppID: String, message: String,
                                    _ geometry: EditorDrawerSectionGeometry,
                                    _ body: EditorDrawerSectionGeometry,
                                    y: Int, height: Int) {
    report.expect(geometry.handleY == y && geometry.handleHeight == height &&
                  geometry.bodyX == body.bodyX && geometry.bodyWidth == body.bodyWidth,
                  cppID: cppID, message: message)
}

func drawerLayoutExpectDrawerToggle(_ report: CheckReport, cppID: String, message: String,
                                    _ geometry: EditorDrawerSectionGeometry,
                                    x: Int, y: Int, size: Int) {
    report.expect(geometry.toggleX == x && geometry.toggleY == y &&
                  geometry.toggleSize == size, cppID: cppID, message: message)
}

func drawerLayoutExpectDrawerPreference(_ report: CheckReport, cppID: String,
                                        _ change: EditorDrawerChangeSet,
                                        _ kind: DrawerSectionKind, visible: Bool,
                                        storedBodyHeight: Int?, message: String) {
    report.expect(change.sectionPreferences.contains {
        $0.kind == kind && $0.visible == visible && $0.storedBodyHeight == storedBodyHeight
    }, cppID: cppID, message: message)
}

func drawerLayoutExpectNoDrawerRecords(_ report: CheckReport, cppID: String,
                                       _ change: EditorDrawerChangeSet, message: String) {
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
}
