import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
    function test_kParameterTabActivationAndTapCession() {
        openTwoSongShell()
        var surface = selectedSurface()
        var session = shell.shellPresenter.session
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the production roll is mounted")
        selectDrawnVelocityNote(surface)
        var notesBefore = grid.noteSummary
        var cursorBefore = grid.editCursorTick
        var trackBefore = grid.trackIndex
        compare(session.documentDirty, false, "tab activation starts from a clean song")
        var playhead = session.playheadPresenter()
        compare(playhead.playing, false, "tab activation starts with transport stopped")
        var toggle = findChild(surface, "drawerToggle_automation")
        verify(toggle && toggle.visible, "the real automation section can be opened")
        mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        var page = null
        tryVerify(function() {
            page = findChild(surface, "automationPage")
            return page && page.visible && page.height > 0
        }, 3000, "the active song mounts its automation plot")
        tryCompare(page, "activeFocus", true, 3000,
                   "the opened automation band owns active focus before the Tap journey")
        var model = page.pageModel
        verify(model && model.tabCount > 1, "the track exposes multiple parameter tabs")
        var initialActive = null
        for (var scanIndex = 0; scanIndex < model.tabCount; ++scanIndex) {
            var scanCandidate = findChild(page, "automationParameterTab" + scanIndex)
            if (scanCandidate && scanCandidate.enabled && scanCandidate.checked)
                initialActive = scanCandidate
        }
        verify(initialActive, "one parameter tab starts active")
        var firstLabel = findChild(page, "automationParameterTab1")
        var secondLabel = findChild(page, "automationParameterTab2")
        verify(firstLabel && firstLabel.enabled && firstLabel.text === "Pan"
               && firstLabel.model.index === 1 && firstLabel !== initialActive,
               "the focused first parameter is the controller 10 Pan lane")
        verify(firstLabel && firstLabel !== initialActive, "an inactive label is available")
        verify(secondLabel && secondLabel.enabled && secondLabel.text === "Modulation"
               && secondLabel.model.index === 2 && secondLabel !== firstLabel,
               "the focused second parameter is the controller 1 Modulation lane")
        verify(secondLabel && secondLabel !== firstLabel, "a second label is available")
        var tempoTab = null
        for (var tempoIndex = 0; tempoIndex < model.tabCount; ++tempoIndex) {
            var tempoCandidate = findChild(page, "automationParameterTab" + tempoIndex)
            if (tempoCandidate && tempoCandidate.enabled
                    && findChild(tempoCandidate, "automationTempoTapButton")) {
                tempoTab = tempoCandidate
                break
            }
        }
        verify(tempoTab, "the tempo tab hosts the tap button")
        verify(tempoTab && tempoTab.enabled && tempoTab.model.tempo,
               "the Tempo parameter is enabled before its focused Tap button")
        var tapButton = findChild(page, "automationTempoTapButton")
        verify(tapButton && tapButton.visible, "the tempo Tap button is drawn")
        firstLabel.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(firstLabel, "activeFocus", true, 3000,
                   "the first label takes keyboard focus")
        verify(!firstLabel.checked, "the focused label is not yet active")
        var activeBeforeSpace = null
        for (var checkedIndex = 0; checkedIndex < model.tabCount; ++checkedIndex) {
            var checkedCandidate = findChild(page, "automationParameterTab" + checkedIndex)
            if (checkedCandidate && checkedCandidate.checked)
                activeBeforeSpace = checkedCandidate.objectName
        }
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000,
                   "bare Space on a focused label owns transport")
        compare(firstLabel.checked, false, "transport Space never activates the label")
        var activeAfterSpace = null
        for (var rescanIndex = 0; rescanIndex < model.tabCount; ++rescanIndex) {
            var rescanCandidate = findChild(page, "automationParameterTab" + rescanIndex)
            if (rescanCandidate && rescanCandidate.checked)
                activeAfterSpace = rescanCandidate.objectName
        }
        compare(activeAfterSpace, activeBeforeSpace, "transport Space never retargets activation")
        compare(session.documentDirty, false, "transport Space never edits the song")
        compare(grid.noteSummary, notesBefore, "transport Space never moves the selection")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000,
                   "the second label Space stops transport")
        keyClick(Qt.Key_Enter)
        tryCompare(firstLabel, "checked", true, 3000,
                   "Enter activates the focused label once")
        compare(session.documentDirty, false, "label Enter never edits the song")
        compare(grid.noteSummary, notesBefore, "label Enter never moves the selection")
        compare(grid.editCursorTick, cursorBefore, "label Enter never moves the cursor")
        compare(grid.trackIndex, trackBefore, "label Enter never retargets the track")
        secondLabel.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(secondLabel, "activeFocus", true, 3000,
                   "the second label takes keyboard focus")
        keyClick(Qt.Key_Return)
        tryCompare(secondLabel, "checked", true, 3000,
                   "Return activates the focused second label")
        compare(firstLabel.checked, false, "Return retargets activation exactly once")
        var secondActivationChanges = 0
        firstLabel.checkedChanged.connect(function() { ++secondActivationChanges })
        secondLabel.checkedChanged.connect(function() { ++secondActivationChanges })
        keyClick(Qt.Key_Return)
        compare(secondActivationChanges, 0, "a second activation never stacks")
        compare(session.documentDirty, false, "label Return never edits the song")
        compare(grid.noteSummary, notesBefore, "label Return never moves the selection")
        compare(grid.editCursorTick, cursorBefore, "label Return never moves the cursor")
        var plot = findChild(page, "automationPlotInput")
        verify(plot && plot.width > 0 && plot.height > 0,
               "the mounted automation plot is available for the Tap time band")
        var bandY = plot.height / 2
        mousePress(plot, plot.width / 5, bandY, Qt.RightButton)
        mouseMove(plot, plot.width * 3 / 5, bandY, -1, Qt.RightButton)
        mouseRelease(plot, plot.width * 3 / 5, bandY, Qt.RightButton)
        var insertTime = findChild(shell, "shellAction_edit.insert_time")
        tryCompare(insertTime, "enabled", true, 3000,
                   "a real automation band stages a lane time range before Tap Space")
        notesBefore = grid.noteSummary
        tapButton.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(tapButton, "activeFocus", true, 3000,
                   "the tempo Tap button takes keyboard focus")
        var revisionBeforeTap = grid.appliedRevisionText
        var undoBeforeTap = session.canUndo
        keyClick(Qt.Key_Enter)
        tryCompare(model, "tapTempoTapCount", 1, 3000,
                   "Enter on the focused Tap button registers exactly one tap")
        compare(tapButton.activeFocus, true, "the first tap keeps button focus")
        keyClick(Qt.Key_Return)
        tryCompare(model, "tapTempoTapCount", 2, 3000,
                   "Return on the focused Tap button adds the second tap")
        var draft = findChild(page, "automationTempoTapDraft")
        verify(draft && draft.visible, "the two-tap session shows the draft readout")
        verify(draft.text.indexOf("BPM") >= 0, "the two-tap draft names a tempo")
        verify(grid.appliedRevisionText === revisionBeforeTap && session.canUndo === undoBeforeTap,
               "tap keys never change the revision or undo availability")
        compare(secondLabel.checked, true, "Return never retargets the active parameter")
        compare(session.documentDirty, false, "tap keys never edit the song")
        compare(grid.noteSummary, notesBefore, "tap keys never move the selection")
        keyClick(Qt.Key_Return, Qt.ShiftModifier)
        compare(model.tapTempoTapCount, 2, "Shift+Return never registers a tap")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000,
                   "bare Space on the Tap button owns transport")
        compare(model.tapTempoTapCount, 2, "transport Space never taps")
        compare(session.documentDirty, false, "tap Space never edits the song")
        compare(grid.noteSummary, notesBefore, "tap Space never moves the selection")
        compare(insertTime.enabled, true,
                "Tap Space preserves the mounted automation lane time range")
        verify(grid.appliedRevisionText === revisionBeforeTap && session.canUndo === undoBeforeTap,
               "tap Space never changes the revision or undo availability")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000,
                   "the second tap Space stops transport")
        model.resetTapTempo()
        compare(model.tapTempoTapCount, 0, "resetTapTempo drops the draft")
    }

    function test_nLabelTimeSelectionCommands() {
        settings.setString("windowState", "")
        settings.setString("windowGeometry", "")
        openTwoSongShell()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var toggle = findChild(surface, "drawerToggle_automation")
        if (!surface.drawerPresenter.automationSection.visible)
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        var page = null
        tryVerify(function() {
            page = findChild(surface, "automationPage")
            return page && page.visible && page.height > 0
        }, 3000, "the automation page mounts for the time selection")
        var volumeTab = null
        for (var index = 0; index < page.pageModel.tabCount; ++index) {
            var candidate = findChild(page, "automationParameterTab" + index)
            if (candidate && candidate.text === "Volume") {
                volumeTab = candidate
                break
            }
        }
        verify(volumeTab && volumeTab.enabled, "the Volume label is available")
        var tabPress = findChild(volumeTab, "automationParameterTabPress" + volumeTab.model.index)
        mouseClick(tabPress, tabPress.width / 2, tabPress.height / 2)
        tryCompare(volumeTab, "checked", true, 3000)
        var plot = findChild(page, "automationPlotInput")
        tryVerify(function() {
            return plot && plot.width > 0 && plot.height > 0
        }, 3000, "the mounted plot can stage a range by pointer; shell="
                 + shell.width + "x" + shell.height + "; surface="
                 + surface.width + "x" + surface.height
                 + "; page=" + page.width + "x" + page.height + "; plot="
                 + (plot ? plot.width + "x" + plot.height : "missing")
                 + "; modelPlot=" + page.plotWidth
                 + "; sectionVisible=" + surface.drawerPresenter.automationSection.visible
                 + "; debugger=" + shell.shellPresenter.polyphonyVisible
                 + "; dock=" + shell.shellPresenter.dockColumnWidth)
        var row = plot.height / 2
        mousePress(plot, plot.width / 4, row, Qt.LeftButton)
        mouseMove(plot, plot.width / 3, row, -1, Qt.LeftButton)
        mouseMove(plot, plot.width / 2, row, -1, Qt.LeftButton)
        mouseRelease(plot, plot.width / 2, row, Qt.LeftButton)
        tryVerify(function() { return page.pageModel.nodeCount > 1 }, 3000,
                  "a real plot sweep writes Volume events")
        var sweepCount = page.pageModel.nodeCount
        mousePress(plot, plot.width * 3 / 4, row, Qt.LeftButton)
        mouseMove(plot, plot.width * 4 / 5, row, -1, Qt.LeftButton)
        mouseRelease(plot, plot.width * 4 / 5, row, Qt.LeftButton)
        tryVerify(function() { return page.pageModel.nodeCount > sweepCount }, 3000,
                  "a separate Volume event lies outside the staged range")
        var beforeCount = page.pageModel.nodeCount
        var pair = selectMountedNotePair(surface)
        compare(pair.length, 2, "the real click and Shift-click select exactly the two note IDs")
        var beforeNotes = grid.noteSummary
        var revisionBeforeSelection = grid.appliedRevisionText
        mousePress(plot, plot.width / 5, row, Qt.RightButton)
        mouseMove(plot, plot.width * 3 / 5, row, -1, Qt.RightButton)
        mouseRelease(plot, plot.width * 3 / 5, row, Qt.RightButton)
        var insertTime = findChild(shell, "shellAction_edit.insert_time")
        tryCompare(insertTime, "enabled", true, 3000, "the right-band selects Volume time")
        compare(grid.appliedRevisionText, revisionBeforeSelection,
                "the right-band alone never writes a lane")
        beforeNotes = grid.noteSummary
        verify(pair.every(function(previous) {
            var retained = JSON.parse(beforeNotes).find(function(note) {
                return note.id === previous.id
            })
            return retained && !retained.selected
        }), "the real lane range clears the competing pair selection")
        volumeTab.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(volumeTab, "activeFocus", true, 3000)
        var shortcut = windowShortcut("shellShortcut_roll.copy")
        copyActivatedSpy.target = shortcut
        copyActivatedSpy.clear()
        keySequence(StandardKey.Copy)
        var copied = JSON.parse(clipProbe.readClipJson())
        verify(copyActivatedSpy.count === 1 && copied.lanes.length === 1
               && copied.lanes[0].cc === 7 && copied.lanes[0].points.length > 0,
               "window Copy over label focus captures the selected Volume lane; bytes="
               + clipProbe.readClipJson() + "; activations=" + copyActivatedSpy.count)
        compare(grid.appliedRevisionText, revisionBeforeSelection,
                "window Copy over label focus never writes the document")
        compare(volumeTab.activeFocus, true, "A066 label retains active focus across range Copy")
        function writtenTicks(item, result) {
            if (item.objectName === "automationNode" && item.model
                    && !item.model.projected && !item.model.phantom)
                result.push(item.model.tick)
            for (var child = 0; child < item.children.length; ++child)
                writtenTicks(item.children[child], result)
            return result
        }
        var outsideTick = Math.max.apply(null, writtenTicks(page, []))
        var beforeUp = writtenTicks(page, []).sort(function(a, b) { return a - b })
        var beforeUpRevision = grid.appliedRevisionText
        keyClick(Qt.Key_Up)
        compare(grid.appliedRevisionText, beforeUpRevision,
                "lane-focus Up leaves the document untouched")
        compare(JSON.stringify(writtenTicks(page, []).sort(function(a, b) { return a - b })),
                JSON.stringify(beforeUp), "lane-focus Up preserves every Volume point")
        keyClick(Qt.Key_Right)
        var advanced = writtenTicks(page, []).sort(function(a, b) { return a - b })
        verify(advanced.length === beforeUp.length
               && advanced.some(function(tick, index) { return tick !== beforeUp[index] })
               && grid.noteSummary === beforeNotes
               && insertTime.enabled,
               "lane-focus Right moves the point and translates the interval")
        keyClick(Qt.Key_Delete)
        verify(page.pageModel.nodeCount < beforeCount,
               "Delete over label focus removes the selected Volume points")
        verify(writtenTicks(page, []).indexOf(outsideTick) >= 0
               && page.pageModel.nodeCount < beforeCount,
               "Delete removes only the lane points inside the staged range")
        compare(grid.noteSummary, beforeNotes, "Volume range Delete preserves the notes")
        compare(volumeTab.activeFocus, true, "A066 label retains active focus after Delete")
        verify(pair.every(function(previous) {
            var retained = JSON.parse(grid.noteSummary).find(function(note) {
                return note.id === previous.id
            })
            return retained && retained.tick === previous.tick
                   && retained.pitch === previous.pitch
        }), "A065 Delete leaves both reserved notes at their original tick and pitch")
        compare(insertTime.enabled, true, "Delete keeps the selected time range")
        verify(!JSON.parse(beforeNotes).some(function(note) { return note.selected }),
               "the lane-only range begins with an empty note selection")
        keySequence(StandardKey.SelectAll)
        compare(findChild(shell, "shellAction_edit.delete_time").enabled, false,
                "Select All over label focus clears the time range")
        var activeNotes = JSON.parse(grid.noteSummary).filter(function(note) {
            return note.track === grid.trackIndex && !note.ghost
        })
        verify(activeNotes.length > 0 && activeNotes.every(function(note) { return note.selected }),
               "Select All over label focus selects the active track's notes")
        verify(activeNotes.some(function(note) {
            return note.id === pair[0].id && note.selected
        }), "A067 Select All includes the first reserved note by its original ID")
        verify(activeNotes.some(function(note) {
            return note.id === pair[1].id && note.selected
        }), "A068 Select All includes the second reserved note by its original ID")
        grid.setEditCursorTick(7680)
        keySequence(StandardKey.Paste)
        tryVerify(function() {
            return page.pageModel.nodeCount > 0 && grid.editCursorTick > 7680
        }, 3000, "Paste over label focus writes the copied Volume lane at the edit cursor")
        compare(volumeTab.activeFocus, true, "A066 label retains active focus after Paste")
        verify(pair.every(function(previous) {
            var retained = JSON.parse(grid.noteSummary).find(function(note) {
                return note.id === previous.id
            })
            return retained && retained.tick === previous.tick
                   && retained.pitch === previous.pitch
                   && retained.duration === previous.duration
                   && retained.velocity === previous.velocity
                   && retained.track === previous.track
        }), "A075 lane Paste leaves both original notes unchanged by ID")
        var roll = findChild(surface, "swiftRollInput")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_B)
        tryCompare(page.pageModel, "isPencilMode", true, 3000)
        function visibleNode(item) {
            if (item.objectName === "automationNode" && item.model
                    && !item.model.projected && !item.model.phantom
                    && item.model.x > item.model.radius
                    && item.model.x < plot.width - item.model.radius)
                return item
            for (var index = 0; index < item.children.length; ++index) {
                var candidate = visibleNode(item.children[index])
                if (candidate)
                    return candidate
            }
            return null
        }
        var node = visibleNode(page)
        verify(node, "a written Volume node is visible for hover deletion")
        var plotted = findChild(surface, "automationPlot")
        plotted.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(plotted, "activeFocus", true, 3000)
        mouseMove(plot, node.model.x, node.model.y)
        tryVerify(function() { return page.pageModel.hoverDisplay.hasNode }, 3000)
        var hoverTick = node.model.tick
        var pointsBeforeHover = JSON.stringify(writtenTicks(page, []))
        keyClick(Qt.Key_Delete)
        verify(activeNotes.every(function(note) {
            return !JSON.parse(grid.noteSummary).some(function(current) {
                return current.id === note.id && !current.ghost
            })
        }) && JSON.stringify(writtenTicks(page, [])) === pointsBeforeHover,
               "a hovered point survives a selected-note Delete")
        keyClick(Qt.Key_Delete)
        tryVerify(function() {
            return writtenTicks(page, []).indexOf(hoverTick) < 0
        }, 3000, "an eligible hovered point is deleted after note selection clears; "
                 + "selected=" + JSON.stringify(JSON.parse(grid.noteSummary).filter(
                     function(note) { return note.selected }))
                 + "; pencil=" + page.pageModel.isPencilMode
                 + "; focus=" + page.pageModel.plotFocused
                 + "; hover=" + JSON.stringify(page.pageModel.hoverDisplay)
                 + "; points=" + JSON.stringify(writtenTicks(page, [])))
        var untouchedPoints = JSON.stringify(writtenTicks(page, []))
        var revisionAtMiss = grid.appliedRevisionText
        mouseMove(plot, plot.width - grid.keyboardWidth / 2, plot.height / 2)
        tryVerify(function() { return !page.pageModel.hoverDisplay.hasNode }, 3000)
        keyClick(Qt.Key_Delete)
        verify(JSON.stringify(writtenTicks(page, [])) === untouchedPoints
               && grid.appliedRevisionText === revisionAtMiss,
               "a hover miss changes no document bytes")
    }

    function test_oEmptySelectionLabelUpEditsNothing() {
        openTwoSongShell()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var toggle = findChild(surface, "drawerToggle_automation")
        if (!surface.drawerPresenter.automationSection.visible)
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        var page = null
        tryVerify(function() {
            page = findChild(surface, "automationPage")
            return page && page.visible
        }, 3000, "the focused Volume label mounts in the drawer")
        var volumeTab = null
        for (var index = 0; index < page.pageModel.tabCount; ++index) {
            var candidate = findChild(page, "automationParameterTab" + index)
            if (candidate && candidate.text === "Volume") {
                volumeTab = candidate
                break
            }
        }
        verify(volumeTab && volumeTab.enabled, "Volume is a usable label")
        var tabPress = findChild(volumeTab, "automationParameterTabPress" + volumeTab.model.index)
        mouseClick(tabPress, tabPress.width / 2, tabPress.height / 2)
        volumeTab.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(volumeTab, "activeFocus", true, 3000)
        var before = grid.noteSummary
        verify(JSON.parse(before).every(function(note) { return !note.selected }),
               "the label-Up fixture has no selected notes")
        var revision = grid.appliedRevisionText
        keyClick(Qt.Key_Up)
        verify(grid.noteSummary === before && grid.appliedRevisionText === revision
               && volumeTab.activeFocus,
               "label-focus Up with an empty selection edits nothing")
    }
}
