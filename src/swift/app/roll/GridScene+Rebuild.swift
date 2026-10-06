import Foundation
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import QtBridge

@MainActor
struct GridSceneInput {
    var metrics: GridMetrics
    var grid: RollGrid = RollGrid()
    var palette: GridPalette
    var camera: EditorCamera
    var scale: ScaleProjection = ScaleProjection()
    var typography: GridTypography?
    var fontSpec: (GridFontKind) -> QmlFont
    var fonts: [GridFontKind: GridFontSpec] = [:]
    var notes: [GridNote] = []
    var displacement: RollNoteDisplacement = .none
    var displacedNotes: Set<NoteID> = []
    var selectedNotes: Set<NoteID> = []
    var drawPreview: (tick: Int, duration: Int, pitch: Int)?
    var bandSelection: (x: Double, y: Double, w: Double, h: Double)?
    var lastVelocity: Int = 100
    var hoverKey: Int = -1
    var noteNameMode = false
    var showVelocityValues = false
    var timeSelection: AutomationTimeSelection? = nil
    var usedTrackCount = 0
    var selectedTrack = 0
    var keyboardNames: [String]?
    var keyboardBankIdentity: ObjectIdentifier?
    var keyboardProgram = 0
    // Band-2 list height: marker row + fitted ruler text + separator, as
    // published on PianoGrid. Part of the frame key like the camera box.
    var rulerHeight: Double = 0

    // Only synchronous record resolution borrows source storage; cache keys retain owned values.
    @_lifetime(borrow self)
    func renderNotes() -> Span<GridNote> {
        notes.span
    }
}

/// Frame-tier key: content generation plus everything the per-frame plot
/// build reads. Equality skips the rebuild.
struct RollDisplayFrameKey: Equatable {
    // Content-tier generation: bumped when records or the content key
    // resolve. Compared by integer so camera seams never scan notes.
    var generation: Int
    var camera: EditorCamera.Snapshot
    var dpr: Double
    var band: RollBandSignature?
    // The keyboard highlight is emitted list content: hover-only moves
    // rebuild the lists and bump displayRevision once.
    var hoverKey: Int
    // Band-2 list height: typography moves rebuild the ruler list.
    var rulerHeight: Double
}

struct RollBandSignature: Equatable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

@MainActor
extension GridScene {
    /// Valid empty list (header, zero records) for the out-of-range
    /// fallback. Built once and retained.
    @QtIgnored
    func retainedEmptyDisplayList() -> Data {
        if let cached = cachedEmptyDisplayList { return cached }
        var writer = DisplayListWriter()
        let empty = writer.finish()
        cachedEmptyDisplayList = empty
        return empty
    }
}

@MainActor
extension GridScene {

    @QtIgnored
    func rebuildStatic(_ input: GridSceneInput) {
        let snapshot = input.camera.snapshot
        // The carrier's width hands drawer delegates the same-turn zoom scale.
        let value = SceneRectValue(
            x: snapshot.scrollX, y: snapshot.scrollY, width: snapshot.pixelsPerTick, height: 0,
            fillColor: .clear)
        syncRetained(
            cameraScroll, CollectionOfOne(value),
            make: SceneRect.init, update: { $0.update($1) })
        rebuildHover(input)
    }
}
