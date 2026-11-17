import Foundation
import PorydawAppPresentation
import PorydawCore
import PorydawDocument
import QtBridge

struct RollNote {
    var id: UInt64
    var velocity: Int
    var ink: UInt32
}

/// Neutral, revision-stamped tracks. Selecting a track changes presentation only;
/// the retained arrays and flat max-end blocks remain shared.
struct RollNoteContent: ExpressibleByArrayLiteral, Equatable {
    static let blockSize = 128

    struct TrackKey: Equatable {
        var chunk: Int?
        var notes: UInt64
        var structure: UInt64
    }

    struct Track {
        let key: TrackKey?
        let notes: [GridNote]
        let blockEnds: [Int]
        let endTick: Int
        let minPitch: Int?
        let maxPitch: Int?
        let hasUnterminated: Bool
        let snap: Int

        /// Flat max-end blocks retain long notes that start before the viewport.
        func forEachCandidateBlock(from: Double, to: Double, _ body: (Range<Int>) -> Void) {
            for block in blockEnds.indices {
                let start = block * RollNoteContent.blockSize
                if Double(notes[start].tick) >= to { break }
                if Double(blockEnds[block]) < from { continue }
                body(start..<min(start + RollNoteContent.blockSize, notes.count))
            }
        }

        init(notes: [GridNote], key: TrackKey? = nil, hasUnterminated: Bool = false, snap: Int = 1) {
            self.key = key
            self.notes = notes
            self.hasUnterminated = hasUnterminated
            self.snap = snap
            var ends: [Int] = []
            ends.reserveCapacity((notes.count + RollNoteContent.blockSize - 1) / RollNoteContent.blockSize)
            var end = 0
            var low: Int?
            var high: Int?
            for start in stride(from: 0, to: notes.count, by: RollNoteContent.blockSize) {
                var blockEnd = 0
                for index in start..<min(start + RollNoteContent.blockSize, notes.count) {
                    let note = notes[index]
                    blockEnd = max(blockEnd, note.tick + note.duration)
                    low = min(low ?? note.pitch, note.pitch)
                    high = max(high ?? note.pitch, note.pitch)
                }
                ends.append(blockEnd)
                end = max(end, blockEnd)
            }
            blockEnds = ends
            endTick = end
            minPitch = low
            maxPitch = high
        }
    }

    private(set) var tracks: [Track] = []
    var selectedTrack: Int
    // A concrete generation stamp keeps hot scene equality independent of note count.
    private var generation = UUID()
    private(set) var count = 0
    private(set) var endTick = 0
    private(set) var minPitch: Int?
    private(set) var maxPitch: Int?
    private var documentKey: (notes: UInt64, structure: UInt64, count: Int, snap: Int)?

    private mutating func updateAggregates() {
        count = 0
        endTick = 0
        minPitch = nil
        maxPitch = nil
        for track in tracks {
            count += track.notes.count
            endTick = max(endTick, track.endTick)
            if let pitch = track.minPitch { minPitch = min(minPitch ?? pitch, pitch) }
            if let pitch = track.maxPitch { maxPitch = max(maxPitch ?? pitch, pitch) }
        }
    }

    init(arrayLiteral elements: GridNote...) {
        selectedTrack = elements.first(where: { !$0.ghost })?.track ?? 0
        let trackCount = (elements.map(\.track).max() ?? -1) + 1
        tracks = (0..<trackCount).map { (track: Int) in
            var notes: [GridNote] = []
            for note in elements where note.track == track {
                notes.append(
                    GridNote(
                        noteId: note.noteId, tick: note.tick, duration: note.duration,
                        pitch: note.pitch, track: track, velocity: note.velocity, ghost: false))
            }
            return Track(notes: notes)
        }
        updateAggregates()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.generation == rhs.generation && lhs.selectedTrack == rhs.selectedTrack
    }

    var primaryNotes: [GridNote] {
        tracks.indices.contains(selectedTrack) ? tracks[selectedTrack].notes : []
    }

