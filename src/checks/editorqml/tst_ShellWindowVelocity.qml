import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
    function test_kVelocityStemEscapeFromRollFocus() {
        openTwoSongShell()
        var surface = selectedSurface()
        var session = shell.shellPresenter.session
        var grid = surface.gridModel
        selectDrawnVelocityNote(surface)
        var plot = findChild(surface, "velocityPlotInput")
        var node = findChild(surface, "velocityNodeFill")
        var stem = findChild(node.parent, "velocityNodeStem")
        var roll = findChild(surface, "swiftRollInput")
        verify(plot && node && stem && roll && stem.width > node.width,
               "the mounted shell exposes a selected velocity duration stem and roll")
        var pair = selectMountedNotePair(surface)
        compare(pair.length, 2,
                "the selected stem gesture starts with two real selected notes")
        var selectedIds = pair.map(function(note) { return note.id }).sort()
        var original = grid.noteSummary
        var revision = grid.appliedRevisionText
        var selected = session.velocityPage().selectedCount
        compare(selected, 2, "the captured stem selection contains both notes")
        var press = stem.mapToItem(plot, stem.width * 3 / 4, stem.height / 2)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        mousePress(plot, press.x, press.y, Qt.LeftButton)
        mouseMove(plot, press.x, press.y - node.height * 2, -1, Qt.LeftButton)
        tryCompare(session.velocityPage(), "interactionActive", true, 3000)
        compare(JSON.parse(grid.noteSummary).filter(function(note) {
            return note.selected
        }).map(function(note) { return note.id }).sort().join(","), selectedIds.join(","),
                "the live selected-stem drag retains its two-note capture")
        var undoBefore = session.canUndo
        var redoBefore = session.canRedo
        keyClick(Qt.Key_Right)
        keyClick(Qt.Key_Delete)
        compare(grid.noteSummary, original, "routed edit keys cannot mutate a live velocity stem drag")
        compare(grid.appliedRevisionText, revision, "held edit keys leave the document revision frozen")
        compare(session.canUndo, undoBefore, "held stem edit keys do not push undo history")
        compare(session.canRedo, redoBefore, "held stem edit keys do not change redo history")
        compare(session.velocityPage().selectedCount, 2,
                "held edit keys cannot replace the captured stem selection")
        keyClick(Qt.Key_Escape)
        tryCompare(session.velocityPage(), "interactionActive", false, 3000)
        compare(session.velocityPage().interactionActive, false,
                "first Escape ends the captured stem gesture")
        mouseRelease(plot, press.x, press.y - node.height * 2, Qt.LeftButton)
        compare(session.velocityPage().selectedCount, selected,
                "the first routed Escape retains the captured note selection")
        compare(grid.noteSummary, original, "Escape and release roll back the velocity stem preview")
        compare(grid.appliedRevisionText, revision, "Escape and release commit no document edit")
        compare(session.canUndo, undoBefore, "stem Escape leaves undo history unchanged")
        compare(session.canRedo, redoBefore, "stem Escape leaves redo history unchanged")
        compare(JSON.parse(grid.noteSummary).filter(function(note) {
            return note.selected
        }).map(function(note) { return note.id }).sort().join(","), selectedIds.join(","),
                "stem Escape restores the exact two-note selection")
        keyClick(Qt.Key_Escape)
        tryCompare(session.velocityPage(), "selectedCount", 0, 3000)
    }

    function test_kOverlappingVelocityNodePaintCaptureAndResume() {
        openTwoSongShell()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        var velocityPlot = findChild(surface, "velocityPlot")
        var input = findChild(surface, "velocityPlotInput")
        var plot = findChild(surface, "timelineQuickRollPlot")
        verify(roll && plot && input && velocityPlot,
               "the mounted roll and velocity plot accept real input")
        var existing = JSON.parse(grid.noteSummary).filter(function(note) { return !note.ghost })
        var endTick = existing.reduce(function(last, note) {
            return Math.max(last, note.tick + note.duration)
        }, 0)
        var snap = grid.snapTicks
        var tick = Math.ceil((endTick + snap) / snap) * snap
        var scale = grid.beatWidth / grid.ticksPerBeat
        grid.setCameraHScroll(Math.max(0, tick * scale - roll.width / 3))
        var firstRow = Math.ceil(grid.cameraScrollY / grid.rowHeight) + 2
        var lastRow = Math.floor((grid.cameraScrollY + plot.height) / grid.rowHeight) - 2
        var pitches = []
        for (var row = firstRow; row <= lastRow && pitches.length < 2; ++row) {
            var pitch = 127 - row
            if (!existing.some(function(note) { return note.pitch === pitch }))
                pitches.push(pitch)
        }
        verify(pitches.length === 2, "two unused pitch rows fit in the mounted roll")
        for (var i = 0; i < 2; ++i) {
            var start = tick + i * 4 * snap
            var duration = (i === 0 ? 8 : 2) * snap
            var inset = Math.max(1, Math.floor(snap / 4))
            var x = (start + inset) * scale - grid.cameraScrollX
            var endX = (start + duration - inset) * scale - grid.cameraScrollX
            var y = (127 - pitches[i] + 0.5) * grid.rowHeight - grid.cameraScrollY
            verify(x > 0 && endX < plot.width && y > 0 && y < plot.height,
                   "the long stem and following note fit the visible roll")
            var pressPoint = plot.mapToItem(roll, x, y)
            var releasePoint = plot.mapToItem(roll, endX, y)
            mouseMove(roll, pressPoint.x, pressPoint.y)
            mousePress(roll, pressPoint.x, pressPoint.y, Qt.LeftButton)
            mouseMove(roll, releasePoint.x, releasePoint.y, 20, Qt.LeftButton)
            mouseRelease(roll, releasePoint.x, releasePoint.y, Qt.LeftButton)
            tryVerify(function() {
                return JSON.parse(grid.noteSummary).filter(function(note) {
                    return !note.ghost
                }).length === existing.length + i + 1
            }, 3000, "the mounted roll commits the overlapping note")
        }
        var pair = JSON.parse(grid.noteSummary).filter(function(note) {
            return pitches.indexOf(note.pitch) >= 0 && note.tick >= tick
        }).sort(function(a, b) { return a.tick - b.tick })
        verify(pair.length === 2 && pair[0].velocity === pair[1].velocity,
               "the earlier stem and following node share a plotted height")
        function nodeFor(id) {
            for (var item of velocityPlot.children) {
                if (item.model && item.model.noteIdText === String(id))
                    return findChild(item, "velocityNodeFill")
            }
            return null
        }
        function overlap() {
            var earlier = nodeFor(pair[0].id)
            var following = nodeFor(pair[1].id)
            verify(earlier && following, "both velocity nodes publish rendered delegates")
            var stem = findChild(earlier.parent, "velocityNodeStem")
            var point = following.mapToItem(input, following.width / 2, following.height / 2)
            verify(stem && following.parent.model.x > stem.x
                   && following.parent.model.x < stem.x + stem.width
                   && point.x > 0 && point.x < input.width && point.y > 0
                   && point.y < input.height, "the following node covers the earlier duration stem")
            return { node: following, point: point }
        }
        function nodePixel() {
            var hit = overlap()
            waitForRendering(shell.contentItem)
            var frame = grabImage(shell.contentItem)
            var point = hit.node.mapToItem(shell.contentItem,
                                           hit.node.width / 2, hit.node.height / 2)
            var dpr = frame.width / shell.contentItem.width
            return { actual: frame.pixel(Math.round(point.x * dpr), Math.round(point.y * dpr)),
                     expected: hit.node.color }
        }
        var earlier = nodeFor(pair[0].id)
        var earlierPoint = earlier.mapToItem(input, earlier.width / 2, earlier.height / 2)
        mouseClick(input, earlierPoint.x, earlierPoint.y)
        tryVerify(function() {
            return JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === pair[0].id && note.selected
            })
        }, 3000, "the earlier duration stem belongs to the selected note")
        var idle = nodePixel()
        verify(Qt.colorEqual(idle.actual, idle.expected),
               "the idle following node pixel paints above the selected earlier stem")
        var press = overlap().point
        mouseMove(input, press.x, press.y)
        var hovered = nodePixel()
        verify(Qt.colorEqual(hovered.actual, hovered.expected),
               "the hovered following node pixel paints above the earlier stem")
        mouseClick(input, press.x, press.y, Qt.LeftButton, Qt.ControlModifier)
        var selected = nodePixel()
        verify(Qt.colorEqual(selected.actual, selected.expected),
               "the selected following node pixel paints above the earlier stem")
        var beatWidth = grid.beatWidth
        mouseWheel(roll, press.x, roll.height / 2, 0, 120)
        tryVerify(function() { return grid.beatWidth > beatWidth }, 3000,
                  "the mounted roll zooms the overlapping node")
        var zoomed = nodePixel()
        verify(Qt.colorEqual(zoomed.actual, zoomed.expected),
               "the zoomed following node pixel paints above the earlier stem")
        mouseWheel(roll, press.x, roll.height / 2, 0, -120)
        tryVerify(function() { return grid.beatWidth <= beatWidth }, 3000,
                  "the mounted roll restores the overlap zoom")
        mouseClick(input, overlap().point.x, overlap().point.y)
        var first = nodeFor(pair[0].id)
        mouseClick(input, first.mapToItem(input, first.width / 2, first.height / 2).x,
                   first.mapToItem(input, first.width / 2, first.height / 2).y)
        var before = grid.noteSummary
        var revision = grid.appliedRevisionText
        var undoBefore = shell.shellPresenter.session.canUndo
        press = overlap().point
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        mousePress(input, press.x, press.y, Qt.LeftButton)
        mouseMove(input, press.x, press.y - nodeFor(pair[1].id).height * 2,
                  -1, Qt.LeftButton)
        tryCompare(shell.shellPresenter.session.velocityPage(), "interactionActive", true)
        verify(JSON.parse(grid.noteSummary).some(function(note) {
            return note.id === pair[1].id && note.selected
        }), "the live overlap drag captures the painted following node")
        keyClick(Qt.Key_Escape)
        tryCompare(shell.shellPresenter.session.velocityPage(), "interactionActive", false)
        mouseRelease(input, press.x, press.y - nodeFor(pair[1].id).height * 2, Qt.LeftButton)
        compare(grid.noteSummary, before,
                "overlap Escape restores the earlier-note selection and exact note content")
        compare(grid.appliedRevisionText, revision, "overlap Escape preserves document revision")
        compare(shell.shellPresenter.session.canUndo, undoBefore,
                "overlap Escape leaves the history tip unchanged")
        compare(shell.shellPresenter.session.velocityPage().interactionActive, false,
                "overlap Escape leaves no live gesture after release")
        press = overlap().point
        mouseClick(input, press.x, press.y)
        tryVerify(function() {
            return JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === pair[1].id && note.selected
            })
        }, 3000, "a fresh click retargets the painted following node")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Right)
        tryVerify(function() {
            var notes = JSON.parse(grid.noteSummary)
            var next = notes.find(function(note) { return note.id === pair[1].id })
            var first = notes.find(function(note) { return note.id === pair[0].id })
            return next && first && next.tick === pair[1].tick + grid.snapTicks
                   && first.tick === pair[0].tick
        }, 3000, "Right after an overlap click moves only the visible following note")
    }

    function test_kVelocityGestureTermination_data() {
        return [
            { tag: "page-switch", route: "page-switch" },
            { tag: "drawer-hide", route: "drawer-hide" },
            { tag: "focus-loss", route: "focus-loss" },
            { tag: "tab-switch", route: "tab-switch" },
            { tag: "last-tab-close", route: "last-tab-close" },
            { tag: "song-reload", route: "song-reload" },
            { tag: "escape", route: "escape" }
        ]
    }

    function test_kVelocityGestureTermination(data) {
        var firstId = openTwoSongShell()
        var session = shell.shellPresenter.session
        if (data.route === "last-tab-close") {
            session.songTabs.requestClose(firstId)
            compare(session.songTabs.tabCount, 1,
                    "closing the inactive tab leaves one selected song")
        }
        var surface = selectedSurface()
        selectDrawnVelocityNote(surface)
        var grid = surface.gridModel
        var page = session.velocityPage()
        var plot = findChild(surface, "velocityPlotInput")
        var node = findChild(surface, "velocityNodeFill")
        var focusPlot = findChild(surface, "velocityPlot")
        verify(plot && node && focusPlot, "the production velocity input and node exist")
        focusPlot.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(focusPlot, "activeFocus", true, 3000)
        var terminalRoute = data.route === "last-tab-close"
                || data.route === "song-reload"
        var hit = node.mapToItem(plot, node.width / 2, node.height / 2)
        var dragY = hit.y < plot.height / 2 ? hit.y + 30 : hit.y - 30
        if (terminalRoute) {
            var initialRevision = grid.appliedRevisionText
            mousePress(plot, hit.x, hit.y, Qt.LeftButton)
            mouseMove(plot, hit.x, dragY, -1, Qt.LeftButton)
            mouseRelease(plot, hit.x, dragY, Qt.LeftButton)
            tryVerify(function() { return grid.appliedRevisionText !== initialRevision },
                      3000, "a committed edit makes the real close gate hold the tab")
            tryCompare(session, "documentDirty", true, 3000)
            node = findChild(surface, "velocityNodeFill")
            hit = node.mapToItem(plot, node.width / 2, node.height / 2)
            dragY = hit.y < plot.height / 2 ? hit.y + 30 : hit.y - 30
        }
        var beforeNotes = grid.noteSummary
        var beforeRevision = grid.appliedRevisionText
        mousePress(plot, hit.x, hit.y, Qt.LeftButton)
        mouseMove(plot, hit.x, dragY, -1, Qt.LeftButton)
        tryCompare(page, "interactionActive", true, 3000)
        tryCompare(plot, "pressed", true, 3000)
        var closingId = session.songTabs.selectedId
        if (data.route === "page-switch") {
            surface.drawerPresenter.toggleSection(0, true)
        } else if (data.route === "drawer-hide") {
            surface.drawerPresenter.setSectionVisible(
                        bootstrap.velocitySectionKind(), false, true)
        } else if (data.route === "focus-loss") {
            var roll = findChild(surface, "swiftRollInput")
            verify(roll, "the roll focus destination exists")
            roll.forceActiveFocus(Qt.OtherFocusReason)
            tryCompare(roll, "activeFocus", true, 3000)
        } else if (data.route === "tab-switch") {
            session.songTabs.selectTab(firstId)
            compare(session.songTabs.selectedId, firstId,
                    "the real tab controller selects the other song")
        } else if (data.route === "last-tab-close") {
            session.songTabs.requestClose(closingId)
        } else if (data.route === "song-reload") {
            session.openSong("mus_littleroot_test")
        } else {
            keyClick(Qt.Key_Escape)
        }
        if (terminalRoute) {
            tryCompare(session.songTabs, "pendingCloseId", closingId, 3000)
            tryCompare(page, "interactionActive", false, 3000)
            mouseRelease(plot, hit.x, dragY, Qt.LeftButton)
            compare(page.selectedCount, 1, "the close gate preserves the selected note")
            compare(grid.noteSummary, beforeNotes, "the close gate writes no velocity")
            compare(grid.appliedRevisionText, beforeRevision,
                    "the close gate does not advance document revision")
            compare(session.documentDirty, true,
                    "the earlier setup edit remains unsaved until Discard")
            session.songTabs.confirmDiscard()
            if (data.route === "last-tab-close") {
                tryCompare(session.songTabs, "tabCount", 0, 3000)
            } else {
                verify(waitForNative(function() {
                    return session.songTabs.tabCount === 2
                            || session.lastSaveError.length > 0
                }, 30000), "the reload completion returns through the native run loop")
                compare(session.songTabs.tabCount, 2,
                        "the replacement song rejoins the surviving tab")
                var mountedTabs = findChild(shell.sceneLoader.item, "songTabPages").parent
                verify(waitForNative(function() {
                    var current = mountedTabs.selectedEditorSurface()
                    return session.songTabs.selectedId === closingId
                            && session.songTabs.selectedPage
                            && current !== null && current.gridModel !== grid
                            && current.gridModel === session.songTabs.selectedPage.gridPresenter()
                }, 5000), "reload installs a different workspace for the song")
            }
            return
        }
        tryCompare(page, "interactionActive", false, 3000)
        mouseRelease(plot, hit.x, dragY, Qt.LeftButton)
        tryCompare(plot, "pressed", false, 3000)
        compare(page.selectedCount, 1, "cancellation keeps the selected note")
        compare(grid.noteSummary, beforeNotes, "a cancelled drag never writes note values")
        compare(grid.appliedRevisionText, beforeRevision,
                "a cancelled drag never increments the document revision")
        compare(session.documentDirty, false, "a cancelled drag never dirties the document")
    }
}
