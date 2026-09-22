// MARK: - Pure layout

/// Drawer preferences, resize state and geometry policy. Page ownership and Qt
/// publication stay in `EditorDrawerPresenter`; every operation receives one
/// immutable fixed-slot snapshot of the current attached pages.
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

    public var resizeKind: DrawerSectionKind? { resize?.kind }

    public func isVisible(_ kind: DrawerSectionKind) -> Bool { sections[kind].visible }
    public func isAvailable(_ kind: DrawerSectionKind) -> Bool { snapshot[kind].available }
    public func storedBodyHeight(_ kind: DrawerSectionKind) -> Int? {
        sections[kind].storedBodyHeight
    }

    // MARK: Host and attachment facts

    /// Host and font facts change together and produce one resolved snapshot.
    public mutating func configure(hostWidth: Int, hostHeight: Int, gutterWidth: Int,
                                   metrics: EditorDrawerMetrics,
                                   pages: EditorDrawerPageFacts) -> EditorDrawerChangeSet {
        self.hostWidth = hostWidth
        self.hostHeight = hostHeight
        self.gutterWidth = gutterWidth
        self.metrics = metrics
        return publish(pages: pages)
    }

    /// Attachment identity and URL acceptance are presenter concerns. The layout
    /// only resolves the supplied page-facts snapshot.
    public mutating func attachPage(pages: EditorDrawerPageFacts)
        -> EditorDrawerChangeSet {
        publish(pages: pages)
    }

    /// Detachment requests cancellation for the formerly available slot; the
    /// presenter executes it before applying the unavailable snapshot.
    public mutating func detachPage(_ kind: DrawerSectionKind,
                                    pages: EditorDrawerPageFacts) -> EditorDrawerChangeSet {
        guard isAvailable(kind) else { return publish(pages: pages) }
        return publish(pages: pages, cancelledSections: [kind])
    }

    // MARK: Restored preferences

    /// Applies one `QtCore.Settings` read. `-1` visibility/page values are absent,
    /// and a height below one restores the unset marker. Restore never writes back.
    public mutating func restorePreferences(
        velocityVisible: Int, velocityHeight: Int,
        automationVisible: Int, automationHeight: Int,
        voiceChangesVisible: Int, voiceChangesHeight: Int,
        activePage: Int, pages: EditorDrawerPageFacts
    ) -> EditorDrawerChangeSet {
        applyRestoredVisibility(velocityVisible, to: .velocity)
        applyRestoredVisibility(automationVisible, to: .automation)
        applyRestoredVisibility(voiceChangesVisible, to: .voiceChanges)
        sections[.velocity].storedBodyHeight = Self.restoredHeight(velocityHeight)
        sections[.automation].storedBodyHeight = Self.restoredHeight(automationHeight)
        sections[.voiceChanges].storedBodyHeight = Self.restoredHeight(voiceChangesHeight)
        if let page = DrawerSectionKind(rawValue: activePage) { self.activePage = page }
        return publish(pages: pages)
    }

    // MARK: Visibility

    public mutating func toggleSection(_ kind: DrawerSectionKind,
                                       drawerOwnsFocus: Bool,
                                       pages: EditorDrawerPageFacts) -> EditorDrawerChangeSet {
        guard isAvailable(kind, pages: pages) else { return publish(pages: pages) }
        let previousVisibility = visibility
        let previousActive = activePage
        sections[kind].visible.toggle()
        activePage = kind
        return transition(previousVisibility: previousVisibility, previousActive: previousActive,
                          preferences: [preferenceRecord(kind)],
                          activePagePreference: previousActive == kind ? nil : kind,
                          drawerOwnsFocus: drawerOwnsFocus, pages: pages)
    }

    public mutating func setSectionVisible(_ kind: DrawerSectionKind, visible: Bool,
                                           drawerOwnsFocus: Bool,
                                           pages: EditorDrawerPageFacts) -> EditorDrawerChangeSet {
        guard isAvailable(kind, pages: pages), sections[kind].visible != visible else {
            return publish(pages: pages)
        }
        let previousVisibility = visibility
        let previousActive = activePage
        sections[kind].visible = visible
        return transition(previousVisibility: previousVisibility, previousActive: previousActive,
                          preferences: [preferenceRecord(kind)], activePagePreference: nil,
                          drawerOwnsFocus: drawerOwnsFocus, pages: pages)
    }

    public mutating func setSectionBodyHeight(_ kind: DrawerSectionKind, height: Int,
                                              pages: EditorDrawerPageFacts)
        -> EditorDrawerChangeSet {
        guard isAvailable(kind, pages: pages) else { return publish(pages: pages) }
        let stored = height < 1 ? nil : height
        guard sections[kind].storedBodyHeight != stored else { return publish(pages: pages) }
        sections[kind].storedBodyHeight = stored
        return publish(pages: pages, preferences: [preferenceRecord(kind)])
    }

    // MARK: Resizing

    public mutating func beginResize(_ kind: DrawerSectionKind,
                                     pages: EditorDrawerPageFacts) -> EditorDrawerChangeSet {
        guard isAvailable(kind, pages: pages), isVisible(kind) else {
            return publish(pages: pages)
        }
        resize = ResizeSession(
            kind: kind,
            startHeight: bodyHeight(kind, pages: pages),
            originalStoredHeight: sections[kind].storedBodyHeight,
            automationStartHeight: bodyHeight(.automation, pages: pages),
            automationOriginalStoredHeight: sections[.automation].storedBodyHeight)
        return publish(pages: pages)
    }

    public mutating func applyResize(_ kind: DrawerSectionKind, delta: Double,
                                     pages: borrowing EditorDrawerPageFacts) -> EditorDrawerChangeSet {
        guard let session = resize, session.kind == kind else {
            return publish(pages: pages)
        }
        let requested = session.startHeight + Self.pixelDelta(delta)
        store(resolveResize(requested: requested, session: session, pages: pages),
              session: session)
        return publish(pages: pages)
    }

    public mutating func endResize(_ kind: DrawerSectionKind,
                                   pages: EditorDrawerPageFacts) -> EditorDrawerChangeSet {
        guard let session = resize, session.kind == kind else {
            return publish(pages: pages)
        }
        resize = nil
        return publish(pages: pages, preferences: resizePreferences(session, pages: pages))
    }

    /// Drops the session, keeps applied heights and records no preference.
    public mutating func cancelResize(pages: EditorDrawerPageFacts) -> EditorDrawerChangeSet {
        resize = nil
        return publish(pages: pages)
    }

    public mutating func adjustResizeHandle(_ kind: DrawerSectionKind, direction: Int,
                                            pages: EditorDrawerPageFacts)
        -> EditorDrawerChangeSet {
        guard direction != 0, isAvailable(kind, pages: pages), isVisible(kind) else {
            return publish(pages: pages)
        }
        let session = ResizeSession(
            kind: kind,
            startHeight: bodyHeight(kind, pages: pages),
            originalStoredHeight: sections[kind].storedBodyHeight,
            automationStartHeight: bodyHeight(.automation, pages: pages),
            automationOriginalStoredHeight: sections[.automation].storedBodyHeight)
        let step = direction > 0 ? 1 : -1
        let requested = session.startHeight + step * metrics.resizeStep
        store(resolveResize(requested: requested, session: session, pages: pages),
              session: session)
        return publish(pages: pages, preferences: resizePreferences(session, pages: pages))
    }

    /// Ends the chrome resize and returns visible-page cancellation effects in
    /// the native Voice Changes → Velocity → Automation call order.
    public mutating func cancelInteractions(pages: EditorDrawerPageFacts)
        -> EditorDrawerChangeSet {
        resize = nil
        let cancelled: [DrawerSectionKind] = [
            .voiceChanges, .velocity, .automation
        ].filter {
            isVisible($0) && isAvailable($0, pages: pages)
        }
        return publish(pages: pages, cancelledSections: cancelled)
    }

    // MARK: Resolution

    private mutating func publish(
        pages: borrowing EditorDrawerPageFacts,
        preferences: [EditorDrawerSectionPreference] = [],
        activePagePreference: DrawerSectionKind? = nil,
        focusRequest: EditorDrawerFocusRequest? = nil,
        cancelledSections: [DrawerSectionKind] = []
    ) -> EditorDrawerChangeSet {
        let next = resolveSnapshot(pages: pages)
        let published: Bool
        if next == snapshot {
            published = false
        } else {
            snapshot = next
            published = true
        }
        return EditorDrawerChangeSet(
            published: published, snapshot: snapshot, focusRequest: focusRequest,
            sectionPreferences: preferences, activePagePreference: activePagePreference,
            cancelledSections: cancelledSections)
    }

    private mutating func transition(
        previousVisibility: KindValues<Bool>,
        previousActive: DrawerSectionKind,
        preferences: [EditorDrawerSectionPreference],
        activePagePreference: DrawerSectionKind?,
        drawerOwnsFocus: Bool,
        pages: EditorDrawerPageFacts
    ) -> EditorDrawerChangeSet {
        let cancelled = cancelTransition(
            from: previousVisibility, previousActive: previousActive, pages: pages)
        let focus = focusRequest(drawerOwnsFocus: drawerOwnsFocus, pages: pages)
        return publish(pages: pages, preferences: preferences,
                       activePagePreference: activePagePreference,
                       focusRequest: focus, cancelledSections: cancelled)
    }

    /// Native transitions first cancel newly hidden kinds in stack order, then
    /// cancel the previously active visible kind when the active slot moves.
    private func cancelTransition(from previousVisibility: KindValues<Bool>,
                                  previousActive: DrawerSectionKind,
                                  pages: EditorDrawerPageFacts) -> [DrawerSectionKind] {
        var cancelled: [DrawerSectionKind] = []
        for kind in DrawerSectionKind.stackOrder
            where previousVisibility[kind] && !isVisible(kind)
                && isAvailable(kind, pages: pages) {
            cancelled.append(kind)
        }
        if previousActive != activePage && previousVisibility[previousActive]
            && isAvailable(previousActive, pages: pages) {
            cancelled.append(previousActive)
        }
        return cancelled
    }

    private mutating func focusRequest(drawerOwnsFocus: Bool,
                                       pages: EditorDrawerPageFacts)
        -> EditorDrawerFocusRequest? {
        guard drawerOwnsFocus else { return nil }
        let target: Int
        if isVisible(activePage) && isAvailable(activePage, pages: pages) {
            target = activePage.rawValue
        } else if let first = DrawerSectionKind.stackOrder.first(where: {
            isVisible($0) && isAvailable($0, pages: pages)
        }) {
            target = first.rawValue
        } else {
            target = -1
        }
        focusRevision += 1
        return EditorDrawerFocusRequest(revision: focusRevision, target: target)
    }

    private func resolveSnapshot(pages: borrowing EditorDrawerPageFacts) -> EditorDrawerSnapshot {
        var next = EditorDrawerSnapshot()
        let origin = max(0, gutterWidth)
        next.plotOrigin = origin
        next.plotWidth = max(0, hostWidth - origin)

        var anyPage = false
        for kind in DrawerSectionKind.allCases {
            let available = isAvailable(kind, pages: pages)
            anyPage = anyPage || available
            var geometry = EditorDrawerSectionGeometry()
            geometry.available = available
            geometry.visible = available && sections[kind].visible
            geometry.contentUrl = available ? pages[kind]!.resolvedContentUrl : ""
            next[kind] = geometry
        }
        guard anyPage else { return next }

        let barHeight = max(0, metrics.barHeight)
        let handleHeight = max(0, metrics.handleHeight)
        let width = max(0, hostWidth)

        var aggregate = barHeight
        var handleCount = 0
        for kind in DrawerSectionKind.stackOrder
            where isVisible(kind) && isAvailable(kind, pages: pages) {
            aggregate += handleHeight + bodyHeight(kind, pages: pages)
            handleCount += 1
        }
        next.height = max(0, min(hostHeight, aggregate))
        next.barVisible = true
        next.barWidth = width
        next.barHeight = barHeight

        // Under the host clamp, Voice Changes takes its height first, Automations
        // second and Velocity the remainder.
        var remaining = max(0, next.height - barHeight - handleHeight * handleCount)
        var drawn = KindValues(0)
        if isVisible(.voiceChanges) && isAvailable(.voiceChanges, pages: pages) {
            drawn.voiceChanges = min(bodyHeight(.voiceChanges, pages: pages), remaining)
            remaining -= drawn.voiceChanges
        }
        if isVisible(.automation) && isAvailable(.automation, pages: pages) {
            drawn.automation = min(bodyHeight(.automation, pages: pages), remaining)
            remaining -= drawn.automation
        }
        if isVisible(.velocity) && isAvailable(.velocity, pages: pages) {
            drawn.velocity = min(bodyHeight(.velocity, pages: pages), remaining)
        }

        var y = 0
        for kind in DrawerSectionKind.stackOrder
            where isVisible(kind) && isAvailable(kind, pages: pages) {
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

        let inset = max(0, metrics.toggleInset)
        let buttonSize = max(max(1, metrics.pixel), barHeight - 2 * inset)
        let groupWidth = 3 * buttonSize + 2 * inset
        let pianoKeysWidth = min(origin, width)
        let groupX = min(max((pianoKeysWidth - groupWidth) / 2, 0),
                         max(0, width - groupWidth))
        for kind in DrawerSectionKind.toggleOrder where isAvailable(kind, pages: pages) {
            var geometry = next[kind]
            geometry.toggleX = groupX + kind.toggleSlot * (buttonSize + inset)
            geometry.toggleY = next.barY + inset
            geometry.toggleSize = buttonSize
            next[kind] = geometry
        }
        if next.velocity.visible {
            next.detentSize = min(buttonSize, min(origin, width))
            next.detentX = next.velocity.bodyX
            next.detentY = next.velocity.bodyY + next.velocity.bodyHeight - next.detentSize
            next.detentIconInset = Double(inset) / 2
        }
        return next
    }

    private func bodyHeight(_ kind: DrawerSectionKind,
                            pages: borrowing EditorDrawerPageFacts) -> Int {
        let floor = max(0, metrics.minimumBody)
        guard let page = pages[kind] else { return floor }
        let requested = sections[kind].storedBodyHeight ?? page.preferredBodyHeight
        var height = max(floor, requested)
        if let maximum = page.maximumBodyHeight {
            height = max(floor, min(height, maximum))
        }
        return height
    }

    private func resolveResize(requested: Int, session: ResizeSession,
                               pages: borrowing EditorDrawerPageFacts) -> ResizeResolution {
        let minimum = max(0, metrics.minimumBody)
        let barHeight = max(0, metrics.barHeight)
        let handleHeight = max(0, metrics.handleHeight)
        let voice = session.kind == .voiceChanges
        let maximum = pages[.voiceChanges]?.maximumBodyHeight
        let spill = voice && maximum != nil
            && isVisible(.automation) && isAvailable(.automation, pages: pages)

        var availableBodyHeight = hostHeight - barHeight
        for kind in DrawerSectionKind.stackOrder
            where isVisible(kind) && isAvailable(kind, pages: pages) {
            availableBodyHeight -= handleHeight
            if kind != session.kind && !(spill && kind == .automation) {
                availableBodyHeight -= bodyHeight(kind, pages: pages)
            }
        }

        var resolvedHeight = requested
        var resolvedAutomation = session.automationStartHeight
        if spill, let maximum {
            let maximumForResized = min(max(minimum, availableBodyHeight), maximum)
            resolvedHeight = Self.clamp(requested, minimum: minimum, maximum: maximumForResized)
            if requested > maximumForResized {
                let automationMaximum = max(minimum, availableBodyHeight - resolvedHeight)
                resolvedAutomation = Self.clamp(
                    session.automationStartHeight + requested - maximumForResized,
                    minimum: minimum, maximum: automationMaximum)
            }
        } else {
            resolvedHeight = Self.clamp(
                requested, minimum: minimum, maximum: max(minimum, availableBodyHeight))
        }

        var height = resolvedHeight == session.startHeight
            ? session.originalStoredHeight : resolvedHeight
        if let current = height, let maximum = pages[session.kind]?.maximumBodyHeight {
            height = max(minimum, min(current, maximum))
        }
        let automation = resolvedAutomation == session.automationStartHeight
            ? session.automationOriginalStoredHeight : resolvedAutomation
        return ResizeResolution(
            height: height, spillAutomation: spill, automationHeight: automation)
    }

    private mutating func store(_ resolution: ResizeResolution, session: ResizeSession) {
        sections[session.kind].storedBodyHeight = resolution.height
        if resolution.spillAutomation {
            sections[.automation].storedBodyHeight = resolution.automationHeight
        }
    }

    private func resizePreferences(_ session: ResizeSession,
                                   pages: EditorDrawerPageFacts)
        -> [EditorDrawerSectionPreference] {
        var preferences: [EditorDrawerSectionPreference] = []
        if isAvailable(session.kind, pages: pages),
           sections[session.kind].storedBodyHeight != session.originalStoredHeight {
            preferences.append(preferenceRecord(session.kind))
        }
        let spill = session.kind == .voiceChanges
            && pages[.voiceChanges]?.maximumBodyHeight != nil
            && isVisible(.automation) && isAvailable(.automation, pages: pages)
        if spill,
           sections[.automation].storedBodyHeight != session.automationOriginalStoredHeight {
            preferences.append(preferenceRecord(.automation))
        }
        return preferences
    }

    private func preferenceRecord(_ kind: DrawerSectionKind)
        -> EditorDrawerSectionPreference {
        EditorDrawerSectionPreference(kind: kind, visible: sections[kind].visible,
                                      storedBodyHeight: sections[kind].storedBodyHeight)
    }

    private func isAvailable(_ kind: DrawerSectionKind,
                             pages: borrowing EditorDrawerPageFacts) -> Bool {
        guard let page = pages[kind] else { return false }
        return !page.resolvedContentUrl.isEmpty
    }

    private var visibility: KindValues<Bool> {
        var mask = KindValues(false)
        for kind in DrawerSectionKind.allCases { mask[kind] = sections[kind].visible }
        return mask
    }

    private mutating func applyRestoredVisibility(_ raw: Int,
                                                  to kind: DrawerSectionKind) {
        guard raw >= 0 else { return }
        sections[kind].visible = raw != 0
    }

    private static func restoredHeight(_ raw: Int) -> Int? { raw > 0 ? raw : nil }

    private static func clamp(_ value: Int, minimum: Int, maximum: Int) -> Int {
        max(minimum, min(value, maximum))
    }

    private static func pixelDelta(_ delta: Double) -> Int {
        guard delta.isFinite else { return 0 }
        let limit = 1_000_000_000.0
        return Int(min(max(delta.rounded(), -limit), limit))
    }

    // MARK: Storage

    private struct Section {
        var visible: Bool
        var storedBodyHeight: Int?
    }

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
