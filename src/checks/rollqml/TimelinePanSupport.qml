import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui
import "../editorqml/RollNoteFaces.js" as RollNoteFaces

RollLaneSupport {
    id: testCaseRoot
    readonly property var testCase: testCaseRoot

    name: "TimelinePan"
    when: windowShown
    width: 960
    height: 640
    visible: true

    verifySurface: true
    reserveRulerHeight: true


    function initTestCase() {
        bootstrap.seedDrawerPreferences(false, true, true, 0)
        verify(bootstrap.start("mus_route101"),
               "the staged route101 project starts opening")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the staged route101 song opened" + testCase.openDiagnostics())
        verify(waitForNative(function() {
            return session.songDockController().songListPresenter().totalCount > 0
        }, 5000), "the Songs dock catalog is ready before checking scene-removal retention")
        testCase.mountOverlay()
    }


    onOverlayMounted: function(item, mounted, drawer) {
        verify(waitForNative(function() {
            return drawer.height > 0 && testCase.gutterBox().height > 0
        }, 5000), "the mounted drawer has sized the roll viewport")
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

    // ---- shared lookups ------------------------------------------------------


    function gutterBox() {
        var box = findChild(surface(), "timelineQuickRollGutter")
        verify(box !== null, "the roll gutter exists")
        return box
    }

    function gutterInput() {
        var box = gutterBox()
        var input = null
        for (var i = 0; i < box.children.length; ++i) {
            if (box.children[i].hoverEnabled === true)
                input = box.children[i]
        }
        verify(input !== null, "the gutter hover MouseArea exists")
        return input
    }

    function keyboardRenderer() {
        var renderer = findChild(surface(), "timelineRendererKeyboard")
        verify(renderer !== null, "the native keyboard renderer is mounted")
        return renderer
    }

    function keyName(pitch) {
        var names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return names[pitch % 12] + (Math.floor(pitch / 12) - 1)
    }

    function keyRow(pitch) {
        var g = grid()
        var top = rollInput().mapToItem(gutterBox(), 0,
                                        (127 - pitch) * g.rowHeight - g.cameraScrollY).y
        return { pitch: pitch, text: keyName(pitch), x: 0, y: top,
                 width: g.keyboardWidth, height: g.rowHeight }
    }

    function rowVisible(row) {
        return row.y >= 0 && row.y + row.height <= gutterBox().height
    }

    function visiblePitch() {
        for (var pitch = 0; pitch < 128; pitch += 12) {
            var row = keyRow(pitch)
            if (rowVisible(row))
                return row
        }
        fail("no fully visible keyboard label")
        return null
    }

    function hoveredName(pitch) {
        var g = grid()
        var row = keyRow(pitch)
        mouseMove(gutterInput(), gutterInput().width / 2, row.y + row.height / 2)
        if (!waitForNative(function() {
            return g.hoverKey === pitch && g.scene.hoverChipVisible
        }, 2000))
            return ""
        return g.scene.hoverChipText
    }

    function rowInk(image, item, row, x0, x1) {
        var dpr = image.width / item.width
        var origin = gutterBox().mapToItem(item, 0, row.y + row.height / 2)
        var y = Math.round(origin.y * dpr)
        var dy = Math.max(0, Math.floor(row.height * dpr * 0.3))
        var left = Math.round(gutterBox().mapToItem(item, x0, 0).x * dpr)
        var right = Math.round(gutterBox().mapToItem(item, x1, 0).x * dpr)
        var r = image.red(left, y), gr = image.green(left, y), b = image.blue(left, y)
        var last = -1
        for (var py = y - dy; py <= y + dy; ++py) {
            for (var px = left; px < right; ++px) {
                if (Math.abs(image.red(px, py) - r) > 2 || Math.abs(image.green(px, py) - gr) > 2
                        || Math.abs(image.blue(px, py) - b) > 2)
                    last = Math.max(last, px)
            }
        }
        return last < 0 ? -1 : last / dpr
    }

    function selectedNoteCount(grid) {
        var notes = JSON.parse(grid.fetchNoteSummary())
        var count = 0
        for (var i = 0; i < notes.length; ++i) {
            if (notes[i].selected)
                ++count
        }
        return count
    }

    function grabItem(item) {
        return RollNoteFaces.grab(testCaseRoot, item)
    }

    // Two grabs differ if any sampled pixel differs.
    function imagesDiffer(a, b) {
        if (a.width !== b.width || a.height !== b.height)
            return true
        var stepX = Math.max(1, Math.floor(a.width / 16))
        var stepY = Math.max(1, Math.floor(a.height / 16))
        for (var y = 0; y < a.height; y += stepY) {
            for (var x = 0; x < a.width; x += stepX) {
                if (a.red(x, y) !== b.red(x, y) || a.green(x, y) !== b.green(x, y)
                    || a.blue(x, y) !== b.blue(x, y) || a.alpha(x, y) !== b.alpha(x, y))
                    return true
            }
        }
        return false
    }

}
