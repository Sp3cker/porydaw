import Foundation

// MARK: - Pure layout

/// The container's state and rules as a pure value type. Requested preferences
/// (visibility, stored heights, active page) are kept apart from effective mounted
/// content: a kind is available only while it holds an attached page with a
/// resolved, non-empty URL, and a section with no page contributes no height, no
/// handle, no toggle and no body.
@MainActor
public struct EditorDrawerLayout {
    public private(set) var snapshot = EditorDrawerSnapshot()
    public private(set) var metrics = EditorDrawerMetrics.resolve(
        baseFontPx: GridCameraPolicy.seedBaseFontPx, appFontLineSpacing: 0)
    public private(set) var hostWidth = 0
    public private(set) var hostHeight = 0
    public private(set) var gutterWidth = 0
    public private(set) var activePage: DrawerSectionKind = .automation

    private var sections = KindValues(
        automation: Section(visible: true, storedBodyHeight: nil),
        velocity: Section(visible: false, storedBodyHeight: nil),
        voiceChanges: Section(visible: false, storedBodyHeight: nil))
    private var resize: ResizeSession?
    private var focusRevision = 0

    public init() {}

    /// The kind whose body a live resize session belongs to, if any.
    public var resizeKind: DrawerSectionKind? { resize?.kind }

    /// True while the chrome resize session is live or any attached page reports
    /// its own interaction. One aggregate a follow-scroll suspension reads; it is
    /// derived on every read and never cached.
    public var interactionActive: Bool {
        if resize != nil { return true }
        for kind in DrawerSectionKind.allCases where sections[kind].page?.interactionActive == true {
            return true
        }
        return false
    }

    public var hasAttachedPage: Bool {
        for kind in DrawerSectionKind.allCases where isAvailable(kind) { return true }
        return false
    }

    public func isVisible(_ kind: DrawerSectionKind) -> Bool { sections[kind].visible }

    public func storedBodyHeight(_ kind: DrawerSectionKind) -> Int? {
        sections[kind].storedBodyHeight
    }

    /// Available is derived, never an independent flag: an attached page with a
    /// resolved, non-empty content URL.
    public func isAvailable(_ kind: DrawerSectionKind) -> Bool {
        sections[kind].page != nil && !sections[kind].contentUrl.isEmpty
    }

    public func attachedPage(_ kind: DrawerSectionKind) -> EditorDrawerPage? { sections[kind].page }

    public func geometry(_ kind: DrawerSectionKind) -> EditorDrawerSectionGeometry { snapshot[kind] }

    /// The body's own height: stored height or the page's preferred default, never
    /// below the font-relative minimum, capped only by the page's declared maximum.
    /// A kind with no page has no body sizing of its own and reports the minimum.
    public func bodyHeight(_ kind: DrawerSectionKind) -> Int {
        let floor = max(0, metrics.minimumBody)
        guard let page = sections[kind].page else { return floor }
        let policy = page.bodyPolicy
        let requested = sections[kind].storedBodyHeight
            ?? policy.preferredBodyHeight(hostHeight, metrics)
        var height = max(floor, requested)
        if let maximum = policy.maximumBodyHeight {
            height = max(floor, min(height, maximum))
        }
        return height
    }

    // MARK: Host and metric facts

    public mutating func configureHost(hostWidth: Int, hostHeight: Int,
                                       gutterWidth: Int) -> EditorDrawerChangeSet {
        self.hostWidth = hostWidth
        self.hostHeight = hostHeight
        self.gutterWidth = gutterWidth
        return publish()
    }

    public mutating func configureMetrics(_ metrics: EditorDrawerMetrics) -> EditorDrawerChangeSet {
        self.metrics = metrics
        return publish()
    }

    // MARK: Attachment

