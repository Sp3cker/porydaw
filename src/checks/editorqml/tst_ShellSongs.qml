import QtCore
import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import "../../ui/shell"

TestCase {
    id: testCase
    name: "ShellSongs"
    when: windowShown
    width: 1100
    height: 720
    visible: true

    property var shell: null
    ShellQmlBootstrap { id: bootstrap }
    Component { id: settingsComponent; Settings {} }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 550; visible: true } }

    function waitForNative(predicate, timeoutMs) {
        const deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
    }

    function cleanupTestCase() {
        verify(bootstrap.clearSettings(), "private settings domain removed")
    }

    function cleanup() {
        if (!shell)
            return
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

    function test_mountedSongDockAndConfirmationRoundTrips() {
        verify(bootstrap.prepareSongDockFixture(), "staged project has a stray and partial registration")
        const settings = settingsComponent.createObject(testCase)
        verify(settings !== null, "QtCore settings is available")
        settings.setValue("lastProjectDir", "")
        settings.setValue("swiftDock/columnWidth", 280)
        settings.setValue("swiftDock/songsRatio", 0.5)
        settings.sync()
        settings.destroy()
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production window loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const session = shell.shellPresenter.session
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
        compareRegion(baseline, "songs.row.second", row(secondId), 3)
        // The service assigns the partial song an earlier ID than the stray.
        // Compare the two warning-row slots independent of their label order.
        const firstWarningId = presenter().songId(8)
        const secondWarningId = presenter().songId(9)
        compareRegion(baseline, "songs.row.unregistered", row(firstWarningId), 3)
        compareRegion(baseline, "songs.row.partial", row(secondWarningId), 3)
        const image = grabImage(shell.contentItem)
        const warningRow = row(firstWarningId)
        const origin = warningRow.mapToItem(shell.contentItem, 0, 0)
        const scale = image.width / shell.contentItem.width
        let paintedAmber = false
        for (let y = Math.floor(origin.y * scale);
            y < Math.ceil((origin.y + warningRow.height) * scale) && !paintedAmber; ++y) {
            for (let x = Math.floor(origin.x * scale);
                x < Math.ceil((origin.x + warningRow.width) * scale); ++x) {
                if (Math.abs(image.red(x, y) - 0xc0) <= 3
                    && Math.abs(image.green(x, y) - 0x80) <= 3
                    && Math.abs(image.blue(x, y) - 0x30) <= 3) {
                    paintedAmber = true
                    break
                }
            }
        }
        verify(paintedAmber, "the mounted warning row paints the QWidget amber foreground")
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
        mouseClick(stray, 4, 4, Qt.RightButton)
        compare(presenter().selectedSongId, strayId,
                "right-click on the recovered stray row selects it")
        menuAction("register")
        verify(waitForNative(function() { return controller().confirmation === "register" }, 5000),
               "registration plan reaches the confirmation")
        verify(controller().confirmationDetail.indexOf("song_table.inc") >= 0,
               "the dialog names the missing registration file")
        controller().cancelConfirmation()
        compare(controller().confirmation, "", "Cancel leaves the staged project unchanged")
        tryCompare(findChild(shell, "songConfirmationLoader"), "status", Loader.Null, 3000)
        compare(presenter().canRegister(strayId), true, "cancel leaves Register enabled")
        mouseClick(row(strayId), 4, 4, Qt.RightButton)
        menuAction("register")
        verify(waitForNative(function() { return controller().confirmation === "register" }, 5000),
               "a second registration plan is prepared")
        clickConfirmation()
        verify(waitForNative(function() {
            return !controller().busy && !presenter().canRegister(strayId)
        }, 30000), "confirmed registration refreshes the badge")
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

    function test_constrainedVoiceEditorRemainsScrollable() {
        const settings = settingsComponent.createObject(testCase)
        verify(settings !== null, "QtCore settings is available")
        settings.setValue("lastProjectDir", "")
        settings.setValue("swiftDock/columnWidth", 280)
        settings.setValue("swiftDock/songsRatio", 0.5)
        settings.sync()
        settings.destroy()
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
        const settings = settingsComponent.createObject(testCase)
        verify(settings !== null, "QtCore settings is available")
        settings.setValue("lastProjectDir", "")
        settings.setValue("swiftDock/columnWidth", 280)
        settings.setValue("swiftDock/songsRatio", 0.3)
        settings.sync()
        settings.destroy()
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
