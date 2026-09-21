import Foundation
import NativeGridTypography
import PorydawCore
import QtBridge

// The production Voice Changes page: one deep owner for the drawer's Voice
// Changes section, following `src/ui/editordrawer/voicechangearea/`
// (`voicechangearea.cpp`, `voicechangemenu.cpp`) and the rendering half in
// `src/ui/songview/quick/voicechangequick.cpp` for behaviour. It publishes
// primitives and stable item models for QML and owns no camera, clock,
// viewport, history or document lookup: the horizontal projection is
// `EditorCamera`, the playhead is the composition-owned segment the page only
// reads, and every mutation is one existing `SongDocument` lane operation.
//
// Ownership: `ApplicationSession` creates the page for the current document,
// attaches it before `songOpen` publishes, refreshes it from the session's
// existing document/camera/playhead publications, and cancels it synchronously
// before the document owners retire.
//
// Identity: a voice event is identified by the document revision and track it
// was projected from plus its lane occurrence (`LanePoint`'s chunk, event
// index, tick and value). A gesture, picker or context menu freezes that
// occurrence when it opens and revalidates it before every commit, so a motion
// draft, a filter keystroke or a camera scroll can never retarget another
// occurrence.
//
// Voice context: the active program is the track's first program advanced by
// every change at or before the context tick. While transport is playing the
// context tick is the rounded shared-playhead tick; while stopped it is
// `DocumentSession.editCursor`. Slots resolve through the current
// `DocumentSession.bankSlots`; a slot with no parsed voice is published as blank
// (`slotBlank == true`, empty symbol) and never gains a name — only the program
// number and its declared type name are drawn, exactly as the legacy
// `paintTextFor` falls back from the voice name to the type name to "Voice".
//
// Snapping: a plain drag preview and every picker/menu insertion tick snap on the
// shared editing lattice (`GridMetrics.snapTick`), and a drag with the alt
// modifier held snaps on the legacy clock lattice exactly —
// `Grid::snapTick(tick, fine: true)` over `Grid::fineGridTicks()`, which is
// `SongDocument::ticksPerClock()`: both facts come from the document itself
// (`ticksPerBeat` and the song config's `extendedClocks`).
//
// Blocked legacy cases (the audition rows of
// `src/checks/drawerpresentation/voice.cpp`, all inside
// `::voicePickerTransactions`): the case drives `SongView::auditionVoice`
// through the real picker rows — press-and-hold note-on, release note-off, the
// release a filter change forces when it hides the sounding row, the dismissal
// release, then `QCOMPARE(audition.count(), 2)` and
// `QCOMPARE(audition.at(1).at(2).toInt(), 0)` to pin that every note-on is
// paired with its release. That audition sounds an arbitrary voicegroup slot,
// which is `AudioEngine::previewVoice(program, key, velocity)`. The authorized
// Swift surface exposes only `NativeAudio.previewNote(track:key:velocity:)`,
// which sounds the *selected track's* current voice at a key and cannot select
// a program, so substituting it would audition a different voice than the row
// the user pressed. This page therefore publishes no audition control:
// `auditionAvailable` is false, `auditionDiagnostic` names the gap, and the
// picker's accessible description claims selection only.
//
// Minimal approval-gated native contract that would unblock it (one entry point
// beside the existing preview, no QtBridge expansion, no new service, no
// mutation):
//
//     void pd_audio_service_preview_voice(AudioServiceHandle *service,
//                                         int program, int key, int velocity);
//
// with `velocity == 0` meaning note-off, plus the matching Swift wrapper
// `NativeAudio.previewVoice(program: Int, key: UInt8, velocity: UInt8)`.
// `VoicePicker.qml` would then drive a row's held press/release into those two
// calls and the page's `auditionAvailable` would become true; nothing else in
// this file would change.

// MARK: - Page vocabulary

/// The page's published constants. The base font seed mirrors the grid's
/// `GridCameraPolicy.seedBaseFontPx`, which is internal to this module.
public enum VoiceChangesPagePolicy {
    public static let seedBaseFontPx: Double = 13
    /// `kVoiceChangesMaximumHeightInRows`: Voice Changes is the only section
    /// with a page-declared maximum body.
    public static let maximumBodyRows: Double = 2.5
    /// `VoiceChangeArea::Geometry::resolve`: marker hit radius, hover paint
    /// padding and the minimum grid cell, all font-relative.
    public static let markerHitRadiusFactor: Double = 3.0 / 4.0
    public static let hoverPaintPaddingFactor: Double = 1.0 / 6.0
    /// `layout::Space::One` / `layout::Space::Four` multipliers.
    public static let spaceOneFactor: Double = 0.25
    public static let spaceFourFactor: Double = 1.0
    /// `VoiceChangeArea::VoiceMenuAction` ids: production dispatch and the
    /// checks that activate rendered rows both read these.
    public static let changeVoiceAction = 1
    public static let insertVoiceChangeAction = 2
    public static let deleteMarkerAction = 3
    /// `Qt::AlignRight`, the readout's own alignment.
    public static let readoutAlignment = 2
}

/// Where a pointer event landed in the page body. Mirrors the legacy
/// `TimelineInputSurface` split: the gutter never edits.
public enum VoiceInputSurface: Int, Sendable {
    case gutter = 0
    case plot = 1
}

/// Qt pointer buttons as QML carries them (`mouse.button`).
enum VoiceQtButton {
    static let left = 1
    static let right = 2
    static let middle = 4
}

/// Qt keyboard modifier bits as QML carries them (`mouse.modifiers`). The alt
/// bit is the drawer's fine-snap modifier.
public enum VoiceModifier {
    public static let alt = 0x0800_0000
}

/// `m4aVoiceTypeName`: the declared type name for a bank macro ordinal, or `""`
/// for an ordinal the voicegroup editor does not publish as one voice.
public func voiceTypeName(macro: Int32?) -> String {
    switch macro {
    case BankVoiceMacro.directSound, BankVoiceMacro.keysplit: return "Sample"
    case BankVoiceMacro.directSoundNoResample: return "Sample (fixed pitch)"
    case BankVoiceMacro.directSoundAlt: return "Sample (reverse)"
    case BankVoiceMacro.square1, BankVoiceMacro.square1Alt: return "Square 1"
    case BankVoiceMacro.square2, BankVoiceMacro.square2Alt: return "Square 2"
    case BankVoiceMacro.programmableWave, BankVoiceMacro.programmableWaveAlt: return "Wave"
    case BankVoiceMacro.noise, BankVoiceMacro.noiseAlt: return "Noise"
    case BankVoiceMacro.keysplitAll: return "Drumkit"
    default: return ""
    }
}

// MARK: - Lane occurrence identity

/// One voice event's document-owned identity. `LanePoint` carries the chunk and
/// event index the document itself uses, and the tick and value join them so a
/// re-resolution can never accept a different occurrence.
public struct VoiceOccurrence: Equatable, Sendable {
    public var chunk: Int
    public var eventIndex: Int
    public var tick: Tick
    public var value: Int

    public init(chunk: Int, eventIndex: Int, tick: Tick, value: Int) {
        self.chunk = chunk
        self.eventIndex = eventIndex
        self.tick = tick
        self.value = value
    }

    public init(_ point: LanePoint) {
        self.init(chunk: point.chunk, eventIndex: point.eventIndex,
                  tick: point.tick, value: point.value)
    }

    /// The bridge-side spelling QML carries. `LanePoint` is not a bridge type,
    /// so identity crosses as text while the page keeps the typed occurrence.
    public var text: String { "\(chunk).\(eventIndex).\(tick).\(value)" }

    /// The occurrence as the lane's own point, for the semantic lane operations.
    public var point: LanePoint {
        LanePoint(chunk: chunk, eventIndex: eventIndex, tick: tick, value: value)
    }
}

/// The page's pure voice-lane rules: label text, context resolution, hit
/// testing and occurrence lookup, all driven from values a check can build.
public enum VoiceLanePolicy {
    /// `VoiceChangeArea::voiceSlotAt`: the track's first program advanced by
    /// every change at or before `tick`. `-1` means "no slot".
    public static func slot(firstProgram: Int, tick: Tick, points: [LanePoint]) -> Int {
        var slot = firstProgram
        for point in points where point.tick <= tick { slot = point.value }
        return slot
    }

