import Foundation
@testable import PorydawApp
import PorydawCore
import QtBridge

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
private func hueDegrees(_ color: String) -> Double? {
    guard color.count == 7 else { return nil }
    let channels = Array(color.dropFirst())
    guard let red = Int(String(channels[0...1]), radix: 16),
          let green = Int(String(channels[2...3]), radix: 16),
          let blue = Int(String(channels[4...5]), radix: 16)
    else { return nil }
    let r = Double(red), g = Double(green), b = Double(blue)
    let high = max(r, g, b), low = min(r, g, b)
    let spread = high - low
    if spread == 0 { return 0 }
    if high == r { return ((g - b) / spread + (g < b ? 6 : 0)) * 60 }
    if high == g { return ((b - r) / spread + 2) * 60 }
    return ((r - g) / spread + 4) * 60
}


@MainActor
func checkVelocityColorMode(_ report: CheckReport, session: DocumentSession) {
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
    let revisionBeforeFlip = session.document.revision
    let zeroInk = palette.noteVelocityZero
    grid.setVelocityColorMode(enabled: true)
    let modeOnRevisionUnchanged = session.document.revision == revisionBeforeFlip
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
    let allOpaque = (2...127).allSatisfy { velocity in
        publishedOpaque(PaletteMath.velocityNoteColor(velocity: velocity, zeroColor: zeroInk))
    }
    let hueOrdered = (1..<127).allSatisfy { velocity in
        let first = PaletteMath.velocityNoteColor(velocity: velocity, zeroColor: zeroInk)
        let next = PaletteMath.velocityNoteColor(velocity: velocity + 1, zeroColor: zeroInk)
        return first == expectedVelocityHue(velocity)
            && next == expectedVelocityHue(velocity + 1)
            && (hueDegrees(first).flatMap { a in hueDegrees(next).map { a >= $0 } } ?? false)
    }
    report.expect(allOpaque, cppID: id,
                  message: "every velocity fill from 2 to 127 is opaque")
    report.expect(hueOrdered, cppID: id,
                  message: "velocity hue falls monotonically from purple to red")
    let minimum = hues[1] ?? ""
    let midpoint = hues[64] ?? ""
    let maximum = hues[127] ?? ""
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
    let revisionBeforeModeOff = session.document.revision
    grid.setVelocityColorMode(enabled: false)
    let modeOffRevisionUnchanged = session.document.revision == revisionBeforeModeOff
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
    report.expect(modeOnRevisionUnchanged && modeOffRevisionUnchanged, cppID: id,
                  message: "velocity-mode flips leave the document revision unchanged")
}

