import Foundation
import PorydawCore
import QtBridge

public enum RollPaletteSlot: UInt16 {
    case rollBackground
    case accidentalLane
    case scaleHighlight
    case gridBar
    case gridBeat
    case gridSub1
    case gridSub2
    case gridSub3
    case noteBorder
    case selectionRing
    case selectionFill
    case selectionFrame
    case timeSelectionFill
    case loopEdge
    case loopGlow
    case drawPreviewFill
    case keyboardWhite
    case keyboardBlack
    case keyboardSeparator
    case keyboardHighlight
    case keyboardLabel
    case noteLabelLight
    case noteLabelDark
    case primaryText
    case rowLine
    case gridBeatFine
    case preRollMask
    case rulerPreRollMask
    case rulerTick
    case chromeBackground
    case separator
    case rulerDetailText
    case implicitSignature
    case noteVelocityZero
}

struct RollDrawingContentKey: Equatable {
    var notes: [GridNote]
    var displayedSpans: [RollDrawingContent.DisplayedSpan]
    var selectedNotes: Set<NoteID>
    var projection: PitchProjection
    var scale: ScaleProjection
    var baseFontPx: Double
    var timeAxis: TimeAxis
    var feel: GridFeel
    var selection: GridSelection
    var clockTicks: Tick
    var palette: Data

    var keyboardNames: [String]?
    var typographyAvailable: Bool
    var fonts: [GridFontKind: RollDrawingContent.FontSignature]
    var drawPreview: RollDrawingContent.DrawPreviewSignature?
    var lastVelocity: Int
    var noteNameMode: Bool
    var showVelocityValues: Bool
    var timeSelection: AutomationTimeSelection?
    var usedTrackCount: Int
    var selectedTrack: Int
}

@MainActor
enum RollDrawingContent {
    struct DisplayedSpan: Equatable {
        var tick: Int
        var end: Int
        var pitch: Int
    }

    struct DrawPreviewSignature: Equatable {
        var tick: Int
        var duration: Int
        var pitch: Int
    }

    struct FontSignature: Equatable {
        var family: String
        var pixelSize: Int
        var weight: Int
        var letterSpacing: Double
    }

    private enum Kind: UInt16 {
        case metrics = 1
        case fonts = 2
        case palette = 3
        case rows = 4
        case notes = 5
        case keyboardNames = 6
        case timeAxis = 7
        case overlay = 8
        case drawPreview = 9
        case modes = 10
    }

    struct Result {
        var data: Data
        var noteRecords: Int
    }

    static func key(_ input: GridSceneInput, palette: Data) -> RollDrawingContentKey {
        RollDrawingContentKey(
            notes: input.notes,
            displayedSpans: input.notes.map {
                let span = input.displayedNote($0)
                return DisplayedSpan(tick: span.tick, end: span.end, pitch: span.pitch)
            },
            selectedNotes: input.selectedNotes,
            projection: input.camera.projection,
            scale: input.scale,
            baseFontPx: input.metrics.baseFontPx,
            timeAxis: input.metrics.timeAxis,
            feel: input.grid.feel,
            selection: input.grid.selection,
            clockTicks: input.grid.clockTicks,
            palette: palette,
            keyboardNames: input.keyboardNames,
            typographyAvailable: input.typography != nil,
            fonts: input.fonts.mapValues {
                FontSignature(
                    family: $0.family, pixelSize: $0.pixelSize,
                    weight: $0.weight, letterSpacing: $0.letterSpacing)
            },
            drawPreview: input.drawPreview.map {
                DrawPreviewSignature(tick: $0.tick, duration: $0.duration, pitch: $0.pitch)
            },
            lastVelocity: input.lastVelocity,
            noteNameMode: input.noteNameMode,
            showVelocityValues: input.showVelocityValues,
            timeSelection: input.timeSelection,
            usedTrackCount: input.usedTrackCount,
            selectedTrack: input.selectedTrack)
    }

    static func pack(_ input: GridSceneInput, palette: Data) -> Result {
        let (notes, noteRecords) = notesSection(input)
        let sections: [(Kind, Data)] = [
            (.metrics, metricsSection(input)),
            (.fonts, fontsSection(input)),
            (.palette, palette),
            (.rows, rowsSection(input)),
            (.notes, notes),
            (.keyboardNames, keyboardNamesSection(input)),
            (.timeAxis, timeAxisSection(input)),
            (.overlay, overlaySection(input)),
            (.drawPreview, drawPreviewSection(input)),
            (.modes, modesSection(input)),
        ]

        return Result(
            data: DrawingContentBinary.frame(sections, kindValue: { $0.rawValue }),
            noteRecords: noteRecords)
    }

