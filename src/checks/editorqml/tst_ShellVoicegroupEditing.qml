import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellVoicegroupSupport {
    function test_editorAndUndo() {
        const controller = app.voiceListController()
        controller.selectSlot(4)
        const draft = controller.editorModel()
        compare(draft.editable, true)
        compare(draft.macro, 3)
        compareRole(findChild(panel, "vgTypeCombo"), "body", "voice editor type selector")
        compareRole(findChild(panel, "vgAttackSpin"), "body", "voice editor attack spin")
        compare(findChild(panel, "vgAttackSpin").Layout.minimumWidth,
                app.baseFontPx * 3.3,
                "voice editor attack minimum width follows the captured base")
        compare(findChild(panel, "vgAttackSpin").Layout.preferredHeight,
                app.baseFontPx * 2.08,
                "voice editor attack height follows the captured base")
        const initial = draft.release
        draft.change("release", initial === 7 ? 6 : initial + 1)
        verify(waitForNative(function() {
            return controller.bankDirty && draft.release !== initial
        }, 15000), "ADSR commit publishes dirty bank and refreshed editor")
        app.requestUndo()
        verify(waitForNative(function() { return draft.release === initial }, 15000),
               "undo restores original ADSR")
    }

    function test_editorSpinKeyCommitsAndUndo() {
        const controller = app.voiceListController()
        controller.selectSlot(4)
        const draft = controller.editorModel()
        const release = findChild(panel, "vgReleaseSpin")
        const scroll = findChild(panel, "voiceEditorScrollView")
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        waitForRendering(release)
        const position = release.mapToItem(scroll, 0, 0)
        verify(position.y >= 0 && position.y + release.height <= scroll.height + 1,
               "the ADSR control is reachable after scrolling the mounted form")
        const before = draft.release
        release.forceActiveFocus()
        keyClick(before === release.to ? Qt.Key_Down : Qt.Key_Up)
        verify(waitForNative(function() {
            return draft.release === before + (before === release.to ? -1 : 1)
                   && controller.bankDirty
        }, 15000), "a release spin edit commits through the bank pipeline: "
                   + "before=" + before + " control=" + release.value
                   + " draft=" + draft.release + " dirty=" + controller.bankDirty)
        app.requestUndo()
        verify(waitForNative(function() {
            return draft.release === before && !controller.bankDirty
        }, 15000), "undo restores release after a focused spin edit")
        tryCompare(release, "value", before, 5000,
                   "focused spin readback returns to the original release after bank undo")
    }

    function test_editorQueuedEditsKeepTheirSlot() {
        const controller = app.voiceListController()
        controller.selectSlot(4)
        const editor = controller.editorModel()
        const firstRelease = editor.release
        editor.change("release", firstRelease === 7 ? 6 : firstRelease + 1)
        controller.selectSlot(0)
        const secondRelease = editor.release
        const changedRelease = secondRelease === 255 ? 254 : secondRelease + 1
        editor.change("release", changedRelease)
        verify(waitForNative(function() {
            return editor.release === changedRelease && controller.bankDirty
        }, 15000), "mounted editor commits the selected slot after discarding the stale edit")
        controller.selectSlot(4)
        compare(editor.release, firstRelease, "queued old-slot edit never lands after selection")
        controller.selectSlot(0)
        app.requestUndo()
        verify(waitForNative(function() { return editor.release === secondRelease }, 15000),
               "undo restores the selected slot after queued stale edit")
    }

    function test_editorSaveCommitsCleanBank() {
        const controller = app.voiceListController()
        controller.selectSlot(4)
        const draft = controller.editorModel()
        const bankPath = bootstrap.projectRoot + "/sound/voicegroups/fixture_rich.inc"
        const beforeBytes = fileProbe.fileFingerprint(bankPath)
        verify(beforeBytes.length > 0, "the mounted bank's persisted bytes are readable")
        const initial = draft.release
        draft.change("release", initial === 7 ? 6 : initial + 1)
        verify(waitForNative(function() { return controller.bankDirty && draft.release !== initial },
                             15000), "editor change makes bank dirty")
        const save = findChild(panel, "vgSaveButton")
        compareRole(save, "body", "voice editor save button")
        verify(save !== null && save.enabled, "mounted editor offers save for dirty bank")
        const startsBefore = saveStarts
        const finishesBefore = saveFinishes
        mouseClick(save, save.width / 2, save.height / 2)
        verify(waitForNative(function() { return saveStarts === startsBefore + 1 }, 5000),
               "real mounted Save starts exactly one in-progress receipt: "
               + saveStarts + " vs " + startsBefore + ", active=" + app.saveInProgress)
        verify(waitForNative(function() {
            return !app.saveInProgress && !controller.bankDirty
                   || app.lastSaveError.length > 0
        }, 15000), "mounted save completes: " + app.lastSaveError)
        compare(app.lastSaveError, "")
        compare(controller.bankDirty, false)
        compare(save.enabled, false)
        compare(draft.release, initial === 7 ? 6 : initial + 1)
        compare(app.saveInProgress, false,
                "a completed mounted save lowers the in-progress receipt")
        verify(!controller.bankDirty && !app.documentDirty && !save.enabled,
               "a unified save cleans the dock")
        compare(saveFinishes, finishesBefore + 1,
                "successful mounted Save completes exactly one receipt")
        verify(fileProbe.fileFingerprint(bankPath) !== beforeBytes,
               "completed mounted Save persists the edited bank bytes")
    }

    function test_xSpaceInFocusedAdsrFieldTogglesTransport() {
        fullShell = fullShellComponent.createObject(null)
        const shell = fullShell
        verify(shell !== null, "the production window mounts the voice editor and transport")
        shell.requestActivate()
        tryCompare(shell, "active", true)
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the mounted song loads: " + session.lastSaveError)
        compare(session.lastSaveError, "")
        const voice = session.voiceListController()
        tryCompare(voice, "isBound", true, 5000)
        voice.selectSlot(4)
        const bar = findChild(shell, "transportToolbar")
        const scroll = findChild(shell, "voiceEditorScrollView")
        waitForRendering(scroll)
        const editor = findChild(shell, "voicegroupEditorSurface")
        tryVerify(function() { return !!findChild(editor, "vgReleaseSpin") }, 3000,
                  "the ADSR row mounts after the selected bank voice refreshes")
        const release = findChild(editor, "vgReleaseSpin")
        verify(bar && release && scroll, "the production window mounts the ADSR field: "
               + "bar=" + !!bar + " release=" + !!release + " scroll=" + !!scroll
               + " bank=" + voice.bankLoadName + " slot=" + voice.currentSlot
               + " macro=" + voice.editorModel().macro
               + " editable=" + voice.editorModel().editable)
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        waitForRendering(release)
        const initial = release.value
        release.contentItem.forceActiveFocus()
        keyClick(Qt.Key_Space)
        tryCompare(bar.presenter, "state", 3, 3000,
                   "Space in a focused ADSR field toggles transport once")
        verify(release.value === initial && release.contentItem.activeFocus,
               "Space does not edit the ADSR field or steal its focus")
        keyClick(Qt.Key_Space)
        tryCompare(bar.presenter, "state", 2, 3000,
                   "the same ADSR focus pauses transport on the next Space")
        const stop = findChild(shell, "transport.stop")
        verify(stop && stop.enabled, "mounted transport offers Stop after focused ADSR Space")
        mouseClick(stop, stop.width / 2, stop.height / 2)
        tryCompare(bar.presenter, "state", 1, 3000,
                   "Stop after ADSR Space leaves the transport stopped")
        cleanup()
    }
}
