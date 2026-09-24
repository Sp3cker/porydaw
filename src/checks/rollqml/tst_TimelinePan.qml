// Timeline-pan assertions for the Swift roll window, run by the rollqml lane:
//
//     roll_qml_tests {scratch} -input tst_TimelinePan.qml
//
// Ports the deleted timelinepan C++ suite's real-input/window assertions to the
// production Swift surface: pixel-wheel pan, middle-drag pan, the piano
// hover-chip overlay, coalesced drawer refresh, track-switch label stability,
// and the selected-pan render obligation from the native performance harness.
// Sites asserting C++-only internals (QSGNode pooling, dashed-segment builders,
// TimelineQuickTextModel zero-signal obligations, drum-pad/program
// classification, gutter-overflow geometry the Swift layout cannot produce)
// stay NATIVE in the ledger.
import QtQuick
import QtTest
import PorydawApp
import RollQmlCheck 1.0
import "../../ui/songview/quick/swiftroll"

TestCase {
    id: testCase

    name: "TimelinePan"
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
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function initTestCase() {
        Qt.application.name = "porydaw"
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        verify(bootstrap.captureSettings(), "saved the caller's native preferences")
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
        surface.drawerPreferenceLocation = bootstrap.preferencesUrl("lane-drawer.ini")
        var drawer = findChild(surface, "editorDrawer")
        verify(drawer, "the production drawer is mounted")
        drawer.presenter.restoreStoredPreferences(0, 160, 1, 240, 1, 90, 0)
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
        verify(bootstrap.restoreSettings(), "restored the caller's native settings")
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

    // The realized keyboard-label delegates: SceneText rows carry labelText and
    // labelRect; the keyboard repeater's delegates are the only band children
    // with a labelBackgroundRect role.
    function keyboardLabels() {
        var labels = []
        var stack = [surface()]
        while (stack.length > 0) {
            var item = stack.pop()
            if (item.labelText !== undefined && item.labelBackgroundRect !== undefined)
                labels.push({ text: item.labelText, x: item.x, y: item.y,
                              width: item.width, height: item.height })
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

    // ---- the cases -----------------------------------------------------------

    // timelinepan's wheelPanCamera: a pixel-delta wheel pans the camera by the
    // delta, an empty wheel is a no-op, and repeated pans leave the gutter
    // labels identical.
    function test_wheelPansCamera() {
        var g = grid()
        var input = rollInput()
        var before = g.cameraScrollX
        // The plot WheelHandler is vertical-only, so the production horizontal
        // pan path is Shift+wheel: handleWheel's shift branch scrolls the camera
        // by -d, so yDelta -8 pans +8px — the same +8 the C++ pixel-delta wheel
        // asserted.
        mouseWheel(input, input.width / 2, input.height / 2, 0, -8, Qt.NoButton, Qt.ShiftModifier)
        tryVerify(function() {
            return Math.abs(g.cameraScrollX - (before + 8.0)) <= 0.01
        }, 5000, "a pixel-delta wheel pans the camera by exactly 8px")

        var summary = g.noteSummary
        mouseWheel(input, input.width / 2, input.height / 2, 0, 0)
        wait(50)
        compare(g.cameraScrollX, before + 8.0)
        compare(g.noteSummary, summary)

        var labelsBefore = keyboardLabels()
        for (var count = 0; count < 8; ++count) {
            var step = g.cameraScrollX
            mouseWheel(input, input.width / 2, input.height / 2, 0, -8, Qt.NoButton, Qt.ShiftModifier)
            tryVerify(function() {
                return Math.abs(g.cameraScrollX - (step + 8.0)) <= 0.01
            }, 5000, "each wheel pan advances the camera by 8px")
        }
        verify(sameLabels(keyboardLabels(), labelsBefore),
               "gutter labels survive eight pans unchanged")
    }

    // timelinepan's middlePan: the real pointer path drives cursor, status and
    // camera; a pointer ungrab cancels the gesture.
    function test_middleDragPansCamera() {
        var g = grid()
        var input = rollInput()
        var summary = g.noteSummary
        var idleStatus = g.statusText
        var startX = input.width / 2
        var startY = input.height / 2

        var beforeX = g.cameraScrollX
        var beforeY = g.cameraScrollY
        mouseMove(input, startX, startY)
        mousePress(input, startX, startY, Qt.MiddleButton)
        tryCompare(g, "cursorKind", 4, 5000)
        compare(g.statusText, "Panning")

        // The camera moves by the negative pointer delta on both axes.
        mouseMove(input, startX + 12, startY - 20, -1, Qt.MiddleButton)
        tryVerify(function() {
            return Math.abs(g.cameraScrollX - (beforeX - 12.0)) <= 0.01
                && Math.abs(g.cameraScrollY - (beforeY + 20.0)) <= 0.01
        }, 5000, "the camera tracks the negative pointer delta")
        compare(g.cursorKind, 4)
        compare(g.noteSummary, summary)

        mouseRelease(input, startX + 12, startY - 20, Qt.MiddleButton)
        tryCompare(g, "cursorKind", 0, 5000)
        compare(g.statusText, idleStatus)

        // The production ungrab path cancels a live pan and restores the cursor.
        mousePress(input, startX, startY, Qt.MiddleButton)
        tryCompare(g, "cursorKind", 4, 5000)
        mouseMove(input, startX + 4, startY, -1, Qt.MiddleButton)
        session.cancelGridInput(1)
        mouseRelease(input, startX + 4, startY, Qt.MiddleButton)
        tryCompare(g, "cursorKind", 0, 5000)
        compare(g.noteSummary, summary)
    }

    // timelinepan's hover-chip assertions: gutter hover publishes the chip, the
    // realized overlay items sit on the band root above the clipped boxes, and
    // the chip/text geometry tracks the published rect.
    function test_hoverChipOverlay() {
        var g = grid()
        var scene = g.scene
        verify(scene !== null, "the grid scene object is published")
        var gutter = gutterInput()
        var pitch = visiblePitch()

        // The overlay items always exist; only their bound state lags. The
        // bridge emits property notifies through a queued connection, so the
        // realized items settle only after the run loop pumps — the C++
        // oracle's pumpQuick() step.
        var chip = findChild(surface(), "timelineQuickPianoHoverChip")
        var chipText = findChild(surface(), "timelineQuickPianoHoverChipText")
        verify(chip !== null, "the hover chip item is realized")
        verify(chipText !== null, "the hover chip text item is realized")

        mouseMove(gutter, gutter.width / 2, pitch.y + pitch.height / 2)
        tryVerify(function() {
            return scene.hoverChipVisible === true
        }, 5000, "the hover chip becomes visible")
        verify(waitForNative(function() {
            return chip.visible && chip.width === scene.hoverChipRect.width
        }, 5000), "the realized chip tracks the published rect")
        compare(scene.hoverChipText, pitch.text)
        var chipRect = scene.hoverChipRect
        verify(chipRect.x >= 0, "the chip stays on-screen")
        // The gutter updates this same grid model; its published key and
        // the scene's keyboard-label text must agree at the hovered row.
        tryVerify(function() { return g.hoverKey >= 0 }, 5000,
                  "the gutter resolves a visible MIDI key")
        var firstKey = g.hoverKey
        verify(chipText.contentWidth <= chip.width, "the chip covers its text")

        // A second row republishes the chip.
        var labels = keyboardLabels()
        var second = null
        var gutterHeight = gutterBox().height
        for (var i = 0; i < labels.length; ++i) {
            if (labels[i].text !== pitch.text && labels[i].y >= 0
                && labels[i].y + labels[i].height <= gutterHeight) {
                second = labels[i]
                break
            }
        }
        verify(second !== null, "a second visible pitch row exists")
        mouseMove(gutter, gutter.width / 2, second.y + second.height / 2)
        tryVerify(function() {
            return scene.hoverChipText === second.text
        }, 5000, "the chip republishes the second key name")
        verify(waitForNative(function() {
            return chipText.text === second.text
                && chip.width === scene.hoverChipRect.width
        }, 5000), "the realized chip tracks the republished rect")
        verify(scene.hoverChipVisible)
        verify(scene.hoverChipRect.x >= 0, "the second chip stays on-screen")
        tryVerify(function() {
            return g.hoverKey >= 0 && g.hoverKey !== firstKey
        }, 5000, "moving to another gutter row resolves another MIDI key")
        verify(chipText.contentWidth <= chip.width, "the second chip covers its text")

        // The chip shares the note rows' coordinate space below the ruler;
        // its overlay layer sits above the clipped plot and gutter boxes.
        var plotBox = findChild(surface(), "timelineQuickRollPlot")
        var gutterBoxItem = gutterBox()
        var bandRoot = plotBox.parent
        verify(bandRoot !== null, "the roll band root exists")
        compare(chip.parent, chipText.parent)
        compare(chip.parent.parent, bandRoot)
        compare(chip.parent.y, plotBox.y)
        verify(chip.parent.z > plotBox.z, "the chip layer draws above the plot")
        verify(chip.parent.z > gutterBoxItem.z, "the chip layer draws above the gutter")
        verify(chipText.z > chip.z, "the chip text draws above the chip")
        verify(gutterBoxItem.clip, "the gutter box clips its contents")

        // The fixed keyboard label is realized inside the band, not the gutter.
        var label = null
        tryVerify(function() {
            label = null
            var stack = [surface()]
            while (stack.length > 0) {
                var item = stack.pop()
                if (item.objectName === "timelineQuickPianoHoverChipText")
                    continue
                if (item.text !== undefined && item.text === pitch.text) {
                    label = item
                    break
                }
                for (var c = 0; c < item.children.length; ++c)
                    stack.push(item.children[c])
            }
            return label !== null
        }, 5000, "the keyboard label item is realized")
        verify(label.visible, "the keyboard label is visible")
        var ancestor = label.parent
        var reachesBand = false
        var insideGutter = false
        while (ancestor) {
            if (ancestor === bandRoot)
                reachesBand = true
            if (ancestor === gutterBoxItem)
                insideGutter = true
            ancestor = ancestor.parent
        }
        verify(reachesBand, "the label's ancestor chain reaches the band root")
        verify(!insideGutter, "the label is not inside the clipped gutter box")
        compare(gutter.parent, gutterBoxItem)

        // Chip geometry tracks the published rect and the text tracks the chip.
        // Re-read the rect: the second hover republished it.
        chipRect = scene.hoverChipRect
        compare(chip.width, chipRect.width)
        compare(chip.x, chipRect.x)
        verify(chip.visible)
        verify(chipText.visible)
        compare(chipText.x, chip.x)
        compare(chipText.y, chip.y)
        compare(chipText.width, chip.width)
        compare(chipText.height, chip.height)
        verify(chipText.contentWidth > 0)
        verify(chipText.contentHeight > 0)
        verify(chipText.contentWidth <= chip.width)
        verify(chipText.contentHeight <= chip.height)
        verify(!chipText.clip)
        compare(chipText.horizontalAlignment, Text.AlignHCenter)
        compare(chipText.verticalAlignment, Text.AlignVCenter)

        // The fixed label's realized text fits and is right-aligned.
        verify(label.contentWidth > 0)
        verify(label.contentHeight > 0)
        verify(label.contentWidth <= label.width)
        verify(!label.clip)
        compare(label.horizontalAlignment, Text.AlignRight)
        g.clearKeyboardHover()
        tryCompare(g, "hoverKey", -1, 5000)
        tryCompare(scene, "hoverChipVisible", false, 5000)
    }

    // static camera's bound-scroll and lead-pad contract through the mounted
    // Swift roll, rather than a detached camera value.
    function test_preRollCameraBounds() {
        var g = grid()
        var prior = g.cameraScrollX
        try {
            g.resetCameraScroll()
            var pad = bootstrap.cameraContentX(0)
            verify(pad > 0, "the mounted camera has a positive pre-roll pad")
            g.setCameraHScroll(-1e9)
            tryCompare(g, "cameraScrollX", -pad, 5000)
            compare(bootstrap.cameraContentX(0), pad,
                    "the mounted tick-zero projection lands at the pre-roll home")
            g.setCameraHScroll(1e9)
            tryVerify(function() {
                return Math.abs(g.cameraScrollX
                    - bootstrap.timelineLengthTicks() * bootstrap.cameraPxPerTick()) <= 1e-9
            }, 5000, "the bound timeline end clamps at the plot origin")
            g.resetCameraScroll()
            tryCompare(g, "cameraScrollX", -pad, 5000)
            compare(bootstrap.cameraContentX(0), pad,
                    "home restores the viewport's tick-zero lead pad")
        } finally {
            g.setCameraHScroll(prior)
        }
    }

    // timelinepan's coalesced-refresh assertions: a section resize changes the
    // drawer raster, and a full visual reload produces the identical capture.
    function test_coalescedRefreshMatchesFull() {
        var g = grid()
        var drawer = findChild(surface(), "editorDrawer")
        verify(drawer !== null, "the drawer item is realized")
        var presenter = drawer.presenter
        var automation = presenter.section(0)
        var voiceChanges = presenter.section(2)
        verify(automation !== null && automation.visible,
               "the automation section is attached and visible")
        verify(voiceChanges !== null && voiceChanges.visible,
               "the voice-changes section is attached and visible")

        var input = rollInput()
        var beforeX = g.cameraScrollX
        mouseWheel(input, input.width / 2, input.height / 2, 0, -8, Qt.NoButton, Qt.ShiftModifier)
        tryVerify(function() {
            return Math.abs(g.cameraScrollX - (beforeX + 8.0)) <= 0.01
        }, 5000, "the coalesced pan advances the camera by 8px")

        waitForRendering(drawer)
        var before = grabImage(drawer)
        verify(before.width > 0 && before.height > 0,
               "the coalesced drawer capture is non-null")

        // A section resize must change the drawer raster.
        var bodyBefore = automation.bodyHeight
        presenter.setSectionBodyHeight(0, bodyBefore + 24)
        tryVerify(function() {
            return presenter.section(0).bodyHeight === bodyBefore + 24
        }, 3000, "the section body height applies")
        waitForRendering(drawer)
        var resized = grabImage(drawer)
        verify(resized.width > 0 && resized.height > 0,
               "the resized drawer capture is non-null")
        verify(imagesDiffer(before, resized), "the resize changed the drawer raster")

        // A full visual reload produces the same raster as the coalesced path.
        g.reloadVisuals()
        waitForRendering(drawer)
        var full = grabImage(drawer)
        verify(full.width > 0 && full.height > 0,
               "the post-reload drawer capture is non-null")
        verify(!imagesDiffer(resized, full),
               "the coalesced refresh matches a full visual reload")
    }

    // timelinepan's drumGutterTrackSwitch, reduced to what the Swift surface
    // publishes: the keyboard labels are track-independent note names and are
    // identical across a track switch.
    function test_trackSwitchKeepsNoteLabels() {
        var g = grid()
        var labelsBefore = keyboardLabels()
        verify(labelsBefore.length > 0, "the keyboard model is populated")

        g.setTrack(1)
        tryCompare(g, "trackIndex", 1, 5000)
        var labelsOther = keyboardLabels()
        verify(labelsOther.length > 0, "the keyboard model stays populated")
        for (var i = 0; i < labelsOther.length; ++i) {
            verify(/^C-?\d+$/.test(labelsOther[i].text),
                   "every label is a natural-C note name on the non-drum track")
        }

        g.setTrack(0)
        tryCompare(g, "trackIndex", 0, 5000)
        verify(sameLabels(keyboardLabels(), labelsBefore),
               "row count and label rects are identical after switching back")
    }

    // timelinepannative's selectionExtentPanPerformance, minus the diagnostic
    // millisecond samples: a live selection, a wheel pan, and a rendered frame.
    function test_selectedPanRenders() {
        var g = grid()
        var input = rollInput()
        var startX = input.width / 4
        var startY = input.height / 4
        mousePress(input, startX, startY, Qt.RightButton)
        mouseMove(input, startX * 2, startY * 2, -1, Qt.RightButton)
        mouseRelease(input, startX * 2, startY * 2, Qt.RightButton)
        tryVerify(function() {
            return selectedNoteCount(g) > 0
        }, 5000, "the right-drag band selects notes")

        var before = g.cameraScrollX
        mouseWheel(input, input.width / 2, input.height / 2, 0, -8, Qt.NoButton, Qt.ShiftModifier)
        tryVerify(function() {
            return Math.abs(g.cameraScrollX - (before + 8.0)) <= 0.01
        }, 5000, "the wheel pan executes with a live selection")
        waitForRendering(surface())
        var frame = grabImage(surface())
        verify(frame.width > 0 && frame.height > 0,
               "the pan renders a non-null frame")
        verify(selectedNoteCount(g) > 0, "the selection survives the pan")
    }
}
