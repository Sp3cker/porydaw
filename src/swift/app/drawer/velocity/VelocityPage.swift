import Foundation
import PorydawCore
import QtBridge

// The production Velocity page: one deep owner for the drawer's Velocity
// section, following `src/ui/editordrawer/velocityarea/` and `velocityaxis.*`
// for behaviour. It publishes primitives and stable item models for QML and
// owns no camera, clock, viewport, history or selection storage: selection
// lives in `DocumentSession`, the horizontal projection is `EditorCamera`, and
// the playhead is the composition-owned segment the page only reads.
//
// Ownership: `ApplicationSession` creates the page for the current document,
// attaches it before `songOpen` publishes, refreshes it from the session's
// existing document/grid/playhead publications, and cancels it synchronously
// before the document owners retire.
//
// Voice/value context: `VelocityMap` (PorydawCore) is the exact authority,
// resolved from the current bank slot's top-level `BankVoice` macro. A
// keysplit/drumkit voice needs per-note subvoice `ToneData`, which the Swift
// bank view does not expose: that context publishes an explicit unsupported
// diagnostic and refuses exactly the edits whose map is unknowable instead of
// approximating a continuous, direct-sound or first-level map.
//
// Blocked legacy cases (all keysplit/drumkit rows of
// `src/checks/drawerpresentation/velocity.cpp`): the fixture-route101 and
// `psgAxisContexts`/`psgRenderingAndDetentToggle`/`hoveredPsgContext` variants
// that install a `VOICE_KEYSPLIT_ALL` parent and read its per-key `subGroup`
// child (`ToneData.subGroup[key]`, and `keySplitTable[key]` for the plain
// keysplit form), then call `VelocityMap::resolve(&voice, key)` per note. Their
// exact result depends on the key, so no top-level substitution can reproduce
// them.
//
// Minimal approval-gated resolving contract (read-only, no mutation, no new
// service and no QtBridge expansion): extend the existing published
// `BankSlotView` with a per-key subvoice lookup, for example
// `subvoiceMacro(forKey:) -> Int32?`, returning the resolved child's macro
// ordinal (`BankVoiceMacro`) for a keysplit/drumkit slot and `nil` for every
// other or unresolvable slot. `VelocityContextPolicy.voiceKind(macro:)` then
// maps that ordinal exactly as it maps the top-level one, and
// `VelocityContextStatus.keysplitSubvoice` disappears for slots the native side
// can resolve. Until that contract exists, this file keeps the diagnostic and
// the refusal.

// MARK: - Page vocabulary

/// The page's published constants. The base font seed mirrors the grid's
/// `GridCameraPolicy.seedBaseFontPx`, which is internal to this module.
public enum VelocityPagePolicy {
    public static let seedBaseFontPx: Double = 13
}

/// Where a pointer event landed in the page body. Mirrors the legacy
/// `TimelineInputSurface` split: the ruler column click-sets, the plot edits.
public enum VelocityInputSurface: Int, Sendable {
    case ruler = 0
    case plot = 1
}

/// Qt pointer buttons as QML carries them (`mouse.button`).
enum VelocityQtButton {
    static let left = 1
    static let right = 2
    static let middle = 4
}

/// Qt keyboard modifier bits as QML carries them (`mouse.modifiers`).
enum VelocityModifier {
    static let shift = 0x0200_0000
    static let control = 0x0400_0000
    static let alt = 0x0800_0000
    static let meta = 0x1000_0000
    static let shortcutMask = shift | control | alt | meta
}

/// `drawerContextTick`: the shared playhead's tick rounded to the nearest whole
/// tick, the context position drawer pages resolve voices at.
func velocityContextTick(_ tick: Double) -> Tick {
    guard tick.isFinite, tick > 0 else { return 0 }
    guard tick < Double(TimeDefaults.maxTick) else { return TimeDefaults.maxTick }
    return Tick((tick + 0.5).rounded(.down))
}

/// `ui::linearRampValue`: the ramp's y at `x`, clamped to the drawn span.
public func velocityRampValue(at x: Double, x0: Double, y0: Double, x1: Double,
                              y1: Double) -> Double {
    let deltaX = x1 - x0
    guard deltaX != 0 else { return y1 }
    let t = min(max((x - x0) / deltaX, 0), 1)
    return y0 + t * (y1 - y0)
}

// MARK: - Voice/value context

/// What the page knows about the active voice's velocity mapping.
public enum VelocityContextStatus: Int, Sendable {
    /// The top-level voice resolves to an exact `VelocityMap`.
    case resolved = 0
    /// No program at this tick, or the program's slot publishes no parsed voice
    /// (blank, read-only and broken lines publish none).
    case unresolvedVoice = 1
    /// A keysplit/drumkit voice: the exact map is per-note and needs subvoice
    /// data the Swift bank view does not expose. Resolving it requires the
    /// per-(slot, key) subvoice lookup described at the top of this file.
    case keysplitSubvoice = 2
}

/// One resolved voice context plus where it came from. `endTick` is the next
/// voice change's tick, or `nil` when the context runs to the song's end.
public struct VelocityVoiceContext: Equatable, Sendable {
    public var status: VelocityContextStatus
    public var map: VelocityMap
    public var slot: Int
    public var endTick: Tick?
    public var symbol: String

    public init(status: VelocityContextStatus,
                map: VelocityMap = VelocityMap(voiceKind: .unresolved),
                slot: Int = -1, endTick: Tick? = nil, symbol: String = "") {
        self.status = status
        self.map = map
        self.slot = slot
        self.endTick = endTick
        self.symbol = symbol
    }

    /// Exact-map editing is available only for a resolved context.
    public var editable: Bool { status == .resolved }

    public var diagnostic: String {
        switch status {
        case .resolved:
            return ""
        case .unresolvedVoice:
            return "No parsed voice publishes program \(slot); exact velocity editing is "
                + "unavailable for this context."
        case .keysplitSubvoice:
            return "Program \(slot) is a keysplit/drumkit voice: per-note subvoice data is "
                + "unavailable, so exact velocity editing is disabled for this context."
        }
    }
}

/// `SongView::voiceContext` plus `VelocityMap::resolve` for the top level. Pure,
/// so the projection checks drive it with synthetic bank views.
public enum VelocityContextPolicy {
    /// The track's first program, then the last voice change at or before
    /// `tick`; the returned end tick is the next change.
    public static func slot(firstProgram: Int, tick: Tick,
                            voiceChanges: [LanePoint]) -> (slot: Int, endTick: Tick?) {
        var slot = firstProgram
        var endTick: Tick?
        for change in voiceChanges where change.tick <= tick {
            slot = change.value
        }
        for change in voiceChanges where change.tick > tick {
            endTick = change.tick
            break
        }
        return (slot, endTick)
    }

    /// The top-level voice kind a bank macro names, or `nil` for a keysplit or
    /// drumkit macro whose resolution needs subvoice data.
    public static func voiceKind(macro: Int32) -> VoiceKind? {
        switch macro {
        case BankVoiceMacro.directSound, BankVoiceMacro.directSoundNoResample,
             BankVoiceMacro.directSoundAlt:
            return .directSound
        case BankVoiceMacro.square1, BankVoiceMacro.square1Alt:
            return .square1
        case BankVoiceMacro.square2, BankVoiceMacro.square2Alt:
            return .square2
        case BankVoiceMacro.programmableWave, BankVoiceMacro.programmableWaveAlt:
            return .wave
        case BankVoiceMacro.noise, BankVoiceMacro.noiseAlt:
            return .noise
        default:
            return nil
        }
    }

    /// One context from the published bank slots.
    public static func resolve(slot: Int, endTick: Tick?, slots: [BankSlotView])
        -> VelocityVoiceContext
    {
        guard slot >= 0, slots.indices.contains(slot), let voice = slots[slot].voice else {
            return VelocityVoiceContext(status: .unresolvedVoice, slot: slot, endTick: endTick)
        }
        guard let kind = voiceKind(macro: voice.macro) else {
            return VelocityVoiceContext(status: .keysplitSubvoice, slot: slot, endTick: endTick,
                                        symbol: voice.symbol)
        }
        return VelocityVoiceContext(status: .resolved, map: VelocityMap(voiceKind: kind),
                                    slot: slot, endTick: endTick, symbol: voice.symbol)
    }
}

// MARK: - Value axis

/// Font-relative ruler geometry: one value per `VelocityAxisGeometry` field.
public struct VelocityAxisGeometry: Equatable, Sendable {
    public var height: Double = 0
    public var verticalInset: Double = 0
    public var labelWidth: Double = 0
    public var labelSideInset: Double = 0
    public var labelColumnGap: Double = 0
    public var labelHeight: Double = 0
    public var continuousDensityD1: Double = 0
    public var continuousDensityD2: Double = 0
    public var continuousDensityD3: Double = 0
    public var continuousDensityD4: Double = 0

    public init() {}
}

public struct VelocityAxisTick: Equatable, Sendable {
    public var velocity: Int = 1
    public var y: Double = 0

    public init(velocity: Int = 1, y: Double = 0) {
        self.velocity = velocity
        self.y = y
    }
}

public struct VelocityAxisLabel: Equatable, Sendable {
    public var velocity: Int = 1
    public var y: Double = 0
    public var text: String = ""

    public init(velocity: Int = 1, y: Double = 0, text: String = "") {
        self.velocity = velocity
        self.y = y
        self.text = text
    }
}

/// One intrinsic (PSG level) graduation. `labelVisible` is the density decision
/// and `emphasized` the active-and-single-selection one; both come from
/// `rebuildQuickAxis`, so QML renders two booleans instead of a rule.
public struct VelocityAxisGraduation: Equatable, Sendable {
    public var level: Int = 0
    public var velocity: Int = 1
    public var y: Double = 0
    public var audible: Bool = false
    public var active: Bool = false
    public var labelVisible: Bool = true
    public var emphasized: Bool = false
    public var text: String = ""

    public init() {}
}

public struct VelocityAxisMarker: Equatable, Sendable {
    public var velocity: Int = 1
    public var y: Double = 0

    public init(velocity: Int = 1, y: Double = 0) {
        self.velocity = velocity
        self.y = y
    }
}

/// The ruler as pure values: `VelocityAxis` from `velocityaxis.cpp`, including
/// the density ladder, the intrinsic row centers and boundaries, the displayed
/// value markers and the ruler hit rules.
public struct VelocityAxisModel: Equatable, Sendable {
    public enum Mode: Int, Sendable {
        case continuous = 0
        case intrinsic = 1
    }

    public static let maximumContinuousTicks = 32
    public static let maximumContinuousLabels = 17
    public static let maximumIntrinsicGraduations = 16
    public static let maximumMarkers = 2
    public static let minimumVelocity = 1
    public static let maximumVelocity = 127

