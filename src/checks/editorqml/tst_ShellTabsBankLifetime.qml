import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellTabsSupport {
    SignalSpy {
        id: cancelledSpy
        target: shell ? shell.shellPresenter.session : null
        signalName: "closeCancelled"
    }

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
        verify(waitForNative(function() { return tabs().tabCount === 0 }, 5000),
               "closing the last song ignores independently dirty voicegroup work")
        compare(tabs().pendingCloseId, -1, "no song prompt is raised for a bank-only edit")
        compare(fileProbe.fileFingerprint(bankPath()), bankBefore, "closing a song writes no bank bytes")
        verify(controller.isBound && controller.bankDirty && controller.editorModel().editable,
               "the retained voicegroup stays bound, dirty and genuinely editable")
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
        var editedRelease = controller.editorModel().release
        session().openProject(bootstrap.projectRoot)
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
                || session().lastSaveError.length > 0
        }, 30000), "the switch asks about the orphan bank"
            + openDiagnostics(session()))
        verifyBankGate("the project switch")
        compare(fileProbe.fileFingerprint(bankPath()), orphan.bankBefore,
                "raising the bank gate wrote no bank bytes")

        var cancelButton = dialogButton("songTabCancel")
        mouseClick(cancelButton, cancelButton.width / 2, cancelButton.height / 2)
        verify(waitForNative(function() { return tabs().pendingCloseBankTitle === "" }, 5000),
               "Cancel lowers the bank gate")
        verify(session().projectOpen && controller.bankDirty
               && controller.editorModel().release === editedRelease,
               "Cancel retains the original project and exact unsaved voicegroup edit")
        verify(waitForNative(function() { return strip().enabled }, 5000),
               "Cancel hands the strip back")
        compare(fileProbe.fileFingerprint(bankPath()), orphan.bankBefore,
                "Cancel wrote no bank bytes")

        session().openProject(bootstrap.projectRoot)
        verify(waitForNative(function() {
            return tabs().pendingCloseBankTitle === "fixture_rich"
        }, 30000), "Cancel keeps the retained dirty owner protected on the next switch"
            + openDiagnostics(session()))
        verifyBankGate("the repeated project switch")
        var discardButton = dialogButton("songTabDiscard")
        mouseClick(discardButton, discardButton.width / 2, discardButton.height / 2)
        verify(waitForNative(function() {
            return !tabs().isClosingAll && !controller.isBound && session().projectOpen
        }, 30000), "Discard releases the old retained owner and installs the replacement project"
            + openDiagnostics(session()))
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
        const controller = session().voiceListController()
        const savedRelease = controller.editorModel().release
        tabs().confirmSave()
        verify(session().saveInProgress, "the bank Save is in flight")
        tabs().confirmDiscard()
        verify(session().saveInProgress, "a second answer does not replace the admitted Save")
        tabs().cancelClose()
        compare(tabs().pendingCloseBankTitle, "", "Cancel immediately lowers the bank gate")
        compare(tabs().isClosingAll, false, "Cancel immediately stops the close walk")
        verify(shell.shellPresenter.sceneActive && !shell.shellPresenter.closeReady,
               "Cancel retains the mounted editable window during the admitted Save")
        verify(waitForNative(function() { return !session().saveInProgress }, 30000),
               "the admitted bank Save settles after cancellation")
        verify(shell.shellPresenter.sceneActive && !shell.shellPresenter.closeReady
               && !tabs().isClosingAll && tabs().pendingCloseBankTitle === "",
               "the completed Save does not revive the cancelled window close")
        verify(controller.isBound && !controller.bankDirty && controller.editingEnabled
               && controller.editorModel().release === savedRelease,
               "the retained bank keeps its saved edit and is editable after cancellation")
        compare(session().lastSaveError, "", "the admitted bank Save reported no error")
        var bankAfter = fileProbe.fileFingerprint(bankPath())
        verify(bankAfter.length > 0 && bankAfter !== orphan.bankBefore,
               "Save wrote the orphaned bank to disk")
        shell.close()
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 30000),
               "a new explicit close completes after the retained bank was saved")
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
        var controller = session().voiceListController()
        var bankBefore = fileProbe.fileFingerprint(bankPath())
        var midiA = session().songMidiBytes("mus_route101")
        var midiB = session().songMidiBytes("mus_route102")
        var beforeA = summaryOf(a)
        var beforeB = summaryOf(b)
        clickSelectTab(a)
        controller.selectSlot(4)
        var draft = controller.editorModel()
        var original = draft.release
        var changed = original === 7 ? 6 : original + 1
        draft.change("release", changed)
        verify(waitForNative(function() {
            return controller.bankDirty && draft.release === changed
        }, 15000), "the first song edits the canonical group")
        verify(!session().documentDirty,
               "bank edits leave the selected song clean")
        verify(String(selectButton(a).text).slice(-1) !== "*"
               && String(selectButton(b).text).slice(-1) !== "*",
               "both song captions remain clean")
        compare(controller.panelTitle, "Voicegroup: fixture_rich*",
                "the named group alone shows its star")
        compare(session().songMidiBytes("mus_route101"), midiA)
        compare(session().songMidiBytes("mus_route102"), midiB)
        compare(summaryOf(a), beforeA)
        compare(summaryOf(b), beforeB)

        clickSelectTab(b)
        controller.selectSlot(0)
        var firstAttack = draft.attack
        var nextAttack = firstAttack === 255 ? 254 : firstAttack + 1
        draft.change("attack", nextAttack)
        verify(waitForNative(function() { return draft.attack === nextAttack }, 15000),
               "the second song appends a different slot to the same chronological group history")
        clickSelectTab(a)
        session().setEditingVoicegroup(true)
        session().requestUndo()
        verify(waitForNative(function() { return draft.attack === firstAttack }, 15000),
               "undo from A reverses B's most recent edit")
        controller.selectSlot(4)
        compare(draft.release, changed, "the earlier group edit is still applied")
        session().requestUndo()
        verify(waitForNative(function() { return draft.release === original && !controller.bankDirty }, 15000),
               "a second group undo returns the shared group to its saved point")

        drawNote(a)
        var editedNotes = summaryOf(a)
        draft.change("release", changed)
        verify(waitForNative(function() { return controller.bankDirty }, 15000))
        session().setEditingVoicegroup(false)
        session().requestUndo()
        verify(waitForNative(function() { return summaryOf(a) === beforeA }, 5000),
               "song undo restores notes without replaying group history")
        verify(editedNotes !== beforeA && controller.bankDirty && draft.release === changed,
               "the independent group edit survives song undo")
        session().setEditingVoicegroup(true)
        session().requestSaveVoicegroup()
        verify(waitForNative(function() { return !session().saveInProgress && !controller.bankDirty }, 30000))
        compare(session().songMidiBytes("mus_route101"), midiA)
        compare(session().songMidiBytes("mus_route102"), midiB)
        var bankSaved = fileProbe.fileFingerprint(bankPath())
        verify(bankSaved !== bankBefore, "only the group resource was persisted")

        draft.change("release", original)
        verify(waitForNative(function() { return controller.bankDirty }, 15000))
        tabs().requestClose(b)
        verify(waitForNative(function() { return tabs().tabCount === 1 }, 5000),
               "a bank-only peer closes without a song gate")
        tabs().requestClose(a)
        verify(waitForNative(function() { return tabs().tabCount === 0 }, 5000),
               "the last clean song also closes without discarding its group")
        compare(tabs().pendingCloseId, -1)
        verify(controller.isBound && draft.editable, "the zero-tab group editor remains live")
        var retained = draft.attack
        var retainedChanged = retained === 7 ? 6 : retained + 1
        draft.change("attack", retainedChanged)
        verify(waitForNative(function() {
            return !controller.bankBusy && controller.bankDirty && draft.attack === retainedChanged
        }, 15000), "a real parameter commit works after every song has closed")
        var retainedEditor = findChild(findChild(shell, "voicegroupPanel"), "voicegroupEditorSurface")
        var retainedAttack = findChild(retainedEditor, "vgAttackSpin")
        verify(waitForNative(function() {
            return retainedAttack && retainedAttack.visible && retainedAttack.enabled
                && retainedAttack.value === draft.attack
        }, 5000), "the retained parameter remains mounted and editable after its commit")
        session().setEditingVoicegroup(true)
        session().requestUndo()
        verify(waitForNative(function() {
            return draft.attack === retained && draft.release === original && controller.bankDirty
        }, 15000), "zero-tab undo restores its own field without discarding the prior group edit")
        session().requestSaveAll()
        verify(waitForNative(function() {
            return !session().saveInProgress && !controller.bankDirty
        }, 30000), "Save All includes a group with no song consumers")
        compare(session().lastSaveError, "")
        compare(fileProbe.fileFingerprint(bankPath()), bankBefore,
                "Save All persists the restored original group without songs")
    }

    function test_vBankSaveAndDiscardFailuresKeepClosePending() {
        var orphan = orphanDirtyBank()
        verify(fileProbe.moveSoundAside(bootstrap.projectRoot), "Save All resource outage is staged")
        try {
            session().requestSaveAll()
            verify(waitForNative(function() {
                return !session().saveInProgress && session().lastSaveError.indexOf("fixture_rich") >= 0
            }, 15000), "Save All identifies the failed zero-tab voicegroup owner")
            verify(orphan.controller.bankDirty, "failed Save All preserves unsaved bank work")
        } finally {
            verify(fileProbe.restoreSound(bootstrap.projectRoot), "Save All resource outage is restored")
        }
        shell.close()
        verify(waitForNative(function() { return tabs().pendingCloseBankTitle === "fixture_rich" }, 5000))
        var controller = orphan.controller
        var edited = controller.editorModel().release
        verify(fileProbe.moveSoundAside(bootstrap.projectRoot), "the resource outage is staged")
        try {
            tabs().confirmSave()
            verify(waitForNative(function() {
                return !session().saveInProgress && session().lastSaveError.length > 0
            }, 15000), "failed bank Save is observable")
            compare(tabs().pendingCloseBankTitle, "fixture_rich")
            verify(controller.bankDirty && !shell.shellPresenter.closeReady,
                   "failed Save neither answers the bank nor releases the project")
            var alert = findChild(shell, "shellCriticalDialog")
            if (alert)
                alert.close()
            tabs().confirmDiscard()
            verify(waitForNative(function() { return !session().saveInProgress }, 15000),
                   "failed bank Discard settles")
            compare(tabs().pendingCloseBankTitle, "fixture_rich")
            verify(controller.bankDirty && controller.editorModel().release === edited,
                   "failed Discard preserves the exact editable bank")
            alert = findChild(shell, "shellCriticalDialog")
            if (alert)
                alert.close()
        } finally {
            verify(fileProbe.restoreSound(bootstrap.projectRoot), "the resource outage is restored")
        }
        cancelledSpy.clear()
        tabs().cancelClose()
        verify(waitForNative(function() { return tabs().pendingCloseBankTitle === "" }, 5000))
        verify(waitForNative(function() { return cancelledSpy.count > 0 }, 5000),
               "Cancel reaches the mounted window close owner before another close request")
        verify(controller.editingEnabled && controller.editorModel().editable,
               "Cancel returns the retained bank to editing")
        shell.close()
        verify(waitForNative(function() { return tabs().pendingCloseBankTitle === "fixture_rich" }, 5000))
        tabs().confirmDiscard()
        verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 30000))
        verify(!controller.bankDirty, "real Discard restores the bank instead of suppressing a prompt")
        compare(fileProbe.fileFingerprint(bankPath()), orphan.bankBefore,
                "Discard never writes the unsaved bank edit")
    }

    function test_wRetainedPickerKeepsSavedHistoriesReachable() {
        var id = openShell(["mus_route101"])[0]
        var controller = dirtyOpenBank()
        var richRelease = controller.editorModel().release
        var selector = findChild(shell, "vgArgCombo")
        selector.forceActiveFocus()
        selector.editText = "fixture_alt"
        selector.contentItem.forceActiveFocus()
        keyClick(Qt.Key_Return)
        verify(waitForNative(function() { return controller.bankLoadName === "fixture_alt" }, 15000))
        controller.selectSlot(2)
        var draft = controller.editorModel()
        var originalAlt = draft.release
        var savedAlt = originalAlt === 7 ? 6 : originalAlt + 1
        draft.change("release", savedAlt)
        verify(waitForNative(function() { return controller.bankDirty && draft.release !== originalAlt }, 15000))
        session().setEditingVoicegroup(false)
        session().requestUndo()
        verify(waitForNative(function() {
            return controller.bankLoadName === "fixture_rich" && !session().documentDirty
        }, 15000), "assignment undo leaves both independent group histories intact")
        tabs().requestClose(id)
        verify(waitForNative(function() { return tabs().tabCount === 0 }, 5000))
        var panel = findChild(shell, "voicegroupPanel")
        verify(!!panel, "the retained voicegroup panel stays mounted without song tabs")
        var picker = findChild(panel, "retainedVoicegroupCombo")
        verify(!!picker, "the retained selector belongs to the mounted voicegroup panel")
        verify(waitForNative(function() {
            return !controller.hasSongContext && controller.retainedGroupNames.length === 2
                && picker.visible && picker.count === 2
        }, 5000), "the no-song dock renders both canonical retained groups: names="
            + controller.retainedGroupNames + " visible=" + picker.visible + " count=" + picker.count)
        session().requestSaveAll()
        verify(waitForNative(function() { return !session().saveInProgress && !controller.bankDirty }, 30000))
        compare(session().lastSaveError, "")
        compare(picker.count, 2, "saving groups does not strand either independent undo history")
        var alternate = controller.retainedGroupNames.findIndex(function(name) {
            return name === "fixture_alt"
        })
        verify(alternate >= 0)
        mouseClick(picker)
        tryCompare(picker.popup, "opened", true)
        var entry = picker.popup.contentItem.itemAtIndex(alternate)
        verify(entry !== null, "the retained alternate is a mounted picker row")
        mouseClick(entry)
        verify(waitForNative(function() { return controller.bankLoadName === "fixture_alt" }, 5000))
        controller.selectSlot(2)
        session().setEditingVoicegroup(true)
        session().requestUndo()
        verify(waitForNative(function() {
            return draft.release === originalAlt && controller.bankDirty
        }, 15000), "the saved alternate's own history remains undoable without songs")
        var rich = controller.retainedGroupNames.findIndex(function(name) {
            return name === "fixture_rich"
        })
        verify(rich >= 0)
        controller.selectRetainedVoicegroup(rich)
        controller.selectSlot(4)
        compare(draft.release, richRelease, "switching retained groups never replays the other history")
        compare(controller.bankDirty, false, "the other saved group stays clean")
        controller.selectRetainedVoicegroup(alternate)
        controller.selectSlot(2)
        session().requestRedo()
        verify(waitForNative(function() {
            return !controller.bankBusy && !controller.bankDirty && draft.release === savedAlt
        }, 15000), "returning to the saved alternate restores its own redo point")
    }

    function test_xProjectReleaseKeepsCanonicalInputGateAndCancelRestoresIt() {
        var id = openShell(["mus_route101"])[0]
        drawNote(id)
        shell.shellPresenter.activate("roll.select_all")
        verify(shell.shellPresenter.action("roll.transpose_up").enabled,
               "the initial song has an executable edit before the close gate")
        var edited = summaryOf(id)
        var pageStack = findChild(shell, "songTabPages")
        session().openProjectAndSong(bootstrap.projectRoot, "mus_route102")
        verify(waitForNative(function() { return tabs().pendingCloseId === id }, 30000),
               "project switch first protects the dirty song")
        tryCompare(pageStack, "enabled", false)
        verify(tabs().isClosingAll && !pageStack.enabled,
               "the canonical close walk disables only the editor pages")
        verify(awaitGateButtons(), "the modal close answers remain operable outside the gated pages")
        shell.shellPresenter.activate("roll.transpose_up")
        compare(summaryOf(id), edited, "no late song command enters a closing project")
        tabs().cancelClose()
        verify(waitForNative(function() {
            return !tabs().isClosingAll && pageStack.enabled && tabs().selectedId === id
        }, 5000), "Cancel restores the original project's canonical input state")
        compare(summaryOf(id), edited, "Cancel preserves the exact editable song")

        session().openProjectAndSong(bootstrap.projectRoot, "mus_route102")
        verify(waitForNative(function() { return tabs().pendingCloseId === id }, 30000))
        tabs().confirmDiscard()
        verify(tabs().isClosingAll && !pageStack.enabled,
               "confirmed close keeps input blocked before asynchronous teardown starts")
        shell.shellPresenter.activate("roll.transpose_up")
        compare(summaryOf(id), edited, "the confirmed close target cannot be changed across the release await")
        verify(waitForNative(function() {
            return !tabs().isClosingAll && tabs().selectedPage
                && tabs().selectedPage.title === "mus_route102"
        }, 30000), "only installing the replacement project ends the canonical closing state")
        verify(pageStack.enabled && session().voiceListController().editingEnabled,
               "new project ownership restores both song and voicegroup editing")
        compare(session().lastSaveError, "")
    }

    function test_yNoSongStandardSaveUsesRetainedOwnerAfterSongFocus() {
        var id = openShell(["mus_route101"])[0]
        var controller = session().voiceListController()
        verify(waitForNative(function() {
            return controller.isBound && !controller.isLoading && controller.bankLoadName === "fixture_rich"
        }, 15000))
        controller.selectSlot(4)
        var bankBefore = fileProbe.fileFingerprint(bankPath())
        var midiPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route101")
        var configPath = bootstrap.projectRoot + "/sound/songs/midi/midi.cfg"
        var midiBefore = fileProbe.fileFingerprint(midiPath)
        var configBefore = fileProbe.fileFingerprint(configPath)
        verify(bankBefore.length > 0 && midiBefore.length > 0 && configBefore.length > 0)
        var panel = findChild(shell, "voicegroupPanel")
        verify(!!panel, "Object exists")
        var editor = findChild(panel, "voicegroupEditorSurface")
        verify(!!editor, "Object exists")
        var scroll = findChild(panel, "voiceEditorScrollView")
        verify(!!scroll, "Object exists")
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        verify(waitForRendering(scroll))
        var release = findChild(editor, "vgReleaseSpin")
        verify(!!release, "Object exists")
        verify(release.visible && release.enabled)
        var original = controller.editorModel().release
        var changed = original === 7 ? 6 : original + 1
        release.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(original === 7 ? Qt.Key_Down : Qt.Key_Up)
        verify(waitForNative(function() {
            return !controller.bankBusy && controller.bankDirty
                && controller.editorModel().release === changed
        }, 15000))
        var roll = surfaceOf(id)
        verify(!!roll, "Object exists")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        tryCompare(session(), "editingVoicegroup", false, 3000)
        var close = closeButton(id)
        verify(!!close, "Object exists")
        mouseClick(close)
        verify(waitForNative(function() {
            return tabs().tabCount === 0 && !controller.hasSongContext
                && controller.isBound && controller.bankDirty
        }, 5000))
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        keySequence(StandardKey.Save)
        verify(waitForNative(function() {
            return !session().saveInProgress && !controller.bankBusy && !controller.bankDirty
        }, 30000))
        compare(session().lastSaveError, "")
        verify(fileProbe.fileFingerprint(bankPath()) !== bankBefore)
        compare(fileProbe.fileFingerprint(midiPath), midiBefore)
        compare(fileProbe.fileFingerprint(configPath), configBefore)
        compare(controller.editorModel().release, changed)
    }
}
