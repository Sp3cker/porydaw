import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

@MainActor
func runNoteRenderingChecks(_ report: CheckReport, session: DocumentSession) {
    checkNoteBorders(report, session: session)
    checkIdentityNoteColors(report, session: session)
    checkVelocityColorMode(report, session: session)
    checkNoteNameMode(report, session: session)
    checkGhostNotes(report, session: session)
    checkProjectionEconomy(report, session: session)
    checkRulerSweepSingleTrackScope(report, session: session)
}

@MainActor
private func firstNoteRect(named name: String, in model: QListModel<SceneRect>) -> SceneRect? {
    for index in 0..<model.count where model[index].primitiveName == name {
        return model[index]
    }
    return nil
}

@MainActor
private func renderingSeed(_ report: CheckReport, id: String,
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
private func noteBox(_ grid: PianoGrid, session: DocumentSession, note: Note)
    -> (x: Double, y: Double, w: Double, h: Double)? {
    grid.projectedNoteBox(tick: Int(note.tick), end: Int(note.tick + note.duration),
                          pitch: Int(note.pitch))
}

func renderingNear(_ lhs: Double, _ rhs: Double) -> Bool {
    abs(lhs - rhs) < 1e-6
}
private func publishedOpaque(_ color: String) -> Bool {
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
private func checkNoteBorders(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectedNoteFrameRaster"
    let tinyID = "swiftcore/PianoRoll::tinyNoteBorderRaster"
    let oldCamera = session.camera
    let priorSelection = session.selectedNoteOrder
    let grid = PianoGrid(session: session)
    defer {
        session.clearSelectedNotes()
        session.setSelectedNotes(priorSelection)
        session.mutateCamera { $0 = oldCamera }
    }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    guard let noteID = renderingSeed(report, id: id, session: session, grid: grid) else { return }
    defer { session.document.deleteNotes([noteID]) }
    guard let note = session.document.note(noteID) else {
        report.fail(id, "note rendering seed disappeared")
        return
    }
    session.clearSelectedNotes()
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(16.375)
        _ = camera.setVScroll(max(0, (127.5 - Double(note.pitch)) * 16.375 - 160))
    }
    grid.refreshCamera()
    guard let box = noteBox(grid, session: session, note: note),
          let fill = firstNoteRect(named: "gridNote_\(noteID.rawValue)",
                                   in: grid.scene.pianoNoteFills) else {
        report.fail(id, "fractional-height note has no published scene box")
        return
    }
    report.expect(renderingNear(fill.x, box.x) && renderingNear(fill.y, box.y)
                      && renderingNear(fill.width, box.w) && renderingNear(fill.height, box.h),
                  cppID: id, message: "fractional 16.375-key-height note keeps projected box")
    session.setSelectedNotes([noteID])
    grid.refreshCamera()
    let borders = grid.scene.pianoNoteBordersAndSelection
    let ring = 3.0 / grid.devicePixelRatio
    let border = 2.0 / grid.devicePixelRatio
    report.expect(hasFrame(borders, box: box, inset: 0, thickness: ring,
                           color: grid.palette.selectionRing),
                  cppID: id, message: "A007/A012 3px contiguous selection ring stops at inset")
    report.expect(hasFrame(borders, box: box, inset: ring, thickness: border,
                           color: grid.palette.noteBorder),
                  cppID: id, message: "A008-A011 2px black frame lies inside every selected edge")
    session.clearSelectedNotes()
    grid.refreshCamera()
    report.expect(hasFrame(borders, box: box, inset: 0, thickness: border,
                           color: grid.palette.noteBorder),
                  cppID: id, message: "A013/A014 unselected bottom border bounds the face")

    grid.configureViewport(width: 640, height: 320, fontPx: 5, dpr: 1)
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(5.0)
        _ = camera.setVScroll(max(0, (127.5 - Double(note.pitch)) * 5.0 - 160))
    }
    grid.refreshCamera()
    guard let tiny = noteBox(grid, session: session, note: note),
          let tinyFill = firstNoteRect(named: "gridNote_\(noteID.rawValue)",
                                       in: grid.scene.pianoNoteFills) else {
        report.fail(tinyID, "5.0-key-height note has no published scene box")
        return
    }
    let fitted = max(0, min(1, (Int(min(tiny.w, tiny.h).rounded()) - 1) / 2))
    report.expect(fitted == 1, cppID: tinyID,
                  message: "A002 5.0-key-height note has room for a 1px border")
    report.expect(hasFrame(borders, box: tiny, inset: 0, thickness: Double(fitted),
                           color: grid.palette.noteBorder),
                  cppID: tinyID, message: "A003 tiny note retains its 1px black border")
    report.expect(tinyFill.fillColor == grid.palette.noteFill(track: grid.trackIndex, velocity: 100)
                      && tiny.w > 2 * Double(fitted) && tiny.h > 2 * Double(fitted),
                  cppID: tinyID, message: "A004 tiny note face survives inside its border")
}

