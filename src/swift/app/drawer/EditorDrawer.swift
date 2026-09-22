import Foundation
import QtBridge

// MARK: - Page seam

/// A page's declared body sizing. The presenter re-reads this value and evaluates
/// the closure on every layout pass; the layout receives only the resulting facts.
public struct EditorDrawerBodyPolicy: Sendable {
    /// `nil` leaves the body unbounded by the page.
    public var maximumBodyHeight: Int?
    /// Default body height for the supplied host height and metrics.
    public var preferredBodyHeight: @Sendable (Int, EditorDrawerMetrics) -> Int

    public init(maximumBodyHeight: Int? = nil,
                preferredBodyHeight: @escaping @Sendable (Int, EditorDrawerMetrics) -> Int) {
        self.maximumBodyHeight = maximumBodyHeight
        self.preferredBodyHeight = preferredBodyHeight
    }
}

/// The container's page seam. A page must not retain the presenter.
@MainActor
public protocol EditorDrawerPage: AnyObject {
    var sectionKind: DrawerSectionKind { get }
    /// Non-empty QML URL, resolved once at attach and never re-pointed.
    var contentUrl: String { get }
    var bodyPolicy: EditorDrawerBodyPolicy { get }
    /// True while this page owns an interaction that follow-scroll would disrupt.
    var interactionActive: Bool { get }
    /// Ends this page's current interaction or gesture synchronously.
    func cancelSectionInteraction()
}

@MainActor
private struct EditorDrawerAttachedPage {
    let page: EditorDrawerPage
    let resolvedContentUrl: String
}

@MainActor
private struct EditorDrawerAttachedPages {
    var automation: EditorDrawerAttachedPage?
    var velocity: EditorDrawerAttachedPage?
    var voiceChanges: EditorDrawerAttachedPage?

    subscript(kind: DrawerSectionKind) -> EditorDrawerAttachedPage? {
        get {
            switch kind {
            case .automation: return automation
            case .velocity: return velocity
            case .voiceChanges: return voiceChanges
            }
        }
        set {
            switch kind {
            case .automation: automation = newValue
            case .velocity: velocity = newValue
            case .voiceChanges: voiceChanges = newValue
            }
        }
    }
}

// MARK: - QML publication

/// One section's published values as a stable bridged object.
@MainActor
@QtBridgeable
public final class EditorDrawerSectionState {
    public var available: Bool = false
    public var visible: Bool = false
    public var contentUrl: String = ""
    public var bodyX: Int = 0
    public var bodyY: Int = 0
    public var bodyWidth: Int = 0
    public var bodyHeight: Int = 0
    public var handleY: Int = 0
    public var handleHeight: Int = 0
    public var toggleX: Int = 0
    public var toggleY: Int = 0
    public var toggleSize: Int = 0

    public init() {}

    @QtIgnored
    func apply(_ geometry: borrowing EditorDrawerSectionGeometry) {
        if available != geometry.available { available = geometry.available }
        if visible != geometry.visible { visible = geometry.visible }
        if contentUrl != geometry.contentUrl { contentUrl = geometry.contentUrl }
        if bodyX != geometry.bodyX { bodyX = geometry.bodyX }
        if bodyY != geometry.bodyY { bodyY = geometry.bodyY }
        if bodyWidth != geometry.bodyWidth { bodyWidth = geometry.bodyWidth }
        if bodyHeight != geometry.bodyHeight { bodyHeight = geometry.bodyHeight }
        if handleY != geometry.handleY { handleY = geometry.handleY }
        if handleHeight != geometry.handleHeight { handleHeight = geometry.handleHeight }
        if toggleX != geometry.toggleX { toggleX = geometry.toggleX }
        if toggleY != geometry.toggleY { toggleY = geometry.toggleY }
        if toggleSize != geometry.toggleSize { toggleSize = geometry.toggleSize }
    }
}

/// Qt adapter and effect runner for the pure `EditorDrawerLayout`.
@MainActor
@QtBridgeable
public final class EditorDrawerPresenter {
    public var height: Int = 0
    public var barVisible: Bool = false
    public var barX: Int = 0
    public var barY: Int = 0
    public var barWidth: Int = 0
    public var barHeight: Int = 0
    public var plotOrigin: Int = 0
    public var plotWidth: Int = 0
    public var detentX: Int = 0
    public var detentY: Int = 0
    public var detentSize: Int = 0
    public var detentIconInset: Double = 0
    /// Monotonic revision of the last executed focus request; `0` means none yet.
    public var focusRequest: Int = 0
    /// Section kind raw value, or `-1` for the roll.
    public var focusTarget: Int = -1

