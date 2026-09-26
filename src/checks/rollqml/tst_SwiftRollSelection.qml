import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

TestCase {
    id: testCase

    name: "SwiftRollSelection"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var overlay: null
    property string openFailure: ""

    RollQmlBootstrap {
        id: bootstrap

        ApplicationSession { id: session }
    }

    Connections {
        target: session

        function onOpenFailed(message) { testCase.openFailure = message }
        function onOperationFailed(message) { testCase.openFailure = message }
    }

    Component {
        id: overlayComponent

        SwiftRollOverlay {
            property var appSession: session
        }
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function initTestCase() {
        bootstrap.seedDrawerPreferences(false, true, true, 0)
        verify(bootstrap.start("mus_route101"),
               "the staged route101 project starts opening")
        verify(waitForNative(function() {
            return session.songOpen || testCase.openFailure.length > 0
        }, 30000), "the staged route101 song opened" + testCase.openDiagnostics())
        testCase.mountOverlay()
    }

    function openDiagnostics() {
        var details = ["projectRoot=" + bootstrap.projectRoot,
                       "label=mus_route101",
                       "projectOpen=" + session.projectOpen,
                       "songOpen=" + session.songOpen]
        if (testCase.openFailure.length > 0)
            details.push("openFailed=" + testCase.openFailure)
        if (session.lastSaveError.length > 0)
            details.push("lastSaveError=" + session.lastSaveError)
        return " (" + details.join("; ") + ")"
    }

    function mountOverlay() {
        var item = overlayComponent.createObject(testCase, {
            "width": testCase.width,
            "height": testCase.height
        })
        verify(item, "the production overlay came up")
        testCase.overlay = item
        var surface = null
        verify(waitForNative(function() {
            surface = testCase.selectedSurface()
            return surface !== null
        }, 5000), "the selected tab's production EditorSurface mounted")
        item.height += surface.gridModel.rulerHeight
        var drawer = findChild(surface, "editorDrawer")
        verify(drawer, "the production drawer is mounted")
        drawer.presenter.restoreStoredPreferences()
        verify(waitForNative(function() {
            return surface.visible && surface.width > 0 && surface.height > 0
        }, 5000), "the mounted surface is drawn")
    }

    function selectedSurface() {
        return testCase.overlay ? findChild(testCase.overlay, "swiftRollOverlay") : null
    }

    function init() {
        bootstrap.cancelInput()
        bootstrap.resumePlayheadPolling()
    }

    function cleanup() {
        bootstrap.cancelInput()
        wait(0)
    }

    function cleanupTestCase() {
        bootstrap.pausePlayheadPolling()
        if (session.songOpen)
            verify(bootstrap.hostClosing(),
                   "the session still presents its document while the scene exists")
        var retired = testCase.overlay
        testCase.overlay = null
        if (retired) {
            retired.destroy()
            wait(0)
            verify(bootstrap.acknowledgeSceneRemoval(),
                   "the session released its document presentation after the"
                   + " acknowledged scene removal")
        }
    }

    function surface() {
        var s = testCase.selectedSurface()
        verify(s !== null, "the production EditorSurface is mounted")
        return s
    }

    function grid() {
        var g = surface().gridModel
        verify(g !== null, "the grid presenter is published")
        return g
    }

    function rollInput() {
        var input = findChild(surface(), "swiftRollInput")
        verify(input !== null, "the roll input MouseArea exists")
        return input
    }

    function gridNotes(g) { return JSON.parse(g.noteSummary) }

    function noteById(g, id) {
        var list = gridNotes(g)
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === id)
                return list[i]
        return null
    }

    function selectedNotes(g) {
        return gridNotes(g).filter(function(n) { return n.selected })
    }

    function publishedNoteCount(g) {
        var total = 0
        verify(waitForNative(function() {
            total = gridNotes(g).length
            return total > 0
        }, 10000), "the staged song publishes grid notes")
        return total
    }

    function noteItem(surf, id) { return findChild(surf, "gridNote_" + id) }

    function bandForNote(roll, surf, id) {
        var item = noteItem(surf, id)
        if (!item || item.width <= 0 || item.height <= 0)
            return null
        var topLeft = item.mapToItem(roll, 0, 0)
        var bottomRight = item.mapToItem(roll, item.width, item.height)
        var sx = topLeft.x - 3
        var sy = topLeft.y - 3
        var ex = bottomRight.x + 3
        var ey = bottomRight.y + 3
        if (sx < 1 || sy < 1 || ex > roll.width - 1 || ey > roll.height - 1)
            return null
        return { sx: sx, sy: sy, ex: ex, ey: ey }
    }

    function firstBandedNote(g, surf, roll, unselectedOnly) {
        var list = gridNotes(g)
        for (var i = 0; i < list.length; ++i) {
            if (unselectedOnly && list[i].selected)
                continue
            if (bandForNote(roll, surf, list[i].id) !== null)
                return list[i]
        }
        return null
    }

    function pointCovered(roll, surf, g, x, y) {
        var list = gridNotes(g)
        for (var i = 0; i < list.length; ++i) {
            var item = noteItem(surf, list[i].id)
            if (!item || item.width <= 0 || item.height <= 0)
                continue
            var tl = item.mapToItem(roll, 0, 0)
            var br = item.mapToItem(roll, item.width, item.height)
            if (x >= tl.x - 4 && x <= br.x + 4 && y >= tl.y - 4 && y <= br.y + 4)
                return true
        }
        return false
    }

    function clearSelection(roll, surf, g) {
        if (selectedNotes(g).length === 0)
            return true
        var pts = [[8, 8], [roll.width - 8, 8], [8, roll.height - 8],
                   [roll.width - 8, roll.height - 8]]
        for (var k = 0; k < pts.length; ++k) {
            if (pointCovered(roll, surf, g, pts[k][0], pts[k][1]))
                continue
            mouseClick(roll, pts[k][0], pts[k][1], Qt.RightButton)
            if (selectedNotes(g).length === 0)
                return true
        }
        for (var gy = 24; gy < roll.height - 8; gy += 40) {
            for (var gx = 24; gx < roll.width - 8; gx += 40) {
                if (pointCovered(roll, surf, g, gx, gy))
                    continue
                mouseClick(roll, gx, gy, Qt.RightButton)
                if (selectedNotes(g).length === 0)
                    return true
            }
        }
        return selectedNotes(g).length === 0
    }

    function sweepBand(roll, band) {
        mousePress(roll, band.sx, band.sy, Qt.RightButton)
        mouseMove(roll, band.ex, band.ey, -1, Qt.RightButton)
    }

    function test_bandSelectsSweptNotes() {
        var g = grid()
        var roll = rollInput()
        var surf = surface()
        publishedNoteCount(g)
        verify(clearSelection(roll, surf, g), "the suite starts with nothing selected")
        var target = firstBandedNote(g, surf, roll, true)
        verify(target !== null, "a fully visible note takes a band")
        var band = bandForNote(roll, surf, target.id)
        verify(band !== null, "the band fits inside the roll")
        sweepBand(roll, band)
        verify(waitForNative(function() {
            return g.statusText.indexOf("Selecting") !== -1
        }, 5000), "the held band previews its selection")
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            var current = noteById(g, target.id)
            return current && current.selected
        }, 5000), "band release selects the swept note")
    }

    function test_bandCancelRestoresSelection() {
        var g = grid()
        var roll = rollInput()
        var surf = surface()
        publishedNoteCount(g)
        verify(clearSelection(roll, surf, g), "the suite starts with nothing selected")
        var target = firstBandedNote(g, surf, roll, true)
        verify(target !== null, "a fully visible note takes a band")
        var band = bandForNote(roll, surf, target.id)
        verify(band !== null, "the band fits inside the roll")
        sweepBand(roll, band)
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            var current = noteById(g, target.id)
            return current && current.selected
        }, 5000), "the setup band selects its note")
        var before = g.noteSummary
        sweepBand(roll, band)
        verify(waitForNative(function() {
            return g.statusText.indexOf("Selecting") !== -1
        }, 5000), "the second band is live")
        verify(bootstrap.cancelInput(), "the production cancel path runs")
        mouseRelease(roll, band.ex, band.ey, Qt.RightButton)
        verify(waitForNative(function() {
            return g.noteSummary === before && g.lastCancelReason === 2
        }, 5000), "cancel restores the band selection with reason 2")
    }

    function test_edgeHoverShowsResizeCursor() {
        var g = grid()
        var roll = rollInput()
        var surf = surface()
        publishedNoteCount(g)
        verify(bootstrap.setCameraTimeZoom(140), "the lane widens the time zoom")
        verify(waitForNative(function() {
            var notes = gridNotes(g)
            for (var k = 0; k < notes.length; ++k) {
                var it = noteItem(surf, notes[k].id)
                if (it && it.width >= 16)
                    return true
            }
            return false
        }, 8000), "the zoomed song realizes a wide note")
        var list = gridNotes(g)
        var probed = false
        for (var i = 0; i < list.length && !probed; ++i) {
            var item = noteItem(surf, list[i].id)
            if (!item || item.width < 16 || item.height <= 0)
                continue
            var center = item.mapToItem(roll, item.width / 2, item.height / 2)
            if (center.x < 8 || center.y < 8
                    || center.x > roll.width - 8 || center.y > roll.height - 8)
                continue
            var edge = item.mapToItem(roll, item.width - 1, item.height / 2)
            mouseMove(roll, edge.x, edge.y)
            if (!waitForNative(function() { return g.cursorKind === 3 }, 3000))
                continue
            verify(waitForNative(function() { return roll.cursorShape === Qt.SizeHorCursor }, 5000),
                   "the edge hover shows the resize cursor")
            mouseMove(roll, center.x, center.y)
            verify(waitForNative(function() { return g.cursorKind === 0 }, 5000),
                   "the note body restores the arrow")
            probed = true
        }
        verify(probed, "a fully visible wide note takes the cursor probe")
    }
    function test_foldDragExceptionCommitsAfterRelease() {
        var g = grid()
        var roll = rollInput()
        var surf = surface()
        publishedNoteCount(g)
        g.setScaleFold(true)
        var initialRows = g.visibleRowCount
        g.setScaleFold(false)
        g.setCameraVScroll((127 - 61 + 0.5) * g.rowHeight - roll.height / 2)
        var originalIds = gridNotes(g).map(function(note) { return note.id })
        function draw(pitch, x) {
            var y = (127 - pitch + 0.5) * g.rowHeight - g.cameraScrollY
            verify(y > g.rowHeight && y < roll.height - g.rowHeight,
                   "the requested pitch row is in the visible plot")
            var endX = x + Math.max(2 * g.drawThreshold,
                                    2 * g.snapTicks * g.beatWidth / g.ticksPerBeat)
            mousePress(roll, x, y, Qt.LeftButton)
            mouseMove(roll, endX, y, -1, Qt.LeftButton)
            mouseRelease(roll, endX, y, Qt.LeftButton)
            var created = null
            tryVerify(function() {
                created = gridNotes(g).find(function(note) {
                    return note.pitch === pitch && originalIds.indexOf(note.id) < 0
                })
                return created !== undefined
            }, 3000)
            originalIds.push(created.id)
            return created
        }
        draw(62, Math.round(roll.width * 0.65))
        g.setScaleFold(true)
        var rowsWithDestination = g.visibleRowCount
        g.setScaleFold(false)
        g.setCameraVScroll((127 - 61 + 0.5) * g.rowHeight - roll.height / 2)
        var exception = draw(61, Math.round(roll.width * 0.75))
        g.setScaleFold(true)
        tryCompare(g, "visibleRowCount", rowsWithDestination + 1)
        verify(g.visibleRowCount >= initialRows + 2,
               "fold gains the occupied off-scale row")
        var note = noteItem(surf, exception.id)
        verify(note !== null && note.width > 0, "the folded exception renders")
        var center = note.mapToItem(roll, note.width / 2, note.height / 2)
        var stableRows = g.visibleRowCount
        mousePress(roll, center.x, center.y, Qt.LeftButton)
        mouseMove(roll, center.x, center.y - g.rowHeight, -1, Qt.LeftButton)
        wait(0)
        verify(g.visibleRowCount === stableRows && noteById(g, exception.id).pitch === 61
               && g.statusText.indexOf("Moving") !== -1,
               "fold drag grabs the off-scale note without rebuilding rows")
        mouseRelease(roll, center.x, center.y - g.rowHeight, Qt.LeftButton)
        tryVerify(function() {
            return noteById(g, exception.id).pitch === 62
        }, 3000, "fold drag commits the note to its scale degree")
        tryCompare(g, "visibleRowCount", stableRows - 1, 3000,
                   "fold collapses the off-scale row after the drag commit")
        g.setScaleFold(false)
    }
}
