import Foundation
import PorydawCore
import QtBridge

@MainActor
extension GridScene {
    struct NoteFillKey: Equatable {
        var notes: [GridNote]
        var pixelsPerTick: Double
        var keyHeight: Double
        var windowLeft: Double
        var windowRight: Double
        var projection: PitchProjection
        var scale: ScaleProjection
        var dpr: Double
        var noteMinWidth: Double
        var noteMinHeight: Double
        var pixel: Double
        var velocityColorMode: Bool
        var velocityZeroColor: String
        var rollBackground: String
        var accidentalLane: String
    }

    struct CachedNoteGeometry {
        var noteId: NoteID
        var tick: Int
        var end: Int
        var pitch: Int
        var track: Int
        var ghost: Bool
        var box: (x: Double, y: Double, w: Double, h: Double)
        var fillColor: String
    }

    @QtIgnored
    func rebuildNotes(_ input: GridSceneInput) {
        let window = ContentWindow(
            camera: input.camera, contentEndTick: input.contentEndTick, previous: contentWindow)
        let key = NoteFillKey(
            notes: input.notes, pixelsPerTick: input.camera.snapshot.pixelsPerTick,
            keyHeight: input.camera.snapshot.keyHeight,
            windowLeft: window.left, windowRight: window.right,
            projection: input.camera.projection, scale: input.scale,
            dpr: input.metrics.dpr, noteMinWidth: input.metrics.noteMinWidth,
            noteMinHeight: input.metrics.noteMinHeight, pixel: input.metrics.pixel,
            velocityColorMode: input.velocityColorMode,
            velocityZeroColor: input.palette.noteVelocityZero,
            rollBackground: input.palette.rollBackground,
            accidentalLane: input.palette.accidentalLane)
        if !input.geometryStable || key != noteFillKey {
            let built = buildNoteFills(input, window: window)
            cachedNoteFills = built.fills
            cachedNoteGeometries = built.geometries
            cachedNoteFaces = built.faces
            noteFillKey = input.geometryStable ? key : nil
        }
        emitNoteSelection(input)
        emitNoteRemainder(input, window: window)
    }

    @QtIgnored
    private func emitNoteSelection(_ input: GridSceneInput) {
        var borders: [SceneRect] = []
        for geometry in cachedNoteGeometries {
            if geometry.ghost {
                if timeCovers(input, track: geometry.track, tick: geometry.tick, end: geometry.end) {
                    addSelectionRing(&borders, box: geometry.box, input: input)
                }
                continue
            }
            if input.isSelected(geometry.noteId)
                || timeCovers(input, track: geometry.track, tick: geometry.tick, end: geometry.end) {
                addSelectionRing(&borders, box: geometry.box, input: input)
            } else {
                addNoteBorder(&borders, box: geometry.box, insetPixels: 0, input: input)
            }
        }
        sync(pianoNoteFills, cachedNoteFills)
        sync(pianoNoteBordersAndSelection, borders)
    }

    @QtIgnored
    private func buildNoteFills(_ input: GridSceneInput, window: ContentWindow)
        -> (fills: [SceneRect], geometries: [CachedNoteGeometry], faces: [NoteNameFace]) {
        let m = input.metrics
        let p = input.palette
        let camera = input.camera
        let projection = camera.projection
        var fills: [SceneRect] = []
        var geometries: [CachedNoteGeometry] = []
        var faces: [NoteNameFace] = []
        for ghostPass in [true, false] {
            for note in input.notes where note.ghost == ghostPass {
                let (tick, end, pitch) = input.displayedNote(note)
                let x0 = camera.contentTickX(tick: Double(tick), dpr: m.dpr)
                let x1 = camera.contentTickX(tick: Double(end), dpr: m.dpr)
                guard max(x1, x0 + m.noteMinWidth) > window.left, x0 < window.right else { continue }
                if (0..<128).contains(pitch),
                    projection.row(forPitch: pitch) == PitchProjection.hiddenRow { continue }
                let box = m.noteContentBox(camera: camera, x0: x0, x1: x1, pitch: pitch)
                boxesProjected += 1
                guard box.w > 0, box.h > 0 else { continue }
                let name = "gridNote_\(note.noteId.rawValue)"
                let fillColor: String
                if ghostPass {
                    fillColor = PaletteMath.ghostFill(
                        track: note.track, accidentalRow: GridScene.isBlackKey(pitch),
                        rollBackground: p.rollBackground, accidentalLane: p.accidentalLane)
                } else if input.velocityColorMode {
                    fillColor = PaletteMath.velocityNoteColor(
                        velocity: note.velocity, zeroColor: p.noteVelocityZero)
                } else {
                    fillColor = PaletteMath.noteFill(
                        track: note.track,
                        velocity: note.velocity,
                        zeroColor: p.noteVelocityZero)
                }
                fills.append(
                    SceneRect(
                        x: box.x, y: box.y, width: box.w, height: box.h,
                        fillColor: fillColor,
                        primitiveName: name))
                fillWrites += 1
                geometries.append(
                    CachedNoteGeometry(
                        noteId: note.noteId, tick: tick, end: end, pitch: pitch,
                        track: note.track, ghost: ghostPass,
                        box: (box.x, box.y, box.w, box.h), fillColor: fillColor))
                if !ghostPass {
                    faces.append(
                        NoteNameFace(
                            pitch: pitch, box: (box.x, box.y, box.w, box.h),
                            velocity: note.velocity,
                            fillColor: fillColor, ghost: false))
                }
            }
        }
        return (fills, geometries, faces)
    }

