import Foundation
import NativeDisplayList
import PorydawCore

@testable import PorydawApp

/// Plot geometry decodes from displayList(0); note entries join decoded fills with grid domain state.
@MainActor struct RollContentProbe {
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

    let revision: Int
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

    private struct Reader {
        let bytes: [UInt8]
        var offset: Int

        mutating func u8() -> UInt8 {
            guard offset < bytes.count else { return 0 }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func unsigned(_ width: Int) -> UInt64 {
            var value: UInt64 = 0
            for shift in 0..<width { value |= UInt64(u8()) << (8 * UInt64(shift)) }
            return value
        }

        mutating func u16() -> Int { Int(unsigned(2)) }
        mutating func u32() -> UInt32 { UInt32(unsigned(4)) }
        mutating func u64() -> Int { Int(clamping: unsigned(8)) }
    }

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

    init(_ scene: GridScene) {
        self.init(
            scene, grid: nil, preview: nil, lastVelocity: 100,
            noteNameMode: nil, showVelocityValues: nil, selectedTrack: nil)
    }

    private init(
        _ scene: GridScene, grid: PianoGrid?,
        preview: (tick: Int, duration: Int, pitch: Int)?, lastVelocity: Int,
        noteNameMode: Bool?, showVelocityValues: Bool?, selectedTrack: Int?
    ) {
        revision = scene.contentRevision
        displayRevision = scene.displayRevision
        let bytes = scene.displayList(list: 0)
        plotBytes = bytes
        let decoded = Self.decodePlot(bytes)
        plotRects = decoded.rects
        plotLabels = decoded.labels
        if let grid {
            let byID = Dictionary(
                grid.notes.map { ($0.noteId.rawValue, $0) },
                uniquingKeysWith: { first, _ in first })
            var seen = Set<UInt64>()
            var built: [Note] = []
            for rect in decoded.rects
                where rect.id != 0 && rect.id < UInt64(PD_DL_ID_LOOP_START)
            {
                guard seen.insert(rect.id).inserted, let note = byID[rect.id] else { continue }
                let shown = grid.displayedNote(note)
                let velocity = grid.previewVelocity(note.noteId) ?? note.velocity
                built.append(Note(
                    id: rect.id, tick: shown.tick,
                    duration: max(0, shown.end - shown.tick),
                    pitch: shown.pitch, track: note.track, velocity: velocity,
                    ghost: note.ghost, fillArgb: rect.argb))
            }
            notes = built
        } else {
            notes = []
        }
        var reader = Reader(bytes: [UInt8](scene.drawingContent()), offset: 0)
        var rows: [Row] = []
        var segments: [Segment] = []
        var ticksPerBeat = 0
        var overlay = Overlay(
            active: false, startTick: 0, endTick: 0, selectedTrack: 0, usedTrackCount: 0,
            scopeTracks: Array(repeating: false, count: 32))
        var keyboardNames: [Int: String] = [:]
        var palette: [UInt32] = []
        var loopStart = 0
        var loopEnd = 0
        var blobModes = false
        var blobVelocity = false
        var drumKeyboard = false
        var blobTrack = 0

        let magic = reader.u32()
        _ = reader.u16()
        let sectionCount = magic == 0x5054_4452 ? reader.u16() : 0
        for _ in 0..<sectionCount {
            let kind = reader.u16()
            let length = Int(reader.u32())
            let end = reader.offset + length
            var r = Reader(bytes: reader.bytes, offset: reader.offset)
            switch kind {
            case 3:
                palette = (0..<r.u16()).map { _ in r.u32() }
            case 4:
                rows = (0..<r.u16()).map { _ in
                    let pitch = Int(r.u8())
                    let flags = r.u8()
                    return Row(pitch: pitch, accidentalLane: flags & 1 != 0, scaleHighlight: flags & 2 != 0)
                }
            case 6:
                for _ in 0..<r.u16() {
                    let pitch = Int(r.u8())
                    let count = r.u16()
                    let start = min(r.offset, r.bytes.count)
                    let stop = min(start + count, r.bytes.count)
                    keyboardNames[pitch] = String(decoding: r.bytes[start..<stop], as: UTF8.self)
                    r.offset += count
                }
            case 7:
                _ = r.u8()
                _ = r.u32()
                _ = r.u8()
                _ = r.u32()
                loopStart = r.u64()
                loopEnd = r.u64()
                segments = (0..<r.u16()).map { _ in
                    let start = r.u64()
                    let next = r.u64()
                    let beatTicks = Int(r.u32())
                    let beatsPerBar = Int(r.u32())
                    let numerator = Int(r.u32())
                    let denomPow2 = Int(r.u8())
                    let implicit = r.u8() != 0
                    return Segment(
                        start: start, next: next, beatTicks: beatTicks, beatsPerBar: beatsPerBar,
                        numerator: numerator, denomPow2: denomPow2, implicit: implicit)
                }
                ticksPerBeat = Int(r.u32())
            case 8:
                let active = r.u8() != 0
                let start = r.u64()
                let stop = r.u64()
                let track = Int(r.u32())
                let used = Int(r.u32())
                let scope = (0..<32).map { _ in r.u8() != 0 }
                overlay = Overlay(
                    active: active, startTick: start, endTick: stop, selectedTrack: track,
                    usedTrackCount: used, scopeTracks: scope)
            case 10:
                let flags = r.u8()
                blobModes = flags & 2 != 0
                blobVelocity = flags & 4 != 0
                drumKeyboard = flags & 16 != 0
                blobTrack = Int(r.u8())
            default:
                break
            }
            reader.offset = end
        }

        self.rows = rows
        self.segments = segments
        self.ticksPerBeat = ticksPerBeat
        self.overlay = overlay
        if let preview {
            self.drawPreview = DrawPreview(
                active: true, tick: preview.tick, duration: preview.duration,
                pitch: preview.pitch, lastVelocity: lastVelocity)
        } else {
            self.drawPreview = DrawPreview(
                active: false, tick: 0, duration: 0, pitch: 0, lastVelocity: 0)
        }
        self.keyboardNames = keyboardNames
        self.palette = palette
        self.loopStartTick = loopStart
        self.loopEndTick = loopEnd
        self.noteNameMode = noteNameMode ?? blobModes
        self.showVelocityValues = showVelocityValues ?? blobVelocity
        self.drumKeyboard = drumKeyboard
        self.selectedTrack = selectedTrack ?? blobTrack
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
                rects.append(PlotRect(
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
                labels.append(PlotLabel(
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

    static func argb(_ hex: String) -> UInt32 {
        SceneRectPacking.argb(hex)
    }
}
