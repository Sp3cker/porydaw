import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

import "ShellDrawerParityRasterSupport.js" as Raster

ShellDrawerParitySupport {
    id: testCase
    Component { id: rasterImageReader; Canvas { width: 1; height: 1 } }
    function test_aAutomationHoverRaster() {
        openDrawerShell("automations")
        var parameters = ["Pan", "Tempo"]
        for (var p = 0; p < parameters.length; ++p)
            Raster.checkAutomationParameter(testCase, parameters[p])
    }
    function physicalRasterFrame(input, label, page) {
        waitForRendering(input)
        var frame = null
        var capture = page || automationPageItem()
        verify(capture.grabToImage(function(result) { frame = result }),
               "the DPR2 mounted drawer page accepts a physical framebuffer grab")
        tryVerify(function() { return frame !== null }, 3000)
        var file = rasterFixtureRoot + "/drawer-raster-dpr2-" + label + ".png"
        verify(frame.saveToFile(file), "the DPR2 drawer frame is saved for physical sampling")
        var reader = rasterImageReader.createObject(input)
        tryCompare(reader, "available", true, 3000)
        var url = "file://" + file
        reader.loadImage(url)
        tryVerify(function() { return reader.isImageLoaded(url) }, 3000)
        var pixels = reader.getContext("2d").createImageData(url)
        compare(pixels.width, Math.round(capture.width * 2),
                "the drawer grab contains twice the logical width in physical pixels")
        compare(pixels.height, Math.round(capture.height * 2),
                "the drawer grab contains twice the logical height in physical pixels")
        reader.destroy()
        return {
            width: pixels.width, height: pixels.height,
            red: function(x, y) { return pixels.data[(y * pixels.width + x) * 4] },
            green: function(x, y) { return pixels.data[(y * pixels.width + x) * 4 + 1] },
            blue: function(x, y) { return pixels.data[(y * pixels.width + x) * 4 + 2] }
        }
    }
    function test_dpr2AutomationHoverRaster() {
        if (!rasterDpr2Child) {
            skip("the dedicated child runs the raster journey at physical DPR2")
            return
        }
        compare(Screen.devicePixelRatio, 2,
                "the DPR2 child observes actual device pixel ratio two")
        openDrawerShell("automations")
        var page = automationPageItem()
        var input = automationPlotInput()
        var model = automationModel()
        var parameters = ["Pan", "Tempo"]
        for (var p = 0; p < parameters.length; ++p) {
            var parameter = parameters[p]
            var expected = Raster.route101Automation(parameter)
            var tab = null
            for (var i = 0; i < model.tabCount; ++i) {
                var candidate = findChild(page, "automationParameterTab" + i)
                if (candidate && candidate.text === parameter)
                    tab = candidate
            }
            verify(tab !== null, parameter === "Pan"
                   ? "the DPR2 Pan selector is mounted"
                   : "the DPR2 Tempo selector is mounted")
            mouseClick(tab, tab.width * 0.2, tab.height / 2)
            verify(waitForNative(function() { return tab.checked }, 3000),
                   parameter === "Pan" ? "the DPR2 Pan lane activates by pointer"
                                       : "the DPR2 Tempo lane activates by pointer")
            mouseMove(rollInput(), 20, 20)
            var idle = physicalRasterFrame(input, parameter + "-idle")
            var held = Raster.nodeCenter(testCase, input, 168,
                                         expected.heldValueAt168, parameter)
            var insertion = { x: held.x, y: input.height * 0.5 }
            mouseMove(input, insertion.x, insertion.y)
            verify(waitForNative(function() { return model.hoverVisible }, 3000),
                   parameter === "Pan" ? "the DPR2 Pan insertion ghost is published"
                                       : "the DPR2 Tempo insertion ghost is published")
            var ghost = physicalRasterFrame(input, parameter + "-ghost")
            var ghostPoint = Raster.physicalPoint(testCase, page, ghost, input, held)
            verify(Raster.pixelIs(testCase, ghost, ghostPoint.x, ghostPoint.y, "#302c29"),
                   parameter === "Pan" ? "the physical DPR2 Pan insertion ghost paints primary ink"
                                       : "the physical DPR2 Tempo insertion ghost paints primary ink")
            var region = Raster.regionOf(testCase, ghost, page, input)
            verify(Raster.changedPixels(testCase, idle, ghost, region, 0) > 0,
                   parameter === "Pan" ? "the physical DPR2 Pan hover changes plot pixels"
                                       : "the physical DPR2 Tempo hover changes plot pixels")
            mouseMove(rollInput(), 20, 20)
            var fills = collectByName(page, "automationNodeFill", [])
            var node = fills.find(function(fill) {
                return fill.visible && fill.parent.model.tick === expected.nodeTick
                    && fill.parent.model.value === expected.nodeValue
            })
            verify(node !== undefined, parameter === "Pan"
                   ? "the DPR2 Pan plot has an interior node"
                   : "the DPR2 Tempo plot has an interior node")
            var center = Raster.nodeCenter(testCase, input, expected.nodeTick,
                                           expected.nodeValue, parameter)
            var point = Raster.physicalPoint(testCase, page, idle, input, center)
            verify(Raster.pixelIs(testCase, idle, point.x, point.y, "#302c29"),
                   parameter === "Pan" ? "the physical DPR2 Pan node center paints primary ink"
                                       : "the physical DPR2 Tempo node center paints primary ink")
            mouseMove(input, center.x, center.y)
            verify(waitForNative(function() {
                return collectByName(page, "automationNodeHover", []).some(
                    function(ring) { return ring.visible })
            }, 3000), parameter === "Pan" ? "the DPR2 Pan node hover is published"
                                           : "the DPR2 Tempo node hover is published")
            var hovered = physicalRasterFrame(input, parameter + "-node")
            compare(Raster.ringQuadrants(testCase, hovered, page, input,
                                        center, "#b9e8ee"), 15,
                    parameter === "Pan" ? "the physical DPR2 Pan ring paints four quadrants"
                                        : "the physical DPR2 Tempo ring paints four quadrants")
            mouseMove(rollInput(), 20, 20)
            var endX = Math.min(input.width - 2, center.x + gridModel().beatWidth)
            verify(endX > center.x + 12,
                   parameter === "Pan" ? "the DPR2 Pan node has room for a real range drag"
                                       : "the DPR2 Tempo node has room for a real range drag")
            var bandY = input.height - model.baseFontPx
            mousePress(input, center.x + 1, bandY, Qt.RightButton)
            mouseMove(input, endX, bandY, -1, Qt.RightButton)
            mouseRelease(input, endX, bandY, Qt.RightButton)
            verify(waitForNative(function() {
                return collectByName(page, "automationNodeRing", []).some(
                    function(ring) { return ring.visible })
            }, 3000), parameter === "Pan" ? "the DPR2 Pan range selects the written node"
                                           : "the DPR2 Tempo range selects the written node")
            var selected = physicalRasterFrame(input, parameter + "-selected")
            compare(Raster.ringQuadrants(testCase, selected, page, input,
                                        center, "#b9e8ee"), 15,
                    parameter === "Pan"
                    ? "the physical DPR2 Pan selected annulus paints all quadrants"
                    : "the physical DPR2 Tempo selected annulus paints all quadrants")
        }
        checkDpr2VoicePreviewRaster()
    }
    function checkDpr2VoicePreviewRaster() {
        var page = voicePageItem()
        var input = voicePlotInput()
        var model = voiceModel()
        var preview = findChild(page, "voiceDragPreview")
        verify(page && input && model && preview,
               "the DPR2 mounted Voice page exposes its real plot and drag preview")
        var lines = collectByName(page, "voiceChangeMarkerLine", [])
        var marker = null
        for (var l = 0; l < lines.length && !marker; ++l) {
            var line = lines[l]
            if (!line.visible || line.parent.model.tick !== 0)
                continue
            var center = line.mapToItem(input, line.width / 2, line.height / 2)
            if (center.x >= 0 && center.y >= 0
                    && center.x <= input.width && center.y <= input.height)
                marker = center
        }
        verify(marker !== null, "the DPR2 Route 101 Voice tick-zero marker is drawn inside its plot")
        mouseMove(rollInput(), 20, 20)
        var before = revision()
        mouseMove(input, marker.x, marker.y)
        tryCompare(model, "hoverHintProfile", 21, 3000,
                   "the DPR2 Voice marker accepts the real plot pointer")
        var idle = physicalRasterFrame(input, "voice-idle", page)
        var region = Raster.regionOf(testCase, idle, page, input)
        mousePress(input, marker.x, marker.y, Qt.LeftButton)
        var pressed = physicalRasterFrame(input, "voice-pressed", page)
        compare(Raster.changedPixels(testCase, idle, pressed, region, 0), 0,
                "the DPR2 stationary Voice press retains the idle physical plot pixels")
        var beatWidth = gridModel().beatWidth
        var targetX = marker.x + beatWidth * 2
        if (targetX > input.width)
            targetX = marker.x - beatWidth * 2
        verify(targetX >= 0 && targetX <= input.width,
               "the DPR2 Voice moved target stays inside the mounted plot")
        mouseMove(input, targetX, marker.y, -1, Qt.LeftButton)
        tryCompare(preview, "visible", true, 3000,
                   "the DPR2 Voice pointer drag stages the real transient marker")
        var expectedTick = targetX > marker.x ? 2 * gridModel().ticksPerBeat
                                              : -2 * gridModel().ticksPerBeat
        var expectedX = Math.round((expectedTick * beatWidth / gridModel().ticksPerBeat
                                    - gridModel().cameraScrollX) * 2) / 2
        verify(Math.abs(model.previewX - expectedX) <= 1,
               "the DPR2 Voice moved preview projects its literal tick-zero source by two beats")
        var draft = physicalRasterFrame(input, "voice-moved", page)
        var point = Raster.physicalPoint(testCase, page, draft, input,
                                         { x: expectedX, y: input.height * 0.75 })
        verify(Raster.pixelIs(testCase, draft, point.x, point.y, "#00cadb", 20)
               && !Raster.pixelIs(testCase, idle, point.x, point.y, "#00cadb", 20),
               "the DPR2 Voice moved marker paints selection-edge ink at its independent physical target")
        compare(draft.width, idle.width,
                "the DPR2 Voice moved preview preserves its physical framebuffer width")
        compare(draft.height, idle.height,
                "the DPR2 Voice moved preview preserves its physical framebuffer height")
        compare(revision(), before, "the DPR2 Voice preview does not commit before release")
        findChild(page, "voicePlot").forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Escape)
        mouseRelease(input, targetX, marker.y, Qt.LeftButton)
        tryCompare(preview, "visible", false, 3000,
                   "the DPR2 Voice cancelled preview clears after the real plot release")
        compare(revision(), before, "the DPR2 Voice preview cancellation preserves the document")
    }
    function test_aAutomationFocusAndWindowCancellation() {
        openDrawerShell("automations")
        var input = automationPlotInput()
        var model = automationModel()
        var target = rollInput()
        var before = revision()
        verify(input && target && input.width > 0, "the mounted plot and alternate focus target exist")
        var x = input.width * 0.6
        var y = input.height * 0.3
        var endX = input.width * 0.8
        mouseMove(input, x, y)
        mousePress(input, x, y, Qt.RightButton)
        mouseMove(input, endX, y, -1, Qt.RightButton)
        tryCompare(model, "bandVisible", true, 3000,
                   "the held right-button drag stages a visible selection band")
        tryCompare(input, "pressed", true, 3000,
                   "the mounted plot retains its pointer grab while staging the band")
        target.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(target, "activeFocus", true, 3000,
                   "keyboard focus moves to the actual roll input")
        tryCompare(model, "interactionActive", true, 3000,
                   "focus transfer retains the held plot transaction")
        compare(input.pressed, true,
                "ordinary keyboard focus loss retains the held plot pointer grab")
        compare(model.bandVisible, true,
                "focus transfer keeps the staged selected-lane band visible")
        mouseRelease(input, endX, y, Qt.RightButton)
        tryCompare(input, "pressed", false, 3000,
                   "the focused-away right release relinquishes the retained grab")
        compare(revision(), before, "the focus-retained right release does not edit the song")
        compare(model.bandVisible, false,
                "the focused-away right release retires its completed band")

        mouseMove(input, x, y)
        mousePress(input, x, y, Qt.LeftButton)
        mouseMove(input, endX, input.height * 0.6, -1, Qt.LeftButton)
        tryCompare(model, "interactionActive", true, 3000,
                   "a fresh left-button sweep stages after focus-retained selection")
        compare(revision(), before,
                "the fresh sweep defers its document write until release")
        mouseRelease(input, endX, input.height * 0.6, Qt.LeftButton)
        tryCompare(model, "interactionActive", false, 3000,
                   "the recovered sweep completes on release")
        tryCompare(gridModel(), "appliedRevisionText", String(Number(before) + 1), 3000,
                   "the recovered sweep commits one song edit")
        verify(session().canUndo, "the recovered sweep records undo history")
        before = revision()

        mouseMove(input, x, y)
        mousePress(input, x, y, Qt.RightButton)
        mouseMove(input, endX, y, -1, Qt.RightButton)
        tryCompare(model, "bandVisible", true, 3000,
                   "a new held band is staged before real window deactivation")
        focusWindow = focusWindowComponent.createObject(null)
        verify(focusWindow !== null, "the second real window opens")
        focusWindow.requestActivate()
        tryCompare(focusWindow, "active", true, 3000,
                   "the second window actually takes activation")
        tryCompare(shell, "active", false, 3000,
                   "the automation window really deactivates")
        tryCompare(model, "interactionActive", false, 3000,
                   "deactivation cancels the staged automation gesture")
        tryCompare(input, "pressed", false, 3000,
                   "Qt deactivation relinquishes the MouseArea pointer grab")
        compare(model.bandVisible, false,
                "window deactivation clears the held band preview")
        mouseRelease(input, endX, y, Qt.RightButton)
        compare(revision(), before, "the deactivated stale release writes nothing")
        focusWindow.destroy()
        focusWindow = null
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000,
                   "the original shell regains window activation")
        mouseMove(input, input.width * 0.3, input.height * 0.75)
        mousePress(input, input.width * 0.3, input.height * 0.75, Qt.LeftButton)
        mouseMove(input, input.width * 0.5, input.height * 0.1, -1, Qt.LeftButton)
        tryCompare(model, "interactionActive", true, 3000,
                   "the reactivated shell stages a new sweep from real pointer input")
        compare(revision(), before,
                "the post-activation sweep still defers its write until release")
        mouseRelease(input, input.width * 0.5, input.height * 0.1, Qt.LeftButton)
        tryCompare(model, "interactionActive", false, 3000,
                   "the post-activation sweep ends normally")
        tryCompare(gridModel(), "appliedRevisionText", String(Number(before) + 1), 3000,
                   "the post-activation sweep commits exactly one more edit")
        before = revision()
        x = input.width * 0.35
        endX = input.width * 0.55
        mouseMove(input, x, y)
        mousePress(input, x, y, Qt.RightButton)
        mouseMove(input, endX, y, -1, Qt.RightButton)
        tryCompare(model, "bandVisible", true, 3000,
                   "the pre-resize right drag stages its band in the mounted plot")
        shell.width *= 1.08
        tryCompare(model, "interactionActive", false, 3000,
                   "a real window layout rebuild cancels the held range band")
        compare(model.bandVisible, false,
                "the resized plot has no stale range preview")
        mouseRelease(input, endX, y, Qt.RightButton)
        compare(revision(), before, "the resize-cancelled stale release writes nothing")
        mouseMove(input, input.width * 0.25, input.height * 0.8)
        mousePress(input, input.width * 0.25, input.height * 0.8, Qt.LeftButton)
        mouseMove(input, input.width * 0.42, input.height * 0.15, -1, Qt.LeftButton)
        tryCompare(model, "interactionActive", true, 3000,
                   "the resized plot accepts a fresh sweep")
        mouseRelease(input, input.width * 0.42, input.height * 0.15, Qt.LeftButton)
        tryCompare(gridModel(), "appliedRevisionText", String(Number(before) + 1), 3000,
                   "the post-resize fresh sweep commits exactly one song edit")
    }
}
