import PorydawCore

// MARK: - Context and scene input

/// Bank and timeline facts used to resolve a note's voice context.
struct VelocityContextSource: Sendable {
    var firstProgram: Int = -1
    var voiceChanges: [LanePoint] = []
    var slots: [BankSlotView] = []

    static let unresolved = Self()

    func resolver() -> (Tick, Int?) -> VelocityVoiceContext {
        let firstProgram = self.firstProgram
        let changes = voiceChanges
        let slots = self.slots
        return { tick, key in
            VelocityContextPolicy.resolve(firstProgram: firstProgram, tick: tick,
                                          voiceChanges: changes, slots: slots, key: key)
        }
    }

    func context(at tick: Tick, key: Int? = nil) -> VelocityVoiceContext {
        resolver()(tick, key)
    }

    func map(at tick: Tick, key: Int) -> VelocityMap {
        context(at: tick, key: key).map
    }
}

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
    var selectionFill: String = ""
    var selectionEdge: String = ""
    var outline: String = ""
    var noteBorder: String = ""
}

/// Every value consumed by a scene build. The gesture is used directly, so the
/// scene does not rebuild a second frozen-note index or mirror its payload.
struct VelocitySceneInput {
    var camera: EditorCamera?
    var context: VelocityVoiceContext
    var notes: [Note]
    var selectedNotes: [Note]
    var selectedNoteIDs: Set<NoteID>
    var track: Int
    var source: VelocityContextSource
    var gesture: VelocityGesture?
    var hovered: NoteID?
    var detentsEnabled: Bool
    var geometry: VelocityNodeGeometry
    var plotWidth: Double
    var plotHeight: Double
    var rulerWidth: Double
    var devicePixelRatio: Double
    var baseFontPx: Double
    var metrics: GridMetrics?
    var palette: VelocityScenePalette
}

// MARK: - Plain scene values

struct VelocityHandleValue: Equatable, Sendable {
    var noteID = NoteID(0)
    var noteIdText = ""
    var tick: Double = 0
    var endTick: Double = 0
    var x: Double = 0
    var endX: Double = 0
    var value = 1
    var y: Double = 0
    var selected = false
    var hovered = false
    var preview = false
    var dimmed = false
    var level = -1
    var label = ""
    var hitRadius: Double = 0
    var stemWidth: Double = 0
    var nodeRadius: Double = 0
    var outlineRadius: Double = 0
    var outlineWidth: Double = 0
    var ringRadius: Double = 0
    var ringWidth: Double = 0
    var fillColor = ""
    var stemColor = ""
    var ringColor = ""
    var outlineColor = ""
    var primitiveName = ""
}

struct VelocityAxisRows: Equatable, Sendable {
    var ticks: [DrawerRectValue] = []
    var graduations: [DrawerRectValue] = []
    var markers: [DrawerRectValue] = []
    var labels: [DrawerTextValue] = []
}

struct VelocityReadoutValue: Equatable, Sendable {
    var text = ""
    var visible = false
    var x: Double = 0
    var y: Double = 0
    var selectedCount = 0
    var hoveredNoteText = ""
}

struct VelocityRampValue: Equatable, Sendable {
    var visible = false
    var x0: Double = 0
    var y0: Double = 0
    var length: Double = 0
    var slopeY: Double = 0
    var color = ""
}

struct VelocityTransientValue: Equatable, Sendable {
    var rects: [DrawerRectValue] = []
    var ramp = VelocityRampValue()
}

/// The complete derived scene. It contains only Swift values: no bridge rows,
/// native typography owner, session, or variant dictionaries.
struct VelocityScene: Sendable {
    var geometry = VelocityNodeGeometry()
    var axis = VelocityAxisModel()
    var handles: [VelocityHandleValue] = []
    var axisRows = VelocityAxisRows()
    var grid: [DrawerRectValue] = []
    var bands: [DrawerRectValue] = []
    var transient = VelocityTransientValue()
    var readout = VelocityReadoutValue()

    static func build(_ input: VelocitySceneInput, textMetrics: DrawerTextMetrics?) -> Self {
        let parts = axisAndHandles(input, textMetrics: textMetrics)
        return Self(
            geometry: input.geometry,
            axis: parts.axis,
            handles: parts.handles,
            axisRows: parts.rows,
            grid: grid(input),
            bands: bands(input, axis: parts.axis, projection: parts.projection),
            transient: transient(input),
            readout: parts.readout)
    }

    static func buildAxisAndHandles(_ input: VelocitySceneInput,
                                    textMetrics: DrawerTextMetrics?) -> VelocityAxisAndHandles {
        let parts = axisAndHandles(input, textMetrics: textMetrics)
        return VelocityAxisAndHandles(axis: parts.axis, handles: parts.handles,
                                      rows: parts.rows, readout: parts.readout)
    }