    public private(set) var map = VelocityMap(voiceKind: .unresolved)
    public var geometry = VelocityAxisGeometry()
    public private(set) var top: Double = 0
    public private(set) var bottom: Double = 0
    public private(set) var ticks: [VelocityAxisTick] = []
    public private(set) var labels: [VelocityAxisLabel] = []
    public private(set) var graduations: [VelocityAxisGraduation] = []
    public private(set) var markers: [VelocityAxisMarker] = []
    public private(set) var accessibleDescription = "Velocity"

    private var levelCenters: [Double] = []
    private var levelBoundaries: [Double] = []

    public init() {
        rebuild()
    }

    public init(map: VelocityMap, geometry: VelocityAxisGeometry, activeValues: [UInt8] = []) {
        self.map = map
        self.geometry = geometry
        rebuild(activeValues: activeValues)
    }

    public var mode: Mode { map.levelCount == 0 ? .continuous : .intrinsic }

    public var drawableSpan: Double { bottom - top }

    public func velocityToY(_ velocity: Int) -> Double {
        let clamped = min(max(velocity, Self.minimumVelocity), Self.maximumVelocity)
        guard drawableSpan != 0 else { return bottom }
        return bottom - Double(clamped - Self.minimumVelocity) * drawableSpan
            / Double(Self.maximumVelocity - Self.minimumVelocity)
    }

    public func yToVelocity(_ y: Double) -> Int {
        guard drawableSpan != 0 else { return Self.minimumVelocity }
        let clampedY = min(max(y, top), bottom)
        let scaled = (bottom - clampedY) * Double(Self.maximumVelocity - Self.minimumVelocity)
            / drawableSpan
        return min(max(Self.minimumVelocity + Int(scaled.rounded()), Self.minimumVelocity),
                   Self.maximumVelocity)
    }

    public func levelToY(_ level: Int) -> Double {
        guard !levelCenters.isEmpty else { return bottom }
        return levelCenters[min(max(level, 0), levelCenters.count - 1)]
    }

    public func yToLevel(_ y: Double) -> Int {
        let highest = max(0, map.levelCount - 1)
        var level = 0
        while level < highest, level < levelBoundaries.count, y <= levelBoundaries[level] {
            level += 1
        }
        return level
    }

    public func levelBoundaryToY(_ lowerLevel: Int) -> Double {
        guard !levelBoundaries.isEmpty else { return bottom }
        return levelBoundaries[min(max(lowerLevel, 0), levelBoundaries.count - 1)]
    }

    public func hasLabel(_ velocity: Int) -> Bool {
        labels.contains { $0.velocity == velocity }
    }

    /// `VelocityAxis::inRuler`: the ruler owns `[0, rulerWidth)`.
    public func inRuler(x: Double, rulerWidth: Double) -> Bool {
        x >= 0 && x < rulerWidth
    }

    /// `VelocityAxis::rulerVelocityAt`: a level representative in intrinsic
    /// mode, else the label whose text row covers `y`, else `-1`.
    public func rulerVelocityAt(y: Double, labelHeight: Double) -> Int {
        if mode == .intrinsic { return Int(map.representative(yToLevel(y))) }
        let textRadius = labelHeight / 2
        for label in labels where abs(y - label.y) <= textRadius {
            return label.velocity
        }
        return -1
    }

    // MARK: Construction

    private mutating func rebuild(activeValues: [UInt8] = []) {
        let height = max(0, geometry.height)
        let inset = max(0, geometry.verticalInset)
        top = min(inset, height / 2)
        bottom = max(top, height - inset)
        ticks = []
        labels = []
        graduations = []
        levelCenters = []
        levelBoundaries = []
        buildContinuousTicks()
        buildContinuousMarkers(activeValues: activeValues)
        if mode == .intrinsic { buildIntrinsicRows() }
        accessibleDescription = map.levelCount == 0
            ? "Velocity"
            : "Velocity. \(map.voiceName) has \(map.levelCount) volume levels."
    }

    private mutating func addTick(_ velocity: Int) {
        guard ticks.count < Self.maximumContinuousTicks else { return }
        ticks.append(VelocityAxisTick(velocity: velocity, y: velocityToY(velocity)))
    }

    private mutating func addLabel(_ velocity: Int) {
        guard labels.count < Self.maximumContinuousLabels else { return }
        labels.append(VelocityAxisLabel(velocity: velocity, y: velocityToY(velocity),
                                        text: String(velocity)))
    }

    /// `VelocityAxis::buildContinuousTicks`: the ruler thins out as the body
    /// shrinks, in the four exact density bands.
    private mutating func buildContinuousTicks() {
        let span = max(0, geometry.height)
        if span < geometry.continuousDensityD1 {
            for velocity in [127, 96, 64, 32, 1] { addTick(velocity) }
            for velocity in [127, 64, 1] { addLabel(velocity) }
            return
        }
        if span < geometry.continuousDensityD2 {
            addTick(127)
            for velocity in stride(from: 112, through: 16, by: -16) { addTick(velocity) }
            addTick(1)
            for velocity in [127, 64, 1] { addLabel(velocity) }
            return
        }
        if span < geometry.continuousDensityD3 {
            addTick(127)
            for velocity in stride(from: 112, through: 16, by: -16) { addTick(velocity) }
            addTick(1)
            for velocity in [127, 96, 64, 32, 1] { addLabel(velocity) }
            return
        }
        if span < geometry.continuousDensityD4 {
            addTick(127)
            for velocity in stride(from: 120, through: 8, by: -8) { addTick(velocity) }
            addTick(1)
            addLabel(127)
            for velocity in stride(from: 112, through: 16, by: -16) { addLabel(velocity) }
            addLabel(1)
            return
        }
        addTick(127)
        for velocity in stride(from: 123, through: 7, by: -4) { addTick(velocity) }
        addTick(1)
        addLabel(127)
        for velocity in stride(from: 120, through: 8, by: -8) { addLabel(velocity) }
        addLabel(1)
    }

    /// `VelocityAxis::buildContinuousMarkers`: the lowest and highest displayed
    /// value of the active set, one marker when they coincide.
    private mutating func buildContinuousMarkers(activeValues: [UInt8]) {
        guard let first = activeValues.first else { return }
        var minimum = Int(clampVelocity(Int(first)))
        var maximum = minimum
        for value in activeValues.dropFirst() {
            let velocity = Int(clampVelocity(Int(value)))
            minimum = min(minimum, velocity)
            maximum = max(maximum, velocity)
        }
        markers.append(VelocityAxisMarker(velocity: minimum, y: velocityToY(minimum)))
        if maximum != minimum {
            markers.append(VelocityAxisMarker(velocity: maximum, y: velocityToY(maximum)))
        }
    }

    /// `VelocityAxis::buildIntrinsicRows`: one row per PSG level, boundaries
    /// where the effective volume changes, labels thinned to the label height.
    private mutating func buildIntrinsicRows() {
        let levelCount = map.levelCount
        guard levelCount > 0 else { return }
        var labelStride = 1
        let levelHeight = drawableSpan / Double(levelCount)
        while labelStride <= levelCount,
              levelHeight * Double(labelStride) < max(0, geometry.labelHeight)
        {
            labelStride *= 2
        }
        for level in 0..<max(0, levelCount - 1) {
            let lower = map.levelRange(level)
            let upper = map.levelRange(level + 1)
            levelBoundaries.append(
                (velocityToY(Int(lower.last)) + velocityToY(Int(upper.first))) / 2)
        }
        for level in 0..<levelCount where graduations.count < Self.maximumIntrinsicGraduations {
            let lowerBoundary = level == 0 ? bottom : levelBoundaries[level - 1]
            let upperBoundary = level + 1 == levelCount ? top : levelBoundaries[level]
            let center = (lowerBoundary + upperBoundary) / 2
            levelCenters.append(center)
            var graduation = VelocityAxisGraduation()
            graduation.level = level
            graduation.velocity = Int(map.representative(level))
            graduation.audible = level != 0
            graduation.labelVisible = (level + 1) % labelStride == 0
            graduation.y = center
            graduation.text = "Vol \(level + 1)"
            graduation.active = markers.contains { map.level(of: $0.velocity) == level }
            graduations.append(graduation)
        }
    }
}

// MARK: - Frozen gesture

/// One note captured when a gesture begins. Motion never reads the document, so
/// every field the preview needs — including the gesture-time voice map — is
/// frozen here: a hover or voicegroup change mid-gesture must not retarget the
/// axis or the map the gesture started on.
public struct VelocityFrozenNote: Equatable, Sendable {
    public var noteID: NoteID
    public var tick: Tick
    public var duration: Tick
    public var pitch: UInt8
    public var velocity: UInt8
    public var map: VelocityMap
    public var exactOrigin: UInt8

    public init(noteID: NoteID, tick: Tick, duration: Tick, pitch: UInt8, velocity: UInt8,
                map: VelocityMap, exactOrigin: UInt8) {
        self.noteID = noteID
        self.tick = tick
        self.duration = duration
        self.pitch = pitch
        self.velocity = velocity
        self.map = map
        self.exactOrigin = exactOrigin
    }
}

public enum VelocityGestureKind: Int, Sendable {
    case relative = 0
    case paint = 1
    case ramp = 2
    case pendingBand = 3
    case band = 4
    /// Middle-drag pan: the shared camera's own scroll, requested by the page.
    case pan = 5
}

/// One live gesture: the frozen targets, the captured document/track identity,
/// the axis map it started on and the preview it publishes.
public struct VelocityGestureState: Equatable, Sendable {
    public var kind: VelocityGestureKind
    public var revision: UInt64
    public var track: Int
    public var notes: [VelocityFrozenNote]
    public var axis: VelocityAxisModel
    public var detentUnlock: Bool
    public var activationDistance: Double
    public var relativeActivated: Bool = false
    public var pressX: Double
    public var pressY: Double
    public var previousX: Double
    public var previousY: Double
    public var bandX: Double
    public var bandY: Double
    public var preview: [NoteID: UInt8] = [:]
    public var bandPreview: [NoteID] = []
    public var controlPress: Bool = false

    public init(kind: VelocityGestureKind, revision: UInt64, track: Int,
                notes: [VelocityFrozenNote], axis: VelocityAxisModel, detentUnlock: Bool,
                activationDistance: Double, pressX: Double, pressY: Double,
                controlPress: Bool = false) {
        self.kind = kind
        self.revision = revision
        self.track = track
        self.notes = notes
        self.axis = axis
        self.detentUnlock = detentUnlock
        self.activationDistance = activationDistance
        self.pressX = pressX
        self.pressY = pressY
        self.previousX = pressX
        self.previousY = pressY
        self.bandX = pressX
        self.bandY = pressY
        self.controlPress = controlPress
    }
}

