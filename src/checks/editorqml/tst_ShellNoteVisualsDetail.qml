import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "GatedVisualsHelpers.js" as Helpers

ShellNoteVisualsSupport {
    function test_velocityValueRaster() {
        var context = openNotes()
        var roll = findChild(context.surface, "swiftRollInput")
        verify(roll !== null, "the roll pointer surface is mounted")
        var initial = grabShell()
        verify(initial !== null, "the idle roll renders a frame")
        var target = trackFace(context, initial, false)
        verify(target !== null, "a visible note guards the velocity drag")
        var anchor = Qt.point(target.item.x + target.item.width / 2, target.item.y)
        context.grid.handleWheel(0, 600, 0, 0, 0, 0, false, anchor.x, 0)
        var idle = grabShell()
        verify(idle !== null, "the zoomed idle roll renders a frame")
        target = trackFace(context, idle, false)
        verify(target !== null && target.rect.w > 45 && target.rect.h > 8,
               "a visible wide note guards the velocity drag")
        var summary = context.grid.fetchNoteSummary()
        var dpr = shellDpr(idle)
        var center = context.plot.mapToItem(roll, target.item.x + target.item.width / 2,
                                            target.item.y + target.item.height / 2)
        var px = center.x
        var py = center.y
        mousePress(roll, px, py, Qt.LeftButton, Qt.ControlModifier)
        mouseMove(roll, px, py - context.grid.dragDistance - 2,
                  -1, Qt.LeftButton, Qt.ControlModifier)
        verify(waitForNative(function() {
            return context.grid.statusText.indexOf("velocity") >= 0
        }, 5000), "the control gesture enters velocity preview")
        var dragged = grabShell()
        verify(dragged !== null, "the velocity drag renders a frame")
        var inkPixels = 0
        var fillPixel = rgb(idle, target.rect.x + Math.floor(target.rect.w / 2),
                            target.rect.y + Math.floor(target.rect.h / 2))
        for (var iy = target.rect.y + Math.ceil(target.rect.h / 4);
             iy < target.rect.y + Math.floor(3 * target.rect.h / 4); ++iy)
            for (var ix = target.rect.x + Math.ceil(target.rect.w / 4);
                 ix < target.rect.x + Math.floor(3 * target.rect.w / 4); ++ix)
                if (!Helpers.colorsNear(rgb(idle, ix, iy), rgb(dragged, ix, iy), 0)
                        && contrast(rgb(dragged, ix, iy), fillPixel) >= 2.5)
                    ++inkPixels
        verify(inkPixels > 2, "velocity drag renders value ink inside the note box")
        var plotRect = deviceRect(context.plot, context.plot, idle, dpr)
        var margin = target.rect.h
        var left = Math.max(plotRect.x, target.rect.x - margin)
        var top = Math.max(plotRect.y, target.rect.y - margin)
        var right = Math.min(plotRect.x + plotRect.w, target.rect.x + target.rect.w + margin)
        var bottom = Math.min(plotRect.y + plotRect.h, target.rect.y + target.rect.h + margin)
        for (var y = top; y < bottom; ++y)
            for (var x = left; x < right; ++x) {
                var inBox = x >= target.rect.x && x < target.rect.x + target.rect.w
                    && y >= target.rect.y && y < target.rect.y + target.rect.h
                if (!inBox)
                    verify(Helpers.colorsNear(rgb(idle, x, y), rgb(dragged, x, y), 0),
                           "velocity drag changes no pixel outside the note box clip at "
                           + x + "," + y)
            }
        mouseRelease(roll, px, py - context.grid.dragDistance - 2,
                     Qt.LeftButton, Qt.ControlModifier)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            var now = publishedNotes(context.grid)
            return now && now.length === JSON.parse(summary).length
                && now.some(function(n) {
                    return n.id === target.note.id && n.velocity === target.note.velocity
                })
        }, 5000), "undo restores the original note document")
    }

    function test_tinyNoteFrameRaster() {
        var context = openNotes(5)
        var grid = context.grid
        var plot = context.plot
        var zoomDelta = Math.round(1200 * Math.log(grid.baseFontPx / grid.rowHeight) / Math.LN2)
        grid.handleWheel(0, zoomDelta, 0, 0, Qt.ControlModifier, 0,
                         false, plot.width / 2, plot.height / 2)
        verify(waitForNative(function() {
            return grid.baseFontPx === 5 && Math.abs(grid.rowHeight - grid.baseFontPx) < 0.01
        }, 5000), "the mounted five-pixel key height matches the small font: "
               + grid.baseFontPx + "/" + grid.rowHeight)
        var notes = publishedNotes(grid)
        var target = notes.find(function(note) {
            var x = note.tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
            return !note.ghost && !note.selected && note.tick > grid.ticksPerBeat
                && x > grid.baseFontPx * 2 && x < plot.width - grid.baseFontPx * 3
        })
        verify(target !== undefined, "a painted tiny note has a visible time cell")
        var scrollY = Math.max(0, Math.min(grid.cameraMaxVScroll,
                (127 - target.pitch + 0.5) * grid.rowHeight - plot.height / 2))
        grid.setCameraVScroll(scrollY)
        var image = grabShell()
        verify(image !== null, "the five-pixel-key roll renders a frame")
        var item = noteItem(context.fills, target.id)
        verify(item !== null, "the tiny note is mounted in the roll")
        var rect = deviceRect(item, plot, image, shellDpr(image))
        verify(rect.h >= 3 && rect.h <= grid.baseFontPx * shellDpr(image),
               "the mounted tiny note spans a border and a face: rect=" + JSON.stringify(rect)
               + ", row=" + grid.rowHeight + ", font=" + grid.baseFontPx
               + ", dpr=" + shellDpr(image))
        var fitted = Helpers.fittedFrameThickness(rect.w, rect.h,
                                                  Math.max(1, Math.round(shellDpr(image))), 0)
        verify(fitted > 0 && rect.h > 2 * fitted,
               "the tiny raster has room inside its fitted border")
        var border = frameFailure(image, rect, 0, fitted,
                                  Helpers.channels(grid.palette.noteBorder), "tiny frame")
        verify(border === "", "the tiny note paints its fitted top and bottom border: " + border)
        var cx = rect.x + Math.floor(rect.w / 2)
        var cy = rect.y + Math.floor(rect.h / 2)
        verify(Helpers.colorsNear(rgb(image, cx, cy), Helpers.channels(probe.noteFace(
                   target.track, target.velocity, grid.palette.noteVelocityZero))),
               "the tiny note paints its face between the thin borders")
    }

    function test_noteRasterParity() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songOpen, "Route 101 loads from the staged project")
        var surface = selectedSurface()
        verify(surface !== null, "the selected tab page is mounted")
        var grid = surface.gridModel
        verify(waitForNative(function() { return grid.renderedNoteCount > 0 }, 5000),
               "the roll publishes notes")
        var plot = findChild(surface, "timelineQuickRollPlot")
        var fills = findChild(surface, "timelineRendererPlot")
        verify(plot !== null, "the roll plot is mounted")
        verify(fills !== null, "the note fill layer is mounted")

        grid.handleWheel(0, -120, 0, 0, Qt.ControlModifier, 0,
                         false, plot.width / 2, plot.height / 2)
        verify(waitForNative(function() {
            return Math.abs(grid.rowHeight - Math.round(grid.rowHeight)) > 0.1
        }, 5000), "the mounted note frame uses a fractional key height")

        var unselectedImage = grabShell()
        verify(unselectedImage !== null, "the unselected roll renders a frame")
        var dpr = shellDpr(unselectedImage)
        var notes = publishedNotes(grid)
        verify(notes !== null, "the note summary parses as note entries")
        var frameNotes = notes.filter(function(note) {
            return note.tick > grid.ticksPerBeat
                && note.tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
                    > -grid.cameraScrollX + grid.baseFontPx * 2
        })
        var unselected = visibleNote(fills, plot, unselectedImage, dpr, frameNotes, false)
        verify(unselected !== null, "a fully visible unselected note is available for probing")

        var expectedFace = Helpers.channels(
                    probe.noteFace(unselected.note.track, unselected.note.velocity,
                                   grid.palette.noteVelocityZero))
        var unselectedFace = [unselectedImage.red(
                    unselected.rect.x + Math.floor(unselected.rect.w / 2),
                    unselected.rect.y + Math.floor(unselected.rect.h / 2)),
                unselectedImage.green(
                    unselected.rect.x + Math.floor(unselected.rect.w / 2),
                    unselected.rect.y + Math.floor(unselected.rect.h / 2)),
                unselectedImage.blue(
                    unselected.rect.x + Math.floor(unselected.rect.w / 2),
                    unselected.rect.y + Math.floor(unselected.rect.h / 2))]
        verify(Helpers.colorsNear(unselectedFace, expectedFace),
                "note " + unselected.note.id + " face follows the track/velocity contract: expected "
                + Helpers.hexOf(expectedFace) + ", actual " + Helpers.hexOf(unselectedFace))

        var borderRequest = Math.max(1, Math.round(dpr))
        var unselectedBorder = Helpers.fittedFrameThickness(
                    unselected.rect.w, unselected.rect.h, borderRequest, 0)
        compare(unselectedBorder, borderRequest, "the unselected border keeps its requested width")
        verify(blackFrameFailure(unselectedImage, unselected.rect, 0, unselectedBorder,
                                 "unselected note " + unselected.note.id
                                 + " lost its display-scaled black border") === "",
                "the unselected black border renders")
        var unselectedSides = sideFrameFailure(
                    unselectedImage, unselected.rect, 0, unselectedBorder,
                    Helpers.channels(grid.palette.noteBorder), "unselected side borders")
        verify(unselectedSides === "",
               "the unselected note bounds its face on both sides: " + unselectedSides)
        var below = rgb(unselectedImage,
                        unselected.rect.x + Math.floor(unselected.rect.w / 2),
                        unselected.rect.y + unselected.rect.h)
        verify(!Helpers.colorsNear(below, expectedFace),
               "the unselected note face stops below its bottom border")

        grid.performCommand(4)
        verify(waitForNative(function() {
            var after = publishedNotes(grid)
            for (var i = 0; i < after.length; ++i)
                if (after[i].id === unselected.note.id)
                    return after[i].selected
            return false
        }, 5000), "select-all publishes the probed note as selected")

        var selectedImage = grabShell()
        verify(selectedImage !== null, "the selected roll renders a frame")
        var selectedItem = noteItem(fills, unselected.note.id)
        verify(selectedItem !== null, "the selected note delegate stays visible")
        var selectedRect = deviceRect(selectedItem, plot, selectedImage, dpr)
        var ringRequest = Math.max(1, Math.round(grid.baseFontPx * (1.0 / 8.0) * dpr))
        var ring = Helpers.fittedFrameThickness(selectedRect.w, selectedRect.h, ringRequest, 0)
        verify(ring > 0, "the selected note retains a visible selection ring")
        var expectedRing = Helpers.channels(grid.palette.selectionRing)
        verify(frameFailure(selectedImage, selectedRect, 0, ring, expectedRing,
                            "selected note " + unselected.note.id + " outer ring") === "",
                "the selection ring uses the selection role color")
        var ringSides = sideFrameFailure(selectedImage, selectedRect, 0, ring,
                                         expectedRing, "selected side ring")
        verify(ringSides === "", "the selection ring continues around both side edges: "
               + ringSides)
        var selectedBorder = Helpers.fittedFrameThickness(
                    selectedRect.w, selectedRect.h, borderRequest, ring)
        verify(selectedBorder > 0, "the selected note keeps room for its inset black border")
        verify(blackFrameFailure(selectedImage, selectedRect, ring, selectedBorder,
                                 "selected note " + unselected.note.id
                                 + " lost its inset black border") === "",
                "the inset black border renders inside the ring")
        var insetSides = sideFrameFailure(
                    selectedImage, selectedRect, ring, selectedBorder,
                    Helpers.channels(grid.palette.noteBorder), "selected inset sides")
        verify(insetSides === "", "the selected inset border paints both left and right edges: "
               + insetSides)
        var darkFrame = Helpers.channels(grid.palette.noteBorder)
        var topInset = edgeFrameFailure(selectedImage, selectedRect, ring,
                                        selectedBorder, darkFrame, "top")
        verify(topInset === "", "the selected inset top border paints: " + topInset)
        var bottomInset = edgeFrameFailure(selectedImage, selectedRect, ring,
                                           selectedBorder, darkFrame, "bottom")
        verify(bottomInset === "", "the selected inset bottom border paints: " + bottomInset)
        var leftInset = edgeFrameFailure(selectedImage, selectedRect, ring,
                                         selectedBorder, darkFrame, "left")
        verify(leftInset === "", "the selected inset left border paints: " + leftInset)
        var rightInset = edgeFrameFailure(selectedImage, selectedRect, ring,
                                          selectedBorder, darkFrame, "right")
        verify(rightInset === "", "the selected inset right border paints: " + rightInset)
        verify(!Helpers.colorsNear(rgb(selectedImage,
                                       selectedRect.x + Math.floor(selectedRect.w / 2),
                                       selectedRect.y + ring), expectedRing),
               "the selection ring stops at its display-scaled inset")
        var selectedFace = [selectedImage.red(
                    selectedRect.x + Math.floor(selectedRect.w / 2),
                    selectedRect.y + Math.floor(selectedRect.h / 2)),
                selectedImage.green(
                    selectedRect.x + Math.floor(selectedRect.w / 2),
                    selectedRect.y + Math.floor(selectedRect.h / 2)),
                selectedImage.blue(
                    selectedRect.x + Math.floor(selectedRect.w / 2),
                    selectedRect.y + Math.floor(selectedRect.h / 2))]
        verify(Helpers.colorsNear(selectedFace, unselectedFace)
               && Helpers.colorsNear(selectedFace, expectedFace),
                "the selection frame preserves the note face")

        var smallFontPx = borderRequest > 1 ? 4.0 : 7.0
        cleanup()
        var smallContext = openNotes(smallFontPx)
        grid = smallContext.grid
        plot = smallContext.plot
        fills = smallContext.fills
        grid.performCommand(4)
        verify(waitForNative(function() { return grid.baseFontPx === smallFontPx }, 5000),
               "the small-font viewport is published")
        grid.resetCameraScroll()
        var maxSmallScrollY = Math.max(0, 128.0 * grid.rowHeight - plot.height)
        verify(waitForNative(function() {
            return Math.abs(grid.cameraMaxVScroll - maxSmallScrollY) < 0.01
        }, 5000), "the published vertical bound is the projected row height")
        verify(waitForNative(function() {
            return publishedNotes(grid).some(function(note) {
                return noteItem(fills, note.id) !== null
            })
        }, 5000), "the small viewport still draws note fills")
        var smallImage = grabShell()
        verify(smallImage !== null, "the small-font roll renders a frame")
        var smallNotes = publishedNotes(grid)
        verify(smallNotes !== null, "the small-font note summary parses")
        var smallRingRequest = Math.max(
                    1, Math.round(grid.baseFontPx * (1.0 / 8.0) * (shellDpr(smallImage))))
        var smallBorderRequest = Math.max(1, Math.round(shellDpr(smallImage)))
        var small = null
        if (smallBorderRequest > 1) {
            var bestArea = -1
            for (var n = 0; n < smallNotes.length; ++n) {
                if (!smallNotes[n].selected)
                    continue
                var item = noteItem(fills, smallNotes[n].id)
                if (!item)
                    continue
                var rect = deviceRect(item, plot, smallImage, shellDpr(smallImage))
                var tryRing = Helpers.fittedFrameThickness(rect.w, rect.h, smallRingRequest, 0)
                var tryBorder = Helpers.fittedFrameThickness(
                            rect.w, rect.h, smallBorderRequest, tryRing)
                if (tryRing > 0 && tryBorder > 0 && tryBorder < smallBorderRequest
                        && rect.w * rect.h > bestArea) {
                    small = { note: smallNotes[n], rect: rect }
                    bestArea = rect.w * rect.h
                }
            }
            verify(small !== null, "a thinned selected note is exposed at the small font")
        } else {
            small = visibleNote(fills, plot, smallImage, shellDpr(smallImage),
                                smallNotes, true)
            verify(small !== null, "a fully visible selected note is exposed at the small font")
        }
        var smallRing = Helpers.fittedFrameThickness(
                    small.rect.w, small.rect.h, smallRingRequest, 0)
        var smallBorder = Helpers.fittedFrameThickness(
                    small.rect.w, small.rect.h, smallBorderRequest, smallRing)
        verify(smallRing > 0 && smallBorder > 0,
                "the small note preserves both ring and inset border")
        if (smallBorderRequest > 1)
            verify(smallBorder < smallBorderRequest,
                    "the small note exercises physical border thinning")
        verify(frameFailure(smallImage, small.rect, 0, smallRing, expectedRing,
                            "small selected note " + small.note.id + " fitted ring") === "",
                "the small fitted selection ring renders")
        verify(blackFrameFailure(smallImage, small.rect, smallRing, smallBorder,
                                 "small selected note " + small.note.id + " border") === "",
                "the small border thins instead of vanishing")
        var smallExpectedFace = Helpers.channels(
                    probe.noteFace(small.note.track, small.note.velocity,
                                   grid.palette.noteVelocityZero))
        var smallFace = [smallImage.red(small.rect.x + Math.floor(small.rect.w / 2),
                                        small.rect.y + Math.floor(small.rect.h / 2)),
                smallImage.green(small.rect.x + Math.floor(small.rect.w / 2),
                                 small.rect.y + Math.floor(small.rect.h / 2)),
                smallImage.blue(small.rect.x + Math.floor(small.rect.w / 2),
                                small.rect.y + Math.floor(small.rect.h / 2))]
        verify(Helpers.colorsNear(smallFace, smallExpectedFace),
                "the small frame preserves the note face")
    }

}