    @QtTracked public var automationSection: EditorDrawerSectionState = EditorDrawerSectionState()
    @QtTracked public var velocitySection: EditorDrawerSectionState = EditorDrawerSectionState()
    @QtTracked public var voiceChangesSection: EditorDrawerSectionState = EditorDrawerSectionState()

    private var layout = EditorDrawerLayout()
    private var attachedPages = EditorDrawerAttachedPages()
    private let unresolvedSection = EditorDrawerSectionState()
    private var publicationRevision = 0

    public init() {}

    /// The stable section state object for a kind raw value.
    public func section(kind: Int) -> EditorDrawerSectionState {
        guard let section = DrawerSectionKind(rawValue: kind) else { return unresolvedSection }
        switch section {
        case .automation: return automationSection
        case .velocity: return velocitySection
        case .voiceChanges: return voiceChangesSection
        }
    }

    /// Pushes host and font facts through one layout/publication pass.
    public func configureLayout(hostWidth: Int, hostHeight: Int, gutterWidth: Int,
                                fontPx: Double, appFontLineSpacing: Double) {
        let metrics = EditorDrawerMetrics.resolve(
            baseFontPx: fontPx, appFontLineSpacing: appFontLineSpacing)
        let pages = pageFacts(hostHeight: hostHeight, metrics: metrics)
        publish(layout.configure(hostWidth: hostWidth, hostHeight: hostHeight,
                                 gutterWidth: gutterWidth, metrics: metrics, pages: pages))
    }

    /// Applies one settings read without writing restored values back.
    public func restoreStoredPreferences(velocityVisible: Int, velocityHeight: Int,
                                         automationVisible: Int, automationHeight: Int,
                                         voiceChangesVisible: Int, voiceChangesHeight: Int,
                                         activePage: Int) {
        let pages = pageFacts()
        publish(layout.restorePreferences(
            velocityVisible: velocityVisible, velocityHeight: velocityHeight,
            automationVisible: automationVisible, automationHeight: automationHeight,
            voiceChangesVisible: voiceChangesVisible, voiceChangesHeight: voiceChangesHeight,
            activePage: activePage, pages: pages))
    }