    /// Attaches `page` to its kind's slot. Rejected while the kind already holds a
    /// page, and rejected when the content URL is empty or unresolvable; a rejected
    /// attach changes no state. Replacing content is an explicit detach followed by
    /// an attach, and the URL is resolved once and never re-pointed.
    public mutating func attachPage(_ page: EditorDrawerPage) -> EditorDrawerChangeSet {
        let kind = page.sectionKind
        guard sections[kind].page == nil else { return .untouched(snapshot) }
        let url = Self.resolvedContentUrl(page.contentUrl)
        guard !url.isEmpty else { return .untouched(snapshot) }
        sections[kind].page = page
        sections[kind].contentUrl = url
        return publish()
    }

    /// Cancels `page` synchronously, then drops its slot, URL and rectangles. The
    /// stored visibility and height survive and produce no control until a page is
    /// attached again.
    public mutating func detachPage(_ page: EditorDrawerPage) -> EditorDrawerChangeSet {
        let kind = page.sectionKind
        guard let attached = sections[kind].page, attached === page else {
            return .untouched(snapshot)
        }
        attached.cancelSectionInteraction()
        sections[kind].page = nil
        sections[kind].contentUrl = ""
        return publish(cancelledSections: [kind])
    }

    // MARK: Restored preferences

    /// Applies the values a `QtCore` `Settings` store produced: `-1` for an absent
    /// visibility or page (leaves the current value untouched), a height `< 1` for
    /// an absent or unset height (the unset marker), and otherwise the raw value.
    /// Restore never records a preference change, so it never writes back.
    public mutating func restorePreferences(velocityVisible: Int, velocityHeight: Int,
                                            automationVisible: Int, automationHeight: Int,
                                            voiceChangesVisible: Int, voiceChangesHeight: Int,
                                            activePage: Int) -> EditorDrawerChangeSet {
        applyRestoredVisibility(velocityVisible, to: .velocity)
        applyRestoredVisibility(automationVisible, to: .automation)
        applyRestoredVisibility(voiceChangesVisible, to: .voiceChanges)
        sections[.velocity].storedBodyHeight = Self.restoredHeight(velocityHeight)
        sections[.automation].storedBodyHeight = Self.restoredHeight(automationHeight)
        sections[.voiceChanges].storedBodyHeight = Self.restoredHeight(voiceChangesHeight)
        if let page = DrawerSectionKind(rawValue: activePage) { self.activePage = page }
        return publish()
    }

    // MARK: Visibility

    /// Flips the section's visibility and makes it the active page. Ignored for a
    /// kind that is not available. A hidden section keeps its stored height.
    public mutating func toggleSection(_ kind: DrawerSectionKind,
                                       drawerOwnsFocus: Bool) -> EditorDrawerChangeSet {
        guard isAvailable(kind) else { return .untouched(snapshot) }
        let previousVisibility = visibility
        let previousActive = activePage
        sections[kind].visible.toggle()
        activePage = kind
        return transition(previousVisibility: previousVisibility, previousActive: previousActive,
                          preferences: [preferenceRecord(kind)],
                          activePagePreference: previousActive == kind ? nil : kind,
                          drawerOwnsFocus: drawerOwnsFocus)
    }

    /// Sets the section's visibility without touching the active page. Ignored for a
    /// kind that is not available, and a no-op assignment publishes nothing.
    public mutating func setSectionVisible(_ kind: DrawerSectionKind, visible: Bool,
                                           drawerOwnsFocus: Bool) -> EditorDrawerChangeSet {
        guard isAvailable(kind), sections[kind].visible != visible else {
            return .untouched(snapshot)
        }
        let previousVisibility = visibility
        let previousActive = activePage
        sections[kind].visible = visible
        return transition(previousVisibility: previousVisibility, previousActive: previousActive,
                          preferences: [preferenceRecord(kind)], activePagePreference: nil,
                          drawerOwnsFocus: drawerOwnsFocus)
    }

    /// Stores the section's body height; a height `< 1` is the unset marker.
    /// Ignored for a kind that is not available.
    public mutating func setSectionBodyHeight(_ kind: DrawerSectionKind,
                                              height: Int) -> EditorDrawerChangeSet {
        guard isAvailable(kind) else { return .untouched(snapshot) }
        let stored = height < 1 ? nil : height
        guard sections[kind].storedBodyHeight != stored else { return .untouched(snapshot) }
        sections[kind].storedBodyHeight = stored
        return publish(preferences: [preferenceRecord(kind)])
    }

