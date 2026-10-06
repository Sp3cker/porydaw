import Foundation
import NativeDisplayList
import PorydawCore
import QtBridge

@testable import PorydawApp
@testable import PorydawAppPresentation
@testable import PorydawDocument

/// Plot geometry decodes from displayList(0); note entries join decoded fills with grid domain state.
@MainActor public struct RollContentProbe {
    struct Note {
        let id: UInt64
        let tick: Int
        let duration: Int
        let pitch: Int
        let track: Int
        let velocity: Int
        let ghost: Bool
        let fillArgb: UInt32
    }
    struct Row {
        let pitch: Int
        let accidentalLane: Bool
        let scaleHighlight: Bool
    }
    struct Segment: Equatable {
        let start: Int
        let next: Int
        let beatTicks: Int
        let beatsPerBar: Int
        let numerator: Int
        let denomPow2: Int
        let implicit: Bool
    }
    struct Overlay {
        let active: Bool
        let startTick: Int
        let endTick: Int
        let selectedTrack: Int
        let usedTrackCount: Int
        let scopeTracks: [Bool]
    }
    struct DrawPreview {
        let active: Bool
        let tick: Int
        let duration: Int
        let pitch: Int
        let lastVelocity: Int
    }
    struct PlotRect {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        let id: UInt64
        let argb: UInt32
        let over: Bool
    }
    struct PlotLabel {
        let x: Double
        let y: Double
        let w: Double
        let h: Double
        let id: UInt64
        let text: String
        let argb: UInt32
        let fontId: UInt32
        let pixelSize: UInt32
        let clip: Bool
    }

    static let nameFontId: UInt32 = 6
    static let valueFontId: UInt32 = 7
    static let loopStartId = UInt64(PD_DL_ID_LOOP_START)
    static let loopEndId = UInt64(PD_DL_ID_LOOP_END)

    let contentKey: RollDrawingContentKey?
    let displayRevision: Int
    let notes: [Note]
    let rows: [Row]
    let segments: [Segment]
    let ticksPerBeat: Int
    let overlay: Overlay
    let drawPreview: DrawPreview
    let keyboardNames: [Int: String]
    let palette: [UInt32]
    let loopStartTick: Int
    let loopEndTick: Int
    let noteNameMode: Bool
    let showVelocityValues: Bool
    let drumKeyboard: Bool
    let selectedTrack: Int
    let plotRects: [PlotRect]
    let plotLabels: [PlotLabel]
    let plotBytes: Data
    let keyboardRects: [PlotRect]
    let keyboardLabels: [PlotLabel]

    init(_ grid: PianoGrid) {
        let showVelocity: Bool
        switch grid.gesture {
        case .velocity:
            showVelocity = true
        case .draw, .pendingDraw:
            showVelocity = grid.pointerModifiers & PianoGrid.QtFact.controlModifier != 0
        default:
            showVelocity = false
        }
        self.init(
            grid.scene, grid: grid,
            preview: grid.drawPreview, lastVelocity: grid.lastVelocity,
            noteNameMode: grid.noteNameMode, showVelocityValues: showVelocity,
            selectedTrack: grid.trackIndex)
    }