@MainActor
private func checkIdentityNoteColors(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::velocityColorRaster"
    let oldCamera = session.camera
    let grid = PianoGrid(session: session)
    defer { session.mutateCamera { $0 = oldCamera } }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    guard let noteID = renderingSeed(report, id: id, session: session, grid: grid) else { return }
    defer { session.document.deleteNotes([noteID]) }
    let track = grid.trackIndex
    var colors: [Int: String] = [:]
    for velocity in [1, 64, 127] {
        guard session.document.setVelocities([NoteVelocity(noteID: noteID, velocity: velocity)],
                                              expectedRevision: session.document.revision) != nil
        else {
            report.fail(id, "could not set fixture velocity \(velocity)")
            return
        }
        grid.refreshFromSession()
        guard let fill = firstNoteRect(named: "gridNote_\(noteID.rawValue)",
                                       in: grid.scene.pianoNoteFills) else {
            report.fail(id, "velocity \(velocity) has no published note fill")
            return
        }
        colors[velocity] = fill.fillColor
    }
    let palette = grid.palette
    // MIDI note-on velocity zero is a note-off, so the document clamps edits
    // to 1...127. Exercise the neutral endpoint through the color API itself.
    let zero = palette.noteFill(track: track, velocity: 0)
    let minimum = colors[1] ?? ""
    let maximum = colors[127] ?? ""
    let midpoint = colors[64] ?? ""
    report.expect(zero == palette.noteVelocityZero, cppID: id,
                  message: "A020 velocity zero uses the neutral palette fill")
    report.expect(publishedOpaque(zero), cppID: id,
                  message: "A021 velocity zero palette fill is opaque")
    report.expect(minimum == palette.noteFill(track: track, velocity: 1)
                      && publishedOpaque(minimum), cppID: id,
                  message: "the minimum MIDI note velocity publishes its opaque palette fill")
    report.expect(maximum == palette.noteFill(track: track, velocity: 127),
                  cppID: id, message: "A022 published full velocity uses the track identity fill")
    report.expect(publishedOpaque(maximum), cppID: id,
                  message: "A023 published full velocity is opaque")
    report.expect(publishedOpaque(midpoint), cppID: id,
                  message: "A024 published middle velocity is opaque")
    report.expect(midpoint != zero && midpoint != minimum && midpoint != maximum, cppID: id,
                  message: "A025 published middle velocity differs from both endpoints")
    let immaterial = GridPalette()
    ShellAppearance.apply(to: immaterial, mode: "immaterial", contrast: 50)
    report.expectEqual(expected: "#7DC36B", actual: immaterial.noteFill(track: 6, velocity: 100),
                       cppID: id, what: "immaterial track-six velocity-100 native note color")
}

/// Independent transcription of SongView::velocityNoteColor
/// (trackvoiceops.cpp): fixed #5F44E9/#E90904 endpoints, linear HSV
/// interpolation with t = (v-1)/126 in float widths, 8-bit quantization.
/// Kept separate from PaletteMath so the check pins the oracle math rather
/// than echoing the implementation.
private func expectedVelocityHue(_ velocity: Int) -> String {
    if velocity <= 1 { return "#5F44E9" }
    if velocity >= 127 { return "#E90904" }
    func toHSV(_ r: Int, _ g: Int, _ b: Int) -> (Double, Double, Double) {
        let red = Double(r) / 255
        let green = Double(g) / 255
        let blue = Double(b) / 255
        let cmax = max(red, max(green, blue))
        let cmin = min(red, min(green, blue))
        let delta = cmax - cmin
        let saturation = delta / cmax
        let hue: Double
        if cmax == red {
            hue = (green - blue) / delta
        } else if cmax == green {
            hue = 2 + (blue - red) / delta
        } else {
            hue = 4 + (red - green) / delta
        }
        var degrees = hue * 60
        if degrees < 0 { degrees += 360 }
        return (degrees / 360, saturation, cmax)
    }
    let minimum = toHSV(0x5F, 0x44, 0xE9)
    let maximum = toHSV(0xE9, 0x09, 0x04)
    let t = Float(velocity - 1) / 126
    let h = Double(Float(minimum.0) + (Float(maximum.0) - Float(minimum.0)) * t)
    let s = Double(Float(minimum.1) + (Float(maximum.1) - Float(minimum.1)) * t)
    let v = Double(Float(minimum.2) + (Float(maximum.2) - Float(minimum.2)) * t)
    let sector = h * 6
    let index = Int(sector.rounded(.down))
    let fraction = sector - Double(index)
    let p = v * (1 - s)
    let q = v * (1 - s * fraction)
    let tt = v * (1 - s * (1 - fraction))
    let rgb: (Double, Double, Double)
    switch index {
    case 0: rgb = (v, tt, p)
    case 1: rgb = (q, v, p)
    case 2: rgb = (p, v, tt)
    case 3: rgb = (p, q, v)
    case 4: rgb = (tt, p, v)
    default: rgb = (v, p, q)
    }
    func quantize(_ channel: Double) -> Int {
        min(255, max(0, Int((channel * 255).rounded(.toNearestOrAwayFromZero))))
    }
    return String(format: "#%02X%02X%02X", quantize(rgb.0), quantize(rgb.1), quantize(rgb.2))
}