    // MARK: Resizing

    /// Captures the drag baseline: the resized kind's start height and original
    /// stored value, plus the Automations section's start height and original stored
    /// value for the spill. Ignored unless the kind holds a visible available body.
    public mutating func beginResize(_ kind: DrawerSectionKind) -> EditorDrawerChangeSet {
        guard isAvailable(kind), isVisible(kind) else { return .untouched(snapshot) }
        resize = ResizeSession(kind: kind,
                               startHeight: bodyHeight(kind),
                               originalStoredHeight: sections[kind].storedBodyHeight,
                               automationStartHeight: bodyHeight(.automation),
                               automationOriginalStoredHeight: sections[.automation].storedBodyHeight)
        return .untouched(snapshot)
    }

    /// `startHeight + round(delta)`, clamped to the minimum and to the height left
    /// by the other visible bodies, then to the page's declared maximum. A resolved
    /// value equal to the drag start restores the original stored value, including
    /// the unset marker. Ignored without a live session for this kind.
    public mutating func applyResize(_ kind: DrawerSectionKind, delta: Double) -> EditorDrawerChangeSet {
        guard let session = resize, session.kind == kind else { return .untouched(snapshot) }
        let requested = session.startHeight + Self.pixelDelta(delta)
        store(resolveResize(requested: requested, session: session), session: session)
        return publish()
    }

    /// Ends the drag and records the section preferences the drag changed.
    public mutating func endResize(_ kind: DrawerSectionKind) -> EditorDrawerChangeSet {
        guard let session = resize, session.kind == kind else { return .untouched(snapshot) }
        resize = nil
        return publish(preferences: resizePreferences(session))
    }

    /// Drops the session, keeps the last applied heights and records nothing.
    public mutating func cancelResize() -> EditorDrawerChangeSet {
        resize = nil
        return .untouched(snapshot)
    }

    /// One keyboard resize step through the same resolution path, recording the
    /// resulting preference change. A zero direction is ignored.
    public mutating func adjustResizeHandle(_ kind: DrawerSectionKind,
                                            direction: Int) -> EditorDrawerChangeSet {
        guard direction != 0, isAvailable(kind), isVisible(kind) else {
            return .untouched(snapshot)
        }
        let session = ResizeSession(kind: kind,
                                    startHeight: bodyHeight(kind),
                                    originalStoredHeight: sections[kind].storedBodyHeight,
                                    automationStartHeight: bodyHeight(.automation),
                                    automationOriginalStoredHeight: sections[.automation].storedBodyHeight)
        let step = direction > 0 ? 1 : -1
        let requested = session.startHeight + step * metrics.resizeStep
        store(resolveResize(requested: requested, session: session), session: session)
        return publish(preferences: resizePreferences(session))
    }

    /// The container's global cancellation entry point: cancels the chrome resize
    /// session and every attached page, recording and publishing nothing.
    public mutating func cancelInteractions() -> EditorDrawerChangeSet {
        resize = nil
        var cancelled: [DrawerSectionKind] = []
        for kind in DrawerSectionKind.stackOrder {
            guard let page = sections[kind].page else { continue }
            page.cancelSectionInteraction()
            cancelled.append(kind)
        }
        return publish(cancelledSections: cancelled)
    }

    // MARK: Resolution

    private mutating func publish(preferences: [EditorDrawerSectionPreference] = [],
                                  activePagePreference: DrawerSectionKind? = nil,
                                  focusRequest: EditorDrawerFocusRequest? = nil,
                                  cancelledSections: [DrawerSectionKind] = []) -> EditorDrawerChangeSet {
        let next = resolveSnapshot()
        let published: Bool
        if next == snapshot {
            published = false
        } else {
            snapshot = next
            published = true
        }
        return EditorDrawerChangeSet(published: published, snapshot: snapshot,
                                     focusRequest: focusRequest,
                                     sectionPreferences: preferences,
                                     activePagePreference: activePagePreference,
                                     cancelledSections: cancelledSections)
    }

