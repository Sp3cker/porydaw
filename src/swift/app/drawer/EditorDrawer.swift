import QtBridge

// MARK: - Page seam

/// A page's declared body sizing. Re-read on every layout pass; the page owns its
/// own default curve and its own maximum.
public struct EditorDrawerBodyPolicy: Sendable {
    /// `nil` leaves the body unbounded by the page.
    public var maximumBodyHeight: Int?
    /// Default body height for the pushed host height and metrics.
    public var preferredBodyHeight: @Sendable (Int, EditorDrawerMetrics) -> Int

    public init(
        maximumBodyHeight: Int? = nil,
        preferredBodyHeight: @escaping @Sendable (Int, EditorDrawerMetrics) -> Int
    ) {
        self.maximumBodyHeight = maximumBodyHeight
        self.preferredBodyHeight = preferredBodyHeight
    }
}

/// The container's whole page seam. One attached page per section kind, held
/// strongly by that kind's slot until an explicit detach; a page must not retain
/// the presenter, so the container's reference creates no cycle.
@MainActor
public protocol EditorDrawerPage: AnyObject {
    var sectionKind: DrawerSectionKind { get }
    /// Non-empty QML URL, resolved once at attach and never re-pointed.
    var contentUrl: String { get }
    var bodyPolicy: EditorDrawerBodyPolicy { get }
    /// True while this page owns an interaction that a follow-scroll would
    /// disrupt. The presenter reads it synchronously and never retains it; it is
    /// not a QML focus or pointer heuristic, and a page reports `false` again
    /// once its own cancellation ran.
    var interactionActive: Bool { get }
    /// Ends this page's current interaction or gesture. Called synchronously by the
    /// container before a hide, a replace or a global cancellation publishes.
    func cancelSectionInteraction()
}

// MARK: - QML publication

