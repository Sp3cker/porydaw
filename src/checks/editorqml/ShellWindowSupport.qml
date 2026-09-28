import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellWindow"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    property alias bootstrap: _bootstrap
    property alias clipProbe: _clipProbe
    property alias copyActivatedSpy: _copyActivatedSpy
    property alias soloActivatedSpy: _soloActivatedSpy
    property alias drawerOriginPreferenceSpy: _drawerOriginPreferenceSpy
    property alias drawerSiblingPreferenceSpy: _drawerSiblingPreferenceSpy
    property alias shellComponent: _shellComponent
    property alias intrinsicShellComponent: _intrinsicShellComponent
    property alias footerCaptionMetrics: _footerCaptionMetrics
    property alias footerBodyMetrics: _footerBodyMetrics
    property alias textProbeComponent: _textProbeComponent
    property alias shortcutTargetComponent: _shortcutTargetComponent
    property alias foreignWindowComponent: _foreignWindowComponent
    readonly property var settings: bootstrap.preferences

    ShellQmlBootstrap { id: _bootstrap }
    GridInputClipProbe { id: _clipProbe }
    SignalSpy { id: _copyActivatedSpy; signalName: "activated" }
    SignalSpy { id: _soloActivatedSpy; signalName: "activated" }
    SignalSpy { id: _drawerOriginPreferenceSpy; signalName: "drawerSectionPreferenceChanged" }
    SignalSpy { id: _drawerSiblingPreferenceSpy; signalName: "drawerSectionPreferenceChanged" }

    Component { id: _shellComponent; ShellWindow { width: 960; height: 640; visible: true } }
    Component { id: _intrinsicShellComponent; ShellWindow { visible: true } }
    FontMetrics {
        id: _footerCaptionMetrics
        font: shell ? Qt.font(shell.chromeTypography.caption) : Application.font
    }
    FontMetrics {
        id: _footerBodyMetrics
        font: shell ? Qt.font(shell.chromeTypography.body) : Application.font
    }
    Component {
        id: _textProbeComponent
        TextField { text: "native copy text probe"; width: 220; height: 32 }
    }
    Component {
        id: _shortcutTargetComponent
        Item { width: 24; height: 24; focus: true }
    }
    Component {
        id: _foreignWindowComponent
        Window {
            width: 320
            height: 120
            visible: true
            TextField {
                objectName: "foreignSoloField"
                x: 20
                y: 20
                width: 220
                height: 32
                text: "foreign draft"
            }
        }
    }


    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "the close-all walk reaches the dirty gate or completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() {
                return shell.shellPresenter.closeReady
            }, 5000), "teardown waits for scene destruction and grid detach")
        }
        copyActivatedSpy.target = null
        soloActivatedSpy.target = null
        shell.destroy()
        shell = null
        wait(0)
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openTwoSongShell(beforeOpen) {
        settings.setBool("editorDrawer.velocityVisible", true)
        settings.setInt("editorDrawer.velocityHeight", 173)
        settings.setBool("editorDrawer.automationVisible", false)
        settings.setBool("editorDrawer.voiceChangesVisible", false)
        settings.setString("editorDrawer.activePage", "velocity")
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000, "the two-song shell window becomes active")
        if (beforeOpen)
            beforeOpen()
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songOpen, "Route 101 loads from the original mainwindowrouting project"
               + openDiagnostics(session))
        tryCompare(session.songTabs, "tabCount", 1)
        var firstId = session.songTabs.selectedId
        session.openSong("mus_littleroot_test")
        waitForNative(function() {
            return session.songTabs.tabCount === 2 || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songTabs.tabCount === 2,
               "Littleroot opens in the second tab of the same project"
               + openDiagnostics(session))
        tryVerify(function() { return session.songTabs.selectedId !== firstId }, 3000,
                  "Littleroot is the selected workspace")
        tryVerify(function() {
            var surface = selectedSurface()
            return surface !== null && surface.visible && surface.width > 0
        }, 5000, "the selected real tab page is mounted and drawn")
        return firstId
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

    function selectedSurface() {
        var pages = shell.sceneLoader.item
        if (!pages)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(pages, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }
    function focusBelongsTo(page) {
        var focused = shell.activeFocusItem
        while (focused) {
            if (focused === page)
                return true
            focused = focused.parent
        }
        return false
    }

    function selectDrawnVelocityNote(surface) {
        var drawer = surface.drawerPresenter
        var velocityKind = bootstrap.velocitySectionKind()
        tryCompare(drawer.section(velocityKind), "visible", true)
        var plot = null
        var node = null
        tryVerify(function() {
            plot = findChild(surface, "velocityPlotInput")
            node = findChild(surface, "velocityNodeFill")
            return plot !== null && node !== null && node.width > 0 && node.height > 0
        }, 3000, "the original velocity page draws a note hit target")
        var hit = node.mapToItem(plot, node.width / 2, node.height / 2)
        mouseClick(plot, hit.x, hit.y)
        tryCompare(shell.shellPresenter.session.velocityPage(), "selectedCount", 1, 3000)
    }

    function selectMountedNotePair(surface) {
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        selectDrawnVelocityNote(surface)
        var first = JSON.parse(grid.fetchNoteSummary()).find(function(note) {
            return note.selected && !note.ghost
        })
        var second = JSON.parse(grid.fetchNoteSummary()).find(function(note) {
            var item = findChild(surface, "gridNote_" + note.id)
            return !note.selected && !note.ghost && item && item.visible
                   && item.width > 0 && item.height > 0
        })
        verify(first && second, "two drawn roll notes are available for the key journey")
        var target = findChild(surface, "gridNote_" + second.id)
        var point = target.mapToItem(roll, target.width / 2, target.height / 2)
        mouseClick(roll, point.x, point.y, Qt.LeftButton, Qt.ShiftModifier)
        var pair = JSON.parse(grid.fetchNoteSummary()).filter(function(note) {
            return note.selected && (note.id === first.id || note.id === second.id)
        })
        return pair
    }

    function drawnNoteContent(grid) {
        return JSON.parse(grid.fetchNoteSummary()).map(function(note) {
            return [note.track, note.tick, note.pitch, note.duration, note.velocity, note.ghost]
        }).sort(function(a, b) { return JSON.stringify(a).localeCompare(JSON.stringify(b)) })
    }

    function paintedTimeRange(surface, roll) {
        var overlay = findChild(surface, "timelineQuickPianoOverlay")
        if (!overlay)
            return null
        var fill = String(surface.gridModel.palette.selectionFill).toLowerCase()
        for (var item of overlay.children) {
            if (item.visible && item.color && String(item.color).toLowerCase() === fill
                    && item.width > 0 && item.height >= roll.height) {
                var point = item.mapToItem(roll, 0, 0)
                return { start: point.x, end: point.x + item.width }
            }
        }
        return null
    }

    function mountedNotePoint(surface, roll, id) {
        var item = findChild(surface, "gridNote_" + id)
        if (!item || !item.visible || item.width <= 0 || item.height <= 0)
            return null
        var point = item.mapToItem(roll, item.width / 2, item.height / 2)
        return point.x >= 0 && point.x <= roll.width && point.y >= 0
               && point.y <= roll.height ? point : null
    }

    function windowShortcut(name) {
        var delegates = shell.contentItem.children
        for (var i = 0; i < delegates.length; ++i) {
            var objects = delegates[i].data
            for (var j = 0; objects && j < objects.length; ++j) {
                if (objects[j].objectName === name)
                    return objects[j]
            }
        }
        return null
    }
}
