import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
    function test_sharedDrawerWindowShortcutsFanOut() {
        bootstrap.resetPreferences()
        var firstId = openTwoSongShell(function() {
            for (var id of ["view.automation_drawer", "view.velocity_drawer",
                            "view.voice_changes_drawer"]) {
                verify(!shell.shellPresenter.actionEnabled(id),
                       "drawer menu actions disable without a workspace: " + id)
            }
        })
        var tabs = shell.shellPresenter.session.songTabs
        var secondId = tabs.selectedId
        var firstPage = findChild(shell.sceneLoader.item, "songTab_" + firstId)
        var first = findChild(firstPage, "swiftRollOverlay")
        var second = selectedSurface()
        var shortcut = windowShortcut("shellShortcut_view.velocity_drawer")
        verify(first && second && shortcut && shortcut.enabled)
        drawerOriginPreferenceSpy.target = second.drawerPresenter
        drawerSiblingPreferenceSpy.target = first.drawerPresenter
        drawerOriginPreferenceSpy.clear()
        drawerSiblingPreferenceSpy.clear()
        var kinds = [bootstrap.velocitySectionKind(), 0, 2]
        var keys = [Qt.Key_V, Qt.Key_A, Qt.Key_P]
        var names = ["V", "A", "P"]
        var roll = findChild(second, "swiftRollInput")
        verify(roll && roll.visible, "the real roll receives window shortcut keys")
        for (var i = 0; i < kinds.length; ++i) {
            roll.forceActiveFocus(Qt.OtherFocusReason)
            tryCompare(roll, "activeFocus", true, 3000)
            var kind = kinds[i]
            var before = second.drawerPresenter.section(kind).visible
            keyClick(keys[i])
            tryCompare(second.drawerPresenter.section(kind), "visible", !before, 3000)
            compare(second.drawerPresenter.focusTarget, i === 0 ? -1 : kind,
                    "toggling a section follows its focus fallback")
            compare(drawerOriginPreferenceSpy.count, i + 1,
                    "the initiating drawer publishes one preference change per key")
            compare(drawerSiblingPreferenceSpy.count, 0,
                    "the projected sibling never republishes a preference change")
            tabs.selectTab(firstId)
            tryCompare(first.drawerPresenter.section(kind), "visible", !before, 3000,
                       "the " + names[i] + " key restores the shared state on the sibling tab")
            tabs.selectTab(secondId)
        }
        var beforeGated = kinds.map(function(kind) {
            return second.drawerPresenter.section(kind).visible
        })
        tabs.setSelectedTabEventsVisible(true)
        var menu = findChild(shell, "shellViewMenu")
        verify(menu && windowShortcut("shellShortcut_view.velocity_drawer"))
        menu.open()
        for (var id of ["view.automation_drawer", "view.velocity_drawer",
                        "view.voice_changes_drawer"]) {
            var item = findChild(menu, "shellAction_" + id)
            verify(item && !item.enabled,
                   "drawer menu items disable while the event list shows: " + id)
        }
        menu.close()
        keyClick(Qt.Key_V)
        keyClick(Qt.Key_P)
        tabs.setSelectedTabEventsVisible(false)
        menu.open()
        var enabledAutomation = findChild(menu, "shellAction_view.automation_drawer")
        verify(enabledAutomation && enabledAutomation.enabled,
               "the Automation View command re-enables after leaving Event List")
        var enabledVelocity = findChild(menu, "shellAction_view.velocity_drawer")
        verify(enabledVelocity && enabledVelocity.enabled,
               "the Velocity View command re-enables after leaving Event List")
        var enabledVoice = findChild(menu, "shellAction_view.voice_changes_drawer")
        verify(enabledVoice && enabledVoice.enabled,
               "the Voice Changes View command re-enables after leaving Event List")
        menu.close()
        for (var j = 0; j < kinds.length; ++j) {
            compare(second.drawerPresenter.section(kinds[j]).visible, beforeGated[j],
                    "the gated keys leave the drawer state unchanged")
        }
        compare(drawerOriginPreferenceSpy.count, keys.length,
                "gated drawer shortcuts publish no preference changes")
    }

    function test_drawerHideResizeAndAllHiddenFanOut() {
        bootstrap.resetPreferences()
        var firstId = openTwoSongShell()
        var tabs = shell.shellPresenter.session.songTabs
        var secondId = tabs.selectedId
        var first = findChild(findChild(shell.sceneLoader.item, "songTab_" + firstId),
                              "swiftRollOverlay")
        var second = selectedSurface()
        var velocity = bootstrap.velocitySectionKind()
        var automation = 0
        var voice = 2
        var view = findChild(shell, "shellViewMenu")
        function clickDrawerRow(id) {
            view.open()
            var row = findChild(view, "shellAction_" + id)
            verify(row && row.enabled, "the mounted View menu exposes " + id)
            mouseClick(row, row.width / 2, row.height / 2)
            tryCompare(view, "opened", false)
        }
        clickDrawerRow("view.velocity_drawer")
        compare(second.drawerPresenter.section(velocity).visible, false,
                "hiding the last visible drawer section hides it on the origin tab")
        tabs.selectTab(firstId)
        compare(first.drawerPresenter.section(velocity).visible, false,
                "hiding the last visible drawer section hides it on the sibling tab")
        compare(first.drawerPresenter.section(automation).visible
                || first.drawerPresenter.section(voice).visible, false,
                "all hidden sections remain hidden when selecting the sibling tab")
        tabs.selectTab(secondId)
        var roll = findChild(second, "swiftRollInput")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_A)
        compare(second.drawerPresenter.section(automation).visible, true,
                "A shows Automation on the origin tab after hide-all")
        tabs.selectTab(firstId)
        tryCompare(first.drawerPresenter.section(automation), "visible", true, 3000,
                   "A shows Automation on the sibling tab after hide-all")
        tabs.selectTab(secondId)
        compare(settings.string("editorDrawer.activePage", ""), "automations",
                "A persists Automation as the active page")
        keyClick(Qt.Key_A)
        compare(second.drawerPresenter.section(automation).visible, false,
                "a second A hides Automation on the origin tab")
        tabs.selectTab(firstId)
        tryCompare(first.drawerPresenter.section(automation), "visible", false, 3000,
                   "a second A hides Automation on the sibling tab")
        tabs.selectTab(secondId)
        keyClick(Qt.Key_V)
        compare(second.drawerPresenter.section(velocity).visible, true,
                "V shows Velocity on the origin tab")
        tabs.selectTab(firstId)
        tryCompare(first.drawerPresenter.section(velocity), "visible", true, 3000,
                   "V shows Velocity on the sibling tab")
        tabs.selectTab(secondId)
        compare(settings.string("editorDrawer.activePage", ""), "velocity",
                "V persists Velocity as the active page")
        keyClick(Qt.Key_P)
        compare(second.drawerPresenter.section(voice).visible, true,
                "P shows Voice Changes on the origin tab")
        tabs.selectTab(firstId)
        tryCompare(first.drawerPresenter.section(voice), "visible", true, 3000,
                   "P shows Voice Changes on the sibling tab")
        tabs.selectTab(secondId)
        compare(settings.string("editorDrawer.activePage", ""), "voiceChanges",
                "P persists Voice Changes as the active page")

        var drawer = findChild(second, "editorDrawer")
        var grip = findChild(drawer, "drawerHandle_velocity")
        verify(grip && grip.visible, "the mounted Velocity handle receives resizing")
        var originalHeight = second.drawerPresenter.section(velocity).bodyHeight
        var gripY = grip.height / 2
        var displacement = shell.shellPresenter.session.baseFontPx
        mousePress(grip, grip.width / 2, gripY, Qt.LeftButton)
        mouseMove(grip, grip.width / 2, gripY - displacement, -1, Qt.LeftButton)
        mouseRelease(grip, grip.width / 2, gripY - displacement, Qt.LeftButton)
        var resized = second.drawerPresenter.section(velocity).bodyHeight
        verify(resized > originalHeight, "dragging the real Velocity handle grows its body")
        tabs.selectTab(firstId)
        tryCompare(first.drawerPresenter.section(velocity), "bodyHeight", resized, 3000,
                   "the resized Velocity body reaches the sibling tab")
        tabs.selectTab(secondId)
        clickDrawerRow("view.voice_changes_drawer")
        compare(second.drawerPresenter.section(voice).visible, false,
                "the View menu hides Voice Changes on the origin tab")
        tabs.selectTab(firstId)
        tryCompare(first.drawerPresenter.section(voice), "visible", false, 3000,
                   "the View menu hides Voice Changes on the sibling tab")
        tabs.selectTab(secondId)
        compare(second.drawerPresenter.section(velocity).visible, true,
                "hiding Voice Changes leaves Velocity visible")
        clickDrawerRow("view.automation_drawer")
        compare(second.drawerPresenter.section(automation).visible, true,
                "the View menu restores Automation on the origin tab")
        tabs.selectTab(firstId)
        tryCompare(first.drawerPresenter.section(automation), "visible", true, 3000,
                   "the View menu restores Automation on the sibling tab")
        tabs.selectTab(secondId)
        clickDrawerRow("view.velocity_drawer")
        compare(second.drawerPresenter.section(velocity).visible, false,
                "the View menu hides Velocity on the origin tab")
        tabs.selectTab(firstId)
        tryCompare(first.drawerPresenter.section(velocity), "visible", false, 3000,
                   "the View menu hides Velocity on the sibling tab")
        tabs.selectTab(secondId)
        compare(second.drawerPresenter.section(automation).visible, true,
                "hiding Velocity leaves Automation visible on the origin tab")
        tabs.selectTab(firstId)
        tryCompare(first.drawerPresenter.section(automation), "visible", true, 3000,
                   "hiding Velocity leaves Automation visible on the sibling tab")
        compare(settings.int("editorDrawer.velocityHeight", 0), resized,
                "the hidden resized Velocity height survives switching tabs")
        tabs.selectTab(secondId)
        compare(settings.int("editorDrawer.velocityHeight", 0), resized,
                "the hidden resized Velocity height survives returning to its tab")
    }
}
