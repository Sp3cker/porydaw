import Foundation
import NativeGridTypography
import PorydawCore
import QtBridge

// The Voice Changes scene: the static content computation the page sequences on
// every rebuild, plus the plot x-mapping, snap lattice and marker-hit rules its
// pointer queries resolve through. Every fact arrives as an argument — this file
// retains no session, camera or page state, so a future adapter with its own
// document can call the same rules.
//
// The page keeps its lifecycle, every reuse cache and all publication: it hands
// the scene explicit values and applies what comes back through its existing
// `publishMarkers/publishSpans/publishGrid/publishGutter/publishReadout` seams.
// Palette and typography objects are build inputs, never outputs: they are
// `@MainActor` handles and ride as parameters on this file's own entry points.

// MARK: - Interaction snapshot

/// The live interaction facts one static rebuild reads: the frozen drag's own
/// preview state, and the hover and selected occurrence identities the marker
/// projection marks its rows with. The page builds it from live state per
/// rebuild; the scene never reads that state itself.
struct VoiceInteractionSnapshot: Sendable {
    /// The frozen drag, exactly as the page holds it: the occurrence it caught,
    /// its preview tick and whether the press passed the activation distance.
    var drag: VoiceDragState?
    /// The marker occurrence the pointer last hovered, when it hovered one.
    var hoverIdentity: String?
    /// The occurrence the page's pressed marker selected.
    var selectedIdentity: String
}

// MARK: - Scene vocabulary

/// The readout's published facts and the box the page draws them in. The box
/// crosses as four values because `[String: QVariantSettable]` is not a Sendable
/// value and stays on the page side of the boundary.
struct VoiceReadoutValues: Sendable {
    var slot: Int = -1
    var blank = true
    var symbol = ""
    var text = ""
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0
}

extension VoiceReadoutValues {
    init(_ projection: VoiceReadoutProjection) {
        slot = projection.slot
        blank = projection.blank
        symbol = projection.symbol
        text = projection.text
        x = projection.rect["x"] as? Double ?? 0
        y = projection.rect["y"] as? Double ?? 0
        width = projection.rect["width"] as? Double ?? 0
        height = projection.rect["height"] as? Double ?? 0
    }
}

/// The context identity a presentation compares against the last one it
/// published: the slot the effective context resolves to and the playing state
/// it resolved under.
struct VoiceContextKey: Equatable {
    var slot: Int
    var playing: Bool
}

// MARK: - Scene input

/// Everything the static voice-scene rules read, projected out of the page per
/// rebuild instead of letting the scene reach back into its owner. The page's
/// palette and its two typography handles are `@MainActor` objects and travel as
/// explicit build parameters, so this input stays a plain Sendable value.
struct VoiceChangesSceneInput: Sendable {
    /// The lane's own points.
    var points: [LanePoint] = []
    /// The projected marker entries: the document's own with the frozen drag's
    /// preview applied.
    var entries: [VoiceProjectionEntry] = []
    /// The bank the labels resolve through, and the presented track's own facts.
    var slots: [BankSlotView] = []
    var track: Int = 0
    var firstProgram: Int = -1
    var lengthTicks: Tick = 0
    var trackAvailable = false
    var gutterTitle = "Voice"
    /// The effective context tick the readout resolves at.
    var contextTick: Tick = 0
    /// The page's body geometry and the font-relative values its own policy
    /// resolves: the hover paint padding, the label gap and the stair limit.
    var plotOrigin: Double = 0
    var plotWidth: Double = 0
    var plotHeight: Double = 0
    var devicePixelRatio: Double = 1
    var pad: Double = 0
    var gap: Double = 0
    var stairLimit: Double = 0
    /// The camera the x-mapping resolves through, the page's cached grid metrics,
    /// and the document's own clock lattice.
    var camera: EditorCamera
    var metrics: GridMetrics
    var grid: RollGrid = RollGrid()
    /// The live interaction the marker projection marks its rows with.
    var interaction: VoiceInteractionSnapshot
}

// MARK: - Scene snapshot

/// The values one static voice-scene build produces. Rows are `@MainActor` scene
/// primitives the page applies to its own models; applying them, and keeping
/// every cache, remains the page owner's responsibility.
struct VoiceChangesSceneSnapshot {
    /// Whether a track is presented: the plot, gutter and marker gate.
    var trackAvailable: Bool
    /// The marker entries the build drew with, frozen preview included.
    var entries: [VoiceProjectionEntry]
    /// The gutter's own two lines.
    var gutterTexts: [SceneText]
    /// One rect per held program span.
    var spans: [SceneRect]
    /// The visible vertical grid.
    var gridLines: [SceneRect]
    /// The effective context's readout.
    var readout: VoiceReadoutValues

