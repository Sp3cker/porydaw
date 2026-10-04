import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellVoicegroupSupport {
    SampleBinProbe { id: sampleHeader }

    function expectedDetail(symbol, looped) {
        verify(sampleHeader.inspect(bootstrap.projectRoot
                                    + "/sound/direct_sound_samples/" + symbol + ".bin"),
               "fixture header independently decodes " + symbol)
        compare(sampleHeader.looped, looped, "fixture loop flag " + symbol)
        return (looped ? "Loops" : "One-shot") + " · " + sampleHeader.rateHz
               + " Hz · " + sampleHeader.seconds.toFixed(2) + " s"
    }

    function pickerBadge(list, index) {
        list.positionViewAtIndex(index, ListView.Contain)
        tryVerify(function() { return !!list.itemAtIndex(index) }, 5000,
                  "picker row is mounted for badge inspection")
        return findChild(list.itemAtIndex(index), "vgSamplePickerLoopBadge")
    }

    function test_wDrumkitTypeListsCatalogDrumkits() {
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const draft = controller.editorModel()
        compare(draft.macro, 0, "slot zero starts as a DirectSound voice")
        const combo = findChild(panel, "vgDrumkitCombo")
        verify(combo !== null, "the voice editor mounts its drumkit selector before the catalog")
        verify(waitForNative(function() { return controller.drumkitChoices().length === 2 }, 15000),
               "the project catalog publishes the fixture drumkits")
        draft.changeType(12, "")
        verify(waitForNative(function() { return draft.macro === 12 }, 15000),
               "choosing the Drumkit type converts the voice")
        tryCompare(combo, "visible", true, 5000, "a drumkit voice shows the drumkit selector")
        compare(combo.editText, "fixture_drums_a", "the converted voice names the first drumkit")
        findChild(panel, "voiceEditorScrollView").contentY = 0
        waitForRendering(combo)
        mouseClick(combo.indicator, combo.indicator.width / 2, combo.indicator.height / 2)
        tryCompare(combo.popup, "opened", true, 5000, "the drumkit dropdown opens")
        compare(combo.count, 2, "the open dropdown lists both catalog drumkits")
        compare(combo.textAt(1), "fixture_drums_b", "the dropdown rows name the catalog drumkits")
        combo.popup.close()
        app.requestUndo()
        verify(waitForNative(function() { return draft.macro === 0 }, 15000),
               "undo restores the DirectSound voice")
    }

    function test_xMountedPickerVisibilityAndMetadata() {
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const draft = controller.editorModel()
        compare(draft.macro, 0, "A013 DirectSound picker belongs to the selected slot")
        const trigger = findChild(panel, "vgSamplePickerButton")
        verify(trigger !== null, "A013 DirectSound slot mounts its picker trigger")
        tryVerify(function() { return trigger.visible }, 5000,
                  "selected DirectSound slot shows the picker trigger")
        const scroll = findChild(panel, "voiceEditorScrollView")
        scroll.contentY = 0
        waitForRendering(trigger)
        mouseClick(trigger, trigger.width / 2, trigger.height / 2)
        const popup = findChild(panel, "vgSamplePickerPopup")
        verify(popup !== null, "A014 picker trigger creates the popup")
        tryCompare(popup, "opened", true, 5000, "A015 picker popup becomes visible")
        const list = findChild(popup, "vgSamplePickerList")
        const detail = findChild(popup, "vgSamplePickerDetail")
        const loop = "DirectSoundWaveData_fixture_loop"
        const drum = "DirectSoundWaveData_fixture_drum"
        verify(waitForNative(function() {
            return controller.pickerDetail(loop, false, false).length > 0
        }, 15000), "picker reads the committed sample set on open")
        verify(waitForNative(function() {
            return list.model.some(row => row.symbol === loop)
                   && list.model.some(row => row.symbol === drum)
        }, 15000), "loop and one-shot rows populate from the project catalog")
        const loopIndex = list.model.findIndex(row => row.symbol === loop)
        const drumIndex = list.model.findIndex(row => row.symbol === drum)
        const loopBadge = pickerBadge(list, loopIndex)
        verify(loopBadge !== null && loopBadge.visible && loopBadge.text === "∞",
               "looped sample carries the infinity badge")
        compare(loopBadge.ToolTip.text, "Loops", "loop badge explains its meaning")
        const drumBadge = pickerBadge(list, drumIndex)
        verify(drumBadge !== null && !drumBadge.visible,
               "one-shot sample does not carry the badge")
        for (let index = 0; index < list.model.length; index++) {
            const row = list.model[index]
            const badge = pickerBadge(list, index)
            verify(badge !== null, "each picker row owns a badge position")
            compare(badge.visible,
                    !!row.symbol && !row.split && !row.typed
                    && controller.pickerRowLoops(row.symbol),
                    "only looped sample row shows badge: " + row.symbol)
        }
        list.currentIndex = loopIndex
        tryCompare(detail, "text", expectedDetail("fixture_loop", true))
        list.currentIndex = drumIndex
        tryCompare(detail, "text", expectedDetail("fixture_drum", false))
        const splitIndex = list.model.findIndex(row => row.symbol === "fixture_bass")
        verify(splitIndex >= 0, "keysplit row exists")
        list.currentIndex = splitIndex
        compare(detail.text, "Keysplit instrument", "keysplit uses the fork detail")
        const search = findChild(popup, "vgSamplePickerSearch")
        search.text = "unlisted_typography_sample"
        const typedIndex = list.model.findIndex(row => row.typed)
        verify(typedIndex >= 0, "typed row exists")
        list.currentIndex = typedIndex
        compare(detail.text, "Unlisted symbol", "typed row uses the fork detail")
        const editor = findChild(panel, "voicegroupEditorSurface")
        editor.visible = false
        tryCompare(popup, "opened", false, 5000,
                   "A017 popup closes when its editor dock hides")
        editor.visible = true
    }

    function test_yPickerReturnFallbackAndWaveUndo() {
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const draft = controller.editorModel()
        const sampleOriginal = draft.symbol
        function openPicker() {
            const trigger = findChild(panel, "vgSamplePickerButton")
            const editorScroll = findChild(panel, "voiceEditorScrollView")
            editorScroll.contentY = 0
            waitForRendering(trigger)
            mousePress(trigger, trigger.width / 2, trigger.height / 2)
            mouseRelease(trigger, trigger.width / 2, trigger.height / 2)
            const popup = findChild(panel, "vgSamplePickerPopup")
            tryCompare(popup, "opened", true)
            return popup
        }
        let popup = openPicker()
        verify(popup.parent.currentEntry()
               && popup.parent.currentEntry().symbol === sampleOriginal,
               "picker opens with the selected sample symbol current")
        let search = findChild(popup, "vgSamplePickerSearch")
        let list = findChild(popup, "vgSamplePickerList")
        search.text = "unlisted_typography_sample"
        verify(list.model.some(row => row.typed && row.symbol === search.text),
               "the picker offers a fallback row for an unlisted symbol")
        search.forceActiveFocus()
        keyClick(Qt.Key_Return)
        tryCompare(popup, "opened", false)
        verify(waitForNative(function() {
            return draft.symbol === "unlisted_typography_sample"
        }, 15000), "an unlisted typed symbol commits via the fallback row")
        app.requestUndo()
        verify(waitForNative(function() { return draft.symbol === sampleOriginal }, 15000),
               "picker undo restores the symbol and preview")
        popup = openPicker()
        verify(popup.parent.currentEntry()
               && popup.parent.currentEntry().symbol === sampleOriginal,
               "picker undo republishes the original sample symbol as current")
        popup.close()
        draft.changeType(7, "ProgrammableWaveData_fixture_pulse")
        verify(waitForNative(function() { return draft.macro === 7 }, 15000),
               "wave mode lists the catalog's waves with full symbols")
        popup = openPicker()
        verify(popup.parent.currentEntry()
               && popup.parent.currentEntry().symbol === "ProgrammableWaveData_fixture_pulse",
               "wave picker opens with the selected wave symbol current")
        search = findChild(popup, "vgSamplePickerSearch")
        list = findChild(popup, "vgSamplePickerList")
        verify(list.model.some(row => row.symbol === "ProgrammableWaveData_fixture_saw")
               && list.model.every(row => !row.symbol
                                    || row.symbol.startsWith("ProgrammableWaveData_")),
               "wave mode lists the catalog's waves with full symbols")
        search.text = "ProgrammableWaveData_fixture_saw"
        const index = list.model.findIndex(row => row.symbol === search.text)
        verify(index >= 0 && list.currentIndex === index,
               "filtering a wave auditions as wave")
        search.forceActiveFocus()
        keyClick(Qt.Key_Return)
        tryCompare(popup, "opened", false)
        verify(waitForNative(function() {
            return draft.symbol === "ProgrammableWaveData_fixture_saw"
        }, 15000), "Return commits the typed wave symbol")
        app.requestUndo()
        verify(waitForNative(function() {
            return draft.symbol === "ProgrammableWaveData_fixture_pulse" && draft.macro === 7
        }, 15000), "wave undo restores the wave voice and the DirectSound original")
        app.requestUndo()
        verify(waitForNative(function() {
            return draft.symbol === sampleOriginal && draft.macro === 0
        }, 15000), "wave undo restores the wave voice and the DirectSound original")
    }

    function test_zPickerAuditionsAndCommitsSampleWaveAndKeysplit() {
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const draft = controller.editorModel()
        function choose(symbol) {
            const trigger = findChild(panel, "vgSamplePickerButton")
            verify(trigger !== null, "mounted sample picker exists")
            tryVerify(function() { return trigger.visible }, 5000,
                      "sample picker becomes visible for macro " + draft.macro
                      + " synth=" + draft.isSynth + " symbol=" + draft.symbol)
            const position = trigger.mapToItem(panel, 0, 0)
            verify(position.y >= 0 && position.y < panel.height,
                   "sample picker is onscreen at " + position.y
                   + " panel=" + panel.height + " triggerHeight=" + trigger.height)
            mousePress(trigger, trigger.width / 2, trigger.height / 2)
            verify(trigger.down, "sample trigger receives press at "
                   + position.x + "," + position.y + " size "
                   + trigger.width + "x" + trigger.height)
            mouseRelease(trigger, trigger.width / 2, trigger.height / 2)
            const popup = findChild(panel, "vgSamplePickerPopup")
            verify(popup !== null, "popup is mounted")
            tryCompare(popup, "opened", true, 1000,
                       "popup opens after clicking button at " + position.x + "," + position.y)
            const search = findChild(popup, "vgSamplePickerSearch")
            const list = findChild(popup, "vgSamplePickerList")
            compareRole(search, "body", "sample picker search")
            compareRole(trigger, "body", "sample picker trigger")
            compareRole(popup, "body", "sample picker popup")
            compareRole(findChild(popup, "vgSamplePickerDetail"), "body", "sample picker detail")
            compare(popup.width, Math.max(trigger.width, app.baseFontPx * 28.33),
                    "sample picker width follows the session base")
            compare(popup.height, app.baseFontPx * 35,
                    "sample picker height follows the session base")
            compare(popup.background.border.color.toString().toLowerCase(),
                    panel.colors.outline.toString().toLowerCase(),
                    "sample popup outline follows the dock palette")
            if (draft.macro === 7 || draft.macro === 8) {
                verify(list.model.some(row => row.symbol === "ProgrammableWaveData_fixture_saw")
                       && list.model.every(row => !row.symbol
                                           || row.symbol.startsWith("ProgrammableWaveData_")),
                       "wave mode filters out samples and keysplits")
            }
            if (symbol === "DirectSoundWaveData_fixture_bass") {
                const headingIndex = list.model.findIndex(row => !row.symbol)
                verify(headingIndex >= 0, "sample picker preserves grouped section headings")
                list.positionViewAtIndex(headingIndex, ListView.Contain)
                tryVerify(function() { return !!list.itemAtIndex(headingIndex) }, 1000,
                          "sample picker section header is mounted")
                compareRole(findChild(list.itemAtIndex(headingIndex), "vgSamplePickerRowText"),
                            "bodyBold", "sample picker section heading")
            }
            search.text = "unlisted_typography_sample"
            const typedIndex = list.model.findIndex(row => row.typed)
            verify(typedIndex >= 0, "sample picker offers the typed symbol fallback")
            list.positionViewAtIndex(typedIndex, ListView.Contain)
            tryVerify(function() { return !!list.itemAtIndex(typedIndex) }, 1000,
                      "sample picker typed fallback is mounted")
            const typedText = findChild(list.itemAtIndex(typedIndex), "vgSamplePickerRowText")
            compareRole(typedText, "body", "sample picker typed fallback")
            compare(typedText.font.italic, true,
                    "sample picker typed fallback uses the published body's italic variant")
            search.text = symbol
            tryVerify(function() {
                return list.model.some(function(row) { return row.symbol === symbol })
            }, 5000, "search finds " + symbol)
            const index = list.model.findIndex(function(row) { return row.symbol === symbol })
            list.positionViewAtIndex(index, ListView.Contain)
            tryVerify(function() { return list.itemAtIndex(index) !== null }, 5000)
            const item = list.itemAtIndex(index)
            compareRole(item, "body", "sample picker sample row")
            compareRole(findChild(item, "vgSamplePickerRowText"),
                        "body", "sample picker sample text")
            compare(item.height, app.baseFontPx * 1.83,
                    "sample picker row height follows the session base")
            const before = draft.symbol
            mouseClick(item, item.width / 2, item.height / 2)
            compare(draft.symbol, before, "first click only auditions")
            mouseClick(item, item.width / 2, item.height / 2)
            tryCompare(popup, "opened", false)
            verify(waitForNative(function() { return draft.symbol === symbol }, 15000),
                   "second click commits " + symbol)
        }
        choose("DirectSoundWaveData_fixture_loop")
        choose("DirectSoundWaveData_fixture_bass")
        draft.changeType(7, "ProgrammableWaveData_fixture_pulse")
        verify(waitForNative(function() { return draft.macro === 7 }, 15000),
               "wave macro is selected")
        choose("ProgrammableWaveData_fixture_saw")
        draft.changeType(0, "DirectSoundWaveData_fixture_loop")
        verify(waitForNative(function() { return draft.macro === 0 }, 15000),
               "sample macro is selected")
        choose("fixture_bass")
        compare(draft.macro, 11, "keysplit symbol switches to keysplit macro")
    }

    function test_zySelectorFailurePreservesBinding() {
        const controller = app.voiceListController()
        const selector = findChild(panel, "vgArgCombo")
        selector.forceActiveFocus()
        selector.editText = "fixture_alt"
        selector.contentItem.forceActiveFocus()
        keyClick(Qt.Key_Return)
        verify(waitForNative(function() {
            return controller.bankLoadName === "fixture_alt" || app.lastSaveError.length > 0
        }, 15000), "selector switches to the staged alternate: " + app.lastSaveError)
        compare(app.lastSaveError, "")
        compare(selector.enabled, true,
                "mounted selector stays available after a successful activation")
        const retainedRow = findChild(panel, "voicegroupRow_0").title
        selector.editText = "_porydaw_missing_voicegroup"
        selector.contentItem.forceActiveFocus()
        keyClick(Qt.Key_Return)
        verify(waitForNative(function() {
            return app.lastSaveError.indexOf("_porydaw_missing_voicegroup") >= 0
        }, 15000), "a missing -G names itself in the failure")
        compare(selector.enabled, true,
                "mounted selector survives the failed -G activation")
        compare(controller.isLoading, false,
                "failed rebind settles the dock instead of leaving it loading")
        compare(controller.selectorEnabled, true,
                "failed rebind leaves the selector enabled")
        const release = findChild(panel, "vgReleaseSpin")
        verify(release !== null, "failed rebind retains the mounted release field")
        verify(release.enabled, "failed rebind keeps the release spin enabled")
        compare(controller.bankLoadName, "fixture_alt",
                "failed rebind retains the previous bank binding")
        compare(findChild(panel, "voicegroupRow_0").title, retainedRow,
                "failed rebind retains the selected slot row text")
        app.requestUndo()
        verify(waitForNative(function() {
            return controller.bankLoadName === "fixture_alt"
                   && controller.selectorText === "fixture_alt"
        }, 15000), "first undo of missing -G restores the retained alternate bank")
        app.requestUndo()
        verify(waitForNative(function() {
            return controller.bankLoadName === "fixture_rich"
                   && controller.selectorText === "fixture_rich"
        }, 15000), "undo after a failed rebind restores the home voicegroup")
        tryCompare(selector, "editText", "fixture_rich", 5000,
                   "selector undo displays the home voicegroup again")
    }
    function test_zzCatalogOutageRetainsLastValid() {
        const shell = createFullShell()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "mounted catalog outage fixture opens: " + session.lastSaveError)
        compare(session.lastSaveError, "")
        const voice = session.voiceListController()
        tryCompare(voice, "isBound", true, 5000)
        voice.selectSlot(0)
        const selector = findChild(shell, "vgArgCombo")
        const editor = findChild(shell, "voicegroupEditorSurface")
        const scroll = findChild(shell, "voiceEditorScrollView")
        verify(selector !== null && editor !== null && scroll !== null,
               "mounted catalog outage controls are present")
        tryVerify(function() { return !!findChild(editor, "vgReleaseSpin") }, 5000,
                  "mounted catalog outage release field loads")
        const release = findChild(editor, "vgReleaseSpin")
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        waitForRendering(release)
        verify(fileProbe.moveSoundAside(bootstrap.projectRoot),
               "mounted outage hides the staged sound directory")
        try {
            fileProbe.children.push(shell.shellPresenter)
            verify(fileProbe.requestShellCatalogRefresh(),
                   "mounted outage starts the shell catalog refresh")
            verify(waitForNative(function() {
                const status = findChild(shell, "shellStatusText")
                return status !== null && status.visible
                       && status.text.indexOf("sound directory is unavailable") >= 0
            }, 15000), "catalog outage reaches the mounted shell status bar")
            verify(selector.enabled,
                   "catalog outage leaves the mounted voicegroup selector enabled")
            verify(release.enabled,
                   "catalog outage leaves the mounted release spin enabled")
        } finally {
            try {
                fileProbe.children.length = 0
            } finally {
                verify(fileProbe.restoreSound(bootstrap.projectRoot),
                       "mounted outage restores the staged sound directory")
            }
        }
    }
}
