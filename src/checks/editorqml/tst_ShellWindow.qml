import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellWindow"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    readonly property var settings: bootstrap.preferences

    ShellQmlBootstrap { id: bootstrap }
    SignalSpy { id: copyActivatedSpy; signalName: "activated" }
    SignalSpy { id: soloActivatedSpy; signalName: "activated" }

    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }
    Component { id: intrinsicShellComponent; ShellWindow { visible: true } }
    FontMetrics {
        id: footerCaptionMetrics
        font: shell ? Qt.font(shell.chromeTypography.caption) : Application.font
    }
    FontMetrics {
        id: footerBodyMetrics
        font: shell ? Qt.font(shell.chromeTypography.body) : Application.font
    }
    Component {
        id: textProbeComponent
        TextField { text: "native copy text probe"; width: 220; height: 32 }
    }
    Component {
        id: shortcutTargetComponent
        Item { width: 24; height: 24; focus: true }
    }
    Component {
        id: foreignWindowComponent
        Window {
            width: 320
            height: 120
            visible: true
            TextField {
                objectName: "foreignSoloField"
                x: 20
                y: 20
                width: 220
                height: 32
                text: "foreign draft"
            }
        }
    }


    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "the close-all walk reaches the dirty gate or completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() {
                return shell.shellPresenter.closeReady
            }, 5000), "teardown waits for scene destruction and grid detach")
        }
        copyActivatedSpy.target = null
        soloActivatedSpy.target = null
        shell.destroy()
        shell = null
        wait(0)
    }

    // Qt Quick Test waits pump Qt events but not Swift MainActor Tasks. Keep
    // production session calls intact and service the native event loop while
    // observing the same state the original checks require.
    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openTwoSongShell(beforeOpen) {
        settings.setBool("editorDrawer.velocityVisible", true)
        settings.setInt("editorDrawer.velocityHeight", 173)
        settings.setBool("editorDrawer.automationVisible", false)
        settings.setBool("editorDrawer.voiceChangesVisible", false)
        settings.setString("editorDrawer.activePage", "velocity")
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        if (beforeOpen)
            beforeOpen()
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songOpen, "Route 101 loads from the original mainwindowrouting project"
               + openDiagnostics(session))
        tryCompare(session.songTabs, "tabCount", 1)
        var firstId = session.songTabs.selectedId
        session.openSong("mus_littleroot_test")
        waitForNative(function() {
            return session.songTabs.tabCount === 2 || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songTabs.tabCount === 2,
               "Littleroot opens in the second tab of the same project"
               + openDiagnostics(session))
        tryVerify(function() { return session.songTabs.selectedId !== firstId }, 3000,
                  "Littleroot is the selected workspace")
        tryVerify(function() {
            var surface = selectedSurface()
            return surface !== null && surface.visible && surface.width > 0
        }, 5000, "the selected real tab page is mounted and drawn")
        return firstId
    }
    function openDiagnostics(session) {
        var labels = []
        for (var i = 0; i < session.songCount() && i < 8; ++i)
            labels.push(session.songLabel(i))
        return " (projectRoot=" + bootstrap.projectRoot
            + "; projectOpen=" + session.projectOpen
            + "; songOpen=" + session.songOpen
            + "; stagedLabels=[" + labels.join(",") + "]"
            + "; lastSaveError=" + session.lastSaveError
            + "; status=" + shell.shellPresenter.statusText + ")"
    }

    function selectedSurface() {
        var pages = shell.sceneLoader.item
        if (!pages)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(pages, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function selectDrawnVelocityNote(surface) {
        var drawer = surface.drawerPresenter
        var velocityKind = bootstrap.velocitySectionKind()
        tryCompare(drawer.section(velocityKind), "visible", true)
        var plot = null
        var node = null
        tryVerify(function() {
            plot = findChild(surface, "velocityPlotInput")
            node = findChild(surface, "velocityNodeFill")
            return plot !== null && node !== null && node.width > 0 && node.height > 0
        }, 3000, "the original velocity page draws a note hit target")
        var hit = node.mapToItem(plot, node.width / 2, node.height / 2)
        mouseClick(plot, hit.x, hit.y)
        tryCompare(shell.shellPresenter.session.velocityPage(), "selectedCount", 1, 3000)
    }

    function windowShortcut(name) {
        var delegates = shell.contentItem.children
        for (var i = 0; i < delegates.length; ++i) {
            var objects = delegates[i].data
            for (var j = 0; objects && j < objects.length; ++j) {
                if (objects[j].objectName === name)
                    return objects[j]
            }
        }
        return null
    }

    function test_savedWindowFrameRestoresAcrossShellSessions() {
        bootstrap.resetPreferences()
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        const screen = Qt.application.screens[0]
        shell.x = screen.virtualX + Math.floor(screen.width / 6)
        shell.y = screen.virtualY + Math.floor(screen.height / 6)
        shell.width = 850
        shell.height = 580
        const frame = [shell.x, shell.y, shell.width, shell.height]
        cleanup()
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        compare([shell.x, shell.y, shell.width, shell.height], frame,
                "a saved window frame restores across a fresh shell session")
    }

    function test_offscreenWindowFrameIsIgnored() {
        bootstrap.resetPreferences()
        settings.setString("windowGeometry", "-99999,-99999,850,580")
        shell = intrinsicShellComponent.createObject(null)
        verify(shell !== null)
        const session = shell.shellPresenter.session
        compare(shell.width === session.baseFontPx * 92 && shell.height === session.baseFontPx * 57,
                true, "an offscreen saved frame is ignored")
    }

    function test_maximizedAndDebuggerWindowStateRestores() {
        bootstrap.resetPreferences()
        settings.setString("windowState", "maximized,debugger")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        compare(shell.shellPresenter.windowMaximized && shell.visibility === Window.Maximized,
                true, "the maximized flag restores across a fresh shell session")
        compare(shell.shellPresenter.polyphonyVisible
                && findChild(shell, "shellPolyphonyDock").visible,
                true, "debugger visibility restores with the window state")
    }

    function test_sessionPreferencesRetainForkKeySpellings() {
        bootstrap.resetPreferences()
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        const transport = shell.shellPresenter.session.transportBarPresenter()
        transport.setFollowPlayhead(false)
        transport.setResonanceSuppression(true)
        transport.commitOutputVolume(72)
        const songs = shell.shellPresenter.session.songDockController().songListPresenter()
        songs.restoreFilters("route", 1, "mus_")
        shell.shellPresenter.polyphonyVisible = true
        cleanup()
        compare(settings.bool("followPlayhead", true) === false
                && settings.bool("dsp.resonanceSuppression", false) === true
                && settings.int("outputVolume", 0) === 72
                && settings.hasValue("windowGeometry") && settings.hasValue("windowState")
                && settings.string("songFilterText", "") === "route"
                && settings.int("songFilterSort", -1) === 1
                && settings.string("songFilterCategory", "") === "mus_"
                && !settings.hasValue("dsp/resonanceSuppression"),
                true, "preferences keep the fork's on-disk key spellings")
    }

    function test_chromeTypographyAndWindowGeometry() {
        bootstrap.resetPreferences()
        shell = intrinsicShellComponent.createObject(null)
        verify(shell !== null, "production window mounts at its natural size")
        const session = shell.shellPresenter.session
        const caption = session.typographyFonts.caption
        const body = session.typographyFonts.body
        const mono = session.typographyFonts.bodyMono
        compare(shell.width, session.baseFontPx * 92, "window width follows fontPx(92)")
        compare(shell.height, session.baseFontPx * 57, "window height follows fontPx(57)")
        compare(shell.chromeTypography.caption.pixelSize, caption.pixelSize,
                "shell role map follows captured session")
        compare(shell.font.pixelSize, body.pixelSize,
                "window font follows captured body role")
        const status = findChild(shell, "shellStatusText")
        const title = findChild(shell, "shellPolyphonyTitle")
        verify(status && title, "status and debugger heading are mounted")
        compare(status.font.family, caption.family, "status uses the caption family")
        compare(status.font.pixelSize, caption.pixelSize, "status uses the caption size")
        compare(status.font.weight, caption.weight, "status uses caption weight")
        compare(title.font.family, body.family, "debugger heading inherits body family")
        compare(title.font.pixelSize, body.pixelSize, "debugger heading inherits body size")
        compare(title.font.weight, body.weight, "debugger heading inherits body weight")
        for (const name of ["shellPolyPcmValue", "shellPolyCgbValue"]) {
            const value = findChild(shell, name)
            compare(value.font.family, mono.family, name + " uses the bodyMono family")
            compare(value.font.pixelSize, mono.pixelSize, name + " uses the bodyMono size")
            compare(value.font.weight, mono.weight, name + " uses bodyMono weight")
        }
        const lost = findChild(shell, "shellPolyLostValue")
        compare(lost.font.family, body.family, "lost notes inherit the body family")
        compare(lost.font.pixelSize, body.pixelSize, "lost notes inherit body size")
        const dock = findChild(shell, "shellPolyphonyDock")
        compare(dock.width, Math.min(session.baseFontPx * 32, shell.width * 0.48),
                "debugger width is bounded by the session base")
    }

    function test_aKeymapNativeSettingsSeeds() {
        settings.setString("keymap.roll·transpose_up", "Ctrl+Alt+U")
        settings.setString("keymap.transport·play_pause", "")
        settings.setString("keymap.roll·velocity_drag", "Shift")
        settings.setString("keymap.velocity·detent_unlock", "")
        settings.synchronize()
        compare(settings.string("keymap.roll·transpose_up", "?"), "Ctrl+Alt+U")
        compare(settings.string("keymap.transport·play_pause", "?"), "")
        compare(settings.string("keymap.roll·velocity_drag", "?"), "Shift")
        compare(settings.string("keymap.velocity·detent_unlock", "?"), "")
        var failures = bootstrap.registryFailures()
        compare(failures.length, 0, "the complete native keymap assertions: " + failures.join("; "))
    }

    function test_bThemeRepairThroughProductionShell() {
        // ThemeLayoutTest::settingsRepair: custom mode is obsolete, 80 survives,
        // and neither obsolete colour key survives restoration.
        settings.setString("theme.mode", "custom")
        settings.setString("theme.primary", "#000000")
        settings.setString("theme.accent", "#FFFFFF")
        settings.setString("theme.grid-line-contrast", "80")
        settings.setString("lastProjectDir", "")
        settings.synchronize()
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell restores the seeded native theme")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        tryCompare(shell.shellPresenter, "themeMode", "vanilla")
        compare(shell.shellPresenter.gridLineContrast, 80)
        tryVerify(function() {
            return settings.string("theme.mode", "") === "vanilla"
                && settings.int("theme.grid-line-contrast", -1) === 80
                && !settings.hasValue("theme.primary")
                && !settings.hasValue("theme.accent")
        }, 3000, "another native Settings reader observes repaired persisted keys")
        compare(settings.string("theme.mode", ""), "vanilla")
        compare(settings.int("theme.grid-line-contrast", -1), 80)
        compare(settings.hasValue("theme.primary"), false)
        compare(settings.hasValue("theme.accent"), false)
    }

    function test_cWindowShortcutsAndNumericOwnership() {
        var firstId = openTwoSongShell()
        var session = shell.shellPresenter.session
        var tabs = session.songTabs
        var secondId = tabs.selectedId
        var firstButton = findChild(shell.sceneLoader.item, "songTabSelect_" + firstId)
        var secondButton = findChild(shell.sceneLoader.item, "songTabSelect_" + secondId)
        verify(firstButton && secondButton, "the two original tab controls are drawn")
        mouseClick(firstButton, firstButton.width / 3, firstButton.height / 2)
        tryCompare(tabs, "selectedId", firstId, 3000,
                   "a real first-tab click retargets the selected workspace")
        mouseClick(secondButton, secondButton.width / 3, secondButton.height / 2)
        tryCompare(tabs, "selectedId", secondId, 3000,
                   "a real second-tab click restores Littleroot's workspace")

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
        var beforeCopy = JSON.parse(surface.gridModel.noteSummary)
        var copied = beforeCopy.filter(function(note) { return note.selected })
        compare(copied.length, 1, "the real node click selected one note")
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

        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Escape)
        tryCompare(session.velocityPage(), "selectedCount", 0, 3000,
                   "the native text probe starts with no musical selection")
        var textProbe = textProbeComponent.createObject(shell.contentItem, { x: 20, y: 20 })
        verify(textProbe, "the local text field is a child of the real window")
        textProbe.selectAll()
        textProbe.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(textProbe, "activeFocus", true, 3000)
        verify(bootstrap.clearClipboardProbe(), "the old song clip is cleared")
        keySequence(StandardKey.Copy)
        textProbe.text = ""
        textProbe.paste()
        compare(textProbe.text, "native copy text probe",
                "focused text Copy replaces the cleared clipboard with text")

        var shortcutTarget = shortcutTargetComponent.createObject(shell.contentItem,
                                                                  { x: 260, y: 20 })
        verify(shortcutTarget, "a non-text window child receives Solo")
        shortcutTarget.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(shortcutTarget, "activeFocus", true, 3000)
        keyClick(Qt.Key_S)
        tryCompare(firstTrack, "soloChecked", true, 3000)
        compare(soloActivatedSpy.count, 1, "first non-text S activates Solo once")
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
        textProbe.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(textProbe, "activeFocus", true, 3000)
        keyClick(Qt.Key_S)
        compare(firstTrack.soloChecked, false, "text-field S never changes Solo")
        compare(soloActivatedSpy.count, 4, "text-field S never activates Solo")
        textProbe.destroy()
        shortcutTarget.destroy()
        selectDrawnVelocityNote(surface)

        session.performGridCommand(bootstrap.setVelocityCommand())
        tryCompare(session.velocityPage(), "promptOpen", true, 3000)
        var field = findChild(surface, "noteVelocityInput")
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
        compare(copyActivatedSpy.count, windowCopyBeforePrompt,
                "prompt Copy/Paste never fire the window Copy action")
        compare(field.activeFocus, true, "local Copy/Paste retains numeric focus")
        keyClick(Qt.Key_S)
        compare(firstTrack.soloChecked, false, "S in a numeric editor never fires Solo")
        compare(session.velocityPage().promptOpen, true)
        keyClick(Qt.Key_Up)
        keyClick(Qt.Key_Down)
        compare(field.activeFocus, true, "prompt arrows keep focus in the numeric editor")
        compare(session.velocityPage().promptOpen, true)
        tryCompare(session.velocityPage(), "selectedCount", 1, 3000,
                   "prompt arrows keep the musical selection")
        compare(session.documentDirty, false, "prompt arrows never edit the song")
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
    }

    function test_cForeignWindowKeepsSoloLocal() {
        openTwoSongShell()
        var surface = selectedSurface()
        verify(surface && surface.visible, "the selected song page is mounted")
        var headers = findChild(surface, "timelineTrackHeaderRows")
        verify(headers && headers.count > 0, "the track headers are mounted")
        var firstTrack = headers.itemAt(surface.gridModel.trackIndex)
        verify(firstTrack && !firstTrack.isAddTrack, "the selected track is actionable")
        selectDrawnVelocityNote(surface)
        compare(firstTrack.soloChecked, false, "Solo starts off on the selected track")
        var soloShortcut = windowShortcut("shellShortcut_roll.solo_tracks")
        verify(soloShortcut, "the production window Solo shortcut is mounted")
        soloActivatedSpy.target = soloShortcut
        soloActivatedSpy.clear()

        var foreign = foreignWindowComponent.createObject(null)
        verify(foreign !== null, "the foreign window loads")
        try {
            foreign.requestActivate()
            tryCompare(foreign, "active", true, 3000)
            tryCompare(shell, "active", false, 3000)
            var field = findChild(foreign, "foreignSoloField")
            verify(field, "the foreign window has its own text field")
            field.selectAll()
            field.forceActiveFocus(Qt.OtherFocusReason)
            tryCompare(field, "activeFocus", true, 3000)
            keyClick(Qt.Key_S)
            tryCompare(field, "text", "s", 3000)
            compare(firstTrack.soloChecked, false,
                    "a foreign-window S does not Solo the main song")
            compare(soloActivatedSpy.count, 0,
                    "a foreign-window S never activates the main window shortcut")
        } finally {
            foreign.destroy()
        }
    }

    function test_dCopyFromOneSongTabPastesIntoAnother() {
        var firstId = openTwoSongShell()
        var tabs = shell.shellPresenter.session.songTabs
        var secondId = tabs.selectedId
        var source = selectedSurface()
        verify(source && source.gridModel, "the source tab has a grid")
        selectDrawnVelocityNote(source)
        var sourceSummary = source.gridModel.noteSummary
        var selected = JSON.parse(sourceSummary).filter(function(note) { return note.selected })
        compare(selected.length, 1, "one source note is selected")
        var sourceRoll = findChild(source, "swiftRollInput")
        sourceRoll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(sourceRoll, "activeFocus", true, 3000)
        keySequence(StandardKey.Copy)
        compare(JSON.parse(bootstrap.copiedClipSummary())[2], selected[0].pitch,
                "Copy places the selected source note on the host clipboard")

        var firstButton = findChild(shell.sceneLoader.item, "songTabSelect_" + firstId)
        verify(firstButton, "the destination tab control exists")
        mouseClick(firstButton, firstButton.width / 3, firstButton.height / 2)
        tryCompare(tabs, "selectedId", firstId, 3000)
        var destination = selectedSurface()
        verify(destination && destination.gridModel, "the destination tab has a grid")
        var destinationBefore = JSON.parse(destination.gridModel.noteSummary)
        var destinationIDs = destinationBefore.map(function(note) { return note.id })
        var destinationTrack = destination.gridModel.trackIndex
        var destinationRoll = findChild(destination, "swiftRollInput")
        destinationRoll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(destinationRoll, "activeFocus", true, 3000)
        keySequence(StandardKey.Paste)
        verify(waitForNative(function() {
            var notes = JSON.parse(destination.gridModel.noteSummary)
            return notes.some(function(note) {
                return destinationIDs.indexOf(note.id) < 0
                    && note.pitch === selected[0].pitch && note.track === destinationTrack
                    && note.selected
            })
        }, 5000), "Paste inserts and selects the copied note in the destination track")
        var destinationAfter = JSON.parse(destination.gridModel.noteSummary)
        var inserted = destinationAfter.filter(function(note) {
            return destinationIDs.indexOf(note.id) < 0
        })
        compare(inserted.length, 1, "Paste changes only the destination by one note")
        compare(destination.gridModel.editCursorTick, inserted[0].tick + inserted[0].duration,
                "Paste advances the destination edit cursor past the inserted note")

        var secondButton = findChild(shell.sceneLoader.item, "songTabSelect_" + secondId)
        verify(secondButton, "the source tab control still exists")
        mouseClick(secondButton, secondButton.width / 3, secondButton.height / 2)
        tryCompare(tabs, "selectedId", secondId, 3000)
        compare(selectedSurface().gridModel.noteSummary, sourceSummary,
                "cross-tab Paste leaves the source song unchanged")

        mouseClick(firstButton, firstButton.width / 3, firstButton.height / 2)
        tryCompare(tabs, "selectedId", firstId, 3000,
                   "the destination is active when the close-all walk begins")
        compare(shell.shellPresenter.session.documentDirty, true,
                "only the pasted destination has unsaved changes")
        shell.close()
        verify(waitForNative(function() {
            return tabs.pendingCloseId === firstId
        }, 5000), "the window close walk pauses at the dirty destination")
        compare(tabs.tabCount, 2, "the dirty gate cannot silently close a tab")
        compare(destination.gridModel.noteSummary, JSON.stringify(destinationAfter),
                "the dirty gate preserves the pasted note")
        var discard = findChild(shell, "songTabDiscard")
        verify(discard && discard.visible, "the close gate exposes Discard")
        mouseClick(discard, discard.width / 2, discard.height / 2)
        verify(waitForNative(function() {
            return shell.shellPresenter.closeReady && tabs.tabCount === 0
                && shell.sceneLoader.item === null
        }, 5000), "Discard advances the remaining clean tab and detaches the scene")
        compare(tabs.pendingCloseId, -1, "the close-all gate is fully resolved")
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
        compare(findChild(timeMenu, "shellAction_edit.insert_time").enabled, false,
                "an open song without a time selection cannot insert a selected range")
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
        var beforeSpace = grid.noteSummary
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000)
        compare(grid.pencilMode, true, "roll Space never unlatches the pencil")
        compare(automation.isPencilMode, true, "roll Space leaves automation pencil armed")
        compare(grid.noteSummary, beforeSpace, "roll Space never changes selected notes")
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
        var field = findChild(surface, "noteVelocityInput")
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

    function test_gEditorRoutedNoteKeysAndChromeArrows() {
        openTwoSongShell()
        var surface = selectedSurface()
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the focused roll receives editor keys")
        selectDrawnVelocityNote(surface)
        var grid = surface.gridModel
        var chosen = JSON.parse(grid.noteSummary).filter(function(note) { return note.selected })
        compare(chosen.length, 1, "the pointer selected one source note")
        var original = chosen[0]
        function selectedNote() {
            var selection = JSON.parse(grid.noteSummary).filter(function(note) {
                return note.selected && note.id === original.id
            })
            compare(selection.length, 1, "the edited source note stays selected")
            return selection[0]
        }
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_Up)
        compare(selectedNote().pitch, original.pitch + 1, "Up transposes one semitone")
        keyClick(Qt.Key_Down)
        compare(selectedNote().pitch, original.pitch, "Down reverses Up")
        keyClick(Qt.Key_Up, Qt.ShiftModifier)
        compare(selectedNote().pitch, original.pitch + 12, "Shift+Up transposes an octave")
        keyClick(Qt.Key_Down, Qt.ShiftModifier)
        compare(selectedNote().pitch, original.pitch, "Shift+Down reverses the octave")
        keyClick(Qt.Key_Right)
        verify(selectedNote().tick > original.tick, "Right nudges the selected note forward")
        keyClick(Qt.Key_Left)
        compare(selectedNote().tick, original.tick, "Left returns the selected note")
        keyClick(Qt.Key_Right, Qt.ShiftModifier)
        verify(selectedNote().duration > original.duration,
               "Shift+Right lengthens the selected note")
        keyClick(Qt.Key_Left, Qt.ShiftModifier)
        compare(selectedNote().duration, original.duration,
                "Shift+Left restores the selected note duration")

        var drawer = findChild(surface, "editorDrawer")
        var grip = findChild(drawer, "drawerHandle_velocity")
        verify(grip && grip.visible, "the drawer resize grip is available")
        grip.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(grip, "activeFocus", true, 3000)
        var beforeGrip = grid.noteSummary
        var heightBefore = surface.drawerPresenter.section(
                    bootstrap.velocitySectionKind()).bodyHeight
        keyClick(Qt.Key_Up)
        verify(surface.drawerPresenter.section(bootstrap.velocitySectionKind()).bodyHeight
               > heightBefore, "grip Up resizes the drawer locally")
        keyClick(Qt.Key_Down)
        compare(surface.drawerPresenter.section(bootstrap.velocitySectionKind()).bodyHeight,
                heightBefore, "grip Down restores its height")
        keyClick(Qt.Key_Left)
        keyClick(Qt.Key_Right)
        compare(grid.noteSummary, beforeGrip, "grip arrows never mutate selected notes")
    }

    function test_hKeyboardFocusAndDrawerSpacePriority() {
        var firstId = openTwoSongShell()
        var surface = selectedSurface()
        var roll = findChild(surface, "swiftRollInput")
        var drawer = findChild(surface, "editorDrawer")
        var toggle = findChild(drawer, "drawerToggle_velocity")
        verify(roll && toggle, "the roll and drawer chrome are visible")
        var tabs = shell.shellPresenter.session.songTabs
        var secondId = tabs.selectedId
        var firstButton = findChild(shell.sceneLoader.item, "songTabSelect_" + firstId)
        var secondButton = findChild(shell.sceneLoader.item, "songTabSelect_" + secondId)
        verify(firstButton && secondButton, "the production tab buttons are mounted")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        var noteSnapshot = surface.gridModel.noteSummary
        var playhead = shell.shellPresenter.session.playheadPresenter()
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000)
        compare(surface.gridModel.noteSummary, noteSnapshot, "roll Space leaves notes unchanged")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000)

        toggle.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(toggle, "activeFocus", true, 3000)
        var section = surface.drawerPresenter.section(bootstrap.velocitySectionKind())
        var sectionVisible = section.visible
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000)
        compare(section.visible, sectionVisible, "chrome Space does not toggle the section")
        compare(surface.gridModel.noteSummary, noteSnapshot,
                "chrome Space never changes musical selection")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000)

        var textProbe = textProbeComponent.createObject(shell.contentItem,
                                                        { x: 20, y: 20 })
        verify(textProbe, "the text field mounts inside the production window")
        textProbe.text = "local"
        textProbe.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(textProbe, "activeFocus", true, 3000)
        keyClick(Qt.Key_Space)
        compare(textProbe.text, "local ", "literal text Space belongs to text entry")
        compare(playhead.playing, false, "literal text Space does not start transport")
        textProbe.destroy()

        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_Tab)
        verify(shell.activeFocusItem !== roll, "Tab traverses away from the roll")
        keyClick(Qt.Key_Backtab)
        tryCompare(roll, "activeFocus", true, 3000)
        mouseClick(firstButton, firstButton.width / 3, firstButton.height / 2)
        tryCompare(tabs, "selectedId", firstId, 3000)
        mouseClick(secondButton, secondButton.width / 3, secondButton.height / 2)
        tryCompare(tabs, "selectedId", secondId, 3000)
        var editMenu = findChild(shell.menuBar, "shellEditMenu")
        verify(editMenu, "the production Edit menu is mounted")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        editMenu.open()
        tryCompare(editMenu, "visible", true, 3000)
        editMenu.close()
        tryCompare(roll, "activeFocus", true, 3000,
                   "closing the Edit menu restores the prior roll focus")
    }

    function test_iEditorCommandDeliveryAndTextLocalKeys() {
        openTwoSongShell()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the production roll routes editor commands")
        selectDrawnVelocityNote(surface)
        var original = JSON.parse(grid.noteSummary).filter(function(note) { return note.selected })[0]
        verify(original, "the selected fixture note is available")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_D, Qt.ControlModifier)
        var duplicated = JSON.parse(grid.noteSummary).filter(function(note) {
            return note.selected && note.id !== original.id
                && note.pitch === original.pitch && note.tick > original.tick
        })
        compare(duplicated.length, 1, "Ctrl+D duplicates and selects the original note")
        keySequence(StandardKey.SelectAll)
        var selectedForJoin = JSON.parse(grid.noteSummary).filter(function(note) {
            return note.selected && note.track === original.track
        })
        verify(selectedForJoin.some(function(note) { return note.id === original.id })
               && selectedForJoin.some(function(note) { return note.id === duplicated[0].id }),
               "Select All includes both same-track notes")
        keyClick(Qt.Key_J, Qt.ControlModifier)
        var joined = JSON.parse(grid.noteSummary)
        verify(joined.filter(function(note) { return note.track === original.track }).length
               < selectedForJoin.length,
               "Ctrl+J merges the adjacent same-pitch notes")
        var selectedJoined = joined.filter(function(note) {
            return note.selected && note.track === original.track
                && note.pitch === original.pitch && note.duration > grid.snapTicks
        })
        verify(selectedJoined.length > 0, "Join selects a subdividable merged note")
        keyClick(Qt.Key_E, Qt.ControlModifier)
        var split = JSON.parse(grid.noteSummary)
        verify(split.length > joined.length, "Ctrl+E splits selected notes on grid boundaries")
        verify(split.some(function(note) { return note.selected && note.pitch === original.pitch }),
               "Split keeps the resulting note fragments selected")

        var beforeCut = split.length
        keySequence(StandardKey.Cut)
        var afterCut = JSON.parse(grid.noteSummary)
        verify(afterCut.length < beforeCut, "Cut deletes selected notes from the focused roll")
        var cutClip = JSON.parse(bootstrap.copiedClipSummary())
        compare(cutClip[0], 1, "Cut writes a decodable single-track clipboard clip")
        verify(cutClip[1] > 0, "Cut preserves at least one copied note")
        keySequence(StandardKey.Paste)
        var afterPaste = JSON.parse(grid.noteSummary)
        verify(afterPaste.length > afterCut.length, "Paste inserts clipboard notes into the roll")
        verify(afterPaste.some(function(note) { return note.selected }),
               "Paste selects at least one inserted note")

        var textProbe = textProbeComponent.createObject(shell.contentItem,
                                                        { x: 20, y: 20 })
        verify(textProbe, "a text editor mounts in the real window")
        textProbe.text = "text"
        textProbe.cursorPosition = 0
        textProbe.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(textProbe, "activeFocus", true, 3000)
        var notesBeforeLocalKeys = grid.noteSummary
        keyClick(Qt.Key_D, Qt.ControlModifier)
        compare(grid.noteSummary, notesBeforeLocalKeys,
                "text-focused Duplicate never changes the musical notes")
        keyClick(Qt.Key_Delete)
        compare(textProbe.text, "ext", "text-focused Delete edits the local text")
        compare(grid.noteSummary, notesBeforeLocalKeys,
                "text-focused Delete never deletes selected notes")
        textProbe.destroy()

        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.SelectAll)
        var selectedAll = JSON.parse(grid.noteSummary).filter(function(note) {
            return note.selected && note.track === original.track
        })
        verify(selectedAll.length > 0, "Select All targets the currently focused roll track")
        keyClick(Qt.Key_Delete)
        var remaining = JSON.parse(grid.noteSummary)
        compare(remaining.filter(function(note) { return note.track === original.track }).length,
                0, "Delete removes only the selected track's notes")
    }

    function test_jTimeSelectionInsertAndDeleteMutatesDocument() {
        openTwoSongShell()
        var surface = selectedSurface()
        var session = shell.shellPresenter.session
        var grid = surface.gridModel
        var toggle = findChild(surface, "drawerToggle_automation")
        verify(toggle && toggle.visible, "the real automation section can be opened")
        mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        var page = null
        tryVerify(function() {
            page = findChild(surface, "automationPage")
            return page && page.visible && page.height > 0
        }, 3000, "the active song mounts its automation plot")
        var volumeTab = null
        for (var index = 0; index < page.pageModel.tabCount; ++index) {
            var candidate = findChild(page, "automationParameterTab" + index)
            if (candidate && candidate.text === "Volume") {
                volumeTab = candidate
                break
            }
        }
        verify(volumeTab && volumeTab.enabled, "the active track exposes Volume")
        var tabPress = findChild(volumeTab, "automationParameterTabPress"
                               + volumeTab.model.index)
        verify(tabPress, "the selector owns a real mouse press")
        mouseClick(tabPress, tabPress.width / 2, tabPress.height / 2)
        tryCompare(volumeTab, "checked", true, 3000)
        var plot = findChild(page, "automationPlotInput")
        verify(plot && plot.width > 280 && plot.height > 20,
               "the automation plot has room for a real sweep and time range")
        var notesBefore = grid.noteSummary
        var row = Math.round(plot.height / 2)
        mousePress(plot, 120, row, Qt.LeftButton)
        mouseMove(plot, 180, row, -1, Qt.LeftButton)
        mouseMove(plot, 240, row, -1, Qt.LeftButton)
        mouseRelease(plot, 240, row, Qt.LeftButton)
        tryVerify(function() { return page.pageModel.nodeCount > 1 }, 3000,
                  "a mouse sweep writes Volume automation into the document")

        function writtenTicks(item, result) {
            if (item.objectName === "automationNode" && item.model
                && !item.model.projected && !item.model.phantom)
                result.push(item.model.tick)
            for (var child = 0; child < item.children.length; ++child)
                writtenTicks(item.children[child], result)
            return result
        }
        var originalTicks = writtenTicks(page, []).sort(function(a, b) { return a - b })
        verify(originalTicks.length >= 2
               && originalTicks[originalTicks.length - 1] > originalTicks[0],
               "the sweep leaves written Volume events at distinct ticks")
        var beforeSelectionRevision = grid.appliedRevisionText
        mousePress(plot, 130, row, Qt.RightButton)
        mouseMove(plot, 205, row, -1, Qt.RightButton)
        mouseRelease(plot, 205, row, Qt.RightButton)
        var timeMenu = findChild(shell, "shellTimeMenu")
        verify(timeMenu, "the production Time submenu is available")
        var insertTime = findChild(timeMenu, "shellAction_edit.insert_time")
        var deleteTime = findChild(timeMenu, "shellAction_edit.delete_time")
        verify(insertTime && deleteTime, "both original time-edit commands exist")
        tryCompare(insertTime, "enabled", true, 3000,
                   "the selected lane range enables Insert Time")
        tryCompare(deleteTime, "enabled", true, 3000,
                   "the selected lane range enables Delete Time")
        compare(grid.appliedRevisionText, beforeSelectionRevision,
                "selecting a range does not write the document")
        keyClick(Qt.Key_I, Qt.ControlModifier | Qt.ShiftModifier)
        verify(waitForNative(function() {
            var moved = writtenTicks(page, []).sort(function(a, b) { return a - b })
            return moved.length === originalTicks.length
                && moved.some(function(tick, index) { return tick > originalTicks[index] })
        }, 3000), "the window Insert Time shortcut shifts written Volume events forward; "
                 + "before=" + JSON.stringify(originalTicks)
                 + "; after=" + JSON.stringify(writtenTicks(page, []))
                 + "; revision=" + beforeSelectionRevision + " to "
                 + grid.appliedRevisionText)
        var shiftedTicks = writtenTicks(page, []).sort(function(a, b) { return a - b })
        var shift = shiftedTicks[shiftedTicks.length - 1]
                    - originalTicks[originalTicks.length - 1]
        verify(shift > 0, "inserting the selected blank range shifts later events")
        var firstShifted = shiftedTicks.findIndex(function(tick, index) {
            return tick !== originalTicks[index]
        })
        for (var tickIndex = 0; tickIndex < originalTicks.length; ++tickIndex)
            compare(shiftedTicks[tickIndex],
                    originalTicks[tickIndex] + (tickIndex >= firstShifted ? shift : 0),
                    "Insert Time shifts all later events by the same range span")
        verify(grid.appliedRevisionText !== beforeSelectionRevision
               && session.documentDirty, "Insert Time commits an unsaved document change")
        compare(grid.noteSummary, notesBefore, "a Volume-only selection does not move notes")

        var editMenu = findChild(shell, "shellEditMenu")
        verify(editMenu, "the Edit menu contains the live Time submenu")
        editMenu.open()
        timeMenu.open()
        tryCompare(deleteTime, "enabled", true, 3000)
        mouseClick(deleteTime, deleteTime.width / 2, deleteTime.height / 2)
        tryVerify(function() {
            var restored = writtenTicks(page, []).sort(function(a, b) { return a - b })
            return restored.length === originalTicks.length
                && restored.every(function(tick, index) { return tick === originalTicks[index] })
        }, 3000, "the Time menu Delete Time removes the inserted blank range")
        compare(grid.noteSummary, notesBefore, "a Volume-only deletion preserves all notes")
    }

    function test_kVelocityGestureTermination_data() {
        return [
            { tag: "page-switch", route: "page-switch" },
            { tag: "drawer-hide", route: "drawer-hide" },
            { tag: "focus-loss", route: "focus-loss" },
            { tag: "tab-switch", route: "tab-switch" },
            { tag: "last-tab-close", route: "last-tab-close" },
            { tag: "song-reload", route: "song-reload" },
            { tag: "escape", route: "escape" }
        ]
    }

    function test_kVelocityGestureTermination(data) {
        var firstId = openTwoSongShell()
        var session = shell.shellPresenter.session
        if (data.route === "last-tab-close") {
            session.songTabs.requestClose(firstId)
            compare(session.songTabs.tabCount, 1,
                    "closing the inactive tab leaves one selected song")
        }
        var surface = selectedSurface()
        selectDrawnVelocityNote(surface)
        var grid = surface.gridModel
        var page = session.velocityPage()
        var plot = findChild(surface, "velocityPlotInput")
        var node = findChild(surface, "velocityNodeFill")
        var focusPlot = findChild(surface, "velocityPlot")
        verify(plot && node && focusPlot, "the production velocity input and node exist")
        focusPlot.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(focusPlot, "activeFocus", true, 3000)
        var terminalRoute = data.route === "last-tab-close"
                || data.route === "song-reload"
        var hit = node.mapToItem(plot, node.width / 2, node.height / 2)
        var dragY = hit.y < plot.height / 2 ? hit.y + 30 : hit.y - 30
        if (terminalRoute) {
            var initialRevision = grid.appliedRevisionText
            mousePress(plot, hit.x, hit.y, Qt.LeftButton)
            mouseMove(plot, hit.x, dragY, -1, Qt.LeftButton)
            mouseRelease(plot, hit.x, dragY, Qt.LeftButton)
            tryVerify(function() { return grid.appliedRevisionText !== initialRevision },
                      3000, "a committed edit makes the real close gate hold the tab")
            tryCompare(session, "documentDirty", true, 3000)
            node = findChild(surface, "velocityNodeFill")
            hit = node.mapToItem(plot, node.width / 2, node.height / 2)
            dragY = hit.y < plot.height / 2 ? hit.y + 30 : hit.y - 30
        }
        var beforeNotes = grid.noteSummary
        var beforeRevision = grid.appliedRevisionText
        mousePress(plot, hit.x, hit.y, Qt.LeftButton)
        mouseMove(plot, hit.x, dragY, -1, Qt.LeftButton)
        tryCompare(page, "interactionActive", true, 3000)
        tryCompare(plot, "pressed", true, 3000)
        var closingId = session.songTabs.selectedId
        if (data.route === "page-switch") {
            surface.drawerPresenter.toggleSection(0, true)
        } else if (data.route === "drawer-hide") {
            surface.drawerPresenter.setSectionVisible(
                        bootstrap.velocitySectionKind(), false, true)
        } else if (data.route === "focus-loss") {
            var roll = findChild(surface, "swiftRollInput")
            verify(roll, "the roll focus destination exists")
            roll.forceActiveFocus(Qt.OtherFocusReason)
            tryCompare(roll, "activeFocus", true, 3000)
        } else if (data.route === "tab-switch") {
            session.songTabs.selectTab(firstId)
            compare(session.songTabs.selectedId, firstId,
                    "the real tab controller selects the other song")
        } else if (data.route === "last-tab-close") {
            session.songTabs.requestClose(closingId)
        } else if (data.route === "song-reload") {
            session.openSong("mus_littleroot_test")
        } else {
            keyClick(Qt.Key_Escape)
        }
        if (terminalRoute) {
            tryCompare(session.songTabs, "pendingCloseId", closingId, 3000)
            tryCompare(page, "interactionActive", false, 3000)
            mouseRelease(plot, hit.x, dragY, Qt.LeftButton)
            compare(page.selectedCount, 1, "the close gate preserves the selected note")
            compare(grid.noteSummary, beforeNotes, "the close gate writes no velocity")
            compare(grid.appliedRevisionText, beforeRevision,
                    "the close gate does not advance document revision")
            compare(session.documentDirty, true,
                    "the earlier setup edit remains unsaved until Discard")
            session.songTabs.confirmDiscard()
            if (data.route === "last-tab-close") {
                tryCompare(session.songTabs, "tabCount", 0, 3000)
            } else {
                verify(waitForNative(function() {
                    return session.songTabs.tabCount === 2
                            || session.lastSaveError.length > 0
                }, 30000), "the reload completion returns through the native run loop")
                compare(session.songTabs.tabCount, 2,
                        "the replacement song rejoins the surviving tab")
                verify(waitForNative(function() {
                    var current = selectedSurface()
                    return session.songTabs.selectedId === closingId
                            && current !== null && current.gridModel !== grid
                }, 5000), "reload installs a different workspace for the song")
            }
            return
        }
        tryCompare(page, "interactionActive", false, 3000)
        mouseRelease(plot, hit.x, dragY, Qt.LeftButton)
        tryCompare(plot, "pressed", false, 3000)
        compare(page.selectedCount, 1, "cancellation keeps the selected note")
        compare(grid.noteSummary, beforeNotes, "a cancelled drag never writes note values")
        compare(grid.appliedRevisionText, beforeRevision,
                "a cancelled drag never increments the document revision")
        compare(session.documentDirty, false, "a cancelled drag never dirties the document")
    }

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
        var model = page.pageModel
        verify(model && model.tabCount > 1, "the track exposes multiple parameter tabs")
        var initialActive = null
        for (var scanIndex = 0; scanIndex < model.tabCount; ++scanIndex) {
            var scanCandidate = findChild(page, "automationParameterTab" + scanIndex)
            if (scanCandidate && scanCandidate.enabled && scanCandidate.checked)
                initialActive = scanCandidate
        }
        verify(initialActive, "one parameter tab starts active")
        var firstLabel = null
        for (var index = 0; index < model.tabCount; ++index) {
            var candidate = findChild(page, "automationParameterTab" + index)
            if (candidate && candidate.enabled && !candidate.checked
                    && !findChild(candidate, "automationTempoTapButton")) {
                firstLabel = candidate
                break
            }
        }
        verify(firstLabel && firstLabel !== initialActive, "an inactive label is available")
        var secondLabel = initialActive
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
        compare(session.documentDirty, false, "label Return never edits the song")
        compare(grid.noteSummary, notesBefore, "label Return never moves the selection")
        compare(grid.editCursorTick, cursorBefore, "label Return never moves the cursor")
        keyClick(Qt.Key_Up)
        compare(secondLabel.checked, true, "Up never retargets the active label")
        compare(session.documentDirty, false, "Up on a label never edits the song")
        compare(grid.noteSummary, notesBefore, "Up on a label never moves the selection")
        tapButton.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(tapButton, "activeFocus", true, 3000,
                   "the tempo Tap button takes keyboard focus")
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
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000,
                   "the second tap Space stops transport")
        model.resetTapTempo()
        compare(model.tapTempoTapCount, 0, "resetTapTempo drops the draft")
    }

    function test_yCleanSessionClosesWithoutPrompt() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var presenter = shell.shellPresenter
        var session = presenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the clean close fixture opens Route 101" + openDiagnostics(session))
        verify(session.songOpen && !session.documentDirty && !session.saveInProgress,
               "the close begins with an open, clean song")
        tryVerify(function() { return shell.sceneLoader.item !== null }, 5000,
                  "the opened song mounts its scene")
        var dialog = findChild(shell, "songTabCloseDialog")
        verify(dialog !== null && !dialog.visible, "the discard prompt starts hidden")
        var promptShown = false
        dialog.visibleChanged.connect(function() {
            if (dialog.visible)
                promptShown = true
        })
        compare(presenter.closeReady, false, "the close is not already ready")
        compare(presenter.beginClose(), false, "the close waits for tab and scene teardown")
        verify(waitForNative(function() { return presenter.closeReady }, 5000),
               "a clean close reaches the scene detach acknowledgement")
        verify(!promptShown && presenter.closeReady && session.songTabs.pendingCloseId === -1
               && session.songTabs.pendingCloseBankTitle.length === 0,
               "a clean session closes without the discard prompt")
    }

    function test_zWindowTitleAndStatusMeter() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production shell is mounted for chrome state")
        var presenter = shell.shellPresenter
        var session = presenter.session
        var projectName = bootstrap.projectRoot.split("/").filter(function(part) {
            return part.length > 0
        }).pop()
        var meter = findChild(shell, "shellPolyMeter")
        verify(meter !== null && !meter.visible, "the status meter is hidden with no song")
        compare(shell.title, "porydaw", "the empty shell names the application")
        compare(presenter.windowModified, false, "the empty shell is not modified")

        session.openProject(bootstrap.projectRoot)
        verify(waitForNative(function() { return session.projectOpen }, 30000),
               "the fixture project opens without selecting a tab" + openDiagnostics(session))
        compare(shell.title, projectName + " — porydaw",
                "an empty project title names the project directory")
        compare(meter.visible, false, "a project without a tab has no audio meter")

        session.openSong("mus_route101")
        verify(waitForNative(function() { return session.songOpen }, 30000),
               "Route 101 opens for shell chrome" + openDiagnostics(session))
        verify(waitForNative(function() {
            return shell.title === "mus_route101 — " + projectName + " — porydaw"
        }, 5000), "the selected song and project appear in the window title; actual="
                 + shell.title)
        compare(presenter.windowModified, false, "the loaded clean song is not modified")
        verify(waitForNative(function() { return meter.visible }, 5000),
               "the selected loaded song exposes the status meter")
        compare(findChild(meter, "shellPolyPcmCaption").text, "PCM",
                "the first meter caption identifies PCM channels")
        compare(findChild(meter, "shellPolyPcmValue").text,
                "0/" + presenter.settingsStore.maxPcmChannels,
                "the PCM meter reports active channels and the configured limit")
        compare(findChild(meter, "shellPolyCgbCaption").text, "CGB",
                "the second meter caption identifies CGB channels")
        compare(findChild(meter, "shellPolyCgbValue").text, "0/4",
                "the CGB meter reports zero of four channels")
        compare(findChild(meter, "shellPolyLostValue").visible, false,
                "the lost-note readout stays hidden without losses")
        const footer = shell.footer
        const status = findChild(shell, "shellStatusText")
        verify(footer && status, "the loaded shell exposes its status region")
        const topInset = 3
        const bottomInset = 2
        const gripHeight = 13 + 4
        compare(footer.height,
                Math.max(footerCaptionMetrics.height, footerBodyMetrics.height, gripHeight)
                    + topInset + bottomInset,
                "footer matches the fork's QStatusBar strut plus vertical spacing")
        compare(status.text, "Song open", "the loaded song publishes the status message")
        const statusTop = status.mapToItem(footer, 0, 0).y
        verify(statusTop >= topInset && footer.height - statusTop - status.height >= bottomInset,
               "status text fits inside the status bar's top and bottom insets")
        for (const name of ["shellPolyPcmCaption", "shellPolyPcmValue",
                            "shellPolyCgbCaption", "shellPolyCgbValue"]) {
            const label = findChild(meter, name)
            verify(label !== null, name + " is mounted")
            const top = label.mapToItem(footer, 0, 0).y
            verify(top >= topInset && top + label.height <= footer.height - bottomInset,
                   name + " fits between the fork's status-bar insets")
        }

        var transport = session.transportBarPresenter()
        transport.setMasterVolume(86)
        verify(waitForNative(function() { return session.documentDirty }, 5000),
               "changing song master volume dirties the selected document")
        verify(waitForNative(function() { return presenter.windowModified }, 5000),
               "the title presenter publishes the dirty state")
        presenter.activate("file.save_song")
        verify(waitForNative(function() { return !session.documentDirty && !session.saveInProgress },
                             30000), "saving the edited song clears the dirty state")
        verify(waitForNative(function() { return !presenter.windowModified }, 5000),
               "saving clears the title modified state")
        var firstId = session.songTabs.selectedId
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 2 && session.songTabs.selectedId !== firstId
        }, 30000), "the second project song becomes the selected tab")
        verify(waitForNative(function() {
            return shell.title === "mus_littleroot_test — " + projectName + " — porydaw"
        }, 5000), "the window title follows the newly selected song")
        var secondId = session.songTabs.selectedId
        session.songTabs.selectTab(firstId)
        verify(waitForNative(function() {
            return shell.title === "mus_route101 — " + projectName + " — porydaw"
        }, 5000), "switching tabs restores the first song's title")
        session.songTabs.requestClose(secondId)
        verify(waitForNative(function() { return session.songTabs.tabCount === 1 }, 5000),
               "closing the inactive clean tab preserves the selected song")
        session.songTabs.requestClose(session.songTabs.selectedId)
        verify(waitForNative(function() { return session.songTabs.tabCount === 0 }, 5000),
               "closing the clean tab leaves the project open")
        verify(waitForNative(function() {
            return shell.title === projectName + " — porydaw"
        }, 5000), "closing the last tab restores the project-only title")
        verify(waitForNative(function() { return !meter.visible }, 5000),
               "closing the last tab hides its audio meter")
        compare(findChild(meter, "shellPolyPcmValue").text, "",
                "unloaded PCM meter values are cleared")
        compare(findChild(meter, "shellPolyCgbValue").text, "",
                "unloaded CGB meter values are cleared")
    }

}