    /// A visibility or active-page transition: cancels the affected pages first,
    /// then publishes the new state and the focus request.
    private mutating func transition(previousVisibility: KindValues<Bool>,
                                     previousActive: DrawerSectionKind,
                                     preferences: [EditorDrawerSectionPreference],
                                     activePagePreference: DrawerSectionKind?,
                                     drawerOwnsFocus: Bool) -> EditorDrawerChangeSet {
        let cancelled = cancelTransition(from: previousVisibility, previousActive: previousActive)
        let focus = focusRequest(drawerOwnsFocus: drawerOwnsFocus)
        return publish(preferences: preferences, activePagePreference: activePagePreference,
                       focusRequest: focus, cancelledSections: cancelled)
    }

    /// Each kind hidden by the transition, plus each kind losing the active slot
    /// while it was visible, cancels its attached page synchronously.
    private func cancelTransition(from previousVisibility: KindValues<Bool>,
                                  previousActive: DrawerSectionKind) -> [DrawerSectionKind] {
        let activeChanged = previousActive != activePage
        var cancelled: [DrawerSectionKind] = []
        for kind in DrawerSectionKind.stackOrder where previousVisibility[kind] {
            let hidden = !isVisible(kind)
            let lostActive = activeChanged && kind == previousActive
            guard hidden || lostActive, let page = sections[kind].page else { continue }
            page.cancelSectionInteraction()
            cancelled.append(kind)
        }
        return cancelled
    }

    /// A request targets the active visible available kind, else the first visible
    /// available kind, else the roll. A request for a kind that is not available and
    /// visible is never published, and the revision only moves on a real request.
    private mutating func focusRequest(drawerOwnsFocus: Bool) -> EditorDrawerFocusRequest? {
        guard drawerOwnsFocus else { return nil }
        let target: Int
        if isVisible(activePage) && isAvailable(activePage) {
            target = activePage.rawValue
        } else if let first = DrawerSectionKind.stackOrder.first(where: {
            isVisible($0) && isAvailable($0)
        }) {
            target = first.rawValue
        } else {
            target = -1
        }
        focusRevision += 1
        return EditorDrawerFocusRequest(revision: focusRevision, target: target)
    }

