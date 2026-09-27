import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
    function test_mLabelCommandsAndPromptTextOwnership() {
        openTwoSongShell()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var pair = selectMountedNotePair(surface)
        compare(pair.length, 2, "the mounted roll provides a selected note")
        var selected = pair[0]
        function note(id) {
            return JSON.parse(grid.noteSummary).find(function(item) { return item.id === id })
        }
        var toggle = findChild(surface, "drawerToggle_automation")
        if (!surface.drawerPresenter.automationSection.visible)
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        var page = null
        tryVerify(function() {
            page = findChild(surface, "automationPage")
            return page && page.visible && page.height > 0
        }, 3000, "the automation page mounts")
        var model = page.pageModel
        var volumeTab = null
        for (var index = 0; index < model.tabCount; ++index) {
            var candidate = findChild(page, "automationParameterTab" + index)
            if (candidate && candidate.text === "Volume") {
                volumeTab = candidate
                break
            }
        }
        verify(volumeTab && volumeTab.enabled && volumeTab.model.index === 0,
               "the focused Volume label represents controller 7")
        verify(volumeTab && volumeTab.enabled, "the real parameter label is available")
        var tabPress = findChild(volumeTab, "automationParameterTabPress" + volumeTab.model.index)
        mouseClick(tabPress, tabPress.width / 2, tabPress.height / 2)
        tryCompare(volumeTab, "checked", true, 3000)
        volumeTab.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(volumeTab, "activeFocus", true, 3000,
                   "A031 the Volume label owns active focus before commands")
        var labelRevision = grid.appliedRevisionText
        var labelNotes = grid.noteSummary
        keyClick(Qt.Key_Enter)
        keyClick(Qt.Key_Return)
        compare(grid.appliedRevisionText, labelRevision,
                "A038 label Enter and Return never edit the document")
        compare(grid.noteSummary, labelNotes,
                "A038 label activation preserves both selected note identities")
        compare(volumeTab.activeFocus, true, "A038 label retains focus after Enter and Return")
        var shortcut = windowShortcut("shellShortcut_roll.copy")
        verify(shortcut, "the window Copy shortcut is mounted")
        copyActivatedSpy.target = shortcut
        copyActivatedSpy.clear()
        keySequence(StandardKey.Copy)
        compare(copyActivatedSpy.count, 1,
                "window Copy over a focused parameter label captures the selected note")
        compare(JSON.parse(clipProbe.readClipJson()).tracks[0].notes[0].key, selected.pitch,
                "window Copy over label focus preserves the selected note")
        var copiedNotes = JSON.parse(clipProbe.readClipJson()).tracks[0].notes
        compare(copiedNotes.length, 2, "A061 label-focus Copy captures the two selected notes")
        var firstTick = Math.min(pair[0].tick, pair[1].tick)
        verify(pair.every(function(previous) {
            return copiedNotes.some(function(copied) {
                return copied.relTick === previous.tick - firstTick
                       && copied.key === previous.pitch
                       && copied.duration === previous.duration
                       && copied.velocity === previous.velocity
            })
        }), "A061 the copied clip retains both note pitches")
        compare(volumeTab.activeFocus, true, "A066 label keeps active focus after Copy")
        keyClick(Qt.Key_Right)
        verify(pair.every(function(previous) {
            var moved = note(previous.id)
            return moved && moved.tick === previous.tick + grid.snapTicks
                   && moved.pitch === previous.pitch && moved.selected
                   && moved.duration === previous.duration
                   && moved.velocity === previous.velocity && moved.track === previous.track
                   && moved.ghost === previous.ghost
        }), "label-focus arrows advance the selected note one grid step")
        compare(volumeTab.activeFocus, true, "A077 label owns focus before routed arrows")
        keyPress(Qt.Key_Up)
        verify(pair.every(function(previous) {
            var moved = note(previous.id)
            return moved && moved.tick === previous.tick + grid.snapTicks
                   && moved.pitch === previous.pitch + 1 && moved.selected
                   && moved.duration === previous.duration
                   && moved.velocity === previous.velocity && moved.track === previous.track
                   && moved.ghost === previous.ghost
        }), "label-focus Up transposes the selected note")
        verify(shell.shellPresenter.releaseEditorKey(false),
               "real label-focus Up key-down starts a live transpose audition latch")
        keyRelease(Qt.Key_Up)
        keyPress(Qt.Key_Up)
        keyRelease(Qt.Key_Up)
        verify(pair.every(function(previous) {
            return note(previous.id).pitch === previous.pitch + 2
        }), "real label-focus Up down/up transposes the note")
        compare(shell.shellPresenter.releaseEditorKey(false), false,
                "real label-focus Up key-up already ended the audition latch")
        compare(volumeTab.checked, true, "the active parameter survives label-focus commands")

        var notesBefore = grid.noteSummary
        var revisionBefore = grid.appliedRevisionText
        var plot = findChild(page, "automationPlotInput")
        tryVerify(function() { return plot && plot.width > 0 && plot.height > 0 }, 3000,
                  "the real plot is mounted to open the value prompt")
        var row = plot.height / 2
        mousePress(plot, plot.width / 4, row, Qt.LeftButton)
        mouseMove(plot, plot.width / 3, row, -1, Qt.LeftButton)
        mouseMove(plot, plot.width / 2, row, -1, Qt.LeftButton)
        mouseRelease(plot, plot.width / 2, row, Qt.LeftButton)
        verify(waitForNative(function() {
            return model.nodeCount > 1 && grid.appliedRevisionText !== revisionBefore
        }, 3000), "the pointer sweep commits a written Volume point before the menu press")
        mousePress(plot, plot.width / 5, row, Qt.RightButton)
        mouseMove(plot, plot.width * 3 / 5, row, -1, Qt.RightButton)
        mouseRelease(plot, plot.width * 3 / 5, row, Qt.RightButton)
        var insertTime = findChild(shell, "shellAction_edit.insert_time")
        tryCompare(insertTime, "enabled", true, 3000,
                   "the point prompt starts with a selected Volume time range")
        var node = null
        function findWritten(item) {
            if (item.objectName === "automationNode" && item.model
                    && item.model.tick > 0 && !item.model.phantom && !item.model.projected) {
                node = item
                return
            }
            for (var child = 0; child < item.children.length && !node; ++child)
                findWritten(item.children[child])
        }
        findWritten(page)
        verify(node, "a written node has a drawn point-menu target")
        notesBefore = grid.noteSummary
        revisionBefore = grid.appliedRevisionText
        var fill = findChild(node, "automationNodeFill")
        verify(fill && fill.visible, "the written node exposes its rendered hit target")
        var point = fill.mapToItem(plot, fill.width / 2, fill.height / 2)
        mouseClick(plot, point.x, point.y, Qt.RightButton)
        tryCompare(model, "menuOpen", true, 3000,
                   "the real node press publishes its Set Value menu")
        var menu = page.menu
        verify(waitForNative(function() {
            return menu && menu.showing && model.menuOpen
        }, 3000), "the node opens the real automation point menu")
        var menuPanel = findChild(menu, "automationMenuPanel")
        tryVerify(function() { return menuPanel && menuPanel.rowItem(0) }, 3000,
                  "the mounted menu realizes its Set Value row")
        keyClick(Qt.Key_Down)
        tryVerify(function() { return menu.currentActionId() === 1 }, 3000,
                  "the menu keyboard selects its enabled Set Value action")
        keyClick(Qt.Key_Return)
        var prompt = null
        var field = null
        verify(waitForNative(function() {
            prompt = page.prompt
            field = prompt ? findChild(prompt, "automationPromptInput") : null
            return prompt && prompt.showing && field && field.activeFocus
        }, 3000), "the mounted prompt owns focus in its real numeric field")
        var originalDraft = field.text
        verify(originalDraft.length > 0, "the prompt opens with its drafted Volume value")
        var promptSoloShortcut = windowShortcut("shellShortcut_roll.solo_tracks")
        verify(promptSoloShortcut, "the real Solo shortcut is mounted beside automation")
        soloActivatedSpy.target = promptSoloShortcut
        soloActivatedSpy.clear()
        var promptTrack = findChild(surface, "timelineTrackHeaderRows").itemAt(grid.trackIndex)
        verify(promptTrack && !promptTrack.soloChecked,
               "automation numeric input begins with the intended track not soloed")
        field.selectAll()
        keyClick(Qt.Key_1)
        keyClick(Qt.Key_2)
        compare(field.text, "12", "actual digits replace automation numeric draft with 12")
        compare(model.promptOpen, true, "typing 12 keeps the automation prompt open")
        keySequence(StandardKey.SelectAll)
        compare(field.selectedText, "12", "prompt Select All selects the drafted text")
        keySequence(StandardKey.Copy)
        compare(field.selectedText, "12", "prompt Copy leaves the draft selected")
        compare(copyActivatedSpy.count, 1, "prompt Copy never activates the window Copy shortcut")
        compare(clipProbe.readClipJson(), "", "prompt Copy never publishes a song clip")
        keyClick(Qt.Key_Delete)
        compare(field.text, "", "prompt Delete clears only the numeric draft")
        keySequence(StandardKey.Paste)
        compare(field.text, "12", "prompt Paste restores the copied numeric draft")
        compare(grid.noteSummary, notesBefore, "prompt text keys preserve the staged note state")
        keyClick(Qt.Key_Up)
        keyClick(Qt.Key_Down)
        compare(model.promptOpen, true, "automation arrows leave the numeric prompt open")
        compare(field.activeFocus, true, "automation arrows keep numeric focus local")
        compare(grid.noteSummary, notesBefore,
                "automation arrows preserve selected note IDs and contents")
        compare(grid.appliedRevisionText, revisionBefore,
                "automation arrows do not commit a song revision")
        keyClick(Qt.Key_S)
        compare(field.text, "12", "automation numeric validator rejects Solo S")
        compare(promptTrack.soloChecked, false, "automation prompt S leaves Solo off")
        compare(soloActivatedSpy.count, 0, "automation prompt S never activates window Solo")
        keyClick(Qt.Key_Escape)
        tryCompare(model, "promptOpen", false, 3000, "Escape closes the prompt without a write")
        compare(grid.appliedRevisionText, revisionBefore, "Escape never commits a document write")
        compare(grid.noteSummary, notesBefore, "Escape keeps the staged note state unchanged")
        compare(insertTime.enabled, true, "Escape keeps the selected time range unchanged")
        var automationPlot = findChild(page, "automationPlot")
        tryCompare(automationPlot, "activeFocus", true, 3000,
                   "Escape returns automation keyboard focus to the production plot")
        compare(shell.active, true, "the active Qt window resumes automation band commands")
        keyClick(Qt.Key_S)
        tryCompare(promptTrack, "soloChecked", true, 3000,
                   "first resumed automation S turns on intended Solo")
        compare(soloActivatedSpy.count, 1,
                "first resumed automation S activates window Solo once")
        keyClick(Qt.Key_S)
        tryCompare(promptTrack, "soloChecked", false, 3000,
                   "second resumed automation S turns off intended Solo")
        compare(soloActivatedSpy.count, 2,
                "second resumed automation S activates window Solo once")
        compare(volumeTab.checked, true,
                "the controller 7 Volume lane remains active before its 48 insertion")
        verify(model.openInsertionPrompt(96, 48),
               "the active Volume lane opens its production insertion draft of 48")
        verify(waitForNative(function() {
            prompt = page.prompt
            field = prompt ? findChild(prompt, "automationPromptInput") : null
            return prompt && prompt.showing && field && field.activeFocus
        }, 3000), "the Volume insertion draft owns the mounted numeric field")
        compare(field.text, "48", "the Volume insertion displays the exact 48 draft")
        compare(field.selectedText, "48", "the Volume insertion selects the exact 48 draft")
        keySequence(StandardKey.SelectAll)
        compare(field.selectedText, "48", "Volume Select All selects exactly 48")
        var copyCountBeforeInsertion = copyActivatedSpy.count
        keySequence(StandardKey.Copy)
        var textClipboardProbe = textProbeComponent.createObject(shell.contentItem, { text: "" })
        verify(textClipboardProbe, "the Volume clipboard probe is mounted in the live window")
        textClipboardProbe.paste()
        compare(textClipboardProbe.text, "48",
                "the native text clipboard contains exactly 48 after Volume Copy")
        textClipboardProbe.destroy()
        compare(copyActivatedSpy.count, copyCountBeforeInsertion,
                "Volume insertion Copy never activates the window note Copy")
        keyClick(Qt.Key_Delete)
        compare(field.text, "", "Volume insertion Delete removes the selected 48 draft")
        keySequence(StandardKey.Paste)
        compare(field.text, "48", "Volume insertion Paste restores exactly 48")
        keyClick(Qt.Key_Escape)
        tryCompare(model, "promptOpen", false, 3000,
                   "Volume insertion Escape closes its exact 48 draft without a write")
        compare(grid.appliedRevisionText, revisionBefore,
                "Volume insertion Escape preserves the document revision")
        mouseClick(tabPress, tabPress.width / 2, tabPress.height / 2)
        tryCompare(volumeTab, "activeFocus", true, 3000,
                   "the closed value prompt permits refocusing the Volume controller 7 label")
    }
}
