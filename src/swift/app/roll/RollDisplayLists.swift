import Foundation
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
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
    case noteLabelAaLight
    case noteLabelAaDark
}

// The complete displacement inputs are scalars; source and membership live in the notes key.
enum RollNoteDisplacement: Equatable {
    case none
    case move(ticks: Int, keys: Int, fold: Bool, scale: ScaleID, root: Int)
    case resize(leading: Bool, ticks: Int)

    @MainActor
    func displayed(_ note: GridNote, selected: borrowing Set<NoteID>) -> (tick: Int, end: Int, pitch: Int) {
        var tick = note.tick
        var end = note.tick + note.duration
        var pitch = note.pitch
        if case .none = self { return (tick, end, pitch) }
        guard !note.ghost, selected.contains(note.noteId) else { return (tick, end, pitch) }
        switch self {
        case .none:
            break
        case .move(let ticks, let keys, let fold, let scale, let root):
            tick = max(0, tick + ticks)
            end = max(tick + 1, end + ticks)
            if fold && keys != 0 {
                let destination = scale.pitch(pitch, steps: keys, root: root)
                if destination >= 0 { pitch = destination }
            } else {
                pitch = min(127, max(0, pitch + keys))
            }
        case .resize(let leading, let ticks):
            if leading {
                tick = min(max(0, tick + ticks), end - 1)
            } else {
                end = max(tick + 1, end + ticks)
            }
        }
        return (tick, end, pitch)
    }
}

enum RollStatusPresentation: Equatable {
    case pendingDraw(tick: Int)
    case draw(tick: Int, duration: Int, pitch: Int)
    case velocity
    case move(count: Int, ticks: Int, keys: Int)
    case resize(count: Int)
    case idle(notes: Int, selected: Int)
    case band(count: Int)
    case pan

    var text: String {
        switch self {
        case .pendingDraw(let tick): return "Pending draw at tick \(tick)"
        case .draw(let tick, let duration, let pitch):
            return "Drawing — tick \(tick), duration \(duration), pitch \(pitch)"
        case .velocity: return "Changing velocity"
        case .move(let count, let ticks, let keys):
            return "Moving \(count) note(s) — dTick \(ticks), dKey \(keys)"
        case .resize(let count): return "Resizing \(count) note(s)"
        case .idle(let notes, let selected): return "\(notes) notes, \(selected) selected"
        case .band(let count): return "Selecting \(count) note(s)"
        case .pan: return "Panning"
        }
    }
}

// Everything the notes section reads; draw-preview motion leaves it equal.
struct RollNotesSectionKey: Equatable {
    var notes: [GridNote]
    var displacement: RollNoteDisplacement
    var displacedNotes: Set<NoteID>
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
    var palette: [UInt32]

    var keyboardNames: [String]?
    var typographyAvailable: Bool
    var fonts: RollDrawingContent.FontDescriptors
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

    struct DrawPreviewSignature: Equatable {
        var tick: Int
        var duration: Int
        var pitch: Int
    }

    struct FontDescriptors: Equatable {
        var values: [GridFontKind: GridFontSpec]

        static func == (lhs: Self, rhs: Self) -> Bool {
            guard lhs.values.count == rhs.values.count else { return false }
            for (kind, font) in lhs.values {
                guard let other = rhs.values[kind],
                    font.family == other.family, font.pixelSize == other.pixelSize,
                    font.weight == other.weight, font.letterSpacing == other.letterSpacing
                else { return false }
            }
            return true
        }
    }

    static func key(_ input: GridSceneInput, palette: [UInt32]) -> RollDrawingContentKey {
        RollDrawingContentKey(
            notesSection: RollNotesSectionKey(
                notes: input.notes,
                displacement: input.displacement,
                displacedNotes: input.displacedNotes,
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
            fonts: FontDescriptors(values: input.fonts),
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
            PaletteMath.argb(p.rollBackground),
            PaletteMath.argb(p.accidentalLane),
            PaletteMath.argb(p.scaleHighlight),
            PaletteMath.argb(p.gridLineBar),
            PaletteMath.argb(p.gridLineBeat),
            PaletteMath.argb(p.gridLineSub1),
            PaletteMath.argb(p.gridLineSub2),
            PaletteMath.argb(p.gridLineSub3),
            PaletteMath.argb(p.noteBorder),
            PaletteMath.argb(p.selectionRing),
            PaletteMath.argb(p.selectionFill),
            PaletteMath.argb(p.selectionEdge),
            PaletteMath.argb(p.selectionFill),
            PaletteMath.argb(p.selectionRing),
            PaletteMath.argb(p.selectionRing),
            p.noteFillArgb(track: input.selectedTrack, velocity: input.lastVelocity),
            PaletteMath.argb(p.keyboardNatural),
            PaletteMath.argb(p.keyboardBlack),
            PaletteMath.argb(p.keyboardSeparator),
            PaletteMath.argb(p.keyboardHover),
            PaletteMath.argb(p.keyboardLabel),
            PaletteMath.argb(p.keyboardNatural),
            PaletteMath.argb(p.keyboardBlack),
            PaletteMath.argb(p.primaryText),
            PaletteMath.argb(p.rowLine),
            PaletteMath.argb(p.gridLineBeatFine),
            PaletteMath.argb(p.preRollMask),
            PaletteMath.argb(p.rulerPreRollMask),
            PaletteMath.argb(p.gridLine),
            PaletteMath.argb(p.chromeBackground),
            PaletteMath.argb(p.separator),
            PaletteMath.argb(p.rulerDetailText),
            PaletteMath.argb(p.implicitSignature),
            PaletteMath.argb(p.noteVelocityZero),
            PaletteMath.argb(p.noteLabelAaLight),
            PaletteMath.argb(p.noteLabelAaDark),
        ]
    }

    static func resolveNotes(
        _ input: borrowing GridSceneInput, notes: borrowing Span<GridNote>,
        into records: inout [RollNote]
    ) -> Int {
        let projection = input.camera.projection
        let noteTable = ThemeColorTables.noteFillTable(input.palette.theme)
        let ghostTable = ThemeColorTables.ghostFillTable(input.palette.theme)
        let light = PaletteMath.argb(input.palette.keyboardNatural)
        let dark = PaletteMath.argb(input.palette.keyboardBlack)
        let fallbackLight = PaletteMath.argb(input.palette.noteLabelAaLight)
        let fallbackDark = PaletteMath.argb(input.palette.noteLabelAaDark)
        let notes = input.notes
        let selected = input.selectedNotes
        records.removeAll(keepingCapacity: true)
        records.reserveCapacity(notes.count)
        var maxDuration = 0
        // Ghost records precede plain notes in paint order, independently of tick order.
        for pass in 0..<2 {
            let ghostPass = pass == 0
            for index in notes.indices {
                let note = notes[index]
                if note.ghost != ghostPass { continue }
                let (tick, end, pitch) = input.displacement.displayed(note, selected: input.displacedNotes)
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
                records.append(
                    RollNote(
                        id: note.noteId.rawValue, tick: start, end: start + duration,
                        pitch: boundedPitch, velocity: velocity, flags: flags, fill: fill,
                        ink: PaletteMath.aaContrastInk(
                            fill: fill, light: light, dark: dark,
                            fallbackLight: fallbackLight, fallbackDark: fallbackDark),
                        order: records.count))
                maxDuration = max(maxDuration, duration)
            }
        }
        records.sort { $0.tick == $1.tick ? $0.order < $1.order : $0.tick < $1.tick }
        return maxDuration
    }
}
