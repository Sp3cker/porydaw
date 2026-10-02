import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait
import "RollNoteFaces.js" as RollNoteFaces

TestCase {
    id: testCase
    name: "ShellClipboard"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    readonly property var settings: bootstrap.preferences
    property alias bootstrap: nativeBootstrap
    property alias clipProbe: nativeClipProbe
    property alias rejectedCursorSpy: nativeRejectedCursorSpy
    property alias rejectedStatusSpy: nativeRejectedStatusSpy

    ShellQmlBootstrap { id: nativeBootstrap }
    GridInputClipProbe { id: nativeClipProbe }
    SignalSpy { id: nativeRejectedCursorSpy; signalName: "editCursorTickChanged" }
    SignalSpy { id: nativeRejectedStatusSpy; signalName: "statusTextChanged" }

    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }


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
        shell.destroy()
        shell = null
        wait(0)
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openRoute101() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songOpen, "Route 101 loads: " + session.lastSaveError)
        verify(waitForNative(function() {
            var surface = selectedSurface()
            return surface !== null && surface.gridModel.renderedNoteCount > 0
        }, 10000), "the staged song publishes grid notes")
        return session
    }

    function selectedSurface() {
        if (!shell || !shell.sceneLoader || !shell.sceneLoader.item)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
        if (!page)
            return null
        return findChild(page, "swiftRollOverlay")
    }

    function gridNotes(grid) { return JSON.parse(grid.fetchNoteSummary()) }

    function editableNotes(grid) {
        return gridNotes(grid).filter(function(note) {
            return !note.ghost && note.track === grid.trackIndex
        })
    }

    function noteFacts(grid, track) {
        var notes = gridNotes(grid)
        if (track !== undefined)
            notes = notes.filter(function(note) { return note.track === track })
        return notes.map(function(note) {
            return [note.id, note.track, note.tick, note.pitch, note.duration, note.velocity].join(":")
        }).sort().join(";")
    }

    function noteById(grid, id) {
        var list = gridNotes(grid)
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === id)
                return list[i]
        return null
    }

    function selectedCount(grid) {
        return gridNotes(grid).filter(function(n) { return n.selected }).length
    }

    function noteCenter(roll, surface, id) {
        return RollNoteFaces.center(findChild(surface, "timelineRendererPlot"), roll, id)
    }

    function pastedAt(grid, sourceId, tick, source) {
        var list = gridNotes(grid)
        for (var i = 0; i < list.length; ++i) {
            var note = list[i]
            if (note.id !== sourceId && note.tick === tick && note.duration === source.duration
                    && note.pitch === source.pitch && note.track === source.track
                    && note.velocity === source.velocity)
                return note
        }
        return null
    }

    function noteFactsFrom(notes) {
        return notes.map(function(note) {
            return [note.id, note.track, note.tick, note.pitch, note.duration, note.velocity].join(":")
        }).sort().join(";")
    }

    function pastedOn(grid, sourceId, tick, source) {
        var list = JSON.parse(grid.fetchNoteSummary())
        for (var i = 0; i < list.length; ++i) {
            var note = list[i]
            if (note.id !== sourceId && note.tick === tick && note.duration === source.duration
                    && note.pitch === source.pitch && note.track === source.track
                    && note.velocity === source.velocity)
                return note
        }
        return null
    }

    function noteOn(grid, id) {
        var list = JSON.parse(grid.fetchNoteSummary())
        for (var i = 0; i < list.length; ++i)
            if (list[i].id === id)
                return list[i]
        return null
    }

    function tileOn(grid, tick, pitch, duration, track, velocity, notId) {
        var list = JSON.parse(grid.fetchNoteSummary())
        for (var i = 0; i < list.length; ++i) {
            var note = list[i]
            if (note.tick === tick && note.pitch === pitch && note.duration === duration
                    && note.track === track && note.velocity === velocity
                    && (notId === undefined || note.id !== notId))
                return note
        }
        return null
    }
}
