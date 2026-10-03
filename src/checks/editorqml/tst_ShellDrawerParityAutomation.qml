import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "RollNoteFaces.js" as RollNoteFaces

ShellDrawerParitySupport {
    id: testCase
    function test_aAutomationNodeGeometryCancellation() {
        openDrawerShell("automations")
        var page = automationPageItem()
        var input = automationPlotInput()
        var model = automationModel()
        var fills = collectByName(page, "automationNodeFill", [])
        var node = null
        var preview = automationPlotInput()
        verify(preview && preview.width > 0, "the mounted plot has a transient preview surface")
        function previewAt(x, y) {
            var frame = RollNoteFaces.grab(testCase, preview)
            var sx = frame.width / preview.width
            var sy = frame.height / preview.height
            var ink = String(page.gridPalette.selectionEdge).slice(-6)
            var rgb = [parseInt(ink.slice(0, 2), 16),
                       parseInt(ink.slice(2, 4), 16),
                       parseInt(ink.slice(4, 6), 16)]
            var radius = Math.ceil(model.baseFontPx * 3 / 4)
            for (var py = Math.max(0, Math.floor((y - radius) * sy));
                 py <= Math.min(frame.height - 1, Math.ceil((y + radius) * sy)); ++py) {
                for (var px = Math.max(0, Math.floor((x - radius) * sx));
                     px <= Math.min(frame.width - 1, Math.ceil((x + radius) * sx)); ++px) {
                    if (Math.max(Math.abs(frame.red(px, py) - rgb[0]),
                                 Math.abs(frame.green(px, py) - rgb[1]),
                                 Math.abs(frame.blue(px, py) - rgb[2])) < 24)
                        return true
                }
            }
            return false
        }
        var arm = model.baseFontPx * 3
        for (var f = 0; f < fills.length && !node; ++f) {
            if (!fills[f].visible)
                continue
            var center = fills[f].mapToItem(input, fills[f].width / 2, fills[f].height / 2)
            if (center.x > arm && center.y > arm
                    && center.x < input.width * 0.5 && center.y < input.height - arm)
                node = fills[f]
        }
        verify(node, "the song exposes a node within the resize drag viewport")
        var before = revision()
        var from = node.mapToItem(input, node.width / 2, node.height / 2)
        mouseMove(input, from.x, from.y)
        mousePress(input, from.x, from.y, Qt.LeftButton)
        mouseMove(input, from.x + arm, from.y, -1, Qt.LeftButton)
        mouseMove(input, from.x + 2 * arm, from.y, -1, Qt.LeftButton)
        tryVerify(function() { return previewAt(from.x + arm, from.y) }, 3000,
                  "a real node drag stages a point preview before geometry changes")
        compare(revision(), before, "the held node preview has not edited the song")
        var stagedRevision = model.displayRevision
        shell.width *= 1.08
        tryCompare(model, "interactionActive", false, 3000,
                   "resizing the mounted plot cancels its held node drag")
        tryVerify(function() {
            return model.displayRevision > stagedRevision
                && !previewAt(from.x + arm, from.y)
        }, 3000, "the geometry rebuild retires the provisional node preview")
        mouseRelease(input, from.x + 2 * arm, from.y, Qt.LeftButton)
        compare(revision(), before,
                "the stale node release after geometry rebuild cannot edit the song")
        from = node.mapToItem(input, node.width / 2, node.height / 2)
        mouseMove(input, from.x, from.y)
        mousePress(input, from.x, from.y, Qt.LeftButton)
        mouseMove(input, from.x + arm, from.y, -1, Qt.LeftButton)
        mouseMove(input, from.x + input.width * 0.3, from.y, -1, Qt.LeftButton)
        tryCompare(model, "interactionActive", true, 3000,
                   "a fresh node drag stages on the rebuilt geometry")
        mouseRelease(input, from.x + input.width * 0.3, from.y, Qt.LeftButton)
        tryCompare(gridModel(), "appliedRevisionText", String(Number(before) + 1), 3000,
                   "the fresh node drag commits exactly one edit after resize")
    }
    function test_aAutomationShortcutHintAndMenuScope() {
        openDrawerShell("automations")
        var page = automationPageItem()
        var input = automationPlotInput()
        var model = automationModel()
        var gutter = findChild(page, "automationGutter")
        var hint = findChild(shell, "shellMouseHintText")
        verify(page && input && model && gutter && hint,
               "the mounted automation plot gutter and shell hint are present")
        var before = revision()
        mouseMove(input, input.width * 0.55, input.height * 0.5)
        tryCompare(model, "hoverVisible", true, 3000,
                   "plot entry presents the background hover")
        tryCompare(hint, "text",
                   "⇧ Drag: draw ramp · ⌥ Drag: draw in ticks · ⌘ Drag: snap to neutral value · ⇧ Wheel: scroll horizontally",
                   3000, "plot entry publishes the exact sweep hint in the shell")
        input.forceActiveFocus(Qt.MouseFocusReason)
        keyClick(Qt.Key_B)
        tryCompare(model, "isPencilMode", true, 3000,
                   "the mounted shell dispatches B to arm the pencil")
        tryCompare(hint, "text",
                   "⌘ Drag: draw freehand · ⇧ Drag: hold value · ⌥ Right-drag: draw in ticks · ⇧ Wheel: scroll horizontally",
                   3000, "the pencil shortcut replaces the shell hint text")
        keyClick(Qt.Key_B)
        tryCompare(model, "isPencilMode", false, 3000,
                   "the second mounted B key returns to sweep mode")
        tryCompare(hint, "text",
                   "⇧ Drag: draw ramp · ⌥ Drag: draw in ticks · ⌘ Drag: snap to neutral value · ⇧ Wheel: scroll horizontally",
                   3000, "sweep hint returns after the second shortcut")

        mouseMove(gutter, gutter.width / 2, gutter.height / 2)
        tryCompare(model, "hoverVisible", false, 3000,
                   "moving from plot to gutter clears the background hover")
        tryCompare(hint, "text", "", 3000,
                   "the gutter leave clears the plot's shell hint")
        mouseMove(input, input.width * 0.65, input.height * 0.5)
        tryCompare(model, "hoverVisible", true, 3000,
                   "returning from gutter restores plot hover")
        tryCompare(hint, "text",
                   "⇧ Drag: draw ramp · ⌥ Drag: draw in ticks · ⌘ Drag: snap to neutral value · ⇧ Wheel: scroll horizontally",
                   3000, "returning from gutter restores the exact sweep hint")

        var fills = collectByName(page, "automationNodeFill", [])
        var node = null
        for (var f = 0; f < fills.length && !node; ++f) {
            if (!fills[f].visible)
                continue
            var center = fills[f].mapToItem(input, fills[f].width / 2, fills[f].height / 2)
            if (center.x > 12 && center.y > 12
                    && center.x < input.width - 12 && center.y < input.height - 12)
                node = center
        }
        verify(node, "the loaded song has a visible node for a pointer-opened menu")
        mouseClick(input, node.x, node.y, Qt.RightButton)
        tryCompare(model, "menuOpen", true, 3000,
                   "the real node right click opens the automation menu")
        tryCompare(hint, "text", "", 3000,
                   "the open menu suppresses the shell's underlying plot hint")
        tryVerify(function() { return page.menu !== null && page.menu.visible }, 3000,
                  "the automation menu is visible in the mounted modal layer")
        var underlay = findChild(page.menu, "automationMenuUnderlay")
        verify(underlay && underlay.visible,
               "the open menu composes its modal pointer underlay")
        var returnPoint = input.mapToItem(underlay, input.width * 0.75,
                                          input.height * 0.5)
        mouseMove(underlay, returnPoint.x, returnPoint.y)
        compare(hint.text, "", "menu-owned hint remains muted over another plot position")
        mouseClick(underlay, returnPoint.x, returnPoint.y, Qt.LeftButton)
        tryCompare(model, "menuOpen", false, 3000,
                   "the outside pointer click closes the automation menu")
        tryCompare(hint, "text",
                   "⇧ Drag: draw ramp · ⌥ Drag: draw in ticks · ⌘ Drag: snap to neutral value · ⇧ Wheel: scroll horizontally",
                   3000, "the exact sweep hint recovers at the stationary dismissal point")
        compare(revision(), before, "shortcut hover and menu dismissal never edit the song")
        var statics = findChild(page, "automationStatics")
        var idleFrame = RollNoteFaces.grab(testCase, statics)
        mouseMove(input, input.width * 0.25, input.height * 0.85)
        mousePress(input, input.width * 0.25, input.height * 0.85, Qt.RightButton)
        mouseMove(input, input.width * 0.4, input.height * 0.85, -1, Qt.RightButton)
        tryCompare(model, "bandVisible", true, 3000,
                   "a real right drag stages its visible selection band")
        compare(revision(), before, "the held right band cannot edit the song")
        mouseRelease(input, input.width * 0.4, input.height * 0.85, Qt.RightButton)
        tryCompare(model, "bandVisible", false, 3000,
                   "right-band release retires the drag preview")
        wait(0)
        var selectedFrame = RollNoteFaces.grab(testCase, statics)
        var edgeInk = String(page.gridPalette.selectionEdge).slice(-6).toLowerCase()
        var edgeRgb = [parseInt(edgeInk.slice(0, 2), 16),
                       parseInt(edgeInk.slice(2, 4), 16),
                       parseInt(edgeInk.slice(4, 6), 16)]
        var probeY = Math.floor(selectedFrame.height * 0.35)
        var paintedEdges = 0
        for (var px = 0; px < selectedFrame.width; ++px) {
            if (selectedFrame.alpha(px, probeY) > 0
                    && Math.max(Math.abs(selectedFrame.red(px, probeY) - edgeRgb[0]),
                                Math.abs(selectedFrame.green(px, probeY) - edgeRgb[1]),
                                Math.abs(selectedFrame.blue(px, probeY) - edgeRgb[2])) < 24)
                ++paintedEdges
        }
        var fillX = Math.floor(selectedFrame.width * 0.33)
        verify(paintedEdges >= 2
               && (selectedFrame.red(fillX, probeY) !== idleFrame.red(fillX, probeY)
                   || selectedFrame.green(fillX, probeY) !== idleFrame.green(fillX, probeY)
                   || selectedFrame.blue(fillX, probeY) !== idleFrame.blue(fillX, probeY)),
               "right-band release publishes its selection fill and two edges")
        compare(revision(), before, "right-band selection leaves the song unchanged")
        var grid = gridModel()
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var coarseStep = grid.snapTicks
        var rampStartX = input.width * 0.7
        var rampEndX = input.width * 0.82
        var dipX = input.width * 0.76
        var rawStart = (rampStartX + grid.cameraScrollX) / pixelsPerTick
        var rawEnd = (rampEndX + grid.cameraScrollX) / pixelsPerTick
        var firstTick = Math.floor(rawStart / coarseStep + 0.5) * coarseStep
        var lastTick = Math.floor(rawEnd / coarseStep + 0.5) * coarseStep
        var dipTick = Math.floor(((dipX + grid.cameraScrollX) / pixelsPerTick)
                                 / coarseStep + 0.5) * coarseStep
        var dipFraction = (dipTick - firstTick) / (lastTick - firstTick)
        var lineY = input.height * (0.8 - dipFraction * 0.6)
        verify(firstTick < dipTick && dipTick < lastTick,
               "the grid places the ramp dip strictly between its snapped endpoints")
        verify(dipX > 0 && dipX < input.width && input.height * 0.95 < input.height
               && Math.abs(input.height * 0.95 - lineY) > model.baseFontPx,
               "the actual in-bounds dip pointer differs from the endpoint interpolation")
        mouseMove(input, input.width * 0.7, input.height * 0.8)
        mousePress(input, input.width * 0.7, input.height * 0.8,
                   Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(input, input.width * 0.76, input.height * 0.95,
                  -1, Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(input, input.width * 0.82, input.height * 0.2,
                  -1, Qt.LeftButton, Qt.ShiftModifier)
        tryCompare(model, "interactionActive", true, 3000,
                   "Shift-left drag stages the ramp while held")
        compare(revision(), before, "the Shift ramp cannot write before release")
        mouseRelease(input, input.width * 0.82, input.height * 0.2,
                     Qt.LeftButton, Qt.ShiftModifier)
        tryCompare(model, "interactionActive", false, 3000,
                   "Shift ramp release retires its held transaction")
        tryCompare(gridModel(), "appliedRevisionText", String(Number(before) + 1), 3000,
                   "mounted Shift ramp release makes exactly one song edit")
        var rampNodes = collectByName(page, "automationNodeFill", []).map(function(fill) {
            return fill.parent.model
        })
        var firstNode = rampNodes.find(function(node) { return node.tick === firstTick })
        var dipNode = rampNodes.find(function(node) { return node.tick === dipTick })
        var lastNode = rampNodes.find(function(node) { return node.tick === lastTick })
        verify(firstNode && dipNode && lastNode,
               "the released ramp publishes the independently snapped endpoint and middle ticks")
        var expectedMidValue = Math.round(firstNode.value
            + dipFraction * (lastNode.value - firstNode.value))
        var dippedValue = Math.round(firstNode.value
            + (0.95 - 0.8) / (0.2 - 0.8) * (lastNode.value - firstNode.value))
        verify(dippedValue !== expectedMidValue,
               "the in-bounds dip maps away from the independently interpolated midpoint")
        compare(dipNode.value, expectedMidValue,
                "the released middle node follows endpoint interpolation rather than the dip")
        var scaleLabels = collectByName(page, "automationScaleLabel", [])
        var axisHigh = null
        var axisLow = null
        for (var s = 0; s < scaleLabels.length; ++s) {
            var axisNumber = parseFloat(scaleLabels[s].text)
            if (!isFinite(axisNumber))
                continue
            var axisCenter = scaleLabels[s].mapToItem(input, scaleLabels[s].width / 2,
                                                     scaleLabels[s].height / 2)
            if (axisHigh === null || axisNumber > axisHigh.value)
                axisHigh = { value: axisNumber, y: axisCenter.y }
            if (axisLow === null || axisNumber < axisLow.value)
                axisLow = { value: axisNumber, y: axisCenter.y }
        }
        verify(axisHigh !== null && axisLow !== null && axisHigh.value > axisLow.value
               && axisHigh.y < axisLow.y,
               "the static value axis calibrates the pointer mapping")
        function axisValueAt(pointerY) {
            var clamped = Math.min(Math.max(pointerY, axisHigh.y), axisLow.y)
            return Math.round(axisHigh.value - (clamped - axisHigh.y)
                              * (axisHigh.value - axisLow.value) / (axisLow.y - axisHigh.y))
        }
        var startMapped = axisValueAt(input.height * 0.8)
        var endMapped = axisValueAt(input.height * 0.2)
        var dipMapped = axisValueAt(input.height * 0.95)
        var midMapped = Math.round(startMapped + dipFraction * (endMapped - startMapped))
        verify(dipMapped !== midMapped,
               "the pointer-mapped dip differs from the pointer-mapped endpoint interpolation")
        var afterRamp = revision()
        input.forceActiveFocus(Qt.MouseFocusReason)
        keyClick(Qt.Key_B)
        tryCompare(model, "isPencilMode", true, 3000,
                   "mounted B arms the pencil for its actual stroke")
        mouseMove(input, input.width * 0.9, input.height * 0.15)
        mousePress(input, input.width * 0.9, input.height * 0.15, Qt.LeftButton)
        tryCompare(model, "interactionActive", true, 3000,
                   "the pencil press stages a real edit before release")
        compare(revision(), afterRamp, "a held pencil stroke has not written yet")
        mouseRelease(input, input.width * 0.9, input.height * 0.15, Qt.LeftButton)
        tryCompare(model, "interactionActive", false, 3000,
                   "pencil release retires its held transaction")
        tryCompare(gridModel(), "appliedRevisionText", String(Number(afterRamp) + 1), 3000,
                   "mounted pencil release makes exactly one song edit")
        var afterPencil = revision()
        input.forceActiveFocus(Qt.MouseFocusReason)
        keyClick(Qt.Key_B)
        tryCompare(model, "isPencilMode", false, 3000,
                   "mounted B restores sweep mode for the fine-grid gesture")
        var clockStep = Math.max(1, Math.floor(grid.ticksPerBeat / 24))
        var pixelTickTolerance = Math.ceil(1 / pixelsPerTick)
        var altStartX = input.width * 0.25
        var altY = input.height * 0.5
        // The arming travel the test drives; production maps the press itself
        // directly and compensates only post-activation release coordinates.
        var slopTravel = model.baseFontPx * 3
        var fineEndpoint = null
        var priorNodes = collectByName(page, "automationNodeFill", []).map(function(fill) {
            return fill.parent.model.tick
        })
        for (var delta = model.baseFontPx * 4; delta < input.width * 0.5;
             delta += model.baseFontPx) {
            var candidateX = altStartX + delta
            var rawTick = (candidateX - slopTravel + grid.cameraScrollX)
                          / pixelsPerTick
            var fineTick = Math.floor(rawTick / clockStep + 0.5) * clockStep
            var coarseTick = Math.floor(rawTick / coarseStep + 0.5) * coarseStep
            if (Math.abs(fineTick - coarseTick) > pixelTickTolerance
                    && priorNodes.indexOf(fineTick) < 0) {
                fineEndpoint = { x: candidateX, tick: fineTick, coarse: coarseTick }
                break
            }
        }
        verify(fineEndpoint && fineEndpoint.x < input.width,
               "the grid exposes a visible Alt endpoint distinct from coarse snap")
        mouseMove(input, altStartX, altY)
        mousePress(input, altStartX, altY, Qt.LeftButton, Qt.AltModifier)
        mouseMove(input, altStartX + slopTravel, altY,
                  -1, Qt.LeftButton, Qt.AltModifier)
        mouseMove(input, fineEndpoint.x, altY - model.baseFontPx,
                  -1, Qt.LeftButton, Qt.AltModifier)
        tryCompare(model, "interactionActive", true, 3000,
                   "the actual Alt-left sweep stages before its release")
        compare(revision(), afterPencil, "the held fine-grid sweep has not edited the song")
        mouseRelease(input, fineEndpoint.x, altY - model.baseFontPx,
                     Qt.LeftButton, Qt.AltModifier)
        tryCompare(gridModel(), "appliedRevisionText", String(Number(afterPencil) + 1), 3000,
                   "the mounted Alt sweep commits exactly one song edit")
        var fineNodes = collectByName(page, "automationNodeFill", [])
        var writtenTicks = fineNodes.map(function(fill) { return fill.parent.model.tick })
                                    .filter(function(tick) { return priorNodes.indexOf(tick) < 0 })
        verify(writtenTicks.some(function(tick) {
            return Math.abs(tick - fineEndpoint.tick) <= pixelTickTolerance
                && Math.abs(tick - fineEndpoint.coarse) > pixelTickTolerance
        }), "the visible Alt stroke follows the fine endpoint within one painted pixel, not coarse snap")
    }
    function test_dGripKeyboardIsolation() {
        openDrawerShell("automations")
        var page = automationPageItem()
        var plot = findChild(page, "automationPlot")
        var grip = findChild(selectedSurface(), "drawerHandle_automation")
        verify(grip && plot, "the automation grip and plot are mounted")

        clickFirstGridNote()
        var notes = JSON.stringify(JSON.parse(gridModel().fetchNoteSummary()))

        plot.forceActiveFocus(Qt.OtherFocusReason)
        verify(waitForNative(function() {
            var window = plot.Window.window
            return window && window.activeFocusItem === plot
        }, 3000), "the automation plot holds window focus")
        var focusPath = []
        var gripFocused = false
        for (var count = 0; count < 80 && !gripFocused; ++count) {
            keyClick(Qt.Key_Tab)
            wait(0)
            var window = plot.Window.window
            var focused = window ? window.activeFocusItem : null
            focusPath.push(focused ? focused.objectName : "<none>")
            gripFocused = grip.activeFocus
        }
        verify(gripFocused, "Tab traversal reaches the grip: " + focusPath.join(" -> "))

        var before = revision()
        var height = plot.height
        keyClick(Qt.Key_Up)
        verify(waitForNative(function() { return plot.height > height }, 3000),
               "Up grows the automation plot")
        keyClick(Qt.Key_Down)
        verify(waitForNative(function() { return plot.height === height }, 3000),
               "Down restores the automation plot")
        keyClick(Qt.Key_Left)
        wait(100)
        keyClick(Qt.Key_Right)
        wait(100)
        compare(plot.height, height, "horizontal arrows never resize the plot")
        compare(revision(), before, "grip keys never edit the song")
        compare(JSON.stringify(JSON.parse(gridModel().fetchNoteSummary())), notes,
                "grip keys never touch the selection")
    }
}