    /// The next change strictly after `tick`, or `nil` when the context runs to
    /// the song's end.
    public static func endTick(after tick: Tick, points: [LanePoint]) -> Tick? {
        points.first { $0.tick > tick }?.tick
    }

    /// The document's current occurrence at an exact tick: the value the picker
    /// and deletion paths re-resolve against. Several events at one tick
    /// collapse to the last, exactly as the legacy projection would.
    public static func occurrence(at tick: Tick, in points: [LanePoint]) -> VoiceOccurrence? {
        points.last { $0.tick == tick }.map(VoiceOccurrence.init)
    }

    /// The occurrence a frozen identity still names, or `nil` when the lane no
    /// longer holds exactly it.
    public static func occurrence(_ identity: VoiceOccurrence,
                                  in points: [LanePoint]) -> VoiceOccurrence? {
        points.first { VoiceOccurrence($0) == identity }.map(VoiceOccurrence.init)
    }

    /// The nearest marker whose drawn x is inside the font-relative hit radius;
    /// ties keep the later point, exactly as the legacy scan does.
    public static func marker(at x: Double, points: [LanePoint], displayX: (Tick) -> Double,
                              hitRadius: Double) -> LanePoint? {
        var best: LanePoint?
        var distance = hitRadius + 1
        for point in points {
            let candidate = abs(displayX(point.tick) - x)
            if candidate <= hitRadius, candidate <= distance {
                best = point
                distance = candidate
            }
        }
        return best
    }

    /// `VoiceChangeArea::paintTextFor`: the program number plus the slot's short
    /// name. A blank or unresolvable slot keeps the program number and gains no
    /// name of its own.
    public static func label(slot: Int, view: BankSlotView?) -> String {
        guard slot >= 0, let view else { return "" }
        guard let voice = view.voice else { return String(format: "%03d", slot) }
        let type = voiceTypeName(macro: voice.macro)
        let name = voice.symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let short: String
        if !name.isEmpty {
            short = type.isEmpty ? name : "\(name) (\(type))"
        } else {
            short = type.isEmpty ? "Voice" : type
        }
        return String(format: "%03d %@", slot, short)
    }

    /// The hover spelling: the label with the legacy arrow prefix.
    public static func hoverLabel(_ label: String) -> String {
        label.isEmpty ? "" : "→ \(label)"
    }

    /// `SongDocument::ticksPerClock`: one mid2agb clock is
    /// `division / (24 * (extendedClocks ? 2 : 1))` ticks, floored at one. This
    /// is the stride of the legacy clock lattice, and it is pure document math:
    /// `ticksPerBeat` is the file's division and `extendedClocks` is the song
    /// config's own flag.
    public static func clockTicks(division: Int, extendedClocks: Bool) -> Tick {
        let clocksPerBeat = 24 * (extendedClocks ? 2 : 1)
        return Tick(max(1, division / clocksPerBeat))
    }

    /// `Grid::snapTick(tick, fine: true)`: the absolute clock lattice anchored at
    /// zero with the clock stride, rounded half-up (`Grid::Lattice::round` with
    /// `tiesUp`), clamped to the song's tick domain.
    public static func fineSnap(_ tick: Double, clockTicks: Tick) -> Tick {
        let stride = Double(Swift.max(1, Int(clockTicks)))
        let limit = Double(TimeDefaults.maxTick)
        let position = Swift.min(Swift.max(0, tick), limit)
        let lower = (position / stride).rounded(.down) * stride
        let upper = Swift.min(lower + stride, limit)
        let lowerDistance = position - lower
        let upperDistance = upper - position
        return Tick(lowerDistance < upperDistance ? lower : upper)
    }
}

// MARK: - Published records

/// One drawn voice-change marker: its occurrence identity, the marker rule, the
/// label box the projection laid out, and its interaction state.
@MainActor
@QtBridgeable
public final class VoiceMarkerHandle {
    public var identity: String = ""
    public var tick: Double = 0
    public var value: Int = 0
    /// `true` when the slot the marker names publishes no parsed voice.
    public var slotBlank: Bool = false
    public var symbol: String = ""
    public var label: String = ""
    public var labelRect: [String: QVariantSettable] = VoiceMarkerHandle.rect(0, 0, 0, 0)
    public var labelColor: String = ""
    /// The marker rule: `x` is the marker's own projected position.
    public var x: Double = 0
    public var lineTop: Double = 0
    public var lineBottom: Double = 0
    public var lineWidth: Double = 0
    public var lineColor: String = ""
    public var selected: Bool = false
    public var hovered: Bool = false
    public var preview: Bool = false
    public var offscreen: Bool = false
    public var primitiveName: String = "voiceChangeMarker"

    static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double)
        -> [String: QVariantSettable]
    {
        ["x": x, "y": y, "width": w, "height": h]
    }

    static func rectMatches(_ lhs: [String: QVariantSettable],
                            _ rhs: [String: QVariantSettable]) -> Bool {
        for key in ["x", "y", "width", "height"] {
            guard let left = lhs[key] as? Double, let right = rhs[key] as? Double,
                  left == right else { return false }
        }
        return true
    }

    @QtIgnored
    func matches(_ other: VoiceMarkerHandle) -> Bool {
        identity == other.identity && tick == other.tick && value == other.value
            && slotBlank == other.slotBlank && symbol == other.symbol
            && label == other.label && labelColor == other.labelColor
            && x == other.x && lineTop == other.lineTop && lineBottom == other.lineBottom
            && lineWidth == other.lineWidth && lineColor == other.lineColor
            && selected == other.selected && hovered == other.hovered
            && preview == other.preview && offscreen == other.offscreen
            && primitiveName == other.primitiveName
            && VoiceMarkerHandle.rectMatches(labelRect, other.labelRect)
    }
}

/// One picker row: the program and the label the current bank publishes for it.
@MainActor
@QtBridgeable
public final class VoicePickerRowHandle {
    public var program: Int = 0
    public var label: String = ""
    /// `true` when this slot publishes no parsed voice. The row stays selectable
    /// and never gains a name.
    public var blank: Bool = false
    public var symbol: String = ""
    public var selected: Bool = false
    public var primitiveName: String = "voicePickerRow"

    @QtIgnored
    func matches(_ other: VoicePickerRowHandle) -> Bool {
        program == other.program && label == other.label && blank == other.blank
            && symbol == other.symbol && selected == other.selected
            && primitiveName == other.primitiveName
    }
}

/// One typed context-menu row: the legacy `VoiceMenuAction` id and its label.
@MainActor
@QtBridgeable
public final class VoiceMenuRowHandle {
    public var actionId: Int = 0
    public var text: String = ""
    public var primitiveName: String = "voiceChangeMenuRow"

    @QtIgnored
    func matches(_ other: VoiceMenuRowHandle) -> Bool {
        actionId == other.actionId && text == other.text
            && primitiveName == other.primitiveName
    }
}

// MARK: - Frozen interaction state

/// One captured target: the document/track identity it was captured in, the
/// snapped tick, and the occurrence when the press hit a marker.
private struct VoiceTarget {
    var revision: UInt64
    var track: Int
    var tick: Tick
    var occurrence: VoiceOccurrence?
}

/// One in-flight marker drag, frozen at press: the occurrence, the track and
/// the revision the press projected, plus the draft tick the motion shows.
private struct VoiceDragState {
    var revision: UInt64
    var track: Int
    var occurrence: VoiceOccurrence
    var identity: String
    var pressX: Double
    var previewTick: Tick
    var active: Bool = false
}

/// One open picker: the captured target plus the filter and row drafts over the
/// current bank. Only the target may be written.
private struct VoicePickerState {
    var target: VoiceTarget
    var initialSlot: Int
    var filter: String = ""
    var program: Int = -1

    var title: String { target.occurrence == nil ? "Insert voice change" : "Change voice" }
}

/// One open context menu: the captured target plus the anchor it opened at.
private struct VoiceMenuState {
    var target: VoiceTarget
    var anchorX: Double
    var anchorY: Double
}

/// The page's own captions, measured through the same native font metrics the
/// roll measures its text with.
@MainActor
private final class VoiceCaption {
    let fontMap: [String: QVariantSettable]
    let height: Double
    private let session: OpaquePointer

