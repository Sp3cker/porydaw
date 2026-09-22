import Foundation

// MARK: - Section identity

/// The three fixed drawer sections. Raw values are the production page values in
/// `src/ui/editordrawer/drawerpage.h` and travel to QML unchanged.
public enum DrawerSectionKind: Int, CaseIterable, Sendable {
    case automation = 0
    case velocity = 1
    case voiceChanges = 2

    /// Top-to-bottom order of the stacked bodies (`DrawerSections::sectionOrder`).
    public static let stackOrder: [DrawerSectionKind] = [.velocity, .voiceChanges, .automation]
    /// Left-to-right order of the chrome toggles (`DrawerChrome`).
    public static let toggleOrder: [DrawerSectionKind] = [.voiceChanges, .automation, .velocity]

    /// Historical `activePage` value, also the human name of the section.
    public var name: String {
        switch self {
        case .automation: "automations"
        case .velocity: "velocity"
        case .voiceChanges: "voiceChanges"
        }
    }

    /// Preference key stem: the stored keys are `editorDrawer/<keyName>Visible` and
    /// `editorDrawer/<keyName>Height`.
    public var keyName: String {
        switch self {
        case .automation: "automation"
        case .velocity: "velocity"
        case .voiceChanges: "voiceChanges"
        }
    }

    /// Existing toggle icon, tinted by the chrome's alpha mask.
    public var iconResource: String {
        switch self {
        case .automation: "qrc:/icons/automation.svg"
        case .velocity: "qrc:/icons/velocity.svg"
        case .voiceChanges: "qrc:/icons/flat-music.svg"
        }
    }

    /// Position of this kind's toggle in `toggleOrder`. Page attachment never moves it.
    var toggleSlot: Int {
        switch self {
        case .voiceChanges: 0
        case .automation: 1
        case .velocity: 2
        }
    }
}

// MARK: - Metrics

/// Font-relative container metrics, derived exactly as production `DrawerSections`
/// derives its chrome metrics and `layout::chromeRowHeight(applicationFont, 0)`
/// derives the bar row.
public struct EditorDrawerMetrics: Equatable, Sendable {
    public let barHeight: Int
    public let handleHeight: Int
    public let minimumBody: Int
    public let pianoRollReserve: Int
    public let toggleInset: Int
    public let resizeStep: Int
    public let pixel: Int

    public init(barHeight: Int, handleHeight: Int, minimumBody: Int, pianoRollReserve: Int,
                toggleInset: Int, resizeStep: Int, pixel: Int) {
        self.barHeight = barHeight
        self.handleHeight = handleHeight
        self.minimumBody = minimumBody
        self.pianoRollReserve = pianoRollReserve
        self.toggleInset = toggleInset
        self.resizeStep = resizeStep
        self.pixel = pixel
    }

    /// The layout base font is the grid's `baseFontPx` — the same value the
    /// composition already pushes to `configureViewport(fontPx:)`. The application
    /// font's line spacing sizes the chrome bar row only and derives no other
    /// geometry. A missing or non-positive base font falls back to the grid seed so
    /// metrics never collapse to a degenerate row.
    public static func resolve(baseFontPx: Double, appFontLineSpacing: Double) -> EditorDrawerMetrics {
        let base = baseFontPx.isFinite && baseFontPx > 0 ? baseFontPx : GridCameraPolicy.seedBaseFontPx
        let lineSpacing = appFontLineSpacing.isFinite ? max(appFontLineSpacing, 0) : 0
        return EditorDrawerMetrics(
            barHeight: Int(lineSpacing) + 2 * Int(fontPx(base, 0.125)) + 2,
            handleHeight: Int(fontPx(base, 1.0 / 3.0)),
            minimumBody: Int(fontPx(base, 17.0 / 5.0)),
            pianoRollReserve: Int(fontPx(base, 10.0)),
            toggleInset: Int(fontPx(base, 0.25)),
            resizeStep: Int(fontPx(base, 0.5)),
            pixel: 1)
    }

    /// Production `EditorDrawer::maximumSectionHeight()`: the piano-roll reserve
    /// bounds *default* body sizing only. It never caps a stored body, a resize or
    /// the aggregate container height.
    public func maximumDefaultBodyHeight(hostHeight: Int) -> Int {
        let reserve = minimumBody + pianoRollReserve
        return hostHeight >= reserve ? hostHeight - pianoRollReserve : hostHeight
    }
}

// MARK: - Page facts

