import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellMenusSupport {
    ShellQmlBootstrap { id: songBootstrap }

    function dockPresenter() { return shell.shellPresenter.session.songDockController().songListPresenter() }
    function dockController() { return shell.shellPresenter.session.songDockController() }
    function dockRow(id) {
        var view = findChild(shell, "songList")
        for (var index = 0; index < view.count; ++index) {
            if (dockPresenter().songId(index) !== id)
                continue
            view.positionViewAtIndex(index, ListView.Contain)
            return view.itemAtIndex(index)
        }
        return null
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
        var names = checkMenuItem(viewMenu, "view.note_names", "Show Note Names")
        compare(automation.enabled, false, "no tab disables the automation drawer toggle")
        compare(velocity.enabled, false, "no tab disables the velocity drawer toggle")
        compare(voiceChanges.enabled, false, "no tab disables the voice-change drawer toggle")
        compare(names.enabled, true, "note names stay available with no song")
        compare(automation.checkable, true, "the automation drawer toggle is checkable")
        compare(names.checkable, true, "note names are checkable")
        var eventList = findChild(viewMenu, "shellAction_view.event_list")
        verify(eventList !== null, "the event list row still leads the View menu")
        compare(viewMenu.itemAt(5).objectName, "shellViewSectionSeparator",
                "the global View preferences follow a separator")
        compare(viewMenu.itemAt(7).objectName, "shellAction_transport.follow_playhead",
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
        menuOrder(file, ["file.open_project", "file.new_song", "file.save_song", "file.register_song", "file.close_tab", "file.quit"])
        compare(file.count, 6, "the File menu keeps only the mounted file rows")
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

    function test_noteNamesPersistAcrossShells() {
        openShell()
        var presenter = shell.shellPresenter
        var session = presenter.session
        if (session.noteNameMode)
            presenter.activate("view.note_names")
        compare(session.noteNameMode, false, "the test starts from names off")
        presenter.activate("view.note_names")
        tryVerify(function() {
            return settings.bool("noteNames", false)
        }, 3000, "toggling names writes the original root key")
        closeShell()
        openShell()
        session = shell.shellPresenter.session
        compare(session.noteNameMode, true, "a fresh shell restores note names")
        var names = findChild(shell, "shellAction_view.note_names")
        compare(names.checked, true, "the restored check is visible in the menu")
        presenter = shell.shellPresenter
        presenter.activate("view.note_names")
        tryVerify(function() {
            return !settings.bool("noteNames", true)
        }, 3000, "toggling back clears the stored names")
    }

    function test_fileRegisterSongActsOnSelectedTab() {
        verify(songBootstrap.resetPreferences(), "the register journey starts with fresh window and filter state")
        var originalRoot = songBootstrap.projectRoot
        verify(songBootstrap.prepareSongActionFixture("charmap"),
               "the register journey stages its isolated charmap-only project")
        var root = songBootstrap.projectRoot
        openShell()
        verify(shell !== null, "the File-menu fixture opens a production shell")
        var session = shell.shellPresenter.session
        var presenter = shell.shellPresenter
        var dock = session.songDockController()
        var songs = dock.songListPresenter()
        var songList = findChild(shell, "songList")
        verify(songList !== null, "the production Songs list is mounted for the File-menu journey")
        session.openProject(root)
        verify(waitForNative(function() { return session.projectOpen && songs.rowCount > 0 }, 30000),
               "the File-menu project loads the staged charmap project with its listed route song")
        var routeId = -1
        for (var index = 0; index < songs.rowCount; ++index) {
            songList.positionViewAtIndex(index, ListView.Contain)
            var candidate = songList.itemAtIndex(index)
            if (candidate !== null && candidate.song.label === "mus_route101")
                routeId = songs.songId(index)
        }
        verify(routeId >= 0, "the charmap-gapped route song is listed for the File-menu journey")
        var fileMenu = findChild(shell, "shellFileMenu")
        var registerRow = checkMenuItem(fileMenu, "file.register_song", "Register Song")
        compare(presenter.actionEnabled("file.register_song"), false,
                "no selected tab disables File Register Song")
        compare(registerRow.enabled, false, "the File menu shows Register Song disabled with no tab")
        var target = dockRow(routeId)
        verify(target !== null, "the gapped route row is mounted for the File-menu journey")
        compare(target.song.registrationGapText, "charmap.txt",
                "the File-menu song is missing only charmap.txt")
        mouseDoubleClickSequence(target, target.width / 2, target.height / 2, Qt.LeftButton)
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 1
                && session.songTabs.selectedPage.title === "mus_route101"
        }, 30000), "the gapped song opens in an editor tab for its File-menu repair")
        compare(presenter.actionEnabled("file.register_song"), true,
                "the selected gapped tab enables File Register Song")
        fileMenu.open()
        tryVerify(function() { return registerRow.enabled }, 3000,
                  "the opened File menu enables Register Song on the gapped tab")
        fileMenu.close()
        presenter.activate("file.register_song")
        verify(waitForNative(function() {
            var dialog = findChild(shell, "songConfirmationDialog")
            return dock.confirmation === "register" && dialog !== null && dialog.visible
        }, 5000), "activating File Register Song mounts the register confirmation for the selected tab")
        var confirmation = findChild(shell, "songConfirmationDialog")
        compare(dock.confirmationDetail,
                "The following registration files need updates:\n  - charmap.txt",
                "the File-menu ingress carries the charmap-only plan detail")
        verify(confirmation.standardButton(Dialog.Ok) !== null,
               "the File-menu confirmation has an activatable accepting button")
        mouseClick(confirmation.standardButton(Dialog.Ok))
        verify(waitForNative(function() {
            return !dock.busy && dockRow(routeId) !== null
                && dockRow(routeId).song.registrationGapText === ""
                && !songs.canRegister(routeId)
        }, 30000), "accepting the File-menu registration repairs the selected song")
        compare(presenter.actionEnabled("file.register_song"), false,
                "the repaired clean tab disables File Register Song")
        fileMenu.open()
        tryVerify(function() { return !registerRow.enabled }, 3000,
                  "the opened File menu disables Register Song on the clean tab")
        fileMenu.close()
        songBootstrap.projectRoot = originalRoot
    }
}