    init(pixelSize: Int, weight: Int) {
        let family = VoiceChangesPage.fontFamily
        fontMap = ["family": family, "pixelSize": pixelSize, "weight": weight,
                   "letterSpacing": 0.0]
        session = family.withCString { sgf_create($0, Int32(pixelSize), Int32(weight), 0)! }
        height = sgf_extents(session).height
    }

    isolated deinit { sgf_destroy(session) }

    func advance(_ text: String) -> Double { text.withCString { sgf_advance(session, $0) } }

    /// `QFontMetricsF::elidedText(..., Qt::ElideRight, width)`: the widest prefix
    /// plus the ellipsis that fits.
    func elided(_ text: String, toWidth width: Double) -> String {
        guard width > 0, advance(text) > width else { return text }
        var characters = Array(text)
        while !characters.isEmpty {
            characters.removeLast()
            let candidate = String(characters) + "…"
            if advance(candidate) <= width { return candidate }
        }
        return "…"
    }
}

// MARK: - Page owner

/// The production Voice Changes page. Every published value derives from the
/// current document session; every mutation is one existing lane operation
/// guarded by the revision and occurrence captured when the interaction began.
@MainActor
@QtBridgeable
public final class VoiceChangesPage: EditorDrawerPage {
    /// The fixed production QML URL, resolved once by the container at attach.
    public static let contentUrl = "qrc:/porydaw/drawer/VoiceChangesPage.qml"

    @QtIgnored public let sectionKind: DrawerSectionKind = .voiceChanges
    @QtIgnored public var contentUrl: String { Self.contentUrl }
    /// Production's Voice Changes default body: `minBody`, bounded by
    /// `minBody * kVoiceChangesMaximumHeightInRows`.
    @QtIgnored public var bodyPolicy: EditorDrawerBodyPolicy
    /// The container's follow-scroll gate: a drag, a pan, an open picker or an
    /// open menu is an active interaction.
    public var interactionActive: Bool = false

    // MARK: Published body facts

    public var plotOrigin: Double = 0
    public var plotWidth: Double = 0
    public var plotHeight: Double = 0
    public var devicePixelRatio: Double = 1
    public var baseFontPx: Double = GridCameraPolicy.seedBaseFontPx
    public var captionFont: [String: QVariantSettable] = [:]
    public var titleFont: [String: QVariantSettable] = [:]
    /// `false` while no track is presented: the plot draws its own message then
    /// and the gutter carries the title alone.
    public var trackAvailable: Bool = false
    public var plotMessage: String = "No track selected"
    public var gutterTitle: String = "Voice"
    public var gutterTexts: QListModel<SceneText> = QListModel()
    /// The current-context readout: the label of the program the effective
    /// context tick resolves to, right-aligned in the plot.
    public var readoutText: String = ""
    public var readoutVisible: Bool = false
    public var readoutRect: [String: QVariantSettable] = VoiceMarkerHandle.rect(0, 0, 0, 0)
    public var readoutAlignment: Int = VoiceChangesPagePolicy.readoutAlignment
    public var contextSlot: Int = -1
    public var contextBlank: Bool = true
    public var contextSymbol: String = ""
    /// The hover transient: the background tick's slot label, or a hovered
    /// marker's own tick with no label.
    public var hoverVisible: Bool = false
    public var hoverText: String = ""
    public var hoverLabelRect: [String: QVariantSettable] = VoiceMarkerHandle.rect(0, 0, 0, 0)
    public var hoverTick: Double = 0
    /// `Qt::SizeHorCursor` (3) while a marker drag is active, `Qt::ArrowCursor`
    /// (0) otherwise.
    public var cursorKind: Int = 0
    /// The live interaction: whether a frozen drag owns a selection, and where
    /// its draft draws.
    public var previewVisible: Bool = false
    public var previewX: Double = 0
    public var previewTick: Double = 0
    public var selectedIdentity: String = ""

    // MARK: Published modal state

    public var menuOpen: Bool = false
    public var menuX: Double = 0
    public var menuY: Double = 0
    public var pickerOpen: Bool = false
    public var pickerTitle: String = ""
    public var pickerFilter: String = ""
    public var pickerIndex: Int = -1
    public var pickerHasMatch: Bool = false
    public var pickerEmptyText: String = "No matching voices"
    /// Voice audition is not reachable through the authorized Swift/native audio
    /// interface, so the page publishes no control that claims it.
    public var auditionAvailable: Bool = false
    public var auditionDiagnostic: String =
        "Voice audition needs the native voice preview the Swift audio service "
        + "does not expose; this picker selects only."

    // MARK: Published models

    public var markers: QListModel<VoiceMarkerHandle> = QListModel()
    public var heldSpans: QListModel<SceneRect> = QListModel()
    public var gridLines: QListModel<SceneRect> = QListModel()
    public var pickerRows: QListModel<VoicePickerRowHandle> = QListModel()
    public var menuRows: QListModel<VoiceMenuRowHandle> = QListModel()

    // MARK: Diagnostics

    /// Distinct static-content rebuilds. Shared-playhead movement inside one
    /// voice span, and repeated equal publications, rebuild nothing.
    @QtIgnored public private(set) var contentBuildCount: UInt64 = 0
    /// Shared-playhead presentations the page consumed.
    @QtIgnored public private(set) var playheadPresentationCount: UInt64 = 0
    /// Presentations that crossed a voice context: the readout/indicator change.
    @QtIgnored public private(set) var contextChangeCount: UInt64 = 0
    @QtIgnored public private(set) var presentedContextTick: Tick = 0
    @QtIgnored public private(set) var presentedContextSlot: Int = -1
    @QtIgnored public private(set) var presentedPlaying = false
    @QtIgnored private var lastPresentedPublication: (tick: Tick, playing: Bool)?

    // MARK: Check-facing state

    @QtIgnored public var hasGesture: Bool { drag != nil }
    @QtIgnored public var hasPan: Bool { panRevision != nil }
    @QtIgnored public var hasPicker: Bool { picker != nil }
    @QtIgnored public var hasMenu: Bool { menu != nil }
    @QtIgnored public var publishedMarkers: [VoiceMarkerHandle] { published }
    @QtIgnored public var markerIdentities: [String] { published.map(\.identity) }
    @QtIgnored public var markerTicks: [Tick] { published.map { Tick($0.tick) } }
    @QtIgnored public var frozenOccurrence: VoiceOccurrence? { drag?.occurrence }
    @QtIgnored public var frozenIdentity: String? { drag?.identity }
    @QtIgnored public var dragPreviewTick: Tick? { drag?.previewTick }
    @QtIgnored public var dragActive: Bool { drag?.active ?? false }
    @QtIgnored public var pickerTargetTick: Tick? { picker?.target.tick }
    @QtIgnored public var pickerTargetIdentity: String? { picker?.target.occurrence?.text }
    @QtIgnored public var menuTargetTick: Tick? { menu?.target.tick }
    @QtIgnored public var menuTargetIdentity: String? { menu?.target.occurrence?.text }
    @QtIgnored public var pickerRowValues: [VoicePickerRowHandle] { pickerRowSnapshots }
    @QtIgnored public var pickerProgram: Int { picker?.program ?? -1 }
    @QtIgnored public var pickerRowPrograms: [Int] { pickerRowSnapshots.map(\.program) }
    @QtIgnored public var menuRowActions: [Int] { menuRows.asArray.map(\.actionId) }
    @QtIgnored public var publishedSlotCount: Int { session?.bankSlots.count ?? 0 }
    @QtIgnored public var presentedContextLabel: String { contextLabel(at: contextSlot) }

    /// The label the current bank publishes for one slot, or `""` when the slot
    /// does not exist.
    @QtIgnored
    public func contextLabel(at slot: Int) -> String {
        let views = slotViews()
        guard views.indices.contains(slot) else { return "" }
        return VoiceLanePolicy.label(slot: slot, view: views[slot])
    }

    /// The presented context span's end tick: the boundary a later presentation
    /// has to cross to change the readout, or `TimeDefaults.noTick` when the
    /// span runs to the song's end.
    @QtIgnored public var presentedContextEndTick: Tick {
        VoiceLanePolicy.endTick(after: presentedContextTick, points: lanePoints())
            ?? TimeDefaults.noTick
    }