@MainActor
private func checkVelocityColorMode(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::velocityColorMode"
    let oldCamera = session.camera
    let grid = PianoGrid(session: session)
    defer { session.mutateCamera { $0 = oldCamera } }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    guard let noteID = renderingSeed(report, id: id, session: session, grid: grid) else { return }
    defer { session.document.deleteNotes([noteID]) }
    guard let note = session.document.note(noteID) else {
        report.fail(id, "velocity color seed disappeared")
        return
    }
    let track = grid.trackIndex
    let palette = grid.palette
    func publishedFill() -> String? {
        firstNoteRect(named: "gridNote_\(noteID.rawValue)",
                      in: grid.scene.pianoNoteFills)?.fillColor
    }
    grid.setVelocityColorMode(enabled: true)
    var hues: [Int: String] = [:]
    for velocity in [1, 64, 127] {
        guard session.document.setVelocities([NoteVelocity(noteID: noteID, velocity: velocity)],
                                              expectedRevision: session.document.revision) != nil
        else {
            report.fail(id, "could not set fixture velocity \(velocity)")
            return
        }
        grid.refreshFromSession()
        guard let fill = publishedFill() else {
            report.fail(id, "velocity \(velocity) has no published note fill")
            return
        }
        hues[velocity] = fill
    }
    let minimum = hues[1] ?? ""
    let midpoint = hues[64] ?? ""
    let maximum = hues[127] ?? ""
    let zeroInk = palette.noteVelocityZero
    report.expect(minimum == "#5F44E9", cppID: id,
                  message: "velocity 1 publishes the purple endpoint in palette format")
    report.expect(minimum == PaletteMath.velocityNoteColor(velocity: 1, zeroColor: zeroInk),
                  cppID: id, message: "velocity 1 matches the velocity color API")
    report.expect(maximum == "#E90904", cppID: id,
                  message: "velocity 127 publishes the red endpoint in palette format")
    report.expect(maximum == PaletteMath.velocityNoteColor(velocity: 127, zeroColor: zeroInk),
                  cppID: id, message: "velocity 127 matches the velocity color API")
    report.expect(midpoint == expectedVelocityHue(64), cppID: id,
                  message: "velocity 64 publishes the independently interpolated HSV hue")
    report.expect(midpoint == PaletteMath.velocityNoteColor(velocity: 64, zeroColor: zeroInk),
                  cppID: id, message: "velocity 64 matches the velocity color API")
    report.expect(publishedOpaque(minimum) && publishedOpaque(midpoint)
                      && publishedOpaque(maximum), cppID: id,
                  message: "velocity hue fills are opaque")
    // MIDI note-on velocity zero is a note-off, so the document clamps edits
    // to 1...127. Exercise the neutral endpoint through the color API itself.
    report.expect(PaletteMath.velocityNoteColor(velocity: 0, zeroColor: zeroInk) == zeroInk,
                  cppID: id, message: "velocity zero uses the neutral palette fill")
    // Ghost path: PianoGrid only presents the selected track, so drive the
    // scene directly with a synthetic ghost face in both modes.
    let ghost = GridNote(noteId: noteID, tick: Int(note.tick),
                         duration: max(1, Int(note.duration)), pitch: Int(note.pitch),
                         track: track, velocity: 64, ghost: true)
    let sceneMetrics = GridMetrics(baseFontPx: 13, dpr: 1, width: 640, height: 320)
    func ghostInput(velocityMode: Bool) -> GridSceneInput {
        GridSceneInput(metrics: sceneMetrics, palette: palette, camera: session.camera,
                       contentEndTick: 384, rulerHeight: 0,
                       typography: nil, fontSpec: { _ in [:] },
                       notes: [ghost], velocityColorMode: velocityMode)
    }
    let expectedGhost = PaletteMath.ghostFill(
        track: track, accidentalRow: GridScene.isBlackKey(Int(note.pitch)),
        rollBackground: palette.rollBackground, accidentalLane: palette.accidentalLane)
    grid.scene.rebuildNotes(ghostInput(velocityMode: true))
    let ghostOn = grid.scene.pianoNoteFills.asArray.filter {
        $0.primitiveName == "gridNote_\(noteID.rawValue)"
    }
    grid.scene.rebuildNotes(ghostInput(velocityMode: false))
    let ghostOff = grid.scene.pianoNoteFills.asArray.filter {
        $0.primitiveName == "gridNote_\(noteID.rawValue)"
    }
    report.expect(ghostOn.count == 1 && ghostOn[0].fillColor == expectedGhost, cppID: id,
                  message: "velocity mode leaves the ghost fill on its identity mix")
    report.expect(ghostOff.count == 1 && ghostOff[0].fillColor == expectedGhost, cppID: id,
                  message: "ghost fill is identical with the mode off")
    // Mode off restores identity fills on the live grid.
    grid.refreshFromSession()
    grid.setVelocityColorMode(enabled: false)
    report.expect(publishedFill() == palette.noteFill(track: track, velocity: 127), cppID: id,
                  message: "disabling the mode restores the identity fill")
    guard session.document.setVelocities([NoteVelocity(noteID: noteID, velocity: 1)],
                                          expectedRevision: session.document.revision) != nil
    else {
        report.fail(id, "could not restore fixture velocity 1")
        return
    }
    grid.refreshFromSession()
    report.expect(publishedFill() == palette.noteFill(track: track, velocity: 1), cppID: id,
                  message: "disabling the mode restores the minimum identity fill")
}

