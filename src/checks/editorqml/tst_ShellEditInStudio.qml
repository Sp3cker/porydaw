import QtQuick
import QtTest
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellLaneSupport {
    id: testCase
    name: "ShellEditInStudio"
    when: windowShown
    visible: true
    width: 1100
    height: 720
    ShellQmlBootstrap { id: bootstrap }
    KitStudioEditProbe { id: probe }
    ImportWizardProbe { id: disk }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    laneBootstrap: bootstrap

    function init() {
        verify(bootstrap.resetPreferences())
        verify(probe.prepareFixture(bootstrap.projectRoot), probe.error)
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() { return session.songOpen }, 30000))
        verify(waitForNative(function() { return session.voiceListController().isBound }, 10000))
        waitForShellScene()
        const rows = child("voicegroupRows")
        verify(rows !== null)
        tryCompare(rows, "count", 128)
        verify(waitForNative(function() { return rows.width > 0 && rows.height > 0 }, 10000))
        verify(waitForPolish(shell))
    }

    function test_editExisting_data() {
        return [
            { tag: "drumkit", slot: 10, mode: 0, name: "fixture_drums_a", firstKey: 36, lastKey: 36 },
            { tag: "keysplit", slot: 8, mode: 1, name: "fixture_keys", firstKey: 0, lastKey: 47 }
        ]
    }

    function test_editExisting(data) {
        const session = shell.shellPresenter.session
        const rows = child("voicegroupRows")
        verify(rows !== null)
        rows.positionViewAtIndex(data.slot, ListView.Center)
        verify(waitForNative(function() { return rows.itemAtIndex(data.slot) !== null }, 5000),
               "row mounts: count=" + rows.count + " height=" + rows.height + " width=" + rows.width)
        const row = rows.itemAtIndex(data.slot)
        const menu = child("voicegroupRowMenu")
        verify(menu !== null)
        const before = session.voiceListController().soundingVoice
        mouseClick(row, row.width / 3, row.height / 2, Qt.RightButton)
        tryCompare(menu, "visible", true)
        compare(session.voiceListController().soundingVoice, before)
        const action = findChild(menu, "voicegroupEditInStudio")
        verify(action !== null)
        compare(action.text, "Edit in Studio")
        mouseClick(action, action.width / 2, action.height / 2)
        const studio = session.kitStudio()
        verify(waitForNative(function() {
            const window = child("splitStudioWindow")
            return window !== null && window.visible && window.editor !== null
                && window.editor.voicegroupName === data.name
        }, 10000))
        const editor = studio.presenter()
        compare(editor.mode, data.mode)
        compare(editor.zoneCount(), 3)
        compare(editor.zoneStartKey(0), data.firstKey)
        compare(editor.zoneEndKey(0), data.lastKey)
        compare(editor.dirty, false)
        compare(editor.canSave, true)
        probe.capture(bootstrap.projectRoot, "_fixture_rich", data.slot)
        verify(waitForNative(function() { return !probe.busy }, 10000))
        compare(probe.error, "")
        const bank = bootstrap.projectRoot + "/sound/voicegroups/fixture_rich.inc"
        const midi = bootstrap.projectRoot + "/sound/songs/midi/mus_route101.mid"
        const bankBefore = disk.fingerprint(bank)
        const midiBefore = disk.fingerprint(midi)
        editor.selectZone(0)
        editor.setZoneRootKey(67)
        compare(editor.selectedZoneRootKey, 67)
        studio.saveVoicegroup()
        verify(waitForNative(function() { return !studio.saving }, 30000))
        compare(studio.alertText, "")
        compare(editor.dirty, false)
        probe.verifySaved(bootstrap.projectRoot, data.firstKey, data.lastKey, 67, -1, -1)
        verify(waitForNative(function() { return !probe.busy }, 10000))
        compare(probe.error, "")
        compare(probe.verified, true)
        compare(disk.fingerprint(bank), bankBefore)
        compare(disk.fingerprint(midi), midiBefore)
        child("splitStudioWindow").close()
        verify(waitForNative(function() { return !studio.windowOpen }, 5000))
    }

    function test_keysplitShrinkClearsTail() {
        const session = shell.shellPresenter.session
        session.voiceListController().requestEditKit(8)
        const studio = session.kitStudio()
        verify(waitForNative(function() { return studio.windowOpen }, 10000))
        const editor = studio.presenter()
        compare(editor.zoneCount(), 3)
        probe.capture(bootstrap.projectRoot, "_fixture_rich", 8)
        verify(waitForNative(function() { return !probe.busy }, 10000))
        compare(probe.error, "")
        // One remaining range plus the gap sentinel shrinks three children to two.
        editor.deleteZone(2)
        editor.deleteZone(1)
        compare(editor.zoneCount(), 1)
        studio.saveVoicegroup()
        verify(waitForNative(function() { return !studio.saving }, 10000))
        compare(studio.alertText, "")
        probe.verifySaved(bootstrap.projectRoot, -1, -1, 0, 48, 127)
        verify(waitForNative(function() { return !probe.busy }, 10000))
        compare(probe.error, "")
        compare(probe.verified, true)
    }

    function test_keyboardContextMenu_data() {
        return [
            { tag: "menu", key: Qt.Key_Menu, modifiers: Qt.NoModifier },
            { tag: "shift-f10", key: Qt.Key_F10, modifiers: Qt.ShiftModifier }
        ]
    }

    function test_keyboardContextMenu(data) {
        const rows = child("voicegroupRows")
        rows.positionViewAtIndex(10, ListView.Center)
        verify(waitForNative(function() { return rows.itemAtIndex(10) !== null }, 5000))
        const row = rows.itemAtIndex(10)
        row.forceActiveFocus()
        keyClick(data.key, data.modifiers)
        const menu = child("voicegroupRowMenu")
        tryCompare(menu, "visible", true)
        keyClick(Qt.Key_Escape)
        tryCompare(menu, "visible", false)
    }

    function test_sampleRowHasNoStudioItem() {
        const session = shell.shellPresenter.session
        const rows = child("voicegroupRows")
        rows.positionViewAtIndex(0, ListView.Beginning)
        verify(waitForNative(function() { return rows.itemAtIndex(0) !== null }, 5000))
        const row = rows.itemAtIndex(0)
        const menu = child("voicegroupRowMenu")
        verify(menu !== null)
        mouseClick(row, row.width / 3, row.height / 2, Qt.RightButton)
        tryCompare(menu, "visible", false)
        row.forceActiveFocus()
        keyClick(Qt.Key_Menu)
        tryCompare(menu, "visible", false)
        keyClick(Qt.Key_F10, Qt.ShiftModifier)
        tryCompare(menu, "visible", false)
        session.voiceListController().requestEditKit(-1)
        session.voiceListController().requestEditKit(128)
        session.voiceListController().requestEditKit(0)
        tryCompare(session.kitStudio(), "windowOpen", false)
        compare(session.sampleStudio().editorOpen, false)
    }
}
