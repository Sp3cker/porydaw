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
    var velocityColorMode: Bool
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
            velocityColorMode: input.velocityColorMode,
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
        let values: [Double] = [
            m.baseFontPx, m.keyboardWidth, m.noteMinWidth, m.noteMinHeight,
            m.selectionRingDip, m.drawThreshold, m.detailMinPxPerBeat,
            m.autoGridMinCell, fontPx(m.baseFontPx, 1.0 / 6.0), m.spaceHalf,
            m.spaceTwo, fontPx(m.baseFontPx, 0.25), fontPx(m.baseFontPx, 0.5),
            m.rulerBeatLabelZoomFactor, m.keyLabelRightInset,
        ]
        for value in values { DrawingContentBinary.append(&d, value) }
        return d
    }

    private static func fontsSection(_ input: GridSceneInput) -> Data {
        let order: [(UInt8, GridFontKind)] = [
            (0, .ruler), (1, .beat), (2, .bold), (3, .sig), (4, .chip),
            (5, .keyLabel), (6, .noteName), (7, .noteValue),
        ]
        var d = Data()
        let present = order.filter { input.fonts[$0.1] != nil }
        DrawingContentBinary.append(&d, UInt8(present.count))
        for (id, kind) in present {
            guard let spec = input.fonts[kind] else { continue }
            DrawingContentBinary.append(&d, id)
            DrawingContentBinary.append(&d, Int32(spec.pixelSize))
            DrawingContentBinary.append(&d, Int32(spec.weight))
            DrawingContentBinary.append(&d, spec.letterSpacing)
            DrawingContentBinary.append(&d, UInt16(min(spec.family.utf8.count, Int(UInt16.max))))
            d.append(contentsOf: spec.family.utf8.prefix(Int(UInt16.max)))
        }
        return d
    }

    static func paletteSection(_ input: GridSceneInput) -> Data {
        let p = input.palette
        let argb = { SceneRectPacking.argb($0) }
        let previewFill: String
        if input.velocityColorMode {
            previewFill = PaletteMath.velocityNoteColor(
                velocity: input.lastVelocity, zeroColor: p.noteVelocityZero)
        } else {
            previewFill = PaletteMath.noteFill(
                track: 0, velocity: input.lastVelocity, zeroColor: p.noteVelocityZero)
        }
        let values: [String] = [
            p.rollBackground, p.accidentalLane, p.scaleHighlight, p.gridLineBar,
            p.gridLineBeat, p.gridLineSub1, p.gridLineSub2, p.gridLineSub3,
            p.noteBorder, p.selectionRing, p.selectionFill, p.selectionEdge,
            p.selectionFill, p.selectionRing, p.selectionRing, previewFill,
            p.keyboardNatural, p.keyboardBlack, p.keyboardSeparator,
            p.keyboardHover, p.keyboardLabel, p.keyboardNatural, p.keyboardBlack,
            p.primaryText, p.rowLine, p.gridLineBeatFine, p.preRollMask,
            p.rulerPreRollMask, p.gridLine, p.chromeBackground, p.separator,
            p.rulerDetailText, p.implicitSignature, p.noteVelocityZero,
        ]
        var d = Data()
        DrawingContentBinary.append(&d, UInt16(values.count))
        for value in values { DrawingContentBinary.append(&d, argb(value)) }
        return d
    }

    private static func rowsSection(_ input: GridSceneInput) -> Data {
        let projection = input.camera.projection
        let pitches = (0..<projection.visibleRowCount).compactMap { projection.visiblePitch(at: $0) }
        var d = Data()
        DrawingContentBinary.append(&d, UInt16(pitches.count))
        for pitch in pitches {
            var flags: UInt8 = 0
            if GridScene.isBlackKey(pitch) { flags |= 1 }
            if input.scale.highlight && input.scale.contains(pitch) { flags |= 2 }
            DrawingContentBinary.append(&d, UInt8(pitch))
            DrawingContentBinary.append(&d, flags)
        }
        return d
    }

    private static func notesSection(_ input: GridSceneInput) -> (Data, Int) {
        let p = input.palette
        let projection = input.camera.projection
        var records: [(UInt64, UInt32, UInt32, UInt8, UInt8, UInt8, UInt8, UInt32)] = []
        records.reserveCapacity(input.notes.count)
        for ghostPass in [true, false] {
            for note in input.notes where note.ghost == ghostPass {
                let (tick, end, pitch) = input.displayedNote(note)
                if (0..<128).contains(pitch),
                    projection.row(forPitch: pitch) == PitchProjection.hiddenRow
                {
                    continue
                }
                var flags: UInt8 = note.ghost ? 1 : 0
                if input.selectedNotes.contains(note.noteId) { flags |= 2 }
                if GridScene.timeCovers(input, track: note.track, tick: tick, end: end) {
                    flags |= 4
                }
                let fill: String
                if ghostPass {
                    fill = PaletteMath.ghostFill(
                        track: note.track,
                        accidentalRow: GridScene.isBlackKey(pitch),
                        rollBackground: p.rollBackground,
                        accidentalLane: p.accidentalLane)
                } else if input.velocityColorMode {
                    fill = PaletteMath.velocityNoteColor(
                        velocity: note.velocity, zeroColor: p.noteVelocityZero)
                } else {
                    fill = PaletteMath.noteFill(
                        track: note.track, velocity: note.velocity,
                        zeroColor: p.noteVelocityZero)
                }
                records.append(
                    (
                        note.noteId.rawValue,
                        UInt32(clamping: max(0, tick)),
                        UInt32(clamping: max(0, end - tick)),
                        UInt8(clamping: min(127, max(0, pitch))),
                        UInt8(clamping: note.track),
                        UInt8(clamping: note.velocity),
                        flags,
                        SceneRectPacking.argb(fill)
                    ))
            }
        }
        var d = Data()
        DrawingContentBinary.append(&d, UInt32(records.count))
        for record in records {
            DrawingContentBinary.append(&d, record.0)
            DrawingContentBinary.append(&d, record.1)
            DrawingContentBinary.append(&d, record.2)
            DrawingContentBinary.append(&d, record.3)
            DrawingContentBinary.append(&d, record.4)
            DrawingContentBinary.append(&d, record.5)
            DrawingContentBinary.append(&d, record.6)
            DrawingContentBinary.append(&d, record.7)
        }
        return (d, records.count)
    }

    private static func keyboardNamesSection(_ input: GridSceneInput) -> Data {
        var d = Data()
        guard let names = input.keyboardNames else {
            DrawingContentBinary.append(&d, UInt16(0))
            return d
        }
        var entries: [(Int, String)] = []
        entries.reserveCapacity(128)
        for pitch in 0..<min(128, names.count) {
            let name = names[pitch]
            if !name.isEmpty { entries.append((pitch, name)) }
        }
        DrawingContentBinary.append(&d, UInt16(entries.count))
        for (pitch, name) in entries {
            DrawingContentBinary.append(&d, UInt8(pitch))
            DrawingContentBinary.append(&d, UInt16(min(name.utf8.count, Int(UInt16.max))))
            d.append(contentsOf: name.utf8.prefix(Int(UInt16.max)))
        }
        return d
    }

    private static func timeAxisSection(_ input: GridSceneInput) -> Data {
        DrawingContentBinary.timeAxis(input.metrics.timeAxis, grid: input.grid)
    }

    private static func overlaySection(_ input: GridSceneInput) -> Data {
        var d = Data()
        let selection = input.timeSelection
        DrawingContentBinary.append(&d, selection?.isActive == true ? UInt8(1) : UInt8(0))
        DrawingContentBinary.append(&d, UInt64(selection?.range.startTick ?? 0))
        DrawingContentBinary.append(&d, UInt64(selection?.range.endTick ?? 0))
        DrawingContentBinary.append(&d, UInt32(clamping: input.selectedTrack))
        DrawingContentBinary.append(&d, UInt32(clamping: input.usedTrackCount))
        var scope = [UInt8](repeating: 0, count: 32)
        if let selection, case .tracks(let tracks) = selection.scope {
            for track in tracks where (0..<32).contains(track) {
                scope[track] = 1
            }
        }
        d.append(contentsOf: scope)
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
        if input.velocityColorMode { flags |= 1 }
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
