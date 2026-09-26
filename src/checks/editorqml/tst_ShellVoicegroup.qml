import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellVoicegroup"
    when: windowShown
    width: 420
    height: 680
    visible: true

    ShellQmlBootstrap { id: bootstrap }
    ApplicationSession { id: app }
    Pane {
        anchors.fill: parent
        padding: 0
        font: Qt.font(app.typographyFonts.body)
        contentItem: VoicegroupPanel {
            id: panel
            applicationSession: app
            controller: app.voiceListController()
        }
    }
    function compareRole(item, role, name) {
        verify(!!item, name + " is mounted for " + role)
        const expected = app.typographyFonts[role]
        compare(item.font.family, expected.family, name + " uses " + role + " family")
        compare(item.font.pixelSize, expected.pixelSize, name + " uses " + role + " pixelSize")
        compare(item.font.weight, expected.weight, name + " uses " + role + " weight")
    }


    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function initTestCase() {
        compare(panel.baseFontPx, app.baseFontPx,
                "voicegroup pane derives its base before a song opens")
        compareRole(findChild(panel, "vgArgCombo"), "body", "voicegroup selector before song open")
        compare(findChild(panel, "voicegroupTreeHeader").height,
                Math.round(app.baseFontPx * 1.83),
                "voicegroup header follows the session base before song open")
        app.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() { return app.songOpen || app.lastSaveError.length > 0 }, 30000),
               "fixture song opens: " + app.lastSaveError)
        compare(app.lastSaveError, "")
        app.gridPresenter().configureViewport(420, 680, 12, 1)
        tryCompare(app.voiceListController(), "isBound", true)
        waitForRendering(panel)
    }

    function region(reference, name) {
        return reference.regions.find(function(entry) { return entry.name === name })
    }

    function directChildGeometry() {
        const editor = findChild(panel, "voicegroupEditorSurface")
        let parts = ["panel h=" + panel.height + " implicit=" + panel.implicitHeight
                     + " font=" + panel.baseFontPx + " slot=" + panel.controller.currentSlot
                     + " editor.macro=" + editor.draft.macro
                     + " fresh.macro=" + panel.controller.editorModel().macro
                     + " editor.preferred=" + editor.Layout.preferredHeight
                     + " editor.rows=" + editor.visibleRows]
        for (let i = 0; i < panel.children.length; i++) {
            const child = panel.children[i]
            parts.push(i + ":" + (child.objectName || "unnamed")
                       + " y=" + child.y + " h=" + child.height
                       + " implicit=" + child.implicitHeight
                       + " visible=" + child.visible)
        }
        for (let i = 0; i < editor.children.length; i++) {
            const child = editor.children[i]
            parts.push("editor." + i + ":" + (child.objectName || "unnamed")
                       + " y=" + child.y + " h=" + child.height
                       + " implicit=" + child.implicitHeight
                       + " visible=" + child.visible)
        }
        return parts.join("; ")
    }

    function checkRegion(reference, name, item, tolerance) {
        const expected = region(reference, name)
        verify(expected !== undefined, "widget reference has " + name)
        verify(item !== null, "mounted panel has " + name)
        const scale = panel.baseFontPx / reference.environment.fontPx
        const origin = item.mapToItem(panel, 0, 0)
        const expectedX = expected.x * scale
        const expectedWidth = panel.width - expectedX
                              - (reference.image.width - expected.x - expected.w) * scale
        const expectedY = name.startsWith("editor.")
                          ? panel.height - (reference.image.height - expected.y) * scale
                          : expected.y * scale
        const expectedHeight = name === "tree"
                               ? panel.height - expectedY
                                 - (reference.image.height - expected.y - expected.h) * scale
                               : expected.h * scale
        verify(Math.abs(origin.x - expectedX) <= tolerance
               && Math.abs(origin.y - expectedY) <= tolerance
               && Math.abs(item.width - expectedWidth) <= tolerance
               && Math.abs(item.height - expectedHeight) <= tolerance,
               name + " measured " + origin.x + "," + origin.y + " "
               + item.width + "x" + item.height + " vs rebased widget "
               + expectedX + "," + expectedY + " "
               + expectedWidth + "x" + expectedHeight
               + (name === "tree" ? "; " + directChildGeometry() : ""))
    }

    function capture(variant) {
        const reference = JSON.parse(bootstrap.voicegroupReferenceJson(variant))
        compare(reference.image.width, panel.width)
        compare(reference.image.height, panel.height)
        const editor = findChild(panel, "voicegroupEditorSurface")
        tryCompare(editor, "visibleRows", variant === "editor-square1" ? 4
                   : variant === "editor-readonly" ? 1 : 3, 1000,
                   "editor form recomputes for selected bank slot")
        waitForRendering(panel)
        checkRegion(reference, "selector", findChild(panel, "vgArgCombo"), 4)
        checkRegion(reference, "tree", findChild(panel, "voicegroupTree"), 5)
        checkRegion(reference, "tree.header", findChild(panel, "voicegroupTreeHeader"), 5)
        checkRegion(reference, "tree.row.000", findChild(panel, "voicegroupRow_0"), 5)
        if (variant === "editor-readonly") {
            checkRegion(reference, "editor.notice",
                        findChild(panel, "voicegroupEditorNotice"), 5)
        } else {
            checkRegion(reference, "editor.type", findChild(panel, "vgTypeCombo"), 5)
            if (variant === "editor-square1") {
                checkRegion(reference, "editor.sweep", findChild(panel, "vgSweepSpin"), 5)
            } else {
                checkRegion(reference, "editor.sample.button",
                            findChild(panel, "vgSamplePickerButton"), 5)
            }
        }
        let saved = false
        const destination = bootstrap.projectRoot + "/voicegroupbrowser-"
                            + (variant.length ? variant : "vanilla") + ".png"
        verify(panel.grabToImage(function(image) {
            saved = image.saveToFile(destination)
        }), "rendered the production VoicegroupPanel")
        tryVerify(function() { return saved }, 5000,
                  "saved " + variant + " voicegroup reference PNG at " + destination)
    }

    function test_128RowsSelectionAndAudition() {
        const controller = app.voiceListController()
        compare(findChild(panel, "voicegroupRows").count, 128)
        compare(controller.bankLoadName, "fixture_rich")
        const first = findChild(panel, "voicegroupRow_0")
        verify(first !== null, "bank row zero is mounted")
        tryVerify(function() { return first.title.indexOf("fixture_loop") >= 0 }, 5000,
                  "row zero publishes fixture_loop after the bank model update; got: " + first.title)
        compareRole(findChild(panel, "vgArgCombo"), "body", "voicegroup selector")
        compareRole(findChild(panel, "voicegroupEditorNotice"), "body", "voice editor notice")
        compareRole(findChild(panel, "voicegroupVoiceHeader"),
                    "body", "voicegroup Voice header")
        compareRole(findChild(panel, "voicegroupTypeHeader"),
                    "body", "voicegroup Type header")
        compareRole(findChild(panel, "voicegroupAdsrHeader"),
                    "body", "voicegroup ADSR header")
        compareRole(findChild(panel, "voicegroupTitle_0"), "body", "used voice title")
        compareRole(findChild(panel, "voicegroupAdsr_0"), "body", "used voice ADSR")
        compare(first.used, true, "fixture row is an assigned voice")
        compare(findChild(panel, "voicegroupTitle_0").font.bold, false,
                "used voice row stays regular while retaining its accent tint")
        compare(first.color, Qt.tint(app.palette.windowBackground, "#22b4e4ee"),
                "assigned voice retains its themed accent tint")
        compare(first.height, Math.round(app.baseFontPx * 1.33),
                "voicegroup row height follows the session base")
        const cry = findChild(panel, "voicegroupRow_12")
        verify(cry !== null, "read-only cry slot is mounted")
        tryVerify(function() { return cry.title.indexOf("fixture_loop") >= 0 }, 5000,
                  "read-only cry row publishes its loaded symbol; got: " + cry.title)
        tryCompare(cry, "typeName", "Sample", 5000,
                   "native VOICE_CRY masks to the Sample type label")
        mousePress(first, first.width / 2, first.height / 2)
        compare(controller.currentSlot, 0)
        compare(controller.soundingVoice, 0)
        mouseRelease(first, first.width / 2, first.height / 2)
        compare(controller.soundingVoice, -1)
        controller.revealSlot(12)
        compare(controller.currentSlot, 12)
    }

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
        const initial = draft.release
        draft.change("release", initial === 7 ? 6 : initial + 1)
        verify(waitForNative(function() { return controller.bankDirty && draft.release !== initial },
                             15000), "editor change makes bank dirty")
        const save = findChild(panel, "vgSaveButton")
        compareRole(save, "body", "voice editor save button")
        verify(save !== null && save.enabled, "mounted editor offers save for dirty bank")
        mouseClick(save, save.width / 2, save.height / 2)
        verify(waitForNative(function() { return !controller.bankDirty || app.lastSaveError.length > 0 },
                             15000), "mounted save completes: " + app.lastSaveError)
        compare(app.lastSaveError, "")
        compare(controller.bankDirty, false)
        compare(save.enabled, false)
        compare(draft.release, initial === 7 ? 6 : initial + 1)
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
            compareRole(findChild(popup, "vgSamplePickerLoop"), "body", "sample picker loop")
            compare(popup.width, Math.max(trigger.width, app.baseFontPx * 28.33),
                    "sample picker width follows the session base")
            compare(popup.height, app.baseFontPx * 35,
                    "sample picker height follows the session base")
            if (symbol === "DirectSoundWaveData_fixture_bass") {
                const headingIndex = list.model.findIndex(row => !row.symbol)
                verify(headingIndex >= 0, "sample picker preserves grouped section headings")
                list.positionViewAtIndex(headingIndex, ListView.Contain)
                tryVerify(function() { return !!list.itemAtIndex(headingIndex) }, 1000,
                          "sample picker section header is mounted")
                compareRole(list.itemAtIndex(headingIndex).contentItem,
                            "bodyBold", "sample picker section heading")
            }
            search.text = "unlisted_typography_sample"
            const typedIndex = list.model.findIndex(row => row.typed)
            verify(typedIndex >= 0, "sample picker offers the typed symbol fallback")
            list.positionViewAtIndex(typedIndex, ListView.Contain)
            tryVerify(function() { return !!list.itemAtIndex(typedIndex) }, 1000,
                      "sample picker typed fallback is mounted")
            compareRole(list.itemAtIndex(typedIndex).contentItem,
                        "body", "sample picker typed fallback")
            compare(list.itemAtIndex(typedIndex).contentItem.font.italic, true,
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
            compareRole(item.contentItem, "body", "sample picker sample text")
            compare(item.height, app.baseFontPx * 1.83,
                    "sample picker row height follows the session base")
            const before = draft.symbol
            mouseClick(item, item.width / 2, item.height / 2)
            compare(draft.symbol, before, "first click only auditions")
            verify(waitForNative(function() { return controller.pickerSampleDetail.length > 0 },
                                 15000), "resolved audition details for " + symbol)
            mouseClick(item, item.width / 2, item.height / 2)
            tryCompare(popup, "opened", false)
            verify(waitForNative(function() { return draft.symbol === symbol }, 15000),
                   "second click commits " + symbol)
            compare(controller.pickerSampleDetail, "", "popup close ends the audition")
        }
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

    function test_zzSynthMintAndMountedSave() {
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const draft = controller.editorModel()
        compare(controller.canMintSynths, true)
        draft.changeType(-1, draft.symbol)
        verify(waitForNative(function() { return draft.isSynth && controller.bankDirty },
                             15000), "synth type creates an unsaved bank edit")
        const waveform = findChild(panel, "vgSynthWaveformCombo")
        verify(waveform !== null && waveform.visible, "mounted synth waveform is visible")
        compare(draft.waveform, 0)
        draft.changeSynth("baseDuty", 77)
        verify(waitForNative(function() { return draft.baseDuty === 77 }, 15000),
               "duty LFO mints an edited pulse voice")
        const pulse = draft.symbol
        const baseDuty = findChild(panel, "vgSynthBaseDutySpin")
        verify(baseDuty !== null && baseDuty.visible, "pulse parameters occupy the editor")
        compare(baseDuty.value, 77)
        verify(controller.synthCatalogChoices().indexOf(pulse) < 0,
               "uncommitted synth does not masquerade as a saved definition")
        const save = findChild(panel, "vgSaveButton")
        mousePress(save, save.width / 2, save.height / 2)
        mouseRelease(save, save.width / 2, save.height / 2)
        verify(waitForNative(function() {
            return (!controller.bankDirty && controller.synthCatalogChoices().includes(pulse))
                   || app.lastSaveError.length > 0
        }, 15000), "save persists synth and refreshes catalog: " + app.lastSaveError)
        compare(app.lastSaveError, "")
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
        verify(release !== null && release.visible && release.enabled && scroll !== null,
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