    /// The detached scene: no track, no content and no context.
    static let detached = Self(
        trackAvailable: false, entries: [], gutterTexts: [], spans: [], gridLines: [],
        readout: VoiceReadoutValues())

    /// The static projections of one rebuild: the gutter, the held spans, the
    /// grid and the readout values, over the entries the page projected. The
    /// palette and the two typography handles are the page's `@MainActor`
    /// objects, which is why they are parameters here and not input fields.
    @MainActor
    static func build(_ input: VoiceChangesSceneInput, palette: GridPalette,
                      title: VoiceCaption?, caption: VoiceCaption?) -> Self {
        Self(
            trackAvailable: input.trackAvailable,
            entries: input.entries,
            gutterTexts: VoiceChangesScene.gutterTexts(input, palette: palette, title: title,
                                                      caption: caption),
            spans: VoiceChangesScene.spans(input, entries: input.entries),
            gridLines: VoiceChangesScene.gridLines(input, palette: palette),
            readout: VoiceChangesScene.readout(firstProgram: input.firstProgram,
                                               tick: input.contextTick, points: input.points,
                                               slots: input.slots, pad: input.pad,
                                               plotWidth: input.plotWidth,
                                               plotHeight: input.plotHeight))
    }
}

// MARK: - Scene value rules

/// The static value rules of the voice scene: plot x-mapping, snapping, marker
/// hit testing, context resolution and the projections behind the page's own
/// publish seams. Every rule is a function of its arguments.
@MainActor
enum VoiceChangesScene {
    // MARK: Plot queries

    /// The shared camera's plot-local x for one tick. `origin: 0` is the page's
    /// own body: the gutter is the plot origin, never part of the camera mapping.
    static func xForTick(_ tick: Tick, camera: EditorCamera,
                         devicePixelRatio: Double) -> Double {
        camera.displayX(tick: Double(tick), origin: 0, dpr: devicePixelRatio)
    }


    /// The nearest marker whose drawn x is inside the font-relative hit radius;
    /// ties keep the later point, exactly as the legacy scan does.
    static func markerHit(at x: Double, points: [LanePoint], camera: EditorCamera,
                          devicePixelRatio: Double, hitRadius: Double) -> LanePoint? {
        VoiceLanePolicy.marker(
            at: x, points: points,
            displayX: { xForTick($0, camera: camera, devicePixelRatio: devicePixelRatio) },
            hitRadius: hitRadius)
    }

    // MARK: Context

    /// The tick the voice context resolves at: the shared playhead while the
    /// transport plays, the edit cursor while it is stopped.
    static func effectiveContextTick(playing: Bool, presentedTick: Tick,
                                     editCursor: Tick) -> Tick {
        playing ? presentedTick : editCursor
    }

    /// The context identity of one tick: the slot it resolves to, and the
    /// playing state it resolved under.
    static func contextKey(tick: Tick, firstProgram: Int, points: [LanePoint],
                           playing: Bool) -> VoiceContextKey {
        let slot = VoiceLanePolicy.slot(firstProgram: firstProgram, tick: tick, points: points)
        return VoiceContextKey(slot: slot, playing: playing)
    }

    /// The label the current bank publishes for one slot, or `""` when the slot
    /// does not exist.
    static func sceneContextLabel(slot: Int, slots: [BankSlotView]) -> String {
        guard slots.indices.contains(slot) else { return "" }
        return VoiceLanePolicy.label(slot: slot, view: slots[slot])
    }

    // MARK: Projection

    /// The projected marker entries: the document's own entries with the frozen
    /// drag's preview applied.
    static func projectedEntries(_ entries: [VoiceProjectionEntry],
                                 interaction: VoiceInteractionSnapshot) -> [VoiceProjectionEntry] {
        VoiceChangesProjection.moving(entries, drag: interaction.drag)
    }

    /// The gutter's two lines, vertically centered: the title, then the change
    /// summary the legacy band publishes while a track is presented.
    static func gutterTexts(_ input: VoiceChangesSceneInput, palette: GridPalette,
                            title: VoiceCaption?, caption: VoiceCaption?) -> [SceneText] {
        VoiceChangesProjection.gutterTexts(VoiceGutterProjectionInput(
            plotHeight: input.plotHeight,
            plotOrigin: input.plotOrigin,
            title: input.gutterTitle,
            summary: input.trackAvailable ? countSummary(input.points) : nil,
            titleFont: title?.fontMap ?? [:],
            captionFont: caption?.fontMap ?? [:],
            titleHeight: title?.height ?? 0,
            captionHeight: caption?.height ?? 0,
            titleColor: palette.primaryText,
            captionColor: palette.secondaryText))
    }