    @QtIgnored
    private func emitNoteRemainder(_ input: GridSceneInput, window: ContentWindow) {
        let m = input.metrics
        let p = input.palette
        let camera = input.camera
        let snapshot = camera.snapshot
        let contentHeight = camera.projection.totalHeight(keyHeight: snapshot.keyHeight)

        var preview: [SceneRect] = []
        var previewFace: NoteNameFace?
        var overlay: [SceneRect] = []
        if let drawn = input.drawPreview {
            let box = m.noteContentBox(
                camera: camera,
                x0: camera.contentTickX(tick: Double(drawn.tick), dpr: m.dpr),
                x1: camera.contentTickX(tick: Double(drawn.tick + drawn.duration), dpr: m.dpr),
                pitch: drawn.pitch)
            let fill = input.velocityColorMode
                ? PaletteMath.velocityNoteColor(
                    velocity: input.lastVelocity, zeroColor: p.noteVelocityZero)
                : PaletteMath.noteFill(
                    track: 0, velocity: input.lastVelocity, zeroColor: p.noteVelocityZero)
            preview.append(SceneRect(
                x: box.x, y: box.y, width: box.w, height: box.h,
                fillColor: fill, primitiveName: "drawPreview"))
            previewFace = NoteNameFace(
                pitch: drawn.pitch, box: (box.x, box.y, box.w, box.h),
                velocity: input.lastVelocity, fillColor: fill, ghost: false)
            addNoteBorder(&overlay, box: box, insetPixels: 0, input: input)
        }
        if let band = input.selectionBand {
            let clip = (
                x: window.left, y: 0.0,
                w: window.right - window.left, h: contentHeight)
            let scrollX = floor(snapshot.scrollX * m.dpr + 0.5) / m.dpr
            let scrollY = floor(snapshot.scrollY * m.dpr + 0.5) / m.dpr
            let x0 = max(band.x + scrollX, clip.x)
            let y0 = max(band.y + scrollY, clip.y)
            let x1 = min(band.x + band.w + scrollX, clip.x + clip.w)
            let y1 = min(band.y + band.h + scrollY, clip.y + clip.h)
            if x1 > x0, y1 > y0 {
                overlay.append(
                    SceneRect(
                        x: x0, y: y0, width: x1 - x0, height: y1 - y0,
                        fillColor: p.selectionFill))
                addDashedFrame(
                    &overlay, box: (x0, y0, x1 - x0, y1 - y0), clip: clip,
                    color: p.selectionEdge, metrics: m)
            }
        }

        if let selection = input.timeSelection, selection.isActive,
            case let .tracks(scope) = selection.scope,
            scope.contains(input.selectedTrack), input.selectedTrack >= 0,
            input.selectedTrack < input.usedTrackCount {
            let x0 = camera.contentTickX(tick: Double(selection.range.startTick), dpr: m.dpr)
            let x1 = camera.contentTickX(tick: Double(selection.range.endTick), dpr: m.dpr)
            overlay.append(SceneRect(
                x: x0, y: 0, width: x1 - x0, height: contentHeight,
                fillColor: p.selectionFill))
            overlay.append(SceneRect(
                x: x0 - m.pixel / 2, y: 0, width: m.pixel, height: contentHeight,
                fillColor: p.selectionEdge))
            overlay.append(SceneRect(
                x: x1 - m.pixel / 2, y: 0, width: m.pixel, height: contentHeight,
                fillColor: p.selectionEdge))
        }
        let startTick = m.timeAxis.loopStartTick
        let endTick = m.timeAxis.loopEndTick
        let hasStart = startTick != TimeDefaults.noTick
        let hasEnd = endTick != TimeDefaults.noTick
        if (hasStart || hasEnd), window.right > window.left, contentHeight > 0 {
            let x0 = hasStart
                ? camera.contentTickX(tick: Double(startTick), dpr: m.dpr) : window.extentLeft
            let x1 = hasEnd
                ? camera.contentTickX(tick: Double(endTick), dpr: m.dpr) : window.extentRight
            if x1 > window.left, x0 < window.right {
                let glowWidth = min(2 * m.baseFontPx, x1 - x0)
                let ink = PaletteMath.channels(p.selectionRing)
                let bandWidth = max(1, m.spaceHalf)
                func appendGlow(at left: Double, fadesRight: Bool, name: String) {
                    guard glowWidth > 0 else { return }
                    let firstBand = max(0, Int(floor((window.left - left) / bandWidth)))
                    var band = firstBand
                    while left + Double(band) * bandWidth < min(left + glowWidth, window.right) {
                        let bandLeft = left + Double(band) * bandWidth
                        let bandRight = min(left + Double(band + 1) * bandWidth, left + glowWidth)
                        let midpoint = (bandLeft + bandRight) / 2
                        let fraction = fadesRight
                            ? (midpoint - left) / glowWidth
                            : (left + glowWidth - midpoint) / glowWidth
                        let alpha = fraction <= 0.2
                            ? 150 + (18 - 150) * fraction / 0.2
                            : 18 * (1 - fraction) / 0.8
                        let visibleLeft = max(window.left, bandLeft)
                        let visibleRight = min(window.right, bandRight)
                        if visibleRight > visibleLeft {
                            overlay.append(SceneRect(
                                x: visibleLeft, y: 0, width: visibleRight - visibleLeft,
                                height: contentHeight,
                                fillColor: PaletteMath.hex(
                                    r: ink.r, g: ink.g, b: ink.b,
                                    a: Int(alpha.rounded(.toNearestOrAwayFromZero))),
                                primitiveName: name))
                        }
                        band += 1
                    }
                }
                if hasStart {
                    appendGlow(at: x0, fadesRight: true, name: "loopGlowStart")
                }
                if hasEnd {
                    appendGlow(at: x1 - glowWidth, fadesRight: false, name: "loopGlowEnd")
                }
                if hasStart {
                    let left = max(window.left, x0 - m.pixel / 2)
                    let right = min(window.right, x0 + m.pixel / 2)
                    if right > left {
                        overlay.append(SceneRect(
                            x: left, y: 0, width: right - left, height: contentHeight,
                            fillColor: p.selectionRing, primitiveName: "loopEdgeStart"))
                    }
                }
                if hasEnd {
                    let left = max(window.left, x1 - m.pixel / 2)
                    let right = min(window.right, x1 + m.pixel / 2)
                    if right > left {
                        overlay.append(SceneRect(
                            x: left, y: 0, width: right - left, height: contentHeight,
                            fillColor: p.selectionRing, primitiveName: "loopEdgeEnd"))
                    }
                }
            }
        }
        sync(pianoDrawPreviewFill, preview)
        sync(pianoOverlay, overlay)

        if input.showVelocityValues, let typography = input.typography,
           typography.noteValueVisible {
            var faces = cachedNoteFaces
            if let previewFace { faces.append(previewFace) }
            syncText(
                pianoNoteTextModel,
                NoteNameLabels.valueLabels(
                    faces: faces, allowance: fontPx(m.baseFontPx, 0.5),
                    advance: typography.noteValueAdvance, font: input.fontSpec(.noteValue),
                    palette: p),
                signatures: &noteTextSignatures)
        } else if !input.showVelocityValues, input.noteNameMode, input.typography != nil {
            syncText(
                pianoNoteTextModel,
                NoteNameLabels.labels(
                    faces: cachedNoteFaces, keyHeight: snapshot.keyHeight,
                    occupiedHeight: input.noteNameOccupiedHeight,
                    pixel: m.pixel, spaceHalf: m.spaceHalf, spaceTwo: m.spaceTwo,
                    advance: input.noteNameAdvance, font: input.fontSpec(.noteName),
                    palette: p),
                signatures: &noteTextSignatures)
        } else {
            syncText(pianoNoteTextModel, [], signatures: &noteTextSignatures)
        }
        syncText(pianoLoadingTextModel, [], signatures: &loadingTextSignatures)
    }
}
