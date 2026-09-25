import QtCore
import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

TestCase {
    id: testCase
    name: "ShellMenus"
    when: windowShown
    width: 1100
    height: 720
    visible: true

    property var shell: null
    property var settings: null

    ShellQmlBootstrap { id: bootstrap }

    Component { id: settingsComponent; Settings {} }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        settings = settingsComponent.createObject(testCase)
        verify(settings !== null, "genuine QtCore.Settings is available")
    }

    function cleanupTestCase() {
        if (settings) {
            settings.destroy()
            settings = null
            wait(0)
        }
        verify(bootstrap.clearSettings(), "removed only the private native settings")
    }

    function closeShell() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            var settled = false
            for (var step = 0; step < 12 && !settled; ++step) {
                var gate = waitForNative(function() {
                    return shell.shellPresenter.closeReady
                        || shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                }, 5000)
                if (!gate)
                    break
                if (shell.shellPresenter.closeReady) {
                    settled = true
                    break
                }
                shell.shellPresenter.session.songTabs.confirmDiscard()
                wait(50)
            }
            verify(shell.shellPresenter.closeReady,
                   "teardown waits for scene destruction and grid detach")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function cleanup() {
        closeShell()
    }

    function waitForNative(predicate, timeoutMs) {
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function openDiagnostics(session) {
        return " (projectOpen=" + session.projectOpen
            + "; songOpen=" + session.songOpen
            + "; lastSaveError=" + session.lastSaveError
            + "; status=" + shell.shellPresenter.statusText + ")"
    }

    function openShell() {
        // Every explicit-open test starts without a stale startup recipe.
        settings.setValue("lastProjectDir", "")
        settings.sync()
        settings.setValue("editorDrawer/velocityVisible", true)
        settings.setValue("editorDrawer/velocityHeight", 173)
        settings.setValue("editorDrawer/automationVisible", true)
        settings.setValue("editorDrawer/automationHeight", 200)
        settings.setValue("editorDrawer/voiceChangesVisible", true)
        settings.setValue("editorDrawer/voiceChangesHeight", 200)
        settings.setValue("editorDrawer/activePage", "velocity")
        settings.sync()
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
    }

    function openSong() {
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the fixture song loads" + openDiagnostics(session))
        verify(session.songOpen, "mus_route101 opens" + openDiagnostics(session))
        tryCompare(session.songTabs, "tabCount", 1)
        var transport = findChild(shell, "transportToolbar")
        verify(waitForNative(function() { return transport.presenter.state !== 0 }, 5000),
               "transport observes the loaded audio timeline")
        return transport
    }

    function editorPage() {
        var tabs = shell.shellPresenter.session.songTabs
        return findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
    }

    function checkMenuItem(menu, actionId, label) {
        var item = findChild(menu, "shellAction_" + actionId)
        verify(item !== null, "the menu owns " + actionId)
        compare(shell.shellPresenter.actionLabel(actionId), label,
                actionId + " keeps the keymap label")
        verify(item.text.indexOf(label) === 0,
                actionId + " shows its label, got: " + item.text)
        return item
    }

    function menuOrder(menu, actionIds) {
        var actual = []
        for (var index = 0; index < menu.count; ++index)
            actual.push(menu.itemAt(index).objectName)
        compare(JSON.stringify(actual),
                JSON.stringify(actionIds.map(function(id) { return "shellAction_" + id })),
                "the menu keeps the original order")
    }

    function test_menuItemsExistWithLabelsAndNoSongGates() {
        openShell()
        var fileMenu = findChild(shell, "shellFileMenu")
        var transportMenu = findChild(shell, "shellTransportMenu")
        var viewMenu = findChild(shell, "shellViewMenu")
        var helpMenu = findChild(shell, "shellHelpMenu")
        verify(fileMenu && transportMenu && viewMenu && helpMenu,
               "File, Transport, View and Help menus are mounted")
        compare(fileMenu.title, "&File")
        compare(transportMenu.title, "&Transport")
        compare(viewMenu.title, "&View")
        compare(helpMenu.title, "&Help")

        var closeTab = checkMenuItem(fileMenu, "file.close_tab", "Close Tab")
        compare(closeTab.enabled, false, "no tab disables Close Tab")

        var goToStart = checkMenuItem(transportMenu, "transport.go_to_start", "Go to Start")
        var play = checkMenuItem(transportMenu, "transport.play", "Play")
        var playPause = checkMenuItem(transportMenu, "transport.play_pause", "Play/Pause")
        var pause = checkMenuItem(transportMenu, "transport.pause", "Pause")
        var stop = checkMenuItem(transportMenu, "transport.stop", "Stop")
        var loop = checkMenuItem(transportMenu, "transport.loop", "Toggle Loop")
        var follow = checkMenuItem(transportMenu, "transport.follow_playhead", "Follow Playhead")
        var transportRows = [goToStart, play, playPause, pause, stop, loop, follow]
        for (var rowIndex = 0; rowIndex < transportRows.length; ++rowIndex)
            compare(transportRows[rowIndex].enabled, false,
                    "no song disables " + transportRows[rowIndex].objectName)
        compare(loop.checkable, true, "Loop is checkable")
        compare(follow.checkable, true, "Follow Playhead is checkable")
        compare(goToStart.checkable, false, "Go to Start is not checkable")
        menuOrder(transportMenu, ["transport.go_to_start", "transport.play",
                                 "transport.play_pause", "transport.pause",
                                 "transport.stop", "transport.loop",
                                 "transport.follow_playhead"])

        var automation = checkMenuItem(viewMenu, "view.automation_drawer", "Automation Drawer")
        var velocity = checkMenuItem(viewMenu, "view.velocity_drawer", "Velocity Drawer")
        var voiceChanges = checkMenuItem(viewMenu, "view.voice_changes_drawer",
                                         "Voice Changes Drawer")
        var colors = checkMenuItem(viewMenu, "view.velocity_colors", "Color Notes by Velocity")
        var names = checkMenuItem(viewMenu, "view.note_names", "Show Note Names")
        compare(automation.enabled, false, "no tab disables the automation drawer toggle")
        compare(velocity.enabled, false, "no tab disables the velocity drawer toggle")
        compare(voiceChanges.enabled, false, "no tab disables the voice-change drawer toggle")
        compare(colors.enabled, true, "velocity colours stay available with no song")
        compare(names.enabled, true, "note names stay available with no song")
        compare(automation.checkable, true, "the automation drawer toggle is checkable")
        compare(colors.checkable, true, "velocity colours are checkable")
        var eventList = findChild(viewMenu, "shellAction_view.event_list")
        verify(eventList !== null, "the event list row still leads the View menu")
        menuOrder(viewMenu, ["view.event_list", "view.automation_drawer",
                             "view.velocity_drawer", "view.voice_changes_drawer",
                             "view.polyphony_debugger", "view.velocity_colors",
                             "view.note_names"])

        var about = checkMenuItem(helpMenu, "help.about", "About porydaw")
        compare(about.enabled, true, "About stays available with no song")
    }

    function test_songMenuActionsDriveSessionState() {
        openShell()
        var bar = openSong()
        var presenter = shell.shellPresenter
        var session = presenter.session
        var tabs = session.songTabs
        var transport = session.transportBarPresenter()

        var closeTab = findChild(shell, "shellAction_file.close_tab")
        compare(closeTab.enabled, true, "the open tab enables Close Tab")

        // Drawer toggles flip section visibility and the menu check follows.
        // DrawerSectionKind raw values travel to QML unchanged: 0 automation,
        // 1 velocity, 2 voice changes.
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
        aboutDialog.close()
        tryVerify(function() { return !aboutDialog.visible }, 3000, "About closes again")
    }

    function test_editTailItemsExistDisabledAndInertWithNoSong() {
        openShell()
        var editMenu = findChild(shell, "shellEditMenu")
        verify(editMenu !== null, "the Edit menu is mounted")
        var ids = ["roll.pitch_bend", "edit.set_velocity", "edit.loop_from_selection",
                   "eventlist.move_up", "eventlist.move_down"]
        for (var index = 0; index < ids.length; ++index) {
            var item = findChild(editMenu, "shellAction_" + ids[index])
            verify(item !== null, "the menu owns " + ids[index])
            compare(item.enabled, false, ids[index] + " is disabled with no song")
            compare(shell.shellPresenter.actionEnabled(ids[index]), false,
                    ids[index] + " reports disabled with no song")
            shell.shellPresenter.activate(ids[index])
        }
        compare(shell.shellPresenter.session.songOpen, false, "inert activations open nothing")
        compare(shell.shellPresenter.sceneActive, true, "inert activations keep the scene")
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

    function test_loopFromRulerSelectionMenuAndUndoRestoresMarkers() {
        openShell()
        openSong()
        var presenter = shell.shellPresenter
        var grid = presenter.session.gridPresenter()
        verify(waitForNative(function() { return editorPage() !== null }, 10000),
               "the selected song tab mounts its ruler")
        var page = editorPage()
        var ruler = findChild(page, "timelineRulerInput")
        verify(ruler !== null && ruler.width > 0, "the production ruler is mounted")
        var loopItem = findChild(shell, "shellAction_edit.loop_from_selection")
        var undoItem = findChild(shell, "shellAction_edit.undo")
        verify(loopItem !== null && undoItem !== null, "the Edit menu owns loop and undo")
        function markerX(name) {
            var marker = findChild(page, name)
            return marker === null ? null : marker.x
        }
        var originalStart = markerX("loopStartMarker")
        var originalEnd = markerX("loopEndMarker")
        compare(loopItem.enabled, false, "without a time range the loop row is disabled")
        var startX = ruler.width * 0.28
        var endX = ruler.width * 0.55
        var y = ruler.height * 0.75
        mousePress(ruler, startX, y, Qt.LeftButton)
        mouseMove(ruler, endX, y, -1, Qt.LeftButton)
        mouseRelease(ruler, endX, y, Qt.LeftButton)
        tryVerify(function() { return loopItem.enabled }, 3000,
                  "the ruler sweep enables the live Edit menu loop row")
        loopItem.triggered()
        var snapPixels = Math.max(1, grid.snapTicks) * grid.beatWidth / grid.ticksPerBeat
        tryVerify(function() {
            var start = markerX("loopStartMarker")
            var end = markerX("loopEndMarker")
            return start !== null && end !== null
                && Math.abs(start + 0.5 - startX) <= snapPixels + 1
                && Math.abs(end + 0.5 - endX) <= snapPixels + 1
        }, 3000, "the loop markers render at the ruler-selected start and end")
        var selectedStart = markerX("loopStartMarker")
        var selectedEnd = markerX("loopEndMarker")
        verify(selectedStart !== originalStart && selectedEnd !== originalEnd,
               "the menu replaces both original loop endpoints")
        tryVerify(function() { return undoItem.enabled }, 3000,
                  "the loop edit enables Undo")
        undoItem.triggered()
        verify(waitForNative(function() {
            return markerX("loopStartMarker") === selectedStart
                && markerX("loopEndMarker") === originalEnd
        }, 3000), "first Undo restores only the original loop end")
        tryVerify(function() { return undoItem.enabled }, 3000,
                  "Undo remains available for the other loop endpoint")
        undoItem.triggered()
        verify(waitForNative(function() {
            return markerX("loopStartMarker") === originalStart
                && markerX("loopEndMarker") === originalEnd
        }, 3000), "second Undo restores both original loop endpoints")
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
        verify(upItem !== null && downItem !== null, "the Edit menu owns the event moves")
        compare(presenter.actionEnabled("eventlist.move_up"), false,
                "the hidden event list disables move up")
        compare(presenter.actionEnabled("eventlist.move_down"), false,
                "the hidden event list disables move down")
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

    function test_displayModesPersistAcrossShells() {
        openShell()
        var presenter = shell.shellPresenter
        var session = presenter.session
        if (session.velocityColorMode)
            presenter.activate("view.velocity_colors")
        if (session.noteNameMode)
            presenter.activate("view.note_names")
        compare(session.velocityColorMode, false, "the test starts from colours off")
        presenter.activate("view.velocity_colors")
        presenter.activate("view.note_names")
        tryVerify(function() {
            settings.sync()
            return settings.value("velocityNoteColors", false) === true
        }, 3000, "toggling colours writes the original root key")
        tryVerify(function() {
            settings.sync()
            return settings.value("noteNames", false) === true
        }, 3000, "toggling names writes the original root key")
        closeShell()
        openShell()
        session = shell.shellPresenter.session
        compare(session.velocityColorMode, true, "a fresh shell restores velocity colours")
        compare(session.noteNameMode, true, "a fresh shell restores note names")
        var colors = findChild(shell, "shellAction_view.velocity_colors")
        compare(colors.checked, true, "the restored check is visible in the menu")
        presenter = shell.shellPresenter
        presenter.activate("view.velocity_colors")
        presenter.activate("view.note_names")
        tryVerify(function() {
            settings.sync()
            return settings.value("velocityNoteColors", true) === false
        }, 3000, "toggling back clears the stored colours")
    }
}