/// The gesture's whole rule set as pure functions: absolute resolution, the
/// relative delta, the ramp, the paint sweep and the commit payload.
public enum VelocityGesturePolicy {
    /// One absolute pointer position to one velocity. The unlock modifier takes
    /// exact MIDI, continuous mode canonicalizes onto the note's own map, and
    /// intrinsic mode takes the representative of the level under the pointer.
    public static func resolvedVelocity(axis: VelocityAxisModel, noteMap: VelocityMap,
                                       detentUnlock: Bool, y: Double) -> UInt8 {
        if detentUnlock { return clampVelocity(axis.yToVelocity(y)) }
        if axis.mode == .continuous { return noteMap.canonicalize(axis.yToVelocity(y)) }
        return noteMap.representative(axis.yToLevel(y))
    }

    /// One relative drag step: one clamped delta covers every frozen note at
    /// once, so relative offsets never collapse. Nothing moves until the drag
    /// leaves the activation distance or crosses an intrinsic level.
    public static func applyRelative(_ gesture: inout VelocityGestureState, y: Double) {
        guard !gesture.notes.isEmpty else { return }
        if !gesture.relativeActivated {
            let intrinsicChange = !gesture.detentUnlock && gesture.axis.mode == .intrinsic
                && gesture.axis.yToLevel(y) != gesture.axis.yToLevel(gesture.pressY)
            if abs(y - gesture.pressY) < gesture.activationDistance && !intrinsicChange {
                return
            }
            gesture.relativeActivated = true
        }
        var preview: [NoteID: UInt8] = [:]
        preview.reserveCapacity(gesture.notes.count)
        if gesture.detentUnlock || gesture.axis.mode == .continuous {
            let delta = gesture.axis.yToVelocity(y) - gesture.axis.yToVelocity(gesture.pressY)
            for note in gesture.notes {
                let proposal = Int(note.velocity) + delta
                preview[note.noteID] = gesture.detentUnlock
                    ? clampVelocity(proposal)
                    : note.map.canonicalize(proposal)
            }
        } else {
            let levelDelta = gesture.axis.yToLevel(y) - gesture.axis.yToLevel(gesture.pressY)
            for note in gesture.notes {
                preview[note.noteID] = note.map.moveLevels(from: note.exactOrigin, by: levelDelta)
            }
        }
        gesture.preview = preview
    }

    /// One ramp step: a straight line from the press position to the pointer,
    /// evaluated at each frozen note's own x. Notes outside the swept column
    /// keep their captured velocity.
    public static func applyRamp(_ gesture: inout VelocityGestureState, x: Double, y: Double,
                                 hitRadius: Double, xForNote: (VelocityFrozenNote) -> Double) {
        guard !gesture.notes.isEmpty else { return }
        let first = min(gesture.pressX, x) - hitRadius
        let last = max(gesture.pressX, x) + hitRadius
        var preview: [NoteID: UInt8] = [:]
        preview.reserveCapacity(gesture.notes.count)
        for note in gesture.notes {
            let noteX = xForNote(note)
            var velocity = note.velocity
            if noteX >= first, noteX <= last {
                let rampedY = velocityRampValue(at: noteX, x0: gesture.pressX, y0: gesture.pressY,
                                                x1: x, y1: y)
                velocity = resolvedVelocity(axis: gesture.axis, noteMap: note.map,
                                            detentUnlock: gesture.detentUnlock, y: rampedY)
            }
            preview[note.noteID] = velocity
        }
        gesture.preview = preview
    }

    /// One paint step: the frozen notes whose x falls in the swept column (or
    /// within the hit radius when the pointer did not move) take the linear
    /// interpolation of the pointer's y at their own x.
    public static func paint(axis: VelocityAxisModel, detentUnlock: Bool,
                             candidates: [(note: VelocityFrozenNote, x: Double)],
                             from: (x: Double, y: Double), to: (x: Double, y: Double),
                             hitRadius: Double) -> [NoteVelocity] {
        let deltaX = to.x - from.x
        let lower = min(from.x, to.x) - hitRadius
        let upper = max(from.x, to.x) + hitRadius
        var updates: [NoteVelocity] = []
        updates.reserveCapacity(candidates.count)
        for candidate in candidates {
            var y = to.y
            if deltaX == 0 {
                if abs(candidate.x - to.x) > hitRadius { continue }
            } else {
                if candidate.x < lower || candidate.x > upper { continue }
                let t = min(max((candidate.x - from.x) / deltaX, 0), 1)
                y = from.y + t * (to.y - from.y)
            }
            let velocity = resolvedVelocity(axis: axis, noteMap: candidate.note.map,
                                            detentUnlock: detentUnlock, y: y)
            updates.append(NoteVelocity(noteID: candidate.note.noteID, velocity: Int(velocity)))
        }
        return updates
    }

    /// The commit payload in frozen order: every previewed value, once.
    public static func updates(_ gesture: VelocityGestureState) -> [NoteVelocity] {
        gesture.notes.compactMap { note in
            guard let velocity = gesture.preview[note.noteID],
                  velocity != note.velocity
            else { return nil }
            return NoteVelocity(noteID: note.noteID, velocity: Int(velocity))
        }
    }
}

// MARK: - Prompt transaction

/// The Set Velocity prompt's frozen transaction: the captured targets, their
/// before-values and the document identity they were captured under. The draft
/// is presentation state; only acceptance mutates the document.
public struct VelocityPromptState: Equatable, Sendable {
    public var revision: UInt64
    public var track: Int
    public var noteIDs: [NoteID]
    public var beforeValues: [UInt8]
    public var initialValue: Int
    public var draft: String
    public var error: String

    public init(revision: UInt64, track: Int, noteIDs: [NoteID], beforeValues: [UInt8],
                initialValue: Int, draft: String, error: String = "") {
        self.revision = revision
        self.track = track
        self.noteIDs = noteIDs
        self.beforeValues = beforeValues
        self.initialValue = initialValue
        self.draft = draft
        self.error = error
    }
}

/// The draft rule: decimal `1...127`, nothing else. An invalid draft publishes
/// an error and commits nothing.
public enum VelocityPromptPolicy {
    public static let minimum = 1
    public static let maximum = 127

    public static func value(draft: String) -> Int? {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 3, trimmed.allSatisfy(\.isNumber),
              let value = Int(trimmed), (minimum...maximum).contains(value)
        else { return nil }
        return value
    }

    public static func error(draft: String) -> String {
        value(draft: draft) == nil ? "Enter a velocity from \(minimum) to \(maximum)." : ""
    }
}

// MARK: - Page geometry

/// The page's font-relative geometry, derived exactly as
/// `VelocityArea::Geometry::resolve` derives it from `layout::fontPx` and the
/// `layout::space` tokens the ruler and transient use.
public struct VelocityNodeGeometry: Equatable, Sendable {
    public var hitRadius: Double = 0
    public var durationLineVerticalRadius: Double = 0
    public var durationLineHorizontalSlop: Double = 0
    public var dragActivationDistance: Double = 0
    public var nodePaintRadius: Double = 0
    public var nodeOutlineDipWidth: Double = 0
    public var selectedNodeRingRadius: Double = 0
    public var selectedNodeRingDipWidth: Double = 0
    public var stemDipWidth: Double = 0
    public var selectedStemDipWidth: Double = 0
    public var densityD1: Double = 0
    public var densityD2: Double = 0
    public var densityD3: Double = 0
    public var densityD4: Double = 0
    public var verticalInset: Double = 0
    public var labelSideInset: Double = 0
    public var labelColumnGap: Double = 0
    public var tickLabelLength: Double = 0
    public var tickShortLength: Double = 0
    public var markerLength: Double = 0
    public var gridLineStroke: Double = 0
    public var pixel: Double = 1

    public init() {}

    public init(baseFontPx: Double, devicePixelRatio: Double) {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        let dpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        func px(_ multiplier: Double) -> Double { fontPx(base, multiplier) }
        densityD1 = px(6)
        densityD2 = px(25.0 / 3.0)
        densityD3 = px(12)
        densityD4 = px(24)
        hitRadius = px(0.5)
        durationLineVerticalRadius = px(1.0 / 3.0)
        durationLineHorizontalSlop = px(1.0 / 6.0)
        dragActivationDistance = px(1.0 / 12.0)
        nodePaintRadius = px(7.0 / 26.0)
        nodeOutlineDipWidth = px(1.0 / 12.0)
        selectedNodeRingRadius = px(3.0 / 8.0)
        selectedNodeRingDipWidth = px(1.0 / 6.0)
        stemDipWidth = px(1.0 / 6.0)
        selectedStemDipWidth = px(1.0 / 4.0)
        verticalInset = px(0.75)
        labelSideInset = px(0.5)
        labelColumnGap = px(0.25)
        tickLabelLength = 3 * px(0.125)
        tickShortLength = px(0.25)
        markerLength = px(0.5)
        gridLineStroke = px(1.0 / 6.0) * physicalPixel(dpr)
        pixel = physicalPixel(dpr)
    }
}

// MARK: - Published note handle

/// One published note handle: stable identity, plot geometry, displayed value
/// and state. QML draws only these values, and the page's own hit tests read the
/// same objects, so a pointer lands on exactly what the renderer drew.
@MainActor
@QtBridgeable
public final class VelocityHandle {
    /// The stable `NoteID` token as text: `UInt64` is not a bridge type.
    public var noteIdText: String = ""
    public var tick: Double = 0
    public var endTick: Double = 0
    public var x: Double = 0
    public var endX: Double = 0
    public var value: Int = 1
    public var y: Double = 0
    public var selected: Bool = false
    public var hovered: Bool = false
    public var preview: Bool = false
    public var dimmed: Bool = false
    public var level: Int = -1
    public var label: String = ""
    public var hitRadius: Double = 0
    public var stemWidth: Double = 0
    public var nodeRadius: Double = 0
    public var outlineRadius: Double = 0
    public var outlineWidth: Double = 0
    public var ringRadius: Double = 0
    public var ringWidth: Double = 0
    public var fillColor: String = ""
    public var stemColor: String = ""
    public var ringColor: String = ""
    public var outlineColor: String = ""
    public var primitiveName: String = ""

    public init() {}

    /// The model's no-op rule: an unchanged handle stays in place, so an
    /// unchanged row emits nothing.
    @QtIgnored
    func matches(_ other: VelocityHandle) -> Bool {
        noteIdText == other.noteIdText && tick == other.tick && endTick == other.endTick
            && x == other.x && endX == other.endX && value == other.value && y == other.y
            && selected == other.selected && hovered == other.hovered
            && preview == other.preview && dimmed == other.dimmed && level == other.level
            && label == other.label && hitRadius == other.hitRadius
            && stemWidth == other.stemWidth && nodeRadius == other.nodeRadius
            && outlineRadius == other.outlineRadius && outlineWidth == other.outlineWidth
            && ringRadius == other.ringRadius && ringWidth == other.ringWidth
            && fillColor == other.fillColor && stemColor == other.stemColor
            && ringColor == other.ringColor && outlineColor == other.outlineColor
            && primitiveName == other.primitiveName
    }
}

// MARK: - Page owner

