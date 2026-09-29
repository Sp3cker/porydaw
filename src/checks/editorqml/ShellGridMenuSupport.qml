import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait
import "RollNoteFaces.js" as RollNoteFaces
import "GatedVisualsHelpers.js" as Visuals

TestCase {
    id: testCase
    name: "ShellGridMenu"
    when: windowShown
    width: Math.round(baseMetrics.height * 76)
    height: Math.round(baseMetrics.height * 55)
    visible: true

    property var shell: null
    property alias bootstrap: shellBootstrap
    readonly property var settings: shellBootstrap.preferences
    property alias clipProbe: clipboardProbe
    property alias menuCursorSpy: cursorSpy
    property alias menuStatusSpy: statusSpy
    property var timeSigHost: null
    property int promptOpenCount: 0
    property bool menuClosedBeforePrompt: false
    FontMetrics { id: baseMetrics; font: Qt.application.font }

    ShellQmlBootstrap { id: shellBootstrap }
    GridInputClipProbe { id: clipboardProbe }
    SignalSpy { id: cursorSpy; signalName: "editCursorTickChanged" }
    SignalSpy { id: statusSpy; signalName: "statusTextChanged" }
    Component {
        id: shellComponent
        ShellWindow {
            width: testCase.width
            height: testCase.height
            visible: true
        }
    }
    Connections {
        target: testCase.timeSigHost
        function onTimeSigPromptOpenChanged() {
            if (target.timeSigPromptOpen) {
                testCase.promptOpenCount++
                testCase.menuClosedBeforePrompt = !target.timeSigMenuOpen
            }
        }
    }


    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            for (var step = 0; step < 20 && !shell.shellPresenter.closeReady; ++step) {
                if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                    shell.shellPresenter.session.songTabs.confirmDiscard()
                waitForNative(function() {
                    return shell.shellPresenter.closeReady
                        || shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                }, 5000)
            }
            verify(shell.shellPresenter.closeReady)
        }
        shell.destroy()
        shell = null
        timeSigHost = null
        wait(0)
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(shellBootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openSong() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(shellBootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), session.lastSaveError)
        verify(session.songOpen, session.lastSaveError)
        verify(waitForNative(function() {
            return surface() !== null && surface().gridModel.renderedNoteCount > 0
        }, 10000))
        timeSigHost = surface().timeSigHost
        return session
    }

    function surface() {
        if (!shell || !shell.sceneLoader.item)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function control(name) {
        var item = findChild(surface(), name)
        verify(item !== null)
        return item
    }

    function panel() {
        verify(waitForNative(function() {
            return findChild(surface(), "quickMenuPanelRoot") !== null
        }, 5000))
        return findChild(surface(), "quickMenuPanelRoot")
    }

    function clickRow(menu, row) {
        tryVerify(function() { return menu.rowItem(row) !== null }, 3000)
        var item = menu.rowItem(row)
        verify(item !== null)
        mouseClick(item, item.width / 2, item.height / 2)
    }

    function openGrid(controlName, kind) {
        tryVerify(function() { return findChild(surface(), "quickMenuPanelRoot") === null }, 3000)
        mouseClick(control(controlName))
        tryCompare(surface().gridModel, "gridMenuKind", kind)
        return panel()
    }

    function assertRows(menu, ids, checkedId) {
        tryCompare(menu, "rowCount", ids.length)
        var checkedCount = 0
        for (var index = 0; index < ids.length; ++index) {
            tryVerify(function() { return menu.rowItem(index) !== null }, 3000)
            var row = menu.rowItem(index)
            compare(row.itemData.actionId, ids[index])
            compare(row.itemData.enabled, true)
            compare(row.itemData.checkable, true)
            compare(row.itemData.checked, ids[index] === checkedId)
            if (row.itemData.checked)
                checkedCount++
        }
        compare(checkedCount, 1)
    }

    function rowTextEqualsControlText(menu, controlText) {
        for (var index = 0; index < menu.rowCount; ++index) {
            var row = menu.rowItem(index)
            if (row.itemData.checked) {
                compare(row.itemData.text, controlText)
                return
            }
        }
        fail("the menu has no checked row")
    }

    function alternateGridMenuId(id) {
        return id === 8 ? 16 : 8
    }

    function rulerTickX(tick) {
        var grid = surface().gridModel
        return tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
    }

    function rulerCellPixels() {
        var grid = surface().gridModel
        return Math.max(1, grid.snapTicks) * grid.beatWidth / grid.ticksPerBeat
    }

    function rulerPanel() {
        var menu = findChild(surface(), "quickMenuPanelRoot")
        return menu !== null && menu.rowObjectNamePrefix === "rulerMenuRow_" && menu.visible
            ? menu : null
    }

    function rulerMenuShown() {
        return rulerPanel() !== null
    }

    function rulerMenuGone() {
        return findChild(surface(), "quickMenuPanelRoot") === null && !timeSigHost.timeSigMenuOpen
    }

    function openRulerMenu(x, y) {
        tryVerify(rulerMenuGone, 3000)
        mouseClick(control("timelineRulerInput"), x, y, Qt.RightButton)
        tryCompare(timeSigHost, "timeSigMenuOpen", true)
        tryVerify(rulerMenuShown, 5000)
        var menu = rulerPanel()
        verify(rulerRowIndex(menu, 11) < 0)
        return menu
    }

    function openTimeMenu(x) {
        tryVerify(rulerMenuGone, 3000)
        var roll = control("swiftRollInput")
        mouseClick(roll, x, roll.height * 0.5, Qt.RightButton)
        tryVerify(rulerMenuShown, 5000)
        var menu = rulerPanel()
        tryCompare(menu, "rowCount", 9)
        verify(rulerRowIndex(menu, 11) === 0)
        return menu
    }

    function rulerRowIndex(menu, actionId) {
        tryVerify(function() { return menu.rowCount > 0 }, 3000)
        for (var index = 0; index < menu.rowCount; ++index) {
            tryVerify(function() { return menu.rowItem(index) !== null }, 3000)
            if (menu.rowItem(index).itemData.actionId === actionId)
                return index
        }
        return -1
    }

    function rulerRowEnabled(menu, actionId) {
        var index = rulerRowIndex(menu, actionId)
        verify(index >= 0)
        return menu.rowItem(index).itemData.enabled
    }

    function clearRulerLoop(x, y) {
        var menu = openRulerMenu(x, y)
        var index = rulerRowIndex(menu, 4)
        if (menu.rowItem(index).itemData.enabled) {
            clickRow(menu, index)
            tryVerify(rulerMenuGone, 3000)
            menu = openRulerMenu(x, y)
        }
        return menu
    }

    function loopMarkerFace(name) {
        var renderer = control("timelineQuickRulerMarks")
        return name === "loopStartMarker" ? renderer.face(renderer.loopStartId)
            : renderer.face(renderer.loopEndId)
    }

    function loopMarkerAt(name, tick) {
        var renderer = control("timelineQuickRulerMarks")
        var marker = loopMarkerFace(name)
        if (!marker || marker.width === undefined)
            return false
        var point = renderer.mapToItem(control("timelineRulerInput"), marker.x, marker.y)
        return Math.abs(point.x + marker.width / 2 - rulerTickX(tick)) <= 0.75
    }

    function loopMarkerAbsent(name) {
        return loopMarkerFace(name).width === undefined
    }

    function rulerSignatureAt(tick) {
        var grid = surface().gridModel
        var x = rulerTickX(tick)
        if (timeSigHost.timeSigChipTick(x, grid.rulerMarkerRowHeight / 2) !== tick)
            return false
        var renderer = control("timelineQuickRulerMarks")
        var image = RollNoteFaces.grab(testCase, renderer)
        var dpr = image.width / renderer.width
        var px = Math.round(x * dpr)
        var py = Math.round(Math.min(3, grid.rulerMarkerRowHeight / 2) * dpr)
        var ink = Visuals.channels(grid.palette.primaryText)
        for (var dx = -2; dx <= 2; ++dx) {
            if (px + dx < 0 || px + dx >= image.width)
                continue
            if (Math.abs(image.red(px + dx, py) - ink[0]) <= 20
                && Math.abs(image.green(px + dx, py) - ink[1]) <= 20
                && Math.abs(image.blue(px + dx, py) - ink[2]) <= 20)
                return true
        }
        return false
    }

    function noteLayout() {
        return JSON.stringify(JSON.parse(surface().gridModel.fetchNoteSummary()).map(function(note) {
            return [note.track, note.tick, note.duration, note.pitch, note.velocity]
        }).sort())
    }

    function noteTargets() {
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var renderer = findChild(surface(), "timelineRendererPlot")
        return JSON.parse(grid.fetchNoteSummary()).filter(function(note) {
            return !note.ghost && note.track === grid.trackIndex
        }).map(function(note) {
            var item = RollNoteFaces.rect(renderer, roll, note.id)
            if (!item || item.width < grid.drawThreshold * 2)
                return null
            var point = Qt.point(item.x + item.width / 2, item.y + item.height / 2)
            return point.x > item.width && point.y > item.height
                && point.x < roll.width - item.width
                && point.y < roll.height - item.height
                ? { note: note, point: point } : null
        }).filter(function(target) { return target !== null })
    }

    function noteMenu() {
        var menu = findChild(shell, "shellGridContextMenu")
        verify(menu !== null, "the shell owns the note context menu")
        return menu
    }

    function noteMenuMiss(menu) {
        var roll = control("swiftRollInput")
        var targets = JSON.parse(surface().gridModel.fetchNoteSummary())
        var renderer = findChild(surface(), "timelineRendererPlot")
        for (var y = roll.height - surface().gridModel.rowHeight; y > 0;
             y -= surface().gridModel.rowHeight) {
            for (var x = roll.width - roll.height / 8; x > 0; x -= roll.width / 8) {
                var point = roll.mapToItem(null, x, y)
                if (point.x >= menu.x && point.x <= menu.x + menu.width
                    && point.y >= menu.y && point.y <= menu.y + menu.height)
                    continue
                var occupied = targets.some(function(note) {
                    var item = RollNoteFaces.rect(renderer, roll, note.id)
                    if (!item)
                        return false
                    return x >= item.x && x <= item.x + item.width
                        && y >= item.y && y <= item.y + item.height
                })
                if (!occupied)
                    return roll.mapToItem(shell.contentItem, x, y)
            }
        }
        return null
    }

    function sweepNoteRange() {
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var notes = JSON.parse(grid.fetchNoteSummary())
        var note = null
        for (var index = 0; index < notes.length && note === null; ++index) {
            var left = rulerTickX(notes[index].tick)
            var right = rulerTickX(notes[index].tick + notes[index].duration)
            if (!notes[index].ghost && notes[index].track === grid.trackIndex
                && left > ruler.width * 0.15 && right < ruler.width * 0.6)
                note = notes[index]
        }
        verify(note !== null, "a whole primary-track note lies inside the ruler sweep band")
        var startX = rulerTickX(note.tick) - rulerCellPixels()
        var endX = rulerTickX(note.tick + note.duration) + rulerCellPixels()
        var y = ruler.height * 0.75
        mousePress(ruler, startX, y, Qt.LeftButton)
        mouseMove(ruler, endX, y, -1, Qt.LeftButton)
        mouseRelease(ruler, endX, y, Qt.LeftButton)
        return { startX: startX, endX: endX, midX: (startX + endX) / 2 }
    }
}
