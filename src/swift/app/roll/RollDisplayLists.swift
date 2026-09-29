import Foundation
import PorydawCore
import QtBridge

struct RollNote {
    var id: UInt64
    var tick: Int
    var end: Int
    var pitch: Int
    var velocity: Int
    var flags: UInt8
    var fill: UInt32
    var ink: UInt32
    var order: Int
}

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

// Everything the notes section reads; draw-preview motion leaves it equal.
struct RollNotesSectionKey: Equatable {
    var notes: [GridNote]
    var displayedSpans: [RollDrawingContent.DisplayedSpan]
    var selectedNotes: Set<NoteID>
    var projection: PitchProjection
    var timeSelection: AutomationTimeSelection?
    var usedTrackCount: Int
    var theme: ThemePreset
}

struct RollDrawingContentKey: Equatable {
    var notesSection: RollNotesSectionKey
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

    static func key(_ input: GridSceneInput, palette: Data) -> RollDrawingContentKey {
        RollDrawingContentKey(
            notesSection: RollNotesSectionKey(
                notes: input.notes,
                displayedSpans: input.displacesNotes
                    ? input.notes.map {
                        let span = input.displayedNote($0)
                        return DisplayedSpan(tick: span.tick, end: span.end, pitch: span.pitch)
                    } : [],
                selectedNotes: input.selectedNotes,
                projection: input.camera.projection,
                timeSelection: input.timeSelection,
                usedTrackCount: input.usedTrackCount,
                theme: input.palette.theme),
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

    static func paletteColors(_ input: GridSceneInput) -> [UInt32] {
        let p = input.palette
        return [
            SceneRectPacking.argb(p.rollBackground),
            SceneRectPacking.argb(p.accidentalLane),
            SceneRectPacking.argb(p.scaleHighlight),
            SceneRectPacking.argb(p.gridLineBar),
            SceneRectPacking.argb(p.gridLineBeat),
            SceneRectPacking.argb(p.gridLineSub1),
            SceneRectPacking.argb(p.gridLineSub2),
            SceneRectPacking.argb(p.gridLineSub3),
            SceneRectPacking.argb(p.noteBorder),
            SceneRectPacking.argb(p.selectionRing),
            SceneRectPacking.argb(p.selectionFill),
            SceneRectPacking.argb(p.selectionEdge),
            SceneRectPacking.argb(p.selectionFill),
            SceneRectPacking.argb(p.selectionRing),
            SceneRectPacking.argb(p.selectionRing),
            p.noteFillArgb(track: 0, velocity: input.lastVelocity),
            SceneRectPacking.argb(p.keyboardNatural),
            SceneRectPacking.argb(p.keyboardBlack),
            SceneRectPacking.argb(p.keyboardSeparator),
            SceneRectPacking.argb(p.keyboardHover),
            SceneRectPacking.argb(p.keyboardLabel),
            SceneRectPacking.argb(p.keyboardNatural),
            SceneRectPacking.argb(p.keyboardBlack),
            SceneRectPacking.argb(p.primaryText),
            SceneRectPacking.argb(p.rowLine),
            SceneRectPacking.argb(p.gridLineBeatFine),
            SceneRectPacking.argb(p.preRollMask),
            SceneRectPacking.argb(p.rulerPreRollMask),
            SceneRectPacking.argb(p.gridLine),
            SceneRectPacking.argb(p.chromeBackground),
            SceneRectPacking.argb(p.separator),
            SceneRectPacking.argb(p.rulerDetailText),
            SceneRectPacking.argb(p.implicitSignature),
            SceneRectPacking.argb(p.noteVelocityZero),
        ]
    }

    static func paletteSection(colors: [UInt32]) -> Data {
        var data = Data()
        data.reserveCapacity(2 + colors.count * 4)
        DrawingContentBinary.append(&data, UInt16(colors.count))
        for color in colors { DrawingContentBinary.append(&data, color) }
        return data
    }

    static func resolveNotes(_ input: GridSceneInput, into records: inout [RollNote]) -> Int {
        let projection = input.camera.projection
        let noteTable = ThemeColorTables.noteFillTable(input.palette.theme)
        let ghostTable = ThemeColorTables.ghostFillTable(input.palette.theme)
        let light = SceneRectPacking.argb(input.palette.keyboardNatural)
        let dark = SceneRectPacking.argb(input.palette.keyboardBlack)
        let notes = input.notes
        let selected = input.selectedNotes
        let displayed = input.displayedNote
        records.removeAll(keepingCapacity: true)
        records.reserveCapacity(notes.count)
        var maxDuration = 0
        // Ghost records precede plain notes in paint order, independently of tick order.
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
                let start = max(0, tick)
                let duration = max(0, end - tick)
                let boundedPitch = min(127, max(0, pitch))
                let velocity = min(127, max(0, note.velocity))
                records.append(RollNote(
                    id: note.noteId.rawValue, tick: start, end: start + duration,
                    pitch: boundedPitch, velocity: velocity, flags: flags, fill: fill,
                    ink: labelInk(fill: fill, light: light, dark: dark),
                    order: records.count))
                maxDuration = max(maxDuration, duration)
            }
        }
        records.sort { $0.tick == $1.tick ? $0.order < $1.order : $0.tick < $1.tick }
        return maxDuration
    }

    static func labelInk(fill: UInt32, light: UInt32, dark: UInt32) -> UInt32 {
        func luminance(_ color: UInt32) -> Double {
            func linear(_ channel: UInt32) -> Double {
                let value = Double(channel & 255) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(color >> 16) + 0.7152 * linear(color >> 8)
                + 0.0722 * linear(color)
        }
        let background = luminance(fill)
        func contrast(_ ink: UInt32) -> Double {
            let value = luminance(ink)
            return (max(background, value) + 0.05) / (min(background, value) + 0.05)
        }
        let preferred = contrast(light) >= contrast(dark) ? light : dark
        if contrast(preferred) >= 4.5 { return preferred }
        return contrast(0xFFFFFFFF) >= contrast(0xFF000000) ? 0xFFFFFFFF : 0xFF000000
    }

}