    private init(
        _ scene: GridScene, grid: PianoGrid,
        preview: (tick: Int, duration: Int, pitch: Int)?, lastVelocity: Int,
        noteNameMode: Bool, showVelocityValues: Bool, selectedTrack: Int
    ) {
        contentKey = scene.listContentKey
        displayRevision = scene.displayRevision
        let bytes = scene.displayList(list: 0)
        plotBytes = bytes
        let decoded = Self.decodePlot(bytes)
        plotRects = decoded.rects
        plotLabels = decoded.labels
        let byID = Dictionary(
            grid.notes.map { ($0.noteId.rawValue, $0) },
            uniquingKeysWith: { first, _ in first })
        var seen = Set<UInt64>()
        var built: [Note] = []
        for rect in decoded.rects
        where rect.id != 0 && rect.id < UInt64(PD_DL_ID_LOOP_START) {
            guard seen.insert(rect.id).inserted, let note = byID[rect.id] else { continue }
            let shown = grid.displayedNote(note)
            let velocity = grid.previewVelocity(note.noteId) ?? note.velocity
            built.append(
                Note(
                    id: rect.id, tick: shown.tick,
                    duration: max(0, shown.end - shown.tick),
                    pitch: shown.pitch, track: note.track, velocity: velocity,
                    ghost: note.ghost, fillArgb: rect.argb))
        }
        notes = built
        // Rows resolve from the live projection and scale, as the removed
        // rows section did at pack time.
        let projection = grid.viewport.camera.projection
        let scale = grid.viewport.scale
        let highlight = scale.highlight
        var rows: [Row] = []
        rows.reserveCapacity(projection.visibleRowCount)
        for row in 0..<projection.visibleRowCount {
            guard let pitch = projection.visiblePitch(at: row) else { continue }
            rows.append(
                Row(
                    pitch: pitch, accidentalLane: GridScene.isBlackKey(pitch),
                    scaleHighlight: highlight && scale.contains(pitch)))
        }
        self.rows = rows
        // Segments resolve from the live axis: the implicit opening segment
        // plus one start per explicit signature, same-tick duplicates merged.
        let axis = grid.metrics.timeAxis
        self.segments = axis.signatureStarts.map { start in
            let segment = axis.segmentAt(start)
            let signature = axis.signatureAt(start)
            return Segment(
                start: Int(start), next: Int(segment.next),
                beatTicks: Int(segment.beatTicks),
                beatsPerBar: Int(segment.beatsPerBar),
                numerator: signature.numerator, denomPow2: signature.denomPow2,
                implicit: signature.implicit)
        }
        self.ticksPerBeat = Int(axis.ticksPerBeat)
        let selection = grid.session.timeSelection
        var scopeTracks = Array(repeating: false, count: 32)
        if let selection, case .tracks(let scoped) = selection.scope {
            for track in scoped where (0..<32).contains(track) { scopeTracks[track] = true }
        }
        self.overlay = Overlay(
            active: selection?.isActive == true,
            startTick: Int(selection?.range.startTick ?? 0),
            endTick: Int(selection?.range.endTick ?? 0),
            selectedTrack: grid.trackIndex,
            usedTrackCount: grid.session.document.engineTracks.usedTrackCount,
            scopeTracks: scopeTracks)
        if let preview {
            self.drawPreview = DrawPreview(
                active: true, tick: preview.tick, duration: preview.duration,
                pitch: preview.pitch, lastVelocity: lastVelocity)
        } else {
            self.drawPreview = DrawPreview(
                active: false, tick: 0, duration: 0, pitch: 0, lastVelocity: 0)
        }
        // Key labels decode from displayList(1); drum names come from the same
        // scene input the builder consumed, with empty pads omitted.
        let keyboardDecoded = Self.decodePlot(scene.displayList(list: 1))
        self.keyboardRects = keyboardDecoded.rects
        self.keyboardLabels = keyboardDecoded.labels
        let drumNames = grid.sceneInput().keyboardNames
        self.keyboardNames = Dictionary(
            uniqueKeysWithValues: (drumNames ?? []).enumerated().compactMap {
                $0.element.isEmpty ? nil : ($0.offset, $0.element)
            })
        self.palette = scene.plotPalette
        self.loopStartTick = Int(axis.loopStartTick)
        self.loopEndTick = Int(axis.loopEndTick)
        self.noteNameMode = noteNameMode
        self.showVelocityValues = showVelocityValues
        self.drumKeyboard = drumNames != nil
        self.selectedTrack = selectedTrack
    }

