import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellMenus"
    when: windowShown
    width: 1100
    height: 720
    visible: true

    property var shell: null
    readonly property var settings: bootstrap.preferences

    ShellQmlBootstrap { id: bootstrap }

    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }


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
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openDiagnostics(session) {
        return " (projectOpen=" + session.projectOpen
            + "; songOpen=" + session.songOpen
            + "; lastSaveError=" + session.lastSaveError
            + "; status=" + shell.shellPresenter.statusText + ")"
    }

    function openShell() {
        // Every explicit-open test starts without a stale startup recipe.
        settings.setString("lastProjectDir", "")
        settings.setBool("editorDrawer.velocityVisible", true)
        settings.setInt("editorDrawer.velocityHeight", 173)
        settings.setBool("editorDrawer.automationVisible", true)
        settings.setInt("editorDrawer.automationHeight", 200)
        settings.setBool("editorDrawer.voiceChangesVisible", true)
        settings.setInt("editorDrawer.voiceChangesHeight", 200)
        settings.setString("editorDrawer.activePage", "velocity")
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
        verify(item.text.indexOf(shell.shellPresenter.menuLabel(actionId)) === 0,
                actionId + " shows its label, got: " + item.text)
        return item
    }

    function menuOrder(menu, actionIds, message) {
        var actual = []
        for (var index = 0; index < menu.count; ++index)
            actual.push(menu.itemAt(index).objectName)
        compare(JSON.stringify(actual),
                JSON.stringify(actionIds.map(function(id) { return "shellAction_" + id })),
                message || "the menu keeps the original order")
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
        compare(transportMenu.title, "Trans&port")
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
        var follow = checkMenuItem(viewMenu, "transport.follow_playhead", "Follow Playhead")
        var transportRows = [goToStart, play, playPause, pause, stop, loop]
        for (var rowIndex = 0; rowIndex < transportRows.length; ++rowIndex)
            compare(transportRows[rowIndex].enabled, false,
                    "no song disables " + transportRows[rowIndex].objectName)
        compare(follow.enabled, true, "Follow Playhead stays enabled without a song")
        compare(loop.checkable, true, "Loop is checkable")
        compare(follow.checkable, true, "Follow Playhead is checkable")
        compare(goToStart.checkable, false, "Go to Start is not checkable")
        menuOrder(transportMenu, ["transport.go_to_start", "transport.play",
                                 "transport.play_pause", "transport.pause",
                                 "transport.stop", "transport.loop"])

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
        compare(viewMenu.itemAt(5).objectName, "shellViewSectionSeparator",
                "the global View preferences follow a separator")
        compare(viewMenu.itemAt(8).objectName, "shellAction_transport.follow_playhead",
                "Follow Playhead stays at the fork View position")

        var about = checkMenuItem(helpMenu, "help.about", "About porydaw")
        compare(about.enabled, true, "About stays available with no song")
    }

    function test_forkMenuTopologyAndLabels() {
        openShell()
        var presenter = shell.shellPresenter
        var file = findChild(shell, "shellFileMenu")
        var edit = findChild(shell, "shellEditMenu")
        var view = findChild(shell, "shellViewMenu")
        menuOrder(file, ["file.open_project", "file.save_song", "file.close_tab", "file.quit"])
        compare(file.count, 4, "the File menu keeps only the mounted file rows")
        verify(findChild(file, "shellAction_songs.find") === null,
               "Find Song moves from File to the Edit clipboard group")
        var clipboard = ["roll.copy", "roll.cut", "roll.paste", "roll.delete",
                         "roll.select_all", "songs.find"]
        for (var i = 0; i < clipboard.length; ++i)
            compare(edit.itemAt(i + 3).objectName, "shellAction_" + clipboard[i],
                    "the Edit clipboard head follows Undo and Redo")
        var submenuNames = ["shellTimeMenu", "shellNotesMenu", "shellMoveMenu",
                            "shellTracksMenu", "shellAutomationMenu", "shellEventsMenu",
                            "shellLoopMenu", "shellTransportMenu"]
        var submenuTitles = ["&Time", "&Notes", "&Move", "Tr&acks", "&Automation",
                             "&Events", "&Loop", "Trans&port"]
        for (var sub = 0; sub < submenuNames.length; ++sub) {
            verify(findChild(edit, submenuNames[sub]) !== null,
                   "the Edit menu mounts " + submenuNames[sub])
            compare(edit.itemAt(sub + 9).text, submenuTitles[sub],
                    "the Edit menu nests the fork's eight command submenus in order")
        }
        menuOrder(findChild(edit, "shellTimeMenu"),
                  ["edit.insert_time", "edit.delete_time", "roll.duplicate_time",
                   "edit.clear_time_selection", "edit.edit_time_signature",
                   "edit.remove_time_signature"], "the Time submenu retains the fork actions")
        menuOrder(findChild(edit, "shellNotesMenu"),
                  ["roll.transpose_up", "roll.transpose_down", "roll.transpose_up_octave",
                   "roll.transpose_down_octave", "roll.pitch_bend", "edit.set_velocity",
                   "roll.duplicate_time", "roll.split", "roll.join"],
                  "the Notes submenu retains the fork actions")
        menuOrder(findChild(edit, "shellMoveMenu"),
                  ["roll.nudge_left", "roll.nudge_right"],
                  "the Move submenu retains the fork actions")
        menuOrder(findChild(edit, "shellTracksMenu"),
                  ["roll.mute_tracks", "roll.solo_tracks"],
                  "the Tracks submenu retains the fork actions")
        menuOrder(findChild(edit, "shellAutomationMenu"),
                  ["automation.pencil_mode"], "the Automation submenu retains the fork action")
        menuOrder(findChild(edit, "shellEventsMenu"),
                  ["eventlist.move_up", "eventlist.move_down"],
                  "the Events submenu retains the fork actions")
        menuOrder(findChild(edit, "shellLoopMenu"),
                  ["edit.set_loop_start", "edit.set_loop_end",
                   "edit.loop_from_selection", "edit.remove_loop"],
                  "the Loop submenu retains the fork actions")
        var transport = findChild(edit, "shellTransportMenu")
        menuOrder(transport, ["transport.go_to_start", "transport.play",
                              "transport.play_pause", "transport.pause",
                              "transport.stop", "transport.loop"])
        verify(findChild(transport, "shellAction_transport.follow_playhead") === null,
               "Follow Playhead is not a Transport submenu row")
        compare(view.itemAt(view.count - 1).objectName,
                "shellAction_transport.follow_playhead",
                "Follow Playhead ends the View preference group")
        compare(presenter.actionLabel("roll.copy"), "Copy Selection",
                "menu rows show the keymap label")
        compare(presenter.actionLabel("file.save_song"), "Save Song",
                "Save Song uses the keymap wording")
        compare(findChild(file, "shellAction_file.open_project").text.indexOf("Open Project...") >= 0,
                true, "the File menu keeps the fork Open Project ellipsis")
        verify(findChild(view, "shellAction_view.voice_changes_drawer").text
               .indexOf("Voice-change Drawer") === 0,
               "the View menu keeps the fork drawer wording")
    }

    function test_forkNoteContextShapeAndLoopGates() {
        openShell()
        var context = findChild(shell, "shellGridContextMenu")
        compare(context.itemAt(0).objectName, "shellContextAction_edit.set_velocity",
                "the note context menu leads with Set Velocity and omits Paste")
        var contextIds = ["roll.copy", "roll.cut", "roll.duplicate_time",
                          "roll.split", "roll.join", "roll.delete"]
        for (var i = 0; i < contextIds.length; ++i)
            compare(context.itemAt(i + 2).objectName,
                    "shellContextAction_" + contextIds[i],
                    "the note context menu follows the fork command order")
        verify(findChild(context, "shellContextAction_roll.paste") === null,
               "the note context menu omits Paste")
        var loop = findChild(shell, "shellLoopMenu")
        menuOrder(loop, ["edit.set_loop_start", "edit.set_loop_end",
                         "edit.loop_from_selection", "edit.remove_loop"])
        compare(shell.shellPresenter.actionEnabled("edit.set_loop_start"), false,
                "loop rows gate on song and markers")
        compare(shell.shellPresenter.actionEnabled("edit.remove_loop"), false,
                "Remove Loop Markers needs a song and marker")
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

    function test_loopMenuCommandsUseCursorAndUndoOneMarkerAtATime() {
        openShell()
        openSong()
        var presenter = shell.shellPresenter
        var session = presenter.session
        var page = editorPage()
        var grid = session.gridPresenter()
        var start = findChild(shell, "shellAction_edit.set_loop_start")
        var end = findChild(shell, "shellAction_edit.set_loop_end")
        var remove = findChild(shell, "shellAction_edit.remove_loop")
        if (remove.enabled)
            remove.triggered()
        tryVerify(function() { return !remove.enabled }, 3000,
                  "Remove Loop Markers gates on existing markers")
        var startTick = Math.max(grid.snapTicks, grid.editCursorTick + grid.snapTicks)
        grid.setEditCursorTick(startTick)
        tryVerify(function() { return start.enabled && end.enabled }, 3000,
                  "the open song enables both cursor loop rows")
        start.triggered()
        var markerStart = function() { return findChild(page, "loopStartMarker") }
        var markerEnd = function() { return findChild(page, "loopEndMarker") }
        var xAt = function(tick) {
            return tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
        }
        tryVerify(function() {
            return markerStart() !== null
                && Math.abs(markerStart().x + 0.5 - xAt(startTick)) <= 0.75
        }, 3000, "Set Loop Start at Edit Cursor writes one undoable marker at the edit cursor")
        var endTick = startTick + Math.max(1, grid.snapTicks)
        grid.setEditCursorTick(endTick)
        end.triggered()
        tryVerify(function() {
            return markerEnd() !== null
                && Math.abs(markerEnd().x + 0.5 - xAt(endTick)) <= 0.75
        }, 3000, "Set Loop End at Edit Cursor writes one undoable marker at the edit cursor")
        tryVerify(function() { return remove.enabled }, 3000,
                  "Remove Loop Markers enables when markers exist")
        remove.triggered()
        tryVerify(function() { return markerStart() === null && markerEnd() === null }, 3000,
                  "Remove Loop Markers clears both markers")
        tryVerify(function() { return session.canUndo }, 3000,
                  "the marker removal publishes its Undo availability")
        session.requestUndo()
        verify(waitForNative(function() {
            return markerStart() === null && markerEnd() !== null
        }, 5000), "Remove Loop Markers writes two undo entries restoring one marker at a time")
        session.requestUndo()
        verify(waitForNative(function() {
            return markerStart() !== null && markerEnd() !== null
        }, 5000), "the second Undo restores the loop start independently")
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
            return settings.bool("velocityNoteColors", false)
        }, 3000, "toggling colours writes the original root key")
        tryVerify(function() {
            return settings.bool("noteNames", false)
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
            return !settings.bool("velocityNoteColors", true)
        }, 3000, "toggling back clears the stored colours")
    }
}