    @QtIgnored private weak var session: DocumentSession?
    @QtIgnored private var palette = GridPalette()
    @QtIgnored private var caption: VoiceCaption?
    @QtIgnored private var title: VoiceCaption?
    @QtIgnored private var published: [VoiceMarkerHandle] = []
    @QtIgnored private var pickerRowSnapshots: [VoicePickerRowHandle] = []
    @QtIgnored private var drag: VoiceDragState?
    @QtIgnored private var panRevision: UInt64?
    @QtIgnored private var previousX: Double = 0
    @QtIgnored private var picker: VoicePickerState?
    @QtIgnored private var menu: VoiceMenuState?
    @QtIgnored private var hoverIdentity: String?
    @QtIgnored private var dragDistance: Double = 10
    @QtIgnored private var contextTick: Tick = 0
    @QtIgnored private var playing = false
    @QtIgnored private var lastContextKey: VoiceContextKey?

    private struct VoiceContextKey: Equatable {
        var slot: Int
        var playing: Bool
    }

    public init(baseFontPx: Double = VoiceChangesPagePolicy.seedBaseFontPx) {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        let minimum = max(1, Int((base * 17.0 / 5.0).rounded()))
        let maximum = Int((Double(minimum) * VoiceChangesPagePolicy.maximumBodyRows).rounded())
        bodyPolicy = EditorDrawerBodyPolicy(maximumBodyHeight: maximum) { _, _ in minimum }
        self.baseFontPx = base
        publishTypography()
    }

    /// Installs the document and palette owners. Called before the container
    /// attaches the page, so no publication can precede the session it reads.
    @QtIgnored
    public func attach(session: DocumentSession, palette: GridPalette) {
        self.session = session
        self.palette = palette
        contextTick = session.editCursor
        rebuildContent()
    }

    /// Drops the session and everything the page owns. Called after the host
    /// acknowledged scene removal and before the document owners retire.
    @QtIgnored
    public func detach() {
        cancelSectionInteraction()
        session = nil
        publishMarkers([])
        syncRects(heldSpans, [])
        syncRects(gridLines, [])
        syncTexts(gutterTexts, [])
    }

    // MARK: Composition input

    /// The page body's own facts, pushed by the production QML as it lays out:
    /// the same plot origin and base font the roll and the container use.
    public func configureBody(width: Double, height: Double, gutter: Double,
                              devicePixelRatio: Double, baseFontPx: Double,
                              dragDistance: Double) {
        let nextWidth = max(0, width.isFinite ? width : 0)
        let nextHeight = max(0, height.isFinite ? height : 0)
        let nextGutter = max(0, gutter.isFinite ? gutter : 0)
        let nextDpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        let nextFont = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        if dragDistance.isFinite, dragDistance > 0, dragDistance != self.dragDistance {
            self.dragDistance = dragDistance
        }
        let fontChanged = nextFont != self.baseFontPx
        let changed = nextWidth != plotWidth || nextHeight != plotHeight
            || nextGutter != plotOrigin || nextDpr != self.devicePixelRatio || fontChanged
        plotWidth = nextWidth
        plotHeight = nextHeight
        plotOrigin = nextGutter
        self.devicePixelRatio = nextDpr
        if fontChanged {
            self.baseFontPx = nextFont
            publishTypography()
        }
        if changed { rebuildContent() }
    }

    // MARK: Session refresh

    /// Document, Undo/Redo, track or bank publication: a frozen gesture, picker
    /// or menu whose captured identity no longer holds cancels, then content
    /// rebuilds. Nothing here re-points a captured target at a new occurrence.
    @QtIgnored
    public func refreshFromDocument() {
        guard let session else { return }
        let track = session.selectedTrack ?? -1
        let revision = session.document.revision
        if let live = drag, live.revision != revision || live.track != track {
            cancelDrag()
        }
        if let live = panRevision, live != revision { cancelPan() }
        if let live = picker, live.target.revision != revision || live.target.track != track {
            cancelPicker()
        }
        if let live = menu, live.target.revision != revision || live.target.track != track {
            dismissVoiceMenu()
        }
        contextTick = session.editCursor
        rebuildContent()
    }

    /// Camera-only publication: the same markers at new plot positions.
    @QtIgnored
    public func refreshCamera() {
        guard session != nil else { return }
        rebuildContent()
    }

    /// One shared-playhead presentation, delivered by `ApplicationSession`'s
    /// Swift fan-out from `SharedPlayheadPresenter.onPresentation` — never from
    /// QML. Movement inside one voice span only re-publishes the readout; a
    /// context or playing-state change rebuilds.
    @QtIgnored
    public func refreshPlayhead(tick: Double, playing: Bool) {
        guard session != nil else { return }
        // The drawer's one context rounding rule, shared with the Velocity page:
        // the shared playhead's tick rounded to the nearest whole tick.
        let resolvedTick = velocityContextTick(tick)
        if let last = lastPresentedPublication, last.tick == resolvedTick,
           last.playing == playing
        {
            return
        }
        lastPresentedPublication = (resolvedTick, playing)
        playheadPresentationCount &+= 1
        let playingChanged = self.playing != playing
        self.playing = playing
        contextTick = resolvedTick
        let next = contextKey(at: effectiveContextTick())
        let contextChanged = lastContextKey != next
        lastContextKey = next
        presentedContextTick = resolvedTick
        presentedContextSlot = next.slot
        presentedPlaying = playing
        if contextChanged || playingChanged {
            contextChangeCount &+= 1
            rebuildContent()
        } else {
            publishReadout()
        }
    }

    // MARK: Page seam

    /// The page's local Escape: an open picker, menu, drag, pan or hover claims
    /// the key; otherwise it stays unhandled for the shared routing.
    public func handleEscape() -> Bool {
        if picker != nil || menu != nil {
            dismissModal()
            return true
        }
        if drag != nil || panRevision != nil {
            cancelSectionInteraction()
            return true
        }
        guard hoverIdentity != nil || hoverVisible else { return false }
        clearHover()
        return true
    }

    /// Ends every interaction the page owns without committing anything. Called
    /// synchronously by the container before a hide, a replace or a global
    /// cancellation publishes.
    public func cancelSectionInteraction() {
        cancelDrag()
        cancelPan()
        cancelPicker()
        dismissVoiceMenu()
        clearHover()
        refreshInteractionPublished()
    }

    // MARK: Pointer input

    /// One press. `true` means the page consumed it. A press while a picker or
    /// menu is open dismisses it and starts nothing: the dismissal never
    /// retargets the captured occurrence.
    @discardableResult
    public func pointerPress(x: Double, y: Double, surface: Int, button: Int,
                             modifiers: Int) -> Bool {
        guard session != nil, let input = VoiceInputSurface(rawValue: surface) else { return false }
        if picker != nil || menu != nil {
            dismissModal()
            previousX = x
            return true
        }
        if input == .gutter {
            clearHover()
            return false
        }
        previousX = x
        switch button {
        case VoiceQtButton.right:
            // Capture before any signal-producing step: the target is fixed from
            // live state, so nothing after the capture can drift it.
            guard let target = captureTarget(at: x) else { return true }
            openMenu(target, anchorX: x, anchorY: max(0, y))
            return true
        case VoiceQtButton.middle:
            clearHover()
            panRevision = session?.document.revision
            refreshInteractionPublished()
            return true
        case VoiceQtButton.left:
            clearHover()
            let hit = markerHit(at: x)
            guard let hit else {
                selectedIdentity = ""
                refreshInteractionPublished()
                projectMarkers(projectedEntries(lanePoints()))
                return true
            }
            let occurrence = VoiceOccurrence(hit)
            selectedIdentity = occurrence.text
            drag = VoiceDragState(
                revision: session?.document.revision ?? 0,
                track: session?.selectedTrack ?? -1,
                occurrence: occurrence, identity: occurrence.text, pressX: x,
                previewTick: occurrence.tick)
            refreshInteractionPublished()
            projectMarkers(projectedEntries(lanePoints()))
            return true
        default:
            return false
        }
    }