    @MainActor
    mutating func refresh(session: DocumentSession, snap: Int) {
        let document = session.document
        let stamps = document.revisions
        let map = document.engineTracks
        let count = map.usedTrackCount
        if let key = documentKey, key.notes == stamps.all.notes,
            key.structure == stamps.structure, key.count == count, key.snap == snap
        {
            return
        }
        var refreshed: [Track] = []
        refreshed.reserveCapacity(count)
        var changed = count != tracks.count
        for track in 0..<count {
            let chunk = map.tracks[track].midiChunk
            let stamp = chunk.map { stamps.chunks[$0].notes } ?? 0
            let key = TrackKey(chunk: chunk, notes: stamp, structure: stamps.structure)
            if tracks.indices.contains(track) {
                let cached = tracks[track]
                if cached.key == key, !cached.hasUnterminated || cached.snap == snap {
                    refreshed.append(cached)
                    continue
                }
            }
            let source = session.projectionCache.notes(in: track)
            var notes: [GridNote] = []
            notes.reserveCapacity(source.count)
            var unterminated = false
            for note in source {
                unterminated = unterminated || note.isUnterminated
                notes.append(
                    GridNote(
                        noteId: note.id, tick: Int(note.tick),
                        duration: note.isUnterminated ? snap : max(1, Int(note.duration)),
                        pitch: Int(note.pitch), track: track, velocity: Int(note.velocity), ghost: false))
            }
            refreshed.append(Track(notes: notes, key: key, hasUnterminated: unterminated, snap: snap))
            changed = true
        }
        if changed {
            tracks = refreshed
            generation = UUID()
            updateAggregates()
        }
        documentKey = (stamps.all.notes, stamps.structure, count, snap)
    }
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

/// One uncommitted note a draw or paint gesture previews in the plot.
struct RollPreviewNote: Equatable {
    var tick: Int
    var duration: Int
    var pitch: Int
}

enum RollStatusPresentation: Equatable {
    case pendingDraw(tick: Int)
    case draw(tick: Int, duration: Int, pitch: Int)
    case paint(count: Int)
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
        case .paint(let count): return "Painting \(count) note(s)"
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

/// Render/key inputs only: scene caches must not retain a publication buffer.
struct RollVelocityPreview: Equatable {
    let revision: UInt64
    let noteId: NoteID
    let pressed: Int
    let delta: Int
    let selection: Set<NoteID>

    func adjusted(_ velocity: Int) -> Int {
        min(127, max(1, velocity + delta))
    }

    func velocity(for note: GridNote) -> Int {
        if note.noteId == noteId { return pressed }
        return selection.contains(note.noteId) ? adjusted(note.velocity) : note.velocity
    }
}

// Everything the notes section reads; draw-preview motion leaves it equal.
struct RollNotesSectionKey: Equatable {
    var notes: RollNoteContent
    var displacement: RollNoteDisplacement
    var displacedNotes: Set<NoteID>
    var selectedNotes: Set<NoteID>
    var velocityPreview: RollVelocityPreview?
    var projection: PitchProjection
    var timeSelection: AutomationTimeSelection?
    var usedTrackCount: Int
    var theme: ThemePreset
}

struct RollDrawingContentKey: Equatable {
    var notesSection: RollNotesSectionKey
    var scale: ScaleProjection
    var baseFontPx: Double
    var timeAxis: TimeAxis
    var feel: GridFeel
    var selection: GridSelection
    var clockTicks: Tick
    var palette: [UInt32]

    var keyboardNames: [String]?
    var typographyAvailable: Bool
    var fonts: [GridFontKind: GridFontSpec]
    var drawPreview: RollPreviewNote?
    var paintPreview: [RollPreviewNote]
    var lastVelocity: Int
    var noteNameMode: Bool
    var showVelocityValues: Bool
}

@MainActor
enum RollDrawingContent {

