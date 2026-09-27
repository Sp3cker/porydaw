import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellMenusSupport {

    function test_songMenuActionsDriveSessionState() {
        openShell()
        var bar = openSong()
        var presenter = shell.shellPresenter
        var session = presenter.session
        var tabs = session.songTabs
        var transport = session.transportBarPresenter()

        var closeTab = findChild(shell, "shellAction_file.close_tab")
        compare(closeTab.enabled, true, "the open tab enables Close Tab")

        // Drawer toggles follow section visibility. DrawerSectionKind values:
        // 0 automation, 1 velocity, 2 voice changes.
        verify(waitForNative(function() {
            var page = session.songTabs.selectedPage
            if (page === null)
                return false
            var attached = page.drawerPresenter()
            return attached.velocitySection.available && attached.automationSection.available
                && attached.voiceChangesSection.available
        }, 10000), "drawer pages attach to the open tab")
        var drawer = tabs.selectedPage.drawerPresenter()
        var sectionIds = ["view.automation_drawer", "view.velocity_drawer",
                          "view.voice_changes_drawer"]
        var sectionKinds = [0, 1, 2]
        var sectionStates = [drawer.automationSection, drawer.velocitySection,
                             drawer.voiceChangesSection]
        for (var sectionIndex = 0; sectionIndex < sectionIds.length; ++sectionIndex) {
            var sectionId = sectionIds[sectionIndex]
            var sectionKind = sectionKinds[sectionIndex]
            var sectionState = sectionStates[sectionIndex]
            var item = findChild(shell, "shellAction_" + sectionId)
            compare(item.enabled, true, sectionId + " is enabled with a tab selected")
            var before = sectionState.visible
            presenter.activate(sectionId)
            verify(waitForNative(function() { return sectionState.visible !== before }, 3000),
                   sectionId + " flips its drawer section")
            tryVerify(function() { return item.checked === !before }, 3000,
                      sectionId + " check follows the flip")
            // Toggling the drawer directly (its own toggle buttons call the
            // same presenter) also updates the menu check.
            drawer.toggleSection(sectionKind, false)
            verify(waitForNative(function() { return sectionState.visible === before }, 3000),
                   "the presenter toggle restores " + sectionId)
            tryVerify(function() { return item.checked === before }, 3000,
                      sectionId + " check follows the presenter toggle")
        }

        // Loop and Follow reflect and flip the transport presenter.
        var loop = findChild(shell, "shellAction_transport.loop")
        var follow = findChild(shell, "shellAction_transport.follow_playhead")
        compare(loop.enabled, true, "the open song enables Loop")
        compare(follow.enabled, true, "the open song enables Follow Playhead")
        compare(loop.checked, transport.loopEnabled, "Loop check mirrors the presenter")
        var loopBefore = transport.loopEnabled
        presenter.activate("transport.loop")
        compare(transport.loopEnabled, !loopBefore, "the menu toggle flips loop state")
        tryVerify(function() { return loop.checked === !loopBefore }, 3000,
                  "Loop check follows the flip")
        transport.setLoopEnabled(loopBefore)
        tryVerify(function() { return loop.checked === loopBefore }, 3000,
                  "Loop check follows the transport bar switch")
        var followBefore = transport.followPlayhead
        presenter.activate("transport.follow_playhead")
        compare(transport.followPlayhead, !followBefore, "the menu toggle flips follow state")
        tryVerify(function() { return follow.checked === !followBefore }, 3000,
                  "Follow check follows the flip")
        transport.setFollowPlayhead(followBefore)
        tryVerify(function() { return follow.checked === followBefore }, 3000,
                  "Follow check follows the transport bar switch")

        // Display modes flip session state and the menu checks.
        var colors = findChild(shell, "shellAction_view.velocity_colors")
        var names = findChild(shell, "shellAction_view.note_names")
        var colorsBefore = session.velocityColorMode
        presenter.activate("view.velocity_colors")
        compare(session.velocityColorMode, !colorsBefore, "the menu toggle flips velocity colours")
        tryVerify(function() { return colors.checked === !colorsBefore }, 3000,
                  "velocity colours check follows the flip")
        presenter.activate("view.velocity_colors")
        var namesBefore = session.noteNameMode
        presenter.activate("view.note_names")
        compare(session.noteNameMode, !namesBefore, "the menu toggle flips note names")
        tryVerify(function() { return names.checked === !namesBefore }, 3000,
                  "note names check follows the flip")
        presenter.activate("view.note_names")

        // Go to Start rewinds the real playhead after it advanced.
        var clock = findChild(bar, "transportTimeLabel")
        verify(clock !== null, "the mounted clock is readable")
        presenter.activate("transport.play")
        tryCompare(transport, "state", 3, 3000)
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return !clock.text.startsWith("0:00.0 / ")
        }, 5000), "playback advances the real playhead")
        presenter.activate("transport.go_to_start")
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return clock.text.startsWith("0:00.0 / ")
        }, 3000), "Go to Start rewinds the real playhead")
        presenter.activate("transport.stop")

        // About opens the dialog.
        var aboutItem = findChild(shell, "shellAction_help.about")
        var aboutDialog = findChild(shell, "shellAboutDialog")
        verify(aboutDialog !== null, "the About dialog is mounted")
        compare(aboutDialog.visible, false, "About starts hidden")
        aboutItem.triggered()
        tryVerify(function() { return aboutDialog.visible }, 3000, "About opens the dialog")
        const body = presenter.session.typographyFonts.body
        const aboutText = findChild(aboutDialog, "shellAboutBody")
        verify(aboutText !== null, "the mounted About dialog renders its body")
        compare(aboutDialog.font.family, body.family, "About resolves the body family")
        compare(aboutText.font.family, body.family, "About body resolves body family")
        compare(aboutText.font.pixelSize, body.pixelSize, "About body resolves body size")
        compare(aboutText.font.weight, body.weight, "About body keeps regular weight")
        aboutDialog.close()
        tryVerify(function() { return !aboutDialog.visible }, 3000, "About closes again")
    }

    function test_noteCommandsRouteThroughMenuAndKey() {
        openShell()
        openSong()
        var presenter = shell.shellPresenter
        var session = presenter.session
        var grid = session.gridPresenter()
        verify(grid !== null, "the roll model is reachable without scene timing")
        verify(waitForNative(function() { return editorPage() !== null }, 10000),
               "the editor page mounts")
        var page = editorPage()
        compare(presenter.actionEnabled("roll.pitch_bend"), false,
                "pitch bend needs a note selection")
        compare(presenter.actionEnabled("edit.set_velocity"), false,
                "set velocity needs a note selection")
        grid.setTrack(0)
        compare(presenter.routeEditorKey(Qt.Key_G, Qt.NoModifier, false), false,
                "G without a note selection is declined")
        presenter.activate("roll.select_all")
        verify(waitForNative(function() {
            return JSON.parse(grid.noteSummary).some(function(n) { return n.selected })
        }, 5000), "Select All selects notes through the production route")
        tryVerify(function() { return presenter.actionEnabled("roll.pitch_bend") }, 3000,
                  "the selection enables pitch bend")
        tryVerify(function() { return presenter.actionEnabled("edit.set_velocity") }, 3000,
                  "the selection enables set velocity")
        compare(presenter.actionEnabled("edit.loop_from_selection"), false,
                "loop from selection needs a time selection")
        var editor = session.pitchBendPresenter()
        var before = grid.appliedRevisionText
        compare(presenter.routeEditorKey(Qt.Key_G, Qt.NoModifier, false), true,
                "G routes to pitch bend with a note selected")
        tryCompare(editor, "isOpen", true)
        tryVerify(function() { return findChild(page, "pitchBendPopup") !== null }, 5000,
                  "the G route realizes the popup")
        compare(grid.appliedRevisionText, before, "opening edits nothing")
        editor.cancelAndClose()
        tryCompare(editor, "isOpen", false)
        verify(waitForNative(function() {
            return findChild(page, "swiftRollInput") !== null
        }, 10000), "the roll input mounts")
        var roll = findChild(page, "swiftRollInput")
        roll.forceActiveFocus()
        tryVerify(function() { return roll.activeFocus }, 3000, "the roll takes key focus")
        keyClick(Qt.Key_G)
        tryCompare(editor, "isOpen", true, 3000,
                   "delivered G opens pitch bend on the selected note")
        compare(grid.appliedRevisionText, before, "the delivered key edits nothing on open")
        editor.cancelAndClose()
        tryCompare(editor, "isOpen", false)
        var pitchItem = findChild(shell, "shellAction_roll.pitch_bend")
        verify(pitchItem !== null, "the Edit menu owns the pitch bend row")
        tryVerify(function() { return pitchItem.enabled }, 3000,
                  "the menu row follows the selection")
        pitchItem.triggered()
        tryCompare(editor, "isOpen", true)
        compare(grid.appliedRevisionText, before, "the menu route edits nothing on open")
        editor.cancelAndClose()
        tryCompare(editor, "isOpen", false)
        verify(JSON.parse(grid.noteSummary).some(function(n) { return n.selected }),
               "closing pitch bend preserves the velocity target")
        var velocityItem = findChild(shell, "shellAction_edit.set_velocity")
        verify(velocityItem !== null, "the Edit menu owns the set velocity row")
        tryVerify(function() { return velocityItem.enabled }, 3000,
                  "the selected note enables the velocity row")
        velocityItem.triggered()
        var velocityModel = session.velocityPage()
        tryVerify(function() { return velocityModel.promptOpen }, 3000,
                  "the menu opens the velocity prompt")
        tryVerify(function() { return findChild(page, "velocityPrompt") !== null }, 5000,
                  "the selected tab mounts its velocity prompt")
        var prompt = findChild(page, "velocityPrompt")
        tryVerify(function() { return prompt.opened && prompt.visible }, 3000,
                  "the mounted prompt opens visibly for the selected note")
        var selectedNotes = JSON.parse(grid.noteSummary).filter(function(n) { return n.selected })
        verify(selectedNotes.length > 0, "the prompt has selected notes to edit")
        var velocityValue = selectedNotes[0].velocity === 100 ? 99 : 100
        velocityModel.updatePromptDraft(String(velocityValue))
        velocityModel.acceptPrompt()
        verify(waitForNative(function() {
            var notes = JSON.parse(grid.noteSummary)
            return selectedNotes.every(function(target) {
                return notes.some(function(note) {
                    return note.id === target.id && note.velocity === velocityValue
                })
            })
        }, 5000), "accepting sets the selected note velocities")
        tryVerify(function() { return !velocityModel.promptOpen }, 3000,
                  "accepting closes the prompt")
    }

    function test_explicitSoloEditMenuStaysAvailableWithTextFocus() {
        openShell()
        openSong()
        var presenter = shell.shellPresenter
        verify(waitForNative(function() { return editorPage() !== null }, 10000),
               "the selected song tab mounts")
        var surface = findChild(editorPage(), "swiftRollOverlay")
        var soloItem = findChild(shell, "shellAction_roll.solo_tracks")
        verify(surface && soloItem, "the selected editor mounts the Edit Solo action")
        var headers = null
        tryVerify(function() {
            headers = findChild(surface, "timelineTrackHeaderRows")
            return headers !== null && headers.count > surface.gridModel.trackIndex
        }, 3000, "the selected track header is mounted")
        var header = headers.itemAt(surface.gridModel.trackIndex)
        verify(header && !header.isAddTrack, "the selected track can be soloed")
        compare(header.soloChecked, false, "the selected track starts unsoloed")
        var field = soloTextProbe.createObject(shell.contentItem)
        verify(field !== null, "the text field belongs to the active shell")
        field.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(field, "activeFocus", true, 3000)
        compare(presenter.actionEnabled("roll.solo_tracks"), true,
                "text focus does not disable the explicit window Solo action")
        compare(soloItem.enabled, true, "the Edit Solo row remains actionable under text focus")
        presenter.activate("roll.solo_tracks")
        tryCompare(header, "soloChecked", true, 3000,
                   "explicit Edit Solo activation still reaches the selected track")
        compare(field.activeFocus, true, "the Edit command does not steal text input focus")
        presenter.activate("roll.solo_tracks")
        tryCompare(header, "soloChecked", false, 3000,
                   "explicit Edit Solo restores the previous mix")
        field.destroy()
    }

    function test_eventMoveRoutesThroughMenuAndEventListKey() {
        openShell()
        openSong()
        var presenter = shell.shellPresenter
        var session = presenter.session
        verify(waitForNative(function() { return editorPage() !== null }, 5000),
               "the selected song tab mounts")
        var page = editorPage()
        var upItem = findChild(shell, "shellAction_eventlist.move_up")
        var downItem = findChild(shell, "shellAction_eventlist.move_down")
        var soloItem = findChild(shell, "shellAction_roll.solo_tracks")
        verify(upItem !== null && downItem !== null && soloItem !== null,
               "the Edit menu owns the event moves and Solo action")
        compare(presenter.actionEnabled("eventlist.move_up"), false,
                "the hidden event list disables move up")
        compare(presenter.actionEnabled("eventlist.move_down"), false,
                "the hidden event list disables move down")
        compare(upItem.enabled, false, "the hidden list keeps the Move Up menu row disabled")
        compare(downItem.enabled, false, "the hidden list keeps the Move Down menu row disabled")
        compare(presenter.actionEnabled("roll.solo_tracks"), true,
                "hiding the event list keeps the window Solo action enabled")
        compare(soloItem.enabled, true, "the hidden event list retains the Edit Solo row")
        presenter.activate("view.event_list")
        var events = session.eventListPresenter()
        tryVerify(function() { return events.visible && events.rowCount > 1 }, 3000,
                  "the event list presents the loaded song's rows")
        var moveRow = -1
        for (var row = 1; row < events.rowCount; ++row) {
            if (events.rowKind(row) === 0 && events.rowKind(row - 1) === 0
                && events.isLegalDrop(row, row - 1)
                && events.cellDisplay(row, 6) !== events.cellDisplay(row - 1, 6)) {
                moveRow = row
                break
            }
        }
        verify(moveRow > 0, "the fixture has distinguishable same-tick event neighbors")
        var earlierSummary = events.cellDisplay(moveRow - 1, 6)
        var movedSummary = events.cellDisplay(moveRow, 6)
        var rowCount = events.rowCount
        events.selectRow(moveRow, Qt.NoModifier)
        compare(events.currentRow, moveRow, "the menu targets the selected event row")
        compare(presenter.actionEnabled("eventlist.move_up"), true,
                "the selected raw event is eligible for Move Up")
        compare(presenter.actionEnabled("roll.solo_tracks"), true,
                "showing the event list does not steal the window Solo action")
        compare(soloItem.enabled, true, "the shown event list retains the Edit Solo row")
        tryVerify(function() { return upItem.enabled }, 3000,
                  "the selected event enables Move Up")
        upItem.triggered()
        compare(events.cellDisplay(moveRow - 1, 6), movedSummary,
                "the menu moves the selected event ahead of its same-tick neighbor")
        compare(events.cellDisplay(moveRow, 6), earlierSummary,
                "the menu leaves the displaced event in the next row")
        compare(events.rowCount, rowCount, "the menu reorder preserves event count")
        compare(events.currentRow, moveRow - 1, "the moved row remains selected")
        compare(presenter.routeEditorKey(Qt.Key_Up, Qt.AltModifier, false), false,
                "the timeline keeps Alt+Up local to the event list")
        var eventPage = findChild(page, "eventListPage")
        verify(eventPage !== null && eventPage.visible, "the event list is mounted")
        eventPage.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(eventPage, "activeFocus", true, 3000)
        keyClick(Qt.Key_Down, Qt.AltModifier)
        compare(events.cellDisplay(moveRow - 1, 6), earlierSummary,
                "Alt+Down returns the displaced event through the event-list key route")
        compare(events.cellDisplay(moveRow, 6), movedSummary,
                "the keyboard route restores the selected event to its original row")
        compare(events.rowCount, rowCount, "keyboard reorder preserves event count")
        presenter.activate("view.event_list")
        tryVerify(function() { return !events.visible }, 3000, "the event list hides again")
        compare(presenter.actionEnabled("eventlist.move_up"), false,
                "hiding the list disables move up again")
        compare(upItem.enabled, false, "the hidden list revokes the Move Up menu row")
        compare(downItem.enabled, false, "the hidden list revokes the Move Down menu row")
        compare(presenter.actionEnabled("roll.solo_tracks"), true,
                "closing the event list leaves the window Solo action available")
        compare(soloItem.enabled, true, "the closed event list retains the Edit Solo row")
    }

    function test_closeTabClosesTheCleanTab() {
        openShell()
        openSong()
        var tabs = shell.shellPresenter.session.songTabs
        var closeTab = findChild(shell, "shellAction_file.close_tab")
        verify(closeTab !== null && closeTab.enabled, "Close Tab targets the clean tab")
        closeTab.triggered()
        verify(waitForNative(function() { return tabs.tabCount === 0 }, 5000),
               "triggering Close Tab closes the clean tab")
        compare(shell.shellPresenter.session.songOpen, false, "no song remains open")
        tryVerify(function() { return !closeTab.enabled }, 3000,
                  "no tab disables Close Tab again")
    }

}
