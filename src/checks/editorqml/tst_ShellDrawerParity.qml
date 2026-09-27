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
    function velocityPageItem() { return findChild(selectedSurface(), "velocityPage") }
    function velocityPlotInput() {
        var page = velocityPageItem()
        return page ? findChild(page, "velocityPlotInput") : null
    }
    function velocityHandleFor(noteId) {
        var fills = collectByName(velocityPageItem(), "velocityNodeFill", [])
        for (var i = 0; i < fills.length; ++i) {
            var handle = fills[i].parent.model
            if (handle && handle.noteIdText === String(noteId))
                return handle
        }
        return null
    }
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
    function colorChannels(color) {
        var hex = String(color).replace("#", "")
        if (hex.length === 8)
            hex = hex.slice(2)
        return [parseInt(hex.slice(0, 2), 16), parseInt(hex.slice(2, 4), 16),
                parseInt(hex.slice(4, 6), 16)]
    }

    function paintedColor(image, capture, item, color) {
        var region = regionOf(image, capture, item)
        var expected = colorChannels(color)
        for (var y = region.y0; y <= region.y1; ++y) {
            for (var x = region.x0; x <= region.x1; ++x) {
                if (pixelDistance(image, x, y, expected) <= 3)
                    return true
            }
        }
        return false
    }
    function nearestPaintedColor(image, capture, item, color) {
        var region = regionOf(image, capture, item)
        var expected = colorChannels(color)
        var nearest = 255
        for (var y = region.y0; y <= region.y1; ++y) {
            for (var x = region.x0; x <= region.x1; ++x)
                nearest = Math.min(nearest, pixelDistance(image, x, y, expected))
        }
        return nearest
    }
    function compositedColor(base, overlay) {
        var color = String(overlay).replace("#", "")
        var alpha = color.length === 8 ? parseInt(color.slice(0, 2), 16) / 255 : 1
        var ink = colorChannels(overlay)
        return base.map(function(channel, index) {
            return Math.round(channel * (1 - alpha) + ink[index] * alpha)
        })
    }
    function forkStemShade(trackFill) {
        var rgb = colorChannels(trackFill).map(function(value) {
            var channel = value / 255
            return channel <= 0.04045 ? channel / 12.92
                                      : Math.pow((channel + 0.055) / 1.055, 2.4)
        })
        var l = Math.pow(0.4122214708 * rgb[0] + 0.5363325363 * rgb[1]
                         + 0.0514459929 * rgb[2], 1 / 3)
        var m = Math.pow(0.2119034982 * rgb[0] + 0.6806995451 * rgb[1]
                         + 0.1073969566 * rgb[2], 1 / 3)
        var s = Math.pow(0.0883024619 * rgb[0] + 0.2817188376 * rgb[1]
                         + 0.6299787005 * rgb[2], 1 / 3)
        var light = (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s) * 2 / 3
        var a = (1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s) * 2 / 3
        var b = (0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s) * 2 / 3
        var ll = light + 0.3963377774 * a + 0.2158037573 * b
        var mm = light - 0.1055613458 * a - 0.0638541728 * b
        var ss = light - 0.0894841775 * a - 1.2914855480 * b
        function gamma(value) {
            var channel = value <= 0.0031308 ? 12.92 * value
                           : 1.055 * Math.pow(Math.max(0, value), 1 / 2.4) - 0.055
            return Math.round(Math.max(0, Math.min(255, channel * 255)))
        }
        return "#" + [
            gamma(4.0767416621 * ll * ll * ll - 3.3077115913 * mm * mm * mm
                  + 0.2309699292 * ss * ss * ss),
            gamma(-1.2684380046 * ll * ll * ll + 2.6097574011 * mm * mm * mm
                  - 0.3413193965 * ss * ss * ss),
            gamma(-0.0041960863 * ll * ll * ll - 0.7034186147 * mm * mm * mm
                  + 1.7076147010 * ss * ss * ss)
        ].map(function(value) { return ("0" + value.toString(16)).slice(-2) }).join("")
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
        var plot = findChild(surface, "timelineQuickRollPlot")
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var x = tick * pixelsPerTick - grid.cameraScrollX
        var y = (127.0 - pitch + 0.5) * grid.rowHeight - grid.cameraScrollY
        return plot.mapToItem(rollInput(), x, y)
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
    function test_eVelocityLateUnlock() {
        dragMountedVelocity(false)
    }

    function test_fVelocityEarlyUnlock() {
        dragMountedVelocity(true)
    }

    function dragMountedVelocity(unlockAtPress) {
        openDrawerShell("velocity")
        var model = session().velocityPage()
        var input = velocityPlotInput()
        var detent = findChild(selectedSurface(), "drawerDetent")
        verify(model && input && detent && input.visible,
               "the real velocity page, input delegate and detent control are mounted")
        var grid = gridModel()
        grid.setTrack(0)
        verify(!detent.visible,
               "the direct-sound context hides the composed detent before PSG staging")
        var voiceInput = voicePlotInput()
        var voicePage = voiceModel()
        verify(voiceInput && voiceInput.visible && voicePage,
               "the mounted voice-change delegate can stage a square program before the drag")
        grid.setCameraHScroll(0)
        var insertionX = grid.beatWidth * 2.5
        verify(insertionX > 0 && insertionX < voiceInput.width,
               "the program-change column is visible before the chosen notes")
        mouseDoubleClickSequence(voiceInput, insertionX, voiceInput.height / 2, Qt.LeftButton)
        tryCompare(voicePage, "pickerOpen", true)
        var search = findChild(selectedSurface(), "voicePickerSearch")
        verify(waitForNative(function() { return search && search.activeFocus }, 3000),
               "the actual voice picker focuses its search field")
        keyClick(Qt.Key_0)
        keyClick(Qt.Key_0)
        keyClick(Qt.Key_4)
        tryCompare(voicePage, "pickerHasMatch", true)
        keyClick(Qt.Key_Return)
        tryCompare(voicePage, "pickerOpen", false)
        var originalNotes = JSON.parse(grid.noteSummary).filter(function(note) {
            return note.track === 0 && !note.ghost
        })
        verify(originalNotes.length >= 6 && originalNotes[3].velocity === 98
               && originalNotes[4].velocity === 104 && originalNotes[5].velocity === 110,
               "the three staged notes after the square change are literal 98/104/110")
        var notes = [originalNotes[3], originalNotes[5], originalNotes[4]]
        var capture = shell.contentItem
        var page = velocityPageItem()
        var unselectedFill = collectByName(page, "velocityNodeFill", []).find(function(fill) {
            return fill.parent.model.noteIdText === String(notes[0].id)
        })
        verify(unselectedFill, "the staged ordinary velocity node is mounted before selection")
        waitForRendering(tabsRoot())
        var ordinaryFrame = grabImage(capture)
        verify(nearestPaintedColor(ordinaryFrame, capture, unselectedFill,
                                   page.gridPalette.noteBorder) <= 16,
               "an ordinary velocity node paints the antialiased semantic black outline")
        verify(paintedColor(ordinaryFrame, capture, unselectedFill,
                            page.gridPalette.noteFill(0, 127)),
               "an ordinary velocity node paints its track identity fill")
        var roll = rollInput()
        grid.setCameraVScroll((127 - (notes[0].pitch + notes[1].pitch) / 2 + 0.5)
                              * grid.rowHeight - roll.height / 2)
        for (var i = 0; i < 2; ++i) {
            var position = gridPointFor(notes[i].tick + notes[i].duration / 2,
                                        notes[i].pitch)
            verify(position.x > 0 && position.x < roll.width
                   && position.y > 0 && position.y < roll.height,
                   "each staged drag note maps into the mounted roll")
            mouseClick(roll, position.x, position.y, Qt.LeftButton,
                       i === 0 ? Qt.NoModifier : Qt.ControlModifier)
        }
        verify(waitForNative(function() {
            return model.selectedCount === 2 && model.detentsAvailable
                && detent.visible && detent.enabled
        }, 5000), "the selected square notes enable the rendered detent control: "
           + JSON.stringify({ selectedCount: model.selectedCount, available: model.detentsAvailable,
                              visible: detent.visible, enabled: detent.enabled, slot: model.contextSlot,
                              selected: JSON.parse(grid.noteSummary).filter(function(note) {
                                  return note.selected
                              }).map(function(note) { return [note.id, note.velocity] }) }))
        var plot = findChild(page, "velocityPlot")
        var ruler = findChild(page, "velocityRuler")
        var drawer = findChild(selectedSurface(), "editorDrawer")
        var bar = findChild(drawer, "drawerBar")
        var velocityToggle = findChild(drawer, "drawerToggle_velocity")
        var automationToggle = findChild(drawer, "drawerToggle_automation")
        verify(plot && ruler && bar && velocityToggle && automationToggle,
               "the composed velocity plot, ruler and drawer chrome are visible")
        var bounds = detent.mapToItem(drawer, 0, 0)
        var band = ruler.mapToItem(drawer, 0, 0)
        var plotLeft = plot.mapToItem(drawer, 0, 0).x
        verify(bar.visible && velocityToggle.visible
               && velocityToggle.x >= bar.x
               && velocityToggle.x + velocityToggle.width <= bar.x + bar.width
               && velocityToggle.y >= bar.y
               && velocityToggle.y + velocityToggle.height <= bar.y + bar.height,
               "the rendered velocity toggle is wholly inside its visible bar")
        compare(velocityToggle.x, automationToggle.x + automationToggle.width
                + Math.round(grid.baseFontPx / 4),
                "velocity chrome follows automation by base-font spacing")
        verify(Math.abs(bounds.x - band.x) <= 1 / page.Screen.devicePixelRatio
               && Math.abs(bounds.y + detent.height - band.y - ruler.height)
                  <= 1 / page.Screen.devicePixelRatio
               && bounds.x + detent.width < plotLeft,
               "the visible detent aligns with the band bottom to the left of the plot")
        var graduation = collectByName(ruler, "velocityRulerGraduations", [])
        verify(graduation.length === 1,
               "the composed ruler has an intrinsic graduation paint layer")
        var ring = findChild(collectByName(page, "velocityNodeFill", []).find(function(fill) {
            return fill.parent.model.noteIdText === String(notes[0].id)
        }).parent, "velocityNodeRing")
        var outsiderFill = collectByName(page, "velocityNodeFill", []).find(function(fill) {
            return fill.parent.model.noteIdText === String(notes[2].id)
        })
        var outsiderStem = findChild(outsiderFill.parent, "velocityNodeStem")
        verify(ring && outsiderStem && outsiderFill, "selected and unselected note paint is mounted")
        waitForRendering(tabsRoot())
        var selectedFrame = grabImage(capture)
        verify(paintedColor(selectedFrame, capture, ring, page.gridPalette.selectionRing),
               "the selected velocity ring paints the semantic highlight ink")
        var expectedStem = forkStemShade(page.gridPalette.noteFill(0, 127))
        verify(nearestPaintedColor(selectedFrame, capture, outsiderStem, expectedStem) <= 16,
               "the outsider stem paints the independent one-third Oklab track shade")
        verify(paintedColor(selectedFrame, capture, outsiderFill, page.gridPalette.outline),
               "the unselected note paints the semantic dimmed mid ink")
        compare(outsiderFill.border.width, 0,
                "a dimmed note no longer paints an ordinary black outline")
        mouseMove(input, outsiderFill.parent.model.x, outsiderFill.parent.model.y,
                  -1, Qt.NoButton)
        verify(waitForNative(function() {
            return model.hoveredNoteText === String(notes[2].id)
        }, 3000), "hovering the outsider selects its own ruler context")
        var hoverFrame = grabImage(capture)
        verify(paintedColor(hoverFrame, capture, graduation[0],
                            page.gridPalette.selectionRing),
               "the active ruler graduation paints the semantic separator accent")
        mouseMove(input, input.width - 3, input.height - 3, -1, Qt.NoButton)
        var checkedFrame = grabRegionStable(capture, regionOf(selectedFrame, capture, detent))
        mouseClick(detent, detent.width / 2, detent.height / 2)
        tryCompare(detent.Accessible, "checked", false)
        var uncheckedFrame = grabUntilDifferent(capture, checkedFrame,
                                                 regionOf(checkedFrame, capture, detent))
        verify(changedPixels(checkedFrame, uncheckedFrame,
                             regionOf(checkedFrame, capture, detent), 0) > 0,
               "clicking the detent visibly repaints its unchecked ink")
        mouseClick(detent, detent.width / 2, detent.height / 2)
        tryCompare(detent.Accessible, "checked", true)
        var restoredFrame = grabUntilDifferent(capture, uncheckedFrame,
                                                regionOf(uncheckedFrame, capture, detent))
        verify(changedPixels(uncheckedFrame, restoredFrame,
                             regionOf(restoredFrame, capture, detent), 0) > 0,
               "clicking the detent visibly repaints its checked ink")
        compare(model.axisMode, 1, "the mounted square context publishes its intrinsic axis")
        compare(detent.Accessible.checked, model.detentsEnabled,
                "the rendered detent control reflects the enabled page preference")
        mouseClick(detent, detent.width / 2, detent.height / 2)
        tryCompare(model, "detentsEnabled", false)
        tryCompare(detent.Accessible, "checked", false, 3000,
                   "the rendered detent control unchecks on click")
        mouseClick(detent, detent.width / 2, detent.height / 2)
        tryCompare(model, "detentsEnabled", true)
        tryCompare(detent.Accessible, "checked", true, 3000,
                   "the rendered detent control checks on click")
        var tickX = input.width * 0.4
        var anchoredTick = (tickX + grid.cameraScrollX) * grid.ticksPerBeat / grid.beatWidth
        var oldBeatWidth = grid.beatWidth
        mouseWheel(input, tickX, input.height / 2, 0, 120, Qt.NoButton, Qt.NoModifier)
        verify(waitForNative(function() { return grid.beatWidth > oldBeatWidth }, 3000),
               "the velocity plot routes a real wheel zoom into the shared camera")
        verify(Math.abs(anchoredTick * grid.beatWidth / grid.ticksPerBeat
                        - grid.cameraScrollX - tickX)
               <= 1 / page.Screen.devicePixelRatio,
               "a real velocity wheel holds its tick under the pointer within one physical pixel")
        mouseWheel(input, tickX, input.height / 2, 0, -120, Qt.NoButton, Qt.NoModifier)
        verify(waitForNative(function() { return grid.beatWidth <= oldBeatWidth }, 3000),
               "the reverse velocity wheel restores the gesture's original time zoom")
        grid.setCameraHScroll(0)
        var velocityBody = findChild(drawer, "drawerBody_velocity")
        var bodyHeight = velocityBody.height
        var rowCount = collectByName(page, "velocityNodeFill", []).length
        var textRowCount = ruler.children.filter(function(item) {
            return item.labelText !== undefined
        }).length
        verify(textRowCount > 0, "the mounted velocity ruler has painted text rows")
        mouseClick(velocityToggle, velocityToggle.width / 2, velocityToggle.height / 2)
        tryCompare(velocityBody, "visible", false)
        compare(settings.int("editorDrawer.velocityHeight", -1), bodyHeight,
                "hiding velocity retains its requested section height in preferences")
        mouseClick(velocityToggle, velocityToggle.width / 2, velocityToggle.height / 2)
        tryCompare(velocityBody, "visible", true)
        compare(velocityBody.height, bodyHeight,
                "showing velocity restores its requested body height")
        compare(collectByName(page, "velocityNodeFill", []).length, rowCount,
                "velocity hide and show retain every painted note row")
        compare(ruler.children.filter(function(item) {
            return item.labelText !== undefined
        }).length, textRowCount,
        "velocity hide and show retain every ruler text row")
        var first = velocityHandleFor(notes[0].id)
        var later = velocityHandleFor(notes[1].id)
        var outside = velocityHandleFor(notes[2].id)
        verify(first && later && outside && first.selected && later.selected
               && !outside.selected, "the drawn velocity handles retain the exact drag selection")
        var pressX = first.x
        var pressY = first.y
        var endY = unlockAtPress
            ? Math.round(pressY - (pressY - later.y) * 7 / 8)
            : later.y
        verify(pressX > 0 && pressX < input.width
               && pressY > 0 && pressY < input.height
               && endY > 0 && endY < input.height,
               "published handle and intrinsic axis geometry keep the drag inside the plot")
        var before = revision()
        var original = grid.noteSummary
        var pressModifier = unlockAtPress ? Qt.ControlModifier : Qt.NoModifier
        var moveModifier = unlockAtPress ? Qt.NoModifier : Qt.ControlModifier
        mousePress(input, pressX, pressY, Qt.LeftButton, pressModifier)
        mouseMove(input, pressX, endY, -1, Qt.LeftButton, moveModifier)
        var quietValue = unlockAtPress ? 105 : 108
        var laterValue = unlockAtPress ? 117 : 116
        verify(waitForNative(function() {
            var quiet = velocityHandleFor(notes[0].id)
            var companion = velocityHandleFor(notes[1].id)
            return quiet && companion && quiet.preview && companion.preview
                && quiet.value === quietValue && companion.value === laterValue
        }, 3000), (unlockAtPress
            ? "an unlocked press retains the raw seven-step delta after modifier release"
            : "a late modifier preserves the snapped levels captured at press")
            + ": " + JSON.stringify({
                first: velocityHandleFor(notes[0].id)
                    ? [velocityHandleFor(notes[0].id).preview, velocityHandleFor(notes[0].id).value]
                    : null,
                later: velocityHandleFor(notes[1].id)
                    ? [velocityHandleFor(notes[1].id).preview, velocityHandleFor(notes[1].id).value]
                    : null,
                active: model.interactionActive, pressed: [pressX, pressY], target: endY,
                selection: model.selectedCount, axis: model.axisMode
            }))
        compare(velocityHandleFor(notes[2].id).preview, false,
                "the outside drawn handle has no held velocity preview")
        compare(revision(), before, "the mounted drag holds the document revision")
        compare(grid.noteSummary, original,
                "the mounted preview leaves the published roll note summary unchanged")
        mouseRelease(input, pressX, endY, Qt.LeftButton, moveModifier)
        verify(waitForNative(function() {
            var current = JSON.parse(grid.noteSummary)
            return current.some(function(note) {
                return note.id === notes[0].id && note.velocity === quietValue && note.selected
            }) && current.some(function(note) {
                return note.id === notes[1].id && note.velocity === laterValue && note.selected
            })
        }, 5000), "the mounted release commits exact selected velocities once")
        verify(revision() !== before, "the mounted release advances the document revision")
        var committed = JSON.parse(grid.noteSummary)
        compare(committed.find(function(note) { return note.id === notes[2].id }).velocity,
                104, "the outside roll note keeps its literal velocity on release")
        compare(velocityHandleFor(notes[0].id).preview, false,
                "the mounted release retires its drawn preview")
        if (unlockAtPress) {
            mountedVelocityRulerAndPaint(model, detent, input, grid, notes, 76)
            mountedRawVelocityGesture(input, grid, notes)
            mountedRawVelocityRamp(input, grid, notes)
            for (var family of [{ slot: 6, snap: 64 }, { slot: 7, snap: 76 }]) {
                mouseDoubleClickSequence(voiceInput, insertionX, voiceInput.height / 2,
                                         Qt.LeftButton)
                tryCompare(voicePage, "pickerOpen", true)
                var familySearch = findChild(selectedSurface(), "voicePickerSearch")
                verify(waitForNative(function() {
                    return familySearch && familySearch.activeFocus
                }, 3000), "the real voice picker focuses before a family replacement")
                familySearch.selectAll()
                keyClick(Qt.Key_0)
                keyClick(Qt.Key_0)
                keyClick(Qt.Key_0 + family.slot)
                tryCompare(voicePage, "pickerHasMatch", true)
                keyClick(Qt.Key_Return)
                tryCompare(voicePage, "pickerOpen", false)
                tryCompare(model, "contextSlot", family.slot)
                compare(model.axisMode, 1,
                        "the selected wave or noise voice presents its intrinsic axis")
                if (family.slot === 6) {
                    var firstRow = collectByName(ruler, "velocityGraduation", [])[0]
                    verify(firstRow, "the staged wave paints its lowest graduation")
                    var waveBounds = detent.mapToItem(drawer, 0, 0)
                    var waveCenter = firstRow.mapToItem(drawer, firstRow.width / 2,
                                                         firstRow.height / 2)
                    verify(waveCenter.y < waveBounds.y
                           || waveCenter.y > waveBounds.y + detent.height,
                           "the actual wave first graduation stays clear of the bottom detent")
                }
                mountedVelocityRulerAndPaint(model, detent, input, grid, notes, family.snap)
                mountedRawVelocityGesture(input, grid, notes)
                mountedRawVelocityRamp(input, grid, notes)
            }
            var ramp = findChild(page, "velocityRamp")
            var rampStartX = input.width * 0.6
            var rampEndX = input.width * 0.8
            var rampStartY = input.height * 0.25
            var rampEndY = input.height * 0.4
            var quietRampFrame = grabImage(capture)
            mousePress(input, rampStartX, rampStartY, Qt.LeftButton, Qt.ShiftModifier)
            mouseMove(input, rampEndX, rampEndY, -1, Qt.LeftButton, Qt.ShiftModifier)
            verify(waitForNative(function() { return ramp.visible }, 3000),
                   "a real Shift drag paints the velocity ramp preview")
            var rampFrame = grabImage(capture)
            var rampMid = ramp.mapToItem(capture, ramp.width / 2, ramp.height / 2)
            var rampPixelX = Math.round(rampMid.x * rampFrame.width / capture.width)
            var rampPixelY = Math.round(rampMid.y * rampFrame.height / capture.height)
            var rampInk = colorChannels(page.gridPalette.primaryText)
            var liveRampInk = false
            for (var px = rampPixelX - 2; px <= rampPixelX + 2; ++px) {
                for (var py = rampPixelY - 2; py <= rampPixelY + 2; ++py) {
                    if (pixelDistance(rampFrame, px, py, rampInk) <= 24
                        && pixelsDiffer(quietRampFrame, rampFrame, px, py))
                        liveRampInk = true
                }
            }
            verify(liveRampInk, "the live ramp paints new semantic edit-preview outline pixels")
            mouseRelease(input, rampEndX, rampEndY, Qt.LeftButton, Qt.ShiftModifier)
            tryCompare(ramp, "visible", false)
            var bandStartX = input.width * 0.65
            var bandEndX = input.width * 0.85
            var bandStartY = input.height * 0.55
            var bandEndY = input.height * 0.75
            var restingFrame = grabImage(capture)
            mousePress(input, bandStartX, bandStartY, Qt.RightButton)
            mouseMove(input, bandEndX, bandEndY, -1, Qt.RightButton)
            var bandFrame = grabUntilDifferent(capture, restingFrame,
                                                regionOf(restingFrame, capture, plot))
            verify(model.interactionActive,
                   "a real right-band drag owns an active selection gesture")
            var edgeOrigin = input.mapToItem(capture,
                                              bandStartX + 2 / page.Screen.devicePixelRatio,
                                              bandStartY)
            var edgeX = Math.round(edgeOrigin.x * bandFrame.width / capture.width)
            var edgeY = Math.round(edgeOrigin.y * bandFrame.height / capture.height)
            var edgeInk = colorChannels(page.gridPalette.selectionEdge)
            var paintedEdge = null
            for (var ex = edgeX - 2; ex <= edgeX + 2; ++ex) {
                for (var ey = edgeY - 2; ey <= edgeY + 2; ++ey) {
                    if (pixelDistance(bandFrame, ex, ey, edgeInk) <= 16
                        && pixelsDiffer(restingFrame, bandFrame, ex, ey))
                        paintedEdge = { x: ex, y: ey }
                }
            }
            verify(paintedEdge !== null,
                   "the new band boundary paints a semantic dashed edge over the resting plot")
            var midPoint = input.mapToItem(capture, (bandStartX + bandEndX) / 2,
                                           (bandStartY + bandEndY) / 2)
            var midX = Math.round(midPoint.x * bandFrame.width / capture.width)
            var midY = Math.round(midPoint.y * bandFrame.height / capture.height)
            var underlyingFill = [restingFrame.red(midX, midY),
                                  restingFrame.green(midX, midY),
                                  restingFrame.blue(midX, midY)]
            verify(pixelDistance(bandFrame, midX, midY,
                                 compositedColor(underlyingFill,
                                                 page.gridPalette.selectionFill)) <= 4
                   && pixelsDiffer(restingFrame, bandFrame, midX, midY),
                   "the band interior composites its palette selection fill over the real plot")
            mouseRelease(input, bandEndX, bandEndY, Qt.RightButton)
            verify(waitForNative(function() { return !model.interactionActive }, 3000),
                   "releasing the right-band gesture relinquishes its pointer capture")
            var clearedFrame = grabImage(capture)
            verify(!pixelsDiffer(restingFrame, clearedFrame, midX, midY)
                   && !pixelsDiffer(restingFrame, clearedFrame, paintedEdge.x, paintedEdge.y),
                   "releasing the right band clears both its fill and dashed edge pixels")
            var editGuide = findChild(selectedSurface(), "sharedPlayheadEditVelocityGuide")
            var timelineRuler = findChild(selectedSurface(), "timelineRulerInput")
            verify(editGuide && timelineRuler,
                   "the real timeline ruler and shared velocity edit guide are mounted")
            mouseClick(timelineRuler, grid.beatWidth / 2, timelineRuler.height / 2)
            verify(waitForNative(function() { return editGuide.visible }, 3000),
                   "the first ruler click paints the shared edit guide in the velocity plot")
            var guideX = editGuide.guide.contentX
            mouseClick(timelineRuler, grid.beatWidth * 1.5, timelineRuler.height / 2)
            verify(waitForNative(function() {
                return editGuide.guide.contentX !== guideX
            }, 3000), "moving the real edit cursor relocates its painted velocity guide")
            var guideFrame = grabImage(capture)
            verify(paintedColor(guideFrame, capture, editGuide, page.gridPalette.editCursor),
                   "the moved edit guide paints its semantic cursor ink in the velocity band")
            var beforeStack = JSON.parse(grid.noteSummary)
            var drawStart = gridPointFor(notes[0].tick + 8, notes[0].pitch + 1)
            var drawEnd = gridPointFor(notes[0].tick + 20, notes[0].pitch)
            verify(drawStart.x > 0 && drawEnd.x < roll.width
                   && drawStart.y > 0 && drawStart.y < roll.height
                   && drawEnd.y > 0 && drawEnd.y < roll.height,
                   "the real roll can draw a stacked note across adjacent pitch rows")
            mousePress(roll, drawStart.x, drawStart.y, Qt.LeftButton)
            mouseMove(roll, drawEnd.x, drawEnd.y, -1, Qt.LeftButton)
            mouseRelease(roll, drawEnd.x, drawEnd.y, Qt.LeftButton)
            var newStack = JSON.parse(grid.noteSummary).filter(function(note) {
                return note.track === 0 && !beforeStack.some(function(old) {
                    return old.id === note.id
                })
            })
            verify(newStack.length === 1 && newStack[0].pitch === notes[0].pitch
                   && newStack[0].tick > notes[0].tick
                   && newStack[0].tick < notes[0].tick + notes[0].duration
                   && newStack[0].selected,
                   "drawing in the real roll commits one selected note stacked over the first stem")
            var stackedHandle = velocityHandleFor(newStack[0].id)
            verify(stackedHandle, "the stacked roll note paints a velocity handle")
            var stackedRing = collectByName(page, "velocityNodeRing", []).find(function(ring) {
                return ring.parent.model.noteIdText === String(newStack[0].id)
            })
            verify(stackedRing && stackedRing.visible,
                   "the stacked velocity node owns a visible selected ring")
            mousePress(input, stackedHandle.x, stackedHandle.y, Qt.LeftButton)
            var leftStackFrame = grabImage(capture)
            verify(paintedColor(leftStackFrame, capture, stackedRing,
                                page.gridPalette.selectionRing),
                   "left-pressing the selected stacked velocity node paints highlight ink")
            mouseRelease(input, stackedHandle.x, stackedHandle.y, Qt.LeftButton)
            mousePress(input, stackedHandle.x, stackedHandle.y, Qt.RightButton)
            var pressedStackFrame = grabImage(capture)
            verify(paintedColor(pressedStackFrame, capture, stackedRing,
                                page.gridPalette.selectionRing),
                   "right-pressing the selected stacked velocity node keeps its highlight ink")
            mouseRelease(input, stackedHandle.x, stackedHandle.y, Qt.RightButton)
            grid.setCameraHScroll(1e9)
            var timelineEndTick = grid.cameraScrollX * grid.ticksPerBeat / grid.beatWidth
            var barsAfterEnd = collectByName(plot, "velocityGrid", []).filter(function(row) {
                var tick = (row.x + row.width / 2 + grid.cameraScrollX)
                           * grid.ticksPerBeat / grid.beatWidth
                return String(row.fillColor).toLowerCase()
                           === String(page.gridPalette.gridLineBar).toLowerCase()
                    && tick > timelineEndTick && row.x > 3 && row.x < input.width - 8
            })
            verify(barsAfterEnd.length > 0,
                   "the grid exposes a painted bar after the camera's authoritative timeline end")
            var pastBar = barsAfterEnd[0]
            var gridFrame = grabImage(capture)
            var pastPoint = pastBar.mapToItem(capture, pastBar.width / 2, input.height * 0.82)
            var pixelX = Math.round(pastPoint.x * gridFrame.width / capture.width)
            var pixelY = Math.round(pastPoint.y * gridFrame.height / capture.height)
            var neighborInk = [gridFrame.red(pixelX + 5, pixelY),
                               gridFrame.green(pixelX + 5, pixelY),
                               gridFrame.blue(pixelX + 5, pixelY)]
            var expectedBarInk = compositedColor(neighborInk, page.gridPalette.gridLineBar)
            var pastEndBarPainted = false
            for (var offset = -2; offset <= 2; ++offset) {
                if (pixelDistance(gridFrame, pixelX + offset, pixelY, expectedBarInk) <= 16
                    && pixelDistance(gridFrame, pixelX + offset, pixelY, neighborInk) > 6)
                    pastEndBarPainted = true
            }
            verify(pastEndBarPainted,
                   "a bar beyond the authoritative timeline paints palette grid ink against its background")
            grid.setCameraHScroll(0)
            mouseDoubleClickSequence(voiceInput, insertionX, voiceInput.height / 2,
                                     Qt.LeftButton)
            tryCompare(voicePage, "pickerOpen", true)
            var directSearch = findChild(selectedSurface(), "voicePickerSearch")
            verify(waitForNative(function() {
                return directSearch && directSearch.activeFocus
            }, 3000), "the real voice picker opens for a PSG-to-direct-sound change")
            directSearch.selectAll()
            keyClick(Qt.Key_0)
            keyClick(Qt.Key_0)
            keyClick(Qt.Key_0)
            tryCompare(voicePage, "pickerHasMatch", true)
            keyClick(Qt.Key_Return)
            tryCompare(voicePage, "pickerOpen", false)
            verify(waitForNative(function() {
                return model.contextSlot === 0 && !model.detentsAvailable && !detent.visible
            }, 3000), "changing the staged PSG voice back to direct sound hides its detent")
        }
    }

    function mountedRawVelocityGesture(input, grid, notes) {
        var ruler = findChild(velocityPageItem(), "velocityRulerInput")
        var roll = rollInput()
        var inset = grid.baseFontPx * 0.75
        var yFor = function(value) {
            return inset + (ruler.height - 2 * inset) * (127 - value) / 126
        }
        var laterPoint = gridPointFor(notes[1].tick + notes[1].duration / 2,
                                      notes[1].pitch)
        mouseClick(roll, laterPoint.x, laterPoint.y, Qt.LeftButton,
                   Qt.ControlModifier)
        for (var index = 0; index < 2; ++index) {
            var note = notes[index]
            var point = gridPointFor(note.tick + note.duration / 2, note.pitch)
            mouseClick(roll, point.x, point.y, Qt.LeftButton)
            var value = index === 0 ? 33 : 87
            mousePress(ruler, ruler.width / 2, yFor(value), Qt.LeftButton, Qt.ControlModifier)
            mouseRelease(ruler, ruler.width / 2, yFor(value), Qt.LeftButton)
        }
        var firstPoint = gridPointFor(notes[0].tick + notes[0].duration / 2, notes[0].pitch)
        mouseClick(roll, firstPoint.x, firstPoint.y, Qt.LeftButton, Qt.ControlModifier)
        var staged = JSON.parse(grid.noteSummary)
        compare(staged.find(function(note) { return note.id === notes[0].id }).velocity, 33,
                "the mounted raw drag begins with a quiet velocity of 33")
        compare(staged.find(function(note) { return note.id === notes[1].id }).velocity, 87,
                "the mounted raw drag begins with a later velocity of 87")
        var first = velocityHandleFor(notes[0].id)
        var later = velocityHandleFor(notes[1].id)
        verify(first.selected && later.selected && first.x > 0 && first.x < input.width,
               "the mounted raw drag captures both visible note columns")
        var baseline = grid.noteSummary
        var before = Number(revision())
        var rawAtPress = Math.round(1 + (ruler.height - inset - first.y) * 126
                                    / (ruler.height - 2 * inset))
        var endY = yFor(rawAtPress + 7)
        mousePress(input, first.x, first.y, Qt.LeftButton, Qt.ControlModifier)
        mouseMove(input, first.x, endY, -1, Qt.LeftButton, Qt.NoModifier)
        verify(waitForNative(function() {
            var quiet = velocityHandleFor(notes[0].id)
            var companion = velocityHandleFor(notes[1].id)
            return quiet && companion && quiet.preview && companion.preview
        }, 3000), "the mounted raw plot routes the modifier-held press into two previews")
        compare(velocityHandleFor(notes[0].id).value, 40,
                "the mounted raw gesture previews quiet literal 40")
        compare(velocityHandleFor(notes[1].id).value, 94,
                "the mounted raw gesture previews later literal 94")
        compare(grid.noteSummary, baseline,
                "the mounted raw gesture keeps both stored velocities while held")
        compare(Number(revision()), before,
                "the mounted raw gesture stages no document revision")
        mouseRelease(input, first.x, endY, Qt.LeftButton)
        verify(waitForNative(function() {
            var current = JSON.parse(grid.noteSummary)
            return current.some(function(note) { return note.id === notes[0].id && note.velocity === 40 })
                && current.some(function(note) { return note.id === notes[1].id && note.velocity === 94 })
        }, 5000), "the mounted raw release commits exactly 40 and 94")
        compare(Number(revision()), before + 1,
                "the mounted raw release advances exactly one revision")
        compare(velocityHandleFor(notes[2].id).preview, false,
                "the mounted raw release leaves the outsider without a preview")
    }

    function mountedRawVelocityRamp(input, grid, notes) {
        var ruler = findChild(velocityPageItem(), "velocityRulerInput")
        var roll = rollInput()
        var inset = grid.baseFontPx * 0.75
        var yFor = function(value) {
            return inset + (ruler.height - 2 * inset) * (127 - value) / 126
        }
        var firstPosition = gridPointFor(notes[0].tick + notes[0].duration / 2,
                                         notes[0].pitch)
        var laterPosition = gridPointFor(notes[1].tick + notes[1].duration / 2,
                                         notes[1].pitch)
        mouseClick(roll, firstPosition.x, firstPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        mouseClick(roll, laterPosition.x, laterPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        var originalScroll = grid.cameraScrollY
        grid.setCameraVScroll((127 - notes[2].pitch + 0.5) * grid.rowHeight
                              - roll.height / 2)
        var midpoint = gridPointFor(notes[2].tick + notes[2].duration / 2,
                                    notes[2].pitch)
        verify(midpoint.x > 0 && midpoint.x < roll.width
               && midpoint.y > 0 && midpoint.y < roll.height,
               "the middle note is visible after the mounted roll scroll")
        mouseClick(roll, midpoint.x, midpoint.y, Qt.LeftButton)
        mousePress(ruler, ruler.width / 2, yFor(56), Qt.LeftButton, Qt.ControlModifier)
        mouseRelease(ruler, ruler.width / 2, yFor(56), Qt.LeftButton)
        grid.setCameraVScroll(originalScroll)
        mouseClick(roll, firstPosition.x, firstPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        mouseClick(roll, laterPosition.x, laterPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        var first = velocityHandleFor(notes[0].id)
        var middle = velocityHandleFor(notes[2].id)
        var later = velocityHandleFor(notes[1].id)
        var pressX = 2 * middle.x - later.x
        verify(first.selected && middle.selected && later.selected
               && first.x < middle.x && middle.x < later.x
               && pressX > 0 && pressX < middle.x
               && Math.abs(pressX - first.x) <= first.hitRadius,
               "the mounted raw ramp brackets the selected midpoint in distinct columns")
        var original = grid.noteSummary
        var before = Number(revision())
        mousePress(input, pressX, yFor(37), Qt.LeftButton,
                   Qt.ControlModifier | Qt.ShiftModifier)
        mouseMove(input, later.x, yFor(93), -1, Qt.LeftButton, Qt.NoModifier)
        verify(waitForNative(function() {
            var a = velocityHandleFor(notes[0].id)
            var b = velocityHandleFor(notes[2].id)
            var c = velocityHandleFor(notes[1].id)
            return a && b && c && a.preview && b.preview && c.preview
                && a.value === 37 && b.value === 65 && c.value === 93
        }, 3000), "the mounted unlocked ramp previews literal 37, 65 and 93")
        compare(grid.noteSummary, original,
                "the mounted raw ramp keeps the committed roll unchanged while held")
        compare(Number(revision()), before,
                "the mounted raw ramp defers its revision until release")
        mouseRelease(input, later.x, yFor(93), Qt.LeftButton)
        verify(waitForNative(function() {
            var current = JSON.parse(grid.noteSummary)
            return current.some(function(note) { return note.id === notes[0].id && note.velocity === 37 })
                && current.some(function(note) { return note.id === notes[2].id && note.velocity === 65 })
                && current.some(function(note) { return note.id === notes[1].id && note.velocity === 93 })
        }, 5000), "the mounted raw ramp commits literal 37, 65 and 93")
        compare(Number(revision()), before + 1,
                "the mounted raw ramp release advances one revision")
        mouseClick(roll, firstPosition.x, firstPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        mouseClick(roll, laterPosition.x, laterPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
        grid.setCameraVScroll((127 - notes[2].pitch + 0.5) * grid.rowHeight
                              - roll.height / 2)
        midpoint = gridPointFor(notes[2].tick + notes[2].duration / 2, notes[2].pitch)
        mousePress(ruler, ruler.width / 2, yFor(104), Qt.LeftButton,
                   Qt.ControlModifier)
        mouseRelease(ruler, ruler.width / 2, yFor(104), Qt.LeftButton)
        mouseClick(roll, midpoint.x, midpoint.y, Qt.LeftButton,
                   Qt.ControlModifier)
        grid.setCameraVScroll(originalScroll)
        mouseClick(roll, firstPosition.x, firstPosition.y, Qt.LeftButton)
        mouseClick(roll, laterPosition.x, laterPosition.y, Qt.LeftButton,
                   Qt.ControlModifier)
    }

    function mountedVelocityRulerAndPaint(model, detent, input, grid, notes, expectedSnap) {
        var first = velocityHandleFor(notes[0].id)
        var later = velocityHandleFor(notes[1].id)
        var ruler = findChild(velocityPageItem(), "velocityRulerInput")
        verify(ruler && ruler.visible, "the mounted velocity ruler receives pointer input")
        var inset = grid.baseFontPx * 0.75
        var yFor = function(value) {
            return inset + (ruler.height - 2 * inset) * (127 - value) / 126
        }
        var rawY = yFor(73)
        verify(rawY > 0 && rawY < ruler.height,
               "raw 73 lies inside the mounted ruler")
        verify(detent.visible && detent.enabled && model.detentsAvailable,
               "every family mounts an available and enabled ruler detent control")
        compare(detent.Accessible.checked, true,
                "every family's ruler control starts checked before modifier unlock")
        var before = Number(revision())
        mousePress(ruler, ruler.width / 2, rawY, Qt.LeftButton, Qt.ControlModifier)
        tryCompare(grid, "appliedRevisionText", String(before + 1))
        var current = JSON.parse(grid.noteSummary)
        compare(current.find(function(note) { return note.id === notes[0].id }).velocity, 73,
                "the modifier-unlocked ruler writes the first selected roll note on press")
        compare(current.find(function(note) { return note.id === notes[1].id }).velocity, 73,
                "the modifier-unlocked ruler writes the later selected roll note on press")
        compare(detent.Accessible.checked, true,
                "the held unlock never unchecks the rendered detent control")
        mouseRelease(ruler, ruler.width / 2, rawY, Qt.LeftButton)
        compare(Number(revision()), before + 1,
                "the mounted ruler release writes no second revision")
        for (var locked of [true, false]) {
            first = velocityHandleFor(notes[0].id)
            later = velocityHandleFor(notes[1].id)
            if (locked) {
                verify(detent.visible, "each locked family paints with a visible detent control")
                verify(detent.enabled, "each locked family paints with an enabled detent control")
                compare(detent.Accessible.checked, true,
                        "each locked family paints with the rendered checkbox checked")
            } else {
                verify(detent.visible, "each unlocked family paints with a visible detent control")
                verify(detent.enabled, "each unlocked family paints with an enabled detent control")
                compare(detent.Accessible.checked, true,
                        "each unlocked family paints with the rendered checkbox checked")
            }
            var startY = yFor(locked ? 73 : 37)
            var endY = yFor(locked ? 73 : 91)
            var pressX = first.x - first.hitRadius * 2
            var pressY = startY + (endY - startY) * (pressX - first.x) / (later.x - first.x)
            var snapshot = grid.noteSummary
            before = Number(revision())
            mousePress(input, pressX, pressY, Qt.LeftButton,
                       locked ? Qt.NoModifier : Qt.ControlModifier)
            mouseMove(input, first.x, startY, -1, Qt.LeftButton, Qt.NoModifier)
            mouseMove(input, later.x, endY, -1, Qt.LeftButton, Qt.NoModifier)
            var expectedFirst = locked ? expectedSnap : 37
            var expectedLast = locked ? expectedSnap : 91
            verify(waitForNative(function() {
                var a = velocityHandleFor(notes[0].id)
                var b = velocityHandleFor(notes[1].id)
                return a && b && a.preview && b.preview
                    && a.value === expectedFirst && b.value === expectedLast
            }, 3000), "the mounted paint sweep previews the press-latched detent policy: "
                 + JSON.stringify({ locked: locked, press: [pressX, pressY], start: [first.x, startY],
                                    selected: model.selectedCount, size: [input.width, input.height],
                                    firstHandle: [first.y, first.hitRadius, first.selected],
                                    laterHandle: [later.y, later.selected],
                                    end: [later.x, endY], current: [
                                        velocityHandleFor(notes[0].id)
                                            ? [velocityHandleFor(notes[0].id).value,
                                               velocityHandleFor(notes[0].id).preview] : null,
                                        velocityHandleFor(notes[1].id)
                                            ? [velocityHandleFor(notes[1].id).value,
                                               velocityHandleFor(notes[1].id).preview] : null
                                    ], active: model.interactionActive }))
            compare(grid.noteSummary, snapshot,
                    "the mounted paint sweep keeps the committed roll unchanged")
            compare(Number(revision()), before,
                    "the mounted paint sweep defers its revision until release")
            mouseRelease(input, later.x, endY, Qt.LeftButton)
            verify(waitForNative(function() {
                var values = JSON.parse(grid.noteSummary)
                return values.some(function(note) {
                    return note.id === notes[0].id && note.velocity === expectedFirst
                }) && values.some(function(note) {
                    return note.id === notes[1].id && note.velocity === expectedLast
                })
            }, 5000), "the mounted paint release commits both selected values")
            compare(Number(revision()), before + 1,
                    "the mounted paint release commits one revision")
            compare(velocityHandleFor(notes[0].id).preview, false,
                    "the mounted paint release clears its first visible preview")
            compare(velocityHandleFor(notes[2].id).value, 104,
                    "the mounted paint release retains the outside note")
            compare(detent.Accessible.checked, true,
                    "the paint unlock never changes the rendered detent control")
            if (locked) {
                mouseClick(detent, detent.width / 2, detent.height / 2)
                tryCompare(detent.Accessible, "checked", false)
                before = Number(revision())
                mousePress(ruler, ruler.width / 2, rawY, Qt.LeftButton)
                tryCompare(grid, "appliedRevisionText", String(before + 1))
                current = JSON.parse(grid.noteSummary)
                compare(current.find(function(note) { return note.id === notes[0].id }).velocity, 73,
                        "the disabled-detent ruler writes the first selected roll note on press")
                compare(current.find(function(note) { return note.id === notes[1].id }).velocity, 73,
                        "the disabled-detent ruler writes the later selected roll note on press")
                compare(current.find(function(note) { return note.id === notes[2].id }).velocity, 104,
                        "the disabled-detent ruler preserves the outside roll note")
                compare(detent.Accessible.checked, false,
                        "the detents-disabled ruler leaves the rendered checkbox unchecked")
                mouseRelease(ruler, ruler.width / 2, rawY, Qt.LeftButton)
                compare(Number(revision()), before + 1,
                        "the disabled-detent ruler also commits only on press")
                mouseClick(detent, detent.width / 2, detent.height / 2)
                tryCompare(detent.Accessible, "checked", true)
            }
        }
    }
}