    static func key(_ input: GridSceneInput, palette: [UInt32]) -> RollDrawingContentKey {
        RollDrawingContentKey(
            notesSection: RollNotesSectionKey(
                notes: input.notes,
                displacement: input.displacement,
                displacedNotes: input.displacedNotes,
                selectedNotes: input.selectedNotes,
                velocityPreview: input.velocityPreview,
                projection: input.camera.projection,
                timeSelection: input.timeSelection,
                usedTrackCount: input.usedTrackCount,
                theme: input.palette.theme),
            scale: input.scale,
            baseFontPx: input.metrics.baseFontPx,
            timeAxis: input.metrics.timeAxis,
            feel: input.grid.feel,
            selection: input.grid.selection,
            clockTicks: input.grid.clockTicks,
            palette: palette,
            keyboardNames: input.keyboardNames,
            typographyAvailable: input.typography != nil,
            fonts: input.fonts,
            drawPreview: input.drawPreview.map {
                RollPreviewNote(tick: $0.tick, duration: $0.duration, pitch: $0.pitch)
            },
            paintPreview: input.paintPreview,
            lastVelocity: input.lastVelocity,
            noteNameMode: input.noteNameMode,
            showVelocityValues: input.showVelocityValues)
    }

    static func updatePalette(_ input: GridSceneInput, into colors: inout [UInt32]) {
        if colors.isEmpty {
            colors = Array(repeating: 0, count: Int(RollPaletteSlot.noteLabelAaDark.rawValue) + 1)
        }
        func set(_ slot: RollPaletteSlot, _ value: UInt32) {
            let index = Int(slot.rawValue)
            if colors[index] != value { colors[index] = value }
        }
        let p = input.palette
        set(.rollBackground, PaletteMath.argb(p.rollBackground))
        set(.accidentalLane, PaletteMath.argb(p.accidentalLane))
        set(.scaleHighlight, PaletteMath.argb(p.scaleHighlight))
        set(.gridBar, PaletteMath.argb(p.gridLineBar))
        set(.gridBeat, PaletteMath.argb(p.gridLineBeat))
        set(.gridSub1, PaletteMath.argb(p.gridLineSub1))
        set(.gridSub2, PaletteMath.argb(p.gridLineSub2))
        set(.gridSub3, PaletteMath.argb(p.gridLineSub3))
        set(.noteBorder, PaletteMath.argb(p.noteBorder))
        let ring = PaletteMath.argb(p.selectionRing)
        set(.selectionRing, ring)
        let selectionFill = PaletteMath.argb(p.selectionFill)
        set(.selectionFill, selectionFill)
        set(.selectionFrame, PaletteMath.argb(p.selectionEdge))
        set(.timeSelectionFill, selectionFill)
        set(.loopEdge, ring)
        set(.loopGlow, ring)
        set(.drawPreviewFill, p.noteFillArgb(track: input.notes.selectedTrack, velocity: input.lastVelocity))
        let white = PaletteMath.argb(p.keyboardNatural)
        set(.keyboardWhite, white)
        let black = PaletteMath.argb(p.keyboardBlack)
        set(.keyboardBlack, black)
        set(.keyboardSeparator, PaletteMath.argb(p.keyboardSeparator))
        set(.keyboardHighlight, PaletteMath.argb(p.keyboardHover))
        set(.keyboardLabel, PaletteMath.argb(p.keyboardLabel))
        set(.noteLabelLight, white)
        set(.noteLabelDark, black)
        set(.primaryText, PaletteMath.argb(p.primaryText))
        set(.rowLine, PaletteMath.argb(p.rowLine))
        set(.gridBeatFine, PaletteMath.argb(p.gridLineBeatFine))
        set(.preRollMask, PaletteMath.argb(p.preRollMask))
        set(.rulerPreRollMask, PaletteMath.argb(p.rulerPreRollMask))
        set(.rulerTick, PaletteMath.argb(p.gridLine))
        set(.chromeBackground, PaletteMath.argb(p.chromeBackground))
        set(.separator, PaletteMath.argb(p.separator))
        set(.rulerDetailText, PaletteMath.argb(p.rulerDetailText))
        set(.implicitSignature, PaletteMath.argb(p.implicitSignature))
        set(.noteVelocityZero, PaletteMath.argb(p.noteVelocityZero))
        set(.noteLabelAaLight, PaletteMath.argb(p.noteLabelAaLight))
        set(.noteLabelAaDark, PaletteMath.argb(p.noteLabelAaDark))
    }

}