    /// One move: the frozen drag drafts its preview tick, a pan scrolls the
    /// shared camera, and otherwise the pointer is hover only. `modifiers` is the
    /// drag's own: the alt modifier switches the preview to the clock lattice.
    @discardableResult
    public func pointerMove(x: Double, y: Double, buttons: Int, modifiers: Int = 0) -> Bool {
        guard session != nil else { return false }
        _ = y
        _ = buttons
        if var live = drag {
            if !live.active {
                guard abs(x - live.pressX) >= dragDistance else { return true }
                live.active = true
                clearHover()
            }
            let tick = snapTick(at: x, fine: modifiers & VoiceModifier.alt != 0)
            let changed = tick != live.previewTick
            live.previewTick = tick
            drag = live
            cursorKind = 3
            if changed {
                projectMarkers(projectedEntries(lanePoints()))
                publishTransient()
            }
            return true
        }
        if panRevision != nil {
            let delta = x - previousX
            previousX = x
            if delta != 0, let session {
                session.mutateCamera { $0.setHScroll($0.snapshot.scrollX - delta) }
            }
            return true
        }
        updateHover(at: x)
        return true
    }

    /// One release: the drag's only document mutation, and a pan's end.
    @discardableResult
    public func pointerRelease(x: Double, y: Double, button: Int) -> Bool {
        guard let session else { return false }
        _ = x
        _ = y
        if button == VoiceQtButton.middle {
            cancelPan()
            return true
        }
        guard button == VoiceQtButton.left, let live = drag else { return false }
        let wasActive = live.active
        let previewTick = live.previewTick
        cancelDrag()
        guard wasActive, previewTick != live.occurrence.tick,
              live.revision == session.document.revision,
              currentTrack(session) == live.track
        else { return true }
        guard let occurrence = occurrence(for: live.occurrence, session: session) else {
            return true
        }
        session.document.moveLanePoints(track: live.track, lane: .voice, moves: [
            LanePointMove(point: occurrence.point, tick: previewTick,
                          value: occurrence.value),
        ])
        return true
    }

    /// The pointer left: hover clears, a live gesture keeps its frozen state.
    public func pointerLeave() {
        guard drag == nil, panRevision == nil else { return }
        clearHover()
    }

    /// One double-click: the legacy direct picker entry. It captures the same
    /// guarded target the context menu's own rows hand over.
    @discardableResult
    public func pointerDoubleClick(x: Double, y: Double) -> Bool {
        guard session != nil else { return false }
        _ = y
        guard let target = captureTarget(at: x) else { return true }
        openPicker(target)
        return true
    }

    // MARK: Picker

    /// Draft filtering: presentation only, over the current bank's labels.
    public func setPickerFilter(text: String) {
        guard var live = picker else { return }
        let filter = String(text.prefix(64))
        guard filter != live.filter else { return }
        live.filter = filter
        live.program = Self.firstProgram(filter: filter, slots: slotViews())
        picker = live
        publishPicker()
    }

    /// Row selection from the list's own press.
    public func selectPickerRow(index: Int) {
        guard let live = picker else { return }
        selectPickerProgram(Self.program(at: index, filter: live.filter, slots: slotViews()))
    }

    /// Arrow navigation over the filtered rows.
    public func movePickerSelection(delta: Int) {
        guard let live = picker else { return }
        let programs = Self.visiblePrograms(filter: live.filter, slots: slotViews())
        guard !programs.isEmpty else { return }
        guard let current = programs.firstIndex(of: live.program) else {
            selectPickerProgram(programs[0])
            return
        }
        selectPickerProgram(programs[min(max(current + delta, 0), programs.count - 1)])
    }

    /// Acceptance: one existing lane operation for the captured target — a value
    /// replacement when the document still holds an occurrence at the captured
    /// tick, an insertion otherwise — or nothing at all. `true` means a write
    /// happened.
    ///
    /// The only refusal besides a stale capture is production's own:
    /// `VoicePicker::accept` returns early when no row matches, so a program slot
    /// the bank holds no parsed voice for is still selectable — the band then
    /// draws that program's number with its blank truth, exactly as the legacy
    /// projection does.
    ///
    /// A captured marker is replaced only while the document still holds exactly
    /// that occurrence: the occurrence's own value is the one the picked slot
    /// replaces, and a lane the document rebuilt under the capture writes
    /// nothing. The captured *tick* is the insertion target only for a capture
    /// that had no occurrence at all (the empty-lane arm), which is exactly the
    /// legacy `addLanePoint(track, lane, tick, voice)` case.
    @discardableResult
    public func acceptPicker() -> Bool {
        guard let live = picker, live.program >= 0 else { return false }
        let selected = live.program
        let target = live.target
        let views = slotViews()
        cancelPicker()
        guard let session, target.revision == session.document.revision,
              currentTrack(session) == target.track, views.indices.contains(selected)
        else { return false }
        if let captured = target.occurrence {
            guard let existing = occurrence(for: captured, session: session) else { return false }
            guard existing.value != selected else { return false }
            session.document.moveLanePoints(track: target.track, lane: .voice, moves: [
                LanePointMove(point: existing.point, tick: existing.tick, value: selected),
            ])
            return true
        }
        session.document.writeLane(track: target.track, lane: .voice, from: target.tick,
                                   through: target.tick,
                                   points: [LaneWrite(tick: target.tick, value: selected)])
        return true
    }

    /// Dismissal: capture, filter, row draft and current program drop without a
    /// write.
    public func cancelPicker() {
        guard picker != nil else { return }
        picker = nil
        pickerOpen = false
        pickerTitle = ""
        pickerFilter = ""
        pickerIndex = -1
        pickerHasMatch = false
        syncPickerRows([])
        refreshInteractionPublished()
    }

    // MARK: Context menu

    /// One typed row activation. Every path revalidates the captured
    /// document/track/point identity first, and a stale pick writes nothing.
    @discardableResult
    public func activateMenuAction(actionId: Int) -> Bool {
        guard let live = menu else { return false }
        dismissVoiceMenu()
        guard let session, live.target.revision == session.document.revision,
              currentTrack(session) == live.target.track
        else { return false }
        switch actionId {
        case VoiceChangesPagePolicy.changeVoiceAction,
             VoiceChangesPagePolicy.insertVoiceChangeAction:
            openPicker(live.target)
            return true
        case VoiceChangesPagePolicy.deleteMarkerAction:
            // The delete row exists only for a marker capture, and it deletes
            // exactly that occurrence or nothing.
            guard let captured = live.target.occurrence,
                  let current = occurrence(for: captured, session: session)
            else { return false }
            session.document.deleteLanePoints(track: live.target.track, lane: .voice,
                                              points: [current.point])
            return true
        default:
            return false
        }
    }

    /// One rendered row activation by its published index: the page maps the row
    /// it published to its typed action, so no QML surface has to read a bridged
    /// row object back across the boundary.
    @discardableResult
    public func activateMenuRow(index: Int) -> Bool {
        let rows = menuRows.asArray
        guard rows.indices.contains(index) else { return false }
        return activateMenuAction(actionId: rows[index].actionId)
    }

    /// Outside dismissal and the menu's own Escape: no action, no write.
    public func dismissVoiceMenu() {
        guard menu != nil else { return }
        menu = nil
        menuOpen = false
        syncMenuRows([])
        refreshInteractionPublished()
    }

    /// Dismisses whichever modal surface is open. The press that dismisses
    /// activates neither a row nor a slot.
    public func dismissModal() {
        cancelPicker()
        dismissVoiceMenu()
    }

    // MARK: Internals: capture

    private func currentTrack(_ session: DocumentSession) -> Int? {
        guard let track = session.selectedTrack, track >= 0,
              track < session.timeline.tracks.count else { return nil }
        return track
    }

    /// The occurrence as the document still holds it — exactly it, or nothing.
    /// A lane the document rebuilt under the capture resolves no occurrence and
    /// every caller no-ops: a tick lookup would silently retarget whatever now
    /// sits at that tick, which is the one thing the capture exists to prevent.
    private func occurrence(for identity: VoiceOccurrence,
                            session: DocumentSession) -> VoiceOccurrence? {
        guard let track = currentTrack(session) else { return nil }
        return VoiceLanePolicy.occurrence(identity,
                                          in: session.document.lanePoints(track: track,
                                                                          lane: .voice))
    }