/// The production Velocity page. Every published value derives from the current
/// document session; every mutation goes through `SongDocument.setVelocities`
/// with the revision captured when the interaction began, so at most one history
/// entry is produced per completed gesture or accepted prompt.
@MainActor
@QtBridgeable
public final class VelocityPage: EditorDrawerPage {
    /// The fixed production QML URL, resolved once by the container at attach.
    public static let contentUrl = "qrc:/porydaw/drawer/VelocityPage.qml"

    @QtIgnored public let sectionKind: DrawerSectionKind = .velocity
    @QtIgnored public var contentUrl: String { Self.contentUrl }
    /// Production's velocity default body:
    /// `clamp(hostHeight / 6, fontPx(8), fontPx(12))`.
    @QtIgnored public var bodyPolicy: EditorDrawerBodyPolicy
    /// The container's follow-scroll gate: a pointer gesture, a frozen preview,
    /// a live prompt or a band selection is an active interaction. Stored, so the
    /// bridge publishes it and every mutation path refreshes it through
    /// `refreshInteractionPublished()`; the rule itself lives in one place.
    public var interactionActive: Bool = false
    /// `VelocityArea::useDetents`: the page's own detent preference. Enabled by
    /// default; `setUseDetents(false)` turns every context into the continuous
    /// 1-127 domain, which is what the legacy detent control toggles.
    public var detentsEnabled: Bool = true
    /// `VelocityArea::isPsgContext`: the detent control is available only while
    /// the presented context resolves to a PSG voice.
    public var detentsAvailable: Bool = false

    // MARK: Published projection

    public var plotHeight: Double = 0
    public var plotWidth: Double = 0
    public var rulerWidth: Double = 0
    public var devicePixelRatio: Double = 1
    public var baseFontPx: Double = GridCameraPolicy.seedBaseFontPx
    public var axisMode: Int = 0
    /// `rebuildQuickAxis`'s rendering branch: the level graduations are drawn only
    /// for an intrinsic context with detents enabled, and the continuous ladder
    /// takes over otherwise.
    public var axisGraduationsVisible: Bool = false
    public var axisAccessibleDescription: String = "Velocity"
    /// `true` while the active context's exact map is unknown: rendering, hover
    /// and navigation stay live, and every exact-map edit is refused.
    public var contextUnsupported: Bool = false
    public var contextDiagnostic: String = ""
    public var contextSlot: Int = -1
    public var contextVoiceName: String = ""
    public var readoutText: String = ""
    public var readoutVisible: Bool = false
    public var readoutX: Double = 0
    public var readoutY: Double = 0
    public var selectedCount: Int = 0
    public var hoveredNoteText: String = ""
    public var rampVisible: Bool = false
    public var rampX0: Double = 0
    public var rampY0: Double = 0
    public var rampLength: Double = 0
    public var rampSlopeY: Double = 0
    public var rampColor: String = ""
    public var promptOpen: Bool = false
    public var promptDraft: String = ""
    public var promptError: String = ""
    public var promptTitle: String = "Note velocity"
    public var promptLabel: String = "Velocity (1-127):"
    public var promptMinimum: Int = VelocityPromptPolicy.minimum
    public var promptMaximum: Int = VelocityPromptPolicy.maximum
    public var promptInitialValue: Int = VelocityPromptPolicy.minimum

    public var gridLines: QListModel<SceneRect> = QListModel()
    public var psgBands: QListModel<SceneRect> = QListModel()
    /// The gesture transient's rects. `transient` alone is a reserved QML
    /// keyword, so the published name carries its own noun.
    public var transientRects: QListModel<SceneRect> = QListModel()
    public var axisTicks: QListModel<SceneRect> = QListModel()
    public var axisGraduations: QListModel<SceneRect> = QListModel()
    public var axisMarkers: QListModel<SceneRect> = QListModel()
    public var axisLabels: QListModel<SceneText> = QListModel()
    public var handles: QListModel<VelocityHandle> = QListModel()

    /// Distinct content rebuilds: shared-playhead movement inside one voice
    /// context, and repeated equal publications, rebuild nothing.
    @QtIgnored public private(set) var contentBuildCount: UInt64 = 0
    /// Shared-playhead presentations the page consumed.
    @QtIgnored public private(set) var playheadPresentationCount: UInt64 = 0
    /// The tick and context slot the page last presented.
    @QtIgnored public private(set) var presentedContextTick: Tick = 0
    @QtIgnored public private(set) var presentedContextSlot: Int = -1
    @QtIgnored public private(set) var presentedPlaying = false
    /// The last publication the page consumed, so one published change that
    /// reaches the page through both of its signals counts once.
    @QtIgnored private var lastPresentedPublication: (tick: Tick, playing: Bool)?
    @QtIgnored public var hasGesture: Bool { gesture != nil }
    /// The primary track's selected notes as the published identity text, for the
    /// lane's real-input cases: the grid's own summary is only as fresh as its
    /// last publication, and this page owns the live selection projection.
    public func selectedNoteIdText() -> String {
        selectedTrackNotes().map { velocityNoteText($0.id) }.joined(separator: ",")
    }
    @QtIgnored public var hasPrompt: Bool { prompt != nil }
    @QtIgnored public var frozenPreview: [NoteID: UInt8] { gesture?.preview ?? [:] }
    @QtIgnored public var frozenNotes: [VelocityFrozenNote] { gesture?.notes ?? [] }
    @QtIgnored public var promptTargets: [NoteID] { prompt?.noteIDs ?? [] }
    @QtIgnored public var promptBeforeValues: [UInt8] { prompt?.beforeValues ?? [] }
    @QtIgnored public var publishedNoteCount: Int { publishedHandles.count }
    @QtIgnored public var publishedHandlesSnapshot: [VelocityHandle] { publishedHandles }
    @QtIgnored public var axisModel: VelocityAxisModel { axis }
    @QtIgnored public var context: VelocityVoiceContext { resolvedContextValue }
    /// The presented context's end tick, and the slot that owns it: the same
    /// boundary the page uses to decide whether a playhead move is a context
    /// change, published for the lane's span-aware cases.
    @QtIgnored public var presentedContextEndTick: Tick { resolvedContextValue.endTick ?? TimeDefaults.noTick }

    @QtIgnored private weak var session: DocumentSession?
    @QtIgnored private var palette = GridPalette()
    @QtIgnored private var geometry = VelocityNodeGeometry()
    @QtIgnored private var axis = VelocityAxisModel()
    @QtIgnored private var resolvedContextValue = VelocityVoiceContext(status: .unresolvedVoice)
    @QtIgnored private var publishedHandles: [VelocityHandle] = []
    @QtIgnored private var gesture: VelocityGestureState?
    @QtIgnored private var prompt: VelocityPromptState?
    @QtIgnored private var hovered: NoteID?
    @QtIgnored private var selectionBeforePress: Set<NoteID> = []
    @QtIgnored private var pressedNote: NoteID?
    @QtIgnored private var dragDistance: Double = 10
    @QtIgnored private var contextTick: Tick = 0
    @QtIgnored private var playing = false
    @QtIgnored private var lastContextKey: ContextKey?
    @QtIgnored private var typographyCache: (key: TypographyKey, value: GridTypography)?

    private struct ContextKey: Equatable {
        var slot: Int
        var status: Int
        var playing: Bool
    }

    private struct TypographyKey: Equatable {
        var baseFontPx: Double
        var devicePixelRatio: Double
        var rowHeight: Double
    }

    public init(baseFontPx: Double = VelocityPagePolicy.seedBaseFontPx) {
        let base = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        bodyPolicy = EditorDrawerBodyPolicy { hostHeight, _ in
            let preferred = Double(hostHeight) / 6
            let minimum = max(1, (base * 8).rounded())
            let maximum = max(minimum, (base * 12).rounded())
            return Int(min(max(preferred, minimum), maximum))
        }
        geometry = VelocityNodeGeometry(baseFontPx: base, devicePixelRatio: 1)
    }

    /// Installs the document and palette owners. Called before the container
    /// attaches the page, so no publication can precede the session it reads.
    @QtIgnored
    public func attach(session: DocumentSession, palette: GridPalette) {
        self.session = session
        self.palette = palette
        contextTick = session.editCursor
        refreshFromDocument()
    }

    /// Drops the session and everything the page owns. Called after the host
    /// acknowledged scene removal and before the document owners retire.
    @QtIgnored
    public func detach() {
        cancelSectionInteraction()
        session = nil
        hovered = nil
        refreshInteractionPublished()
        publishHandles([])
    }

    // MARK: Composition input

    /// The page body's own facts, pushed by the production QML as it lays out:
    /// the same plot origin and base font the roll and the container use.
    public func configureBody(width: Double, height: Double, rulerWidth: Double,
                              devicePixelRatio: Double, baseFontPx: Double,
                              dragDistance: Double) {
        let nextWidth = max(0, width.isFinite ? width : 0)
        let nextHeight = max(0, height.isFinite ? height : 0)
        let nextRuler = max(0, rulerWidth.isFinite ? rulerWidth : 0)
        let nextDpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1
        let nextFont = baseFontPx.isFinite && baseFontPx > 0
            ? baseFontPx
            : GridCameraPolicy.seedBaseFontPx
        if dragDistance.isFinite, dragDistance > 0, dragDistance != self.dragDistance {
            self.dragDistance = dragDistance
        }
        let changed = nextWidth != plotWidth || nextHeight != plotHeight
            || nextRuler != self.rulerWidth || nextDpr != self.devicePixelRatio
            || nextFont != self.baseFontPx
        if plotWidth != nextWidth { plotWidth = nextWidth }
        if plotHeight != nextHeight { plotHeight = nextHeight }
        if self.rulerWidth != nextRuler { self.rulerWidth = nextRuler }
        if self.devicePixelRatio != nextDpr { self.devicePixelRatio = nextDpr }
        if self.baseFontPx != nextFont { self.baseFontPx = nextFont }
        if changed { rebuildContent() }
    }

    // MARK: Session refresh

    /// Document, undo/redo, track or selection publication: a live interaction
    /// whose captured identity no longer matches cancels, then content rebuilds.
    @QtIgnored
    public func refreshFromDocument() {
        guard let session else { return }
        if let gesture, gesture.revision != session.document.revision
            || gesture.track != (session.selectedTrack ?? -1)
        {
            cancelSectionInteraction()
        }
        if promptRevisionMismatch(session) { cancelPrompt() }
        contextTick = session.editCursor
        rebuildContent()
    }

    /// Camera-only publication: the same notes at new plot positions.
    @QtIgnored
    public func refreshCamera() {
        guard session != nil else { return }
        rebuildContent()
    }

