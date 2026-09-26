import PorydawCore

// Scene build vocabulary for the drawer's Velocity section: the frozen
// interaction snapshot, the context source, the palette and input values one
// build reads, the snapshot and scoped axis-and-handles values it produces,
// and the note handle-row construction both builds share. The pure
// scene-value helpers the builds call live in VelocitySceneValues.swift.
//
// Ownership: values in, values out. The scene never retains a
// `DocumentSession`, never reads gesture or hover state except through the
// `VelocityInteractionSnapshot` its input carries, holds no cache, and never
// publishes anything: the page owns every model, reuse cache and apply path,
// and hands the document facts in.

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

    init(frozenNotes: [VelocityFrozenNote] = [], preview: [NoteID: UInt8] = [:],
         detentUnlock: Bool = false, relativeActivated: Bool = false, hovered: NoteID? = nil,
         detentsEnabled: Bool = true) {
        self.frozenNotes = frozenNotes
        self.preview = preview
        self.detentUnlock = detentUnlock
        self.relativeActivated = relativeActivated
        self.hovered = hovered
        self.detentsEnabled = detentsEnabled
        frozenIndices = Dictionary(uniqueKeysWithValues:
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
            VelocityContextPolicy.resolve(firstProgram: firstProgram, tick: tick,
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

/// The page's palette colours as values: the scene draws with these strings and
/// never reads the palette owner.
struct VelocityScenePalette: Sendable {
    var gridLineSub1: String = ""
    var gridLineSub2: String = ""
    var gridLineSub3: String = ""
    var gridLineBar: String = ""
    var gridLineBeat: String = ""
    var gridLineBeatFine: String = ""
    var separator: String = ""
    var primaryText: String = ""
    var selectionRing: String = ""
    var outline: String = ""
    var noteBorder: String = ""
}

/// Everything one static scene build reads: the document facts, the page's
/// frozen interaction snapshot, the drawn geometry, the palette colours as
/// values, and the page's reuse decision for handle rows.
struct VelocitySceneInput: Sendable {
    /// The shared camera at the page's device pixel ratio, or `nil` while the
    /// page has no session: camera-derived rows are then empty and x reads zero.
    var camera: EditorCamera?
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
    /// The page's cached grid metrics; the scene owns no cache of its own.
    var metrics: GridMetrics?
    var palette: VelocityScenePalette
    /// The page's handle-reuse decision.
    var reuseGeometry: Bool
}

// MARK: - Scene snapshot

/// The ruler's drawn rows and labels for one axis and interaction state.
struct VelocityAxisRows {
    var ticks: [SceneRect] = []
    var graduations: [SceneRect] = []
    var markers: [SceneRect] = []
    var labels: [SceneText] = []
}

/// The values one static scene build produces. Rows are `@MainActor` scene
/// primitives the page applies to its own models; the page keeps every cache
/// and every publish path.
struct VelocitySceneSnapshot {
    let axis: VelocityAxisModel
    let handles: [VelocityHandle]
    let axisTicks: [SceneRect]
    let axisGraduations: [SceneRect]
    let axisMarkers: [SceneRect]
    let axisLabels: [SceneText]
    let grid: [SceneRect]
    let bands: [SceneRect]

    /// The full static build: the value axis for the presented context, the note
    /// handle rows, the ruler rows and labels, the time grid and the PSG bands.
    @MainActor
    static func build(_ input: VelocitySceneInput,
                      previousHandles: [NoteID: VelocityHandle]) -> Self {
        let parts = axisAndHandles(input, previousHandles: previousHandles)
        return Self(
            axis: parts.axis,
            handles: parts.handles,
            axisTicks: parts.rows.ticks,
            axisGraduations: parts.rows.graduations,
            axisMarkers: parts.rows.markers,
            axisLabels: parts.rows.labels,
            grid: VelocityScene.grid(input),
            bands: VelocityScene.bands(input, axis: parts.axis, projection: parts.projection))
    }

    /// The scoped build a hover, a pointer exit or a detent change republishes:
    /// the same axis, handle rows and ruler rows a full build derives, without
    /// the grid subdivision walk or the PSG band walk a content rebuild performs.
    @MainActor
    static func buildAxisAndHandles(_ input: VelocitySceneInput,
                                    previousHandles: [NoteID: VelocityHandle])
        -> VelocityAxisAndHandles {
        let parts = axisAndHandles(input, previousHandles: previousHandles)
        return VelocityAxisAndHandles(axis: parts.axis, handles: parts.handles, rows: parts.rows)
    }

    /// The values both builds share: the value axis, the projection the rows are
    /// drawn against, the note handle rows and the ruler rows one interaction
    /// state produces.
    @MainActor
    private static func axisAndHandles(_ input: VelocitySceneInput,
                                       previousHandles: [NoteID: VelocityHandle])
        -> (axis: VelocityAxisModel, projection: VelocityProjection, handles: [VelocityHandle],
            rows: VelocityAxisRows) {
        let axis = VelocityScene.axisModel(input)
        let projection = VelocityProjection(camera: input.camera, geometry: input.geometry,
                                            devicePixelRatio: input.devicePixelRatio, axis: axis)
        let handles = handleRows(input, axis: axis, projection: projection,
                                 previousHandles: previousHandles)
        let relativeGesture = input.interaction.relativeActivated
            || handles.filter(\.selected).count > 1 || input.interaction.hovered != nil
        let rows = VelocityScene.axisRows(input, axis: axis, relativeGesture: relativeGesture)
        return (axis, projection, handles, rows)
    }

    /// The scoped build a live gesture uses: motion changes only the frozen
    /// preview and hover facts, so the axis, ruler rows, grid and bands stay as
    /// published and only the handle rows are rebuilt. `axis` is the page's
    /// published value axis.
    @MainActor
    static func buildHandleRows(_ input: VelocitySceneInput, axis: VelocityAxisModel,
                                previousHandles: [NoteID: VelocityHandle]) -> [VelocityHandle] {
        handleRows(input, axis: axis, projection: VelocityProjection(
            camera: input.camera, geometry: input.geometry,
            devicePixelRatio: input.devicePixelRatio, axis: axis),
            previousHandles: previousHandles)
    }

    /// The note handle rows one projection produces: stable identity, plot
    /// geometry, displayed value and state, with unchanged handles reused in
    /// place so an unchanged row emits nothing. `previousHandles` is the page's
    /// `@MainActor` lookup of the rows it published last.
    @MainActor
    private static func handleRows(_ input: VelocitySceneInput, axis: VelocityAxisModel,
                                   projection: VelocityProjection,
                                   previousHandles: [NoteID: VelocityHandle]) -> [VelocityHandle] {
        let selected = input.selectedNoteIDs
        let notes = input.notes
        let trackColor = PaletteMath.trackIdentityFills[PaletteMath.trackIdentityIndex(input.track)]
        let trackChannels = PaletteMath.channels(trackColor)
        let stemColor = PaletteMath.hex(
            PaletteMath.mixTowardOklab(
                PaletteMath.oklab(r: trackChannels.r, g: trackChannels.g, b: trackChannels.b),
                PaletteMath.oklab(r: 0, g: 0, b: 0), 1.0 / 3.0))
        let selectedCount = notes.filter { selected.contains($0.id) }.count
        let dimUnselected = selectedCount > 1
        let resolve = input.source.resolver()
        var result: [VelocityHandle] = []
        result.reserveCapacity(notes.count)
        for note in notes {
            let frozen = input.interaction.frozenNote(note.id)
            let map = frozen?.map ?? resolve(note.tick, Int(note.pitch)).map
            let previewValue = input.interaction.preview[note.id]
            let displayed = previewValue.map(Int.init) ?? Int(note.velocity)
            let isSelected = selected.contains(note.id)
            let isHovered = input.interaction.hovered == note.id
            let x = projection.xForDisplayTick(Double(note.tick))
            let endTick = Double(note.tick) + Double(note.duration)
            let endX = projection.xForDisplayTick(endTick)
            let y = projection.yForNote(
                map: map, velocity: displayed,
                detentUnlock: !input.interaction.detentsEnabled || input.interaction.detentUnlock)
            let level = map.level(of: displayed) ?? -1
            let previous = previousHandles[note.id]
            if input.reuseGeometry, let previous,
               previous.tick == Double(note.tick), previous.endTick == endTick,
               previous.x == x, previous.endX == endX, previous.y == y,
               previous.value == displayed, previous.level == level,
               previous.selected == isSelected, previous.hovered == isHovered,
               previous.preview == (previewValue != nil),
               previous.dimmed == (dimUnselected && !isSelected) {
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
                handle.label = axis.mode == .intrinsic && level >= 0
                    ? "Vol \(level + 1)" : "\(displayed)"
            }
            handle.hitRadius = input.geometry.hitRadius
            handle.stemWidth = (isSelected ? input.geometry.selectedStemDipWidth
                                           : input.geometry.stemDipWidth) / input.devicePixelRatio
            handle.nodeRadius = input.geometry.nodePaintRadius
            handle.outlineRadius = input.geometry.nodePaintRadius
                + input.geometry.nodeOutlineDipWidth / 2
            handle.outlineWidth = input.geometry.nodeOutlineDipWidth / input.devicePixelRatio
            handle.ringRadius = input.geometry.selectedNodeRingRadius
                + input.geometry.selectedNodeRingDipWidth / 2
            handle.ringWidth = input.geometry.selectedNodeRingDipWidth / input.devicePixelRatio
            handle.fillColor = isSelected || !dimUnselected ? trackColor : input.palette.outline
            handle.stemColor = isSelected ? input.palette.selectionRing : stemColor
            handle.ringColor = input.palette.selectionRing
            handle.outlineColor = input.palette.noteBorder
            handle.primitiveName = "velocityNode"
            result.append(handle)
        }
        return result
    }
}

/// The axis, the note handle rows and the ruler rows one interaction state
/// produces: the half of a build a hover, a pointer exit or a detent change
/// republishes. Those interactions never change the time grid or the PSG bands,
/// so the scoped build never walks them.
struct VelocityAxisAndHandles {
    let axis: VelocityAxisModel
    let handles: [VelocityHandle]
    let rows: VelocityAxisRows

    /// The scoped view of a full build: the same axis, handle and ruler values,
    /// without the grid and the bands that build also produced.
    init(_ snapshot: VelocitySceneSnapshot) {
        axis = snapshot.axis
        handles = snapshot.handles
        rows = VelocityAxisRows(ticks: snapshot.axisTicks, graduations: snapshot.axisGraduations,
                                markers: snapshot.axisMarkers, labels: snapshot.axisLabels)
    }

    init(axis: VelocityAxisModel, handles: [VelocityHandle], rows: VelocityAxisRows) {
        self.axis = axis
        self.handles = handles
        self.rows = rows
    }
}