/// One section's published values as a stable bridged object. Only the fields that
/// changed are written, so an unchanged layout pass emits no property signal.
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
    func apply(_ geometry: EditorDrawerSectionGeometry) {
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

/// The container as QML sees it: one `EditorDrawerLayout` value mirrored into
/// published primitives, one bridged section state per kind and the section preference signal.
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

    /// Swift-only hook for pages that were hidden during shared-playhead publication.
    @QtIgnored public var onSectionVisibilityChanged: ((DrawerSectionKind, Bool) -> Void)?
    @QtIgnored public var onChromeChanged: ((EditorDrawerChromeState) -> Void)?

    private var layout = EditorDrawerLayout()
    private let unresolvedSection = EditorDrawerSectionState()

    public init() {}

    /// The stable section state object for a kind raw value; an unknown value
    /// yields an empty, always-unavailable state.
    public func section(kind: Int) -> EditorDrawerSectionState {
        guard let section = DrawerSectionKind(rawValue: kind) else { return unresolvedSection }
        switch section {
        case .automation: return automationSection
        case .velocity: return velocitySection
        case .voiceChanges: return voiceChangesSection
        }
    }

    /// The composition's layout-fact push. `fontPx` is the grid's `baseFontPx`; the
    /// application font's line spacing sizes the bar row only.
    public func configureLayout(
        hostWidth: Int, hostHeight: Int, gutterWidth: Int,
        fontPx: Double, appFontLineSpacing: Double
    ) {
        publish(
            layout.configureMetrics(
                EditorDrawerMetrics.resolve(
                    baseFontPx: fontPx, appFontLineSpacing: appFontLineSpacing)))
        publish(
            layout.configureHost(
                hostWidth: hostWidth, hostHeight: hostHeight,
                gutterWidth: gutterWidth))
    }

    @QtIgnored
    public var chromeState: EditorDrawerChromeState {
        var state = EditorDrawerChromeState()
        state.velocity = .init(
            visible: layout.isVisible(.velocity),
            height: layout.storedBodyHeight(.velocity))
        state.automation = .init(
            visible: layout.isVisible(.automation),
            height: layout.storedBodyHeight(.automation))
        state.voiceChanges = .init(
            visible: layout.isVisible(.voiceChanges),
            height: layout.storedBodyHeight(.voiceChanges))
        state.activePage = layout.activePage
        return state
    }

    @QtIgnored
    public func applyChrome(_ state: EditorDrawerChromeState) {
        publish(
            layout.restorePreferences(
                velocityVisible: state.velocity.visible ? 1 : 0,
                velocityHeight: state.velocity.height ?? 0,
                automationVisible: state.automation.visible ? 1 : 0,
                automationHeight: state.automation.height ?? 0,
                voiceChangesVisible: state.voiceChanges.visible ? 1 : 0,
                voiceChangesHeight: state.voiceChanges.height ?? 0,
                activePage: state.activePage.rawValue))
    }

    public func toggleSection(kind: Int, drawerOwnsFocus: Bool) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        if !layout.isAvailable(section), onChromeChanged != nil {
            var state = chromeState
            switch section {
            case .automation: state.automation.visible.toggle()
            case .velocity: state.velocity.visible.toggle()
            case .voiceChanges: state.voiceChanges.visible.toggle()
            }
            state.activePage = section
            publishDetachedChange(state, section: section)
            return
        }
        let change = layout.toggleSection(section, drawerOwnsFocus: drawerOwnsFocus)
        cancelPages(change.cancelledSections)
        publish(change)
    }

    public func setSectionVisible(kind: Int, visible: Bool, drawerOwnsFocus: Bool) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        if !layout.isAvailable(section), onChromeChanged != nil {
            var state = chromeState
            switch section {
            case .automation: state.automation.visible = visible
            case .velocity: state.velocity.visible = visible
            case .voiceChanges: state.voiceChanges.visible = visible
            }
            publishDetachedChange(state, section: section)
            return
        }
        let change = layout.setSectionVisible(
            section, visible: visible, drawerOwnsFocus: drawerOwnsFocus)
        cancelPages(change.cancelledSections)
        publish(change)
    }

    public func setSectionBodyHeight(kind: Int, height: Int) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        if !layout.isAvailable(section), onChromeChanged != nil {
            var state = chromeState
            let stored = height > 0 ? height : nil
            switch section {
            case .automation: state.automation.height = stored
            case .velocity: state.velocity.height = stored
            case .voiceChanges: state.voiceChanges.height = stored
            }
            publishDetachedChange(state, section: section)
            return
        }
        publish(layout.setSectionBodyHeight(section, height: height))
    }

    private func publishDetachedChange(
        _ state: EditorDrawerChromeState,
        section: DrawerSectionKind
    ) {
        guard state != chromeState else { return }
        let preference: DrawerChromeSection
        switch section {
        case .automation: preference = state.automation
        case .velocity: preference = state.velocity
        case .voiceChanges: preference = state.voiceChanges
        }
        drawerSectionPreferenceChanged(
            kind: section.rawValue, visible: preference.visible,
            height: preference.height ?? 0)
        onChromeChanged?(state)
    }

    public func beginResize(kind: Int) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        publish(layout.beginResize(section))
    }

    public func applyResize(kind: Int, delta: Double) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        publish(layout.applyResize(section, delta: delta))
    }

    public func endResize(kind: Int) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        publish(layout.endResize(section))
    }

    public func cancelResize() {
        publish(layout.cancelResize())
    }

    public func adjustResizeHandle(kind: Int, direction: Int) {
        guard let section = DrawerSectionKind(rawValue: kind) else { return }
        publish(layout.adjustResizeHandle(section, direction: direction))
    }

    /// Ends resize before cancelling pages, then publishes the settled layout.
    public func inputCancelled(reason: Int) {
        _ = layout.cancelResize()
        var cancelled: [DrawerSectionKind] = []
        for kind in DrawerSectionKind.stackOrder {
            guard let page = layout.attachedPage(kind) else { continue }
            page.cancelSectionInteraction()
            cancelled.append(kind)
        }
        publish(layout.publishCancellation(cancelled))
    }

    @QtIgnored
    public var resizeActive: Bool { layout.resizeKind != nil }

    /// The container's aggregate interaction state: the chrome resize session or
    /// any attached page's own interaction. Swift-only: the shared playhead's
    /// follow gate reads it, and no QML surface learns gesture state from it.
    @QtIgnored
    public var interactionActive: Bool { layout.interactionActive }

    /// Emitted when an available kind's visibility or stored height really changed.
    /// `height == 0` is the unset marker.
    @QtSignal public func drawerSectionPreferenceChanged(kind: Int, visible: Bool, height: Int)

    /// Swift-only page attachment; the session owns every attach and detach call.
    @QtIgnored
    public func attachSection(_ page: EditorDrawerPage) {
        publish(layout.attachPage(page))
    }

    /// Swift-only page attachment: publishes only the combined final layout.
    @QtIgnored
    public func attachSections(_ pages: [EditorDrawerPage]) {
        publish(layout.attachPages(pages))
    }

    /// Swift-only page detachment: cancels `page` synchronously, then publishes the
    /// kind as unavailable.
    @QtIgnored
    public func detachSection(_ page: EditorDrawerPage) {
        guard layout.attachedPage(page.sectionKind) === page else { return }
        page.cancelSectionInteraction()
        publish(layout.detachPage(page))
    }

    private func cancelPages(_ kinds: [DrawerSectionKind]) {
        for kind in kinds {
            let page = layout.attachedPage(kind)
            page?.cancelSectionInteraction()
        }
    }

    private func publish(_ change: EditorDrawerChangeSet) {
        guard !change.isEmpty else { return }
        let visibilityChanges = change.sectionPreferences.compactMap { preference -> (DrawerSectionKind, Bool)? in
            let current = section(kind: preference.kind.rawValue).visible
            return current == preference.visible ? nil : (preference.kind, preference.visible)
        }
        if change.published { apply(change.snapshot) }
        for preference in change.sectionPreferences {
            drawerSectionPreferenceChanged(
                kind: preference.kind.rawValue,
                visible: preference.visible,
                height: preference.storedBodyHeight ?? 0)
        }
        for (kind, visible) in visibilityChanges {
            onSectionVisibilityChanged?(kind, visible)
        }
        if !change.sectionPreferences.isEmpty || change.activePagePreference != nil {
            onChromeChanged?(chromeState)
        }
        // The target is published before the revision so a handler that runs on the
        // revision change reads the matching target.
        if let focus = change.focusRequest {
            focusTarget = focus.target
            focusRequest = focus.revision
        }
    }

    private func apply(_ snapshot: EditorDrawerSnapshot) {
        height = snapshot.height
        barVisible = snapshot.barVisible
        barX = snapshot.barX
        barY = snapshot.barY
        barWidth = snapshot.barWidth
        barHeight = snapshot.barHeight
        plotOrigin = snapshot.plotOrigin
        plotWidth = snapshot.plotWidth
        automationSection.apply(snapshot.automation)
        detentX = snapshot.detentX
        detentY = snapshot.detentY
        detentSize = snapshot.detentSize
        detentIconInset = snapshot.detentIconInset
        velocitySection.apply(snapshot.velocity)
        voiceChangesSection.apply(snapshot.voiceChanges)
    }
}
