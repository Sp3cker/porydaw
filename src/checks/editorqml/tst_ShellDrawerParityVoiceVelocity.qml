import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

import "ShellDrawerParityRasterSupport.js" as Raster
import "ShellDrawerParityVelocitySupport.js" as Velocity

ShellDrawerParitySupport {
    id: testCase
    function test_bVoiceDragCommit() {
        dragVoiceTransaction(false)
    }
    function test_cVoiceDragCancel() {
        dragVoiceTransaction(true)
    }
    function dragVoiceTransaction(cancel) {
        openDrawerShell("voiceChanges")
        var page = voicePageItem()
        var input = voicePlotInput()
        var model = voiceModel()
        var preview = findChild(page, "voiceDragPreview")
        verify(input && page && model && preview, "the voice page is mounted")
        var roll = rollInput()
        mouseMove(roll, 20, 20)
        var lines = collectByName(page, "voiceChangeMarkerLine", [])
        verify(lines.length > 0, "the fixture publishes a voice-change marker")
        var marker = null
        for (var l = 0; l < lines.length && !marker; ++l) {
            var line = lines[l]
            if (!line.visible)
                continue
            var center = line.mapToItem(input, line.width / 2, line.height / 2)
            if (center.x >= 0 && center.y >= 0
                    && center.x <= input.width && center.y <= input.height)
                marker = center
        }
        verify(marker, "a voice marker maps inside the plot")
        var sourceTick = 0
        compare(line.parent.model.tick, sourceTick,
                "the Route 101 Voice drag starts at the fixture's written tick-zero marker")
        mouseMove(input, marker.x, marker.y)
        tryCompare(model, "hoverHintProfile", 21, 3000,
                   "the marker hover resolves its hint profile")
        var before = revision()
        verify(before.length > 0, "the document publishes its revision")
        var capture = shell.contentItem
        var idleRegion = Raster.regionOf(testCase, grabImage(capture), capture, input)
        var idle = Raster.grabRegionStable(testCase, capture, idleRegion)
        verify(idle.width > 0, "the idle plot composited into an image")
        var inputRegion = Raster.regionOf(testCase, idle, capture, input)

        mousePress(input, marker.x, marker.y, Qt.LeftButton)
        wait(50)
        compare(revision(), before, "pressing the marker writes nothing")
        verify(!preview.visible, "pressing shows no preview yet")
        waitForRendering(tabsRoot())
        var pressed = Raster.grabRegionStable(testCase, capture, inputRegion)
        compare(pressed.width, idle.width, "press keeps the frame size")
        compare(Raster.changedPixels(testCase, idle, pressed, inputRegion, 0), 0,
                "pressing paints nothing")

        var beatWidth = gridModel().beatWidth
        var target = { x: marker.x + beatWidth * 2, y: marker.y }
        if (target.x < 0 || target.x > input.width)
            target = { x: marker.x - beatWidth * 2, y: marker.y }
        verify(target.x >= 0 && target.x <= input.width,
               "the drag target stays inside the plot")
        mouseMove(input, target.x, target.y, -1, Qt.LeftButton)
        verify(waitForNative(function() { return preview.visible }, 3000),
               "dragging publishes its preview")
        tryCompare(model, "cursorKind", 3, 3000,
                   "the drag carries the horizontal cursor")
        compare(input.cursorShape, Qt.SizeHorCursor, "the plot draws the drag cursor")
        waitForRendering(tabsRoot())
        var draft = Raster.grabUntilDifferent(testCase, capture, idle, inputRegion)
        var ticksPerBeat = gridModel().ticksPerBeat
        var deltaTick = target.x > marker.x ? 2 * ticksPerBeat : -2 * ticksPerBeat
        var expectedTick = Math.round(sourceTick + deltaTick)
        var expectedX = Math.round((expectedTick * beatWidth / ticksPerBeat
                                    - gridModel().cameraScrollX) * devicePixelRatioFor(input))
                        / devicePixelRatioFor(input)
        verify(Math.abs(model.previewX - expectedX) <= 1,
               "the moved Voice preview projects its exact source tick plus two beats")
        var previewPoint = Raster.physicalPoint(testCase, capture, draft, input,
                                                { x: expectedX, y: input.height * 0.75 })
        verify(Raster.pixelIs(testCase, draft, previewPoint.x, previewPoint.y, "#00cadb", 20)
               && !Raster.pixelIs(testCase, idle, previewPoint.x, previewPoint.y, "#00cadb", 20),
               "the moved Voice preview paints selection-edge ink only at its projected cursor")
        verify(Raster.changedPixels(testCase, idle, draft, inputRegion, 0) > 0, "the draft paints")
        compare(draft.width, idle.width, "the draft keeps the frame size")
        compare(revision(), before, "dragging writes nothing yet")
        verify(model.interactionActive, "the drag owns the interaction")

        if (cancel) {
            var plot = findChild(page, "voicePlot")
            plot.forceActiveFocus(Qt.OtherFocusReason)
            tryCompare(plot, "activeFocus", true, 3000)
            keyClick(Qt.Key_Escape)
            verify(waitForNative(function() { return !preview.visible }, 3000),
                   "Escape cancels the drag preview")
            mouseRelease(input, target.x, target.y, Qt.LeftButton)
            compare(revision(), before, "a cancelled drag writes nothing")
            verify(!session().canUndo, "a cancelled drag arms no history")
        } else {
            mouseRelease(input, target.x, target.y, Qt.LeftButton)
            verify(waitForNative(function() { return revision() !== before }, 5000),
                   "releasing the drag commits")
            verify(waitForNative(function() { return !preview.visible }, 3000),
                   "the committed preview retires")
            verify(waitForNative(function() { return session().canUndo }, 3000),
                   "the commit arms history")
            var committed = revision()
            session().requestUndo()
            verify(waitForNative(function() { return revision() !== committed },
                                 5000), "undo replays the commit")
            verify(waitForNative(function() { return !session().canUndo }, 5000),
                   "undo disarms history")
        }
        verify(waitForNative(function() { return !model.interactionActive }, 3000),
               "the transaction releases the interaction")
        mouseMove(input, marker.x, marker.y)
        waitForRendering(tabsRoot())
        var settled = Raster.grabRegionStable(testCase, capture, inputRegion)
        compare(Raster.changedPixels(testCase, idle, settled, inputRegion, 0), 0,
                "the plot settles back to idle")
    }
    function test_eVelocityLateUnlock() {
        Velocity.dragMountedVelocity(testCase, false)
    }
    function test_fVelocityEarlyUnlock() {
        Velocity.dragMountedVelocity(testCase, true)
    }
}