    private static func metricsSection(_ input: GridSceneInput) -> Data {
        let m = input.metrics
        var d = Data()
        d.reserveCapacity(15 * 8)
        DrawingContentBinary.append(&d, m.baseFontPx)
        DrawingContentBinary.append(&d, m.keyboardWidth)
        DrawingContentBinary.append(&d, m.noteMinWidth)
        DrawingContentBinary.append(&d, m.noteMinHeight)
        DrawingContentBinary.append(&d, m.selectionRingDip)
        DrawingContentBinary.append(&d, m.drawThreshold)
        DrawingContentBinary.append(&d, m.detailMinPxPerBeat)
        DrawingContentBinary.append(&d, m.autoGridMinCell)
        DrawingContentBinary.append(&d, fontPx(m.baseFontPx, 1.0 / 6.0))
        DrawingContentBinary.append(&d, m.spaceHalf)
        DrawingContentBinary.append(&d, m.spaceTwo)
        DrawingContentBinary.append(&d, fontPx(m.baseFontPx, 0.25))
        DrawingContentBinary.append(&d, fontPx(m.baseFontPx, 0.5))
        DrawingContentBinary.append(&d, m.rulerBeatLabelZoomFactor)
        DrawingContentBinary.append(&d, m.keyLabelRightInset)
        return d
    }

    private static func fontsSection(_ input: GridSceneInput) -> Data {
        let order: [(UInt8, GridFontKind)] = [
            (0, .ruler), (1, .beat), (2, .bold), (3, .sig), (4, .chip),
            (5, .keyLabel), (6, .noteName), (7, .noteValue),
        ]
        let fonts = input.fonts
        var d = Data()
        d.reserveCapacity(1 + order.count * 24)
        DrawingContentBinary.append(&d, UInt8(0))  // count placeholder, patched below
        var count = 0
        for (id, kind) in order {
            guard let spec = fonts[kind] else { continue }
            DrawingContentBinary.append(&d, id)
            DrawingContentBinary.append(&d, Int32(spec.pixelSize))
            DrawingContentBinary.append(&d, Int32(spec.weight))
            DrawingContentBinary.append(&d, spec.letterSpacing)
            DrawingContentBinary.append(&d, UInt16(min(spec.family.utf8.count, Int(UInt16.max))))
            d.append(contentsOf: spec.family.utf8.prefix(Int(UInt16.max)))
            count += 1
        }
        d[0] = UInt8(count)
        return d
    }

