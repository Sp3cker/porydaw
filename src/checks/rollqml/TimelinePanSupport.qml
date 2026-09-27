import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import Porydaw.Ui
import "../editorqml/NativeWait.js" as NativeWait

TestCase {
    id: testCaseRoot
    readonly property var testCase: testCaseRoot
    property alias bootstrap: bootstrapObject
    property alias session: sessionObject

    name: "TimelinePan"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var overlay: null
    property string openFailure: ""

    RollQmlBootstrap {
        id: bootstrapObject

        ApplicationSession { id: sessionObject }
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
        // Keep the note viewport's fixture height after reserving the ruler.
        item.height += surface.gridModel.rulerHeight
        var drawer = findChild(surface, "editorDrawer")
        verify(drawer, "the production drawer is mounted")
        session.configurePersistence()
        verify(waitForNative(function() {
            return surface.visible && surface.width > 0 && surface.height > 0
        }, 5000), "the mounted surface is drawn")
        verify(waitForNative(function() {
            return drawer.height > 0 && testCase.gutterBox().height > 0
        }, 5000), "the mounted drawer has sized the roll viewport")
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

    // ---- shared lookups ------------------------------------------------------

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

    function keyboardLabels() {
        var labels = []
        var stack = [surface()]
        while (stack.length > 0) {
            var item = stack.pop()
            if (item.labelText !== undefined && item.labelBackgroundRect !== undefined) {
                var position = item.mapToItem(gutterBox(), 0, 0)
                labels.push({ text: item.labelText, x: position.x, y: position.y,
                              width: item.width, height: item.height })
            }
            for (var c = 0; c < item.children.length; ++c)
                stack.push(item.children[c])
        }
        return labels
    }

    function sameLabels(a, b) {
        if (a.length !== b.length)
            return false
        for (var i = 0; i < a.length; ++i) {
            if (a[i].text !== b[i].text || a[i].x !== b[i].x || a[i].y !== b[i].y
                || a[i].width !== b[i].width || a[i].height !== b[i].height)
                return false
        }
        return true
    }

    // A fully visible pitch row inside the gutter viewport.
    function visiblePitch() {
        var height = gutterBox().height
        var labels = keyboardLabels()
        for (var i = 0; i < labels.length; ++i) {
            if (labels[i].y >= 0 && labels[i].y + labels[i].height <= height)
                return labels[i]
        }
        fail("no fully visible keyboard label")
        return null
    }

    function selectedNoteCount(grid) {
        var notes = JSON.parse(grid.noteSummary)
        var count = 0
        for (var i = 0; i < notes.length; ++i) {
            if (notes[i].selected)
                ++count
        }
        return count
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