    /// `VoiceChangeArea::captureTargetAt`: the marker under the press, or the
    /// snapped tick of the press itself.
    private func captureTarget(at x: Double) -> VoiceTarget? {
        guard let session, let track = currentTrack(session) else { return nil }
        if let hit = markerHit(at: x) {
            return VoiceTarget(revision: session.document.revision, track: track, tick: hit.tick,
                               occurrence: VoiceOccurrence(hit))
        }
        return VoiceTarget(revision: session.document.revision, track: track, tick: snapTick(at: x),
                           occurrence: nil)
    }

    private func openPicker(_ target: VoiceTarget) {
        let views = slotViews()
        let filter = ""
        let initial = target.occurrence?.value
            ?? VoiceLanePolicy.slot(firstProgram: firstProgram(), tick: target.tick,
                                    points: lanePoints())
        let visible = Self.visiblePrograms(filter: filter, slots: views)
        picker = VoicePickerState(target: target, initialSlot: initial, filter: filter,
                                  program: visible.contains(initial) ? initial
                                      : (visible.first ?? -1))
        pickerOpen = true
        pickerTitle = picker?.title ?? ""
        pickerFilter = filter
        refreshInteractionPublished()
        publishPicker()
    }

    private func openMenu(_ target: VoiceTarget, anchorX: Double, anchorY: Double) {
        menu = VoiceMenuState(target: target, anchorX: anchorX, anchorY: anchorY)
        menuOpen = true
        menuX = anchorX
        menuY = anchorY
        if target.occurrence != nil {
            syncMenuRows([Self.menuRow(VoiceChangesPagePolicy.changeVoiceAction, "Change voice"),
                          Self.menuRow(VoiceChangesPagePolicy.deleteMarkerAction, "Delete")])
        } else {
            syncMenuRows([Self.menuRow(VoiceChangesPagePolicy.insertVoiceChangeAction,
                                       "Insert voice change")])
        }
        refreshInteractionPublished()
    }

    private static func menuRow(_ actionId: Int, _ text: String) -> VoiceMenuRowHandle {
        let row = VoiceMenuRowHandle()
        row.actionId = actionId
        row.text = text
        return row
    }

    // MARK: Internals: hover

    /// `VoiceChangeArea::updateHover`: a hovered marker publishes its own tick
    /// and no label; a background hover publishes the snapped tick's slot label.
    private func updateHover(at x: Double) {
        guard plotWidth > 0, plotHeight > 0, session != nil else {
            clearHover()
            return
        }
        let pad = fontPx(VoiceChangesPagePolicy.spaceOneFactor)
        if let hit = markerHit(at: x) {
            let identity = VoiceOccurrence(hit).text
            let lineX = xForTick(hit.tick)
            let rect = VoiceMarkerHandle.rect(lineX + pad, 0, max(0, plotWidth - lineX),
                                              plotHeight)
            guard hoverIdentity != identity || hoverVisible || !hoverText.isEmpty
                || !VoiceMarkerHandle.rectMatches(hoverLabelRect, rect)
            else { return }
            hoverIdentity = identity
            hoverTick = Double(hit.tick)
            hoverText = ""
            hoverVisible = false
            hoverLabelRect = rect
            publishReadout()
            return
        }
        let tick = snapTick(at: x)
        let slot = VoiceLanePolicy.slot(firstProgram: firstProgram(), tick: tick,
                                        points: lanePoints())
        let label = VoiceLanePolicy.hoverLabel(contextLabel(at: slot))
        guard !label.isEmpty else {
            clearHover()
            return
        }
        let lineX = xForTick(tick)
        hoverIdentity = nil
        hoverTick = Double(tick)
        setPublished(&hoverText, label)
        setPublishedRect(&hoverLabelRect,
                         VoiceMarkerHandle.rect(lineX + pad, 0, max(0, plotWidth - lineX),
                                                plotHeight))
        setPublished(&hoverVisible, true)
        publishReadout()
    }

    private func clearHover() {
        guard hoverIdentity != nil || hoverVisible || !hoverText.isEmpty || hoverTick != 0
        else { return }
        hoverIdentity = nil
        hoverText = ""
        hoverVisible = false
        hoverTick = 0
        hoverLabelRect = VoiceMarkerHandle.rect(0, 0, 0, 0)
        publishReadout()
    }

    // MARK: Internals: gesture teardown

    private func cancelDrag() {
        guard drag != nil else { return }
        drag = nil
        cursorKind = 0
        refreshInteractionPublished()
        projectMarkers(projectedEntries(lanePoints()))
        publishTransient()
    }

    private func cancelPan() {
        guard panRevision != nil else { return }
        panRevision = nil
        refreshInteractionPublished()
    }

    /// Re-derives the published interaction gate from the page's own state.
    private func refreshInteractionPublished() {
        let active = drag != nil || panRevision != nil || picker != nil || menu != nil
        if interactionActive != active { interactionActive = active }
        setPublished(&selectedIdentity, drag?.identity ?? selectedIdentity)
    }

    // MARK: Internals: projection

    private func lanePoints() -> [LanePoint] {
        guard let session, let track = currentTrack(session) else { return [] }
        return session.document.lanePoints(track: track, lane: .voice)
    }

    private func firstProgram() -> Int {
        guard let session, let track = currentTrack(session) else { return -1 }
        return session.timeline.tracks[track].firstProgram
    }

    private func slotViews() -> [BankSlotView] { session?.bankSlots ?? [] }

    private func xForTick(_ tick: Tick) -> Double {
        guard let session else { return 0 }
        return session.camera.displayX(tick: Double(tick), origin: 0, dpr: devicePixelRatio)
    }

    /// `VoiceChangeArea`'s snap seam: the shared grid's editing lattice for a
    /// plain drag, and the legacy alt-fine clock lattice while the modifier is
    /// held — `Grid::snapTick(rawTick, modifiers & Qt::AltModifier)`.
    private func snapTick(at x: Double, fine: Bool = false) -> Tick {
        guard let session else { return 0 }
        let raw = max(0, session.camera.tickAtContentX(max(0, x)))
        guard !fine else {
            return VoiceLanePolicy.fineSnap(
                raw, clockTicks: VoiceLanePolicy.clockTicks(
                    division: session.document.ticksPerBeat,
                    extendedClocks: session.document.state.config.extendedClocks))
        }
        return Tick(max(0, gridMetrics(session).snapTick(raw, camera: session.camera)))
    }

    private func markerHit(at x: Double) -> LanePoint? {
        VoiceLanePolicy.marker(at: x, points: lanePoints(),
                               displayX: { self.xForTick($0) },
                               hitRadius: fontPx(VoiceChangesPagePolicy.markerHitRadiusFactor))
    }

    private func effectiveContextTick() -> Tick {
        guard let session else { return 0 }
        return playing ? contextTick : session.editCursor
    }

    private func contextKey(at tick: Tick) -> VoiceContextKey {
        let slot = VoiceLanePolicy.slot(firstProgram: firstProgram(), tick: tick,
                                        points: lanePoints())
        return VoiceContextKey(slot: slot, playing: playing)
    }

    // MARK: Content rebuild

    /// Rebuilds every static projection: the typography, the gutter texts, the
    /// held spans, the grid and the markers.
    private func rebuildContent() {
        guard let session, plotHeight > 0 || plotWidth > 0 else { return }
        contentBuildCount &+= 1
        publishTypography()
        trackAvailable = currentTrack(session) != nil
        publishGutter()
        let entries = projectedEntries(lanePoints())
        publishSpans(entries)
        publishGrid()
        projectMarkers(entries)
        publishReadout()
        publishTransient()
    }

    /// The entries the band paints: the live lane, or the frozen drag's draft
    /// with its own occurrence moved to the preview tick. Ties keep document
    /// order, exactly as the legacy stable sort does.
    private func projectedEntries(_ points: [LanePoint])
        -> [(tick: Tick, value: Int, identity: String)]
    {
        var entries = points.map {
            (tick: $0.tick, value: $0.value, identity: VoiceOccurrence($0).text)
        }
        if let live = drag, live.active {
            entries = entries.map { entry in
                entry.identity == live.identity
                    ? (tick: live.previewTick, value: entry.value, identity: entry.identity)
                    : entry
            }
        }
        return entries.enumerated()
            .sorted { left, right in
                left.element.tick == right.element.tick
                    ? left.offset < right.offset : left.element.tick < right.element.tick
            }
            .map(\.element)
    }

