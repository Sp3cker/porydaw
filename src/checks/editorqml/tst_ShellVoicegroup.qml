import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

TestCase {
    id: testCase
    name: "ShellVoicegroup"
    when: windowShown
    width: 420
    height: 680
    visible: true

    ShellQmlBootstrap { id: bootstrap }
    ApplicationSession { id: app }
    VoicegroupPanel {
        id: panel
        anchors.fill: parent
        applicationSession: app
        controller: app.voiceListController()
    }

    function waitForNative(predicate, timeoutMs) {
        const deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function initTestCase() {
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
        const origin = item.mapToItem(panel, 0, 0)
        verify(Math.abs(origin.x - expected.x) <= tolerance
               && Math.abs(origin.y - expected.y) <= tolerance
               && Math.abs(item.width - expected.w) <= tolerance
               && Math.abs(item.height - expected.h) <= tolerance,
               name + " measured " + origin.x + "," + origin.y + " "
               + item.width + "x" + item.height + " vs widget "
               + expected.x + "," + expected.y + " " + expected.w + "x" + expected.h
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
            checkRegion(reference, "editor.adsr.attack",
                        findChild(panel, "vgAttackSpin"), 5)
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
        const initial = draft.release
        draft.change("release", initial === 7 ? 6 : initial + 1)
        verify(waitForNative(function() {
            return controller.bankDirty && draft.release !== initial
        }, 15000), "ADSR commit publishes dirty bank and refreshed editor")
        app.requestUndo()
        verify(waitForNative(function() { return draft.release === initial }, 15000),
               "undo restores original ADSR")
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
            search.text = symbol
            tryVerify(function() {
                return list.model.some(function(row) { return row.symbol === symbol })
            }, 5000, "search finds " + symbol)
            const index = list.model.findIndex(function(row) { return row.symbol === symbol })
            list.positionViewAtIndex(index, ListView.Contain)
            tryVerify(function() { return list.itemAtIndex(index) !== null }, 5000)
            const item = list.itemAtIndex(index)
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
}