    public func toggleSection(kind: Int, drawerOwnsFocus: Bool) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        let pages = pageFacts()
        publish(layout.toggleSection(
            section, drawerOwnsFocus: drawerOwnsFocus, pages: pages))
    }

    public func setSectionVisible(kind: Int, visible: Bool, drawerOwnsFocus: Bool) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        let pages = pageFacts()
        publish(layout.setSectionVisible(
            section, visible: visible, drawerOwnsFocus: drawerOwnsFocus, pages: pages))
    }

    public func setSectionBodyHeight(kind: Int, height: Int) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        let pages = pageFacts()
        publish(layout.setSectionBodyHeight(section, height: height, pages: pages))
    }

    public func beginResize(kind: Int) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        let pages = pageFacts()
        publish(layout.beginResize(section, pages: pages))
    }

    public func applyResize(kind: Int, delta: Double) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        let pages = pageFacts()
        publish(layout.applyResize(section, delta: delta, pages: pages))
    }

    public func endResize(kind: Int) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        let pages = pageFacts()
        publish(layout.endResize(section, pages: pages))
    }

    public func cancelResize() {
        publish(layout.cancelResize(pages: pageFacts()))
    }

    public func adjustResizeHandle(kind: Int, direction: Int) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        let pages = pageFacts()
        publish(layout.adjustResizeHandle(section, direction: direction, pages: pages))
    }

    /// Ends the chrome resize and every visible page interaction synchronously.
    public func inputCancelled(reason: Int) {
        publish(layout.cancelInteractions(pages: pageFacts()))
    }

    /// Aggregate interaction stays a synchronous adapter read, never layout state.
    @QtIgnored
    public var interactionActive: Bool {
        if layout.resizeKind != nil { return true }
        for kind in DrawerSectionKind.allCases
            where attachedPages[kind]?.page.interactionActive == true {
            return true
        }
        return false
    }

    @QtSignal public func drawerSectionPreferenceChanged(kind: Int, visible: Bool, height: Int)
    @QtSignal public func drawerActivePagePreferenceChanged(page: Int)

    /// Attaches one accepted page to its fixed kind slot.
    @QtIgnored
    public func attachSection(_ page: EditorDrawerPage) {
        let kind = page.sectionKind
        guard attachedPages[kind] == nil,
              let resolvedContentUrl = Self.resolveContentUrl(page.contentUrl) else {
            return
        }
        attachedPages[kind] = EditorDrawerAttachedPage(
            page: page, resolvedContentUrl: resolvedContentUrl)
        publish(layout.attachPage(pages: pageFacts()))
    }

    /// A mismatched detach is ignored. The matching page stays retained until its
    /// cancellation effect completes and the unavailable snapshot is published.
    @QtIgnored
    public func detachSection(_ page: EditorDrawerPage) {
        let kind = page.sectionKind
        guard let attached = attachedPages[kind], attached.page === page else { return }
        let remainingPages = pageFacts(excluding: kind)
        publish(layout.detachPage(kind, pages: remainingPages))
        attachedPages[kind] = nil
    }

    /// Re-reads each attached page policy for the applicable host and metrics.
    private func pageFacts(hostHeight: Int? = nil, metrics: EditorDrawerMetrics? = nil,
                           excluding excludedKind: DrawerSectionKind? = nil)
        -> EditorDrawerPageFacts {
        let effectiveHostHeight = hostHeight ?? layout.hostHeight
        let effectiveMetrics = metrics ?? layout.metrics
        var facts = EditorDrawerPageFacts()
        for kind in DrawerSectionKind.allCases where kind != excludedKind {
            guard let attached = attachedPages[kind] else { continue }
            let policy = attached.page.bodyPolicy
            facts[kind] = EditorDrawerPageFacts.Page(
                resolvedContentUrl: attached.resolvedContentUrl,
                preferredBodyHeight: policy.preferredBodyHeight(
                    effectiveHostHeight, effectiveMetrics),
                maximumBodyHeight: policy.maximumBodyHeight)
        }
        return facts
    }

    private func publish(_ change: consuming EditorDrawerChangeSet) {
        guard !change.isEmpty else { return }
        publicationRevision &+= 1
        let expectedRevision = publicationRevision
        if !change.cancelledSections.isEmpty {
            let cancellationPages = change.cancelledSections.compactMap {
                attachedPages[$0]?.page
            }
            // Callbacks see the old Qt values, while the reduced layout state is
            // already installed. A nested publication supersedes this snapshot.
            for page in cancellationPages { page.cancelSectionInteraction() }
        }
        guard publicationRevision == expectedRevision else { return }
        if change.published { apply(change.snapshot) }
        for preference in change.sectionPreferences {
            drawerSectionPreferenceChanged(kind: preference.kind.rawValue,
                                           visible: preference.visible,
                                           height: preference.storedBodyHeight ?? 0)
        }
        if let page = change.activePagePreference {
            drawerActivePagePreferenceChanged(page: page.rawValue)
        }
        // Target precedes revision so revision observers read the matching target.
        if let focus = change.focusRequest {
            if focusTarget != focus.target { focusTarget = focus.target }
            if focusRequest != focus.revision { focusRequest = focus.revision }
        }
    }

    private func apply(_ snapshot: borrowing EditorDrawerSnapshot) {
        if height != snapshot.height { height = snapshot.height }
        if barVisible != snapshot.barVisible { barVisible = snapshot.barVisible }
        if barX != snapshot.barX { barX = snapshot.barX }
        if barY != snapshot.barY { barY = snapshot.barY }
        if barWidth != snapshot.barWidth { barWidth = snapshot.barWidth }
        if barHeight != snapshot.barHeight { barHeight = snapshot.barHeight }
        if plotOrigin != snapshot.plotOrigin { plotOrigin = snapshot.plotOrigin }
        if plotWidth != snapshot.plotWidth { plotWidth = snapshot.plotWidth }
        automationSection.apply(snapshot.automation)
        if detentX != snapshot.detentX { detentX = snapshot.detentX }
        if detentY != snapshot.detentY { detentY = snapshot.detentY }
        if detentSize != snapshot.detentSize { detentSize = snapshot.detentSize }
        if detentIconInset != snapshot.detentIconInset {
            detentIconInset = snapshot.detentIconInset
        }
        velocitySection.apply(snapshot.velocity)
        voiceChangesSection.apply(snapshot.voiceChanges)
    }

    private static func resolveContentUrl(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return nil }
        return trimmed
    }
}
