import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func firstNoteRect(named name: String, in model: QListModel<SceneRect>) -> SceneRect? {
    for index in 0..<model.count where model[index].primitiveName == name {
        return model[index]
    }
    return nil
}

@MainActor
func renderingSeed(_ report: CheckReport, id: String,
                           session: DocumentSession, grid: PianoGrid) -> NoteID? {
    let camera = session.camera
    let projection = camera.projection
    let snapshot = camera.snapshot
    let track = grid.trackIndex
    let occupied = (0..<session.document.engineTracks.usedTrackCount).flatMap {
        session.document.notes(in: $0)
    }
    for pitch in (24...115).reversed() {
        let row = projection.row(forPitch: pitch)
        guard row != PitchProjection.hiddenRow,
              let top = projection.rowTop(row, keyHeight: snapshot.keyHeight,
                                          scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
              let bottom = projection.rowBottom(row, keyHeight: snapshot.keyHeight,
                                                scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
              top >= 0, bottom <= snapshot.rollHeight else { continue }
        for probe in stride(from: 40, to: Int(snapshot.viewportWidth) - 40, by: 24) {
            let tick = grid.snapTickDown(camera.tickAtContentX(Double(probe)))
            let cell = grid.gridCell(at: tick)
            let duration = cell.duration
            guard (tick - cell.start) % duration == 0 else { continue }
            let left = camera.contentX(tick: Double(tick))
            let right = camera.contentX(tick: Double(tick + duration))
            let snap = camera.contentX(tick: Double(tick + grid.snapTicks))
            guard left >= 0, right - left >= 12, snap - left >= 8,
                  right < snapshot.viewportWidth,
                  !occupied.contains(where: { note in
                      Int(note.pitch) == pitch && Int(note.tick) < tick + duration
                          && Int(note.tick) + Int(note.duration) > tick
                  }) else { continue }
            guard let added = try? session.document.addNotes([
                NewNote(track: track, tick: Tick(tick), pitch: UInt8(pitch),
                        duration: Tick(duration), velocity: 100)
            ]), let id = added.first else {
                report.fail(id, "note rendering fixture could not insert the free cell")
                return nil
            }
            grid.refreshFromSession()
            return id
        }
    }
    report.fail(id, "note rendering fixture has no visible free cell (40px initial probe)")
    return nil
}

@MainActor
func noteBox(_ grid: PianoGrid, session: DocumentSession, note: Note)
    -> (x: Double, y: Double, w: Double, h: Double)? {
    let camera = session.camera
    guard camera.projection.row(forPitch: Int(note.pitch)) != PitchProjection.hiddenRow
    else { return nil }
    return grid.metrics.noteContentBox(
        camera: camera,
        x0: camera.contentTickX(tick: Double(note.tick), dpr: grid.devicePixelRatio),
        x1: camera.contentTickX(tick: Double(note.tick + note.duration),
                                dpr: grid.devicePixelRatio),
        pitch: Int(note.pitch))
}

@MainActor
func viewportPoint(_ grid: PianoGrid, x: Double, y: Double) -> (x: Double, y: Double) {
    let dpr = grid.devicePixelRatio
    return (x - (grid.cameraScrollX * dpr).rounded() / dpr,
            y - (grid.cameraScrollY * dpr).rounded() / dpr)
}

func renderingNear(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) < 1e-6
}
func publishedOpaque(_ color: String) -> Bool {
    color.count == 7 && color.hasPrefix("#")
}


@MainActor
func hasFrame(_ model: QListModel<SceneRect>,
                      box: (x: Double, y: Double, w: Double, h: Double),
                      inset: Double, thickness: Double, color: String) -> Bool {
    let x = box.x + inset, y = box.y + inset
    let w = box.w - 2 * inset, h = box.h - 2 * inset
    guard w > 0, h > 2 * thickness else { return false }
    let sides = [(x, y, w, thickness), (x, y + h - thickness, w, thickness),
                 (x, y + thickness, thickness, h - 2 * thickness),
                 (x + w - thickness, y + thickness, thickness, h - 2 * thickness)]
    return sides.allSatisfy { side in
        (0..<model.count).contains { index in
            let rect = model[index]
            return rect.fillColor == color && renderingNear(rect.x, side.0)
                && renderingNear(rect.y, side.1) && renderingNear(rect.width, side.2)
                && renderingNear(rect.height, side.3)
        }
    }
}

@MainActor
struct GhostSeed {
    let id: NoteID
    let pitch: Int
    let tick: Int
    let duration: Int
}

@MainActor
func ghostSeed(_ report: CheckReport, id: String, session: DocumentSession,
                       grid: PianoGrid, track: Int, spanCells: Int,
                       nearPitch: Int? = nil, nearTick: Int? = nil,
                       excluding: Set<Int> = []) -> GhostSeed? {
    let camera = session.camera
    let projection = camera.projection
    let snapshot = camera.snapshot
    let occupied = (0..<session.document.engineTracks.usedTrackCount).flatMap {
        session.document.notes(in: $0)
    }
    let pitches: [Int]
    if let near = nearPitch {
        pitches = (24...115).sorted {
            let lhs = abs($0 - near), rhs = abs($1 - near)
            return lhs == rhs ? $0 > $1 : lhs < rhs
        }
    } else {
        pitches = Array((24...115).reversed())
    }
    var probes = stride(from: 40, to: Int(snapshot.viewportWidth) - 40, by: 24).map { probe in
        (probe: Double(probe), tick: grid.snapTickDown(camera.tickAtContentX(Double(probe))))
    }
    if let near = nearTick {
        probes.sort { abs($0.tick - near) < abs($1.tick - near) }
    }
    for pitch in pitches {
        if excluding.contains(pitch) { continue }
        let row = projection.row(forPitch: pitch)
        guard row != PitchProjection.hiddenRow,
              let top = projection.rowTop(row, keyHeight: snapshot.keyHeight,
                                          scrollY: snapshot.scrollY, dpr: grid.devicePixelRatio),
              let bottom = projection.rowBottom(row, keyHeight: snapshot.keyHeight,
                                                scrollY: snapshot.scrollY,
                                                dpr: grid.devicePixelRatio),
              top >= 0, bottom <= snapshot.rollHeight else { continue }
        for probe in probes {
            let tick = probe.tick
            let cell = grid.gridCell(at: tick)
            guard (tick - cell.start) % cell.duration == 0 else { continue }
            let duration = cell.duration * spanCells
            let left = camera.contentX(tick: Double(tick))
            let right = camera.contentX(tick: Double(tick + duration))
            let snap = camera.contentX(tick: Double(tick + grid.snapTicks))
            guard left >= 0, right - left >= 12, snap - left >= 8,
                  right < snapshot.viewportWidth,
                  !occupied.contains(where: { note in
                      Int(note.pitch) == pitch && Int(note.tick) < tick + duration
                          && Int(note.tick) + Int(note.duration) > tick
                  }) else { continue }
            guard let added = try? session.document.addNotes([
                NewNote(track: track, tick: Tick(tick), pitch: UInt8(pitch),
                        duration: Tick(duration), velocity: 100)
            ]), let noteID = added.first else {
                report.fail(id, "ghost fixture could not insert the free cell")
                return nil
            }
            grid.refreshFromSession()
            return GhostSeed(id: noteID, pitch: pitch, tick: tick, duration: duration)
        }
    }
    report.fail(id, "ghost fixture has no visible free cell")
    return nil
}