@MainActor
private func checkNoteNameMode(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::noteNameMode"
    let oldCamera = session.camera
    let grid = PianoGrid(session: session)
    defer { session.mutateCamera { $0 = oldCamera } }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    guard let noteID = renderingSeed(report, id: id, session: session, grid: grid) else { return }
    defer { session.document.deleteNotes([noteID]) }
    guard let note = session.document.note(noteID) else {
        report.fail(id, "note name seed disappeared")
        return
    }
    let pitch = Int(note.pitch)
    let tick = Int(note.tick)
    // Row heights that surely fit the fixed face: the oracle hides the
    // reduced caption face below its padded height, so use a tall row for the
    // positive case and a sub-threshold one for the gate case.
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(32)
        _ = camera.setVScroll(max(0, (127.5 - Double(pitch)) * 32 - 160))
    }
    grid.refreshCamera()
    // Widen the seeded cell well past name width, keeping it on screen.
    _ = session.mutateCamera { _ = $0.setTimeZoom(280) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(max(camera.snapshot.minHScroll,
                                  camera.contentX(tick: Double(tick)) - 160))
    }
    grid.refreshCamera()
    grid.setNoteNameMode(enabled: true)
    func matchingRecords() -> [SceneText] {
        grid.scene.pianoNoteTextModel.asArray.filter { $0.labelText == GridScene.keyName(pitch) }
    }
    guard let box = noteBox(grid, session: session, note: note) else {
        report.fail(id, "wide note has no projected box")
        return
    }
    let half = grid.metrics.spaceHalf
    let expectedRect = (x: box.x + half, y: box.y + half,
                        w: box.w - 2 * half, h: box.h - 2 * half)
    func rectMatches(_ record: SceneText) -> Bool {
        guard let x = record.labelRect["x"] as? Double,
              let y = record.labelRect["y"] as? Double,
              let width = record.labelRect["width"] as? Double,
              let height = record.labelRect["height"] as? Double
        else { return false }
        return renderingNear(x, expectedRect.x) && renderingNear(y, expectedRect.y)
            && renderingNear(width, expectedRect.w) && renderingNear(height, expectedRect.h)
    }
    let wide = matchingRecords()
    report.expect(wide.count == 1, cppID: id,
                  message: "a wide selected-track note gets exactly one name label")
    if let record = wide.first(where: rectMatches) {
        let fill = firstNoteRect(named: "gridNote_\(noteID.rawValue)",
                                 in: grid.scene.pianoNoteFills)?.fillColor ?? ""
        let light = grid.palette.keyboardNatural
        let dark = grid.palette.keyboardBlack
        let expectedInk = PaletteMath.contrastRatio(fill, light)
            >= PaletteMath.contrastRatio(fill, dark) ? light : dark
        report.expect(record.labelColor == expectedInk
                          && (record.labelColor == light || record.labelColor == dark),
                      cppID: id,
                      message: "the name label uses the contrasting keyboard ink")
        report.expect(record.labelHorizontalAlignment == 0x1
                          && record.labelVerticalAlignment == 0x80, cppID: id,
                      message: "the name label is left-aligned and vertically centred")
        report.expect((record.labelFont["pixelSize"] as? Int) == 11, cppID: id,
                      message: "the name label uses the fixed reduced caption face")
    } else {
        report.fail(id, "the wide note label rect misses the half-space inset box")
    }
    // Too narrow: the same note at minimum time zoom earns no label.
    _ = session.mutateCamera { _ = $0.setTimeZoom(4) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(camera.snapshot.minHScroll)
    }
    grid.refreshCamera()
    report.expect(matchingRecords().isEmpty, cppID: id,
                  message: "a too-narrow note gets no name label")
    // Below the key-height threshold: wide again, but rows too short.
    _ = session.mutateCamera { _ = $0.setTimeZoom(280) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(max(camera.snapshot.minHScroll,
                                  camera.contentX(tick: Double(tick)) - 160))
        _ = camera.setKeyHeight(8)
        _ = camera.setVScroll(max(0, (127.5 - Double(pitch)) * 8 - 160))
    }
    grid.refreshCamera()
    report.expect(matchingRecords().isEmpty, cppID: id,
                  message: "no name labels below the key-height threshold")
    // Ghost exclusion through the exact layout entry the scene calls:
    // PianoGrid only presents the selected track, so exercise the pure
    // function with a synthetic ghost face.
    let faces = [
        NoteNameFace(pitch: pitch, box: (0, 0, 200, 24),
                     fillColor: grid.palette.noteVelocityZero, ghost: true),
        NoteNameFace(pitch: pitch, box: (0, 0, 200, 24),
                     fillColor: grid.palette.noteVelocityZero, ghost: false),
    ]
    let ghostLabels = NoteNameLabels.labels(
        faces: faces, keyHeight: 32, occupiedHeight: 0, pixel: 1,
        spaceHalf: 2, spaceTwo: 7, advance: { _ in 10 },
        font: [:], palette: grid.palette)
    report.expect(ghostLabels.count == 1 && ghostLabels[0].labelText == GridScene.keyName(pitch),
                  cppID: id, message: "ghost notes are never labeled")
    // Mode off empties the model unconditionally.
    grid.setNoteNameMode(enabled: false)
    report.expect(grid.scene.pianoNoteTextModel.count == 0, cppID: id,
                  message: "disabling the mode empties the name model")
}