    /// One shared-playhead presentation, delivered by `ApplicationSession`'s
    /// Swift fan-out from `SharedPlayheadPresenter.onPresentation` — never from
    /// QML, which would have to reach a mutator through a transient bridge
    /// wrapper. Movement inside one voice context only re-publishes the readout;
    /// a context or playing-state change rebuilds.
    @QtIgnored
    public func refreshPlayhead(tick: Double, playing: Bool) {
        guard let session else { return }
        let resolvedTick = velocityContextTick(tick)
        if let last = lastPresentedPublication, last.tick == resolvedTick,
           last.playing == playing
        {
            return
        }
        lastPresentedPublication = (resolvedTick, playing)
        playheadPresentationCount &+= 1
        let effective = playing ? resolvedTick : session.editCursor
        contextTick = resolvedTick
        let next = contextKey(at: effective, playing: playing)
        presentedContextTick = resolvedTick
        presentedContextSlot = next.slot
        presentedPlaying = playing
        let playingChanged = self.playing != playing
        self.playing = playing
        if lastContextKey != next || playingChanged {
            rebuildContent()
        } else {
            publishReadout()
        }
    }

    // MARK: Page seam

    /// The page's local Escape: an open prompt or a live gesture claims the key;
    /// otherwise it stays unhandled for the shared routing.
    public func handleEscape() -> Bool {
        if prompt != nil {
            cancelPrompt()
            return true
        }
        guard gesture != nil else { return false }
        cancelSectionInteraction()
        return true
    }

    public func cancelSectionInteraction() {
        cancelGesture()
        cancelPrompt()
    }

    // MARK: Pointer input

    /// One press. `true` means the page consumed it.
    @discardableResult
    public func pointerPress(x: Double, y: Double, surface: Int, button: Int,
                             modifiers: Int) -> Bool {
        guard let session, let input = VelocityInputSurface(rawValue: surface) else { return false }
        if prompt != nil { cancelPrompt() }
        if gesture != nil { cancelGesture() }
        selectionBeforePress = session.selectedNotes
        pressedNote = nil
        switch input {
        case .ruler:
            guard button == VelocityQtButton.left, axis.inRuler(x: x, rulerWidth: rulerWidth)
            else { return false }
            guard !contextUnsupported else { return true }
            let unlock = detentsUnlocked(modifiers: modifiers, allowShift: false)
            let velocity = unlock
                ? Int(clampVelocity(axis.yToVelocity(y)))
                : axis.rulerVelocityAt(y: y, labelHeight: axis.geometry.labelHeight)
            guard velocity >= 1 else { return true }
            beginGesture(kind: .relative, x: x, y: y, detentUnlock: unlock,
                         notes: selectedTrackNotes(), modifiers: modifiers)
            guard var live = gesture else { return true }
            var preview: [NoteID: UInt8] = [:]
            for note in live.notes { preview[note.noteID] = UInt8(velocity) }
            live.preview = preview
            gesture = live
            finishGesture(commit: !preview.isEmpty)
        case .plot:
            if button == VelocityQtButton.middle {
                // The shared camera's pan, requested from the band that renders
                // its projection: one delta per move, clamped by the camera.
                beginGesture(kind: .pan, x: x, y: y, detentUnlock: false, notes: [],
                             modifiers: modifiers)
                return true
            }
            if button == VelocityQtButton.right {
                beginGesture(kind: .pendingBand, x: x, y: y, detentUnlock: false, notes: [],
                             modifiers: modifiers)
                if let hit = hitTest(x: x, y: y, includeStems: true) { pressedNote = hit }
                if let pressed = pressedNote, !isControl(modifiers),
                   !selectionBeforePress.contains(pressed)
                {
                    setSelection([pressed])
                }
                return true
            }
            guard button == VelocityQtButton.left else { return false }
            let unlock = detentsUnlocked(modifiers: modifiers, allowShift: true)
            if isShift(modifiers) {
                guard !contextUnsupported else { return true }
                beginGesture(kind: .ramp, x: x, y: y, detentUnlock: unlock,
                             notes: selectedTrackNotes(), modifiers: modifiers)
                updateRampPreview(x: x, y: y)
                return true
            }
            let hit = hitTest(x: x, y: y, includeStems: true)
            pressedNote = hit
            if hit == nil {
                beginGesture(kind: .paint, x: x, y: y, detentUnlock: unlock, notes: [],
                             modifiers: modifiers)
                guard !contextUnsupported else { return true }
                paintBetween(fromX: x, fromY: y, toX: x, toY: y)
                return true
            }
            if isControl(modifiers) {
                var selection = selectionBeforePress
                if let hit, !selection.contains(hit) { selection.insert(hit) }
                setSelection(selection)
            } else if let hit, !selectionBeforePress.contains(hit) {
                setSelection([hit])
            }
            // Selection is presentation state and stays available; the velocity
            // gesture itself needs the exact map, so an unknown context refuses
            // to freeze one.
            guard !contextUnsupported else { return true }
            beginGesture(kind: .relative, x: x, y: y, detentUnlock: unlock,
                         notes: selectedTrackNotes(), modifiers: modifiers)
        }
        return true
    }

    /// One move. With no live gesture this is hover only.
    @discardableResult
    public func pointerMove(x: Double, y: Double, buttons: Int) -> Bool {
        guard session != nil else { return false }
        _ = buttons
        guard var live = gesture else {
            updateHover(x: x, y: y)
            return true
        }
        switch live.kind {
        case .relative:
            live.bandX = x
            live.bandY = y
            VelocityGesturePolicy.applyRelative(&live, y: y)
            live.previousX = x
            live.previousY = y
            gesture = live
            publishHandles(projectHandles())
        case .paint:
            paintBetween(fromX: live.previousX, fromY: live.previousY, toX: x, toY: y)
            gesture?.previousX = x
            gesture?.previousY = y
        case .ramp:
            updateRampPreview(x: x, y: y)
        case .pendingBand:
            if abs(x - live.pressX) + abs(y - live.pressY) >= dragDistance {
                live.kind = .band
                live.bandX = x
                live.bandY = y
                gesture = live
                updateBandPreview(x: x, y: y)
            }
        case .band:
            updateBandPreview(x: x, y: y)
        case .pan:
            let delta = x - live.previousX
            gesture?.previousX = x
            gesture?.previousY = y
            if delta != 0, let session {
                session.mutateCamera { $0.setHScroll($0.snapshot.scrollX - delta) }
            }
        }
        return true
    }

    /// One release: the only place a gesture reaches the document.
    @discardableResult
    public func pointerRelease(x: Double, y: Double, button: Int) -> Bool {
        guard session != nil, let live = gesture else { return false }
        if button == VelocityQtButton.middle {
            finishGesture(commit: false)
            return true
        }
        if button == VelocityQtButton.right {
            // The secondary release resolves the band selection and never
            // commits: a band replaces the selection (or extends it under the
            // modifier), and a stationary secondary press toggles the pressed
            // note or clears an empty selection.
            switch live.kind {
            case .band:
                var selection = live.controlPress ? selectionBeforePress : Set<NoteID>()
                for id in live.bandPreview { selection.insert(id) }
                finishGesture(commit: false)
                setSelection(selection)
            case .pendingBand:
                if live.controlPress {
                    var selection = session?.selectedNotes ?? []
                    if let pressed = pressedNote {
                        if selection.contains(pressed) {
                            selection.remove(pressed)
                        } else {
                            selection.insert(pressed)
                        }
                    }
                    finishGesture(commit: false)
                    setSelection(selection)
                } else if pressedNote == nil {
                    finishGesture(commit: false)
                    setSelection([])
                } else {
                    finishGesture(commit: false)
                }
            default:
                finishGesture(commit: false)
            }
            return true
        }
        guard button == VelocityQtButton.left else { return true }
        switch live.kind {
        case .paint:
            let commit = !live.notes.isEmpty && !live.preview.isEmpty
            if !commit { setSelection([]) }
            finishGesture(commit: commit)
        case .ramp:
            finishGesture(commit: live.previousX != live.pressX || live.previousY != live.pressY)
        case .relative:
            if !live.relativeActivated {
                if live.controlPress {
                    var selection = selectionBeforePress
                    if let pressed = pressedNote {
                        if selection.contains(pressed) {
                            selection.remove(pressed)
                        } else {
                            selection.insert(pressed)
                        }
                    }
                    setSelection(selection)
                } else if let pressed = pressedNote {
                    setSelection([pressed])
                } else {
                    setSelection([])
                }
            }
            finishGesture(commit: live.relativeActivated)
        case .pendingBand, .band, .pan:
            finishGesture(commit: false)
        }
        return true
    }

    /// The pointer left: hover clears, a live gesture keeps its frozen state.
    public func pointerLeave() {
        hovered = nil
        guard gesture == nil else { return }
        refreshAxisAndHandles()
    }

    // MARK: Prompt

    /// Opens the Set Velocity prompt for the current selection. The command's
    /// availability already gates an empty selection; this repeats the check so
    /// the entry point is safe on its own.
    @discardableResult
    public func openSelectedVelocityPrompt() -> Bool {
        guard let session, !contextUnsupported else { return false }
        let notes = selectedTrackNotes()
        guard !notes.isEmpty else { return false }
        cancelGesture()
        let ids = notes.map(\.id)
        let before = notes.map(\.velocity)
        let initial = promptInitialValue(for: notes)
        prompt = VelocityPromptState(revision: session.document.revision,
                                     track: session.selectedTrack ?? -1,
                                     noteIDs: ids, beforeValues: before, initialValue: initial,
                                     draft: String(initial))
        setPublished(&promptOpen, true)
        setPublished(&promptDraft, String(initial))
        setPublished(&promptError, "")
        setPublished(&promptInitialValue, initial)
        refreshInteractionPublished()
        publishHandles(projectHandles())
        return true
    }

    /// Draft editing: presentation state only, never a document mutation.
    public func updatePromptDraft(draft text: String) {
        guard var live = prompt else { return }
        live.draft = String(text.prefix(4))
        live.error = VelocityPromptPolicy.error(draft: live.draft)
        prompt = live
        setPublished(&promptDraft, live.draft)
        setPublished(&promptError, live.error)
    }

    /// Acceptance: one `setVelocities` transaction for the captured targets, or
    /// nothing at all when the draft is invalid, the capture is stale, the track
    /// moved, or no target survives. `true` means the prompt committed.
    @discardableResult
    public func acceptPrompt() -> Bool {
        guard let session, let live = prompt else { return false }
        guard let value = VelocityPromptPolicy.value(draft: live.draft) else {
            setPublished(&promptError, VelocityPromptPolicy.error(draft: live.draft))
            return false
        }
        prompt = nil
        setPublished(&promptOpen, false)
        setPublished(&promptDraft, "")
        setPublished(&promptError, "")
        refreshInteractionPublished()
        defer { publishHandles(projectHandles()) }
        guard live.revision == session.document.revision,
              live.track == (session.selectedTrack ?? -1)
        else { return false }
        var updates: [NoteVelocity] = []
        updates.reserveCapacity(live.noteIDs.count)
        for id in live.noteIDs {
            guard session.document.note(id) != nil else { return false }
            updates.append(NoteVelocity(noteID: id, velocity: value))
        }
        guard !updates.isEmpty else { return false }
        _ = session.document.setVelocities(updates, expectedRevision: live.revision)
        return true
    }

