import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import QtBridge

// Pure build inputs and outputs; the page owns publication and reuse caches.

// MARK: - Interaction snapshot

/// The page's live gesture and hover facts, frozen for one build: the notes the
/// gesture captured, its previewed values, its detent-unlock and activation
/// flags, the hovered note and the detent preference. Sendable values only.
struct VelocityInteractionSnapshot: Sendable {
    var frozen = VelocityFrozenNotes()
    var preview: [NoteID: UInt8] = [:]
    var detentUnlock: Bool = false
    var relativeActivated: Bool = false
    var hovered: NoteID? = nil
    var detentsEnabled: Bool = true

    /// One frozen note by identity.
    func frozenNote(_ id: NoteID) -> VelocityFrozenNote? {
        frozen.frozenNote(id)
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
    var separator: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var primaryText: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
    var selectionRing: QmlColor = QmlColor(red: 0, green: 0, blue: 0)
}

/// Everything one static scene build reads: the document facts, the page's
/// frozen interaction snapshot, the drawn geometry and the palette colours.
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
    /// The bank/timeline facts per-note and per-section resolution reads.
    var source: VelocityContextSource
    var interaction: VelocityInteractionSnapshot
    var geometry: VelocityNodeGeometry
    var plotHeight: Double
    var rulerWidth: Double
    var devicePixelRatio: Double
    var baseFontPx: Double
    var typography: Typography
    var palette: VelocityScenePalette
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
        into result: inout [VelocityHandle]
    ) {
        projectedHandleRows(
            input,
            projection: VelocityProjection(
                camera: input.camera, geometry: input.geometry,
                devicePixelRatio: input.devicePixelRatio, axis: axis),
            into: &result)
    }

    /// Projects the current note facts into the retained overscan buffer.
    private static func projectedHandleRows(
        _ input: VelocitySceneInput, projection: VelocityProjection,
        into result: inout [VelocityHandle]
    ) {
        let selected = input.selectedNoteIDs
        let notes = input.notes
        let dimUnselected = input.selectedNotes.count > 1
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
        result.removeAll(keepingCapacity: true)
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
            var handle = VelocityHandle()
            handle.noteID = note.id
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
            result.append(handle)
        }
    }
}