@MainActor
private struct GhostSeed {
    let id: NoteID
    let pitch: Int
    let tick: Int
    let duration: Int
}

@MainActor
private func ghostSeed(_ report: CheckReport, id: String, session: DocumentSession,
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

@MainActor
private func checkGhostNotes(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::ghostNoteRaster"
    let document = session.document
    let initialState = document.state
    let initialIdentity = document.history.currentIdentity
    let oldCamera = session.camera
    let priorSelection = session.selectedNoteOrder
    let priorTrack = session.selectedTrack
    defer {
        session.clearSelectedNotes()
        if let priorTrack, session.selectedTrack != priorTrack {
            session.selectPrimaryTrack(priorTrack)
        }
        while document.history.currentIdentity != initialIdentity && document.history.canUndo {
            guard document.history.undoDocument() else { break }
        }
        session.selectedTrack = priorTrack
        session.setSelectedNotes(priorSelection)
        session.mutateCamera { $0 = oldCamera }
        report.expect(document.state == initialState
                          && document.history.currentIdentity == initialIdentity,
                      cppID: id, message: "undo restores the ghost fixture and its track")
    }
    let grid = PianoGrid(session: session)
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    let primary = grid.trackIndex
    guard document.canAddTrack, let other = document.addTrack(voice: 0),
          other != primary else {
        report.fail(id, "ghost fixture cannot provision a second engine track")
        return
    }
    report.expect(document.engineTracks.usedTrackCount > other && other != primary,
                  cppID: id, message: "A016 a distinct other track exists for the ghost seed")
    grid.refreshFromSession()
    guard let ghost = ghostSeed(report, id: id, session: session, grid: grid,
                                track: other, spanCells: 8) else { return }
    guard let plain = ghostSeed(report, id: id, session: session, grid: grid,
                                track: primary, spanCells: 1, nearPitch: ghost.pitch,
                                nearTick: ghost.tick, excluding: [ghost.pitch]) else { return }
    func projected(_ noteID: NoteID) -> GridNote? {
        grid.notes.first { $0.noteId == noteID }
    }
    func ghostFill(named name: String) -> String? {
        firstNoteRect(named: name, in: grid.scene.pianoNoteFills)?.fillColor
    }
    report.expect(projected(plain.id)?.ghost == false && projected(ghost.id)?.ghost == true,
                  cppID: id, message: "A016 both fixture notes project, other-track note as ghost")
    guard let ghostBox = grid.projectedNoteBox(tick: ghost.tick, end: ghost.tick + ghost.duration,
                                               pitch: ghost.pitch),
          let plainBox = grid.projectedNoteBox(tick: plain.tick, end: plain.tick + plain.duration,
                                               pitch: plain.pitch) else {
        report.fail(id, "ghost fixture has no projected scene box")
        return
    }
    let expectedGhost = PaletteMath.ghostFill(
        track: other, accidentalRow: GridScene.isBlackKey(ghost.pitch),
        rollBackground: grid.palette.rollBackground, accidentalLane: grid.palette.accidentalLane)
    report.expect(ghostFill(named: "gridNote_\(ghost.id.rawValue)") == expectedGhost,
                  cppID: id, message: "A017 ghost face uses the track-identity mix")
    ShellAppearance.apply(to: grid.palette, mode: "immaterial", contrast: 50)
    grid.refreshFromSession()
    let themedBackdrop = GridScene.isBlackKey(ghost.pitch)
        ? grid.palette.accidentalLane : grid.palette.rollBackground
    let backdropChannels = PaletteMath.channels(themedBackdrop)
    let backdrop = PaletteMath.oklab(r: backdropChannels.r, g: backdropChannels.g,
                                     b: backdropChannels.b)
    let identity = PaletteMath.trackIdentityOklab(other)
    let weight = 60.0 / 255.0
    let lightness = backdrop.lightness
        + min(0.055, max(-0.055, (identity.lightness - backdrop.lightness) * weight))
    let immaterialGhost = PaletteMath.hex(PaletteMath.Oklab(
        lightness: lightness, a: backdrop.a + (identity.a - backdrop.a) * weight,
        b: backdrop.b + (identity.b - backdrop.b) * weight))
    report.expect(ghostFill(named: "gridNote_\(ghost.id.rawValue)") == immaterialGhost,
                  cppID: id, message: "A017 immaterial ghost face mixes into its themed roll lane")
    ShellAppearance.apply(to: grid.palette, mode: "vanilla", contrast: 50)
    grid.refreshFromSession()
    let ring = 3.0 / grid.devicePixelRatio
    let border = 2.0 / grid.devicePixelRatio
    session.setSelectedNotes([plain.id])
    grid.refreshCamera()
    report.expect(hasFrame(grid.scene.pianoNoteBordersAndSelection, box: plainBox, inset: 0,
                           thickness: ring, color: grid.palette.selectionRing),
                  cppID: id, message: "the plain note rings while the ghost face stays flat")
    report.expect(!hasFrame(grid.scene.pianoNoteBordersAndSelection, box: ghostBox, inset: 0,
                            thickness: border, color: grid.palette.noteBorder)
                      && !hasFrame(grid.scene.pianoNoteBordersAndSelection, box: ghostBox, inset: 0,
                                   thickness: ring, color: grid.palette.selectionRing),
                  cppID: id, message: "A017 ghost face edge matches its interior: no border or ring")
    session.setSelectedNotes([ghost.id])
    grid.refreshCamera()
    report.expect(!hasFrame(grid.scene.pianoNoteBordersAndSelection, box: ghostBox, inset: 0,
                            thickness: ring, color: grid.palette.selectionRing),
                  cppID: id, message: "selecting a ghost publishes no selection ring")
    session.clearSelectedNotes()
    grid.refreshCamera()
    grid.setTrack(index: other)
    report.expect(grid.trackIndex == other
                      && projected(plain.id)?.ghost == true
                      && projected(ghost.id)?.ghost == false,
                  cppID: id, message: "selecting the other track swaps plain and ghost roles")
    report.expect(ghostFill(named: "gridNote_\(plain.id.rawValue)")
                      == PaletteMath.ghostFill(
                          track: primary, accidentalRow: GridScene.isBlackKey(plain.pitch),
                          rollBackground: grid.palette.rollBackground,
                          accidentalLane: grid.palette.accidentalLane)
                      && ghostFill(named: "gridNote_\(ghost.id.rawValue)")
                      == grid.palette.noteFill(track: other, velocity: 100),
                  cppID: id, message: "swapped faces follow their new roles")
    grid.setTrack(index: primary)
    grid.setVelocityColorMode(enabled: true)
    let ghostVelocityFill = ghostFill(named: "gridNote_\(ghost.id.rawValue)")
    grid.setVelocityColorMode(enabled: false)
    report.expect(ghostVelocityFill == expectedGhost
                      && ghostFill(named: "gridNote_\(ghost.id.rawValue)") == expectedGhost,
                  cppID: id, message: "A031 velocity-color mode leaves the ghost fill byte-identical")
    let pressX = ghostBox.x + ghostBox.w / 2
    let pressY = ghostBox.y + ghostBox.h / 2
    let revision = session.document.revision
    grid.beginPointer(x: pressX, y: pressY, modifiers: 0)
    report.expect(!session.selectedNotes.contains(ghost.id)
                      && session.document.revision == revision,
                  cppID: id, message: "pressing a ghost selects and edits nothing")
    grid.inputCancelled(reason: GridCancelReason.hidden.rawValue)
    report.expect(!session.selectedNotes.contains(ghost.id) && !grid.interactionActive
                      && session.document.revision == revision,
                  cppID: id, message: "cancelling a ghost press leaves no gesture or edit")
    grid.beginRightPointer(x: ghostBox.x - 4, y: ghostBox.y - 4)
    grid.updateRightPointer(x: ghostBox.x + ghostBox.w + 4, y: ghostBox.y + ghostBox.h + 4)
    grid.endRightPointer(x: ghostBox.x + ghostBox.w + 4, y: ghostBox.y + ghostBox.h + 4)
    report.expect(!session.selectedNotes.contains(ghost.id),
                  cppID: id, message: "a band over a ghost never selects it")
    session.clearSelectedNotes()
    let stateBefore = session.document.state
    grid.doublePointer(x: pressX, y: pressY)
    report.expect(session.document.note(ghost.id) != nil
                      && session.document.state == stateBefore,
                  cppID: id, message: "double-tapping a ghost deletes nothing")
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(32)
        _ = camera.setVScroll(max(0, (127.5 - Double(plain.pitch)) * 32 - 160))
    }
    grid.refreshCamera()
    _ = session.mutateCamera { _ = $0.setTimeZoom(280) }
    grid.refreshCamera()
    _ = session.mutateCamera { camera in
        _ = camera.setHScroll(max(camera.snapshot.minHScroll,
                                  camera.contentX(tick: Double(min(ghost.tick, plain.tick))) - 160))
    }
    grid.refreshCamera()
    grid.setNoteNameMode(enabled: true)
    let labels = grid.scene.pianoNoteTextModel.asArray
    report.expect(labels.contains { $0.labelText == GridScene.keyName(plain.pitch) },
                  cppID: id, message: "the wide selected-track note keeps its name label")
    report.expect(!labels.contains { $0.labelText == GridScene.keyName(ghost.pitch) },
                  cppID: id, message: "A036 ghost notes are never labeled")
    grid.setNoteNameMode(enabled: false)
}