    /// Dismissal: draft, capture and error drop without a write.
    public func cancelPrompt() {
        guard prompt != nil else { return }
        prompt = nil
        setPublished(&promptOpen, false)
        setPublished(&promptDraft, "")
        setPublished(&promptError, "")
        refreshInteractionPublished()
        publishHandles(projectHandles())
    }

    // MARK: Gesture plumbing

    private func promptRevisionMismatch(_ session: DocumentSession) -> Bool {
        guard let prompt else { return false }
        return prompt.revision != session.document.revision
            || prompt.track != (session.selectedTrack ?? -1)
    }

    private func isShift(_ modifiers: Int) -> Bool {
        modifiers & VelocityModifier.shift != 0
    }

    private func isControl(_ modifiers: Int) -> Bool {
        modifiers & VelocityModifier.control != 0
    }

    /// `keymap::Registry::matchesModifier`: the binding is exactly Control, with
    /// Shift admitted only where production admits it (`allowShift`).
    private func detentUnlocked(modifiers: Int, allowShift: Bool) -> Bool {
        let held = modifiers & VelocityModifier.shortcutMask
        return held == VelocityModifier.control
            || (allowShift && held == (VelocityModifier.control | VelocityModifier.shift))
    }

    /// The page's whole unlock rule: a disabled detent set unlocks everything,
    /// otherwise the held modifier decides. `VelocityArea::detentsUnlocked`.
    private func detentsUnlocked(modifiers: Int, allowShift: Bool) -> Bool {
        !detentsEnabled || detentUnlocked(modifiers: modifiers, allowShift: allowShift)
    }

    /// Re-derives the published interaction gate from the page's own state.
    private func refreshInteractionPublished() {
        let active = gesture != nil || prompt != nil
        if interactionActive != active { interactionActive = active }
    }

    /// The detent control's own activation, exactly `VelocityArea::setUseDetents`:
    /// the preference flips, the live interaction cancels and the ruler
    /// republishes.
    public func setUseDetents(enabled: Bool) {
        guard detentsEnabled != enabled else { return }
        cancelGesture()
        detentsEnabled = enabled
        refreshAxisAndHandles()
    }

    /// The control's press action.
    public func toggleDetents() {
        setUseDetents(enabled: !detentsEnabled)
    }

    private func beginGesture(kind: VelocityGestureKind, x: Double, y: Double,
                              detentUnlock: Bool, notes: [Note], modifiers: Int) {
        gesture = VelocityGestureState(
            kind: kind, revision: session?.document.revision ?? 0,
            track: session?.selectedTrack ?? -1, notes: freeze(notes), axis: axis,
            detentUnlock: detentUnlock, activationDistance: geometry.dragActivationDistance,
            pressX: x, pressY: y, controlPress: isControl(modifiers))
        refreshInteractionPublished()
        publishHandles(projectHandles())
    }

    private func freeze(_ notes: [Note]) -> [VelocityFrozenNote] {
        notes.map { freeze($0) }
    }

    private func freeze(_ note: Note) -> VelocityFrozenNote {
        VelocityFrozenNote(noteID: note.id, tick: note.tick, duration: note.duration,
                           pitch: note.pitch, velocity: note.velocity,
                           map: voiceMap(at: note.tick), exactOrigin: note.velocity)
    }

    private func cancelGesture() {
        guard gesture != nil else { return }
        let selectionBefore = selectionBeforePress
        gesture = nil
        pressedNote = nil
        selectionBeforePress = []
        if let session, session.selectedNotes != selectionBefore {
            // A cancelled gesture restores the selection its press replaced.
            session.selectedNotes = selectionBefore
        }
        refreshInteractionPublished()
        publishHandles(projectHandles())
        publishTransient()
    }

    /// Release: one semantic document operation, or none when the gesture
    /// committed nothing or its captured revision moved under it.
    private func finishGesture(commit: Bool) {
        guard let live = gesture else { return }
        gesture = nil
        pressedNote = nil
        selectionBeforePress = []
        if commit, let session, live.revision == session.document.revision {
            let updates = VelocityGesturePolicy.updates(live)
            if !updates.isEmpty {
                _ = session.document.setVelocities(updates, expectedRevision: live.revision)
            }
        }
        refreshInteractionPublished()
        publishHandles(projectHandles())
        publishTransient()
    }

    private func setSelection(_ ids: Set<NoteID>) {
        guard let session else { return }
        session.selectedNotes = ids
        refreshAxisAndHandles()
    }

    private func updateRampPreview(x: Double, y: Double) {
        guard var live = gesture else { return }
        VelocityGesturePolicy.applyRamp(&live, x: x, y: y, hitRadius: geometry.hitRadius) { note in
            self.xForDisplayTick(Double(note.tick))
        }
        live.previousX = x
        live.previousY = y
        gesture = live
        publishHandles(projectHandles())
        publishTransient()
    }

    /// One paint step. The first step freezes the selection; later steps add the
    /// notes the swept column reaches, exactly like `paintSelectedNodesBetween`.
    private func paintBetween(fromX: Double, fromY: Double, toX: Double, toY: Double) {
        guard var live = gesture else { return }
        var frozen = live.notes
        let radius = geometry.hitRadius
        let deltaX = toX - fromX
        for note in selectedTrackNotes()
        where !frozen.contains(where: { $0.noteID == note.id }) {
            let x = xForDisplayTick(Double(note.tick))
            let inSpan = deltaX == 0
                ? abs(x - toX) <= radius
                : (x >= min(fromX, toX) - radius && x <= max(fromX, toX) + radius)
            if inSpan { frozen.append(freeze(note)) }
        }
        live.notes = frozen
        gesture = live
        guard !frozen.isEmpty else { return }
        let updates = VelocityGesturePolicy.paint(
            axis: live.axis, detentUnlock: live.detentUnlock,
            candidates: frozen.map { (note: $0, x: xForDisplayTick(Double($0.tick))) },
            from: (fromX, fromY), to: (toX, toY), hitRadius: radius)
        guard !updates.isEmpty else { return }
        var preview = live.preview
        for update in updates { preview[update.noteID] = UInt8(update.velocity) }
        gesture?.preview = preview
        publishHandles(projectHandles())
    }

    private func updateBandPreview(x: Double, y: Double) {
        guard var live = gesture else { return }
        live.bandX = x
        live.bandY = y
        let minX = min(live.pressX, x)
        let maxX = max(live.pressX, x)
        let minY = min(live.pressY, y)
        let maxY = max(live.pressY, y)
        let radius = geometry.hitRadius
        var hits: [NoteID] = []
        for handle in publishedHandles {
            let x0 = handle.x - radius
            let y0 = handle.y - radius
            if x0 + 2 * radius >= minX, x0 <= maxX, y0 + 2 * radius >= minY, y0 <= maxY,
               let id = noteID(fromText: handle.noteIdText)
            {
                hits.append(id)
            }
        }
        live.bandPreview = hits
        gesture = live
        publishHandles(projectHandles())
        publishTransient()
    }

    private func updateHover(x: Double, y: Double) {
        let hit = hitTest(x: x, y: y, includeStems: false)
        guard hit != hovered else { return }
        hovered = hit
        refreshAxisAndHandles()
    }

    // MARK: Selection and context

    private func trackNotes() -> [Note] {
        guard let session, let track = session.selectedTrack else { return [] }
        return session.document.notes(in: track)
    }

    /// The primary track's selected notes in document order: the set a roll
    /// selection resolves to, and the page's gesture and prompt target.
    ///
    /// Document order (tick, then identity) is the deterministic order this
    /// build can reconstruct, because `DocumentSession.selectedNotes` is a
    /// `Set<NoteID>` and keeps no selection insertion order. The prompt's
    /// initial value therefore prefers the note the user last pointed at inside
    /// the captured set, and otherwise the first note in document order; the
    /// legacy `resolveSelection().front()` insertion order is not reconstructible
    /// from available state and is reported as that precise gap.
    private func selectedTrackNotes() -> [Note] {
        guard let session, let track = session.selectedTrack else { return [] }
        return session.selectedNotes.compactMap { session.document.note($0) }
            .filter { $0.track == track }
            .sorted {
                $0.tick == $1.tick ? $0.id.rawValue < $1.id.rawValue : $0.tick < $1.tick
            }
    }

    /// The prompt's initial value: the note the page last pointed at (pressed,
    /// then hovered) when it is one of the captured targets, else the first
    /// captured target in document order.
    private func promptInitialValue(for notes: [Note]) -> Int {
        let pointed = pressedNote ?? hovered
        if let pointed, let note = notes.first(where: { $0.id == pointed }) {
            return Int(note.velocity)
        }
        return Int(notes.first?.velocity ?? 100)
    }

    private func voiceMap(at tick: Tick) -> VelocityMap {
        resolvedContext(at: tick).map
    }

    /// The exact context at one tick, before any selection compatibility rule.
    private func resolvedContext(at tick: Tick) -> VelocityVoiceContext {
        guard let session else { return VelocityVoiceContext(status: .unresolvedVoice) }
        let track = session.selectedTrack ?? -1
        guard track >= 0, track < session.timeline.tracks.count else {
            return VelocityVoiceContext(status: .unresolvedVoice)
        }
        let (slot, endTick) = VelocityContextPolicy.slot(
            firstProgram: session.timeline.tracks[track].firstProgram, tick: tick,
            voiceChanges: session.document.lanePoints(track: track, lane: .voice))
        return VelocityContextPolicy.resolve(slot: slot, endTick: endTick,
                                             slots: session.bankSlots)
    }

    private func contextKey(at tick: Tick, playing: Bool) -> ContextKey {
        let context = resolvedContext(at: tick)
        return ContextKey(slot: context.slot, status: context.status.rawValue, playing: playing)
    }

    /// The context the ruler presents: the shared playhead's rounded tick while
    /// transport is playing, the edit cursor while stopped.
    private func effectiveContextTick() -> Tick {
        guard let session else { return 0 }
        return playing ? contextTick : session.editCursor
    }

    /// `VelocityArea::currentContext`: no selection resolves the context at the
    /// effective tick; a selection resolves per note, keeps an intrinsic map only
    /// when every selected note resolves to the same PSG voice, and falls back to
    /// the continuous domain when their maps disagree.
    private func presentationContext(_ handles: [VelocityHandle]) -> VelocityVoiceContext {
        let selected = handles.filter(\.selected)
        guard !selected.isEmpty else { return resolvedContext(at: effectiveContextTick()) }
        let source = resolvedContext(at: TimeDefaults.tick(from: selected[0].tick))
        guard source.status == .resolved else { return source }
        guard source.map.isPSG else { return continuousContext(from: source) }
        for handle in selected.dropFirst() {
            let context = resolvedContext(at: TimeDefaults.tick(from: handle.tick))
            guard context.status == .resolved else { return context }
            guard context.map.compatible(with: source.map) else {
                return continuousContext(from: source)
            }
        }
        return source
    }

