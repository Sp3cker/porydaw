import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellVoicegroupSupport {
    function test_zzzzzUnifiedSaveAndUndoRestorationReceipts() {
        const shell = createFullShell()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "unified receipt fixture opens: " + session.lastSaveError)
        compare(session.lastSaveError, "")
        const voice = session.voiceListController()
        tryCompare(voice, "isBound", true, 5000)
        voice.selectSlot(0)
        const midiPath = fileProbe.songPath(bootstrap.projectRoot, "mus_route101")
        const cfgPath = bootstrap.projectRoot + "/sound/songs/midi/midi.cfg"
        const bankPath = bootstrap.projectRoot + "/sound/voicegroups/fixture_rich.inc"
        const initialMidi = fileProbe.fileFingerprint(midiPath)
        const initialCfg = fileProbe.fileFingerprint(cfgPath)
        const initialBank = fileProbe.fileFingerprint(bankPath)
        verify(initialMidi.length > 0 && initialCfg.length > 0 && initialBank.length > 0,
               "unified save baseline MIDI, song flags and bank bytes are readable")
        const settings = shell.shellPresenter.settingsStore
        settings.open()
        const changedVolume = settings.masterVolume === 110 ? 111 : 110
        settings.changeMasterVolume(changedVolume)
        settings.apply()
        verify(waitForNative(function() {
            return !settings.isApplying && shell.shellPresenter.windowModified
        }, 15000), "mounted song config edit dirties the document: "
                  + "volume=" + settings.masterVolume + " modified="
                  + shell.shellPresenter.windowModified + " error=" + session.lastSaveError)
        compare(settings.masterVolume, changedVolume,
                "applied song setting retains the edited master volume")
        const draft = voice.editorModel()
        const previousRelease = draft.release
        const editedRelease = previousRelease === 255 ? 254 : previousRelease + 1
        draft.change("release", editedRelease)
        verify(waitForNative(function() {
            return draft.release === editedRelease && voice.bankDirty
        }, 15000), "mounted bank edit joins the dirty song save")
        const editor = findChild(shell, "voicegroupEditorSurface")
        const save = findChild(editor, "vgSaveButton")
        verify(save && save.enabled, "mounted bank Save handles the unified dirty journey")
        const scroll = findChild(shell, "voiceEditorScrollView")
        verify(scroll !== null, "the mounted Save belongs to its editor viewport")
        waitForFullShellScene()
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        waitForFullShellScene()
        const saveCenter = save.mapToItem(scroll, save.width / 2, save.height / 2)
        verify(save.visible && save.width > 0 && save.height > 0
               && saveCenter.x >= 0 && saveCenter.x < scroll.width
               && saveCenter.y >= 0 && saveCenter.y < scroll.height,
               "the Save click targets the real button inside its clipped editor viewport")
        const beforeStarts = shellSaveStarts
        const beforeFinishes = shellSaveFinishes
        mouseClick(save)
        verify(waitForNative(function() {
            return !session.saveInProgress && !voice.bankDirty
                   || session.lastSaveError.length > 0
        }, 15000), "unified Save completes: " + session.lastSaveError)
        verify(session.lastSaveError === "" && shellSaveStarts === beforeStarts + 1
               && shellSaveFinishes === beforeFinishes + 1 && !voice.bankDirty
               && !shell.shellPresenter.windowModified,
               "unified Save completes one clean song-and-bank receipt")
        verify(fileProbe.fileFingerprint(cfgPath) !== initialCfg
               && fileProbe.fileFingerprint(bankPath) !== initialBank
               && fileProbe.fileFingerprint(midiPath) === initialMidi,
               "unified Save persists song flags and bank bytes without changing MIDI")
        session.requestUndo()
        verify(waitForNative(function() { return voice.bankDirty }, 15000),
               "undo after Save dirties the saved bank")
        session.requestUndo()
        verify(waitForNative(function() {
            return shell.shellPresenter.windowModified && draft.release === previousRelease
        }, 15000), "restoration undo dirties the saved song and restores the bank voice")
        const restoreStarts = shellSaveStarts
        const restoreFinishes = shellSaveFinishes
        mouseClick(save)
        verify(waitForNative(function() {
            return !session.saveInProgress && !voice.bankDirty
                   || session.lastSaveError.length > 0
        }, 15000), "restoration Save completes: " + session.lastSaveError)
        verify(session.lastSaveError === "" && shellSaveStarts === restoreStarts + 1
               && shellSaveFinishes === restoreFinishes + 1 && !voice.bankDirty
               && !shell.shellPresenter.windowModified,
               "undo restoration Save completes one clean receipt")
        compare(fileProbe.fileFingerprint(cfgPath), initialCfg,
                "restoration Save writes the original song flags")
        compare(fileProbe.fileFingerprint(midiPath), initialMidi,
                "restoration Save preserves the original MIDI")
        compare(fileProbe.fileFingerprint(bankPath), initialBank,
                "restoration Save writes the original bank")
        const selector = findChild(shell, "vgArgCombo")
        selector.editText = "_porydaw_missing_voicegroup"
        selector.contentItem.forceActiveFocus()
        keyClick(Qt.Key_Return)
        verify(waitForNative(function() {
            return session.lastSaveError.indexOf("_porydaw_missing_voicegroup") >= 0
        }, 15000), "missing -G publishes the failed bank-load argument")
        verify(shell.shellPresenter.statusText.indexOf("_porydaw_missing_voicegroup") >= 0,
               "missing -G failure appears in the mounted shell status")
        const renderedStatus = findChild(shell, "shellStatusText")
        verify(renderedStatus !== null && renderedStatus.visible,
               "missing -G failure renders a visible shell status item")
        compare(renderedStatus.text, "No voicegroup file declares voicegroup_porydaw_missing_voicegroup.",
                "missing -G status retains the fork failure wording")
        compare(renderedStatus.text, session.lastSaveError,
                "rendered missing -G failure matches the session error")
        verify(!renderedStatus.truncated,
               "missing -G argument remains fully visible in the shell status text")
        compare(voice.selectorText, "porydaw_missing_voicegroup",
                "missing -G publishes the edited selector display")
        compare(voice.bankLoadName, "fixture_rich",
                "missing -G leaves the previously loaded voicegroup available")
        session.requestUndo()
        verify(waitForNative(function() {
            return voice.selectorText === "fixture_rich"
                   && !shell.shellPresenter.windowModified && !voice.bankDirty
        }, 15000), "undo of missing -G returns the song to its clean saved binding")
        cleanup()
    }

    function test_zzzzzzReleaseBoundaryEditsLeaveSongClean() {
        const shell = createFullShell()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "release boundary fixture opens: " + session.lastSaveError)
        compare(session.lastSaveError, "")
        const voice = session.voiceListController()
        tryCompare(voice, "isBound", true, 5000)
        voice.selectSlot(0)
        const scroll = findChild(shell, "voiceEditorScrollView")
        verify(scroll !== null, "voice editor scroll view mounts after the song opens")
        waitForRendering(scroll)
        const editor = findChild(shell, "voicegroupEditorSurface")
        tryVerify(function() { return !!findChild(editor, "vgReleaseSpin") }, 5000,
                  "the mounted sample release field loads with the bank")
        const release = findChild(editor, "vgReleaseSpin")
        verify(release && release.enabled, "sample release spin is mounted")
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        waitForRendering(release)
        const initial = release.value
        const bankPath = bootstrap.projectRoot + "/sound/voicegroups/fixture_rich.inc"
        const persisted = fileProbe.fileFingerprint(bankPath)
        verify(persisted.length > 0, "release fixture bank bytes are readable")
        release.contentItem.forceActiveFocus()
        keyClick(initial === release.to ? Qt.Key_Down : Qt.Key_Up)
        const adjacent = initial === release.to ? initial - 1 : initial + 1
        tryCompare(release, "value", adjacent, 15000,
                   "mounted release spin accepts an adjacent value")
        verify(waitForNative(function() { return voice.bankDirty }, 15000),
               "adjacent release edit dirties the bank")
        compare(shell.shellPresenter.windowModified, false,
                "adjacent bank edit leaves the document window unmodified")
        const undoAction = findChild(shell, "shellAction_edit.undo")
        verify(undoAction && undoAction.enabled && release.contentItem.activeFocus,
               "focused release field offers the standard window Undo action")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return release.value === initial && !voice.bankDirty
                   && !session.documentDirty && !shell.shellPresenter.windowModified
        }, 15000), "one focused standard Undo restores the exact release and clean song and bank")
        compare(fileProbe.fileFingerprint(bankPath), persisted,
                "focused Undo does not write the previously persisted bank bytes")
        keyClick(initial === release.to ? Qt.Key_Down : Qt.Key_Up)
        verify(waitForNative(function() { return release.value === adjacent && voice.bankDirty },
               15000), "a new release edit remains possible after focused Undo")
        const settings = shell.shellPresenter.settingsStore
        settings.open()
        const editedVolume = settings.masterVolume === 110 ? 111 : 110
        settings.changeMasterVolume(editedVolume)
        settings.apply()
        verify(waitForNative(function() {
            return !settings.isApplying && shell.shellPresenter.windowModified
        }, 15000), "song setting application independently marks the document window modified")
        verify(settings.masterVolume === editedVolume && session.documentDirty && voice.bankDirty,
               "song setting retains its value and dirties the document while the bank remains dirty")
        session.requestUndo()
        verify(waitForNative(function() {
            return !shell.shellPresenter.windowModified && voice.bankDirty
        }, 15000), "undo of the song setting clears the window but leaves the separate bank edit dirty")
        release.contentItem.forceActiveFocus()
        for (let value = adjacent; value > 0; --value)
            keyClick(Qt.Key_Down)
        tryCompare(release, "value", 0, 15000,
                   "mounted release spin accepts the lower boundary")
        compare(voice.bankDirty, true, "zero release leaves the bank dirty")
        compare(shell.shellPresenter.windowModified, false,
                "zero release leaves the song window unmodified")
        for (let value = 0; value < release.to; ++value)
            keyClick(Qt.Key_Up)
        tryCompare(release, "value", 255, 15000,
                   "mounted release spin accepts the upper boundary")
        compare(voice.bankDirty, true, "255 release leaves the bank dirty")
        compare(shell.shellPresenter.windowModified, false,
                "255 release leaves the song window unmodified")
        compare(fileProbe.fileFingerprint(bankPath), persisted,
                "release edits never save the bank without Save")
        cleanup()
    }

    function test_zzSynthMintAndMountedSave() {
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const draft = controller.editorModel()
        verify(waitForNative(function() { return controller.canMintSynths }, 5000),
               "the deferred synth catalog is ready before minting")
        compare(controller.canMintSynths, true)
        draft.changeType(0, "DirectSoundWaveData_fixture_loop")
        verify(waitForNative(function() {
            return draft.macro === 0 && !draft.isSynth && controller.currentSlot === 0
        }, 15000), "slot zero is a non-synth DirectSound voice before Synth selection")
        tryCompare(findChild(panel, "voicegroupEditorSurface"), "visibleRows", 3)
        waitForRendering(panel)
        const typeControl = findChild(panel, "vgTypeCombo")
        const samplePicker = findChild(panel, "vgSymbolPicker")
        const release = findChild(panel, "vgReleaseSpin")
        verify(typeControl !== null && typeControl.visible && typeControl.enabled
               && typeControl.indexOfValue(-1) >= 0
               && samplePicker !== null && samplePicker.visible && samplePicker.enabled
               && release !== null && release.visible && release.enabled,
               "DirectSound slot zero offers an enabled Synth type, sample picker, and ADSR release")
        const waveformBeforeSwitch = findChild(panel, "vgSynthWaveformCombo")
        const baseDutyBeforeSwitch = findChild(panel, "vgSynthBaseDutySpin")
        const dutyStepBeforeSwitch = findChild(panel, "vgSynthDutyStepSpin")
        const modDepthBeforeSwitch = findChild(panel, "vgSynthModDepthSpin")
        const phaseBeforeSwitch = findChild(panel, "vgSynthPhaseSpin")
        verify(waveformBeforeSwitch !== null && !waveformBeforeSwitch.visible
               && baseDutyBeforeSwitch !== null && !baseDutyBeforeSwitch.visible
               && dutyStepBeforeSwitch !== null && !dutyStepBeforeSwitch.visible
               && modDepthBeforeSwitch !== null && !modDepthBeforeSwitch.visible
               && phaseBeforeSwitch !== null && !phaseBeforeSwitch.visible,
               "non-synth DirectSound keeps preconstructed waveform and pulse fields hidden")
        draft.changeType(-1, draft.symbol)
        verify(waitForNative(function() { return draft.isSynth && controller.bankDirty },
                             15000), "synth type creates an unsaved bank edit")
        const row = findChild(panel, "voicegroupRow_0")
        const icon = findChild(panel, "voicegroupTypeIcon_0")
        verify(row.typeName === "Synth (Golden Sun)"
               && row.typeIconKey === 0 && icon.Accessible.name === row.typeName,
               "the adopted synth publishes its type and sample glyph")
        const waveform = findChild(panel, "vgSynthWaveformCombo")
        verify(waveform !== null && waveform.visible, "mounted synth waveform is visible")
        compare(draft.waveform, 0)
        const editorScroll = findChild(panel, "voiceEditorScrollView")
        editorScroll.contentY = Math.max(0, editorScroll.contentHeight - editorScroll.height)
        waitForRendering(waveform)
        mouseClick(waveform)
        const pulseChoice = waveform.popup.contentItem.itemAtIndex(0)
        verify(pulseChoice !== null, "mounted waveform popup offers Pulse")
        mouseClick(pulseChoice)
        tryCompare(waveform, "currentIndex", 0, 5000,
                   "mounted waveform activation selects Pulse")
        draft.changeSynth("baseDuty", 77)
        verify(waitForNative(function() { return draft.baseDuty === 77 }, 15000),
               "duty LFO mints an edited pulse voice")
        const initialPulse = draft.symbol
        verify(/^DirectSoundSynth_GoldenSun_4D[0-9A-F]{6}$/.test(initialPulse)
               && !controller.synthCatalogChoices().includes(initialPulse),
               "synth activation publishes the param-named symbol")
        const baseDuty = findChild(panel, "vgSynthBaseDutySpin")
        verify(baseDuty !== null && baseDuty.visible, "pulse parameters occupy the editor")
        compare(baseDuty.value, 77)
        for (const step of [
            { name: "DutyStep", field: "dutyStep", suffix: "4D010000" },
            { name: "ModDepth", field: "modDepth", suffix: "4D010100" },
            { name: "Phase", field: "phase", suffix: "4D010101" }
        ]) {
            const spin = findChild(panel, "vgSynth" + step.name + "Spin")
            verify(spin !== null && spin.visible,
                   "mounted synth " + step.name + " parameter exists")
            spin.forceActiveFocus()
            keyClick(Qt.Key_Up)
            verify(waitForNative(function() {
                return draft[step.field] === 1
                    && draft.symbol === "DirectSoundSynth_GoldenSun_" + step.suffix
            }, 15000), "synth " + step.field + " commits its cumulative param-named symbol")
        }
        const pulse = draft.symbol
        verify(controller.synthCatalogChoices().indexOf(pulse) < 0,
               "uncommitted synth does not masquerade as a saved definition")
        const startsBefore = saveStarts
        const finishesBefore = saveFinishes
        const save = findChild(panel, "vgSaveButton")
        mousePress(save, save.width / 2, save.height / 2)
        mouseRelease(save, save.width / 2, save.height / 2)
        verify(waitForNative(function() { return saveStarts === startsBefore + 1 }, 5000),
               "synth Save starts one real completion receipt")
        verify(waitForNative(function() {
            return (!controller.bankDirty && controller.synthCatalogChoices().includes(pulse))
                   || app.lastSaveError.length > 0
        }, 15000), "save persists synth and refreshes catalog: " + app.lastSaveError)
        compare(app.lastSaveError, "")
        verify(!app.saveInProgress && saveFinishes === finishesBefore + 1
               && !controller.bankDirty && !app.documentDirty,
               "saved synth completes one receipt with a clean bank and document")
        const bankPath = bootstrap.projectRoot + "/sound/voicegroups/fixture_rich.inc"
        const pulseBytes = fileProbe.fileFingerprint(bankPath)
        verify(pulseBytes.length > 0, "the saved synth bank bytes are readable")
        compare(draft.symbol, pulse)
        draft.changeSynth("waveform", 1)
        verify(waitForNative(function() {
            return draft.isSynth && draft.waveform === 1 && draft.symbol !== pulse
        }, 15000), "waveform edit mints a saw")
        compare(baseDuty.visible, false, "non-pulse waveforms hide duty LFO controls")
        app.requestUndo()
        verify(waitForNative(function() {
            return draft.symbol === pulse && draft.waveform === 0
        }, 15000), "undo restores saved pulse voice")
        editorScroll.contentY = Math.max(0, editorScroll.contentHeight - editorScroll.height)
        waitForRendering(waveform)
        mouseClick(waveform)
        mouseClick(waveform.popup.contentItem.itemAtIndex(0))
        verify(waitForNative(function() { return draft.waveform === 0 }, 15000),
               "mounted waveform returns to Pulse after a saw edit")
        const pulseDepth = draft.modDepth
        draft.changeSynth("modDepth", pulseDepth === 255 ? 254 : pulseDepth + 1)
        controller.selectSlot(4)
        const otherRelease = draft.release
        draft.change("release", otherRelease === 7 ? 6 : otherRelease + 1)
        verify(waitForNative(function() { return draft.release !== otherRelease }, 15000),
               "selected slot commits after the obsolete synth request")
        controller.selectSlot(0)
        compare(draft.symbol, pulse, "stale synth change cannot retarget another slot")
        compare(draft.modDepth, pulseDepth, "obsolete synth descriptor remains unchanged")
        controller.selectSlot(4)
        app.requestUndo()
        verify(waitForNative(function() { return draft.release === otherRelease }, 15000),
               "undo removes only the selected slot's edit")
        controller.selectSlot(0)
        draft.changeSynth("waveform", 1)
        verify(waitForNative(function() {
            return draft.waveform === 1 && controller.bankDirty
        }, 15000), "saw edit prepares the saved synth's undo journey")
        mouseClick(save, save.width / 2, save.height / 2)
        verify(waitForNative(function() {
            return !app.saveInProgress && !controller.bankDirty
                   || app.lastSaveError.length > 0
        }, 15000), "saw save completes before restoration: " + app.lastSaveError)
        compare(app.lastSaveError, "")
        app.requestUndo()
        verify(waitForNative(function() {
            return draft.symbol === pulse && controller.bankDirty
        }, 15000), "undo of the saved saw dirties the pulse restoration")
        const restoreStarts = saveStarts
        const restoreFinishes = saveFinishes
        const scroll = findChild(panel, "voiceEditorScrollView")
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        waitForRendering(save)
        verify(save.enabled, "post-undo synth Save remains enabled for restored dirty pulse")
        mousePress(save, save.width / 2, save.height / 2)
        mouseRelease(save, save.width / 2, save.height / 2)
        verify(waitForNative(function() { return saveStarts === restoreStarts + 1 }, 5000),
               "post-undo Save starts exactly one completed-save receipt")
        verify(waitForNative(function() {
            return !app.saveInProgress && !controller.bankDirty || app.lastSaveError.length > 0
        }, 15000), "post-undo synth Save completes: " + app.lastSaveError)
        verify(app.lastSaveError === "" && saveFinishes === restoreFinishes + 1
               && !controller.bankDirty && !app.documentDirty,
               "post-undo synth Save completes cleanly with one receipt")
        compare(fileProbe.fileFingerprint(bankPath), pulseBytes,
                "restoring the saved pulse reproduces its bank bytes")
    }

    function test_referenceProfileCapture() {
        const controller = app.voiceListController()
        controller.selectSlot(0)
        capture("")
        controller.selectSlot(4)
        capture("editor-square1")
        controller.selectSlot(12)
        compare(controller.editorModel().notice, "Cry voices are read-only.")
        capture("editor-readonly")
    }

    function test_zzzzSharedBankBetweenTwoLiveTabs() {
        const tabs = app.songTabs
        const firstId = tabs.selectedId
        app.openSong("mus_route102")
        verify(waitForNative(function() {
            return tabs.tabCount === 2 && tabs.selectedId !== firstId
                   || app.lastSaveError.length > 0
        }, 30000), "second shared-bank song opens: " + app.lastSaveError)
        compare(app.lastSaveError, "")
        const peerId = tabs.selectedId
        compare(tabs.selectedPage.title, "mus_route102")
        const controller = app.voiceListController()
        controller.selectSlot(4)
        const release = findChild(panel, "vgReleaseSpin")
        const scroll = findChild(panel, "voiceEditorScrollView")
        verify(scroll !== null, "shared-bank editor scroll is mounted")
        verify(waitForNative(function() {
            return !controller.isLoading && controller.currentSlot === 4
                   && release !== null && release.value === controller.editorModel().release
        }, 5000), "the newly opened peer publishes its mounted slot-four value")
        verify(release !== null && release.visible && release.enabled,
               "mounted release spin is available for the shared bank")
        const peerBefore = release.value
        tabs.selectTab(firstId)
        verify(waitForNative(function() {
            return tabs.selectedId === firstId && controller.bankLoadName === "fixture_rich"
        }, 5000), "first live document reselects the shared bank")
        controller.selectSlot(4)
        const draft = controller.editorModel()
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        compare(draft.release, peerBefore)
        const edited = peerBefore === release.to ? peerBefore - 1 : peerBefore + 1
        mouseClick(release, release.width / 2, release.height / 2, Qt.LeftButton)
        keyClick(peerBefore === release.to ? Qt.Key_Down : Qt.Key_Up)
        verify(waitForNative(function() {
            return controller.bankDirty && draft.release === edited && release.value === edited
        }, 15000), "first document commits its mounted numeric release edit")

        tabs.selectTab(peerId)
        verify(waitForNative(function() {
            return tabs.selectedId === peerId && controller.editorModel().release === edited
                   && release.value === edited
                   && controller.bankDirty
        }, 15000), "already-open peer presents edited voice and dirty bank")
        const save = findChild(panel, "vgSaveButton")
        verify(save !== null && save.enabled, "peer offers mounted Save for the shared dirty bank")
        mouseClick(save, save.width / 2, save.height / 2)
        verify(waitForNative(function() {
            return !controller.bankDirty || app.lastSaveError.length > 0
        }, 15000), "peer Save completes: " + app.lastSaveError)
        compare(app.lastSaveError, "")
        compare(release.value, edited, "peer's mounted release spin retains the saved voice")
        tabs.selectTab(firstId)
        verify(waitForNative(function() {
            return tabs.selectedId === firstId && !controller.bankDirty
                   && controller.editorModel().release === edited && release.value === edited
        }, 15000), "clean saved bank and numeric editor publish back to the first tab")
    }
}
