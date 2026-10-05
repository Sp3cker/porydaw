import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait
import "RollNoteFaces.js" as RollNoteFaces

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
        font: shell ? shell.chromeTypography.caption : Application.font
    }
    FontMetrics {
        id: _footerBodyMetrics
        font: shell ? shell.chromeTypography.body : Application.font
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
        bootstrap.children.length = 0
        shell.destroy()
        shell = null
        wait(0)
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function waitForShellScene() {
        verify(waitForNative(function() {
            return shell.sceneLoader !== null && shell.sceneLoader.status === Loader.Ready
        }, 10000), "the presented window mounts its deferred editor scene")
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
        waitForShellScene()
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
        var songs = session.songDockController().songListPresenter()
        for (var i = 0; i < songs.rowCount && i < 8; ++i)
            labels.push(songs.songLabel(i))
        return " (projectRoot=" + bootstrap.projectRoot
            + "; projectOpen=" + session.projectOpen
            + "; songOpen=" + session.songOpen
            + "; stagedLabels=[" + labels.join(",") + "]"
            + "; lastSaveError=" + session.lastSaveError
            + "; status=" + shell.shellPresenter.statusText + ")"
    }

    function gridNotes(grid) { return JSON.parse(grid.fetchNoteSummary()) }

    function selectedSurface() {
        if (!shell || !shell.sceneLoader || shell.sceneLoader.status !== Loader.Ready)
            return null
        var pages = shell.sceneLoader.item
        if (!pages)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(pages, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function pointFor(grid, tick, pitch) {
        var ppt = grid.beatWidth / grid.ticksPerBeat
        return {
            x: tick * ppt - grid.cameraScrollX,
            y: (127 - pitch + 0.5) * grid.rowHeight - grid.cameraScrollY
        }
    }

    function freeLane(grid, surface, spanSnaps) {
        var snap = grid.snapTicks
        var plot = findChild(surface, "timelineQuickRollPlot")
        if (!plot || plot.width <= 0 || plot.height <= 0)
            return null
        var ppt = grid.beatWidth / grid.ticksPerBeat
        var rowH = grid.rowHeight
        var scrollX = grid.cameraScrollX
        var scrollY = grid.cameraScrollY
        var firstTick = Math.ceil(((scrollX + 24) / ppt) / snap) * snap
        var lastTick = Math.floor(((scrollX + plot.width - 24) / ppt) / snap) * snap
        var firstRow = Math.min(127, Math.max(0, Math.ceil(scrollY / rowH) + 2))
        var lastRow = Math.min(127, Math.max(0, Math.floor((scrollY + plot.height) / rowH) - 2))
        var current = gridNotes(grid)
        var tick = Math.max(0, firstTick)
        if (tick + spanSnaps * snap > lastTick)
            return null
        for (var row = firstRow; row <= lastRow; ++row) {
            var pitch = 127 - row
            // Drawing needs an untouched pitch row: a neighboring fixture note
            // can capture the press through its resize grip even without overlap.
            var occupied = current.some(function(note) {
                return note.track === grid.trackIndex && note.pitch === pitch
            })
            if (!occupied)
                return { tick: tick, pitch: pitch }
        }
        return null
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
        var renderer = findChild(surface, "timelineRendererPlot")
        var second = JSON.parse(grid.fetchNoteSummary()).find(function(note) {
            return !note.selected && !note.ghost && RollNoteFaces.face(renderer, note.id) !== null
        })
        verify(first && second, "two drawn roll notes are available for the key journey")
        var point = RollNoteFaces.center(renderer, roll, second.id)
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
        var renderer = findChild(surface, "timelineRendererPlot")
        if (!renderer || renderer.width <= 0 || renderer.height <= 0)
            return null
        var edge = Qt.color(String(surface.gridModel.palette.selectionEdge))
        var playheadOverlay = findChild(surface, "sharedPlayhead")
        if (playheadOverlay)
            playheadOverlay.visible = false
        var image = RollNoteFaces.grab(testCase, renderer)
        if (playheadOverlay)
            playheadOverlay.visible = true
        var dpr = image.width / renderer.width
        var rows = [0.2, 0.5, 0.8].map(function(f) { return Math.floor(image.height * f) })
        var first = -1
        var last = -1
        for (var x = 0; x < image.width; ++x) {
            var column = rows.every(function(y) {
                return Math.abs(image.red(x, y) - edge.r * 255) <= 16
                    && Math.abs(image.green(x, y) - edge.g * 255) <= 16
                    && Math.abs(image.blue(x, y) - edge.b * 255) <= 16
            })
            if (!column)
                continue
            if (first < 0)
                first = x
            last = x
        }
        if (first < 0 || last - first < 2)
            return null
        var origin = renderer.mapToItem(roll, 0, 0)
        return { start: origin.x + (first + 0.5) / dpr, end: origin.x + (last + 0.5) / dpr }
    }

    function mountedNotePoint(surface, roll, id) {
        var point = RollNoteFaces.center(findChild(surface, "timelineRendererPlot"), roll, id)
        if (!point)
            return null
        return point.x >= 0 && point.x <= roll.width && point.y >= 0
               && point.y <= roll.height ? point : null
    }

    function windowShortcut(name) {
        var content = findChild(shell, "shellContentLoader").item
        var delegates = content ? content.children : []
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
