import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
    function test_numericHistoryDoesNotUndoSong() {
        openTwoSongShell()
        const session = shell.shellPresenter.session
        const surface = selectedSurface()
        const roll = findChild(surface, "swiftRollInput")
        selectDrawnVelocityNote(surface)
        const originalNotes = surface.gridModel.fetchNoteSummary()
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Up)
        tryCompare(session, "canUndo", true, 3000)
        const editedNotes = surface.gridModel.fetchNoteSummary()
        verify(editedNotes !== originalNotes, "transpose creates document history")

        const field = findChild(shell, "transportMasterVolumeInput")
        verify(field, "persistent master-volume field is mounted")
        field.text = "10"
        field.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(field, "activeFocus", true, 3000)
        keyClick(Qt.Key_End)
        keyClick(Qt.Key_1)
        compare(field.text, "101")
        keySequence(StandardKey.Undo)
        compare(field.text, "10", "Undo changes the focused draft")
        compare(surface.gridModel.fetchNoteSummary(), editedNotes, "draft Undo preserves the song")
        compare(session.canUndo, true, "document Undo remains available")
        keySequence(StandardKey.Redo)
        compare(field.text, "101", "platform Redo restores the draft")
        compare(surface.gridModel.fetchNoteSummary(), editedNotes, "draft Redo preserves the song")

        const copyShortcut = windowShortcut("shellShortcut_roll.copy")
        verify(copyShortcut, "the production window Copy shortcut is mounted")
        copyActivatedSpy.target = copyShortcut
        copyActivatedSpy.clear()
        keySequence(StandardKey.SelectAll)
        compare(field.selectedText, "101")
        keySequence(StandardKey.Copy)
        keySequence(StandardKey.Cut)
        compare(field.text, "")
        keySequence(StandardKey.Paste)
        compare(field.text, "101", "clipboard commands stay in the numeric draft")
        compare(copyActivatedSpy.count, 0, "numeric Copy never copies the selected note")
        compare(surface.gridModel.fetchNoteSummary(), editedNotes)
        keyClick(Qt.Key_Home)
        keyClick(Qt.Key_Right, Qt.ShiftModifier)
        compare(field.selectedText, "1", "Home moves the numeric caret")
        const playhead = session.playheadPresenter()
        compare(playhead.playing, false)
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000, "numeric text focus yields Space to transport")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000)

        field.text = "100"
        const scrollbar = findChild(surface, "timelineRollScrollBar")
        verify(scrollbar && scrollbar.scrollable, "timeline exposes keyboard scrolling")
        scrollbar.forceActiveFocus(Qt.TabFocusReason)
        keyClick(Qt.Key_End)
        tryCompare(scrollbar, "value", scrollbar.maximum, 3000)
        keyClick(Qt.Key_Home)
        tryCompare(scrollbar, "value", scrollbar.minimum, 3000,
                   "scrollbar Home survives the window transport binding")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keySequence(StandardKey.Undo)
        tryCompare(session, "documentDirty", false, 3000)
        compare(surface.gridModel.fetchNoteSummary(), originalNotes,
                "leaving the numeric field restores document Undo")
        keySequence(StandardKey.Redo)
        tryVerify(function() { return surface.gridModel.fetchNoteSummary() === editedNotes }, 3000)
        keySequence(StandardKey.Undo)
        tryCompare(session, "documentDirty", false, 3000)
    }

    function test_cWindowShortcutsAndNumericOwnership() {
        var firstId = openTwoSongShell()
        var session = shell.shellPresenter.session
        var tabs = session.songTabs
        var secondId = tabs.selectedId
        var firstButton = findChild(shell.sceneLoader.item, "songTabSelect_" + firstId)
        var secondButton = findChild(shell.sceneLoader.item, "songTabSelect_" + secondId)
        verify(firstButton && secondButton, "the two original tab controls are drawn")
        var readyFirst = findChild(shell.sceneLoader.item, "songTab_" + firstId)
        var readySecond = findChild(shell.sceneLoader.item, "songTab_" + secondId)
        verify(readyFirst && readySecond && readyFirst !== readySecond,
               "both real songs have distinct ready pages")
        var startingRoll = findChild(readySecond, "swiftRollInput")
        verify(startingRoll, "the newly opened song exposes its real roll input")
        mouseClick(startingRoll, startingRoll.width - 2, startingRoll.height - 2)
        tryCompare(startingRoll, "activeFocus", true, 3000,
                   "entering the new song gives its roll keyboard ownership")
        mouseClick(firstButton, firstButton.width / 3, firstButton.height / 2)
        tryCompare(tabs, "selectedId", firstId, 3000,
                   "a real first-tab click retargets the selected workspace")
        tryVerify(function() { return focusBelongsTo(readyFirst) }, 3000,
                  "switching from a focused roll targets the first ready editor")
        mouseClick(secondButton, secondButton.width / 3, secondButton.height / 2)
        tryCompare(tabs, "selectedId", secondId, 3000,
                   "a real second-tab click restores Littleroot's workspace")
        tryVerify(function() { return focusBelongsTo(readySecond) }, 3000,
                  "switching back targets the second ready editor")
        compare(readyFirst.visible, false, "the unselected ready page does not receive input")
        compare(readySecond.visible, true, "the selected ready page is displayed")

        verify(shell.shellPresenter.actionSequences("roll.copy").length > 0,
               "native Copy is registered as a window shortcut")
        compare(shell.shellPresenter.actionSequences("roll.solo_tracks")[0], "S")
        compare(shell.shellPresenter.actionSequences("transport.play_pause")[0], "Space")

        var surface = selectedSurface()
        verify(surface && surface.visible, "the selected production EditorSurface is visible")
        var headers = findChild(surface, "timelineTrackHeaderRows")
        verify(headers && headers.count > 0, "the original track header delegates are mounted")
        var firstTrack = headers.itemAt(surface.gridModel.trackIndex)
        verify(firstTrack && !firstTrack.isAddTrack, "the selected track header is available")
        compare(firstTrack.soloChecked, false)
        var inactiveSummary = findChild(readyFirst, "swiftRollOverlay").gridModel.fetchNoteSummary()
        var inactiveMix = findChild(findChild(readyFirst, "swiftRollOverlay"),
                                    "timelineTrackHeaderRows").itemAt(surface.gridModel.trackIndex)
        verify(inactiveMix, "the inactive track header remains mounted")
        var inactiveSoloBefore = inactiveMix.soloChecked
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the real roll owns raw editor keys")
        selectDrawnVelocityNote(surface)
        var editMenu = findChild(shell.menuBar, "shellEditMenu")
        verify(editMenu, "the production Edit menu exists")
        var menuCopy = findChild(editMenu, "shellAction_roll.copy")
        var menuSolo = findChild(editMenu, "shellAction_roll.solo_tracks")
        verify(menuCopy && menuSolo, "Copy and Solo are real Edit-menu actions")
        var copyShortcut = windowShortcut("shellShortcut_roll.copy")
        var soloShortcut = windowShortcut("shellShortcut_roll.solo_tracks")
        verify(copyShortcut && soloShortcut, "the real window shortcuts are mounted")
        copyActivatedSpy.target = copyShortcut
        soloActivatedSpy.target = soloShortcut
        copyActivatedSpy.clear()
        soloActivatedSpy.clear()
        editMenu.open()
        tryCompare(editMenu, "visible", true, 3000)
        compare(menuCopy.enabled, true, "Copy is enabled by the selected note")
        compare(menuSolo.enabled, true, "Solo is enabled for the selected track")
        editMenu.close()
        compare(shell.shellPresenter.actionEnabled("roll.copy"), true)
        var noteSummaryBeforeCopy = surface.gridModel.fetchNoteSummary()
        var beforeCopy = JSON.parse(surface.gridModel.fetchNoteSummary())
        var copied = beforeCopy.filter(function(note) { return note.selected })
        compare(copied.length, 1, "the real node click selected one note")
        var drawerToggle = findChild(surface, "drawerToggle_velocity")
        verify(drawerToggle && drawerToggle.visible, "the mounted drawer has a real chrome toggle")
        shell.shellPresenter.activate("view.velocity_drawer")
        tryCompare(surface.drawerPresenter.section(bootstrap.velocitySectionKind()),
                   "visible", false, 3000, "Copy runs with every drawer section hidden")
        compare(session.documentDirty, false, "Copy starts from a clean song")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000,
                   "the Edit menu returned keyboard focus to the roll")
        keySequence(StandardKey.Copy)
        compare(copyActivatedSpy.count, 1, "native Copy activates the window shortcut once")
        var clip = JSON.parse(bootstrap.copiedClipSummary())
        compare(clip.length, 3, "the native clipboard carries a decodable song clip")
        compare(clip[0], 1, "the copied clip contains one track")
        compare(clip[1], 1, "the copied track contains one selected note")
        compare(clip[2], copied[0].pitch, "the copied note retains its original key")
        compare(session.documentDirty, false, "the native window Copy never edits the song")
        compare(surface.gridModel.fetchNoteSummary(), noteSummaryBeforeCopy,
                "Copy preserves the active song's selected note bytes")
        compare(findChild(readyFirst, "swiftRollOverlay").gridModel.fetchNoteSummary(), inactiveSummary,
                "Copy never changes the inactive ready song")
        compare(firstTrack.soloChecked, false, "Copy never changes the selected track mix")
        var ruler = findChild(surface, "timelineRulerInput")
        verify(ruler && ruler.width > 80, "the mounted ruler receives time-range input")
        mousePress(ruler, ruler.width * 0.25, ruler.height / 2, Qt.LeftButton)
        mouseMove(ruler, ruler.width * 0.65, ruler.height / 2, -1, Qt.LeftButton)
        mouseRelease(ruler, ruler.width * 0.65, ruler.height / 2, Qt.LeftButton)
        tryVerify(function() { return paintedTimeRange(surface, roll) !== null }, 3000,
                  "ruler input paints the selected time range")
        var copyCountBeforeRange = copyActivatedSpy.count
        keySequence(StandardKey.Copy)
        compare(copyActivatedSpy.count, copyCountBeforeRange + 1,
                "time-range Copy activates the same window shortcut once")
        compare(session.documentDirty, false, "time-range Copy never dirties the active song")
        compare(findChild(readyFirst, "swiftRollOverlay").gridModel.fetchNoteSummary(), inactiveSummary,
                "time-range Copy leaves the inactive song untouched")

        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Escape)
        tryCompare(session.velocityPage(), "selectedCount", 0, 3000,
                   "the native text probe starts with no musical selection")
        var search = findChild(shell, "songListSearch")
        verify(search, "the production song-list search is mounted")
        search.text = "copy probe"
        search.selectAll()
        search.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(search, "activeFocus", true, 3000)
        compare(search.selectedText, "copy probe", "the production editor selects the complete text")
        verify(bootstrap.clearClipboardProbe(), "the old song clip is cleared")
        compare(search.activeFocus, true,
                "the production song search owns text Copy instead of the window")
        var copyCountBeforeText = copyActivatedSpy.count
        keySequence(StandardKey.Copy)
        search.clear()
        keySequence(StandardKey.Paste)
        compare(search.text, "copy probe",
                "native text Copy and Paste restore the exact production search text")
        compare(copyActivatedSpy.count, copyCountBeforeText,
                "text Copy never activates the window Copy shortcut")

        drawerToggle.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(drawerToggle, "activeFocus", true, 3000,
                   "production drawer chrome retains intentional non-text focus")
        keyClick(Qt.Key_S)
        tryCompare(firstTrack, "soloChecked", true, 3000)
        compare(soloActivatedSpy.count, 1, "first non-text S activates Solo once")
        compare(inactiveMix.soloChecked, inactiveSoloBefore,
                "chrome Solo leaves the inactive song mix untouched")
        keyClick(Qt.Key_S)
        tryCompare(firstTrack, "soloChecked", false, 3000)
        compare(soloActivatedSpy.count, 2, "second non-text S activates Solo twice total")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_S)
        tryCompare(firstTrack, "soloChecked", true, 3000)
        compare(soloActivatedSpy.count, 3, "first roll S activates Solo three times total")
        keyClick(Qt.Key_S)
        tryCompare(firstTrack, "soloChecked", false, 3000)
        compare(soloActivatedSpy.count, 4, "second roll S activates Solo four times total")
        compare(inactiveMix.soloChecked, inactiveSoloBefore,
                "roll Solo leaves the inactive song mix untouched")
        search.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(search, "activeFocus", true, 3000)
        keyClick(Qt.Key_S)
        compare(firstTrack.soloChecked, false, "text-field S never changes Solo")
        compare(soloActivatedSpy.count, 4, "text-field S never activates Solo")
        shell.shellPresenter.activate("view.velocity_drawer")
        tryCompare(surface.drawerPresenter.section(bootstrap.velocitySectionKind()),
                   "visible", true, 3000, "the velocity page returns for the numeric prompt")
        var notePoint = mountedNotePoint(surface, roll, copied[0].id)
        verify(notePoint, "the original copied note remains drawn after the time-range Copy")
        mouseClick(roll, notePoint.x, notePoint.y)
        tryVerify(function() { return paintedTimeRange(surface, roll) === null }, 3000,
                  "entering the roll note replaces the ruler time-range selection")
        selectDrawnVelocityNote(surface)

        compare(shell.active, true,
                "the production Qt window is active before resumed numeric commands")
        var noteMenu = findChild(shell, "shellGridContextMenu")
        verify(noteMenu && !noteMenu.visible, "the real note menu starts closed")
        var selectedVelocityNote = JSON.parse(surface.gridModel.fetchNoteSummary()).find(function(note) {
            return note.selected && !note.ghost
        })
        verify(selectedVelocityNote, "the velocity menu targets a selected roll note")
        notePoint = mountedNotePoint(surface, roll, selectedVelocityNote.id)
        verify(notePoint, "the selected note remains visible for the right-click")
        mouseClick(roll, notePoint.x, notePoint.y, Qt.RightButton)
        tryCompare(noteMenu, "visible", true, 3000,
                   "right-click on the selected visible note opens its real menu")
        var velocityRow = findChild(noteMenu, "shellContextAction_edit.set_velocity")
        verify(velocityRow && velocityRow.visible && velocityRow.enabled,
               "the real note menu renders an enabled Set Velocity row")
        mouseClick(velocityRow, velocityRow.width / 2, velocityRow.height / 2)
        tryCompare(noteMenu, "visible", false, 3000,
                   "clicking Set Velocity closes the production note menu")
        tryCompare(session.velocityPage(), "promptOpen", true, 3000,
                   "the clicked Set Velocity row opens the production prompt")
        var velocityNoteBeforeKeys = surface.gridModel.fetchNoteSummary()
        var velocityRevisionBeforeKeys = surface.gridModel.appliedRevisionText
        var field = null
        tryVerify(function() {
            field = findChild(surface, "noteVelocityInput")
            return field !== null
        }, 3000)
        verify(field, "the original numeric prompt has a text field")
        tryCompare(field, "activeFocus", true, 3000)
        field.selectAll()
        keyClick(Qt.Key_1)
        keyClick(Qt.Key_2)
        compare(field.text, "12", "digits stay in the focused numeric editor")
        var windowCopyBeforePrompt = copyActivatedSpy.count
        field.selectAll()
        keySequence(StandardKey.Copy)
        field.selectAll()
        keyClick(Qt.Key_3)
        field.selectAll()
        keySequence(StandardKey.Paste)
        compare(field.text, "12", "native Copy and Paste stay with the text editor")
        compare(field.selectedText, "", "numeric Paste replaces the selected draft")
        compare(copyActivatedSpy.count, windowCopyBeforePrompt,
                "prompt Copy/Paste never fire the window Copy action")
        compare(field.activeFocus, true, "local Copy/Paste retains numeric focus")
        var velocityBeforeSolo = field.text
        keyClick(Qt.Key_S)
        compare(field.text, velocityBeforeSolo, "numeric validator rejects Solo S without changing text")
        compare(firstTrack.soloChecked, false, "S in a numeric editor never fires Solo")
        compare(soloActivatedSpy.count, 4,
                "numeric S never activates the window Solo shortcut")
        compare(session.velocityPage().promptOpen, true,
                "numeric S leaves the value prompt open")
        keyClick(Qt.Key_Up)
        keyClick(Qt.Key_Down)
        compare(field.activeFocus, true, "prompt arrows keep focus in the numeric editor")
        compare(session.velocityPage().promptOpen, true)
        tryCompare(session.velocityPage(), "selectedCount", 1, 3000,
                   "prompt arrows keep the musical selection")
        compare(session.documentDirty, false, "prompt arrows never edit the song")
        compare(surface.gridModel.fetchNoteSummary(), velocityNoteBeforeKeys,
                "velocity arrows retain the selected NoteID and note contents")
        compare(surface.gridModel.appliedRevisionText, velocityRevisionBeforeKeys,
                "velocity numeric keys never commit a song revision")
        compare(soloActivatedSpy.count, 4,
                "numeric arrow keys never activate Solo")
        var promptTextAfterArrows = field.text
        var playhead = session.playheadPresenter()
        compare(playhead.playing, false)
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000,
                   "window Space owns transport even with numeric text focus")
        compare(field.text, promptTextAfterArrows, "transport Space never modifies numeric text")
        compare(field.activeFocus, true)
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000,
                   "the second window Space reverses one transport activation")
        compare(session.velocityPage().promptOpen, true)
        keyClick(Qt.Key_Escape)
        tryCompare(session.velocityPage(), "promptOpen", false, 3000)
        compare(surface.gridModel.fetchNoteSummary(), velocityNoteBeforeKeys,
                "velocity prompt cancellation preserves the selected note")
        compare(surface.gridModel.appliedRevisionText, velocityRevisionBeforeKeys,
                "velocity prompt cancellation preserves the document revision")
        tryCompare(roll, "activeFocus", true, 3000,
                   "Escape returns focus to the real roll after the velocity prompt")
        compare(shell.active, true, "the production Qt window is active for resumed roll Solo")
        keyClick(Qt.Key_S)
        tryCompare(firstTrack, "soloChecked", true, 3000,
                   "the first resumed roll S turns on the intended track Solo")
        compare(soloActivatedSpy.count, 5,
                "the first resumed S activates the window Solo exactly once")
        keyClick(Qt.Key_S)
        tryCompare(firstTrack, "soloChecked", false, 3000,
                   "the second resumed roll S turns off the intended track Solo")
        compare(soloActivatedSpy.count, 6,
                "the second resumed S activates the window Solo exactly once")
        var drawer = findChild(surface, "editorDrawer")
        verify(drawer, "the production drawer is mounted")
        var velocityToggle = findChild(drawer, "drawerToggle_velocity")
        verify(velocityToggle && velocityToggle.visible, "the velocity toggle is drawn")
        velocityToggle.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(velocityToggle, "activeFocus", true, 3000,
                   "drawer chrome takes keyboard focus")
        var toggleSectionVisible = surface.drawerPresenter.section(
                    bootstrap.velocitySectionKind()).visible
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000,
                   "bare Space on focused drawer chrome owns transport")
        compare(surface.drawerPresenter.section(
                    bootstrap.velocitySectionKind()).visible, toggleSectionVisible,
                "chrome Space never toggles the focused section")
        compare(session.documentDirty, false, "chrome Space never edits the song")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000,
                   "the second chrome Space stops transport")
        compare(session.documentDirty, false,
                "local numeric keys leave the active tab clean before explicit close")
        shell.close()
        verify(waitForNative(function() {
            return shell.shellPresenter.closeReady
        }, 5000), "the clean key journey closes without a dirty-tab gate")
        compare(session.songTabs.pendingCloseId, -1,
                "clean numeric editing leaves no pending dirty-tab close")
    }

    function test_bUnloadedEditCommandsStayDisabled() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the unloaded production ShellWindow mounts")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000,
                   "the unloaded shell window becomes active")
        waitForShellScene()
        tryCompare(shell.menuBar, "visible", true, 3000,
                   "the unloaded shell mounts its visible menu controls")
        var session = shell.shellPresenter.session
        compare(session.songOpen, false,
                "the unloaded shell opens no song workspace")
        var editMenu = findChild(shell.menuBar, "shellEditMenu")
        var timeMenu = editMenu ? findChild(editMenu, "shellTimeMenu") : null
        verify(editMenu && timeMenu
               && findChild(editMenu, "shellAction_roll.copy")
               && findChild(editMenu, "shellAction_roll.solo_tracks")
               && findChild(timeMenu, "shellAction_edit.insert_time")
               && findChild(timeMenu, "shellAction_edit.delete_time"),
               "the unloaded shell publishes its edit command set through the Edit menu")
        verify(session.songTabs.selectedPage === null,
               "the unloaded shell binds no song page target")
        compare(shell.shellPresenter.actionEnabled("roll.copy"), false,
                "the unloaded shell disables Copy with no workspace")
        compare(shell.shellPresenter.actionEnabled("roll.solo_tracks"), false,
                "the unloaded shell disables Solo with no workspace")
        compare(shell.shellPresenter.actionEnabled("edit.insert_time"), false,
                "the unloaded shell disables Insert Time with no workspace")
        compare(shell.shellPresenter.actionEnabled("edit.delete_time"), false,
                "the unloaded shell disables Delete Time with no workspace")
    }

    function test_fPencilLatchTextAndSpaceOwnership() {
        openTwoSongShell()
        var surface = selectedSurface()
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the roll receives the pencil key")
        var grid = surface.gridModel
        var playhead = shell.shellPresenter.session.playheadPresenter()
        var automation = shell.shellPresenter.session.automationPage()
        compare(grid.pencilMode, false)
        compare(automation.isPencilMode, false)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyPress(Qt.Key_B)
        tryCompare(grid, "pencilMode", true, 3000)
        tryCompare(automation, "isPencilMode", true, 3000)
        wait(520)
        compare(grid.pencilMode, true, "the pencil latch survives the B hold without release")
        compare(automation.isPencilMode, true, "holding B preserves automation pencil mode")
        keyRelease(Qt.Key_B)
        compare(grid.pencilMode, true, "releasing B keeps the pencil latched")
        compare(automation.isPencilMode, true, "releasing B keeps automation pencil latched")
        var beforeSpace = grid.fetchNoteSummary()
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000)
        compare(grid.pencilMode, true, "roll Space never unlatches the pencil")
        compare(automation.isPencilMode, true, "roll Space leaves automation pencil armed")
        compare(grid.fetchNoteSummary(), beforeSpace, "roll Space never changes selected notes")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000)
        keyPress(Qt.Key_B)
        tryCompare(grid, "pencilMode", false, 3000)
        tryCompare(automation, "isPencilMode", false, 3000)
        keyRelease(Qt.Key_B)
        compare(grid.pencilMode, false, "releasing the second B preserves the off state")
        compare(automation.isPencilMode, false,
                "releasing the second B preserves the automation off state")

        var textProbe = textProbeComponent.createObject(shell.contentItem,
                                                        { x: 20, y: 20 })
        verify(textProbe, "the focused text probe belongs to the production window")
        textProbe.text = ""
        textProbe.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(textProbe, "activeFocus", true, 3000)
        keyClick(Qt.Key_B)
        compare(textProbe.text.toLowerCase(), "b", "text focus keeps its typed B")
        compare(grid.pencilMode, false, "text-field B never enables the pencil")
        compare(automation.isPencilMode, false,
                "text-field B never changes automation pencil mode")
        textProbe.destroy()

        selectDrawnVelocityNote(surface)
        shell.shellPresenter.session.performGridCommand(bootstrap.setVelocityCommand())
        tryCompare(shell.shellPresenter.session.velocityPage(), "promptOpen", true, 3000)
        var field = null
        tryVerify(function() {
            field = findChild(surface, "noteVelocityInput")
            return field !== null
        }, 3000)
        verify(field, "the numeric prompt exposes its real input")
        tryCompare(field, "activeFocus", true, 3000)
        var numericText = field.text
        keyClick(Qt.Key_B)
        compare(field.text, numericText, "numeric text rejects the nonnumeric B")
        compare(grid.pencilMode, false, "numeric B never reaches the pencil shortcut")
        compare(automation.isPencilMode, false,
                "numeric B never changes automation pencil mode")
        keyClick(Qt.Key_Escape)
        tryCompare(shell.shellPresenter.session.velocityPage(), "promptOpen", false, 3000)
    }
}
