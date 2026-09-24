import QtCore
import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import "../../ui/shell"

TestCase {
    id: testCase
    name: "ShellWindow"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    property var settings: null

    ShellQmlBootstrap { id: bootstrap }
    SignalSpy { id: copyActivatedSpy; signalName: "activated" }
    SignalSpy { id: soloActivatedSpy; signalName: "activated" }

    Component { id: settingsComponent; Settings {} }
    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }
    Component {
        id: textProbeComponent
        TextField { text: "native copy text probe"; width: 220; height: 32 }
    }
    Component {
        id: shortcutTargetComponent
        Item { width: 24; height: 24; focus: true }
    }

    function initTestCase() {
        // Preserve the original fixture's private store while exercising the
        // real native QtCore.Settings backend, never the caller's preferences.
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
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function openTwoSongShell() {
        // MainWindowRoutingFixture::openSession: the original velocity/173
        // drawer seed, with absent nullopt heights in this fresh native domain.
        settings.setValue("editorDrawer/velocityVisible", true)
        settings.setValue("editorDrawer/velocityHeight", 173)
        settings.setValue("editorDrawer/automationVisible", false)
        settings.setValue("editorDrawer/voiceChangesVisible", false)
        settings.setValue("editorDrawer/activePage", "velocity")
        const lanes = '{"emptyLanes":[],"hiddenLanes":[],"laneHeight":0,"laneHeights":{},"laneRanges":{}}'
        const laneBytes = new Uint8Array(lanes.length)
        for (var byteIndex = 0; byteIndex < lanes.length; ++byteIndex)
            laneBytes[byteIndex] = lanes.charCodeAt(byteIndex)
        settings.setValue("editorDrawer/automationLanes", laneBytes.buffer)
        settings.sync()
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
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

    function test_aKeymapNativeSettingsSeeds() {
        // KeymapCheckTest::keymapSettingsSeedsAreIgnored writes these four values
        // through QSettings. This test writes the same values through QtCore.Settings.
        settings.setValue("keymap/roll.transpose_up", "Ctrl+Alt+U")
        settings.setValue("keymap/transport.play_pause", "")
        settings.setValue("keymap/roll.velocity_drag", "Shift")
        settings.setValue("keymap/velocity.detent_unlock", "")
        settings.sync()
        compare(settings.value("keymap/roll.transpose_up", null), "Ctrl+Alt+U")
        compare(settings.value("keymap/transport.play_pause", null), "")
        compare(settings.value("keymap/roll.velocity_drag", null), "Shift")
        compare(settings.value("keymap/velocity.detent_unlock", null), "")
        var failures = bootstrap.registryFailures()
        compare(failures.length, 0, "the complete native keymap assertions: " + failures.join("; "))
    }

    function test_bThemeRepairThroughProductionShell() {
        // ThemeLayoutTest::settingsRepair: custom mode is obsolete, 80 survives,
        // and neither obsolete colour key survives restoration.
        settings.setValue("theme/mode", "custom")
        settings.setValue("theme/primary", "#000000")
        settings.setValue("theme/accent", "#FFFFFF")
        settings.setValue("theme/grid-line-contrast", "80")
        settings.sync()
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell restores the seeded native theme")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        tryCompare(shell.shellPresenter, "themeMode", "vanilla")
        compare(shell.shellPresenter.gridLineContrast, 80)
        tryVerify(function() {
            settings.sync()
            return settings.value("theme/mode", null) === "vanilla"
                && Number(settings.value("theme/grid-line-contrast", null)) === 80
                && settings.value("theme/primary", null) === null
                && settings.value("theme/accent", null) === null
        }, 3000, "another native Settings reader observes repaired persisted keys")
        compare(settings.value("theme/mode", null), "vanilla")
        compare(Number(settings.value("theme/grid-line-contrast", null)), 80)
        compare(settings.value("theme/primary", null), null)
        compare(settings.value("theme/accent", null), null)
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

}