    /// A selection that cannot share one intrinsic map falls back to the
    /// continuous 1–127 domain, exactly as `VelocityMap::resolve(nullptr, none)`.
    private func continuousContext(from source: VelocityVoiceContext) -> VelocityVoiceContext {
        var resolved = source
        resolved.map = VelocityMap(voiceKind: .unresolved)
        return resolved
    }

    // MARK: Content rebuild

    /// Rebuilds every static projection: the ruler, the grid, the PSG bands and
    /// the note handles.
    private func rebuildContent() {
        guard session != nil, plotHeight > 0 || plotWidth > 0 else { return }
        contentBuildCount &+= 1
        geometry = VelocityNodeGeometry(baseFontPx: baseFontPx,
                                        devicePixelRatio: devicePixelRatio)
        let handles = projectHandles()
        let presented = presentationContext(handles)
        resolvedContextValue = presented
        lastContextKey = ContextKey(slot: presented.slot, status: presented.status.rawValue,
                                    playing: playing)
        contextUnsupported = !presented.editable
        contextDiagnostic = presented.diagnostic
        contextSlot = presented.slot
        contextVoiceName = presented.map.voiceName
        setPublished(&detentsAvailable, presented.status == .resolved && presented.map.isPSG)
        refreshAxisAndHandles()
        publishGrid()
        publishBands()
        publishTransient()
    }

    /// Axis plus handle rows: the hover path and a selection change republish
    /// these without rebuilding the static content.
    private func refreshAxisAndHandles() {
        let handles = projectHandles()
        rebuildAxis(handles)
        publishHandles(handles)
        publishReadout()
    }

    private func rebuildAxis(_ handles: [VelocityHandle]) {
        var activeValues: [UInt8] = []
        var mapped = resolvedContextValue.map
        if let hovered, let handle = handles.first(where: { $0.noteIdText == velocityNoteText(hovered) }) {
            activeValues.append(clampVelocity(handle.value))
            mapped = resolvedContext(at: TimeDefaults.tick(from: handle.tick)).map
        } else {
            for handle in handles where handle.selected {
                activeValues.append(clampVelocity(handle.value))
            }
        }
        var axisGeometry = VelocityAxisGeometry()
        axisGeometry.height = plotHeight
        axisGeometry.verticalInset = geometry.verticalInset
        axisGeometry.labelWidth = max(0, rulerWidth - geometry.pixel)
        axisGeometry.labelSideInset = geometry.labelSideInset
        axisGeometry.labelColumnGap = geometry.labelColumnGap
        axisGeometry.labelHeight = max(geometry.densityD1, plotHeight / 8)
        axisGeometry.continuousDensityD1 = geometry.densityD1
        axisGeometry.continuousDensityD2 = geometry.densityD2
        axisGeometry.continuousDensityD3 = geometry.densityD3
        axisGeometry.continuousDensityD4 = geometry.densityD4
        axis = VelocityAxisModel(map: mapped, geometry: axisGeometry, activeValues: activeValues)
        setPublished(&axisMode, axis.mode.rawValue)
        setPublished(&axisGraduationsVisible, axis.mode == .intrinsic && detentsEnabled)
        setPublished(&axisAccessibleDescription, axis.accessibleDescription)
        publishAxis()

    }

    private func xForDisplayTick(_ tick: Double) -> Double {
        guard let session else { return 0 }
        return session.camera.displayX(tick: tick, origin: 0, dpr: devicePixelRatio)
    }

    private func projectHandles() -> [VelocityHandle] {
        let selected = session?.selectedNotes ?? []
        let notes = trackNotes()
        let track = session?.selectedTrack ?? 0
        let trackColor = PaletteMath.trackIdentityFills[PaletteMath.trackIdentityIndex(track)]
        let trackChannels = PaletteMath.channels(trackColor)
        let stemColor = PaletteMath.hex(
            PaletteMath.mixTowardOklab(
                PaletteMath.oklab(r: trackChannels.r, g: trackChannels.g, b: trackChannels.b),
                PaletteMath.oklab(r: 0, g: 0, b: 0), 1.0 / 3.0))
        let selectedCount = notes.filter { selected.contains($0.id) }.count
        let dimUnselected = selectedCount > 1
        var result: [VelocityHandle] = []
        result.reserveCapacity(notes.count)
        for note in notes {
            let map = voiceMap(at: note.tick)
            let previewValue = gesture?.preview[note.id]
            let displayed = previewValue.map(Int.init) ?? Int(note.velocity)
            let isSelected = selected.contains(note.id)
            let frozen = gesture?.notes.first { $0.noteID == note.id }
            let handle = VelocityHandle()
            handle.noteIdText = velocityNoteText(note.id)
            handle.tick = Double(note.tick)
            handle.endTick = Double(note.tick) + Double(note.duration)
            handle.x = xForDisplayTick(Double(note.tick))
            handle.endX = xForDisplayTick(Double(note.tick) + Double(note.duration))
            handle.value = displayed
            handle.y = yForNote(map: frozen?.map ?? map, velocity: displayed,
                                detentUnlock: !detentsEnabled
                                    || (gesture?.detentUnlock ?? false))
            handle.selected = isSelected
            handle.hovered = hovered == note.id
            handle.preview = previewValue != nil
            handle.dimmed = dimUnselected && !isSelected
            handle.level = map.level(of: displayed) ?? -1
            handle.label = axis.mode == .intrinsic && handle.level >= 0
                ? "Vol \(handle.level + 1)"
                : "\(displayed)"
            handle.hitRadius = geometry.hitRadius
            handle.stemWidth = (isSelected ? geometry.selectedStemDipWidth
                                           : geometry.stemDipWidth) / devicePixelRatio
            handle.nodeRadius = geometry.nodePaintRadius
            handle.outlineRadius = geometry.nodePaintRadius + geometry.nodeOutlineDipWidth / 2
            handle.outlineWidth = geometry.nodeOutlineDipWidth / devicePixelRatio
            handle.ringRadius = geometry.selectedNodeRingRadius
                + geometry.selectedNodeRingDipWidth / 2
            handle.ringWidth = geometry.selectedNodeRingDipWidth / devicePixelRatio
            handle.fillColor = isSelected || !dimUnselected ? trackColor : palette.outline
            handle.stemColor = isSelected ? palette.selectionRing : stemColor
            handle.ringColor = palette.selectionRing
            handle.outlineColor = palette.noteBorder
            handle.primitiveName = "velocityNode"
            result.append(handle)
        }
        return result
    }

    private func yForNote(map: VelocityMap, velocity: Int, detentUnlock: Bool) -> Double {
        if detentUnlock { return axis.velocityToY(velocity) }
        guard let level = map.level(of: velocity) else { return axis.velocityToY(velocity) }
        return axis.levelToY(level)
    }

    private func hitTest(x: Double, y: Double, includeStems: Bool) -> NoteID? {
        let radius = geometry.hitRadius
        var best: NoteID?
        var bestCircle = false
        var bestSelected = false
        var bestDistance = 0.0
        var bestOrder = 0
        var order = 0
        for handle in publishedHandles {
            let dx = handle.x - x
            let dy = handle.y - y
            let distance = dx * dx + dy * dy
            let circleHit = distance <= radius * radius
            let stemHit = includeStems
                && x >= handle.x - geometry.durationLineHorizontalSlop
                && x <= handle.endX + geometry.durationLineHorizontalSlop
                && abs(y - handle.y) <= geometry.durationLineVerticalRadius
            if circleHit || stemHit {
                let better = best == nil
                    || (circleHit && !bestCircle)
                    || (circleHit == bestCircle && handle.selected && !bestSelected)
                    || (circleHit == bestCircle && handle.selected == bestSelected
                        && (distance < bestDistance
                            || (distance == bestDistance && order > bestOrder)))
                if better, let id = noteID(fromText: handle.noteIdText) {
                    best = id
                    bestCircle = circleHit
                    bestSelected = handle.selected
                    bestDistance = distance
                    bestOrder = order
                }
            }
            order += 1
        }
        return best
    }

    // MARK: Publication

    /// Publishes one handle projection. The page's own array is the authoritative
    /// copy the hit tests and the checks read, so it moves with the model.
    private func publishHandles(_ values: [VelocityHandle]) {
        publishedHandles = values
        let common = min(handles.count, values.count)
        for index in 0..<common where !handles[index].matches(values[index]) {
            handles[index] = values[index]
        }
        if handles.count != values.count {
            handles.replaceSubrange(common..<handles.count, with: values[common...])
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
        for index in 0..<common where !matchesText(model[index], texts[index]) {
            model[index] = texts[index]
        }
        if model.count != texts.count {
            model.replaceSubrange(common..<model.count, with: texts[common...])
        }
    }

    /// `SceneText` publishes no comparison of its own; an equal record leaves
    /// its row untouched. The font map is compared through its published
    /// spelling, because its values are variant-typed.
    private func matchesText(_ lhs: SceneText, _ rhs: SceneText) -> Bool {
        lhs.labelText == rhs.labelText && lhs.labelColor == rhs.labelColor
            && lhs.labelBackground == rhs.labelBackground
            && lhs.labelHorizontalAlignment == rhs.labelHorizontalAlignment
            && lhs.labelVerticalAlignment == rhs.labelVerticalAlignment
            && Self.rectMatches(lhs.labelRect, rhs.labelRect)
            && Self.fontMatches(lhs.labelFont, rhs.labelFont)
    }

    private static func rectMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: [String: QVariantSettable]) -> Bool {
        for key in ["x", "y", "width", "height"] {
            guard let left = lhs[key] as? Double, let right = rhs[key] as? Double,
                  left == right
            else { return false }
        }
        return true
    }

    private static func fontMatches(_ lhs: [String: QVariantSettable],
                                    _ rhs: [String: QVariantSettable]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (key, value) in lhs {
            guard let other = rhs[key], String(describing: value) == String(describing: other)
            else { return false }
        }
        return true
    }

