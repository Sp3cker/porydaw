import PorydawCore
import PorydawDocument
import QtBridge

// Pure build inputs and outputs; the page owns publication and reuse caches.

// MARK: - Interaction snapshot

/// The page's live gesture and hover facts, frozen for one build: the notes the
/// gesture captured, its previewed values, its detent-unlock and activation
/// flags, the hovered note and the detent preference. Sendable values only.
struct VelocityInteractionSnapshot: Sendable {
    var frozenNotes: [VelocityFrozenNote] = []
    var preview: [NoteID: UInt8] = [:]
    var detentUnlock: Bool = false
    var relativeActivated: Bool = false
    var hovered: NoteID?
    var detentsEnabled: Bool = true
    /// The frozen notes by identity, exactly the gesture's own lookup.
    private var frozenIndices: [NoteID: Int] = [:]

    init(
        frozenNotes: [VelocityFrozenNote] = [], preview: [NoteID: UInt8] = [:],
        detentUnlock: Bool = false, relativeActivated: Bool = false, hovered: NoteID? = nil,
        detentsEnabled: Bool = true
    ) {
        self.frozenNotes = frozenNotes
        self.preview = preview
        self.detentUnlock = detentUnlock
        self.relativeActivated = relativeActivated
        self.hovered = hovered
        self.detentsEnabled = detentsEnabled
        frozenIndices = Dictionary(
            uniqueKeysWithValues:
                frozenNotes.enumerated().map { ($0.element.noteID, $0.offset) })
    }

    /// One frozen note by identity.
    func frozenNote(_ id: NoteID) -> VelocityFrozenNote? {
        frozenIndices[id].map { frozenNotes[$0] }
    }
}

// MARK: - Context source

/// The bank/timeline facts one build resolves voice contexts from: the track's
/// first program, its voice-lane changes and the published bank slots. The page
/// reads them from its session; nothing here retains one.
struct VelocityContextSource: Sendable {
    var firstProgram: Int = -1
    var voiceChanges: [LanePoint] = []
    var slots: [BankSlotView] = []

    /// No track to resolve: every lookup answers the unresolved context.
    static let unresolved = Self()

    /// The exact context at one tick, before any selection compatibility rule.
    func resolver() -> (Tick, Int?) -> VelocityVoiceContext {
        let firstProgram = self.firstProgram
        let changes = voiceChanges
        let slots = self.slots
        return { tick, key in
            VelocityContextPolicy.resolve(
                firstProgram: firstProgram, tick: tick,
                voiceChanges: changes, slots: slots, key: key)
        }
    }

    /// The exact context at one tick.
    func context(at tick: Tick, key: Int? = nil) -> VelocityVoiceContext {
        resolver()(tick, key)
    }

    /// The exact map one note's own tick and key resolve to.
    func map(at tick: Tick, key: Int) -> VelocityMap {
        context(at: tick, key: key).map
    }

    /// The stable identity used to decide whether a context presentation changed.
    func key(at tick: Tick, playing: Bool) -> VelocityContextKey {
        VelocityContextKey(context: context(at: tick), playing: playing)
    }
}

// MARK: - Scene input

/// Palette colors copied into the scene's value inputs.
struct VelocityScenePalette: Sendable {
    var gridLineSub1: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var gridLineSub2: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var gridLineSub3: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var gridLineBar: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var gridLineBeat: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var gridLineBeatFine: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var separator: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var primaryText: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var selectionRing: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var outline: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var noteBorder: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
}

/// Everything one static scene build reads: the document facts, the page's
/// frozen interaction snapshot, the drawn geometry, the palette colours as
/// values, and the page's reuse decision for handle rows.
struct VelocitySceneInput: Sendable {
    /// The shared camera at the page's device pixel ratio, or `nil` while the
    /// page has no session: camera-derived rows are then empty and x reads zero.
    var camera: EditorCamera?
    /// The retained overscan window; live interaction notes bypass this range.
    var handleTickWindow: ClosedRange<Double>? = nil
    /// The presented voice context the page resolved for this build.
    var context: VelocityVoiceContext
    /// The primary track's notes, its selected notes in selection order, and the
    /// selection the handle flags read.
    var notes: [Note]
    var selectedNotes: [Note]
    var selectedNoteIDs: Set<NoteID>
    var track: Int
    /// The bank/timeline facts per-note and per-section resolution reads.
    var source: VelocityContextSource
    var interaction: VelocityInteractionSnapshot
    var geometry: VelocityNodeGeometry
    var plotWidth: Double
    var plotHeight: Double
    var rulerWidth: Double
    var devicePixelRatio: Double
    var baseFontPx: Double
    var typography: Typography
    /// The page's cached grid metrics; the scene owns no cache of its own.
    var metrics: GridMetrics?
    var grid: RollGrid? = nil
    var palette: VelocityScenePalette
    /// The page's handle-reuse decision.
    var reuseGeometry: Bool
}

// MARK: - Axis and handle build

/// The ruler's drawn rows and labels for one axis and interaction state.
struct VelocityAxisRows {
    var ticks: [SceneRectValue] = []
    var graduations: [SceneRectValue] = []
    var markers: [SceneRectValue] = []
    var labels: [SceneTextValue] = []
}

