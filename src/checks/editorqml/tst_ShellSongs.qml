import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellSongs"
    when: windowShown
    width: 1100
    height: 720
    visible: true

    property var shell: null
    property string originalProjectRoot: ""
    ShellQmlBootstrap { id: bootstrap }
    TabsDrawerProbe { id: fileProbe }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 550; visible: true } }
    SignalSpy { id: failureSpy; signalName: "operationFailed" }

    function init() {
        originalProjectRoot = bootstrap.projectRoot
        verify(bootstrap.resetPreferences(), "each shell starts with fresh window and filter state")
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }


    function cleanup() {
        if (!shell) {
            bootstrap.projectRoot = originalProjectRoot
            return
        }
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            for (let step = 0; step < 12 && !shell.shellPresenter.closeReady; ++step) {
                verify(waitForNative(function() {
                    return shell.shellPresenter.closeReady
                        || shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                }, 5000), "the close-all walk settles")
                if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                    shell.shellPresenter.session.songTabs.confirmDiscard()
            }
            verify(shell.shellPresenter.closeReady,
                   "scene and workspace release before shell destruction")
        }
        shell.destroy()
        shell = null
        bootstrap.projectRoot = originalProjectRoot
        wait(0)
    }

    function panel() { return findChild(shell, "swiftSongsPanel") }
    function list() { return findChild(shell, "songList") }
    function row(id) {
        const view = list()
        for (let index = 0; index < view.count; ++index) {
            if (presenter().songId(index) !== id)
                continue
            view.positionViewAtIndex(index, ListView.Contain)
            return view.itemAtIndex(index)
        }
        return null
    }
    function presenter() { return shell.shellPresenter.session.songDockController().songListPresenter() }
    function controller() { return shell.shellPresenter.session.songDockController() }
    function windowShortcut(name) {
        const delegates = shell.contentItem.children
        for (const delegate of delegates) {
            const objects = delegate.data
            for (const object of objects || []) {
                if (object.objectName === name)
                    return object
            }
        }
        return null
    }
    function compareRole(item, role, name) {
        verify(!!item, name + " is mounted for " + role)
        const expected = shell.shellPresenter.session.typographyFonts[role]
        compare(item.font.family, expected.family, name + " uses " + role + " family")
        compare(item.font.pixelSize, expected.pixelSize, name + " uses " + role + " pixelSize")
        compare(item.font.weight, expected.weight, name + " uses " + role + " weight")
    }


    function menuAction(id) {
        const menu = findChild(shell, "songListContextMenu")
        verify(!!menu && menu.visible, "the mounted Songs context menu is open")
        const index = ({ open: 0, newTab: 1, register: 3, delete: 4 })[id]
        const item = menu.contentItem.rowItem(index)
        verify(!!item && item.objectName === "songs.menu." + id,
               "mounted menu has " + id)
        mouseClick(item, item.width / 2, item.height / 2)
        verify(!menu.visible, "clicking " + id + " activates and closes the mounted menu")
    }

    function clickConfirmation() {
        const loader = findChild(shell, "songConfirmationLoader")
        verify(loader !== null && loader.status === Loader.Ready, "real confirmation dialog is loaded")
        const dialog = loader.item
        verify(dialog.visible, "confirmation is visible")
        const button = dialog.standardButton(Dialog.Ok)
        verify(button !== null, "the confirmation exposes its action")
        mouseClick(button)
    }

    function registrationBytes() {
        return ["sound/song_table.inc", "include/constants/songs.h",
                "sound/songs/midi/midi.cfg"].map(function(relative) {
            return fileProbe.fileFingerprint(bootstrap.projectRoot + "/" + relative)
        })
    }

    function compareRegion(reference, name, item, tolerance) {
        const expected = reference.regions.find(function(region) { return region.name === name })
        verify(expected !== undefined, name + " is pinned by widget baseline JSON")
        verify(!!item, name + " exists inside the mounted Songs pane")
        const actual = item.mapToItem(panel(), 0, 0)
        verify(Math.abs(actual.x - expected.x) <= tolerance, name + " x: " + actual.x)
        verify(Math.abs(actual.y - expected.y) <= tolerance, name + " y: " + actual.y)
        verify(Math.abs(item.width - expected.w) <= tolerance, name + " width: " + item.width)
        verify(Math.abs(item.height - expected.h) <= tolerance, name + " height: " + item.height)
    }

    function test_newSongShortcutCreatesFromSelectedSong() {
        verify(bootstrap.prepareSongActionFixture("open-delete"),
               "the new-song journey uses its own copied project")
        const root = bootstrap.projectRoot
        const source = root + "/sound/songs/midi/mus_route101.mid"
        const target = root + "/sound/songs/midi/musclone.mid"
        compare(fileProbe.fileFingerprint(source), "471:d31e7c4a0a32a53f",
                "the original song starts with independently pinned MIDI bytes")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production shell mounts the New Song shortcut")
        shell.requestActivate()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(root, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen && session.songTabs.selectedPage
                && session.songTabs.selectedPage.isReady
        }, 30000), "the current source song is ready before the shortcut")
        const priorId = session.songTabs.selectedId
        const shortcut = windowShortcut("shellShortcut_file.new_song")
        verify(shortcut !== null && shortcut.enabled,
               "the registered New Song window shortcut is mounted and enabled")
        list().forceActiveFocus()
        keySequence(StandardKey.New)
        verify(waitForNative(function() { return controller().confirmation === "create" }, 5000),
               "the real New shortcut opens the Songs dock name prompt")
        const nameField = findChild(shell, "songNewName")
        const dialog = findChild(shell, "songConfirmationDialog")
        verify(nameField !== null && dialog !== null && nameField.activeFocus,
               "the mounted prompt focuses its visible name entry")
        const accept = dialog.standardButton(Dialog.Ok)
        compare(accept.text, "Create", "the New Song accept action is titled Create")
        compare(accept.enabled, false, "an empty song name cannot be accepted")
        keyClick(Qt.Key_Return)
        compare(controller().confirmation, "create",
                "Return cannot accept the prompt while its name is invalid")
        for (const key of [Qt.Key_M, Qt.Key_U, Qt.Key_S, Qt.Key_C, Qt.Key_L,
                           Qt.Key_O, Qt.Key_N, Qt.Key_E])
            keyClick(key)
        compare(nameField.text, "musclone", "real text input enters the song label")
        compare(accept.enabled, true, "a valid label enables the mounted Create button")
        keyClick(Qt.Key_Return)
        verify(waitForNative(function() {
            return !controller().busy && session.songTabs.tabCount === 2
                && session.songTabs.selectedPage
                && session.songTabs.selectedPage.title === "musclone"
                && session.songTabs.selectedPage.isReady
        }, 30000), "Create registers, opens and selects a new playable song tab")
        compare(fileProbe.fileFingerprint(target), "471:d31e7c4a0a32a53f",
                "the new MIDI contains the source's independently pinned bytes")
        verify(session.songTabs.selectedId !== priorId,
               "creation selects a distinct tab while retaining the original")
        compare(row(presenter().currentSongId).song.label, "musclone",
                "the Songs dock selects the newly opened song")
    }

    function test_newSongEscapeCancelsWithoutMutation() {
        verify(bootstrap.prepareSongActionFixture("open-delete"),
               "the Escape journey stages an isolated copied project")
        const root = bootstrap.projectRoot
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the mounted shell presents the Escape journey")
        shell.requestActivate()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(root, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen && session.songTabs.selectedPage
                && session.songTabs.selectedPage.isReady
        }, 30000), "the current source is ready before cancelling creation")
        verify(waitForNative(function() { return presenter().rowCount > 0 }, 5000),
               "the Songs dock catalog is ready before cancelling creation")
        const priorId = session.songTabs.selectedId
        const originalFiles = registrationBytes()
        const priorCount = presenter().rowCount
        list().forceActiveFocus()
        keySequence(StandardKey.New)
        verify(waitForNative(function() { return controller().confirmation === "create" }, 5000),
               "the mounted New Song prompt opens before Escape")
        const field = findChild(shell, "songNewName")
        verify(field !== null && field.activeFocus,
               "Escape starts from the focused production song-name entry")
        keyClick(Qt.Key_M)
        compare(field.text, "m", "the cancelled prompt contains typed draft input")
        keyClick(Qt.Key_Escape)
        verify(waitForNative(function() { return controller().confirmation === "" }, 5000),
               "Escape dismisses the prompt and cancels the draft")
        compare(fileProbe.fileFingerprint(root + "/sound/songs/midi/m.mid"), "",
                "Escape creates no MIDI file for the draft label")
        compare(JSON.stringify(registrationBytes()), JSON.stringify(originalFiles),
                "Escape leaves registration and song flags untouched")
        compare(session.songTabs.selectedId, priorId,
                "Escape keeps the original tab selected")
        compare(session.songTabs.tabCount, 1, "Escape adds no song tab")
        compare(presenter().rowCount, priorCount, "Escape leaves the Songs dock unchanged")
    }

    function test_newSongCollisionRefusesWithoutTouchingTabsOrBytes() {
        verify(bootstrap.prepareSongDeletionFixture("cancel"),
               "the colliding song journey uses its own copied project")
        const root = bootstrap.projectRoot
        const stray = root + "/sound/songs/midi/mus_stray_test.mid"
        const expectedStray = "471:d31e7c4a0a32a53f"
        compare(fileProbe.fileFingerprint(stray), expectedStray,
                "the test-owned stray begins with the independent literal MIDI fingerprint")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production shell mounts the collision prompt")
        shell.requestActivate()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(root, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen && session.songTabs.selectedPage
                && session.songTabs.selectedPage.isReady
        }, 30000), "the current song opens before the collision attempt")
        verify(waitForNative(function() { return presenter().rowCount > 0 }, 5000),
               "the Songs dock catalog is ready before the collision attempt")
        const priorId = session.songTabs.selectedId
        const priorCount = presenter().rowCount
        const originalFiles = registrationBytes()
        failureSpy.target = session
        failureSpy.clear()
        list().forceActiveFocus()
        keySequence(StandardKey.New)
        verify(waitForNative(function() { return controller().confirmation === "create" }, 5000),
               "the registered window shortcut presents the mounted name prompt")
        const field = findChild(shell, "songNewName")
        const dialog = findChild(shell, "songConfirmationDialog")
        verify(field !== null && field.activeFocus && dialog !== null,
               "the collision label is entered in the real prompt")
        for (const key of [Qt.Key_M, Qt.Key_U, Qt.Key_S, Qt.Key_Underscore, Qt.Key_S,
                           Qt.Key_T, Qt.Key_R, Qt.Key_A, Qt.Key_Y, Qt.Key_Underscore,
                           Qt.Key_T, Qt.Key_E, Qt.Key_S, Qt.Key_T])
            keyClick(key)
        compare(field.text, "mus_stray_test", "real typing names the existing stray MIDI")
        compare(dialog.standardButton(Dialog.Ok).enabled, true,
                "an unregistered stray must reach the service collision check")
        mouseClick(dialog.standardButton(Dialog.Ok))
        verify(waitForNative(function() { return failureSpy.count === 1 && !controller().busy }, 30000),
               "the colliding create reports one production error")
        verify(failureSpy.signalArguments[0][0].indexOf("mus_stray_test") >= 0,
               "the mounted failure names the colliding label")
        compare(fileProbe.fileFingerprint(stray), expectedStray,
                "the refusal preserves every byte of the independently pinned stray")
        compare(JSON.stringify(registrationBytes()), JSON.stringify(originalFiles),
                "the refusal leaves all registration and flag files unchanged")
        compare(session.songTabs.tabCount, 1, "collision leaves the original tab count")
        compare(session.songTabs.selectedId, priorId, "collision leaves the original tab selected")
        compare(presenter().rowCount, priorCount, "collision leaves the Songs dock listing unchanged")
        compare(fileProbe.fileFingerprint(root + "/sound/songs/midi/mus_stray_test.s"), "",
                "collision produces no stray MIDI assembly output")
    }

    function test_newSongNameFieldFoldsFiltersAndRefusesLeadingDigit() {
        verify(bootstrap.prepareSongActionFixture("open-delete"),
               "the folded-name journey uses its own copied project")
        const root = bootstrap.projectRoot
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production shell mounts the folding name prompt")
        shell.requestActivate()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(root, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen && session.songTabs.selectedPage
                && session.songTabs.selectedPage.isReady
        }, 30000), "the current source song is ready before folding input")
        list().forceActiveFocus()
        keySequence(StandardKey.New)
        verify(waitForNative(function() { return controller().confirmation === "create" }, 5000),
               "the real New shortcut opens the Songs dock name prompt")
        const field = findChild(shell, "songNewName")
        const dialog = findChild(shell, "songConfirmationDialog")
        verify(field !== null && field.activeFocus && dialog !== null,
               "folded input enters through the real mounted prompt")
        const accept = dialog.standardButton(Dialog.Ok)
        keyClick(Qt.Key_M, Qt.ShiftModifier)
        compare(field.text, "m", "a typed capital folds to lowercase in the field")
        keyClick(Qt.Key_U, Qt.ShiftModifier)
        compare(field.text, "mu", "consecutive capitals keep folding per keystroke")
        keyClick(Qt.Key_Dollar)
        compare(field.text, "mu", "a character outside the name alphabet never reaches the field")
        keyClick(Qt.Key_Home)
        keyClick(Qt.Key_9)
        compare(field.text, "mu", "a leading digit never leads the mounted field")
        compare(controller().newSongLabel, "mu", "the folded text publishes to the creation label")
        compare(accept.enabled, true, "the folded free label enables the mounted Create button")
        const taken = findChild(shell, "songConfirmationTaken")
        verify(taken !== null && !taken.visible,
               "no taken hint shows for the free folded label")
    }

    function test_newSongTakenNameDisablesCreateWithHint() {
        verify(bootstrap.prepareSongActionFixture("open-delete"),
               "the taken-name journey uses its own copied project")
        const root = bootstrap.projectRoot
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production shell mounts the taken-name prompt")
        shell.requestActivate()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(root, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen && session.songTabs.selectedPage
                && session.songTabs.selectedPage.isReady
        }, 30000), "the current source song is ready before the taken-name attempt")
        list().forceActiveFocus()
        keySequence(StandardKey.New)
        verify(waitForNative(function() { return controller().confirmation === "create" }, 5000),
               "the real New shortcut opens the Songs dock name prompt")
        const field = findChild(shell, "songNewName")
        const dialog = findChild(shell, "songConfirmationDialog")
        verify(field !== null && field.activeFocus && dialog !== null,
               "the taken label is entered in the real prompt")
        const accept = dialog.standardButton(Dialog.Ok)
        for (const key of [Qt.Key_M, Qt.Key_U, Qt.Key_S, Qt.Key_Underscore, Qt.Key_R,
                           Qt.Key_O, Qt.Key_U, Qt.Key_T, Qt.Key_E, Qt.Key_1, Qt.Key_0, Qt.Key_1])
            keyClick(key)
        compare(field.text, "mus_route101", "real typing names the open snapshot song")
        const taken = findChild(shell, "songConfirmationTaken")
        verify(taken !== null && taken.visible,
               "the taken name shows the mounted collision hint")
        compare(taken.text, "A song named mus_route101 already exists.",
                "the mounted hint carries the fork's collision wording")
        compare(accept.enabled, false, "a taken name disables the mounted Create button")
        keyClick(Qt.Key_Return)
        compare(controller().confirmation, "create",
                "Return cannot accept the prompt while its name is taken")
        field.selectAll()
        for (const key of [Qt.Key_M, Qt.Key_U, Qt.Key_S, Qt.Key_N, Qt.Key_E, Qt.Key_W])
            keyClick(key)
        compare(field.text, "musnew", "a fresh label replaces the taken draft")
        compare(taken.visible, false, "the hint clears for the free label")
        compare(accept.enabled, true, "the free label re-enables the mounted Create button")
    }

    function test_deleteSongConfirmationBranches() {
        for (const branch of ["cancel", "opt-out", "opt-in"]) {
            verify(bootstrap.prepareSongDeletionFixture(branch),
                   "the mounted deletion branch uses its own copied project")
            const paths = ["sound/song_table.inc", "include/constants/songs.h",
                           "sound/songs/midi/midi.cfg", "sound/voice_groups.inc",
                           "sound/voicegroups/fixture_songs_dock.inc"]
            const expected = ["780:cd265cf93bb70ec3", "423:7e4eec643bee2aa", "672:c98052dc8895c041",
                              "52:3bb1c28fd6f7ab72", "73:922bb3bdc6282dd5"]
            shell = shellComponent.createObject(null)
            verify(shell !== null, "a mounted production shell opens the copied deletion project")
            shell.shellPresenter.session.openProject(bootstrap.projectRoot)
            verify(waitForNative(function() { return shell.shellPresenter.session.projectOpen }, 30000),
                   "the mounted deletion project opens before dialog input")
            verify(waitForNative(function() { return presenter().rowCount === 10 }, 5000),
                   "the deletion fixture exposes its stray MIDI in the mounted list")
            let deletedId = -1
            for (let index = 0; index < presenter().rowCount; ++index) {
                const candidate = presenter().songId(index)
                if (row(candidate).song.label === "mus_stray_test") {
                    deletedId = candidate
                    break
                }
            }
            verify(deletedId >= 0, "the mounted stray is located by its song label")
            mouseClick(row(deletedId), row(deletedId).width / 2,
                       row(deletedId).height / 2, Qt.RightButton)
            menuAction("delete")
            verify(waitForNative(function() { return controller().confirmation === "delete" }, 5000),
                   "the real menu opens its mounted deletion confirmation")
            compare(JSON.stringify(paths.map(path => fileProbe.fileFingerprint(bootstrap.projectRoot + "/" + path))),
                    JSON.stringify(expected), "staging deletion preserves the literal project and bank images")
            compare(bootstrap.dockSongMidiExists(), true, "staging keeps the original MIDI at its path")
            const dialog = findChild(shell, "songConfirmationDialog")
            const checkbox = findChild(dialog, "songDeleteVoicegroup")
            compare(checkbox.checked, true, "the mounted deletion checkbox initially opts into unused-bank removal")
            if (branch === "cancel") {
                mouseClick(dialog.standardButton(Dialog.Cancel))
                compare(controller().confirmation, "", "Cancel dismisses the mounted deletion confirmation")
                compare(JSON.stringify(paths.map(path => fileProbe.fileFingerprint(bootstrap.projectRoot + "/" + path))),
                        JSON.stringify(expected), "Cancel preserves literal registration, flags and bank images")
                compare(bootstrap.dockSongMidiExists(), true, "Cancel preserves MIDI at the original path")
                compare(bootstrap.dockTrashedMidiExists(), false, "Cancel creates no MIDI trash entry")
            } else {
                if (branch === "opt-out") {
                    mouseClick(checkbox)
                    compare(checkbox.checked, false, "clicking the mounted checkbox opts out of bank deletion")
                }
                clickConfirmation()
                verify(waitForNative(function() {
                    return !controller().busy && presenter().rowCount === 9
                }, 30000), "confirmed deletion refreshes the mounted song listing")
                compare(row(deletedId), null, "confirmed deletion removes the selected row")
                compare(bootstrap.dockSongMidiExists(), false, "confirmed deletion removes the original MIDI path")
                compare(fileProbe.fileFingerprint(bootstrap.projectRoot + "/.porydaw/trash/mus_stray_test.mid"),
                        "471:d31e7c4a0a32a53f", "the disclosed trash destination contains the original MIDI bytes")
                if (branch === "opt-out") {
                    compare(fileProbe.fileFingerprint(bootstrap.projectRoot + "/sound/voicegroups/fixture_songs_dock.inc"),
                            expected[4], "opt-out preserves the literal complete bank source")
                } else {
                    compare(bootstrap.dockVoicegroupExists(), false, "opt-in removes the unused bank source")
                }
                // Removing the sole include leaves one newline byte in the hub.
                const expectedHub = branch === "opt-in" ? "1:af63c74c8601c8dd" : expected[3]
                compare(fileProbe.fileFingerprint(bootstrap.projectRoot + "/sound/voice_groups.inc"),
                        expectedHub, "acceptance removes exactly the optional bank include-hub entry")
            }
            cleanup()
        }
    }

    function test_charmapOnlyRegisterAndReopen() {
        verify(bootstrap.prepareSongActionFixture("charmap"),
               "the isolated charmap-only fixture stages")
        const root = bootstrap.projectRoot
        const charmap = root + "/charmap.txt"
        compare(fileProbe.fileFingerprint(charmap), "273:9f0b840cb4f4a2c0",
                "the independently seeded charmap omits exactly the registered song")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the action fixture opens a production shell")
        const session = shell.shellPresenter.session
        session.openProject(root)
        verify(waitForNative(function() { return session.projectOpen && presenter().rowCount === 8 }, 30000),
               "the charmap-only project loads its eight playable registered songs")
        const id = 2
        verify(row(id) !== null, "the registered route song is listed")
        compare(row(id).song.text, "mus_route101  ⚠ not fully registered",
                "A014: the registered song remains partial rather than becoming an unregistered stray")
        compare(row(id).song.registrationGapText, "charmap.txt",
                "A015: the partial registered song is missing only charmap.txt")
        compare(row(id).song.label, "mus_route101",
                "A016: the partially registered song remains listed under its original label")
        mouseDoubleClickSequence(row(id), row(id).width / 2, row(id).height / 2, Qt.LeftButton)
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 1
                && session.songTabs.selectedPage.title === "mus_route101"
        }, 30000), "A011: the original registered song opens in an editor tab before its charmap repair")
        compare(presenter().canRegister(id), true,
                "A012: Register is enabled for the open song with only a charmap gap")
        mouseClick(row(id), 4, 4, Qt.RightButton)
        const menu = findChild(shell, "songListContextMenu")
        compare(menu.contentItem.rowItem(3).enabled, true,
                "the real context menu enables Register on the charmap-only row")
        menuAction("register")
        verify(waitForNative(function() {
            const dialog = findChild(shell, "songConfirmationDialog")
            return controller().confirmation === "register" && dialog !== null && dialog.visible
        }, 5000), "A017: the mounted Register confirmation appears for the charmap-only plan")
        const confirmation = findChild(shell, "songConfirmationDialog")
        verify(confirmation.standardButton(Dialog.Ok) !== null,
               "A018: the mounted Register confirmation has an activatable accepting button")
        verify(presenter().canRegister(id)
               && controller().confirmationDetail ===
                   "The following registration files need updates:\n  - charmap.txt",
               "A006: the mounted registration plan applies to the charmap and no other missing file")
        compare(fileProbe.fileFingerprint(charmap), "273:9f0b840cb4f4a2c0",
                "the plan leaves the stripped charmap unchanged before acceptance")
        clickConfirmation()
        verify(waitForNative(function() {
            return !controller().busy && row(id) !== null
                && row(id).song.registrationGapText === ""
                && !row(id).song.warning && !presenter().canRegister(id)
        }, 30000), "A019: accepting Register refreshes the listed song to complete registration with Register disabled")
        compare(fileProbe.fileBytesBase64(charmap),
                "TVVTX0RVTU1ZID0gMDAgMDAKTVVTX0xJVFRMRVJPT1RfVEVTVCA9IDAxIDAwCk1VU19ST1VURTEwMSA9IDAyIDAwCk1VU19ST1VURTEwMiA9IDAzIDAwCk1VU19HU0NfUk9VVEUzOCA9IDA0IDAwCk1VU19DQVVHSFQgPSAwNSAwMApNVVNfUEVUQUxCVVJHID0gMDYgMDAKTVVTX09MREFMRSA9IDA3IDAwCk1VU19HWU0gPSAwOCAwMApNVVNfU1VSRiA9IDA5IDAwCk1VU19WSUNUT1JZX1dJTEQgPSAwQSAwMApTRV9VU0VfSVRFTSA9IDBCIDAwClNFX1BDX0xPR0lOID0gMEMgMDAKU0VfRkFORkFSRV8xVFJLID0gMEQgMDAK",
                "A020: accepting Register restores every byte of the independently seeded complete charmap")
        session.songTabs.requestClose(session.songTabs.selectedId)
        verify(waitForNative(function() { return session.songTabs.tabCount === 0 }, 5000),
               "the clean registered song tab closes before a fresh open")
        mouseClick(row(id), 4, 4, Qt.RightButton)
        compare(menu.contentItem.rowItem(3).enabled, false,
                "the mounted Register menu is disabled after the completed repair")
        menuAction("open")
        verify(waitForNative(function() {
            return session.projectOpen && session.songTabs.tabCount === 1
                && session.songTabs.selectedPage.title === "mus_route101"
        }, 30000), "A023: reopening the repaired song restores an enabled project and a ready editor tab")
        compare(presenter().canRegister(id), false,
                "A024: reopening the fully registered song keeps Register disabled")
    }

    function test_openRegisteredSongDeletion() {
        verify(bootstrap.prepareSongActionFixture("open-delete"),
               "the isolated registered deletion fixture stages")
        const root = bootstrap.projectRoot
        const midi = root + "/sound/songs/midi/mus_route101.mid"
        compare(fileProbe.fileFingerprint(midi), "471:d31e7c4a0a32a53f",
                "the original registered MIDI starts with the fixed fixture bytes")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the mounted shell opens the registered deletion fixture")
        const session = shell.shellPresenter.session
        session.openProject(root)
        verify(waitForNative(function() { return session.projectOpen && presenter().rowCount === 8 }, 30000),
               "the deletion fixture lists all eight playable originals")
        const id = 2
        mouseDoubleClickSequence(row(id), row(id).width / 2, row(id).height / 2, Qt.LeftButton)
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 1
                && session.songTabs.selectedPage.title === "mus_route101"
        }, 30000), "A033: the registered clean deletion candidate opens in its named editor tab")
        const originalTabId = session.songTabs.selectedId
        mouseClick(row(id), 4, 4, Qt.RightButton)
        menuAction("delete")
        verify(waitForNative(function() { return controller().confirmation === "delete" }, 5000),
               "A042: the open song raises the mounted deletion confirmation")
        const dialog = findChild(shell, "songConfirmationDialog")
        verify(dialog !== null && dialog.visible && dialog.standardButton(Dialog.Ok) !== null,
               "A043: the deletion confirmation exposes its visible accepting button")
        clickConfirmation()
        verify(waitForNative(function() {
            return !controller().busy && session.songTabs.tabCount === 0
                && session.songTabs.selectedId !== originalTabId
        }, 30000), "A045: accepting deletion closes the original clean open song tab")
        compare(row(id), null, "A046: deletion removes the original song row from the mounted list")
        compare(presenter().rowCount, 7, "A047: deleting one song decreases the listed count by exactly one")
        compare(bootstrap.actionMidiExists(), false,
                "A048: deleting the song removes its original MIDI path")
        compare(fileProbe.fileFingerprint(root + "/.porydaw/trash/mus_route101.mid"),
                "471:d31e7c4a0a32a53f",
                "A049: deletion leaves the original MIDI bytes at the named trash path")
    }

    function test_fallbackDeletionRefusedWithOpenTab() {
        verify(bootstrap.prepareSongActionFixture("fallback"),
               "the isolated fallback fixture stages its playable ID-zero MIDI")
        const root = bootstrap.projectRoot
        const paths = ["sound/song_table.inc", "include/constants/songs.h", "ld_script.ld",
                       "charmap.txt", "sound/songs/midi/midi.cfg", "src/debug.c"]
        const expected = ["732:4efe265a89789cea", "423:7e4eec643bee2aa",
                          "761:755b12f592bddb60", "294:863a4ea898d33ff6",
                          "615:2d0bb9be3c185b9e", "580:1d158bbea527b04f"]
        compare(JSON.stringify(paths.map(path => fileProbe.fileFingerprint(root + "/" + path))),
                JSON.stringify(expected), "the six literal fallback project images are staged")
        const midi = root + "/sound/songs/midi/mus_dummy.mid"
        compare(fileProbe.fileFingerprint(midi), "471:d31e7c4a0a32a53f",
                "the playable fallback MIDI starts with independently fixed bytes")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the fallback fixture opens a production shell")
        const session = shell.shellPresenter.session
        session.openProject(root)
        verify(waitForNative(function() { return session.projectOpen && presenter().rowCount === 9 }, 30000),
               "the project lists its newly playable ID-zero fallback")
        const id = 0
        mouseDoubleClickSequence(row(id), row(id).width / 2, row(id).height / 2, Qt.LeftButton)
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 1
                && session.songTabs.selectedPage.title === "mus_dummy"
        }, 30000), "the song-table ID-zero fallback opens in its own clean tab")
        const tabId = session.songTabs.selectedId
        mouseClick(row(id), 4, 4, Qt.RightButton)
        menuAction("delete")
        verify(waitForNative(function() {
            return findChild(shell, "shellCriticalDialog").visible
                && shell.shellPresenter.statusText.indexOf("mus_dummy") >= 0
        }, 5000), "A035: fallback deletion raises a refusal identifying mus_dummy")
        const refusal = findChild(shell, "shellCriticalDialog")
        compare(refusal.informativeText.indexOf("mus_dummy") >= 0, true,
                "the visible refusal identifies the protected song rather than a blank error")
        refusal.close()
        compare(session.songTabs.selectedId, tabId,
                "A038: rejecting fallback deletion retains the original open tab")
        compare(JSON.stringify(paths.map(path => fileProbe.fileFingerprint(root + "/" + path))),
                JSON.stringify(expected),
                "A039: fallback refusal preserves exact table, header, linker, charmap, flags and debug bytes")
        compare(fileProbe.fileFingerprint(midi), "471:d31e7c4a0a32a53f",
                "A041: fallback refusal retains its original playable MIDI bytes")
        compare(presenter().rowCount, 9,
                "the fallback refusal retains all nine playable rows in the mounted list")
    }

    function test_mountedSongDockAndConfirmationRoundTrips() {
        verify(bootstrap.prepareSongDockFixture(), "staged project has a stray and partial registration")
        const settings = bootstrap.preferences
        settings.setString("lastProjectDir", "")
        settings.setInt("swiftDock.columnWidth", 280)
        settings.setDouble("swiftDock.songsRatio", 0.5)
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production window loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const session = shell.shellPresenter.session
        compare(panel().baseFontPx, session.baseFontPx,
                "Songs pane derives its geometry from the captured session base before project open")
        compare(panel().pad, session.layoutSpaces.one,
                "Songs pane margins follow the published One token")
        compareRole(findChild(shell, "songListSearch"), "body", "song search")
        compareRole(findChild(shell, "songListCategory"), "body", "song category")
        compareRole(findChild(shell, "songListSort"), "body", "song sort")
        compareRole(findChild(shell, "songListCount"), "body", "song count")
        compare(findChild(shell, "songListSearch").height,
                Math.ceil(session.baseFontPx * (1.5 + 1 / 3)),
                "song search height follows the captured base")
        compare(findChild(shell, "songListSort").width, session.baseFontPx * 7.25,
                "song sort width follows the captured base")
        session.openProject(bootstrap.projectRoot)
        verify(waitForNative(function() { return session.projectOpen || session.lastSaveError.length > 0 }, 30000),
               "fixture project opens: " + session.lastSaveError)
        verify(session.projectOpen, "opening the project mounts its song feed")
        verify(waitForNative(function() { return presenter().rowCount === 10 }, 5000),
               "the live list contains eight registered songs, a partial and a stray")
        const dock = findChild(shell, "swiftDockColumn")
        verify(dock !== null && panel() !== null, "Songs is the first pane of the vertical dock")
        compare(dock.width, 280, "restored dock column starts at its default width")
        const emptyMessage = findChild(shell, "shellEmptySongMessage")
        verify(emptyMessage !== null && emptyMessage.visible,
               "empty-song guidance is shown before opening an editor")
        verify(emptyMessage.mapToItem(shell.contentItem, 0, 0).x >= dock.width,
               "empty-song guidance stays over the editor, not the Songs dock")
        for (let step = 0; step < 6 && Math.abs(panel().height - 480) > 1; ++step) {
            shell.height += 2 * (480 - panel().height)
            wait(200)
        }
        tryVerify(function() { return Math.abs(panel().height - 480) <= 1 }, 3000,
                  "the Songs pane reaches its visual baseline height")
        waitForRendering(panel())
        const actualDpr = Math.round(panel().Screen.devicePixelRatio)
        const actualFontPx = Math.round(panel().baseFontPx)
        const referenceJson = bootstrap.songListBaselineJson(actualDpr, actualFontPx)
        verify(referenceJson.length > 0,
               "missing Songs widget baseline for mounted DPR " + actualDpr
                   + " and font " + actualFontPx + "px")
        const baseline = JSON.parse(referenceJson)
        compare(baseline.environment.fontPx, actualFontPx, "widget font profile matches the dock")
        compare(baseline.image.dpr, actualDpr, "widget DPR profile matches the mounted pane")
        compareRegion(baseline, "songListSearch", findChild(shell, "songListSearch"), 3)
        compareRegion(baseline, "songListCategory", findChild(shell, "songListCategory"), 3)
        compareRegion(baseline, "songListSort", findChild(shell, "songListSort"), 3)
        compareRegion(baseline, "songList", list(), 3)
        compareRegion(baseline, "songListCount", findChild(shell, "songListCount"), 3)
        const firstId = presenter().songId(0)
        const secondId = presenter().songId(1)
        const thirdId = presenter().songId(2)
        tryVerify(function() { return !!row(firstId) && !!row(secondId) }, 5000,
                  "the first two live song delegates are rendered")
        compare(row(firstId).objectName, "songListRow_" + firstId,
                "the rendered delegate identifies the first catalog song")
        compareRegion(baseline, "songs.row.first", row(firstId), 3)
        compareRole(row(firstId), "body", "song row")
        compareRole(row(firstId).contentItem, "body", "song row text")
        compare(row(firstId).height, Math.ceil(session.baseFontPx * 9 / 8),
                "song row height follows the captured base")
        compareRegion(baseline, "songs.row.second", row(secondId), 3)
        // The service assigns the partial song an earlier ID than the stray.
        // Compare the two warning-row slots independent of their label order.
        const firstWarningId = presenter().songId(8)
        const secondWarningId = presenter().songId(9)
        compareRegion(baseline, "songs.row.unregistered", row(firstWarningId), 3)
        compareRegion(baseline, "songs.row.partial", row(secondWarningId), 3)
        compareRole(row(firstWarningId).contentItem, "body", "unregistered song row text")
        compare(row(firstWarningId).height, Math.ceil(session.baseFontPx * 11 / 8),
                "warning song row height follows the captured base")
        const image = grabImage(shell.contentItem)
        const warningRow = row(firstWarningId)
        const origin = warningRow.mapToItem(shell.contentItem, 0, 0)
        const scale = image.width / shell.contentItem.width
        // The legacy amber #C08030 sat 2.0:1 on the window; the warning ink is
        // the theme's warningText (docs/adr/0002-text-contrast-first.md).
        const warningInk = Qt.color(shell.shellPresenter.session.palette.warningText)
        let paintedWarning = false
        for (let y = Math.floor(origin.y * scale);
            y < Math.ceil((origin.y + warningRow.height) * scale) && !paintedWarning; ++y) {
            for (let x = Math.floor(origin.x * scale);
                x < Math.ceil((origin.x + warningRow.width) * scale); ++x) {
                if (Math.abs(image.red(x, y) - Math.round(warningInk.r * 255)) <= 3
                    && Math.abs(image.green(x, y) - Math.round(warningInk.g * 255)) <= 3
                    && Math.abs(image.blue(x, y) - Math.round(warningInk.b * 255)) <= 3) {
                    paintedWarning = true
                    break
                }
            }
        }
        verify(paintedWarning, "the mounted warning row paints the theme warning ink")
        const category = findChild(shell, "songListCategory")
        compare(category.displayText, "All (10)",
                "the visible category caption updates after loading the project")
        verify(typeof presenter().selectCategory === "function",
               "the mounted Songs presenter exports category selection to QML")
        presenter().selectCategory(1)
        tryCompare(presenter(), "categoryIndex", 1, 3000)
        tryCompare(presenter(), "rowCount", 7, 3000)
        presenter().selectCategory(0)
        tryCompare(presenter(), "categoryIndex", 0, 3000)
        tryCompare(presenter(), "rowCount", 10, 3000)
        compare(category.currentIndex, 0, "the mounted combo follows the restored All category")
        mouseClick(category)
        verify(category.popup.visible, "category choices open on the mounted combo")
        const musicChoice = category.popup.contentItem.itemAtIndex(1)
        verify(musicChoice !== null && musicChoice.text.indexOf("Music") === 0,
               "the second category is the mounted Music choice")
        compareRole(musicChoice, "body", "category popup delegate")
        mouseClick(musicChoice)
        compare(category.currentIndex, 1, "the clicked category is selected in the mounted combo")
        tryCompare(presenter(), "categoryIndex", 1, 3000)
        tryCompare(presenter(), "rowCount", 7, 3000)
        mouseClick(category)
        mouseClick(category.popup.contentItem.itemAtIndex(0))
        tryCompare(presenter(), "rowCount", 10)
        const sort = findChild(shell, "songListSort")
        mouseClick(sort)
        mouseClick(sort.popup.contentItem.itemAtIndex(1))
        tryCompare(presenter(), "sortIndex", 1, 3000)
        verify(presenter().songId(0) !== firstId, "alphabetical sort changes the first visible song")
        mouseClick(sort)
        mouseClick(sort.popup.contentItem.itemAtIndex(0))
        compare(presenter().songId(0), firstId, "ID order restores the snapshot order")

        mouseDoubleClickSequence(row(firstId), row(firstId).width / 2,
                                 row(firstId).height / 2, Qt.LeftButton)
        verify(waitForNative(function() { return session.songTabs.tabCount === 1 }, 30000),
               "double-click opens the first song in the current tab")
        tryCompare(emptyMessage, "visible", false, 3000,
                   "the guidance hides when a song opens")
        mouseClick(row(secondId), 4, 4, Qt.RightButton)
        const typographyMenu = findChild(shell, "songListContextMenu")
        compareRole(typographyMenu, "body", "song context menu")
        const openAction = typographyMenu.contentItem.rowItem(0)
        compareRole(openAction.children.find(child => child.text === qsTr("Open")),
                    "body", "song context action text")
        compare(typographyMenu.contentItem.rowHeight, Math.ceil(session.baseFontPx * 1.7),
                "song context action height follows the captured base")
        menuAction("newTab")
        verify(waitForNative(function() { return session.songTabs.tabCount === 2 }, 5000),
               "Open in New Tab preserves the existing tab (tabs="
                   + session.songTabs.tabCount + ", error=" + session.lastSaveError
                   + ", requested ID=" + secondId + ")")
        mouseClick(row(thirdId), 4, 4, Qt.RightButton)
        menuAction("open")
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 2
                && session.songTabs.selectedPage.title === row(thirdId).song.label
        }, 30000), "Open replaces the current clean tab, rather than appending another")

        shell.shellPresenter.activate("songs.find")
        const search = findChild(shell, "songListSearch")
        tryCompare(search, "activeFocus", true, 3000)
        const wasPlaying = session.playheadPresenter().playing
        keyClick(Qt.Key_Space)
        compare(search.text, " ", "a focused search retains literal Space as text")
        compare(session.playheadPresenter().playing, wasPlaying,
                "literal search Space does not toggle transport")
        keyClick(Qt.Key_Backspace)
        compare(search.text, "", "deleting the space restores the empty query")
        list().forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(list(), "activeFocus", true, 3000)
        keyClick(Qt.Key_Space)
        tryVerify(function() { return session.playheadPresenter().playing !== wasPlaying }, 3000,
                  "bare Space on the list reaches the window transport")
        session.stop()
        shell.shellPresenter.activate("songs.find")
        tryCompare(search, "activeFocus", true, 3000)
        keyClick(Qt.Key_Down)
        compare(presenter().selectedSongId, presenter().songId(list().currentIndex),
                "Down from search navigates the list without moving text focus")
        verify(search.activeFocus, "list navigation keeps search focus")
        keyClick(Qt.Key_S)
        keyClick(Qt.Key_T)
        keyClick(Qt.Key_R)
        keyClick(Qt.Key_A)
        keyClick(Qt.Key_Y)
        tryCompare(presenter(), "rowCount", 1)
        compare(list().count, 1, "search filters the mounted rows")
        const strayId = presenter().songId(0)
        presenter().updateSearch("")
        tryCompare(presenter(), "rowCount", 10)
        const stray = row(strayId)
        verify(stray !== null && stray.song.warning, "unregistered song wears the warning badge")
        const beforeRegistration = registrationBytes()
        mouseClick(stray, 4, 4, Qt.RightButton)
        compare(presenter().selectedSongId, strayId,
                "right-click on the recovered stray row selects it")
        menuAction("register")
        verify(waitForNative(function() { return controller().confirmation === "register" }, 5000),
               "registration plan reaches the confirmation")
        verify(controller().confirmationDetail.indexOf("song_table.inc") >= 0,
               "the dialog names the missing registration file")
        const confirmation = findChild(shell, "songConfirmationDialog")
        const bodyFont = session.typographyFonts.body
        verify(confirmation !== null, "song confirmation mounts after Register")
        for (const name of ["songConfirmationPrompt", "songConfirmationDetail"]) {
            const label = findChild(confirmation, name)
            compare(label.font.family, bodyFont.family, name + " inherits body family")
            compare(label.font.pixelSize, bodyFont.pixelSize, name + " inherits body size")
            compare(label.font.weight, bodyFont.weight, name + " inherits regular weight")
        }
        compare(confirmation.contentItem.spacing, session.layoutSpaces.four,
                "confirmation content uses the Four spacing token")
        compare(JSON.stringify(registrationBytes()), JSON.stringify(beforeRegistration),
                "opening Register stages a plan without changing table, header or config bytes")
        const cancelButton = confirmation.standardButton(Dialog.Cancel)
        verify(cancelButton !== null, "the mounted Register confirmation offers Cancel")
        mouseClick(cancelButton)
        compare(controller().confirmation, "", "Cancel leaves the staged project unchanged")
        compare(JSON.stringify(registrationBytes()), JSON.stringify(beforeRegistration),
                "clicking Cancel preserves the exact table, header and config bytes")
        tryCompare(findChild(shell, "songConfirmationLoader"), "status", Loader.Null, 3000)
        compare(presenter().canRegister(strayId), true, "cancel leaves Register enabled")
        mouseClick(row(strayId), 4, 4, Qt.RightButton)
        menuAction("register")
        verify(waitForNative(function() { return controller().confirmation === "register" }, 5000),
               "a second registration plan is prepared")
        compare(JSON.stringify(registrationBytes()), JSON.stringify(beforeRegistration),
                "reopening Register still leaves project bytes untouched before acceptance")
        clickConfirmation()
        verify(waitForNative(function() {
            return !controller().busy && !presenter().canRegister(strayId)
        }, 30000), "confirmed registration refreshes the badge")
        const afterRegistration = registrationBytes()
        verify(afterRegistration[0] !== beforeRegistration[0],
               "Accept changes the song table after the mounted confirmation")
        compare(afterRegistration[2], beforeRegistration[2],
                "Accept leaves the MIDI config byte-identical")
        verify(afterRegistration[1] !== beforeRegistration[1],
               "Accept changes songs.h after the mounted confirmation")
        mouseClick(row(strayId), 4, 4, Qt.RightButton)
        menuAction("delete")
        verify(waitForNative(function() { return controller().confirmation === "delete" }, 5000),
               "delete plan reaches the warning confirmation")
        verify(controller().confirmationDetail.indexOf(".porydaw/trash") >= 0,
               "delete discloses where the MIDI file moves")
        compare(controller().deletableVoicegroup, "fixture_songs_dock",
                "an unused song-specific voicegroup is offered for deletion")
        const voicegroupOption = findChild(shell, "songDeleteVoicegroup")
        verify(voicegroupOption !== null && voicegroupOption.visible && voicegroupOption.checked,
               "the real delete dialog defaults to including the unused voicegroup")
        compare(voicegroupOption.font.family, bodyFont.family,
                "delete voicegroup option inherits the body family")
        compare(voicegroupOption.font.pixelSize, bodyFont.pixelSize,
                "delete voicegroup option inherits the body size")
        compare(voicegroupOption.font.weight, bodyFont.weight,
                "delete voicegroup option keeps regular body weight")
        clickConfirmation()
        verify(waitForNative(function() { return !controller().busy && presenter().rowCount === 9 }, 30000),
               "confirmed deletion removes the song from the refreshed listing")
        tryCompare(category, "displayText", "All (9)", 3000,
                   "the mounted category caption refreshes after deletion")
        verify(row(strayId) === null, "the deleted song is no longer painted in the dock")
        verify(!bootstrap.dockSongMidiExists() && bootstrap.dockTrashedMidiExists(),
               "deletion moves the .mid to .porydaw/trash")
        verify(!bootstrap.dockVoicegroupExists(),
               "deleting with the checked option removes the unused voicegroup source")
    }

    function test_songFiltersSurviveShellRelaunch() {
        const settings = bootstrap.preferences
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        const session = shell.shellPresenter.session
        session.openProject(bootstrap.projectRoot)
        verify(waitForNative(function() { return session.projectOpen }, 30000),
               "the filter fixture project opens")
        const search = findChild(shell, "songListSearch")
        const sort = findChild(shell, "songListSort")
        verify(search && sort && findChild(shell, "songListCategory"),
               "the mounted Songs filters are available")
        search.forceActiveFocus()
        for (const key of [Qt.Key_R, Qt.Key_O, Qt.Key_U, Qt.Key_T, Qt.Key_E])
            keyClick(key)
        tryCompare(presenter(), "searchText", "route")
        sort.currentIndex = 1
        presenter().selectSort(1)
        presenter().selectCategory(1)
        const prefix = presenter().categoryPrefix()
        verify(prefix !== "", "the mounted Songs panel selects a real category")
        cleanup()
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        const restored = shell.shellPresenter.session
        restored.openProject(bootstrap.projectRoot)
        verify(waitForNative(function() { return restored.projectOpen }, 30000))
        tryVerify(function() {
            return findChild(shell, "songListSearch").text === "route"
                && presenter().searchText === "route"
                && findChild(shell, "songListSort").currentIndex === 1
                && presenter().sortIndex === 1
                && presenter().categoryPrefix() === prefix
                && findChild(shell, "songListCategory").currentIndex === presenter().categoryIndex
                && presenter().categoryIndex > 0
        }, 3000, "song filter text, sort and category restore across a fresh shell session")
        const reopenedCategoryBox = findChild(shell, "songListCategory")
        verify(reopenedCategoryBox !== null && reopenedCategoryBox.count > 1,
               "the reopened Songs browser still lists more than one category")
        cleanup()
        settings.setString("songFilterText", "")
        settings.setInt("songFilterSort", 0)
        settings.setString("songFilterCategory", "")
    }

    function test_unknownStoredSongCategoryFallsBackToAll() {
        const settings = bootstrap.preferences
        settings.setString("lastProjectDir", "")
        settings.setString("songFilterCategory", "zz")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        const session = shell.shellPresenter.session
        session.openProject(bootstrap.projectRoot)
        verify(waitForNative(function() { return session.projectOpen }, 30000))
        tryCompare(presenter(), "categoryIndex", 0)
        compare(presenter().categoryPrefix(), "",
                "a restored category the project does not have falls back to all songs")
    }

    function test_constrainedVoiceEditorRemainsScrollable() {
        const settings = bootstrap.preferences
        settings.setString("lastProjectDir", "")
        settings.setInt("swiftDock.columnWidth", 280)
        settings.setDouble("swiftDock.songsRatio", 0.5)
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production window loads")
        shell.height = 380
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() { return session.songOpen || session.lastSaveError.length > 0 },
                             30000), "the fixture bank loads: " + session.lastSaveError)
        compare(session.lastSaveError, "")
        const dock = findChild(shell, "swiftDockColumn")
        const scroll = findChild(shell, "voiceEditorScrollView")
        const editor = findChild(shell, "voicegroupEditorSurface")
        verify(editor !== null, "the form is mounted inside the scroller")
        verify(dock !== null && scroll !== null, "the mounted voice pane has an editor scroller")
        compare(dock.width, 280, "selecting a voice never expands the saved dock width")
        const voice = session.voiceListController()
        tryCompare(voice, "isBound", true, 5000)
        for (const slot of [4, 0]) {
            voice.selectSlot(slot)
            tryCompare(voice.editorModel(), "editable", true, 5000,
                       "the chosen bank voice becomes editable after loading")
            waitForRendering(editor)
            tryVerify(function() { return scroll.contentHeight > scroll.height + 1 }, 3000,
                      "the selected form extends below the constrained viewport: "
                      + scroll.contentHeight + " vs " + scroll.height)
            scroll.contentY = 0
            const type = findChild(shell, "vgTypeCombo")
            verify(type !== null && type.visible, "the type selector is mounted")
            const top = type.mapToItem(scroll, 0, 0)
            verify(top.y >= 0 && top.y + type.height <= scroll.height + 1,
                   "the type selector is visible at the start of the form")
            mouseWheel(scroll, 1, scroll.height / 2, 0, -120)
            tryVerify(function() { return scroll.contentY > 0 }, 3000,
                      "a wheel gesture advances the constrained editor form")
            scroll.contentY = scroll.contentHeight - scroll.height
            const release = findChild(editor, "vgReleaseSpin")
            verify(release !== null && release.visible, "the release control is mounted")
            const origin = release.mapToItem(scroll, 0, 0)
            verify(origin.y >= 0 && origin.y + release.height <= scroll.height + 1
                   && origin.x >= 0 && origin.x + release.width <= scroll.width + 1,
                   "the release control is reachable within the dock's viewport")
            compare(dock.width, 280, "CGB and DirectSound selection keep the saved width")
        }
    }

    function test_voicegroupPaneStackedAndRatioRestores() {
        const settings = bootstrap.preferences
        settings.setString("lastProjectDir", "")
        settings.setInt("swiftDock.columnWidth", 280)
        settings.setDouble("swiftDock.songsRatio", 0.3)
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production window loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const dock = findChild(shell, "swiftDockColumn")
        const songs = findChild(shell, "swiftSongsPanel")
        const voice = findChild(shell, "voicegroupPanel")
        verify(dock !== null && songs !== null && voice !== null,
               "Songs and Voicegroup panes mount in the dock column")
        function insideDock(item) {
            let host = item.parent
            for (let i = 0; i < 4 && host; ++i) {
                if (host === dock) return true
                host = host.parent
            }
            return false
        }
        verify(insideDock(songs) && insideDock(voice),
               "both panes are stacked in swiftDockColumn")
        tryVerify(function() {
            return voice.mapToItem(dock, 0, 0).y >= songs.mapToItem(dock, 0, 0).y + songs.height
                && Math.abs(songs.height / dock.height - 0.3) < 0.06
        }, 3000, "the voicegroup pane sits below Songs with the restored swiftDock/songsRatio")
    }
}
