import QtQuick
import QtTest

TimelinePanSupport {
    function test_wheelPansCamera() {
        var g = grid()
        var input = rollInput()
        var before = g.cameraScrollX
        mouseWheel(input, input.width / 2, input.height / 2, 0, -8, Qt.NoButton, Qt.ShiftModifier)
        tryVerify(function() {
            return Math.abs(g.cameraScrollX - (before + 8.0)) <= 0.01
        }, 5000, "a pixel-delta wheel pans the camera by exactly 8px")

        var summary = g.noteSummary
        mouseWheel(input, input.width / 2, input.height / 2, 0, 0)
        wait(50)
        var cameraUnchanged = g.cameraScrollX === before + 8.0
        var summaryUnchanged = g.noteSummary === summary
        verify(cameraUnchanged && summaryUnchanged,
               "an empty wheel leaves the camera and gutter summary unchanged")

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

        g.setCameraHScroll(0)
        tryCompare(g, "cameraScrollX", 0, 5000)
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

    function test_hoverChipOverlay() {
        var g = grid()
        var scene = g.scene
        verify(scene !== null, "the grid scene object is published")
        var gutter = gutterInput()
        var pitch = visiblePitch()

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

        // A neighboring pitch may not have a keyboard-label delegate when the
        // mounted scrollbar reduces the viewport. Hover its row directly.
        var step = Math.max(g.rowHeight, pitch.height)
        var nextY = pitch.y + pitch.height / 2 + step
        if (nextY >= gutterBox().height)
            nextY = pitch.y + pitch.height / 2 - step
        verify(nextY >= 0 && nextY < gutterBox().height,
               "a second visible pitch row exists")
        mouseMove(gutter, gutter.width / 2, nextY)
        tryVerify(function() {
            return scene.hoverChipText !== pitch.text && g.hoverKey !== firstKey
        }, 5000, "the chip republishes the second key name")
        verify(waitForNative(function() {
            return chipText.text === scene.hoverChipText
                && chip.width === scene.hoverChipRect.width
        }, 5000), "the realized chip tracks the republished rect")
        verify(scene.hoverChipVisible)
        verify(scene.hoverChipRect.x >= 0, "the second chip stays on-screen")
        verify(g.hoverKey >= 0, "moving to another gutter row resolves another MIDI key")
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
