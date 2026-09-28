import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
    function test_cAutomationInsertionPrompts() {
        openTwoSongShell()
        var surface = selectedSurface()
        var session = shell.shellPresenter.session
        var toggle = findChild(surface, "drawerToggle_automation")
        verify(toggle && toggle.visible, "the automation drawer toggle is mounted")
        if (!surface.drawerPresenter.automationSection.visible)
            mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        var page = null
        tryVerify(function() {
            page = findChild(surface, "automationPage")
            return page && page.visible && page.height > 0
        }, 3000, "the insertion prompt has a mounted automation page")
        var model = session.automationPage()
        var tempo = null
        for (var i = 0; i < page.pageModel.tabCount; ++i) {
            var candidate = findChild(page, "automationParameterTab" + i)
            if (candidate && candidate.text === "Tempo") {
                tempo = candidate
                break
            }
        }
        verify(tempo, "the mounted selector offers Tempo")
        verify(model.activateParameter(tempo.model.index) || tempo.checked,
               "the production Tempo selector activates")
        tryCompare(tempo, "checked", true, 3000)
        var grid = surface.gridModel
        var beforeTempo = grid.appliedRevisionText
        verify(model.openInsertionPrompt(24, 140), "the production presenter opens Tempo insertion")
        var field = null
        tryVerify(function() {
            field = findChild(page, "automationPromptInput")
            return field && field.activeFocus
        }, 3000, "Tempo insertion focuses the actual numeric input")
        compare(field.text, "140", "Tempo insertion displays the exact 140 draft")
        compare(field.selectedText, "140", "Tempo insertion selects the entire 140 draft")
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_0)
        compare(field.text, "90", "real digits replace the selected Tempo draft")
        keyClick(Qt.Key_Enter)
        tryCompare(model, "promptOpen", false, 3000)
        verify(grid.appliedRevisionText !== beforeTempo,
               "Tempo insertion commits a document revision through Enter")
        var plot = findChild(page, "automationPlot")
        tryCompare(plot, "activeFocus", true, 3000,
                   "accepted insertion returns focus to automation")

        var pan = null
        for (i = 0; i < page.pageModel.tabCount; ++i) {
            candidate = findChild(page, "automationParameterTab" + i)
            if (candidate && candidate.text === "Pan") {
                pan = candidate
                break
            }
        }
        verify(pan, "the mounted selector offers CC10 Pan")
        verify(model.activateParameter(pan.model.index) || pan.checked,
               "the production Pan selector activates")
        tryCompare(pan, "checked", true, 3000)
        var beforePanCancel = grid.appliedRevisionText
        var beforePanNotes = grid.fetchNoteSummary()
        var beforePanUndo = session.canUndo
        verify(model.openInsertionPrompt(96, 64),
               "value-prompt CC10 insertion opens at empty tick 96")
        tryVerify(function() {
            field = findChild(page, "automationPromptInput")
            return field && field.activeFocus
        }, 3000, "tick-96 insertion focuses the mounted numeric field")
        compare(field.text, "0", "tick-96 CC10 insertion displays exact signed zero")
        keyClick(Qt.Key_Escape)
        tryCompare(model, "promptOpen", false, 3000)
        compare(grid.appliedRevisionText, beforePanCancel,
                "tick-96 insertion Escape preserves the document revision")
        compare(grid.fetchNoteSummary(), beforePanNotes,
                "tick-96 insertion Escape preserves selected notes")
        compare(session.canUndo, beforePanUndo,
                "tick-96 insertion Escape preserves history availability")
        tryCompare(plot, "activeFocus", true, 3000,
                   "tick-96 insertion Escape returns automation plot focus")
        verify(model.openInsertionPrompt(48, 32), "CC10 fixture inserts its tick-48 node")
        model.updatePromptDraft("-32")
        verify(model.acceptPromptDraft(), "CC10 fixture records tick-48")
        verify(model.openInsertionPrompt(96, 64), "CC10 fixture inserts its tick-96 node")
        model.updatePromptDraft("0")
        verify(model.acceptPromptDraft(), "CC10 fixture records tick-96")
        var velocityToggle = findChild(surface, "drawerToggle_velocity")
        verify(velocityToggle && velocityToggle.visible, "the Littleroot velocity drawer toggle is mounted")
        if (!surface.drawerPresenter.section(bootstrap.velocitySectionKind()).visible)
            mouseClick(velocityToggle, velocityToggle.width / 2, velocityToggle.height / 2)
        selectDrawnVelocityNote(surface)
        var selectedNotes = JSON.parse(grid.fetchNoteSummary()).filter(function(note) {
            return note.selected && !note.ghost
        })
        compare(selectedNotes.length, 1, "the tick-144 prompt targets one real selected Littleroot note")
        var beforeCancel = grid.appliedRevisionText
        var beforeNotes = grid.fetchNoteSummary()
        var beforeUndo = session.canUndo
        verify(model.openInsertionPrompt(144, 64), "CC10 insertion opens at empty tick 144")
        tryVerify(function() {
            field = findChild(page, "automationPromptInput")
            return field && field.activeFocus
        }, 3000, "the tick-144 insertion focuses the mounted numeric field")
        compare(field.text, "0", "CC10 insertion displays stored 64 as signed zero")
        field.selectAll()
        keyClick(Qt.Key_1)
        keyClick(Qt.Key_2)
        compare(field.text, "12", "actual CC10 numeric keys type the literal 12")
        keySequence(StandardKey.SelectAll)
        compare(field.selectedText, "12", "CC10 insertion selects its exact typed draft")
        keySequence(StandardKey.Copy)
        keyClick(Qt.Key_Delete)
        keySequence(StandardKey.Paste)
        compare(field.text, "12", "CC10 insertion Copy and Paste restore the typed 12")
        keyClick(Qt.Key_Up)
        keyClick(Qt.Key_Down)
        compare(field.activeFocus, true, "CC10 insertion arrows retain numeric focus")
        var solo = windowShortcut("shellShortcut_roll.solo_tracks")
        verify(solo, "the window Solo shortcut is mounted")
        soloActivatedSpy.target = solo
        soloActivatedSpy.clear()
        var track = findChild(surface, "timelineTrackHeaderRows").itemAt(grid.trackIndex)
        var soloBefore = track.soloChecked
        keyClick(Qt.Key_S)
        compare(field.text, "12", "local S retains the exact numeric insertion draft")
        compare(track.soloChecked, soloBefore, "local S does not toggle the track Solo")
        compare(soloActivatedSpy.count, 0, "local S never activates window Solo")
        keyClick(Qt.Key_Escape)
        tryCompare(model, "promptOpen", false, 3000)
        compare(grid.appliedRevisionText, beforeCancel,
                "CC10 insertion Escape preserves its document revision")
        compare(grid.fetchNoteSummary(), beforeNotes,
                "CC10 insertion Escape preserves selected note identities")
        compare(session.canUndo, beforeUndo, "CC10 insertion Escape preserves history availability")
        tryCompare(plot, "activeFocus", true, 3000,
                   "CC10 insertion Escape returns automation plot focus")
        keyClick(Qt.Key_S)
        tryCompare(track, "soloChecked", !soloBefore, 3000,
                   "resumed automation S reaches the window Solo command")
        compare(soloActivatedSpy.count, 1, "resumed window Solo activates once")
        keyClick(Qt.Key_S)
        tryCompare(track, "soloChecked", soloBefore, 3000,
                   "second resumed automation S reverses the Solo toggle")
        compare(soloActivatedSpy.count, 2, "second resumed window Solo activates exactly once more")
    }

    function test_eStandaloneInsertTimeOpensMountedPrompt() {
        var firstId = openTwoSongShell()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var menu = surface.rulerMenu
        var timeMenu = findChild(shell, "shellTimeMenu")
        var insert = findChild(timeMenu, "shellAction_edit.insert_time")
        verify(insert && menu, "the selected song exposes the window Insert Time command")
        compare(findChild(shell, "shellAction_edit.delete_time").enabled, false,
                "an open song without a time selection cannot delete a selected range")
        var before = grid.appliedRevisionText
        var notesBefore = grid.fetchNoteSummary()
        var cursor = grid.editCursorTick
        var roll = findChild(surface, "swiftRollInput")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_I, Qt.ControlModifier | Qt.ShiftModifier)
        tryCompare(menu, "insertTimePromptOpen", true, 3000,
                   "the window Insert Time shortcut opens the mounted prompt without a range")
        compare(grid.appliedRevisionText, before,
                "opening Insert Time does not edit the selected song")
        var bars = null
        var beats = null
        var fractions = null
        tryVerify(function() {
            bars = findChild(surface, "insertTimeBars")
            beats = findChild(surface, "insertTimeBeats")
            fractions = findChild(surface, "insertTimeBeatFractions")
            return !!findChild(surface, "insertTimePrompt") && bars && beats && fractions
        }, 3000, "the selected editor draws the existing three-field Insert Time form")
        compare(bars.text, "1", "Insert Time starts with one displayed bar")
        compare(beats.text, "0", "Insert Time starts with zero displayed beats")
        compare(fractions.text, "0", "Insert Time starts with zero displayed fractions")
        tryCompare(bars, "activeFocus", true, 3000)
        keyClick(Qt.Key_0)
        compare(bars.text, "0", "Cancel form accepts typed Bars input")
        keyClick(Qt.Key_Tab)
        tryCompare(beats, "activeFocus", true, 3000,
                   "Cancel form Tab moves to Beats")
        keyClick(Qt.Key_Backspace)
        keyClick(Qt.Key_2)
        compare(beats.text, "2", "Cancel form accepts typed Beats input")
        mouseClick(findChild(surface, "insertTimeCancel"))
        tryCompare(menu, "insertTimePromptOpen", false, 3000,
                   "Cancel closes the mounted Insert Time form")
        tryVerify(function() { return findChild(surface, "insertTimePrompt") === null },
                  3000, "Cancel unmounts the old prompt before another command")
        compare(grid.appliedRevisionText, before,
                "Cancel leaves the selected document unchanged")
        var editMenu = findChild(shell, "shellEditMenu")
        editMenu.open()
        timeMenu.open()
        tryCompare(insert, "enabled", true, 3000)
        mouseClick(insert, insert.width / 2, insert.height / 2)
        tryCompare(menu, "insertTimePromptOpen", true, 3000,
                   "the actual Time menu row opens the same mounted prompt")
        tryVerify(function() {
            return findChild(surface, "insertTimePrompt") !== null
                && findChild(surface, "insertTimeBars") !== null
        }, 3000, "the menu-opened form remounts for editing")
        bars = findChild(surface, "insertTimeBars")
        beats = findChild(surface, "insertTimeBeats")
        verify(bars && beats, "the menu-opened form has editable numeric fields")
        tryCompare(bars, "activeFocus", true, 3000)
        keyClick(Qt.Key_0)
        compare(bars.text, "0", "typing replaces the selected Bars value")
        verify(menu.insertTimePromptMaximumBeats >= 2,
               "the mounted song admits a two-beat input")
        keyClick(Qt.Key_Tab)
        tryCompare(beats, "activeFocus", true, 3000,
                   "Tab moves editing from Bars to Beats")
        keyClick(Qt.Key_Backspace)
        keyClick(Qt.Key_2)
        compare(beats.text, "2", "typing edits the actual Beats input")
        keyClick(Qt.Key_Return)
        tryCompare(menu, "insertTimePromptOpen", false, 3000,
                   "Return accepts and closes the edited form")
        tryVerify(function() { return grid.appliedRevisionText !== before }, 3000,
                  "the accepted nonzero form changes the selected song")
        compare(grid.editCursorTick, cursor,
                "accepting a cursor insertion does not move the edit cursor")
        var shifted = JSON.parse(grid.fetchNoteSummary())
        var original = JSON.parse(notesBefore)
        verify(original.some(function(note, index) {
            return note.tick >= cursor && shifted[index].tick > note.tick
        }), "the accepted form shifts drawn active-song notes")
        var tabs = shell.shellPresenter.session.songTabs
        var secondId = tabs.selectedId
        var firstButton = findChild(shell.sceneLoader.item, "songTabSelect_" + firstId)
        mouseClick(firstButton, firstButton.width / 3, firstButton.height / 2)
        tryCompare(tabs, "selectedId", firstId)
        var otherNotes = selectedSurface().gridModel.fetchNoteSummary()
        var secondButton = findChild(shell.sceneLoader.item, "songTabSelect_" + secondId)
        mouseClick(secondButton, secondButton.width / 3, secondButton.height / 2)
        tryCompare(tabs, "selectedId", secondId)
        mouseClick(firstButton, firstButton.width / 3, firstButton.height / 2)
        tryCompare(tabs, "selectedId", firstId)
        compare(selectedSurface().gridModel.fetchNoteSummary(), otherNotes,
                "insertion leaves the inactive tab unchanged")
    }

    function test_eStandaloneInsertTimeZeroClickClosesWithoutEdit() {
        openTwoSongShell()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var menu = surface.rulerMenu
        var before = grid.appliedRevisionText
        var notesBefore = grid.fetchNoteSummary()
        var editMenu = findChild(shell, "shellEditMenu")
        var timeMenu = findChild(shell, "shellTimeMenu")
        var insert = findChild(timeMenu, "shellAction_edit.insert_time")
        editMenu.open()
        timeMenu.open()
        mouseClick(insert, insert.width / 2, insert.height / 2)
        tryCompare(menu, "insertTimePromptOpen", true, 3000,
                   "the mounted zero-span form opens through the Time menu")
        var bars = null
        tryVerify(function() {
            bars = findChild(surface, "insertTimeBars")
            return bars !== null && !!findChild(surface, "insertTimeAccept")
        }, 3000, "the mounted zero-span form exposes Bars and OK")
        tryCompare(bars, "activeFocus", true, 3000)
        keyClick(Qt.Key_0)
        compare(bars.text, "0", "the zero-span form accepts typed zero Bars")
        mouseClick(findChild(surface, "insertTimeAccept"))
        tryCompare(menu, "insertTimePromptOpen", false, 3000,
                   "clicking OK closes the accepted zero-span form")
        compare(grid.appliedRevisionText, before,
                "a zero-span OK click preserves the selected document revision")
        compare(grid.fetchNoteSummary(), notesBefore,
                "a zero-span OK click preserves the selected document notes")
    }

    function test_eTimeAndTracksMenuContainment() {
        var timeIds = ["edit.insert_time", "edit.delete_time", "roll.duplicate_time",
                       "edit.clear_time_selection", "edit.edit_time_signature",
                       "edit.remove_time_signature"]
        var trackIds = ["roll.mute_tracks", "roll.solo_tracks"]
        var firstId = openTwoSongShell(function() {
            var noSongTime = findChild(shell, "shellTimeMenu")
            var noSongTracks = findChild(shell, "shellTracksMenu")
            verify(noSongTime && noSongTracks, "both Edit submenus exist before any song")
            for (var index = 0; index < timeIds.length; ++index) {
                var action = findChild(noSongTime, "shellAction_" + timeIds[index])
                verify(action, "Time has " + timeIds[index])
                compare(action.enabled, false, "no song disables " + timeIds[index])
            }
            for (var trackIndex = 0; trackIndex < trackIds.length; ++trackIndex) {
                var trackAction = findChild(noSongTracks,
                                            "shellAction_" + trackIds[trackIndex])
                verify(trackAction, "Tracks has " + trackIds[trackIndex])
                compare(trackAction.enabled, false, "no song disables " + trackIds[trackIndex])
            }
        })
        var editMenu = findChild(shell, "shellEditMenu")
        var timeMenu = findChild(shell, "shellTimeMenu")
        var tracksMenu = findChild(shell, "shellTracksMenu")
        verify(editMenu && timeMenu && tracksMenu, "the active shell exposes Edit submenus")
        var editIds = [
            "edit.undo", "edit.redo", "roll.copy", "roll.cut", "roll.paste",
            "roll.delete", "roll.select_all", "songs.find", "roll.transpose_up",
            "roll.transpose_down", "roll.transpose_up_octave",
            "roll.transpose_down_octave", "roll.nudge_left", "roll.nudge_right",
            "automation.pencil_mode", "roll.split", "roll.join",
            "roll.pitch_bend", "edit.set_velocity", "edit.set_loop_start",
            "edit.set_loop_end", "edit.loop_from_selection", "edit.remove_loop",
            "eventlist.move_up", "eventlist.move_down", "edit.preferences",
            "edit.song_settings", "edit.engine_settings"
        ]
        for (var timeIndex = 0; timeIndex < timeIds.length; ++timeIndex)
            tryVerify(function() {
                return findChild(timeMenu, "shellAction_" + timeIds[timeIndex]) !== null
            }, 3000, "Time mounts " + timeIds[timeIndex])
        for (var tracksIndex = 0; tracksIndex < trackIds.length; ++tracksIndex)
            tryVerify(function() {
                return findChild(tracksMenu, "shellAction_" + trackIds[tracksIndex]) !== null
            }, 3000, "Tracks mounts " + trackIds[tracksIndex])
        for (var editIndex = 0; editIndex < editIds.length; ++editIndex)
            tryVerify(function() {
                return findChild(editMenu, "shellAction_" + editIds[editIndex]) !== null
            }, 3000, "Edit mounts " + editIds[editIndex])
        editMenu.open()
        compare(findChild(timeMenu, "shellAction_edit.insert_time").enabled, true,
                "an open song offers standalone Insert Time")
        compare(findChild(timeMenu, "shellAction_edit.delete_time").enabled, false,
                "an open song without a time selection cannot delete a selected range")
        compare(findChild(tracksMenu, "shellAction_roll.solo_tracks").enabled, true,
                "the active song offers Solo")
        var firstButton = findChild(shell.sceneLoader.item, "songTabSelect_" + firstId)
        verify(firstButton, "the first song tab can retarget the Edit menu")
        editMenu.close()
        mouseClick(firstButton, firstButton.width / 3, firstButton.height / 2)
        tryCompare(shell.shellPresenter.session.songTabs, "selectedId", firstId)
        editMenu.open()
        compare(findChild(tracksMenu, "shellAction_roll.solo_tracks").enabled, true,
                "Solo rebinds to the newly active song")
        editMenu.close()
    }
}
