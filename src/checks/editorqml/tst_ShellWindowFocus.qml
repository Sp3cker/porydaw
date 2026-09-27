import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
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

        var automationSection = surface.drawerPresenter.automationSection
        var voiceSection = surface.drawerPresenter.voiceChangesSection
        var poly = shell.shellPresenter
        var polyDock = findChild(shell, "shellPolyphonyDock")
        verify(polyDock, "the mounted shell contains its polyphony dock")
        compare(automationSection.visible, false, "focused chrome starts with Automation hidden")
        compare(section.visible, true, "focused chrome starts with Velocity visible")
        compare(voiceSection.visible, false, "focused chrome starts with Voice Changes hidden")
        compare(polyDock.visible, false, "focused chrome starts with the polyphony dock hidden")
        function checkChromeShortcut(key, modifiers, changed, anchor) {
            toggle.forceActiveFocus(Qt.TabFocusReason)
            tryCompare(toggle, "activeFocus", true, 3000)
            var before = [automationSection.visible, section.visible,
                          voiceSection.visible, polyDock.visible]
            keyClick(key, modifiers)
            var after = [automationSection.visible, section.visible,
                         voiceSection.visible, polyDock.visible]
            verify(after.every(function(value, index) {
                return value === (index === changed ? !before[index] : before[index])
            }), anchor)
        }
        var beforeChrome = [automationSection.visible, section.visible,
                            voiceSection.visible, polyDock.visible]
        checkChromeShortcut(Qt.Key_A, Qt.NoModifier, 0,
                            "focused velocity chrome A toggles only Automation")
        compare(automationSection.visible, true,
                "focused velocity chrome A shows the mounted Automation section")
        checkChromeShortcut(Qt.Key_V, Qt.NoModifier, 1,
                            "focused velocity chrome V toggles only Velocity")
        compare(section.visible, false,
                "focused velocity chrome V hides the mounted Velocity section")
        checkChromeShortcut(Qt.Key_P, Qt.NoModifier, 2,
                            "focused velocity chrome P toggles only Voice Changes")
        compare(voiceSection.visible, true,
                "focused velocity chrome P shows the mounted Voice Changes section")
        checkChromeShortcut(Qt.Key_P, Qt.ControlModifier | Qt.ShiftModifier, 3,
                            "focused velocity chrome Ctrl+Shift+P toggles only Polyphony")
        compare(polyDock.visible, true,
                "focused velocity chrome Ctrl+Shift+P shows the mounted polyphony dock")
        poly.activate("view.polyphony_debugger")
        poly.activate("view.voice_changes_drawer")
        poly.activate("view.velocity_drawer")
        poly.activate("view.automation_drawer")
        tryCompare(polyDock, "visible", beforeChrome[3], 3000,
                   "restored polyphony visibility reaches the mounted dock")
        compare([automationSection.visible, section.visible,
                 voiceSection.visible, polyDock.visible].toString(),
                beforeChrome.toString(),
                "chrome shortcut exercise restores the drawer before the next shell")

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

    function test_lChromeArrowsAndUnknownKey() {
        openTwoSongShell()
        var surface = selectedSurface()
        var session = shell.shellPresenter.session
        var grid = surface.gridModel
        var pair = selectMountedNotePair(surface)
        compare(pair.length, 2, "the real roll click selects a note")
        function note(id) {
            return JSON.parse(grid.noteSummary).find(function(item) { return item.id === id })
        }
        function pairUnchanged(before) {
            return before.every(function(previous) {
                return JSON.stringify(note(previous.id)) === JSON.stringify(previous)
            })
        }
        var drawer = findChild(surface, "editorDrawer")
        var grip = findChild(drawer, "drawerHandle_automation")
        var toggle = findChild(drawer, "drawerToggle_automation")
        verify(grip && toggle && toggle.visible, "the automation section exposes its focused chrome")
        mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        tryCompare(surface.drawerPresenter.automationSection, "visible", true, 3000)
        var section = surface.drawerPresenter.automationSection
        var automationPage = null
        tryVerify(function() {
            automationPage = findChild(drawer, "automationPage")
            return automationPage && automationPage.activeFocus
        }, 3000, "the automation page receives drawer focus before grip focus")
        for (var tabStep = 0; tabStep < 96 && !grip.activeFocus; ++tabStep)
            keyClick(Qt.Key_Tab)
        tryCompare(grip, "activeFocus", true, 3000,
                   "real Tab traversal reaches the automation resize grip")
        compare(grip.activeFocus, true,
                "automation resize grip owns active focus before arrows")
        var beforeHeight = section.bodyHeight
        var beforeNote = pair.map(function(item) { return note(item.id) })
        var beforeRevision = grid.appliedRevisionText
        var beforeSummary = grid.noteSummary
        var beforeUndo = session.canUndo
        copyActivatedSpy.target = windowShortcut("shellShortcut_roll.copy")
        soloActivatedSpy.target = windowShortcut("shellShortcut_roll.solo_tracks")
        verify(copyActivatedSpy.target && soloActivatedSpy.target,
               "the mounted window Copy and Solo shortcuts are observed")
        copyActivatedSpy.clear()
        soloActivatedSpy.clear()
        keyClick(Qt.Key_F24)
        verify(section.bodyHeight === beforeHeight && grid.noteSummary === beforeSummary
               && grid.appliedRevisionText === beforeRevision && session.canUndo === beforeUndo,
               "an unrecognized key changes nothing")
        compare(copyActivatedSpy.count, 0, "A010 F24 never activates window Copy")
        compare(soloActivatedSpy.count, 0, "F24 never activates window Solo")
        verify(pairUnchanged(beforeNote), "F24 retains both selected notes by ID")
        keyClick(Qt.Key_Up)
        compare(section.bodyHeight, beforeHeight + shell.chromeSpacing.two,
                "the automation grip grows by one step on Up")
        verify(pairUnchanged(beforeNote), "A017 grip Up leaves both reserved notes byte-identical")
        keyClick(Qt.Key_Down)
        compare(section.bodyHeight, beforeHeight, "grip Down restores the automation height")
        verify(pairUnchanged(beforeNote), "grip Down leaves both reserved notes byte-identical")
        keyClick(Qt.Key_Left)
        verify(pairUnchanged(beforeNote), "grip Left leaves both reserved notes byte-identical")
        keyClick(Qt.Key_Right)
        verify(pairUnchanged(beforeNote), "A020 grip Right leaves both reserved notes byte-identical")
        compare(section.bodyHeight, beforeHeight,
                "cross-axis grip arrows never resize the automation section")
        compare(grid.appliedRevisionText, beforeRevision,
                "grip arrows never trigger window actions")
        verify(pairUnchanged(beforeNote), "the automation grip keeps the selected note unchanged")
        compare(copyActivatedSpy.count, 0, "A018 grip arrows never activate window Copy")
        compare(soloActivatedSpy.count, 0, "grip arrows never activate window Solo")

        for (var toggleStep = 0; toggleStep < 96 && !toggle.activeFocus; ++toggleStep)
            keyClick(Qt.Key_Tab)
        tryCompare(toggle, "activeFocus", true, 3000,
                   "real Tab traversal reaches the automation drawer toggle")
        compare(toggle.activeFocus, true,
                "automation toggle owns active focus before arrows")
        var snap = grid.snapTicks
        keyClick(Qt.Key_Right)
        verify(pair.every(function(previous) {
            var moved = note(previous.id)
            return moved && moved.tick === previous.tick + snap
                   && moved.pitch === previous.pitch && moved.selected
                   && moved.duration === previous.duration
                   && moved.velocity === previous.velocity && moved.track === previous.track
                   && moved.ghost === previous.ghost
        }), "toggle arrows route to the selected note by one grid step")
        keyClick(Qt.Key_Up)
        verify(pair.every(function(previous) {
            var moved = note(previous.id)
            return moved && moved.tick === previous.tick + snap
                   && moved.pitch === previous.pitch + 1 && moved.selected
                   && moved.duration === previous.duration
                   && moved.velocity === previous.velocity && moved.track === previous.track
                   && moved.ghost === previous.ghost
        }), "toggle Up transposes the selected note")
        var beforeActivation = pair.map(function(previous) { return note(previous.id) })
        var playhead = session.playheadPresenter()
        compare(playhead.playing, false, "toggle Space starts from stopped transport")
        var sectionVisible = section.visible
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000,
                   "toggle Space activates window transport rather than local chrome")
        compare(section.visible, sectionVisible, "toggle Space leaves the section visible")
        verify(pairUnchanged(beforeActivation),
               "A113 bare Space on the focused toggle retains both note IDs")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000,
                   "the second toggle Space stops window transport")
        verify(pairUnchanged(beforeActivation), "the second toggle Space retains both note IDs")
        keyClick(Qt.Key_Enter)
        tryCompare(section, "visible", false, 3000,
                   "Enter toggles the focused drawer section")
        verify(pairUnchanged(beforeActivation),
               "toggle Enter leaves both reserved notes byte-identical")
        toggle.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(toggle, "activeFocus", true, 3000)
        keyClick(Qt.Key_Return)
        tryCompare(section, "visible", true, 3000,
                   "Return restores the focused drawer section")
        verify(pairUnchanged(beforeActivation),
               "A116 toggle Return leaves both reserved notes byte-identical")
        verify(pairUnchanged(beforeActivation), "toggle activation keys never mutate the selected note")
        compare(copyActivatedSpy.count, 0, "toggle activation never fires window Copy")
        compare(soloActivatedSpy.count, 0, "toggle activation never fires window Solo")
    }
}