    private func publishTypography() {
        let pixelSize = max(1, Int(baseFontPx.rounded()))
        let caption = VoiceCaption(pixelSize: pixelSize, weight: 400)
        let title = VoiceCaption(pixelSize: pixelSize, weight: 600)
        self.caption = caption
        self.title = title
        setPublishedFont(&captionFont, caption.fontMap)
        setPublishedFont(&titleFont, title.fontMap)
    }

    /// The gutter's two lines, vertically centered: the title, then the change
    /// summary the legacy band publishes while a track is presented.
    private func publishGutter() {
        let captionHeight = caption?.height ?? 0
        let titleHeight = title?.height ?? 0
        let top = max(0, (plotHeight - titleHeight - captionHeight) / 2)
        var texts: [SceneText] = []
        texts.append(SceneText(
            rect: (0, top, plotOrigin, titleHeight), text: gutterTitle,
            color: palette.primaryText, font: titleFont, horizontal: 0x1, vertical: 0x80))
        if trackAvailable {
            texts.append(SceneText(
                rect: (0, top + titleHeight, plotOrigin, captionHeight), text: countSummary(),
                color: palette.secondaryText, font: captionFont, horizontal: 0x1,
                vertical: 0x80))
        }
        syncTexts(gutterTexts, texts)
    }

    private func countSummary() -> String {
        let count = lanePoints().count
        return count == 0 ? "no voice set · double-click to add"
            : "\(count) change(s) · double-click to edit"
    }

    /// One held-span rect per program section, exactly the legacy walk: a span
    /// from the previous change to this one, then the tail to the song's end.
    private func publishSpans(_ entries: [(tick: Tick, value: Int, identity: String)]) {
        guard let session, plotHeight > 0, plotWidth > 0, trackAvailable else {
            syncRects(heldSpans, [])
            return
        }
        let track = currentTrack(session) ?? 0
        let held = PaletteMath.hex(PaletteMath.trackIdentityOklab(track), alpha: 18)
        var program = firstProgram()
        var spanStart: Tick = 0
        var rects: [SceneRect] = []
        for entry in entries {
            if program >= 0, entry.tick > spanStart {
                rects.append(spanRect(from: spanStart, to: entry.tick, color: held))
            }
            program = entry.value
            spanStart = entry.tick
        }
        if program >= 0, session.timeline.lengthTicks > spanStart {
            rects.append(spanRect(from: spanStart, to: session.timeline.lengthTicks, color: held))
        }
        syncRects(heldSpans, rects.filter { $0.width > 0 })
    }

    private func spanRect(from begin: Tick, to end: Tick, color: String) -> SceneRect {
        let left = min(max(xForTick(begin), 0), plotWidth)
        let right = min(max(xForTick(end), 0), plotWidth)
        return SceneRect(x: left, y: 0, width: max(0, right - left), height: plotHeight,
                         fillColor: color, primitiveName: "voiceHeldSpan")
    }

