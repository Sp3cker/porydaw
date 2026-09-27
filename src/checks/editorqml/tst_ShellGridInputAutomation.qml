import QtQuick
import QtTest

ShellGridInputSupport {
    function test_mountedAutomationDragDeleteUndoPreservesRoll() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var notesBefore = grid.noteSummary
        var toggle = findChild(surface, "drawerToggle_automation")
        verify(toggle && toggle.visible, "the mounted Automation toggle is available")
        if (!surface.drawerPresenter.automationSection.visible)
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        var page = null
        tryVerify(function() {
            page = findChild(surface, "automationPage")
            return page && page.visible && page.height > 0
        }, 3000, "the production Automation page opens")
        var plot = findChild(page, "automationPlotInput")
        verify(plot && plot.width > 0 && plot.height > 0,
               "the mounted Automation plot accepts input")
        var volumeTab = null
        for (var index = 0; index < page.pageModel.tabCount; ++index) {
            var candidate = findChild(page, "automationParameterTab" + index)
            if (candidate && candidate.text === "Volume") {
                volumeTab = candidate
                break
            }
        }
        verify(volumeTab && volumeTab.enabled, "Volume is available in the mounted drawer")
        var tabPress = findChild(volumeTab,
                                 "automationParameterTabPress" + volumeTab.model.index)
        verify(tabPress, "the Volume label accepts the real pointer")
        mouseClick(tabPress, tabPress.width / 2, tabPress.height / 2)
        tryCompare(volumeTab, "checked", true, 3000)
        var row = plot.height / 2
        var start = plot.width * 0.3
        var stop = plot.width * 0.55
        dragLeft(plot, start, row, stop, row)
        tryVerify(function() { return page.pageModel.nodeCount > 1 }, 3000,
                  "a real Volume sweep writes nodes")
        function writtenNodes(item, result) {
            if (item.objectName === "automationNode" && item.model
                && !item.model.projected && !item.model.phantom)
                result.push({tick: item.model.tick, x: item.model.x,
                             y: item.model.y, selected: item.model.selected})
            for (var child = 0; child < item.children.length; ++child)
                writtenNodes(item.children[child], result)
            return result
        }
        var written = writtenNodes(page, [])
        verify(written.length > 1, "the sweep exposes multiple written nodes")
        var grabbed = written[Math.floor(written.length / 2)]
        var movedY = grabbed.y < plot.height / 2
                     ? grabbed.y + plot.height / 4 : grabbed.y - plot.height / 4
        var armY = grabbed.y + (movedY > grabbed.y ? 1 : -1)
                   * (Qt.styleHints.startDragDistance + 2)
        var releaseY = armY + movedY - grabbed.y
        mousePress(plot, grabbed.x, grabbed.y, Qt.LeftButton)
        mouseMove(plot, grabbed.x, armY, -1, Qt.LeftButton)
        mouseMove(plot, grabbed.x, releaseY, -1, Qt.LeftButton)
        mouseRelease(plot, grabbed.x, releaseY, Qt.LeftButton)
        tryVerify(function() {
            return writtenNodes(page, []).some(function(node) {
                return node.tick === grabbed.tick && Math.abs(node.y - grabbed.y) > 4
            })
        }, 3000, "the mounted pointer drag moves the written automation node")
        var moved = writtenNodes(page, []).find(function(node) {
            return node.tick === grabbed.tick && Math.abs(node.y - grabbed.y) > 4
        })
        var bandStart = Math.max(1, start - Qt.styleHints.startDragDistance * 2)
        var bandEnd = Math.min(plot.width - 1, stop + Qt.styleHints.startDragDistance * 2)
        dragRight(plot, bandStart, moved.y, bandEnd, moved.y)
        tryVerify(function() {
            return writtenNodes(page, []).some(function(node) { return node.selected })
        }, 3000, "the real right drag highlights a selected Automation node")
        plot.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(plot, "activeFocus", true, 3000)
        keyClick(Qt.Key_Delete)
        verify(waitForNative(function() {
            return !writtenNodes(page, []).some(function(node) { return node.tick === grabbed.tick })
        }, 5000), "Delete routes to the selected automation node")
        var undoAction = findChild(shell, "shellAction_edit.undo")
        verify(undoAction && undoAction.enabled,
               "the deleted Automation transaction enables the production Undo action")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return writtenNodes(page, []).some(function(node) {
                return node.tick === grabbed.tick && Math.abs(node.y - moved.y) < 4
            })
        }, 5000), "Undo restores the deleted visible automation node")
        dragRight(plot, bandStart, moved.y, bandEnd, moved.y)
        var selectedBand = null
        tryVerify(function() {
            selectedBand = findChild(page, "automationSelectionFill")
            return selectedBand && selectedBand.visible && selectedBand.width > 0
                && writtenNodes(page, []).some(function(node) {
                    return node.tick === grabbed.tick && node.selected
                })
        }, 3000, "the mounted range paints its interval and selects its written node")
        var bandBefore = selectedBand.x
        var originalTicks = writtenNodes(page, []).map(function(node) { return node.tick })
        var selectedNode = writtenNodes(page, []).find(function(node) {
            return node.tick === grabbed.tick && node.selected
        })
        var armX = selectedNode.x + Qt.styleHints.startDragDistance + 2
        var endX = armX + Math.min(plot.width / 8, plot.width - armX - 4)
        var beforeShift = page.pageModel.nodeCount
        var beforeShiftTicks = writtenNodes(page, []).map(function(node) {
            return [node.tick, node.x, node.y]
        })
        var beforeShiftRevision = grid.appliedRevisionText
        mousePress(plot, selectedNode.x, selectedNode.y, Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(plot, armX, selectedNode.y, -1, Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(plot, endX, selectedNode.y, -1, Qt.LeftButton, Qt.ShiftModifier)
        compare(page.pageModel.nodeCount, beforeShift,
                "held Shift range move preserves the number of visible nodes")
        compare(JSON.stringify(writtenNodes(page, []).map(function(node) {
            return [node.tick, node.x, node.y]
        })), JSON.stringify(beforeShiftTicks),
                "held Shift range move preserves every visible node tick and coordinate")
        compare(grid.appliedRevisionText, beforeShiftRevision,
                "held Shift range move leaves the applied document revision unchanged")
        mouseRelease(plot, endX, selectedNode.y, Qt.LeftButton, Qt.ShiftModifier)
        tryVerify(function() {
            selectedBand = findChild(page, "automationSelectionFill")
            return selectedBand && selectedBand.visible && selectedBand.x > bandBefore
                && writtenNodes(page, []).some(function(node) {
                    return node.selected && originalTicks.indexOf(node.tick) === -1
                })
        }, 3000, "Shift release commits translated nodes and renders the moved range")
        var shiftedTicks = writtenNodes(page, []).filter(function(node) {
            return node.selected && originalTicks.indexOf(node.tick) === -1
        }).map(function(node) { return node.tick })
        var restoredBandStart = selectedBand.x
        var restoredBandEnd = selectedBand.x + selectedBand.width
        plot.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(plot, "activeFocus", true, 3000)
        keyClick(Qt.Key_Delete)
        tryVerify(function() {
            return shiftedTicks.every(function(tick) {
                return !writtenNodes(page, []).some(function(node) { return node.tick === tick })
            })
        }, 3000, "Delete removes every shifted selected automation point")
        tryCompare(undoAction, "enabled", true, 3000)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return shiftedTicks.every(function(tick) {
                return writtenNodes(page, []).some(function(node) { return node.tick === tick })
            })
        }, 5000), "Undo recovers the moved written points through the mounted drawer")
        dragRight(plot, restoredBandStart, selectedNode.y,
                  restoredBandEnd, selectedNode.y)
        tryVerify(function() {
            var restoredBand = findChild(page, "automationSelectionFill")
            return restoredBand && restoredBand.visible && restoredBand.width > 0
                && writtenNodes(page, []).some(function(node) {
                    return shiftedTicks.indexOf(node.tick) !== -1 && node.selected
                })
        }, 3000, "a real pointer sweep repaints the restored selected interval")
        compare(grid.noteSummary, notesBefore,
                "Automation pointer and Delete Undo leave all roll notes unchanged")
    }

    function test_mountedMixedAutomationRangeDragDeleteUndo() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var originalNotes = grid.noteSummary
        var toggle = findChild(surface, "drawerToggle_automation")
        verify(toggle && toggle.visible, "mixed range reaches the production Automation toggle")
        if (!surface.drawerPresenter.automationSection.visible)
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        var page = null
        tryVerify(function() {
            page = findChild(surface, "automationPage")
            return page && page.visible && page.height > 0
        }, 3000, "the mixed range mounts the production Automation drawer")
        var plot = findChild(page, "automationPlotInput")
        verify(plot && plot.width > 0 && plot.height > 0,
               "the mixed range plot accepts real pointer input")
        function written() {
            var nodes = []
            function visit(item) {
                if (item.objectName === "automationNode" && item.model
                    && !item.model.projected && !item.model.phantom)
                    nodes.push({tick: item.model.tick, x: item.model.x,
                                y: item.model.y, selected: item.model.selected})
                for (var child = 0; child < item.children.length; ++child)
                    visit(item.children[child])
            }
            visit(page)
            return nodes
        }
        function activate(label) {
            for (var index = 0; index < page.pageModel.tabCount; ++index) {
                var tab = findChild(page, "automationParameterTab" + index)
                if (tab && tab.text === label) {
                    verify(tab.enabled, label + " supports real pointer selection")
                    tab.forceActiveFocus(Qt.OtherFocusReason)
                    var press = findChild(tab, "automationParameterTabPress" + tab.model.index)
                    verify(press, label + " exposes its selector press area")
                    mouseClick(press, press.width / 2, press.height / 2)
                    tryCompare(tab, "checked", true, 3000)
                    return
                }
            }
            fail("the mounted selector has no " + label + " parameter")
        }
        var start = plot.width * 0.31
        var stop = plot.width * 0.53
        var row = plot.height * 0.45
        activate("Pan")
        dragLeft(plot, start, row, stop, row)
        tryVerify(function() { return written().length > 1 }, 3000,
                  "real Pan sweep writes selected-range source points")
        var panStart = written().find(function(node) { return node.tick > 0 })
        activate("LFO speed")
        dragLeft(plot, start, row, stop, row)
        tryVerify(function() { return written().length > 0 }, 3000,
                  "real LFO speed sweep writes a selected-range source point")
        var lfoStart = written().find(function(node) { return node.tick > 0 })
        activate("Tempo")
        mouseClick(plot, panStart.x, row, Qt.LeftButton)
        tryVerify(function() {
            return written().some(function(node) { return node.tick > 0 })
        }, 3000, "real Tempo click writes a selected-range source point")
        var tempoStart = written().find(function(node) { return node.tick > 0 })
        var ruler = findChild(surface, "timelineRulerInput")
        verify(ruler && ruler.width > 0, "the mounted shared ruler accepts real range input")
        var cameraScale = grid.beatWidth / grid.ticksPerBeat
        var firstTick = Math.max(0, Math.min(panStart.tick, lfoStart.tick, tempoStart.tick)
                                    - grid.snapTicks)
        var lastTick = Math.max(panStart.tick, lfoStart.tick, tempoStart.tick)
                       + 8 * grid.snapTicks
        var rulerStart = Math.max(1, firstTick * cameraScale - grid.cameraScrollX)
        var rulerStop = Math.min(ruler.width - 1, lastTick * cameraScale - grid.cameraScrollX)
        mousePress(ruler, rulerStart, ruler.height / 2, Qt.LeftButton, Qt.ControlModifier)
        mouseMove(ruler, rulerStop, ruler.height / 2, -1, Qt.LeftButton, Qt.ControlModifier)
        mouseRelease(ruler, rulerStop, ruler.height / 2, Qt.LeftButton, Qt.ControlModifier)
        tryVerify(function() {
            return written().some(function(node) {
                return node.tick === tempoStart.tick && node.selected
            })
        }, 3000, "the shared multi-track ruler selects a visible Tempo point")
        activate("Pan")
        verify(written().some(function(node) {
            return node.tick === panStart.tick && node.selected
        }), "the same real ruler interval covers its Pan source")
        activate("LFO speed")
        verify(written().some(function(node) {
            return node.tick === lfoStart.tick && node.selected
        }), "the same real ruler interval covers its LFO source")
        activate("Tempo")
        var mixedBand = findChild(page, "automationSelectionFill")
        verify(mixedBand && mixedBand.visible && mixedBand.width > 0,
               "the mounted mixed-track interval paints a visible range band")
        var mixedBandX = mixedBand.x
        var tempoBefore = written().map(function(node) { return [node.tick, node.x, node.y] })
        var revisionBefore = grid.appliedRevisionText
        var armX = tempoStart.x + Qt.styleHints.startDragDistance + 2
        var endX = armX + Math.min(plot.width / 8, plot.width - armX - 4)
        mousePress(plot, tempoStart.x, tempoStart.y, Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(plot, armX, tempoStart.y, -1, Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(plot, endX, tempoStart.y, -1, Qt.LeftButton, Qt.ShiftModifier)
        compare(JSON.stringify(written().map(function(node) {
            return [node.tick, node.x, node.y]
        })), JSON.stringify(tempoBefore),
                "held mixed Shift drag preserves every displayed Tempo point")
        compare(grid.appliedRevisionText, revisionBefore,
                "held mixed Shift drag leaves the document revision unchanged")
        mouseRelease(plot, endX, tempoStart.y, Qt.LeftButton, Qt.ShiftModifier)
        tryVerify(function() {
            return written().some(function(node) {
                return node.selected && node.tick > tempoStart.tick
            })
        }, 3000, "mixed Shift release moves the selected Tempo point")
        tryVerify(function() {
            mixedBand = findChild(page, "automationSelectionFill")
            return mixedBand && mixedBand.visible && mixedBand.width > 0
                && mixedBand.x > mixedBandX
        }, 3000, "mixed Shift release translates the rendered selection interval")
        verify(grid.appliedRevisionText !== revisionBefore,
               "mixed Shift release commits the shared edit to the mounted document")
        var movedTempo = written().find(function(node) {
            return node.selected && node.tick > tempoStart.tick
        })
        var delta = movedTempo.tick - tempoStart.tick
        verify(!written().some(function(node) { return node.tick === tempoStart.tick }),
               "mixed Tempo Shift drag vacates its original source tick")
        activate("Pan")
        tryVerify(function() {
            return !written().some(function(node) { return node.tick === panStart.tick })
                && written().some(function(node) {
                    return node.selected && node.tick === panStart.tick + delta
                })
        }, 3000, "mixed Shift release translates Pan by exactly the Tempo tick delta")
        activate("LFO speed")
        tryVerify(function() {
            return !written().some(function(node) { return node.tick === lfoStart.tick })
                && written().some(function(node) {
                    return node.selected && node.tick === lfoStart.tick + delta
                })
        }, 3000, "mixed Shift release translates LFO by exactly the Tempo tick delta")
        plot.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(plot, "activeFocus", true, 3000)
        keyClick(Qt.Key_Delete)
        tryVerify(function() {
            return !written().some(function(node) {
                return node.tick === lfoStart.tick + delta
            })
        }, 3000, "mounted mixed Delete removes the exact translated LFO occurrence")
        activate("Pan")
        verify(!written().some(function(node) { return node.tick === panStart.tick + delta }),
               "mounted mixed Delete removes the exact translated Pan occurrence")
        activate("Tempo")
        verify(!written().some(function(node) { return node.tick === tempoStart.tick + delta }),
               "mounted mixed Delete removes the exact translated Tempo occurrence")
        var undoAction = findChild(shell, "shellAction_edit.undo")
        verify(undoAction && undoAction.enabled, "mixed Delete enables the window Undo action")
        activate("LFO speed")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return written().some(function(node) {
                return node.tick === lfoStart.tick + delta
            })
        }, 5000), "mixed Undo visibly recovers the exact translated LFO occurrence")
        activate("Pan")
        verify(written().some(function(node) { return node.tick === panStart.tick + delta }),
               "mixed Undo restores the translated Pan occurrence")
        activate("Tempo")
        verify(written().some(function(node) { return node.tick === tempoStart.tick + delta }),
               "mixed Undo restores the translated Tempo occurrence")
        compare(grid.noteSummary, originalNotes, "mixed Automation edits preserve all roll notes")
    }

}
