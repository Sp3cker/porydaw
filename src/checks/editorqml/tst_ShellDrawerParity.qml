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
    }
}
