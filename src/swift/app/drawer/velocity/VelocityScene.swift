import PorydawCore
import QtBridge

// Static content computation for the drawer's Velocity section: the presented
// voice context's value axis, the note handle rows, the ruler rows and labels,
// the time grid and the PSG level bands.
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
/// values, and the page's reuse decision for the handle rows. The page's label
/// typography and its previous handle rows are `@MainActor` objects and travel
/// as explicit build parameters, so this input stays a plain Sendable value.
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
    /// `typography` and `previousHandles` are the page's `@MainActor` objects,
    /// which is why they are parameters here and not input fields.
    @MainActor
    static func build(_ input: VelocitySceneInput, typography: GridTypography?,
                      previousHandles: [NoteID: VelocityHandle]) -> Self {
        let parts = axisAndHandles(input, typography: typography, previousHandles: previousHandles)
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
    static func buildAxisAndHandles(_ input: VelocitySceneInput, typography: GridTypography?,
                                    previousHandles: [NoteID: VelocityHandle])
        -> VelocityAxisAndHandles {
        let parts = axisAndHandles(input, typography: typography, previousHandles: previousHandles)
        return VelocityAxisAndHandles(axis: parts.axis, handles: parts.handles, rows: parts.rows)
    }

    /// The values both builds share: the value axis, the projection the rows are
    /// drawn against, the note handle rows and the ruler rows one interaction
    /// state produces.
    @MainActor
    private static func axisAndHandles(_ input: VelocitySceneInput, typography: GridTypography?,
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
        let rows = VelocityScene.axisRows(input, axis: axis, relativeGesture: relativeGesture,
                                          typography: typography)
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

// MARK: - Scene values

/// The velocity band's static value computation: the page's session reads, the
/// value axis and its rows, the grid, the PSG bands and the small shared value
/// helpers. Every entry is pure over its arguments; nothing here retains page
/// or document state.
@MainActor
enum VelocityScene {
    /// The primary track's notes.
    static func trackNotes(_ session: DocumentSession?) -> [Note] {
        guard let session, let track = session.selectedTrack else { return [] }
        return session.projectionCache.notes(in: track)
    }

    /// The primary track's selected notes, in the session's insertion order.
    static func selectedTrackNotes(_ session: DocumentSession?) -> [Note] {
        guard let session, let track = session.selectedTrack else { return [] }
        return session.selectedNoteOrder.compactMap { session.projectionCache.note($0, in: track) }
    }

    /// The bank/timeline facts one build resolves voice contexts from.
    static func contextSource(_ session: DocumentSession?) -> VelocityContextSource {
        guard let session else { return .unresolved }
        let track = session.selectedTrack ?? -1
        guard track >= 0, track < session.timeline.tracks.count else { return .unresolved }
        return VelocityContextSource(
            firstProgram: session.timeline.tracks[track].firstProgram,
            voiceChanges: session.projectionCache.lanePoints(track: track, lane: .voice),
            slots: session.bankSlots)
    }

    /// The exact context at one tick, before any selection compatibility rule.
    static func contextResolver(_ session: DocumentSession?) -> (Tick, Int?) -> VelocityVoiceContext {
        contextSource(session).resolver()
    }

    /// The stable identity used to decide whether a context presentation changed.
    static func contextKey(_ session: DocumentSession?, at tick: Tick, playing: Bool)
        -> VelocityContextKey
    {
        contextSource(session).key(at: tick, playing: playing)
    }

    /// The context the ruler presents: the shared playhead's rounded tick while
    /// transport is playing, the edit cursor while stopped.
    static func effectiveContextTick(_ session: DocumentSession?, playing: Bool,
                                     contextTick: Tick) -> Tick {
        guard let session else { return 0 }
        return playing ? contextTick : session.editCursor
    }

    /// `VelocityArea::currentContext`: no selection resolves the context at the
    /// effective tick; a selection resolves per note, keeps an intrinsic map only
    /// when every selected note resolves to the same PSG voice, and falls back to
    /// the continuous domain when their maps disagree.
    static func presentation(_ session: DocumentSession?, playing: Bool,
                             contextTick: Tick) -> VelocityVoiceContext {
        VelocityContextPolicy.presentation(
            selectedNotes: selectedTrackNotes(session),
            effectiveTick: effectiveContextTick(session, playing: playing, contextTick: contextTick),
            resolve: contextResolver(session))
    }

    /// The shared grid metrics at one size.
    static func gridMetrics(baseFontPx: Double, devicePixelRatio: Double, width: Double,
                            height: Double, timeAxis: TimeAxis) -> GridMetrics {
        GridMetrics(baseFontPx: baseFontPx, dpr: devicePixelRatio, width: width, height: height,
                    timeAxis: timeAxis)
    }

    /// The roll's own time axis, built from the same document facts the grid
    /// uses, so the velocity band's grid is the roll's grid.
    static func timeAxis(_ session: DocumentSession) -> TimeAxis {
        session.projectionCache.timeAxis
    }

    /// The label typography the ruler draws with.
    static func typography(metrics: GridMetrics, rowHeight: Double) -> GridTypography {
        GridTypography(fonts: GridTypography.fonts(metrics: metrics), rowHeight: rowHeight)
    }

    /// The ruler label font: the page's typography, or the seed literal while
    /// the page has no session.
    static func fontMap(emphasized: Bool, typography: GridTypography?,
                        baseFontPx: Double) -> [String: QVariantSettable] {
        guard let typography else {
            return ["family": "Atkinson Hyperlegible Next",
                    "pixelSize": Int(baseFontPx),
                    "weight": emphasized ? 600 : 400,
                    "letterSpacing": 0.0]
        }
        return typography.fontMap(emphasized ? .bold : .keyLabel)
    }

    /// The value axis: the presented context's map, the active set's markers and
    /// the font-relative ruler geometry. A hovered note takes its own tick's map
    /// while the selection keeps its own.
    static func axisModel(_ input: VelocitySceneInput) -> VelocityAxisModel {
        var activeValues: [UInt8] = []
        var mapped = input.context.map
        if let hovered = input.interaction.hovered,
           let note = input.notes.first(where: { $0.id == hovered }) {
            activeValues.append(input.interaction.preview[note.id] ?? note.velocity)
            mapped = input.source.map(at: note.tick, key: Int(note.pitch))
        } else {
            for note in input.selectedNotes {
                activeValues.append(input.interaction.preview[note.id] ?? note.velocity)
            }
        }
        var axisGeometry = VelocityAxisGeometry()
        axisGeometry.height = input.plotHeight
        axisGeometry.verticalInset = input.geometry.verticalInset
        axisGeometry.labelWidth = max(0, input.rulerWidth - input.geometry.pixel)
        axisGeometry.labelSideInset = input.geometry.labelSideInset
        axisGeometry.labelColumnGap = input.geometry.labelColumnGap
        axisGeometry.labelHeight = max(input.geometry.densityD1, input.plotHeight / 8)
        axisGeometry.continuousDensityD1 = input.geometry.densityD1
        axisGeometry.continuousDensityD2 = input.geometry.densityD2
        axisGeometry.continuousDensityD3 = input.geometry.densityD3
        axisGeometry.continuousDensityD4 = input.geometry.densityD4
        return VelocityAxisModel(map: mapped, geometry: axisGeometry, activeValues: activeValues)
    }

    /// The ruler's rows and labels: the intrinsic graduations with their
    /// density-thinned labels, or the continuous ladder with its ticks, markers
    /// and active-value labels. The label column's own geometry is part of the
    /// value, exactly as `rebuildQuickAxis` derives it. `typography` is the
    /// page's `@MainActor` label typography, or `nil` while it has no session.
    static func axisRows(_ input: VelocitySceneInput, axis: VelocityAxisModel,
                         relativeGesture: Bool,
                         typography: GridTypography?) -> VelocityAxisRows {
        let separatorX = max(0, input.rulerWidth - input.geometry.pixel)
        // The ruler spans the whole gutter (track headers plus the keyboard
        // column); the label column keeps its keyboard-column width, anchored
        // to the separator the ticks draw against.
        let labelColumnWidth = fontPx(input.baseFontPx, 13.0 / 3.0) - input.geometry.pixel
        let labelRight = max(input.geometry.labelSideInset,
                             separatorX - input.geometry.labelSideInset)
        let labelLeft = max(input.geometry.labelSideInset, labelRight - labelColumnWidth)
        let labelWidth = max(0, labelRight - labelLeft)
        let labelHeight = max(0, axis.geometry.labelHeight)
        let labelColor = input.palette.primaryText
        let selectedColor = input.palette.selectionRing
        var rows = VelocityAxisRows()
        if axis.mode == .intrinsic && input.interaction.detentsEnabled {
            for graduation in axis.graduations {
                let width = graduation.active ? 1.5 : input.geometry.pixel
                rows.graduations.append(SceneRect(
                    x: separatorX - input.geometry.tickLabelLength, y: graduation.y - width / 2,
                    width: input.geometry.tickLabelLength, height: width,
                    fillColor: graduation.active ? selectedColor : labelColor,
                    primitiveName: "velocityGraduation"))
                let emphasized = graduation.active
                    && (relativeGesture || !graduation.labelVisible)
                guard (!relativeGesture && graduation.labelVisible) || emphasized else {
                    continue
                }
                rows.labels.append(SceneText(
                    rect: (labelLeft, graduation.y - labelHeight / 2, labelWidth, labelHeight),
                    text: graduation.text, color: labelColor,
                    font: fontMap(emphasized: emphasized, typography: typography,
                                  baseFontPx: input.baseFontPx), horizontal: 0x2))
            }
        } else {
            for tick in axis.ticks {
                let length = axis.hasLabel(tick.velocity) ? input.geometry.tickLabelLength
                                                          : input.geometry.tickShortLength
                rows.ticks.append(SceneRect(
                    x: separatorX - length, y: tick.y - input.geometry.pixel / 2, width: length,
                    height: input.geometry.pixel, fillColor: labelColor,
                    primitiveName: "velocityTick"))
            }
            if !relativeGesture {
                for label in axis.labels {
                    rows.labels.append(SceneText(
                        rect: (labelLeft, label.y - labelHeight / 2, labelWidth, labelHeight),
                        text: label.text, color: labelColor,
                        font: fontMap(emphasized: false, typography: typography,
                                      baseFontPx: input.baseFontPx), horizontal: 0x2))
                }
            }
            for marker in axis.markers {
                rows.markers.append(SceneRect(
                    x: separatorX - input.geometry.markerLength, y: marker.y - 0.75,
                    width: input.geometry.markerLength, height: 1.5, fillColor: selectedColor,
                    primitiveName: "velocityMarker"))
                guard relativeGesture else { continue }
                rows.labels.append(SceneText(
                    rect: (labelLeft, marker.y - labelHeight / 2, labelWidth, labelHeight),
                    text: "\(marker.velocity)", color: labelColor,
                    font: fontMap(emphasized: true, typography: typography,
                                  baseFontPx: input.baseFontPx), horizontal: 0x2))
            }
        }
        return rows
    }

    /// The vertical grid over the visible plot: `composeBandedGrid`'s
    /// subdivisions plus the beat, fine-beat and bar lines.
    static func grid(_ input: VelocitySceneInput) -> [SceneRect] {
        guard let camera = input.camera, let metrics = input.metrics,
              input.plotHeight > 0, input.plotWidth > input.rulerWidth else { return [] }
        let physicalPixel = max(input.geometry.pixel, 0.0001)
        let roundingMargin = physicalPixel / 2
        let beginTick = camera.tickAtContentX(-roundingMargin)
        let endTick = camera.tickAtContentX(input.plotWidth - physicalPixel + roundingMargin) + 1
        guard endTick > beginTick else { return [] }
        let range = (begin: Tick(max(0, beginTick.rounded(.down))),
                     end: Tick(max(1, endTick.rounded(.up))))
        let stroke = metrics.gridLineStroke
        var rects: [SceneRect] = []
        metrics.forEachSubdivision(from: range.begin, to: range.end, camera: camera) { tick, level in
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: input.devicePixelRatio)
            let color = level == 1 ? input.palette.gridLineSub1
                : level == 2 ? input.palette.gridLineSub2 : input.palette.gridLineSub3
            rects.append(SceneRect(x: x - stroke / 2, y: 0, width: stroke,
                                   height: input.plotHeight, fillColor: color,
                                   primitiveName: "velocityGrid"))
        }
        var segment = metrics.timeAxis.segmentAt(range.begin)
        var finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
        metrics.timeAxis.forEachGridLine(from: range.begin, to: range.end) { tick, isBar, _, _ in
            if tick >= segment.next {
                segment = metrics.timeAxis.segmentAt(tick)
                finest = metrics.visibleGridTicks(in: segment, camera: camera) == 1
            }
            let x = camera.displayX(tick: Double(tick), origin: 0, dpr: input.devicePixelRatio)
            rects.append(SceneRect(
                x: x - stroke / 2, y: 0, width: stroke, height: input.plotHeight,
                fillColor: isBar ? input.palette.gridLineBar
                    : finest ? input.palette.gridLineBeatFine : input.palette.gridLineBeat,
                primitiveName: "velocityGrid"))
        }
        return rects
    }

    /// PSG level bands: one horizontal boundary per level inside each voice
    /// context section whose map resolves exactly to a PSG voice. A section
    /// whose map is unknown draws no level line rather than a guessed layout.
    static func bands(_ input: VelocitySceneInput, axis: VelocityAxisModel,
                      projection: VelocityProjection) -> [SceneRect] {
        guard let camera = input.camera, input.plotHeight > 0,
              input.plotWidth > input.rulerWidth else { return [] }
        let color = input.palette.separator
        let first = Tick(max(0, camera.tickAtContentX(0).rounded(.down)))
        let last = max(Tick(first + 1), Tick(camera.tickAtContentX(input.plotWidth).rounded(.up)))
        var sectionTick = first
        var rects: [SceneRect] = []
        var guardCounter = 0
        let resolve = input.source.resolver()
        while sectionTick < last, guardCounter < 4096 {
            guardCounter += 1
            let context = resolve(sectionTick, nil)
            let sectionEnd = min(last, context.endTick ?? last)
            if sectionEnd <= sectionTick { break }
            if context.status == .resolved, context.map.isPSG, context.map.levelCount > 1 {
                let left = min(max(projection.xForDisplayTick(Double(sectionTick)), 0),
                               input.plotWidth)
                let right = min(max(projection.xForDisplayTick(Double(sectionEnd)), 0),
                                input.plotWidth)
                if right > left {
                    let sectionMap = context.map
                    for level in 0..<(context.map.levelCount - 1) {
                        let y = axis.levelBoundaryToY(level, map: sectionMap)
                        rects.append(SceneRect(
                            x: left, y: y - input.geometry.gridLineStroke / 2,
                            width: right - left, height: input.geometry.gridLineStroke,
                            fillColor: color, primitiveName: "velocityBand"))
                    }
                }
            }
            sectionTick = sectionEnd
        }
        return rects
    }

    /// One dashed band edge of the gesture transient. The page supplies the
    /// physical pixel and edge colour the reticle draws with.
    static func appendDashed(_ rects: inout [SceneRect], horizontal: Bool, fixed: Double,
                             from: Double, to: Double, dash: Double, gap: Double,
                             physicalPixel: Double, color: String) {
        let period = dash + gap
        guard period > 0, to > from else { return }
        var position = from
        while position < to {
            let end = min(position + dash, to)
            if horizontal {
                rects.append(SceneRect(x: position, y: fixed - physicalPixel / 2,
                                       width: end - position, height: physicalPixel,
                                       fillColor: color, primitiveName: "velocityBandEdge"))
            } else {
                rects.append(SceneRect(x: fixed - physicalPixel / 2, y: position,
                                       width: physicalPixel, height: end - position,
                                       fillColor: color, primitiveName: "velocityBandEdge"))
            }
            position += period
        }
    }
}