extension VelocityScene {
    /// The live-gesture build: only the handle rows, projected against the
    /// page's published `axis`; the ruler rows, grid and bands stay as published.
    static func handleRows(
        _ input: VelocitySceneInput, axis: VelocityAxisModel,
        previousHandles: [NoteID: VelocityHandle]
    ) -> [VelocityHandle] {
        projectedHandleRows(
            input, axis: axis,
            projection: VelocityProjection(
                camera: input.camera, geometry: input.geometry,
                devicePixelRatio: input.devicePixelRatio, axis: axis),
            previousHandles: previousHandles)
    }

    /// Note handle rows for one projection; unchanged handles are reused in
    /// place so an unchanged row emits nothing.
    private static func projectedHandleRows(
        _ input: VelocitySceneInput, axis: VelocityAxisModel, projection: VelocityProjection,
        previousHandles: [NoteID: VelocityHandle]
    ) -> [VelocityHandle] {
        let selected = input.selectedNoteIDs
        let notes = input.notes
        let trackColor = PaletteMath.trackIdentityColors[PaletteMath.trackIdentityIndex(input.track)]
        let stemColor = PaletteMath.velocityStemColors[PaletteMath.trackIdentityIndex(input.track)]
        let selectedCount = notes.reduce(0) { $0 + (selected.contains($1.id) ? 1 : 0) }
        let dimUnselected = selectedCount > 1
        let resolve = input.source.resolver()
        let candidates = notes.lazy.filter { note in
            guard let window = input.handleTickWindow else { return true }
            return
                (Double(note.tick) <= window.upperBound
                && Double(note.tick) + Double(note.duration) >= window.lowerBound)
                || input.interaction.frozenNote(note.id) != nil
                || input.interaction.hovered == note.id
                || input.interaction.preview[note.id] != nil
        }
        var result: [VelocityHandle] = []
        result.reserveCapacity(notes.count)
        for note in candidates {
            let frozen = input.interaction.frozenNote(note.id)
            let map = frozen?.map ?? resolve(note.tick, Int(note.pitch)).map
            let previewValue = input.interaction.preview[note.id]
            let displayed = previewValue.map(Int.init) ?? Int(note.velocity)
            let isSelected = selected.contains(note.id)
            let isHovered = input.interaction.hovered == note.id
            let x = projection.stableXForTick(Double(note.tick))
            let endTick = Double(note.tick) + Double(note.duration)
            let endX = projection.stableXForTick(endTick)
            let y = projection.yForNote(
                map: map, velocity: displayed,
                detentUnlock: !input.interaction.detentsEnabled || input.interaction.detentUnlock)
            let level = map.level(of: displayed) ?? -1
            let previous = previousHandles[note.id]
            if input.reuseGeometry, let previous,
                previous.tick == Double(note.tick), previous.endTick == endTick,
                previous.y == y, previous.value == displayed, previous.level == level,
                previous.selected == isSelected, previous.hovered == isHovered,
                previous.preview == (previewValue != nil),
                previous.dimmed == (dimUnselected && !isSelected)
            {
                previous.publish(\.x, x)
                previous.publish(\.endX, endX)
                result.append(previous)
                continue
            }
            let handle = VelocityHandle()
            handle.noteID = note.id
            handle.noteIdText = previous?.noteIdText ?? velocityNoteText(note.id)
            handle.tick = Double(note.tick)
            handle.endTick = endTick
            handle.x = x
            handle.endX = endX
            handle.value = displayed
            handle.y = y
            handle.selected = isSelected
            handle.hovered = isHovered
            handle.preview = previewValue != nil
            handle.dimmed = dimUnselected && !isSelected
            handle.level = level
            if input.reuseGeometry, let previous, previous.level == level, previous.value == displayed {
                handle.label = previous.label
            } else {
                handle.label =
                    axis.mode == .intrinsic && level >= 0
                    ? "Vol \(level + 1)" : "\(displayed)"
            }
            handle.hitRadius = input.geometry.hitRadius
            handle.stemWidth =
                (isSelected
                    ? input.geometry.selectedStemDipWidth
                    : input.geometry.stemDipWidth) / input.devicePixelRatio
            handle.nodeRadius = input.geometry.nodePaintRadius
            handle.outlineRadius =
                input.geometry.nodePaintRadius
                + input.geometry.nodeOutlineDipWidth / 2
            handle.outlineWidth = input.geometry.nodeOutlineDipWidth / input.devicePixelRatio
            handle.ringRadius =
                input.geometry.selectedNodeRingRadius
                + input.geometry.selectedNodeRingDipWidth / 2
            handle.ringWidth = input.geometry.selectedNodeRingDipWidth / input.devicePixelRatio
            handle.fillColor =
                isSelected || !dimUnselected ? trackColor : input.palette.outline
            handle.stemColor = isSelected ? input.palette.selectionRing : stemColor
            handle.ringColor = input.palette.selectionRing
            handle.outlineColor = input.palette.noteBorder
            handle.primitiveName = "velocityNode"
            result.append(handle)
        }
        return result
    }
}
