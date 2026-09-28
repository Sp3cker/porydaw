import Foundation
import PorydawCore

@testable import PorydawApp

@MainActor struct RollContentProbe {
    struct Note {
        let id: UInt64
        let tick: Int
        let duration: Int
        let pitch: Int
        let track: Int
        let velocity: Int
        let ghost: Bool
        let selected: Bool
        let timeCovered: Bool
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

    let revision: Int
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

    init(_ scene: GridScene) {
        revision = scene.contentRevision
        var reader = Reader(bytes: [UInt8](scene.drawingContent()), offset: 0)
        var notes: [Note] = []
        var rows: [Row] = []
        var segments: [Segment] = []
        var ticksPerBeat = 0
        var overlay = Overlay(
            active: false, startTick: 0, endTick: 0, selectedTrack: 0, usedTrackCount: 0,
            scopeTracks: Array(repeating: false, count: 32))
        var drawPreview = DrawPreview(active: false, tick: 0, duration: 0, pitch: 0, lastVelocity: 0)
        var keyboardNames: [Int: String] = [:]
        var palette: [UInt32] = []
        var loopStart = 0
        var loopEnd = 0
        var noteNameMode = false
        var showVelocityValues = false
        var drumKeyboard = false
        var selectedTrack = 0

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
            case 5:
                notes = (0..<Int(r.u32())).map { _ in
                    let id = r.unsigned(8)
                    let tick = Int(r.u32())
                    let duration = Int(r.u32())
                    let pitch = Int(r.u8())
                    let track = Int(r.u8())
                    let velocity = Int(r.u8())
                    let flags = r.u8()
                    let fill = r.u32()
                    return Note(
                        id: id, tick: tick, duration: duration, pitch: pitch, track: track, velocity: velocity,
                        ghost: flags & 1 != 0, selected: flags & 2 != 0, timeCovered: flags & 4 != 0,
                        fillArgb: fill)
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
            case 9:
                let active = r.u8() != 0
                let tick = Int(r.u32())
                let duration = Int(r.u32())
                let pitch = Int(r.u8())
                let velocity = Int(r.u8())
                drawPreview = DrawPreview(
                    active: active, tick: tick, duration: duration, pitch: pitch,
                    lastVelocity: velocity)
            case 10:
                let flags = r.u8()
                noteNameMode = flags & 2 != 0
                showVelocityValues = flags & 4 != 0
                drumKeyboard = flags & 16 != 0
                selectedTrack = Int(r.u8())
            default:
                break
            }
            reader.offset = end
        }

        self.notes = notes
        self.rows = rows
        self.segments = segments
        self.ticksPerBeat = ticksPerBeat
        self.overlay = overlay
        self.drawPreview = drawPreview
        self.keyboardNames = keyboardNames
        self.palette = palette
        self.loopStartTick = loopStart
        self.loopEndTick = loopEnd
        self.noteNameMode = noteNameMode
        self.showVelocityValues = showVelocityValues
        self.drumKeyboard = drumKeyboard
        self.selectedTrack = selectedTrack
    }

    func note(_ id: NoteID) -> Note? {
        notes.first { $0.id == id.rawValue }
    }

    static func argb(_ hex: String) -> UInt32 {
        SceneRectPacking.argb(hex)
    }
}
