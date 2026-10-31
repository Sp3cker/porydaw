import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

// The production Virtual MIDI Keyboard: the View toggle, typing and mouse play into
// the selected track's audition membership, shortcut priority while it has the keys,
// every release path, and persistence.
ShellMenusSupport {
    id: testCase
    name: "ShellVirtualKeyboard"

    // One probe per shell: it reads the live presenter pushed into its children.
    property VirtualKeyboardShellProbe probe: null
    Component { id: probeComponent; VirtualKeyboardShellProbe {} }

    function resetKeyboardPreferences(visible) {
        settings.setBool("virtualKeyboard.visible", visible)
        settings.remove("virtualKeyboard.base")
        settings.remove("virtualKeyboard.velocity")
        settings.remove("virtualKeyboard.geometry")
    }

    function keyboard() { return shell.shellPresenter.session.virtualKeyboard }

    function keyboardWindow() {
        const loader = findChild(shell, "virtualKeyboardLoader")
        verify(loader !== null, "the shell hosts the keyboard window")
        verify(waitForNative(function() { return loader.item !== null }, 5000), "the keyboard window loads")
        return loader.item
    }

    function targetTrack() {
        const text = keyboard().targetText
        verify(text.indexOf(" · ") > 0 && text.indexOf(" — ") > 0, "the target names a track and voice: " + text)
        return parseInt(text) - 1
    }

    function focusKeyboard(window) {
        window.requestActivate()
        tryCompare(window, "active", true, 3000)
        window.keySurface.forceActiveFocus()
        tryCompare(window.keySurface, "activeFocus", true, 3000)
    }

    function openKeyboard() {
        resetKeyboardPreferences(false)
        openShell()
        openSong()
        probe = probeComponent.createObject(testCase) as VirtualKeyboardShellProbe
        probe.children.push(shell.shellPresenter)
        verify(probe.members() === "", "the probe reads the live keyboard, silent at first")
        shell.shellPresenter.activate("view.virtual_keyboard")
        tryCompare(keyboard(), "visible", true)
        const window = keyboardWindow()
        tryCompare(window, "visible", true, 3000)
        focusKeyboard(window)
        return window
    }

    function members() { return probe.members() }

    function test_toggleTargetAndPersistence() {
        resetKeyboardPreferences(false)
        openShell()
        const presenter = shell.shellPresenter
        const kb = keyboard()
        compare(kb.visible, false, "hidden by default")
        compare(presenter.action("view.virtual_keyboard").label, "Virtual MIDI Keyboard")
        presenter.activate("view.virtual_keyboard")
        tryCompare(kb, "visible", true)
        compare(kb.activateOnShow, true, "the user's toggle hands the window the keys")
        compare(presenter.action("view.virtual_keyboard").checked, true)
        compare(settings.bool("virtualKeyboard.visible", false), true, "visibility persists on the toggle")
        compare(kb.targetText, "No song open")
        const window = keyboardWindow()
        tryCompare(window, "visible", true, 3000)
        compare(window.title, "Virtual MIDI Keyboard")
        openSong()
        targetTrack()
        presenter.activate("view.virtual_keyboard")
        tryCompare(kb, "visible", false)
        tryCompare(window, "visible", false, 3000)
        compare(settings.bool("virtualKeyboard.visible", true), false)
        compare(presenter.action("view.virtual_keyboard").checked, false)
    }

    function test_restoreShowsWithoutTakingKeys() {
        resetKeyboardPreferences(true)
        settings.setInt("virtualKeyboard.base", 62)
        settings.setInt("virtualKeyboard.velocity", 33)
        openShell()
        const kb = keyboard()
        compare(kb.visible, true, "a keyboard open at quit comes back")
        compare(kb.activateOnShow, false, "the restore leaves the keys with the main window")
        compare(kb.base, 60, "the saved base rounds down to its C")
        compare(kb.octaveText, "C4")
        compare(kb.velocity, 33, "velocity persists")
        const window = keyboardWindow()
        tryCompare(window, "visible", true, 3000)
        verify(waitForNative(function() { return shell.activeFocusItem !== null }, 3000),
               "the main window keeps the keys after the restore")
        compare(window.keySurface.activeFocus, false, "the restored window does not take the keys")
    }

    function test_typingChordsAndShortcutPriority() {
        const window = openKeyboard()
        const kb = keyboard()
        const presenter = shell.shellPresenter
        const track = targetTrack()
        keyPress(Qt.Key_Z)
        tryCompare(kb, "litMask", 1)
        compare(members(), track + ":48:100", "Z sounds the base C on the selected track at the slider's velocity")
        keyPress(Qt.Key_Z)
        compare(probe.holders(48), 1, "a repeated press is one holder")
        keyPress(Qt.Key_Comma)
        keyPress(Qt.Key_Q)
        compare(probe.holders(60), 2, "comma and Q both hold the upper C")
        compare(members(), track + ":48:100," + track + ":60:100", "the chord sounds each key once")
        keyRelease(Qt.Key_Comma)
        compare(members(), track + ":48:100," + track + ":60:100", "the upper C sounds until its last key lets go")
        keyRelease(Qt.Key_Q)
        keyRelease(Qt.Key_Z)
        compare(members(), "", "every release stops its note")
        compare(kb.litMask, 0)

        const velocityChecked = presenter.action("view.velocity_drawer").checked
        keyClick(Qt.Key_V)
        compare(presenter.action("view.velocity_drawer").checked, velocityChecked,
                "a note key (V) never also runs its window shortcut")
        const automationChecked = presenter.action("view.automation_drawer").checked
        keyClick(Qt.Key_A)
        tryCompare(presenter.action("view.automation_drawer"), "checked", !automationChecked)
        keyClick(Qt.Key_A)
        tryCompare(presenter.action("view.automation_drawer"), "checked", automationChecked)
        const playhead = presenter.session.playheadPresenter()
        keyPress(Qt.Key_Z)
        compare(members(), track + ":48:100")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000)
        compare(members(), "", "starting playback cuts the held note, and the key lets go with it")
        compare(kb.litMask, 0, "a key the transport silenced is no longer lit")
        keyRelease(Qt.Key_Z)
        keyPress(Qt.Key_X)
        compare(members(), track + ":50:100", "keys play over the running song")
        keyRelease(Qt.Key_X)
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000)
        compare(window.keySurface.activeFocus, true, "the window keeps the keys while Space runs the transport")
        keyPress(Qt.Key_Z, Qt.ControlModifier)
        compare(members(), "", "a Ctrl chord is a command, never a note")
        keyRelease(Qt.Key_Z, Qt.ControlModifier)
        keyClick(Qt.Key_B, Qt.AltModifier)
        tryCompare(kb, "visible", false)
        tryCompare(window, "visible", false, 3000)
    }

    function test_releasePaths() {
        const window = openKeyboard()
        const kb = keyboard()
        const track = targetTrack()
        keyPress(Qt.Key_X)
        compare(members(), track + ":50:100")
        keyPress(Qt.Key_Equal)
        compare(kb.base, 60, "= shifts up one octave")
        compare(members(), "", "an octave shift releases every held note first")
        keyRelease(Qt.Key_X)
        compare(members(), "", "a key held through the shift stays silent")
        keyPress(Qt.Key_Minus)
        compare(kb.base, 48, "- shifts down")
        compare(settings.int("virtualKeyboard.base", -1), 48, "the base persists")

        keyPress(Qt.Key_C)
        compare(members(), track + ":52:100")
        shell.requestActivate()
        tryCompare(window.keySurface, "activeFocus", false, 3000)
        compare(members(), "", "losing the keys releases what was held")
        compare(kb.litMask, 0)
        focusKeyboard(window)
        keyRelease(Qt.Key_C)
        compare(members(), "", "the late release sends nothing more")

        keyPress(Qt.Key_C)
        compare(members(), track + ":52:100")
        shell.shellPresenter.activate("file.close_tab")
        verify(waitForNative(function() { return !shell.shellPresenter.session.songOpen }, 10000),
               "the tab closes")
        compare(kb.targetText, "No song open")
        compare(members(), "", "a target change releases every held note")
        keyRelease(Qt.Key_C)
        compare(kb.litMask, 0)
    }

    function test_mouseGlideAndClose() {
        const window = openKeyboard()
        const kb = keyboard()
        const track = targetTrack()
        const c = findChild(window.keySurface, "virtualKeyboardKey_0")
        const e = findChild(window.keySurface, "virtualKeyboardKey_4")
        const cSharp = findChild(window.keySurface, "virtualKeyboardKey_1")
        verify(c && e && cSharp, "the piano draws its keys")
        mousePress(c, c.width / 2, c.height - 4)
        compare(members(), track + ":48:100", "a click sounds its key")
        keyPress(Qt.Key_Z)
        compare(probe.holders(48), 2, "a typed and a clicked C3 are two holders of one note")
        keyRelease(Qt.Key_Z)
        compare(members(), track + ":48:100", "the click still holds it")
        mouseMove(e, e.width / 2, e.height - 4)
        compare(members(), track + ":52:100", "a drag glides to the next key")
        mouseRelease(e, e.width / 2, e.height - 4)
        compare(members(), "", "the release stops it")

        kb.setVelocity(64)
        kb.commitVelocity()
        compare(settings.int("virtualKeyboard.velocity", -1), 64, "a settled velocity persists")
        mousePress(cSharp, cSharp.width / 2, 4)
        compare(members(), track + ":49:64", "the black key is hit first, at the new velocity")
        window.close()
        tryCompare(kb, "visible", false)
        compare(members(), "", "closing the window releases the mouse key")
        compare(settings.bool("virtualKeyboard.visible", true), false, "the title bar's close persists hidden")
    }
}