    private func resolveSnapshot() -> EditorDrawerSnapshot {
        var next = EditorDrawerSnapshot()
        let origin = max(0, gutterWidth)
        next.plotOrigin = origin
        next.plotWidth = max(0, hostWidth - origin)

        var anyPage = false
        for kind in DrawerSectionKind.allCases {
            let available = isAvailable(kind)
            anyPage = anyPage || available
            var geometry = EditorDrawerSectionGeometry()
            geometry.available = available
            geometry.visible = available && sections[kind].visible
            geometry.contentUrl = available ? sections[kind].contentUrl : ""
            next[kind] = geometry
        }
        // The production no-page state: zero height, no bar, handle, toggle or body.
        guard anyPage else { return next }

        let barHeight = max(0, metrics.barHeight)
        let handleHeight = max(0, metrics.handleHeight)
        let width = max(0, hostWidth)

        var aggregate = barHeight
        var handleCount = 0
        for kind in DrawerSectionKind.stackOrder where isVisible(kind) && isAvailable(kind) {
            aggregate += handleHeight + bodyHeight(kind)
            handleCount += 1
        }
        next.height = max(0, min(hostHeight, aggregate))
        next.barVisible = true
        next.barWidth = width
        next.barHeight = barHeight

        // Under the host clamp, Voice Changes takes its height first, Automations
        // keeps its height second and Velocity takes the remainder.
        var remaining = max(0, next.height - barHeight - handleHeight * handleCount)
        var drawn = KindValues(0)
        if isVisible(.voiceChanges) && isAvailable(.voiceChanges) {
            drawn.voiceChanges = min(bodyHeight(.voiceChanges), remaining)
            remaining -= drawn.voiceChanges
        }
        if isVisible(.automation) && isAvailable(.automation) {
            drawn.automation = min(bodyHeight(.automation), remaining)
            remaining -= drawn.automation
        }
        if isVisible(.velocity) && isAvailable(.velocity) {
            drawn.velocity = min(bodyHeight(.velocity), remaining)
        }

        // Bodies and handles stack top to bottom in stackOrder; the bar spans the
        // container's full width below them.
        var y = 0
        for kind in DrawerSectionKind.stackOrder where isVisible(kind) && isAvailable(kind) {
            var geometry = next[kind]
            geometry.handleY = y
            geometry.handleHeight = handleHeight
            y += handleHeight
            geometry.bodyX = 0
            geometry.bodyY = y
            geometry.bodyWidth = width
            geometry.bodyHeight = drawn[kind]
            y += geometry.bodyHeight
            next[kind] = geometry
        }
        next.barY = y

        // The three production toggle slots stay put; only available kinds render.
        let inset = max(0, metrics.toggleInset)
        let buttonSize = max(max(1, metrics.pixel), barHeight - 2 * inset)
        let groupWidth = 3 * buttonSize + 2 * inset
        let groupX = min(max((origin - groupWidth) / 2, 0), max(0, width - groupWidth))
        for kind in DrawerSectionKind.toggleOrder where isAvailable(kind) {
            var geometry = next[kind]
            geometry.toggleX = groupX + kind.toggleSlot * (buttonSize + inset)
            geometry.toggleY = next.barY + inset
            geometry.toggleSize = buttonSize
            next[kind] = geometry
        }
        // Historical DrawerSections::arrangeLocal: lower-left of the velocity
        // body, with the icon inset by half the toggle padding.
        if next.velocity.visible {
            next.detentSize = min(buttonSize, min(origin, width))
            next.detentX = next.velocity.bodyX
            next.detentY = next.velocity.bodyY + next.velocity.bodyHeight - next.detentSize
            next.detentIconInset = Double(inset) / 2
        }
        return next
    }

    /// Production `applyResize`: resolves the requested height against the height
    /// left by the other visible bodies, and applies the Voice-Changes→Automations
    /// spill when the resized kind declares a maximum beside a visible Automations
    /// section.
    private func resolveResize(requested: Int, session: ResizeSession) -> ResizeResolution {
        let minimum = max(0, metrics.minimumBody)
        let barHeight = max(0, metrics.barHeight)
        let handleHeight = max(0, metrics.handleHeight)
        let voice = session.kind == .voiceChanges
        let spill = voice && isVisible(.automation) && isAvailable(.automation)

        var availableBodyHeight = hostHeight - barHeight
        for kind in DrawerSectionKind.stackOrder where isVisible(kind) && isAvailable(kind) {
            availableBodyHeight -= handleHeight
            // The Automations body is subtracted for every kind except Voice Changes.
            if kind != session.kind && !(voice && kind == .automation) {
                availableBodyHeight -= bodyHeight(kind)
            }
        }

        var resolvedHeight = requested
        var resolvedAutomation = session.automationStartHeight
        if spill, let maximum = sections[.voiceChanges].page?.bodyPolicy.maximumBodyHeight {
            let maximumForResized = min(max(minimum, availableBodyHeight), maximum)
            resolvedHeight = Self.clamp(requested, minimum: minimum, maximum: maximumForResized)
            if requested > maximumForResized {
                let automationMaximum = max(minimum, availableBodyHeight - resolvedHeight)
                resolvedAutomation = Self.clamp(session.automationStartHeight
                                                    + requested - maximumForResized,
                                                minimum: minimum, maximum: automationMaximum)
            }
        } else {
            resolvedHeight = Self.clamp(requested, minimum: minimum,
                                        maximum: max(minimum, availableBodyHeight))
        }

        var height = resolvedHeight == session.startHeight
            ? session.originalStoredHeight : resolvedHeight
        if let current = height, let maximum = sections[session.kind].page?.bodyPolicy.maximumBodyHeight {
            height = max(minimum, min(current, maximum))
        }
        let automation = resolvedAutomation == session.automationStartHeight
            ? session.automationOriginalStoredHeight : resolvedAutomation
        return ResizeResolution(height: height, spillAutomation: spill, automationHeight: automation)
    }