@MainActor
private func checkProjectionEconomy(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::selectedNoteFrameRaster"
    let oldCamera = session.camera
    let priorSelection = session.selectedNoteOrder
    let grid = PianoGrid(session: session)
    defer {
        grid.timeSelectionSource = nil
        grid.clearKeyboardHover()
        session.clearSelectedNotes()
        session.setSelectedNotes(priorSelection)
        session.mutateCamera { $0 = oldCamera }
    }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    guard let noteID = renderingSeed(report, id: id, session: session, grid: grid) else { return }
    defer { session.document.deleteNotes([noteID]) }
    guard let note = session.document.note(noteID),
          let box = grid.projectedNoteBox(
              tick: Int(note.tick), end: Int(note.tick + note.duration),
              pitch: Int(note.pitch)) else {
        report.fail(id, "projection economy fixture has no projected box")
        return
    }
    func fillSnapshot() -> [String] {
        (0..<grid.scene.pianoNoteFills.count).map { index in
            let rect = grid.scene.pianoNoteFills[index]
            return "\(rect.primitiveName)|\(rect.x)|\(rect.y)"
                + "|\(rect.width)|\(rect.height)|\(rect.fillColor)"
        }
    }
    let ring = 3.0 / grid.devicePixelRatio
    session.clearSelectedNotes()
    grid.refreshCamera()
    grid.scene.boxesProjected = 0
    grid.scene.fillWrites = 0
    grid.noteSummaryRebuilds = 0
    let fillsBefore = fillSnapshot()
    let summaryBefore = grid.noteSummary
    session.setSelectedNotes([noteID])
    grid.refreshCamera()
    report.expect(fillSnapshot() == fillsBefore
                      && grid.scene.boxesProjected == 0 && grid.scene.fillWrites == 0,
                  cppID: id,
                  message: "a selection-only refresh reuses the published fills with no box or fill work")
    report.expect(hasFrame(grid.scene.pianoNoteBordersAndSelection, box: box, inset: 0,
                           thickness: ring, color: grid.palette.selectionRing),
                  cppID: id,
                  message: "a selection-only refresh still republishes the selection ring")
    report.expect(grid.noteSummaryRebuilds > 0 && grid.noteSummary != summaryBefore,
                  cppID: id,
                  message: "a selection-content change still rebuilds the note summary")
    grid.scene.boxesProjected = 0
    grid.scene.fillWrites = 0
    grid.noteSummaryRebuilds = 0
    let fillsSelected = fillSnapshot()
    let summarySelected = grid.noteSummary
    grid.updateHover(x: 4, y: box.y + box.h / 2)
    grid.refreshCamera()
    report.expect(fillSnapshot() == fillsSelected
                      && grid.scene.boxesProjected == 0 && grid.scene.fillWrites == 0,
                  cppID: id,
                  message: "a hover-only refresh reuses the published fills with no box or fill work")
    report.expect(grid.noteSummary == summarySelected && grid.noteSummaryRebuilds == 0,
                  cppID: id,
                  message: "a hover-only refresh leaves the note summary byte-identical with no rebuild")
    grid.clearKeyboardHover()
    session.clearSelectedNotes()
    grid.refreshCamera()
    grid.scene.boxesProjected = 0
    grid.scene.fillWrites = 0
    grid.noteSummaryRebuilds = 0
    let fillsPlain = fillSnapshot()
    let summaryPlain = grid.noteSummary
    let startTick = Tick(max(0, Int(note.tick) - 2))
    let endTick = Tick(Int(note.tick) + Int(note.duration) + 2)
    grid.timeSelectionSource = {
        AutomationTimeSelection(
            range: TimeRange(startTick: startTick, endTick: endTick),
            scope: .tracks([grid.trackIndex]))
    }
    grid.refreshCamera()
    report.expect(fillSnapshot() == fillsPlain
                      && grid.scene.boxesProjected == 0 && grid.scene.fillWrites == 0,
                  cppID: id,
                  message: "a highlight-only refresh reuses the published fills with no box or fill work")
    report.expect(grid.noteSummary == summaryPlain && grid.noteSummaryRebuilds == 0,
                  cppID: id,
                  message: "a highlight-only refresh leaves the note summary byte-identical with no rebuild")
    report.expect(hasFrame(grid.scene.pianoNoteBordersAndSelection, box: box, inset: 0,
                           thickness: ring, color: grid.palette.selectionRing),
                  cppID: id,
                  message: "a highlight-only refresh still rings the time-covered note")
    grid.timeSelectionSource = nil
    grid.noteSummaryRebuilds = 0
    let summaryBeforeScroll = grid.noteSummary
    let scrolledX = session.camera.snapshot.scrollX
    session.mutateCamera { _ = $0.scrollByPx(10) }
    guard session.camera.snapshot.scrollX != scrolledX else {
        report.fail(id, "projection economy fixture could not scroll the camera")
        return
    }
    grid.refreshCamera()
    report.expect(grid.scene.boxesProjected > 0,
                  cppID: id,
                  message: "a camera move still reprojects the note boxes")
    report.expect(grid.noteSummary == summaryBeforeScroll && grid.noteSummaryRebuilds == 0,
                  cppID: id,
                  message: "a camera-only refresh leaves the note summary byte-identical with no rebuild")
}

