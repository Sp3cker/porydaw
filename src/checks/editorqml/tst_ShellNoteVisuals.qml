import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "GatedVisualsHelpers.js" as Helpers

ShellNoteVisualsSupport {

    function test_drawnNoteFillBorderAndAbuttingSeam() {
        var context = openNotes()
        verify(context.plot !== null, "the fixture mounts a timeline")
        var grid = context.grid
        var roll = findChild(context.surface, "swiftRollInput")
        verify(roll !== null, "the mounted pencil input is available")
        var notes = publishedNotes(grid)
        var ticksPerPixel = grid.ticksPerBeat / grid.beatWidth
        var snap = grid.snapTicks
        var start = Math.ceil((grid.cameraScrollX + roll.width / 3)
                              * ticksPerPixel / snap) * snap
        var span = Math.max(2 * snap, Math.ceil(2 * grid.drawThreshold * ticksPerPixel
                                               / snap) * snap)
        var x = start / ticksPerPixel - grid.cameraScrollX
        var end = (start + 2 * span) / ticksPerPixel - grid.cameraScrollX
        var pitch = -1
        for (var row = Math.ceil(grid.cameraScrollY / grid.rowHeight) + 2;
             row < Math.floor((grid.cameraScrollY + roll.height) / grid.rowHeight) - 2;
             ++row) {
            var candidate = 127 - row
            if (!notes.some(function(note) {
                return note.pitch === candidate && note.tick < start + 2 * span
                    && note.tick + note.duration > start
            })) {
                pitch = candidate
                break
            }
        }
        verify(pitch >= 0 && x > grid.rowHeight && end < roll.width - grid.rowHeight,
               "two adjacent displayed cells have an empty pitch row")
        var y = (127 - pitch + 0.5) * grid.rowHeight - grid.cameraScrollY
        var baseline = grabShell()
        verify(baseline !== null, "the empty row renders before painting")
        var originalIds = notes.map(function(note) { return note.id })
        var inset = Math.min(grid.drawThreshold / 2, snap / ticksPerPixel / 4)
        var firstEnd = (start + span) / ticksPerPixel - grid.cameraScrollX - inset
        mousePress(roll, x + inset, y, Qt.LeftButton)
        mouseMove(roll, firstEnd, y, -1, Qt.LeftButton)
        mouseRelease(roll, firstEnd, y, Qt.LeftButton)
        var first = null
        verify(waitForNative(function() {
            first = publishedNotes(grid).find(function(note) {
                return originalIds.indexOf(note.id) < 0
            })
            return first !== undefined
        }, 5000), "the first cell commits a drawn note")
        var firstImage = grabShell()
        verify(firstImage !== null, "the first pencil note renders a frame")
        var firstItem = noteItem(context.fills, first.id)
        verify(firstItem !== null, "the first drawn note box is mounted")
        var firstDpr = shellDpr(firstImage)
        var firstBox = deviceRect(firstItem, context.plot, firstImage, firstDpr)
        var firstRight = firstBox.x + firstBox.w
        var firstBottom = firstBox.y + firstBox.h
        var escaped = false
        for (var borderY = firstBox.y; borderY <= firstBottom; ++borderY) {
            if (!Helpers.colorsNear(rgb(firstImage, firstRight, borderY),
                                    rgb(baseline, firstRight, borderY), 0)) {
                escaped = true
                break
            }
        }
        for (var borderX = firstBox.x; borderX <= firstRight && !escaped; ++borderX) {
            if (!Helpers.colorsNear(rgb(firstImage, borderX, firstBottom),
                                    rgb(baseline, borderX, firstBottom), 0))
                escaped = true
        }
        verify(!escaped, "note color does not escape its border box")
        var adjacentX = (first.tick + first.duration) / ticksPerPixel - grid.cameraScrollX
        var secondStart = adjacentX + span / ticksPerPixel / 2
        var secondEnd = adjacentX + span / ticksPerPixel
        mousePress(roll, secondStart, y, Qt.LeftButton)
        mouseMove(roll, secondEnd, y, -1, Qt.LeftButton)
        mouseRelease(roll, secondEnd, y, Qt.LeftButton)
        var second = null
        verify(waitForNative(function() {
            second = publishedNotes(grid).find(function(note) {
                return originalIds.indexOf(note.id) < 0 && note.id !== first.id
                    && note.pitch === pitch
            })
            return second !== undefined
        }, 5000), "the next displayed cell commits the second note")
        var secondItem = null
        tryVerify(function() {
            secondItem = noteItem(context.fills, second.id)
            return secondItem !== null
        }, 3000)
        var center = context.plot.mapToItem(roll, secondItem.x + secondItem.width / 2,
                                            secondItem.y + secondItem.height / 2)
        var shift = (second.tick - first.tick - first.duration) / ticksPerPixel
        verify(shift > grid.drawThreshold, "the drawn notes leave a movable snapped gap")
        mousePress(roll, center.x, center.y, Qt.LeftButton)
        mouseMove(roll, center.x - shift, center.y, -1, Qt.LeftButton)
        mouseRelease(roll, center.x - shift, center.y, Qt.LeftButton)
        var secondId = second.id
        verify(waitForNative(function() {
            second = publishedNotes(grid).find(function(note) { return note.id === secondId })
            return second !== undefined && second.tick === first.tick + first.duration
        }, 5000), "the next drawn note abuts the first on the same row")
        var image = grabShell()
        firstItem = noteItem(context.fills, first.id)
        secondItem = noteItem(context.fills, second.id)
        verify(image !== null, "the adjacent pencil notes render a frame")
        verify(secondItem !== null, "the second drawn note box is mounted")
        var dpr = shellDpr(image)
        var box = deviceRect(firstItem, context.plot, image, dpr)
        var nextBox = deviceRect(secondItem, context.plot, image, dpr)
        var cy = box.y + Math.floor(box.h / 2)
        var cx = box.x + Math.floor(box.w / 2)
        var expected = Helpers.channels(grid.palette.noteFill(first.track, first.velocity))
        verify(Helpers.colorsNear(rgb(image, cx, cy), expected),
               "a drawn note paints its interior in the velocity fill")
        var seamStart = box.x
        var seamEnd = nextBox.x + nextBox.w - 1
        var seamPainted = true
        for (var seamX = seamStart; seamX <= seamEnd; ++seamX) {
            if (Helpers.colorsNear(rgb(image, seamX, cy),
                                   rgb(baseline, seamX, cy), 0)) {
                seamPainted = false
                break
            }
        }
        verify(nextBox.x <= box.x + box.w && nextBox.x + nextBox.w > seamStart
               && seamPainted, "abutting notes leave no unpainted gap column")
    }

    function test_noteNameRaster() {
        var context = openNotes()
        context.grid.handleWheel(0, 1600, 0, 0, Qt.ControlModifier, 0,
                                 false, 0, context.plot.height / 2)
        context.grid.setCameraHScroll(context.grid.cameraMinHScroll)
        var roll = findChild(context.surface, "swiftRollInput")
        verify(roll !== null, "the roll pointer surface is mounted")
        var ghost = null
        var lane = null
        var step = context.plot.height / 2
        var attempts = Math.ceil(context.grid.cameraMaxVScroll / step) + 1
        for (var index = 0; index <= attempts; ++index) {
            context.grid.setCameraVScroll(Math.min(context.grid.cameraMaxVScroll, index * step))
            var frame = grabShell()
            if (frame === null)
                continue
            ghost = trackFace(context, frame, true)
            if (ghost === null)
                continue
            var grid = context.grid
            var ppt = grid.beatWidth / grid.ticksPerBeat
            var snap = grid.snapTicks
            var tick = Math.ceil(((grid.cameraScrollX + 24) / ppt) / snap) * snap
            if ((tick + 12 * snap) * ppt - grid.cameraScrollX > context.plot.width - 24)
                continue
            var occupied = publishedNotes(grid)
            var first = Math.ceil(grid.cameraScrollY / grid.rowHeight) + 2
            var last = Math.floor((grid.cameraScrollY + context.plot.height)
                                  / grid.rowHeight) - 2
            for (var row = first; row <= last; ++row) {
                var pitch = 127 - row
                if (!occupied.some(function(n) { return n.pitch === pitch })) {
                    lane = { tick: tick, pitch: pitch }
                    break
                }
            }
            if (lane !== null)
                break
        }
        verify(ghost !== null && lane !== null,
               "a visible ghost and free wide-note lane share the fixture viewport")
        var beforeCount = publishedNotes(context.grid).length
        var x0 = lane.tick * ppt - context.grid.cameraScrollX + 1
        var x1 = (lane.tick + 12 * snap) * ppt - context.grid.cameraScrollX - 1
        var y0 = (127 - lane.pitch + 0.5) * context.grid.rowHeight
            - context.grid.cameraScrollY
        mousePress(roll, x0, y0, Qt.LeftButton)
        mouseMove(roll, x1, y0, -1, Qt.LeftButton)
        mouseRelease(roll, x1, y0, Qt.LeftButton)
        verify(waitForNative(function() {
            return publishedNotes(context.grid).length === beforeCount + 1
        }, 5000), "the mounted roll seeds a wide name-bearing note")
        var baseline = grabShell()
        verify(baseline !== null, "the unlabeled roll renders a frame")
        shell.shellPresenter.activate("view.note_names")
        verify(waitForNative(function() { return context.session.noteNameMode }, 5000),
               "the menu enables note-name rendering")
        var named = grabShell()
        verify(named !== null, "the named roll renders a frame")
        verify(regionIdentical(baseline, named, ghost.rect),
               "note-name mode changes no ghost note pixel")
        var notes = publishedNotes(context.grid)
        var inkPixels = 0
        for (var i = 0; i < notes.length; ++i) {
            if (notes[i].track !== context.grid.trackIndex)
                continue
            var item = noteItem(context.fills, notes[i].id)
            if (!item)
                continue
            var noteRect = deviceRect(item, context.plot, named, shellDpr(named))
            if (noteRect.w <= 20 || noteRect.h <= 12)
                continue
            var noteFill = context.grid.palette.noteFill(notes[i].track, notes[i].velocity)
            var ink = Helpers.channels(context.grid.palette.noteLabelInk(noteFill))
            for (var y = noteRect.y + 2; y < noteRect.y + noteRect.h - 2; ++y)
                for (var x = noteRect.x + 2; x < noteRect.x + noteRect.w - 2; ++x) {
                    var painted = rgb(named, x, y)
                    if (Helpers.colorsNear(painted, ink)
                            && !Helpers.colorsNear(rgb(baseline, x, y), ink)
                            && contrast(painted, Helpers.channels(noteFill)) >= 2.5)
                        ++inkPixels
                }
        }
        verify(inkPixels > 0, "wide-note label ink contrasts with its fill")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return publishedNotes(context.grid).length === beforeCount
        }, 5000), "undo removes the seeded name fixture note")
    }

    function test_dpr2SmallFontThinning() {
        if (Screen.devicePixelRatio !== 2) {
            skip("the physical border-thinning capture requires dpr2")
            return
        }
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads for dpr2")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        verify(probe.prepareUnsignedSong(bootstrap.projectRoot, "mus_route101", 24),
               "the dpr2 song copy has its explicit signature removed")
        unsignedSongPrepared = true
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() { return session.songOpen }, 30000),
               "Route 101 loads for the physical dpr2 ruler capture")
        var surface = null
        verify(waitForNative(function() {
            surface = selectedSurface()
            return surface !== null && surface.visible
        }, 10000), "the dpr2 roll is mounted")
        var grid = surface.gridModel
        var plot = findChild(surface, "timelineQuickRollPlot")
        var fills = findChild(surface, "timelineRendererPlot")
        verify(plot !== null && fills !== null, "the dpr2 plot and note fills are mounted")
        verify(waitForNative(function() { return grid.renderedNoteCount > 0 }, 5000),
               "the dpr2 roll publishes notes")
        var rulerContext = { surface: surface, grid: grid, plot: plot, session: session }
        var physicalRuler = unsignedRulerJourney(rulerContext, true)
        var ruler = findChild(surface, "timelineQuickRuler")
        verify(Math.abs(physicalRuler.width - ruler.width * 2) <= 1,
               "the mounted unsigned ruler captures its full physical dpr2 width")
        shell.destroy()
        shell = smallFontShellComponent.createObject(null)
        verify(shell !== null, "the production small-font ShellWindow loads for dpr2")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() { return session.songOpen }, 30000),
               "Route 101 loads for the dpr2 small-font note capture")
        surface = null
        verify(waitForNative(function() {
            surface = selectedSurface()
            return surface !== null && surface.visible
        }, 10000), "the dpr2 small-font roll is mounted")
        grid = surface.gridModel
        plot = findChild(surface, "timelineQuickRollPlot")
        fills = findChild(surface, "timelineRendererPlot")
        verify(plot !== null && fills !== null,
               "the dpr2 small-font plot and note fills are mounted")
        verify(waitForNative(function() { return grid.renderedNoteCount > 0 }, 5000),
               "the dpr2 small-font roll publishes notes")
        grid.performCommand(4)
        verify(waitForNative(function() {
            var notes = publishedNotes(grid)
            return notes && notes.some(function(note) { return note.selected })
        }, 5000), "the dpr2 roll publishes a selected note")
        var dpr = Screen.devicePixelRatio
        verify(waitForNative(function() { return grid.baseFontPx === 4.0 }, 5000),
               "the dpr2 small-font viewport is published")
        var originalRowHeight = grid.rowHeight
        grid.handleWheel(0, -1600, 0, 0, Qt.ControlModifier, 0,
                         false, plot.width / 2, plot.height / 2)
        verify(waitForNative(function() { return grid.rowHeight < originalRowHeight }, 5000),
               "the dpr2 small-font roll zooms into the thinning height")
        var anchor = publishedNotes(grid).find(function(note) { return note.selected })
        var targetScroll = Math.max(0, Math.min(
                    grid.cameraMaxVScroll,
                    (127 - anchor.pitch + 0.5) * grid.rowHeight - plot.height / 2))
        grid.setCameraVScroll(targetScroll)
        verify(waitForNative(function() {
            return Math.abs(grid.cameraScrollY - targetScroll) < 0.01
        }, 5000), "the dpr2 selected note row is centered")
        verify(waitForNative(function() { return grid.renderedNoteCount > 0 }, 5000),
               "the dpr2 small-font plot still publishes notes")
        verify(waitForRendering(plot, 3000), "the dpr2 note plot has rendered")
        var notes = publishedNotes(grid)
        var ringRequest = Math.max(1, Math.round(grid.baseFontPx * (1.0 / 8.0) * dpr))
        var borderRequest = Math.max(1, Math.round(dpr))
        var small = null
        var bestArea = Infinity
        for (var n = 0; n < notes.length; ++n) {
            if (!notes[n].selected)
                continue
            var item = noteItem(fills, notes[n].id)
            if (!item)
                continue
            var topLeft = Qt.point(item.x, item.y)
            if (topLeft.x < 1 || topLeft.y < 1
                    || topLeft.x + item.width > plot.width - 1
                    || topLeft.y + item.height > plot.height - 1)
                continue
            var width = Math.round(item.width * dpr)
            var height = Math.round(item.height * dpr)
            var ring = Helpers.fittedFrameThickness(width, height, ringRequest, 0)
            var border = Helpers.fittedFrameThickness(width, height, borderRequest, ring)
            if (ring > 0 && border > 0 && width * height < bestArea) {
                small = { note: notes[n], ring: ring, border: border }
                bestArea = width * height
            }
        }
        verify(small !== null && borderRequest > 1,
               "the dpr2 small-font viewport exposes a selected note whose border request exceeds one pixel")
        verify(small.border >= 1 && small.border < Math.max(1, Math.round(dpr)),
               "the dpr2 selected note thins its physical border without vanishing")
        verify(small.border < borderRequest,
               "the small note exercises physical border thinning")
        var capture = null
        verify(plot.grabToImage(function(result) { capture = result }),
               "the dpr2 plot accepts a physical-pixel capture")
        tryVerify(function() { return capture !== null }, 3000)
        verify(capture.saveToFile(bootstrap.projectRoot + "/notevisuals-dpr2-small-font.png"),
               "the dpr2 selected note frame is saved")
        var selectedItem = noteItem(fills, small.note.id)
        var noteOrigin = Qt.point(selectedItem.x, selectedItem.y)
        var physical = { x: Math.floor(noteOrigin.x * dpr),
                         y: Math.floor(noteOrigin.y * dpr),
                         w: Math.ceil((noteOrigin.x + selectedItem.width) * dpr)
                            - Math.floor(noteOrigin.x * dpr),
                         h: Math.ceil((noteOrigin.y + selectedItem.height) * dpr)
                            - Math.floor(noteOrigin.y * dpr) }
        var reader = physicalCaptureReader.createObject(plot)
        verify(reader !== null, "the physical DPR2 capture has an image reader")
        tryCompare(reader, "available", true, 3000)
        var imageUrl = "file://" + bootstrap.projectRoot + "/notevisuals-dpr2-small-font.png"
        reader.loadImage(imageUrl)
        tryVerify(function() { return reader.isImageLoaded(imageUrl) }, 3000)
        var pixels = reader.getContext("2d").createImageData(imageUrl)
        verify(pixels !== null && Math.abs(pixels.width - plot.width * dpr) <= 1
               && Math.abs(pixels.height - plot.height * dpr) <= 1,
               "the DPR2 note capture retains physical-sized image data: "
               + (pixels ? pixels.width + "x" + pixels.height : "null")
               + " expected " + Math.round(plot.width * dpr)
               + "x" + Math.round(plot.height * dpr))
        var capturedPixels = {
            red: function(x, y) { return pixels.data[(y * pixels.width + x) * 4] },
            green: function(x, y) { return pixels.data[(y * pixels.width + x) * 4 + 1] },
            blue: function(x, y) { return pixels.data[(y * pixels.width + x) * 4 + 2] }
        }
        var physicalRect = physical
        var ringInk = Helpers.channels(grid.palette.selectionRing)
        var borderInk = Helpers.channels(grid.palette.noteBorder)
        var centerX = physicalRect.x + Math.floor(physicalRect.w / 2)
        var topEdge = -1, bottomEdge = -1
        for (var offset = -1; offset <= 1; ++offset) {
            var topY = physicalRect.y + offset
            var bottomY = physicalRect.y + physicalRect.h - 1 + offset
            if (topEdge < 0 && Helpers.colorsNear(rgb(capturedPixels, centerX, topY), ringInk))
                topEdge = topY
            if (Helpers.colorsNear(rgb(capturedPixels, centerX, bottomY), ringInk))
                bottomEdge = bottomY
        }
        verify(topEdge >= 0 && bottomEdge > topEdge,
               "the captured DPR2 selected ring brackets the note's physical bounds")
        physicalRect.y = topEdge
        physicalRect.h = bottomEdge - topEdge + 1
        var ringFailure = frameFailure(capturedPixels, physicalRect, 0,
                                       small.ring, ringInk, "DPR2 outer ring")
        verify(ringFailure === "",
               "the captured small-font DPR2 note paints its selected ring: " + ringFailure)
        var borderFailure = frameFailure(capturedPixels, physicalRect, small.ring,
                                         small.border, borderInk, "DPR2 inset border")
        verify(borderFailure === "",
               "the captured small-font DPR2 note paints its fitted inset border: "
               + borderFailure)
        var face = rgb(capturedPixels,
                       physicalRect.x + Math.floor(physicalRect.w / 2),
                       physicalRect.y + Math.floor(physicalRect.h / 2))
        verify(Helpers.colorsNear(face, Helpers.channels(
                   grid.palette.noteFill(small.note.track, small.note.velocity))),
               "the captured small-font DPR2 note keeps a face inside the thinned border")
        reader.destroy()
    }
}
