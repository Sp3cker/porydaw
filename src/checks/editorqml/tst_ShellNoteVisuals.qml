import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "GatedVisualsHelpers.js" as Helpers
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellNoteVisuals"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    property var grabbed: null

    ShellQmlBootstrap { id: bootstrap }
    GatedVisualsProbe { id: probe }

    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
    }

    function cleanupTestCase() {
        verify(bootstrap.clearSettings(), "removed only the private native settings")
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function cleanup() {
        grabbed = null
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "the close-all walk reaches the dirty gate or completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() {
                return shell.shellPresenter.closeReady
            }, 5000), "teardown waits for scene destruction and grid detach")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function selectedSurface() {
        var pages = shell.sceneLoader.item
        if (!pages)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(pages, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function grabShell() {
        var image = grabImage(shell.contentItem)
        if (image.width <= 0 || image.height <= 0)
            return null
        return image
    }
    function shellDpr(image) { return image.width / shell.contentItem.width }
    function win(item, x, y) {
        var corg = shell.contentItem.mapToItem(null, 0, 0)
        var w = item.mapToItem(null, x, y)
        return { x: w.x - corg.x, y: w.y - corg.y }
    }

    function publishedNotes(grid) {
        var parsed = JSON.parse(grid.noteSummary)
        for (var i = 0; i < parsed.length; ++i) {
            var e = parsed[i]
            if (!(e.id > 0) || typeof e.track !== "number" || typeof e.velocity !== "number")
                return null
        }
        return parsed
    }

    function noteItem(fills, id) {
        return findChild(fills, "gridNote_" + id)
    }

    function deviceRect(item, plot, image, dpr) {
        var topLeft = win(item, 0, 0)
        var size = win(item, item.width, item.height)
        var r = { x: Math.round(topLeft.x * dpr), y: Math.round(topLeft.y * dpr),
                  w: Math.max(1, Math.round((size.x - topLeft.x) * dpr)),
                  h: Math.max(1, Math.round((size.y - topLeft.y) * dpr)) }
        r.x = Math.max(0, r.x)
        r.y = Math.max(0, r.y)
        r.w = Math.min(r.w, image.width - r.x)
        r.h = Math.min(r.h, image.height - r.y)
        return r
    }

    function visibleNote(fills, plot, image, dpr, notes, selected) {
        var best = null
        var bestArea = -1
        for (var i = 0; i < notes.length; ++i) {
            var note = notes[i]
            if (selected !== undefined && note.selected !== selected)
                continue
            var item = noteItem(fills, note.id)
            if (!item || !item.visible)
                continue
            var topLeft = item.mapToItem(plot, 0, 0)
            var bottomRight = item.mapToItem(plot, item.width, item.height)
            if (topLeft.x < 1 || topLeft.y < 1
                    || bottomRight.x > plot.width - 1 || bottomRight.y > plot.height - 1)
                continue
            var rect = deviceRect(item, plot, image, dpr)
            var area = rect.w * rect.h
            if (rect.w >= 5 && rect.h >= 5 && area > bestArea) {
                best = { note: note, item: item, rect: rect }
                bestArea = area
            }
        }
        return best
    }

    function frameFailure(image, rect, inset, thickness, expected, label) {
        var cx = rect.x + Math.floor(rect.w / 2)
        for (var pixel = 0; pixel < thickness; ++pixel) {
            var off = inset + pixel
            var points = [[cx, rect.y + off], [cx, rect.y + rect.h - 1 - off]]
            for (var i = 0; i < points.length; ++i) {
                var p = [image.red(points[i][0], points[i][1]),
                         image.green(points[i][0], points[i][1]),
                         image.blue(points[i][0], points[i][1])]
                if (!Helpers.colorsNear(p, expected))
                    return label + " at device pixel (" + points[i][0] + "," + points[i][1]
                        + "): expected " + Helpers.hexOf(expected) + ", actual " + Helpers.hexOf(p)
            }
        }
        return ""
    }

    function blackFrameFailure(image, rect, inset, thickness, label) {
        var cx = rect.x + Math.floor(rect.w / 2)
        for (var pixel = 0; pixel < thickness; ++pixel) {
            var off = inset + pixel
            var points = [[cx, rect.y + off], [cx, rect.y + rect.h - 1 - off]]
            for (var i = 0; i < points.length; ++i) {
                var p = [image.red(points[i][0], points[i][1]),
                         image.green(points[i][0], points[i][1]),
                         image.blue(points[i][0], points[i][1])]
                if (!Helpers.isPhysicalBlack(p))
                    return label + " at device pixel (" + points[i][0] + "," + points[i][1]
                        + "): expected physical black, actual " + Helpers.hexOf(p)
            }
        }
        return ""
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
        var fills = findChild(surface, "timelineQuickPianoNoteFills")
        verify(plot !== null, "the roll plot is mounted")
        verify(fills !== null, "the note fill layer is mounted")

        var unselectedImage = grabShell()
        verify(unselectedImage !== null, "the unselected roll renders a frame")
        var dpr = shellDpr(unselectedImage)
        var notes = publishedNotes(grid)
        verify(notes !== null, "the note summary parses as note entries")
        var unselected = visibleNote(fills, plot, unselectedImage, dpr, notes, false)
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
        verify(selectedItem && selectedItem.visible, "the selected note delegate stays visible")
        var selectedRect = deviceRect(selectedItem, plot, selectedImage, dpr)
        var ringRequest = Math.max(1, Math.round(grid.baseFontPx * (1.0 / 8.0) * dpr))
        var ring = Helpers.fittedFrameThickness(selectedRect.w, selectedRect.h, ringRequest, 0)
        verify(ring > 0, "the selected note retains a visible selection ring")
        var expectedRing = Helpers.channels(grid.palette.selectionRing)
        verify(frameFailure(selectedImage, selectedRect, 0, ring, expectedRing,
                            "selected note " + unselected.note.id + " outer ring") === "",
                "the selection ring uses the selection role color")
        var selectedBorder = Helpers.fittedFrameThickness(
                    selectedRect.w, selectedRect.h, borderRequest, ring)
        verify(selectedBorder > 0, "the selected note keeps room for its inset black border")
        verify(blackFrameFailure(selectedImage, selectedRect, ring, selectedBorder,
                                 "selected note " + unselected.note.id
                                 + " lost its inset black border") === "",
                "the inset black border renders inside the ring")
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
        grid.configureViewport(plot.width, plot.height, smallFontPx, dpr)
        verify(waitForNative(function() { return grid.baseFontPx === smallFontPx }, 5000),
               "the small-font viewport is published")
        grid.resetCameraScroll()
        var maxSmallScrollY = Math.max(0, 128.0 * grid.rowHeight - plot.height)
        verify(waitForNative(function() {
            return Math.abs(grid.cameraMaxVScroll - maxSmallScrollY) < 0.01
        }, 5000), "the published vertical bound is the projected row height")
        verify(waitForNative(function() {
            var count = 0
            for (var i = 0; i < fills.children.length; ++i) {
                var c = fills.children[i]
                if (c && c.fillColor !== undefined && c.visible)
                    ++count
            }
            return count > 0
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
                if (!item || !item.visible)
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