    static func paletteSection(_ input: GridSceneInput) -> Data {
        let p = input.palette
        var d = Data()
        d.reserveCapacity(2 + 34 * 4)
        DrawingContentBinary.append(&d, UInt16(34))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.rollBackground))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.accidentalLane))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.scaleHighlight))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.gridLineBar))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.gridLineBeat))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.gridLineSub1))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.gridLineSub2))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.gridLineSub3))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.noteBorder))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.selectionRing))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.selectionFill))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.selectionEdge))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.selectionFill))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.selectionRing))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.selectionRing))
        DrawingContentBinary.append(&d, p.noteFillArgb(track: 0, velocity: input.lastVelocity))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.keyboardNatural))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.keyboardBlack))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.keyboardSeparator))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.keyboardHover))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.keyboardLabel))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.keyboardNatural))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.keyboardBlack))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.primaryText))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.rowLine))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.gridLineBeatFine))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.preRollMask))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.rulerPreRollMask))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.gridLine))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.chromeBackground))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.separator))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.rulerDetailText))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.implicitSignature))
        DrawingContentBinary.append(&d, SceneRectPacking.argb(p.noteVelocityZero))
        return d
    }

    private static func rowsSection(_ input: GridSceneInput) -> Data {
        let projection = input.camera.projection
        let rowCount = projection.visibleRowCount
        let highlight = input.scale.highlight
        let scale = input.scale
        var d = Data()
        d.reserveCapacity(2 + rowCount * 2)
        DrawingContentBinary.append(&d, UInt16(0))  // count placeholder, patched below
        var count = 0
        for row in 0..<rowCount {
            guard let pitch = projection.visiblePitch(at: row) else { continue }
            var flags: UInt8 = 0
            if GridScene.isBlackKey(pitch) { flags |= 1 }
            if highlight && scale.contains(pitch) { flags |= 2 }
            DrawingContentBinary.append(&d, UInt8(pitch))
            DrawingContentBinary.append(&d, flags)
            count += 1
        }
        let patched: UInt16 = UInt16(count).littleEndian
        d.withUnsafeMutableBytes { $0.storeBytes(of: patched, toByteOffset: 0, as: UInt16.self) }
        return d
    }

    private static func notesSection(_ input: GridSceneInput) -> (Data, Int) {
        let projection = input.camera.projection
        let noteTable = ThemeColorTables.noteFillTable(input.palette.theme)
        let ghostTable = ThemeColorTables.ghostFillTable(input.palette.theme)
        let notes = input.notes
        let selected = input.selectedNotes
        let displayed = input.displayedNote
        var d = Data()
        d.reserveCapacity(4 + notes.count * 24)
        DrawingContentBinary.append(&d, UInt32(0))  // count placeholder, patched below
        var count = 0
        // Ghost records first, preserving the old two-pass order without the array.
        for pass in 0..<2 {
            let ghostPass = pass == 0
            for note in notes where note.ghost == ghostPass {
                let (tick, end, pitch) = displayed(note)
                if (0..<128).contains(pitch),
                    projection.row(forPitch: pitch) == PitchProjection.hiddenRow
                {
                    continue
                }
                var flags: UInt8 = note.ghost ? 1 : 0
                if selected.contains(note.noteId) { flags |= 2 }
                if GridScene.timeCovers(input, track: note.track, tick: tick, end: end) {
                    flags |= 4
                }
                let trackIndex = PaletteMath.trackIdentityIndex(note.track)
                let fill: UInt32
                if ghostPass {
                    fill = ghostTable[trackIndex * 2 + (GridScene.isBlackKey(pitch) ? 1 : 0)]
                } else {
                    fill = noteTable[trackIndex * 128 + min(127, max(0, note.velocity))]
                }
                DrawingContentBinary.append(&d, note.noteId.rawValue)
                DrawingContentBinary.append(&d, UInt32(clamping: max(0, tick)))
                DrawingContentBinary.append(&d, UInt32(clamping: max(0, end - tick)))
                DrawingContentBinary.append(&d, UInt8(clamping: min(127, max(0, pitch))))
                DrawingContentBinary.append(&d, UInt8(clamping: note.track))
                DrawingContentBinary.append(&d, UInt8(clamping: note.velocity))
                DrawingContentBinary.append(&d, flags)
                DrawingContentBinary.append(&d, fill)
                count += 1
            }
        }
        let patched: UInt32 = UInt32(count).littleEndian
        d.withUnsafeMutableBytes { $0.storeBytes(of: patched, toByteOffset: 0, as: UInt32.self) }
        return (d, count)
    }

    private static func keyboardNamesSection(_ input: GridSceneInput) -> Data {
        var d = Data()
        guard let names = input.keyboardNames else {
            DrawingContentBinary.append(&d, UInt16(0))
            return d
        }
        d.reserveCapacity(2 + 128 * 8)
        DrawingContentBinary.append(&d, UInt16(0))  // count placeholder, patched below
        var count = 0
        for pitch in 0..<min(128, names.count) {
            let name = names[pitch]
            if name.isEmpty { continue }
            DrawingContentBinary.append(&d, UInt8(pitch))
            DrawingContentBinary.append(&d, UInt16(min(name.utf8.count, Int(UInt16.max))))
            d.append(contentsOf: name.utf8.prefix(Int(UInt16.max)))
            count += 1
        }
        let patched: UInt16 = UInt16(count).littleEndian
        d.withUnsafeMutableBytes { $0.storeBytes(of: patched, toByteOffset: 0, as: UInt16.self) }
        return d
    }

    private static func timeAxisSection(_ input: GridSceneInput) -> Data {
        DrawingContentBinary.timeAxis(input.metrics.timeAxis, grid: input.grid)
    }

    private static func overlaySection(_ input: GridSceneInput) -> Data {
        var d = Data()
        d.reserveCapacity(1 + 8 + 8 + 4 + 4 + 32)
        let selection = input.timeSelection
        DrawingContentBinary.append(&d, selection?.isActive == true ? UInt8(1) : UInt8(0))
        DrawingContentBinary.append(&d, UInt64(selection?.range.startTick ?? 0))
        DrawingContentBinary.append(&d, UInt64(selection?.range.endTick ?? 0))
        DrawingContentBinary.append(&d, UInt32(clamping: input.selectedTrack))
        DrawingContentBinary.append(&d, UInt32(clamping: input.usedTrackCount))
        var tracks: Set<Int>? = nil
        if let selection, case .tracks(let scoped) = selection.scope { tracks = scoped }
        for track in 0..<32 {
            let bit: UInt8 = tracks?.contains(track) == true ? 1 : 0
            DrawingContentBinary.append(&d, bit)
        }
        return d
    }

    private static func drawPreviewSection(_ input: GridSceneInput) -> Data {
        var d = Data()
        guard let preview = input.drawPreview else {
            DrawingContentBinary.append(&d, UInt8(0))
            DrawingContentBinary.append(&d, UInt32(0))
            DrawingContentBinary.append(&d, UInt32(0))
            DrawingContentBinary.append(&d, UInt8(0))
            DrawingContentBinary.append(&d, UInt8(0))
            return d
        }
        DrawingContentBinary.append(&d, UInt8(1))
        DrawingContentBinary.append(&d, UInt32(clamping: max(0, preview.tick)))
        DrawingContentBinary.append(&d, UInt32(clamping: max(0, preview.duration)))
        DrawingContentBinary.append(&d, UInt8(clamping: min(127, max(0, preview.pitch))))
        DrawingContentBinary.append(&d, UInt8(clamping: input.lastVelocity))
        return d
    }

    private static func modesSection(_ input: GridSceneInput) -> Data {
        var flags: UInt8 = 0
        if input.noteNameMode { flags |= 2 }
        if input.showVelocityValues { flags |= 4 }
        if input.typography != nil { flags |= 8 }
        if input.keyboardNames != nil { flags |= 16 }
        var d = Data()
        DrawingContentBinary.append(&d, flags)
        DrawingContentBinary.append(&d, UInt8(clamping: input.selectedTrack))
        return d
    }

}
