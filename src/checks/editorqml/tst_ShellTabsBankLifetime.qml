import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellTabsSupport {
    function bankPath() { return bootstrap.projectRoot + "/sound/voicegroups/fixture_rich.inc" }
    function closeGateLabel() {
        var dialog = findChild(tabsRoot(), "songTabCloseDialog")
        if (!dialog || dialog.contentChildren.length === 0)
            return ""
        return String(dialog.contentChildren[0].text)
    }

    function dirtyOpenBank() {
        var controller = session().voiceListController()
        verify(waitForNative(function() {
            return controller.isBound && controller.bankLoadName === "fixture_rich"
        }, 15000), "the open song binds its voicegroup bank")
        verify(fileProbe.fileFingerprint(bankPath()).length > 0,
               "the staged bank source is readable")
        controller.selectSlot(4)
        var draft = controller.editorModel()
        var initial = draft.release
        draft.change("release", initial === 7 ? 6 : initial + 1)
        verify(waitForNative(function() {
            return controller.bankDirty && draft.release !== initial
        }, 15000), "the voice editor release edit dirties the bank")
        return controller
    }

    function orphanDirtyBank() {
        var onlyId = openShell(["mus_route101"])[0]
        var controller = dirtyOpenBank()
        var bankBefore = fileProbe.fileFingerprint(bankPath())
        var close = closeButton(onlyId)
        mouseClick(close, close.width / 2, close.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === onlyId }, 5000),
               "the bank-dirty tab close raises the tab gate")
        verify(awaitGateButtons(), "the tab gate offers Save, Discard and Cancel")
        var discardButton = dialogButton("songTabDiscard")
        mouseClick(discardButton, discardButton.width / 2, discardButton.height / 2)
        verify(waitForNative(function() { return tabs().tabCount === 0 }, 5000),
               "Discard closes the last tab")
        compare(tabs().pendingCloseId, -1, "Discard lowers the tab gate")
        compare(fileProbe.fileFingerprint(bankPath()), bankBefore, "Discard wrote no bank bytes")
        return { controller: controller, bankBefore: bankBefore }
    }

    function verifyBankGate(cause) {
        compare(tabs().pendingCloseBankTitle, "fixture_rich", cause + " names the dirty bank")
        compare(tabs().pendingCloseId, -1, cause + " asks about no tab")
        verify(awaitGateButtons(), cause + " offers Save, Discard and Cancel")
        verify(closeGateLabel().indexOf("fixture_rich") >= 0,
               cause + " dialog names the bank: " + closeGateLabel())
        verify(waitForNative(function() { return !strip().enabled }, 5000),
               cause + " gates the strip while the dialog asks")
    }
    function test_lOrphanDirtyBankGatesProjectSwitch() {
        var orphan = orphanDirtyBank()
        var controller = orphan.controller
        var revisionBefore = controller.catalogRevision
        session().openProject(bootstrap.projectRoot)
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
                || controller.catalogRevision !== revisionBefore
                || session().lastSaveError.length > 0
        }, 30000), "the switch either asks about the orphan bank or completes"
            + openDiagnostics(session()))
        compare(controller.catalogRevision, revisionBefore,
                "the switch waits for an answer about the orphaned dirty bank")
        verifyBankGate("the project switch")
        compare(fileProbe.fileFingerprint(bankPath()), orphan.bankBefore,
                "raising the bank gate wrote no bank bytes")

        var cancelButton = dialogButton("songTabCancel")
        mouseClick(cancelButton, cancelButton.width / 2, cancelButton.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseBankTitle === "" }, 5000),
               "Cancel lowers the bank gate")
        compare(controller.catalogRevision, revisionBefore, "Cancel aborts the switch")
        verify(session().projectOpen, "Cancel keeps the project open")
        verify(waitForNative(function() { return strip().enabled }, 5000),
               "Cancel hands the strip back")
        compare(fileProbe.fileFingerprint(bankPath()), orphan.bankBefore,
                "Cancel wrote no bank bytes")

        session().openProject(bootstrap.projectRoot)
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
                || controller.catalogRevision !== revisionBefore
        }, 30000), "the next switch asks again" + openDiagnostics(session()))
        compare(controller.catalogRevision, revisionBefore,
                "Cancel kept the orphaned bank dirty for the next switch")
        verifyBankGate("the repeated project switch")
        var discardButton = dialogButton("songTabDiscard")
        mouseClick(discardButton, discardButton.width / 2, discardButton.height / 2)
        verify(waitForNative(function() {
            return controller.catalogRevision !== revisionBefore
        }, 30000), "Discard lets the switch complete" + openDiagnostics(session()))
        compare(tabs().pendingCloseBankTitle, "", "Discard lowers the bank gate")
        compare(session().lastSaveError, "", "the switch reported no error")
        compare(fileProbe.fileFingerprint(bankPath()), orphan.bankBefore,
                "Discard wrote no bank bytes")
    }

    function test_mOrphanDirtyBankGatesWindowClose() {
        var orphan = orphanDirtyBank()
        shell.close()
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
                || shell.shellPresenter.closeReady
        }, 5000), "the window close asks about the orphan bank or completes")
        verify(!shell.shellPresenter.closeReady, "the window close waits for an answer")
        verifyBankGate("the window close")

        var cancelled = 0
        var countCancel = function() { cancelled++ }
        session().closeCancelled.connect(countCancel)
        var cancelButton = dialogButton("songTabCancel")
        mouseClick(cancelButton, cancelButton.width / 2, cancelButton.height / 2)
        verify(waitForNative(function() { return cancelled === 1 }, 5000),
               "Cancel reports the refused close to the window")
        session().closeCancelled.disconnect(countCancel)
        verify(waitForNative(function() { return tabs().pendingCloseBankTitle === "" }, 5000),
               "Cancel lowers the bank gate")
        verify(shell.shellPresenter.sceneActive && !shell.shellPresenter.closeReady,
               "Cancel leaves the window open")
        compare(fileProbe.fileFingerprint(bankPath()), orphan.bankBefore,
                "Cancel wrote no bank bytes")

        shell.close()
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
                || shell.shellPresenter.closeReady
        }, 5000), "the next window close asks again")
        verifyBankGate("the repeated window close")
        tabs().confirmSave()
        verify(session().saveInProgress, "the bank Save is in flight")
        tabs().confirmDiscard()
        tabs().cancelClose()
        compare(tabs().pendingCloseBankTitle, "fixture_rich",
                "Discard and Cancel are refused while the bank Save is in flight")
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 30000),
               "the saved bank lets the window close complete")
        compare(tabs().pendingCloseBankTitle, "", "Save lowers the bank gate")
        compare(session().saveInProgress, false, "the close waited for the bank Save")
        compare(session().lastSaveError, "", "the bank Save reported no error")
        var bankAfter = fileProbe.fileFingerprint(bankPath())
        verify(bankAfter.length > 0 && bankAfter !== orphan.bankBefore,
               "Save wrote the orphaned bank to disk")
    }

    function test_nDirtyTabThenOrphanBankWalk() {
        var onlyId = openShell(["mus_route101"])[0]
        dirtyOpenBank()
        drawNote(onlyId)
        var songPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route101")
        var songBefore = fileProbe.fileFingerprint(songPath)
        var bankBefore = fileProbe.fileFingerprint(bankPath())

        shell.close()
        verify(waitForNative(function() { return tabs().pendingCloseId === onlyId }, 5000),
               "the window close asks about the dirty tab first")
        compare(tabs().pendingCloseBankTitle, "", "the tab question names no bank")
        verify(awaitGateButtons(), "the tab gate offers its answers")
        var discardButton = dialogButton("songTabDiscard")
        mouseClick(discardButton, discardButton.width / 2, discardButton.height / 2)
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
                || shell.shellPresenter.closeReady
        }, 5000), "the walk moves on from the discarded tab")
        compare(tabs().tabCount, 0, "Discard closed the tab")
        verify(!shell.shellPresenter.closeReady, "the orphaned bank is asked about by name")
        verifyBankGate("the bank stage")

        discardButton = dialogButton("songTabDiscard")
        mouseClick(discardButton, discardButton.width / 2, discardButton.height / 2)
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 30000),
               "the answered bank is not asked about again")
        compare(tabs().pendingCloseBankTitle, "", "Discard lowers the bank gate")
        compare(fileProbe.fileFingerprint(bankPath()), bankBefore, "Discard wrote no bank bytes")
        compare(fileProbe.fileFingerprint(songPath), songBefore, "Discard wrote no song bytes")
    }
    function test_uSharedBankTwoTabJourney() {
        var ids = openShell(["mus_route101", "mus_route102"])
        var a = ids[0]
        var b = ids[1]
        var bankBefore = fileProbe.fileFingerprint(bankPath())
        verify(bankBefore.length > 0, "the shared bank starts readable")
        clickSelectTab(a)
        var controller = session().voiceListController()
        verify(waitForNative(function() {
            return controller.isBound && controller.bankLoadName === "fixture_rich"
        }, 15000), "tab A binds the shared bank")
        var voiceRows = findChild(shell, "voicegroupRows")
        verify(voiceRows !== null && voiceRows.count === 128,
               "the mounted voicegroup dock publishes all shared bank rows")
        controller.revealSlot(4)
        voiceRows.positionViewAtIndex(4, ListView.Contain)
        verify(waitForNative(function() {
            return voiceRows.itemAtIndex(4) !== null
        }, 5000), "slot four renders in the mounted voicegroup dock")
        var voiceRow = voiceRows.itemAtIndex(4)
        var originalAdsr = voiceRow.adsr
        var draft = controller.editorModel()
        var original = draft.release
        var changed = original === 7 ? 6 : original + 1
        draft.change("release", changed)
        verify(waitForNative(function() {
            return controller.bankDirty && draft.release === changed
                && String(selectButton(a).text).slice(-1) === "*"
                && String(selectButton(b).text).slice(-1) === "*"
                && session().documentDirty
        }, 15000), "mounted edit stars both shared-bank captions and the window")
        var editedAdsr = voiceRow.adsr
        verify(editedAdsr !== originalAdsr, "the selected dock row renders the edited ADSR")
        compare(fileProbe.fileFingerprint(bankPath()), bankBefore,
                "the mounted edit has not written bank bytes")
        verify(session().canUndo, "tab A owns the bank edit's undo")

        clickSelectTab(b)
        verify(waitForNative(function() {
            controller.selectSlot(4)
            return controller.bankLoadName === "fixture_rich"
                && controller.bankDirty && controller.panelTitle === "Voicegroup*"
                && controller.editorModel().release === changed && session().documentDirty
        }, 5000), "tab B's dock rebind displays the peer's edited bank")
        verify(waitForNative(function() {
            var peerRow = voiceRows.itemAtIndex(4)
            return peerRow !== null && peerRow.adsr === editedAdsr
        }, 5000), "tab B's mounted voicegroup row displays the edited ADSR")
        verify(!session().canUndo, "tab B does not inherit tab A's undo history")
        var close = closeButton(b)
        mouseClick(close, close.width / 2, close.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === b }, 5000),
               "bank-only dirty tab B raises its own close gate")
        verify(awaitGateButtons(), "tab B's gate offers Save, Discard and Cancel")
        var cancel = dialogButton("songTabCancel")
        mouseClick(cancel, cancel.width / 2, cancel.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === -1 }, 5000),
               "Cancel lowers tab B's gate")
        compare(tabs().tabCount, 2, "Cancel retains both shared-bank tabs")
        tabs().requestClose(b)
        verify(waitForNative(function() { return tabs().pendingCloseId === b }, 5000),
               "tab B asks again after Cancel")
        verify(awaitGateButtons(), "the reopened tab B gate presents its answers")
        var discard = dialogButton("songTabDiscard")
        mouseClick(discard, discard.width / 2, discard.height / 2)
        verify(waitForNative(function() {
            return tabs().tabCount === 1 && tabs().selectedId === a
                && String(selectButton(a).text).slice(-1) === "*"
        }, 5000), "Discard closes tab B but leaves tab A's shared bank dirty")
        compare(fileProbe.fileFingerprint(bankPath()), bankBefore,
                "discarding the peer writes no bank bytes")

        session().openSong("mus_route102")
        verify(waitForNative(function() {
            return tabs().tabCount === 2 && tabs().selectedId !== a
        }, 30000), "tab B reopens while the bank is dirty")
        b = tabs().selectedId
        waitForPage(b)
        verify(waitForNative(function() {
            controller.selectSlot(4)
            return controller.bankDirty && controller.editorModel().release === changed
                && String(selectButton(b).text).slice(-1) === "*"
        }, 15000), "reopened tab B adopts the unwritten shared voice and dirty star")
        clickSelectTab(a)
        session().requestUndo()
        verify(waitForNative(function() {
            return controller.editorModel().release === original && !controller.bankDirty
                && String(selectButton(a).text).slice(-1) !== "*"
                && String(selectButton(b).text).slice(-1) !== "*"
        }, 15000), "only tab A's undo restores the voice and clears both captions")
        compare(fileProbe.fileFingerprint(bankPath()), bankBefore,
                "undoing the shared edit writes no bank bytes")

        draft.change("release", changed)
        verify(waitForNative(function() {
            return controller.bankDirty && String(selectButton(b).text).slice(-1) === "*"
        }, 15000), "tab A's next mounted edit reaches the live peer")
        close = closeButton(a)
        mouseClick(close, close.width / 2, close.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === a }, 5000),
               "tab A's bank-only close raises its own gate")
        verify(awaitGateButtons(), "tab A's bank gate shows its answers")
        discard = dialogButton("songTabDiscard")
        mouseClick(discard, discard.width / 2, discard.height / 2)
        verify(waitForNative(function() {
            return tabs().tabCount === 1 && tabs().selectedId === b
                && String(selectButton(b).text).slice(-1) === "*"
        }, 5000), "tab A's Discard keeps tab B's shared bank dirty")
        session().openSong("mus_route101")
        verify(waitForNative(function() {
            return tabs().tabCount === 2 && tabs().selectedId !== b
        }, 30000), "tab A reopens without saving the bank")
        a = tabs().selectedId
        waitForPage(a)
        verify(waitForNative(function() {
            controller.selectSlot(4)
            return controller.bankDirty && controller.editorModel().release === changed
                && String(selectButton(a).text).slice(-1) === "*"
        }, 15000), "reopened tab A adopts the dirty shared bank")
        compare(fileProbe.fileFingerprint(bankPath()), bankBefore,
                "reopening the shared bank does not write it")

        clickSelectTab(b)
        close = closeButton(b)
        mouseClick(close, close.width / 2, close.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === b }, 5000),
               "tab B raises its gate for bank Save")
        verify(awaitGateButtons(), "tab B's bank Save gate shows its answers")
        var save = dialogButton("songTabSave")
        mouseClick(save, save.width / 2, save.height / 2)
        verify(waitForNative(function() {
            return tabs().tabCount === 1 && tabs().selectedId === a
                && String(selectButton(a).text).slice(-1) !== "*"
                && !controller.bankDirty
        }, 30000), "peer Save closes tab B and clears tab A's shared dirty caption")
        var bankSaved = fileProbe.fileFingerprint(bankPath())
        verify(bankSaved.length > 0 && bankSaved !== bankBefore,
               "peer Save persists the edited shared bank")

        controller.selectSlot(4)
        draft = controller.editorModel()
        draft.change("release", original)
        verify(waitForNative(function() { return controller.bankDirty }, 15000),
               "a later mounted edit dirties the shared bank for the close walk")
        session().openSong("mus_route102")
        verify(waitForNative(function() { return tabs().tabCount === 2 }, 30000),
               "the close walk has two tabs over the same dirty bank")
        b = tabs().selectedId
        waitForPage(b)
        shell.close()
        verify(waitForNative(function() { return tabs().pendingCloseId === a }, 5000),
               "the window close walk asks tab A first")
        verify(awaitGateButtons(), "the close walk shows tab A's answers")
        discard = dialogButton("songTabDiscard")
        mouseClick(discard, discard.width / 2, discard.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseId === b }, 5000),
               "the window close walk asks tab B second")
        verify(awaitGateButtons(), "the close walk shows tab B's answers")
        discard = dialogButton("songTabDiscard")
        mouseClick(discard, discard.width / 2, discard.height / 2)
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
        }, 5000), "the close walk asks the shared bank once after both tabs")
        verifyBankGate("the shared-bank close walk")
        discard = dialogButton("songTabDiscard")
        mouseClick(discard, discard.width / 2, discard.height / 2)
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 30000),
               "the answered shared bank completes the close walk without a second bank gate")
        compare(tabs().pendingCloseBankTitle, "", "the bank gate stays lowered")
        compare(fileProbe.fileFingerprint(bankPath()), bankSaved,
                "discarding the walk's unsaved edit preserves the last saved bank bytes")
    }
}