    /// One held-span rect per program section, exactly the legacy walk: a span
    /// from the previous change to this one, then the tail to the song's end.
    static func spans(_ input: VoiceChangesSceneInput,
                      entries: [VoiceProjectionEntry]) -> [SceneRect] {
        guard input.plotHeight > 0, input.plotWidth > 0, input.trackAvailable else { return [] }
        let held = PaletteMath.hex(PaletteMath.trackIdentityOklab(input.track), alpha: 18)
        return VoiceChangesProjection.spans(VoiceSpanProjectionInput(
            entries: entries,
            firstProgram: input.firstProgram,
            lengthTicks: input.lengthTicks,
            plotWidth: input.plotWidth,
            plotHeight: input.plotHeight,
            color: held,
            displayX: { xForTick($0, camera: input.camera,
                                 devicePixelRatio: input.devicePixelRatio) }))
    }

    /// The vertical grid over the visible plot: the roll's own subdivision,
    /// beat, fine-beat and bar lines, through the same grid metrics.
    static func gridLines(_ input: VoiceChangesSceneInput,
                          palette: GridPalette) -> [SceneRect] {
        guard input.plotHeight > 0, input.plotWidth > 0, input.trackAvailable else { return [] }
        return VoiceChangesProjection.grid(
            metrics: input.metrics,
            camera: input.camera,
            plotWidth: input.plotWidth,
            grid: input.grid,
            plotHeight: input.plotHeight,
            colors: VoiceGridProjectionColors(
                subdivision1: palette.gridLineSub1,
                subdivision2: palette.gridLineSub2,
                subdivision3: palette.gridLineSub3,
                bar: palette.gridLineBar,
                beat: palette.gridLineBeat,
                fineBeat: palette.gridLineBeatFine),
            displayX: { xForTick($0, camera: input.camera,
                                 devicePixelRatio: input.devicePixelRatio) })
    }

    /// The marker projection: one marker rule and one label box per entry, with
    /// the legacy elision, stair placement and offscreen rule. The page's own
    /// geometry lookup arrives here and every unaffected row reuses it.
    static func markers(_ input: VoiceChangesSceneInput, palette: GridPalette,
                        caption: VoiceCaption?,
                        reusing previous: [String: VoiceMarkerHandle] = [:])
        -> [VoiceMarkerHandle]
    {
        guard input.plotWidth > 0, input.plotHeight > 0, input.trackAvailable, let caption
        else { return [] }
        return VoiceChangesProjection.markers(VoiceMarkerProjectionInput(
            entries: input.entries,
            slots: input.slots,
            plotWidth: input.plotWidth,
            plotHeight: input.plotHeight,
            pad: input.pad,
            gap: input.gap,
            stairLimit: input.stairLimit,
            physicalPixel: physicalPixel(input.devicePixelRatio),
            labelColor: palette.primaryText,
            lineColor: PaletteMath.trackIdentityFills[PaletteMath.trackIdentityIndex(input.track)],
            selectedIdentity: input.interaction.drag?.identity
                ?? (input.interaction.selectedIdentity.isEmpty
                    ? nil : input.interaction.selectedIdentity),
            hoverIdentity: input.interaction.hoverIdentity,
            previewIdentity: input.interaction.drag?.active == true
                ? input.interaction.drag?.identity : nil,
            caption: caption,
            displayX: { xForTick($0, camera: input.camera,
                                 devicePixelRatio: input.devicePixelRatio) }),
            reusing: previous)
    }

    /// The readout: the label of the program the effective context tick resolves
    /// to, right-aligned in the plot.
    static func readout(firstProgram: Int, tick: Tick, points: [LanePoint],
                        slots: [BankSlotView], pad: Double, plotWidth: Double,
                        plotHeight: Double) -> VoiceReadoutValues {
        VoiceReadoutValues(VoiceChangesProjection.readout(
            firstProgram: firstProgram,
            tick: tick,
            points: points,
            slots: slots,
            pad: pad,
            plotWidth: plotWidth,
            plotHeight: plotHeight))
    }

    // MARK: Summary

    /// The change summary the legacy band publishes while a track is presented.
    private static func countSummary(_ points: [LanePoint]) -> String {
        let count = points.count
        return count == 0 ? "no voice set · double-click to add"
            : "\(count) change(s) · double-click to edit"
    }
}