@MainActor
private func checkRulerSweepSingleTrackScope(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::timelineRulerScope"
    let oldCamera = session.camera
    let priorSelection = session.selectedNoteOrder
    let priorTrack = session.selectedTrack
    let palette = GridPalette()
    let grid = PianoGrid(session: session, palette: palette)
    let automation = AutomationPage(baseFontPx: grid.baseFontPx)
    automation.attach(session: session, palette: palette)
    defer {
        automation.clearTimeSelection()
        automation.detach()
        session.clearSelectedNotes()
        session.setSelectedNotes(priorSelection)
        session.selectedTrack = priorTrack
        session.mutateCamera { $0 = oldCamera }
    }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 2)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    if session.selectedTrack == nil { session.selectPrimaryTrack(0) }
    grid.refreshFromSession()
    let primary = session.selectedTrack ?? grid.trackIndex
    let cell = max(1, grid.snapTicks)
    let anchor = Tick(grid.snapTickDown(Double(72)))
    var farTick = anchor + Tick(cell * 4)
    var alignSteps = 0
    while Tick(grid.snapTickDown(Double(farTick))) != farTick && alignSteps < 1024 {
        farTick = farTick + 1
        alignSteps += 1
    }
    let document = session.document
    guard document.canAddTrack, let other = document.addTrack(voice: 0), other != primary,
          let overlapIDs = try? document.addNotes([NewNote(
              track: other, tick: anchor, pitch: 60,
              duration: Tick(cell * 4), velocity: 90)]), !overlapIDs.isEmpty else {
        report.fail(id, "single-track sweep fixture cannot seed the intersecting other-track note")
        return
    }
    defer {
        _ = document.history.undoDocument()
        _ = document.history.undoDocument()
    }
    let revision = document.revision
    automation.clearTimeSelection()
    let menu = RulerMenuPresenter(session: session, grid: grid, automation: automation)
    defer { menu.cancelSweep(); menu.close() }
    menu.beginSweep(contentX: session.camera.contentX(tick: Double(anchor)))
    menu.updateSweep(contentX: session.camera.contentX(tick: Double(farTick)))
    guard let swept = automation.selection, swept.isActive else {
        report.fail(id, "a plain ruler sweep published no time selection")
        return
    }
    report.expect(swept.range == TimeRange(startTick: anchor, endTick: farTick)
                      && swept.scope == .tracks([primary]),
                  cppID: id,
                  message: "a plain sweep keeps the primary-only scope with an intersecting other-track note")
    report.expect(document.revision == revision,
                  cppID: id,
                  message: "a plain sweep publishes its range without a document write")
}