@MainActor
func checkVelocityValues(_ report: CheckReport, session: DocumentSession) {
    let id = "swiftcore/PianoRoll::velocityValueRaster"
    let oldCamera = session.camera
    let document = session.document
    let initialState = document.state
    let initialIdentity = document.history.currentIdentity
    let priorSelection = session.selectedNoteOrder
    let grid = PianoGrid(session: session)
    defer {
        if grid.interactionActive {
            grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
        }
        while document.history.currentIdentity != initialIdentity && document.history.canUndo {
            guard document.history.undoDocument() else { break }
        }
        session.setSelectedNotes(priorSelection)
        session.mutateCamera { $0 = oldCamera }
        report.expect(document.state == initialState
                          && document.history.currentIdentity == initialIdentity,
                      cppID: id, message: "velocity-value fixture undo restores the document")
    }
    grid.configureViewport(width: 640, height: 320, fontPx: 13, dpr: 1)
    grid.resetCameraScroll()
    _ = session.mutateCamera { _ = $0.setTimeZoom(35) }
    grid.refreshCamera()
    guard let noteID = renderingSeed(report, id: id, session: session, grid: grid),
          let note = document.note(noteID) else { return }
    session.mutateCamera { camera in
        _ = camera.setKeyHeight(32)
        _ = camera.setVScroll(max(0, (127.5 - Double(note.pitch)) * 32 - 160))
    }
    grid.refreshCamera()
    guard let other = ghostSeed(report, id: id, session: session, grid: grid,
                                track: grid.trackIndex, spanCells: 1,
                                nearPitch: Int(note.pitch),
                                excluding: [Int(note.pitch)]),
          let otherNote = document.note(other.id) else { return }
    session.mutateCamera { camera in
        _ = camera.setTimeZoom(280)
        _ = camera.setHScroll(max(camera.snapshot.minHScroll,
                                  camera.contentX(tick: Double(note.tick)) - 160))
    }
    grid.refreshCamera()
    let revisionBeforeDrag = document.revision
    grid.setNoteNameMode(enabled: true)
    for height in [32.0, 8.6, 9.0] {
        let rowMessage = height == 32.0 ? "" : " at row \(height)"
        session.mutateCamera { camera in
            _ = camera.setKeyHeight(height)
            _ = camera.setVScroll(max(0, (127.5 - Double(note.pitch)) * height - 160))
        }
        grid.refreshCamera()
        guard let box = noteBox(grid, session: session, note: note),
              let otherBox = noteBox(grid, session: session, note: otherNote) else {
            report.fail(id, "velocity-value fixture has no visible pair of note boxes")
            return
        }
        let press = viewportPoint(grid, x: box.x + box.w / 2, y: box.y + box.h / 2)
        let x = press.x, y = press.y
        grid.setVelocityColorMode(enabled: height == 9.0)
        grid.beginPointer(x: x, y: y, modifiers: 0x0400_0000)
        grid.updatePointer(x: x, y: y - grid.dragDistance - 2, modifiers: 0x0400_0000)
        guard let preview = grid.previewVelocity(noteID) else {
            report.fail(id, "control drag did not publish a preview velocity")
            return
        }
        let labels = grid.scene.pianoNoteTextModel.asArray
        let fill = firstNoteRect(named: "gridNote_\(noteID.rawValue)",
                                 in: grid.scene.pianoNoteFills)?.fillColor ?? ""
        let expectedFill = height == 9.0
            ? PaletteMath.velocityNoteColor(
                velocity: preview, zeroColor: grid.palette.noteVelocityZero)
            : grid.palette.noteFill(track: grid.trackIndex, velocity: preview)
        func fits(_ label: SceneText, box: (x: Double, y: Double, w: Double, h: Double))
            -> Bool {
            renderingNear((label.labelRect["x"] as? Double) ?? -.infinity, box.x)
                && renderingNear((label.labelRect["y"] as? Double) ?? -.infinity, box.y)
                && renderingNear((label.labelRect["width"] as? Double) ?? -.infinity, box.w)
                && renderingNear((label.labelRect["height"] as? Double) ?? -.infinity, box.h)
                && label.labelHorizontalAlignment == 0x4
                && label.labelVerticalAlignment == 0x80
        }
        report.expect(labels.contains { $0.labelText == String(preview) && fits($0, box: box) },
                      cppID: id,
                      message: "velocity drag publishes the preview value on its note\(rowMessage)")
        report.expect(labels.contains {
            $0.labelText == String(otherNote.velocity) && fits($0, box: otherBox)
        }, cppID: id,
           message: "other notes show their document velocity during a drag\(rowMessage)")
        report.expect(!labels.contains {
            $0.labelText == GridScene.keyName(Int(note.pitch))
                || $0.labelText == GridScene.keyName(other.pitch)
        }, cppID: id, message: "velocity values replace note names while shown\(rowMessage)")
        report.expect(fill == expectedFill, cppID: id,
                      message: "the dragged note's fill follows its preview velocity\(rowMessage)")
        report.expect(labels.contains {
            $0.labelText == String(preview)
                && $0.labelColor == grid.palette.noteLabelInk(forFill: fill)
        }, cppID: id,
           message: "the preview value uses AA ink against its live fill\(rowMessage)")
        report.expect(document.revision == revisionBeforeDrag, cppID: id,
                      message: "previewing velocity leaves the document unchanged\(rowMessage)")
        if height != 9.0 {
            grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
        } else {
            grid.endPointer(x: x, y: y - grid.dragDistance - 2)
            report.expect(grid.previewVelocity(noteID) == nil
                              && grid.scene.pianoNoteTextModel.asArray.allSatisfy {
                                  $0.labelText != String(preview)
                              }, cppID: id, message: "ending the drag clears velocity values")
            report.expect(document.note(noteID)?.velocity == UInt8(preview), cppID: id,
                          message: "release commits the preview velocity")
        }
    }
    let measured = GridTypography(
        fonts: GridTypography.fonts(
            metrics: grid.metrics, typography: Typography(baseFontPx: 13)),
        rowHeight: 9, pixel: grid.metrics.pixel)
    let allowance = fontPx(grid.metrics.baseFontPx, 0.5)
    let value = NoteNameFace(
        pitch: Int(note.pitch), box: (0, 0, 0, 9), velocity: 100,
        fillColor: grid.palette.noteVelocityZero, ghost: false)
    let threshold = measured.noteValueAdvance("100") + allowance
    let narrow = NoteNameFace(
        pitch: value.pitch, box: (0, 0, threshold - grid.metrics.pixel, 9),
        velocity: value.velocity, fillColor: value.fillColor, ghost: false)
    let fitted = NoteNameFace(
        pitch: value.pitch, box: (0, 0, threshold, 9),
        velocity: value.velocity, fillColor: value.fillColor, ghost: false)
    report.expect(NoteNameLabels.valueLabels(
        faces: [narrow], allowance: allowance, advance: measured.noteValueAdvance,
        font: measured.fontMap(.noteValue), palette: grid.palette).isEmpty,
        cppID: id, message: "one allowance-short box hides the velocity value")
    report.expect(NoteNameLabels.valueLabels(
        faces: [fitted], allowance: allowance, advance: measured.noteValueAdvance,
        font: measured.fontMap(.noteValue), palette: grid.palette).count == 1,
        cppID: id, message: "a box at the exact velocity-value fit shows the value")
    let ghost = NoteNameFace(
        pitch: value.pitch, box: fitted.box, velocity: 100,
        fillColor: value.fillColor, ghost: true)
    report.expect(NoteNameLabels.valueLabels(
        faces: [ghost], allowance: allowance, advance: measured.noteValueAdvance,
        font: measured.fontMap(.noteValue), palette: grid.palette).isEmpty,
        cppID: id, message: "ghost notes never display velocity values")
    let camera = session.camera
    let snapshot = camera.snapshot
    let occupiedPitches = Set(document.notes(in: grid.trackIndex).map { Int($0.pitch) })
    let freeRow = (24...115).first { pitch in
        guard !occupiedPitches.contains(pitch) else { return false }
        let row = camera.projection.row(forPitch: pitch)
        guard row != PitchProjection.hiddenRow,
              let top = camera.projection.rowTop(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
                dpr: grid.devicePixelRatio),
              let bottom = camera.projection.rowBottom(
                row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
                dpr: grid.devicePixelRatio) else { return false }
        return top >= 8 && bottom <= snapshot.rollHeight - 8
    }
    guard let freeRow else {
        report.fail(id, "no empty visible row for the draw preview")
        return
    }
    let row = camera.projection.row(forPitch: freeRow)
    guard let top = camera.projection.rowTop(
        row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
        dpr: grid.devicePixelRatio),
          let bottom = camera.projection.rowBottom(
            row, keyHeight: snapshot.keyHeight, scrollY: snapshot.scrollY,
            dpr: grid.devicePixelRatio) else {
        report.fail(id, "draw preview row cannot be projected")
        return
    }
    let drawY = (top + bottom) / 2
    let revisionBeforeDraw = document.revision
    grid.beginPointer(x: 80, y: drawY, modifiers: 0x0400_0000)
    grid.updatePointer(x: 220, y: drawY, modifiers: 0x0400_0000)
    guard grid.drawPreview != nil,
          let previewBox = grid.scene.pianoDrawPreviewFill.asArray.first else {
        report.fail(id, "control draw did not emit a preview box")
        return
    }
    report.expect(grid.scene.pianoNoteTextModel.asArray.contains {
        $0.labelText == String(grid.lastVelocity)
            && renderingNear(($0.labelRect["x"] as? Double) ?? -.infinity, previewBox.x)
            && renderingNear(($0.labelRect["width"] as? Double) ?? -.infinity,
                             previewBox.width)
            && $0.labelHorizontalAlignment == 0x4
    }, cppID: id, message: "the draw preview carries the last velocity while the modifier is held")
    grid.inputCancelled(reason: GridCancelReason.pointerUngrabbed.rawValue)
    report.expect(grid.drawPreview == nil && document.revision == revisionBeforeDraw,
                  cppID: id, message: "cancelling the draw preview edits no note")
    grid.setNoteNameMode(enabled: false)
    grid.setVelocityColorMode(enabled: false)
}