    private func publishAxis() {
        let relativeGesture = (gesture?.relativeActivated ?? false)
            || publishedHandles.filter(\.selected).count > 1 || hovered != nil
        let separatorX = max(0, rulerWidth - geometry.pixel)
        let labelLeft = geometry.labelSideInset
        let labelRight = max(labelLeft, separatorX - geometry.labelSideInset)
        let labelWidth = max(0, labelRight - labelLeft)
        let labelHeight = max(0, axis.geometry.labelHeight)
        let labelColor = palette.primaryText
        let selectedColor = palette.selectionRing
        var ticks: [SceneRect] = []
        var graduations: [SceneRect] = []
        var markers: [SceneRect] = []
        var labels: [SceneText] = []
        if axis.mode == .intrinsic && detentsEnabled {
            for graduation in axis.graduations {
                let width = graduation.active ? 1.5 : geometry.pixel
                graduations.append(SceneRect(
                    x: separatorX - geometry.tickLabelLength, y: graduation.y - width / 2,
                    width: geometry.tickLabelLength, height: width,
                    fillColor: graduation.active ? selectedColor : labelColor,
                    primitiveName: "velocityGraduation"))
                let emphasized = graduation.active
                    && (relativeGesture || !graduation.labelVisible)
                guard (!relativeGesture && graduation.labelVisible) || emphasized else {
                    continue
                }
                labels.append(SceneText(
                    rect: (labelLeft, graduation.y - labelHeight / 2, labelWidth, labelHeight),
                    text: graduation.text, color: labelColor,
                    font: fontMap(emphasized: emphasized)))
            }
        } else {
            for tick in axis.ticks {
                let length = axis.hasLabel(tick.velocity) ? geometry.tickLabelLength
                                                          : geometry.tickShortLength
                ticks.append(SceneRect(
                    x: separatorX - length, y: tick.y - geometry.pixel / 2, width: length,
                    height: geometry.pixel, fillColor: labelColor,
                    primitiveName: "velocityTick"))
            }
            if !relativeGesture {
                for label in axis.labels {
                    labels.append(SceneText(
                        rect: (labelLeft, label.y - labelHeight / 2, labelWidth, labelHeight),
                        text: label.text, color: labelColor,
                        font: fontMap(emphasized: false)))
                }
            }
            for marker in axis.markers {
                markers.append(SceneRect(
                    x: separatorX - geometry.markerLength, y: marker.y - 0.75,
                    width: geometry.markerLength, height: 1.5, fillColor: selectedColor,
                    primitiveName: "velocityMarker"))
                guard relativeGesture else { continue }
                labels.append(SceneText(
                    rect: (labelLeft, marker.y - labelHeight / 2, labelWidth, labelHeight),
                    text: "\(marker.velocity)", color: labelColor,
                    font: fontMap(emphasized: true)))
            }
        }
        syncRects(axisTicks, ticks)
        syncRects(axisGraduations, graduations)
        syncRects(axisMarkers, markers)
        syncTexts(axisLabels, labels)
    }

    private func fontMap(emphasized: Bool) -> [String: QVariantSettable] {
        guard let typography else {
            return ["family": "Atkinson Hyperlegible Next",
                    "pixelSize": Int(baseFontPx),
                    "weight": emphasized ? 600 : 400,
                    "letterSpacing": 0.0]
        }
        return typography.fontMap(emphasized ? .bold : .keyLabel)
    }

    private var typography: GridTypography? {
        guard let session else { return nil }
        let key = TypographyKey(baseFontPx: baseFontPx, devicePixelRatio: devicePixelRatio,
                               rowHeight: session.camera.snapshot.keyHeight)
        if let typographyCache, typographyCache.key == key { return typographyCache.value }
        let value = GridTypography(fonts: GridTypography.fonts(metrics: gridMetrics(session)),
                                   rowHeight: key.rowHeight)
        typographyCache = (key, value)
        return value
    }

    private func gridMetrics(_ session: DocumentSession) -> GridMetrics {
        GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio, width: plotWidth,
                    height: plotHeight, timeAxis: timeAxis(session))
    }

    /// The roll's own time axis, built from the same document facts the grid
    /// uses, so the velocity band's grid is the roll's grid.
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

    /// The vertical grid over the visible plot: `composeBandedGrid`'s
    /// subdivisions plus the beat, fine-beat and bar lines.
    private func publishGrid() {
        guard let session, plotHeight > 0, plotWidth > rulerWidth else {
            syncRects(gridLines, [])
            return
        }
        let camera = session.camera
        let metrics = gridMetrics(session)
        let physicalPixel = max(geometry.pixel, 0.0001)
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
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: devicePixelRatio)
            let color = level == 1 ? palette.gridLineSub1
                : level == 2 ? palette.gridLineSub2 : palette.gridLineSub3
            rects.append(SceneRect(x: x - stroke / 2, y: 0, width: stroke, height: plotHeight,
                                   fillColor: color, primitiveName: "velocityGrid"))
        }
        var segment = metrics.timeAxis.segmentAt(range.begin)
        var finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
            }
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: devicePixelRatio)
            rects.append(SceneRect(
                x: x - stroke / 2, y: 0, width: stroke, height: plotHeight,
                fillColor: isBar ? palette.gridLineBar
                    : finest ? palette.gridLineBeatFine : palette.gridLineBeat,
                primitiveName: "velocityGrid"))
        }
        syncRects(gridLines, rects)
    }

    /// PSG level bands: one horizontal boundary per level inside each voice
    /// context section whose map resolves exactly to a PSG voice. A section
    /// whose map is unknown draws no level line rather than a guessed layout.
    private func publishBands() {
        guard let session, plotHeight > 0, plotWidth > rulerWidth else {
            syncRects(psgBands, [])
            return
        }
        let camera = session.camera
        let color = palette.separator
        let first = Tick(max(0, camera.tickAtContentX(0).rounded(.down)))
        let last = max(Tick(first + 1), Tick(camera.tickAtContentX(plotWidth).rounded(.up)))
        var sectionTick = first
        var rects: [SceneRect] = []
        var guardCounter = 0
        while sectionTick < last, guardCounter < 4096 {
            guardCounter += 1
            let context = resolvedContext(at: sectionTick)
            let sectionEnd = min(last, context.endTick ?? last)
            if sectionEnd <= sectionTick { break }
            if context.status == .resolved, context.map.isPSG, context.map.levelCount > 1 {
                let left = min(max(xForDisplayTick(Double(sectionTick)), 0), plotWidth)
                let right = min(max(xForDisplayTick(Double(sectionEnd)), 0), plotWidth)
                if right > left {
                    let sectionAxis = VelocityAxisModel(map: context.map, geometry: axis.geometry)
                    for level in 0..<(context.map.levelCount - 1) {
                        let y = sectionAxis.levelBoundaryToY(level)
                        rects.append(SceneRect(
                            x: left, y: y - geometry.pixel / 2, width: right - left,
                            height: geometry.pixel, fillColor: color,
                            primitiveName: "velocityBand"))
                    }
                }
            }
            sectionTick = sectionEnd
        }
        syncRects(psgBands, rects)
    }

    /// The gesture's transient rendering: the ramp line and the band reticle.
    private func publishTransient() {
        var rects: [SceneRect] = []
        setPublished(&rampVisible, false)
        setPublished(&rampLength, 0)
        setPublished(&rampSlopeY, 0)
        if let gesture {
            switch gesture.kind {
            case .ramp:
                let dx = gesture.previousX - gesture.pressX
                let dy = gesture.previousY - gesture.pressY
                setPublished(&rampX0, gesture.pressX)
                setPublished(&rampY0, gesture.pressY)
                setPublished(&rampLength, (dx * dx + dy * dy).squareRoot())
                setPublished(&rampSlopeY, dy)
                setPublished(&rampColor, palette.primaryText)
                setPublished(&rampVisible, rampLength > 0)
            case .band, .pendingBand:
                let minX = min(gesture.pressX, gesture.bandX)
                let maxX = max(gesture.pressX, gesture.bandX)
                let minY = min(gesture.pressY, gesture.bandY)
                let maxY = max(gesture.pressY, gesture.bandY)
                rects.append(SceneRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY,
                                       fillColor: palette.selectionFill,
                                       primitiveName: "velocityBandFill"))
                let dash = 4 * geometry.pixel
                let gap = 2 * geometry.pixel
                appendDashed(&rects, horizontal: true, fixed: minY, from: minX, to: maxX,
                             dash: dash, gap: gap)
                appendDashed(&rects, horizontal: true, fixed: maxY, from: minX, to: maxX,
                             dash: dash, gap: gap)
                appendDashed(&rects, horizontal: false, fixed: minX, from: minY, to: maxY,
                             dash: dash, gap: gap)
                appendDashed(&rects, horizontal: false, fixed: maxX, from: minY, to: maxY,
                             dash: dash, gap: gap)
            case .relative, .paint, .pan:
                break
            }
        }
        syncRects(transientRects, rects)
        publishReadout()
    }

    private func appendDashed(_ rects: inout [SceneRect], horizontal: Bool, fixed: Double,
                              from: Double, to: Double, dash: Double, gap: Double) {
        let period = dash + gap
        guard period > 0, to > from else { return }
        var position = from
        while position < to {
            let end = min(position + dash, to)
            if horizontal {
                rects.append(SceneRect(x: position, y: fixed - geometry.pixel / 2,
                                       width: end - position, height: geometry.pixel,
                                       fillColor: palette.selectionEdge,
                                       primitiveName: "velocityBandEdge"))
            } else {
                rects.append(SceneRect(x: fixed - geometry.pixel / 2, y: position,
                                       width: geometry.pixel, height: end - position,
                                       fillColor: palette.selectionEdge,
                                       primitiveName: "velocityBandEdge"))
            }
            position += period
        }
    }

    /// The readout: the hovered or dragged value plus the selection count. An
    /// unchanged publication writes nothing.
    private func publishReadout() {
        var text = ""
        var visible = false
        var x = 0.0
        var y = 0.0
        if let hovered, let handle = publishedHandles.first(where: {
            $0.noteIdText == velocityNoteText(hovered)
        }) {
            text = handle.label
            visible = true
            x = handle.x
            y = handle.y
        } else if let gesture, let first = gesture.notes.first {
            let handle = publishedHandles.first { $0.noteIdText == velocityNoteText(first.noteID) }
            let preview = gesture.preview[first.noteID].map(Int.init) ?? Int(first.velocity)
            text = handle?.label ?? "\(preview)"
            visible = true
            x = handle?.x ?? 0
            y = handle?.y ?? 0
        }
        setPublished(&readoutText, text)
        setPublished(&readoutVisible, visible)
        setPublished(&readoutX, x)
        setPublished(&readoutY, y)
        setPublished(&selectedCount, publishedHandles.filter(\.selected).count)
        setPublished(&hoveredNoteText, hovered.map(velocityNoteText) ?? "")
    }

    /// Writes one published primitive only when it really changed, so a
    /// repeated equal publication emits nothing.
    private func setPublished<Value: Equatable>(_ storage: inout Value, _ value: Value) {
        if storage != value { storage = value }
    }
}

// MARK: - Note identity text

/// The bridge-side spelling of a token, and the spelling published handles
/// carry. `NoteID` is not a bridge type, so identity crosses as decimal text.
func velocityNoteText(_ id: NoteID) -> String { "\(id.rawValue)" }

/// Parses a published handle's identity back into a `NoteID`.
func noteID(fromText text: String) -> NoteID? {
    guard let value = UInt64(text) else { return nil }
    return NoteID(value)
}