    private mutating func store(_ resolution: ResizeResolution, session: ResizeSession) {
        sections[session.kind].storedBodyHeight = resolution.height
        if resolution.spillAutomation {
            sections[.automation].storedBodyHeight = resolution.automationHeight
        }
    }

    /// The preference records a finished resize caused: the resized kind, and the
    /// Automations section when the spill moved it, each only when the stored value
    /// really differs from the drag-start value.
    private func resizePreferences(_ session: ResizeSession) -> [EditorDrawerSectionPreference] {
        var preferences: [EditorDrawerSectionPreference] = []
        if isAvailable(session.kind),
           sections[session.kind].storedBodyHeight != session.originalStoredHeight {
            preferences.append(preferenceRecord(session.kind))
        }
        let spill = session.kind == .voiceChanges && isVisible(.automation) && isAvailable(.automation)
        if spill, sections[.automation].storedBodyHeight != session.automationOriginalStoredHeight {
            preferences.append(preferenceRecord(.automation))
        }
        return preferences
    }

    private func preferenceRecord(_ kind: DrawerSectionKind) -> EditorDrawerSectionPreference {
        EditorDrawerSectionPreference(kind: kind, visible: sections[kind].visible,
                                      storedBodyHeight: sections[kind].storedBodyHeight)
    }

    private var visibility: KindValues<Bool> {
        var mask = KindValues(false)
        for kind in DrawerSectionKind.allCases { mask[kind] = sections[kind].visible }
        return mask
    }

    private mutating func applyRestoredVisibility(_ raw: Int, to kind: DrawerSectionKind) {
        guard raw >= 0 else { return }
        sections[kind].visible = raw != 0
    }

    private static func restoredHeight(_ raw: Int) -> Int? { raw > 0 ? raw : nil }

    private static func clamp(_ value: Int, minimum: Int, maximum: Int) -> Int {
        max(minimum, min(value, maximum))
    }

    /// Rounds a pointer delta to whole pixels without trapping on a hostile value.
    private static func pixelDelta(_ delta: Double) -> Int {
        guard delta.isFinite else { return 0 }
        let limit = 1_000_000_000.0
        return Int(min(max(delta.rounded(), -limit), limit))
    }

    /// Resolves the page's content URL once. An empty or unresolvable URL is
    /// rejected, so an attached page always publishes a usable URL.
    private static func resolvedContentUrl(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return "" }
        return trimmed
    }

    // MARK: Storage

    private struct Section {
        var visible: Bool
        var storedBodyHeight: Int?
        var page: EditorDrawerPage? = nil
        var contentUrl = ""
    }

    /// One value per section kind, indexed by kind. Per-kind state stays in named
    /// fields, so no lookup allocates.
    private struct KindValues<Value> {
        var automation: Value
        var velocity: Value
        var voiceChanges: Value

        init(_ value: Value) {
            automation = value
            velocity = value
            voiceChanges = value
        }

        init(automation: Value, velocity: Value, voiceChanges: Value) {
            self.automation = automation
            self.velocity = velocity
            self.voiceChanges = voiceChanges
        }

        subscript(kind: DrawerSectionKind) -> Value {
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

    private struct ResizeSession {
        let kind: DrawerSectionKind
        let startHeight: Int
        let originalStoredHeight: Int?
        let automationStartHeight: Int
        let automationOriginalStoredHeight: Int?
    }

    private struct ResizeResolution {
        let height: Int?
        let spillAutomation: Bool
        let automationHeight: Int?
    }
}
