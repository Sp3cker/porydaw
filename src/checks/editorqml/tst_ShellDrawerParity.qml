import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellDrawerParity"
    when: windowShown
    width: 1100
    height: 760
    visible: true

    property var shell: null
    readonly property var settings: bootstrap.preferences

    ShellQmlBootstrap { id: bootstrap }

    Component { id: shellComponent; ShellWindow { width: 1100; height: 760; visible: true } }


    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            var settled = false
            for (var step = 0; step < 12 && !settled; ++step) {
                var gate = waitForNative(function() {
                    return shell.shellPresenter.closeReady
                        || shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                }, 5000)
                if (!gate)
                    break
                if (shell.shellPresenter.closeReady) {
                    settled = true
                    break
                }
                shell.shellPresenter.session.songTabs.confirmDiscard()
                wait(50)
            }
            verify(shell.shellPresenter.closeReady,
                   "teardown waits for scene destruction and grid detach")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openDiagnostics(session) {
        var labels = []
        for (var i = 0; i < session.songCount() && i < 8; ++i)
            labels.push(session.songLabel(i))
        return " (projectRoot=" + bootstrap.projectRoot
            + "; projectOpen=" + session.projectOpen
            + "; songOpen=" + session.songOpen
            + "; stagedLabels=[" + labels.join(",") + "]"
            + "; lastSaveError=" + session.lastSaveError
            + "; status=" + shell.shellPresenter.statusText + ")"
    }

    function openDrawerShell(activePage) {
        settings.setBool("editorDrawer.velocityVisible", true)
        settings.setInt("editorDrawer.velocityHeight", 173)
        settings.setBool("editorDrawer.automationVisible", true)
        settings.setInt("editorDrawer.automationHeight", 220)
        settings.setBool("editorDrawer.voiceChangesVisible", true)
        settings.setInt("editorDrawer.voiceChangesHeight", 220)
        settings.setString("editorDrawer.activePage", activePage)
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "Route 101 loads" + openDiagnostics(session))
        tryCompare(session.songTabs, "tabCount", 1)
        verify(waitForNative(function() {
            var surface = selectedSurface()
            return surface !== null && surface.visible && surface.width > 0
        }, 5000), "the selected tab page is mounted")
        verify(waitForNative(function() {
            return automationPlotInput() !== null && voicePlotInput() !== null
                && automationPlotInput().visible && voicePlotInput().visible
        }, 5000), "both drawer plots are mounted and drawn")
        waitForRendering(tabsRoot())
    }

    function session() { return shell.shellPresenter.session }
    function tabsRoot() { return shell.sceneLoader.item }
    function selectedSurface() {
        var tabs = session().songTabs
        var page = findChild(tabsRoot(), "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }
    function gridModel() { return selectedSurface().gridModel }
    function revision() { return gridModel().appliedRevisionText }
    function rollInput() { return findChild(selectedSurface(), "swiftRollInput") }
    function automationModel() { return session().automationPage() }
    function voiceModel() { return session().voiceChangesPage() }
    function automationPageItem() { return findChild(selectedSurface(), "automationPage") }
    function voicePageItem() { return findChild(selectedSurface(), "voiceChangesPage") }
    function automationPlotInput() {
        var page = automationPageItem()
        return page ? findChild(page, "automationPlotInput") : null
    }
    function voicePlotInput() {
        var page = voicePageItem()
        return page ? findChild(page, "voicePlotInput") : null
    }

    function collectByName(item, name, found) {
        var collected = found || []
        if (!item)
            return collected
        if (item.objectName === name)
            collected.push(item)
        if (!item.children)
            return collected
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectByName(item.children[i], name, collected)
        return collected
    }

    function regionOf(image, anchor, control) {
        var origin = control.mapToItem(anchor, 0, 0)
        var scaleX = anchor.width > 0 ? image.width / anchor.width : 1
        var scaleY = anchor.height > 0 ? image.height / anchor.height : 1
        return { x0: Math.max(0, Math.round(origin.x * scaleX)),
                 y0: Math.max(0, Math.round(origin.y * scaleY)),
                 x1: Math.min(image.width - 1,
                              Math.round((origin.x + control.width) * scaleX) - 1),
                 y1: Math.min(image.height - 1,
                              Math.round((origin.y + control.height) * scaleY) - 1) }
    }


    function pixelDistance(image, x, y, target) {
        return Math.max(Math.abs(image.red(x, y) - target[0]),
                        Math.abs(image.green(x, y) - target[1]),
                        Math.abs(image.blue(x, y) - target[2]))
    }

    function pixelsDiffer(before, after, x, y) {
        return before.red(x, y) !== after.red(x, y)
            || before.green(x, y) !== after.green(x, y)
            || before.blue(x, y) !== after.blue(x, y)
    }

    function changedPixels(before, after, region, limit) {
        var changed = 0
        var cap = limit || 1000000
        for (var x = region.x0; x <= region.x1; ++x) {
            for (var y = region.y0; y <= region.y1; ++y) {
                if (pixelsDiffer(before, after, x, y)) {
                    if (++changed > cap)
                        return changed
                }
            }
        }
        return changed
    }
    function grabRegionStable(item, region) {
        var previous = grabImage(item)
        for (var i = 0; i < 20; ++i) {
            wait(100)
            var next = grabImage(item)
            if (changedPixels(previous, next, region, 0) === 0)
                return next
            previous = next
        }
        return previous
    }

    function grabUntilDifferent(item, reference, region) {
        var frame = grabImage(item)
        for (var i = 0; i < 30 && changedPixels(reference, frame, region, 0) <= 0; ++i) {
            wait(100)
            frame = grabImage(item)
        }
        return frame
    }

    function gridPointFor(tick, pitch) {
        var grid = gridModel()
        var surface = selectedSurface()
        var fills = findChild(surface, "timelineQuickPianoNoteFills")
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var x = tick * pixelsPerTick - grid.cameraScrollX
        var y = (127.0 - pitch + 0.5) * grid.rowHeight - grid.cameraScrollY
        return fills.mapToItem(rollInput(), x, y)
    }

    function clickFirstGridNote() {
        var input = rollInput()
        var notes = JSON.parse(gridModel().noteSummary)
        verify(notes.length > 0, "the staged song publishes notes")
        var target = null
        for (var n = 0; n < notes.length && !target; ++n) {
            var center = gridPointFor(notes[n].tick + notes[n].duration / 2,
                                      notes[n].pitch)
            if (center.x > 1 && center.y > 1
                    && center.x < input.width - 1 && center.y < input.height - 1)
                target = center
        }
        verify(target, "the fixture exposes a note a click can reach")
        mouseClick(input, target.x, target.y)
        verify(waitForNative(function() {
            return JSON.parse(gridModel().noteSummary).some(function(note) {
                return note.selected
            })
        }, 5000), "the real click selected one grid note")
    }

    function test_aAutomationHoverRaster() {
        openDrawerShell("automations")
        var parameters = ["Pan", "Tempo"]
        for (var p = 0; p < parameters.length; ++p)
            checkAutomationParameter(parameters[p])
    }

    function checkAutomationParameter(parameter) {
        var page = automationPageItem()
        var input = automationPlotInput()
        var model = automationModel()
        verify(page && input && model, "the automation page is mounted")
        var tab = null
        for (var i = 0; i < model.tabCount; ++i) {
            var candidate = findChild(page, "automationParameterTab" + i)
            if (candidate && candidate.text === parameter)
                tab = candidate
        }
        verify(tab, "missing parameter tab: " + parameter)
        tab.forceActiveFocus(Qt.TabFocusReason)
        mouseClick(tab, tab.width * 0.2, tab.height / 2)
        verify(waitForNative(function() { return tab.checked }, 3000),
               parameter + " activates by pointer")
        var roll = rollInput()
        mouseMove(roll, 20, 20)
        verify(waitForNative(function() { return !model.hoverVisible }, 3000),
               "no hover is published away from the plot")
        var before = revision()
        verify(before.length > 0, "the document publishes its revision")
        var capture = shell.contentItem
        var idleRegion = regionOf(grabImage(capture), capture, input)
        var idle = grabRegionStable(capture, idleRegion)
        verify(idle.width > 0, "the idle plot composited into an image")

        var insertion = { x: input.width * 0.55, y: input.height * 0.5 }
        mouseMove(input, insertion.x, insertion.y)
        verify(waitForNative(function() { return model.hoverVisible }, 3000),
               parameter + " publishes its insertion hover")
        var hovered = grabUntilDifferent(capture, idle, idleRegion)
        var inputRegion = regionOf(hovered, capture, input)
        verify(changedPixels(idle, hovered, inputRegion, 0) > 0,
               parameter + ": the insertion hover paints")
        compare(revision(), before, parameter + ": hovering writes nothing")
        mouseMove(input, insertion.x, insertion.y)
        var repeated = grabRegionStable(capture, inputRegion)
        compare(changedPixels(hovered, repeated, inputRegion, 0), 0,
                parameter + ": the repeated hover is pixel-stable")

        mouseMove(roll, 20, 20)
        verify(waitForNative(function() { return !model.hoverVisible }, 3000),
               parameter + ": leaving the plot clears the hover")
        waitForRendering(tabsRoot())
        var cleared = grabRegionStable(capture, inputRegion)
        compare(changedPixels(idle, cleared, inputRegion, 0), 0,
                parameter + ": the cleared plot matches idle")
        compare(revision(), before, parameter + ": the hover round trip writes nothing")

        var fills = collectByName(page, "automationNodeFill", [])
        verify(fills.length > 0, parameter + ": the lane draws written nodes")
        var node = null
        for (var f = 0; f < fills.length && !node; ++f) {
            var fill = fills[f]
            if (!fill.visible)
                continue
            var center = fill.mapToItem(input, fill.width / 2, fill.height / 2)
            if (center.x > 12 && center.y > 12
                    && center.x < input.width - 12 && center.y < input.height - 12)
                node = { item: fill, at: center }
        }
        verify(node, "the fixture exposes a written node away from plot edges")
        var ring = findChild(node.item.parent, "automationNodeHover")
        verify(ring, "the node carries its hover ring")
        var ringRegion = regionOf(idle, capture, ring)
        mouseMove(input, node.at.x, node.at.y)
        verify(waitForNative(function() {
            var rings = collectByName(automationPageItem(), "automationNodeHover", [])
            return rings.some(function(item) { return item.visible })
        }, 3000), parameter + ": the node hover ring draws")
        waitForRendering(tabsRoot())
        var ringFrame = grabUntilDifferent(capture, idle, ringRegion)
        verify(changedPixels(idle, ringFrame, ringRegion, 0) > 0,
               parameter + ": the ring paints")
        compare(revision(), before, parameter + ": node hovering writes nothing")
        mouseMove(roll, 20, 20)
        verify(waitForNative(function() {
            var rings = collectByName(automationPageItem(), "automationNodeHover", [])
            return !rings.some(function(item) { return item.visible })
        }, 3000), parameter + ": leaving the node clears the ring")
        waitForRendering(tabsRoot())
        var ringCleared = grabRegionStable(capture, inputRegion)
        compare(changedPixels(idle, ringCleared, inputRegion, 0), 0,
                parameter + ": the plot returns to idle")
        compare(revision(), before, parameter + ": the ring round trip writes nothing")
    }

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
        mouseMove(input, marker.x, marker.y)
        tryCompare(model, "hoverHintProfile", 21, 3000,
                   "the marker hover resolves its hint profile")
        var before = revision()
        verify(before.length > 0, "the document publishes its revision")
        var capture = shell.contentItem
        var idleRegion = regionOf(grabImage(capture), capture, input)
        var idle = grabRegionStable(capture, idleRegion)
        verify(idle.width > 0, "the idle plot composited into an image")
        var inputRegion = regionOf(idle, capture, input)

        mousePress(input, marker.x, marker.y, Qt.LeftButton)
        wait(50)
        compare(revision(), before, "pressing the marker writes nothing")
        verify(!preview.visible, "pressing shows no preview yet")
        waitForRendering(tabsRoot())
        var pressed = grabRegionStable(capture, inputRegion)
        compare(pressed.width, idle.width, "press keeps the frame size")
        compare(changedPixels(idle, pressed, inputRegion, 0), 0,
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
        var draft = grabUntilDifferent(capture, idle, inputRegion)
        verify(changedPixels(idle, draft, inputRegion, 0) > 0, "the draft paints")
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
        var settled = grabRegionStable(capture, inputRegion)
        compare(changedPixels(idle, settled, inputRegion, 0), 0,
                "the plot settles back to idle")
    }

    function test_dGripKeyboardIsolation() {
        openDrawerShell("automations")
        var page = automationPageItem()
        var plot = findChild(page, "automationPlot")
        var grip = findChild(selectedSurface(), "drawerHandle_automation")
        verify(grip && plot, "the automation grip and plot are mounted")

        clickFirstGridNote()
        var notes = JSON.stringify(JSON.parse(gridModel().noteSummary))

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
        compare(JSON.stringify(JSON.parse(gridModel().noteSummary)), notes,
                "grip keys never touch the selection")
    }
}