    static func buildHandleRows(_ input: VelocitySceneInput,
                                axis: VelocityAxisModel) -> VelocityHandleRows {
        let handles = handleRows(
            input, axis: axis,
            projection: VelocityProjection(camera: input.camera, geometry: input.geometry,
                                           devicePixelRatio: input.devicePixelRatio, axis: axis))
        return VelocityHandleRows(handles: handles, readout: readout(input, handles: handles))
    }

    private static func axisAndHandles(_ input: VelocitySceneInput,
                                       textMetrics: DrawerTextMetrics?)
        -> (axis: VelocityAxisModel, projection: VelocityProjection,
            handles: [VelocityHandleValue], rows: VelocityAxisRows,
            readout: VelocityReadoutValue) {
        let axis = axisModel(input)
        let projection = VelocityProjection(camera: input.camera, geometry: input.geometry,
                                            devicePixelRatio: input.devicePixelRatio, axis: axis)
        let handles = handleRows(input, axis: axis, projection: projection)
        let relativeGesture = input.gesture?.relativeActivated == true
            || handles.lazy.filter(\.selected).count > 1 || input.hovered != nil
        let rows = axisRows(input, axis: axis, relativeGesture: relativeGesture,
                            textMetrics: textMetrics)
        return (axis, projection, handles, rows, readout(input, handles: handles))
    }

    private static func handleRows(_ input: VelocitySceneInput, axis: VelocityAxisModel,
                                   projection: VelocityProjection) -> [VelocityHandleValue] {
        let selected = input.selectedNoteIDs
        let trackColor = PaletteMath.trackIdentityFills[PaletteMath.trackIdentityIndex(input.track)]
        let trackChannels = PaletteMath.channels(trackColor)
        let stemColor = PaletteMath.hex(
            PaletteMath.mixTowardOklab(
                PaletteMath.oklab(r: trackChannels.r, g: trackChannels.g, b: trackChannels.b),
                PaletteMath.oklab(r: 0, g: 0, b: 0), 1.0 / 3.0))
        let selectedCount = input.notes.lazy.filter { selected.contains($0.id) }.count
        let dimUnselected = selectedCount > 1
        let resolve = input.source.resolver()
        let preview = input.gesture?.preview ?? [:]
        let detentUnlock = !input.detentsEnabled || input.gesture?.detentUnlock == true
        var result: [VelocityHandleValue] = []
        result.reserveCapacity(input.notes.count)
        for note in input.notes {
            let frozen = input.gesture?.frozenNote(note.id)
            let map = frozen?.map ?? resolve(note.tick, Int(note.pitch)).map
            let previewValue = preview[note.id]
            let displayed = previewValue.map(Int.init) ?? Int(note.velocity)
            let isSelected = selected.contains(note.id)
            let isHovered = input.hovered == note.id
            let x = projection.xForDisplayTick(Double(note.tick))
            let endTick = Double(note.tick) + Double(note.duration)
            let endX = projection.xForDisplayTick(endTick)
            let y = projection.yForNote(
                map: map, velocity: displayed, detentUnlock: detentUnlock)
            let level = map.level(of: displayed) ?? -1
            result.append(VelocityHandleValue(
                noteID: note.id,
                noteIdText: velocityNoteText(note.id),
                tick: Double(note.tick),
                endTick: endTick,
                x: x,
                endX: endX,
                value: displayed,
                y: y,
                selected: isSelected,
                hovered: isHovered,
                preview: previewValue != nil,
                dimmed: dimUnselected && !isSelected,
                level: level,
                label: axis.mode == .intrinsic && level >= 0 ? "Vol \(level + 1)" : "\(displayed)",
                hitRadius: input.geometry.hitRadius,
                stemWidth: (isSelected ? input.geometry.selectedStemDipWidth
                                       : input.geometry.stemDipWidth) / input.devicePixelRatio,
                nodeRadius: input.geometry.nodePaintRadius,
                outlineRadius: input.geometry.nodePaintRadius
                    + input.geometry.nodeOutlineDipWidth / 2,
                outlineWidth: input.geometry.nodeOutlineDipWidth / input.devicePixelRatio,
                ringRadius: input.geometry.selectedNodeRingRadius
                    + input.geometry.selectedNodeRingDipWidth / 2,
                ringWidth: input.geometry.selectedNodeRingDipWidth / input.devicePixelRatio,
                fillColor: isSelected || !dimUnselected ? trackColor : input.palette.outline,
                stemColor: isSelected ? input.palette.selectionRing : stemColor,
                ringColor: input.palette.selectionRing,
                outlineColor: input.palette.noteBorder,
                primitiveName: "velocityNode"))
        }
        return result
    }
}

struct VelocityAxisAndHandles: Sendable {
    var axis: VelocityAxisModel
    var handles: [VelocityHandleValue]
    var rows: VelocityAxisRows
    var readout: VelocityReadoutValue
}

struct VelocityHandleRows: Sendable {
    var handles: [VelocityHandleValue]
    var readout: VelocityReadoutValue
}