    /// The vertical grid over the visible plot: the roll's own subdivision,
    /// beat, fine-beat and bar lines, through the same grid metrics.
    private func publishGrid() {
        guard let session, plotHeight > 0, plotWidth > 0, trackAvailable else {
            syncRects(gridLines, [])
            return
        }
        let camera = session.camera
        let metrics = gridMetrics(session)
        let physicalPixel = max(metrics.pixel, 0.0001)
        let roundingMargin = physicalPixel / 2
        let beginTick = camera.tickAtContentX(-roundingMargin)
        let endTick = camera.tickAtContentX(plotWidth - physicalPixel + roundingMargin) + 1
        guard endTick > beginTick else {
            syncRects(gridLines, [])
            return
        }
        let range = (begin: Tick(max(0, beginTick.rounded(.down))),
                     end: Tick(max(1, endTick.rounded(.up))))
        let stroke = metrics.gridLineStroke
        var rects: [SceneRect] = []
        metrics.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let color = level == 1 ? palette.gridLineSub1
                : level == 2 ? palette.gridLineSub2 : palette.gridLineSub3
            rects.append(SceneRect(x: xForTick(tick) - stroke / 2, y: 0, width: stroke,
                                   height: plotHeight, fillColor: color,
                                   primitiveName: "voiceGrid"))
        }
        var segment = metrics.timeAxis.segmentAt(range.begin)
        var finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
            }
            rects.append(SceneRect(
                x: xForTick(tick) - stroke / 2, y: 0, width: stroke, height: plotHeight,
                fillColor: isBar ? palette.gridLineBar
                    : finest ? palette.gridLineBeatFine : palette.gridLineBeat,
                primitiveName: "voiceGrid"))
        }
        syncRects(gridLines, rects)
    }

    /// The marker projection: one marker rule and one label box per entry, with
    /// the legacy elision, stair placement and offscreen rule.
    private func projectMarkers(_ entries: [(tick: Tick, value: Int, identity: String)]) {
        guard plotWidth > 0, plotHeight > 0, trackAvailable, let session, let caption else {
            publishMarkers([])
            return
        }
        let views = slotViews()
        let track = currentTrack(session) ?? 0
        let pad = fontPx(VoiceChangesPagePolicy.spaceOneFactor)
        let gap = max(fontPx(VoiceChangesPagePolicy.hoverPaintPaddingFactor), pad)
        let labelHeight = caption.height
        let centerY = plotHeight / 2 - labelHeight / 2
        let stairStep = min(fontPx(VoiceChangesPagePolicy.spaceFourFactor),
                            (plotHeight - labelHeight - 2 * pad) / 2)
        let canStair = stairStep > 1
        let trackColor = PaletteMath.trackIdentityFills[PaletteMath.trackIdentityIndex(track)]
        let selection = drag?.identity ?? (selectedIdentity.isEmpty ? nil : selectedIdentity)
        var stairUp = true
        var lastXEnd = -Double.infinity
        var values: [VoiceMarkerHandle] = []
        values.reserveCapacity(entries.count)
        for entry in entries {
            let label = contextLabel(at: entry.value)
            let source = label.isEmpty ? "No voice" : label
            let labelX = xForTick(entry.tick) + pad
            let maxWidth = max(0, plotWidth - labelX)
            let drawn = caption.advance(source) > maxWidth && maxWidth > 0
                ? caption.elided(source, toWidth: maxWidth.rounded(.down))
                : source
            let labelWidth = min(caption.advance(drawn), maxWidth)
            let offscreen = labelX + labelWidth < 0 || labelX > plotWidth || labelWidth <= 0
            var labelY = centerY
            if !offscreen {
                if labelX < lastXEnd + gap, canStair {
                    stairUp.toggle()
                    labelY = stairUp ? centerY - stairStep : centerY + stairStep
                }
                let lower = pad
                let upper = max(lower, plotHeight - labelHeight - pad)
                labelY = min(max(labelY, lower), upper)
                lastXEnd = labelX + labelWidth + gap
            }
            let handle = VoiceMarkerHandle()
            handle.identity = entry.identity
            handle.tick = Double(entry.tick)
            handle.value = entry.value
            handle.slotBlank = !views.indices.contains(entry.value)
                || views[entry.value].voice == nil
            handle.symbol = views.indices.contains(entry.value)
                ? views[entry.value].voice?.symbol ?? "" : ""
            handle.label = drawn
            handle.labelRect = VoiceMarkerHandle.rect(labelX, labelY, labelWidth, labelHeight)
            handle.labelColor = palette.primaryText
            handle.x = labelX - pad
            handle.lineTop = pad
            handle.lineBottom = max(pad, plotHeight - pad)
            handle.lineWidth = 2 * physicalPixel(devicePixelRatio)
            handle.lineColor = trackColor
            handle.selected = selection == entry.identity
            handle.hovered = hoverIdentity == entry.identity
            handle.preview = drag?.active == true && drag?.identity == entry.identity
            handle.offscreen = offscreen
            values.append(handle)
        }
        publishMarkers(values)
    }

    /// The drag's transient: where the frozen occurrence currently drafts.
    private func publishTransient() {
        guard let live = drag, live.active else {
            setPublished(&previewVisible, false)
            setPublished(&previewX, 0)
            setPublished(&previewTick, 0)
            return
        }
        setPublished(&previewVisible, true)
        setPublished(&previewX, xForTick(live.previewTick))
        setPublished(&previewTick, Double(live.previewTick))
    }

    /// The readout: the effective context's label, right-aligned in the plot.
    /// The page always publishes it; the QML draws it while a track is
    /// presented, exactly as the legacy band does.
    private func publishReadout() {
        let tick = effectiveContextTick()
        let slot = VoiceLanePolicy.slot(firstProgram: firstProgram(), tick: tick,
                                        points: lanePoints())
        let views = slotViews()
        let label = contextLabel(at: slot)
        let pad = fontPx(VoiceChangesPagePolicy.spaceOneFactor)
        setPublished(&contextSlot, slot)
        setPublished(&contextBlank, !views.indices.contains(slot) || views[slot].voice == nil)
        setPublished(&contextSymbol, views.indices.contains(slot)
            ? views[slot].voice?.symbol ?? "" : "")
        setPublished(&readoutText, label.isEmpty ? "No voice" : label)
        setPublished(&readoutVisible, trackAvailable)
        setPublishedRect(&readoutRect,
                         VoiceMarkerHandle.rect(pad, 0, max(0, plotWidth - 2 * pad), plotHeight))
    }

    // MARK: Internals: picker publication

    private func publishPicker() {
        guard let live = picker else {
            syncPickerRows([])
            return
        }
        let views = slotViews()
        let programs = Self.visiblePrograms(filter: live.filter, slots: views)
        var rows: [VoicePickerRowHandle] = []
        rows.reserveCapacity(programs.count)
        for program in programs {
            let row = VoicePickerRowHandle()
            row.program = program
            row.label = Self.pickerLabel(slot: program,
                                         view: views.indices.contains(program)
                                             ? views[program] : nil)
            row.blank = !views.indices.contains(program) || views[program].voice == nil
            row.symbol = views.indices.contains(program)
                ? views[program].voice?.symbol ?? "" : ""
            row.selected = program == live.program
            rows.append(row)
        }
        syncPickerRows(rows)
        setPublished(&pickerFilter, live.filter)
        setPublished(&pickerIndex, programs.firstIndex(of: live.program) ?? -1)
        setPublished(&pickerHasMatch, live.program >= 0)
    }

    /// `VoicePickerModel`: `"%03d  %@"` with the slot's short name; the two
    /// spaces are the picker's own separator, distinct from the band's one.
    private static func pickerLabel(slot: Int, view: BankSlotView?) -> String {
        let label = VoiceLanePolicy.label(slot: slot, view: view)
        guard let separator = label.firstIndex(of: " ") else { return label }
        return "\(label[label.startIndex..<separator])  \(label[label.index(after: separator)...])"
    }

    private static func visiblePrograms(filter: String, slots: [BankSlotView]) -> [Int] {
        (0..<slots.count).filter { program in
            filter.isEmpty
                || pickerLabel(slot: program, view: slots[program])
                    .range(of: filter, options: .caseInsensitive) != nil
        }
    }

    private static func firstProgram(filter: String, slots: [BankSlotView]) -> Int {
        visiblePrograms(filter: filter, slots: slots).first ?? -1
    }

    private static func program(at index: Int, filter: String, slots: [BankSlotView]) -> Int {
        let programs = visiblePrograms(filter: filter, slots: slots)
        return programs.indices.contains(index) ? programs[index] : -1
    }

    private func selectPickerProgram(_ program: Int) {
        guard var live = picker, live.program != program else { return }
        live.program = program
        picker = live
        publishPicker()
    }

    // MARK: Internals: publication plumbing

    private func publishMarkers(_ values: [VoiceMarkerHandle]) {
        published = values
        let common = min(markers.count, values.count)
        for index in 0..<common where !markers[index].matches(values[index]) {
            markers[index] = values[index]
        }
        if markers.count != values.count {
            markers.replaceSubrange(common..<markers.count, with: values[common...])
        }
    }

    private func syncRects(_ model: QListModel<SceneRect>, _ rects: [SceneRect]) {
        let common = min(model.count, rects.count)
        for index in 0..<common where !model[index].matches(rects[index]) {
            model[index] = rects[index]
        }
        if model.count != rects.count {
            model.replaceSubrange(common..<model.count, with: rects[common...])
        }
    }

    private func syncTexts(_ model: QListModel<SceneText>, _ texts: [SceneText]) {
        let common = min(model.count, texts.count)
        for index in 0..<common where !Self.textMatches(model[index], texts[index]) {
            model[index] = texts[index]
        }
        if model.count != texts.count {
            model.replaceSubrange(common..<model.count, with: texts[common...])
        }
    }

    private func syncPickerRows(_ values: [VoicePickerRowHandle]) {
        pickerRowSnapshots = values
        let common = min(pickerRows.count, values.count)
        for index in 0..<common where !pickerRows[index].matches(values[index]) {
            pickerRows[index] = values[index]
        }
        if pickerRows.count != values.count {
            pickerRows.replaceSubrange(common..<pickerRows.count, with: values[common...])
        }
    }

    private func syncMenuRows(_ values: [VoiceMenuRowHandle]) {
        let common = min(menuRows.count, values.count)
        for index in 0..<common where !menuRows[index].matches(values[index]) {
            menuRows[index] = values[index]
        }
        if menuRows.count != values.count {
            menuRows.replaceSubrange(common..<menuRows.count, with: values[common...])
        }
    }

    private static func textMatches(_ lhs: SceneText, _ rhs: SceneText) -> Bool {
        lhs.labelText == rhs.labelText && lhs.labelColor == rhs.labelColor
            && lhs.labelHorizontalAlignment == rhs.labelHorizontalAlignment
            && lhs.labelVerticalAlignment == rhs.labelVerticalAlignment
            && VoiceMarkerHandle.rectMatches(lhs.labelRect, rhs.labelRect)
            && lhs.labelFont.count == rhs.labelFont.count
            && lhs.labelFont.allSatisfy {
                String(describing: $1) == String(describing: rhs.labelFont[$0])
            }
    }

    /// Writes one published primitive only when it really changed, so a repeated
    /// equal publication emits nothing.
    private func setPublished<Value: Equatable>(_ storage: inout Value, _ value: Value) {
        if storage != value { storage = value }
    }

    /// The variant-typed records compare through their published spelling:
    /// `[String: QVariantSettable]` is not `Equatable`, and an equal record must
    /// leave its storage untouched.
    private func setPublishedRect(_ storage: inout [String: QVariantSettable],
                                 _ value: [String: QVariantSettable]) {
        if !VoiceMarkerHandle.rectMatches(storage, value) { storage = value }
    }

    private func setPublishedFont(_ storage: inout [String: QVariantSettable],
                                  _ value: [String: QVariantSettable]) {
        if !Self.fontMatches(storage, value) { storage = value }
    }

    private static func fontMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: [String: QVariantSettable]) -> Bool {
        lhs.count == rhs.count && lhs.allSatisfy {
            String(describing: $1) == String(describing: rhs[$0])
        }
    }

    // MARK: Internals: shared metrics

    private func fontPx(_ multiplier: Double) -> Double {
        multiplier == 0 ? 0 : max(1, (baseFontPx * multiplier).rounded())
    }

    private func gridMetrics(_ session: DocumentSession) -> GridMetrics {
        GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio, width: plotWidth,
                    height: plotHeight, timeAxis: timeAxis(session))
    }

    private func timeAxis(_ session: DocumentSession) -> TimeAxis {
        let timeline = session.timeline
        return TimeAxis(map: TimeMap(
            ticksPerBeat: UInt32(max(1, session.document.ticksPerBeat)),
            lengthTicks: timeline.lengthTicks,
            loopStartTick: timeline.loopStartTick,
            loopEndTick: timeline.loopEndTick,
            timeSigs: session.document.timeSignatures.map {
                TimeSigPoint(tick: $0.tick, numerator: $0.numerator,
                             denomPow2: $0.denominatorPower)
            }))
    }

    static let fontFamily = "Atkinson Hyperlegible Next"
}