/// Plain, fixed-slot page facts for one layout pass. An absent slot is
/// unavailable. The presenter resolves URLs once, but re-evaluates each attached
/// page's preferred-height closure against the current host and metrics.
public struct EditorDrawerPageFacts: Equatable, Sendable {
    public struct Page: Equatable, Sendable {
        public let resolvedContentUrl: String
        public let preferredBodyHeight: Int
        public let maximumBodyHeight: Int?

        public init(resolvedContentUrl: String, preferredBodyHeight: Int,
                    maximumBodyHeight: Int? = nil) {
            self.resolvedContentUrl = resolvedContentUrl
            self.preferredBodyHeight = preferredBodyHeight
            self.maximumBodyHeight = maximumBodyHeight
        }
    }

    public var automation: Page?
    public var velocity: Page?
    public var voiceChanges: Page?

    public init(automation: Page? = nil, velocity: Page? = nil,
                voiceChanges: Page? = nil) {
        self.automation = automation
        self.velocity = velocity
        self.voiceChanges = voiceChanges
    }

    public subscript(kind: DrawerSectionKind) -> Page? {
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

// MARK: - Published values

/// One section's published values, drawer-local (origin at the container's
/// top-left). A kind with no attached page publishes `available == false`, an empty
/// URL and no rectangle or control at all.
public struct EditorDrawerSectionGeometry: Equatable, Sendable {
    public var available = false
    public var visible = false
    public var contentUrl = ""
    public var bodyX = 0
    public var bodyY = 0
    public var bodyWidth = 0
    public var bodyHeight = 0
    public var handleY = 0
    public var handleHeight = 0
    public var toggleX = 0
    public var toggleY = 0
    public var toggleSize = 0

    public init() {}
}

/// The complete published container state.
public struct EditorDrawerSnapshot: Equatable, Sendable {
    public var height = 0
    public var barVisible = false
    public var barX = 0
    public var barY = 0
    public var barWidth = 0
    public var barHeight = 0
    public var plotOrigin = 0
    public var plotWidth = 0
    public var detentX = 0
    public var detentY = 0
    public var detentSize = 0
    public var detentIconInset = 0.0
    public var automation = EditorDrawerSectionGeometry()
    public var velocity = EditorDrawerSectionGeometry()
    public var voiceChanges = EditorDrawerSectionGeometry()

    public init() {}

    public subscript(kind: DrawerSectionKind) -> EditorDrawerSectionGeometry {
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

// MARK: - Change records

/// A focus request published by one transition. `target` is a section kind raw
/// value, or `-1` for the roll when nothing visible remains.
public struct EditorDrawerFocusRequest: Equatable, Sendable {
    public let revision: Int
    public let target: Int

    public init(revision: Int, target: Int) {
        self.revision = revision
        self.target = target
    }
}

/// One section's persisted chrome values after an interactive change. A `nil`
/// stored height is the unset marker and is written as `0`.
public struct EditorDrawerSectionPreference: Equatable, Sendable {
    public let kind: DrawerSectionKind
    public let visible: Bool
    public let storedBodyHeight: Int?

    public init(kind: DrawerSectionKind, visible: Bool, storedBodyHeight: Int?) {
        self.kind = kind
        self.visible = visible
        self.storedBodyHeight = storedBodyHeight
    }
}

/// What one operation caused: whether the published values changed, the values
/// themselves, a focus request, the preference-change records and the sections
/// whose attached pages the presenter must cancel synchronously.
public struct EditorDrawerChangeSet: Equatable, Sendable {
    public let published: Bool
    public let snapshot: EditorDrawerSnapshot
    public let focusRequest: EditorDrawerFocusRequest?
    public let sectionPreferences: [EditorDrawerSectionPreference]
    public let activePagePreference: DrawerSectionKind?
    public let cancelledSections: [DrawerSectionKind]

    public init(published: Bool, snapshot: EditorDrawerSnapshot,
                focusRequest: EditorDrawerFocusRequest?,
                sectionPreferences: [EditorDrawerSectionPreference],
                activePagePreference: DrawerSectionKind?,
                cancelledSections: [DrawerSectionKind]) {
        self.published = published
        self.snapshot = snapshot
        self.focusRequest = focusRequest
        self.sectionPreferences = sectionPreferences
        self.activePagePreference = activePagePreference
        self.cancelledSections = cancelledSections
    }

    public var isEmpty: Bool {
        !published && focusRequest == nil && sectionPreferences.isEmpty
            && activePagePreference == nil && cancelledSections.isEmpty
    }
}