    // The C decoder borrows the Data bytes: every record is copied out
    // inside withUnsafeBytes so no view pointer outlives the closure.
    private static func decodePlot(_ data: Data) -> (rects: [PlotRect], labels: [PlotLabel]) {
        data.withUnsafeBytes { raw -> (rects: [PlotRect], labels: [PlotLabel]) in
            var view = PdDlView()
            guard pd_dl_decode(raw.baseAddress, raw.count, &view),
                let header = view.header, let rectBase = view.rects,
                let labelBase = view.labels, let textBase = view.text
            else { return ([], []) }
            let rectCount = Int(header.pointee.rectCount)
            var rects: [PlotRect] = []
            rects.reserveCapacity(rectCount)
            for i in 0..<rectCount {
                let r = rectBase[i]
                rects.append(
                    PlotRect(
                        x: r.x, y: r.y, w: r.w, h: r.h, id: r.id, argb: r.argb,
                        over: r.flags & UInt32(PD_DL_RECT_OVER) != 0))
            }
            let labelCount = Int(header.pointee.labelCount)
            var labels: [PlotLabel] = []
            labels.reserveCapacity(labelCount)
            for i in 0..<labelCount {
                let l = labelBase[i]
                let length = Int(l.textLength)
                let text: String
                if length > 0 {
                    let ptr = textBase.advanced(by: Int(l.textOffset))
                    text = String(decoding: Data(bytes: UnsafeRawPointer(ptr), count: length), as: UTF8.self)
                } else {
                    text = ""
                }
                labels.append(
                    PlotLabel(
                        x: l.x, y: l.y, w: l.w, h: l.h, id: l.id, text: text,
                        argb: l.argb, fontId: l.fontId, pixelSize: l.pixelSize,
                        clip: l.flags & UInt32(PD_DL_LABEL_CLIP) != 0))
            }
            return (rects, labels)
        }
    }

    func note(_ id: NoteID) -> Note? {
        notes.first { $0.id == id.rawValue }
    }

    /// First rect carrying the note id: the production builder emits the
    /// fill first, so `face(id)` and the fill coincide.
    func fillRect(_ id: NoteID) -> PlotRect? {
        plotRects.first { $0.id == id.rawValue }
    }

    func ringRects(_ id: NoteID) -> [PlotRect] {
        guard let ring = slot(.selectionRing) else { return [] }
        return plotRects.filter { $0.id == id.rawValue && $0.over && $0.argb == ring }
    }

    /// Emitted hover-highlight records from the painted keyboard list.
    func keyboardHighlightRects() -> [PlotRect] {
        guard let highlight = slot(.keyboardHighlight) else { return [] }
        return keyboardRects.filter { $0.argb == highlight }
    }

    /// Painted key-label texts from the keyboard list, in record order.
    func keyLabelTexts() -> [String] {
        keyboardLabels.map(\.text)
    }

    func borderRects(_ id: NoteID) -> [PlotRect] {
        guard let ring = slot(.selectionRing),
            let fill = fillRect(id)?.argb
        else { return [] }
        return plotRects.filter {
            $0.id == id.rawValue && $0.argb != ring && $0.argb != fill
        }
    }

    func nameLabel(_ id: NoteID) -> PlotLabel? {
        plotLabels.first { $0.id == id.rawValue && $0.fontId == Self.nameFontId }
    }

    func valueLabel(_ id: NoteID) -> PlotLabel? {
        plotLabels.first { $0.id == id.rawValue && $0.fontId == Self.valueFontId }
    }

    func nameLabels() -> [PlotLabel] {
        plotLabels.filter { $0.fontId == Self.nameFontId }
    }

    func valueLabels() -> [PlotLabel] {
        plotLabels.filter { $0.fontId == Self.valueFontId }
    }

    /// Draw-preview records carry the NONE id; the fill matches the preview
    /// palette slot.
    func previewFill() -> PlotRect? {
        guard let preview = slot(.drawPreviewFill) else { return nil }
        return plotRects.first { $0.id == UInt64(PD_DL_ID_NONE) && $0.argb == preview }
    }

    func loopEdgeMinX() -> Double? {
        guard let edge = slot(.loopEdge) else { return nil }
        return plotRects.filter {
            $0.id == Self.loopStartId && $0.argb == edge
        }.map(\.x).min()
    }

    func loopEdgeMaxX() -> Double? {
        guard let edge = slot(.loopEdge) else { return nil }
        return plotRects.filter {
            $0.id == Self.loopEndId && $0.argb == edge
        }.map(\.x).max()
    }

    func slot(_ slot: RollPaletteSlot) -> UInt32? {
        let index = Int(slot.rawValue)
        return palette.indices.contains(index) ? palette[index] : nil
    }

    public static func argb(_ hex: String) -> UInt32 {
        PaletteMath.argb(hex)
    }

    public static func argb(_ color: QmlColor) -> UInt32 {
        PaletteMath.argb(color)
    }
}
