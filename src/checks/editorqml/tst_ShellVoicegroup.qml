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
    property var fullShell: null
    Component {
        id: fullShellComponent
        ShellWindow {
            width: testCase.width * 2.5
            height: testCase.height
            visible: true
        }
    }
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

    function test_trackHeaderRevealRoutesToMountedDock() {
        const controller = app.voiceListController()
        const headers = app.trackHeadersPresenter()
        headers.configureViewport(panel.width, panel.height, app.baseFontPx, 1)
        const rows = findChild(panel, "voicegroupRows")
        for (const slot of [0, 2, 4, 8, 12]) {
            rows.positionViewAtIndex(slot, ListView.Contain)
            const row = findChild(panel, "voicegroupRow_" + slot)
            verify(row && row.used === controller.slotIsMarkedUsed(slot),
                   "used marks match the assigned programs and clear on undo")
        }
        verify(headers.rowHeight > 0,
               "the song publishes header geometry: " + headers.rowHeight)
        controller.selectSlot(12)
        const before = controller.revealRequest
        const x = headers.voiceLineRect.x + headers.voiceLineRect.width / 2
        const y = headers.rowHeight / 2
        verify(headers.beginPointer(x, y, Qt.LeftButton, Qt.NoModifier),
               "the mounted song accepts a header press")
        verify(headers.endPointer(x, y, Qt.LeftButton, Qt.NoModifier),
               "the mounted song accepts a header release")
        verify(controller.currentSlot === 0 && controller.revealSlotId === 0
               && controller.revealRequest === before + 1,
               "revealing a track voice selects its program")
        const mounted = findChild(panel, "voicegroupRow_0")
        verify(mounted && mounted.used,
               "revealing a track voice selects its program")
    }

    function test_typeColumnFamiliesAndAlternateChips() {
        const controller = app.voiceListController()
        const header = findChild(panel, "voicegroupTypeHeader")
        const firstIcon = findChild(panel, "voicegroupTypeIcon_0")
        verify(firstIcon.width >= header.implicitWidth
               && firstIcon.width >= app.baseFontPx * 1.5
                   + 2 * app.layoutSpaces.two,
               "the type column fits its header and icon at base-font sizing")
        const types = ["Sample", "Sample", "Sample (fixed pitch)", "Sample (reverse)",
                       "Square 1", "Square 2", "Wave", "Noise", "Keysplit", "Keysplit",
                       "Drumkit", "Drumkit", "Sample"]
        const keys = [0, 0, 0, 2, 4, 6, 8, 10, 12, 12, 14, 14, 0]
        const rows = findChild(panel, "voicegroupRows")
        for (let slot = 0; slot < types.length; ++slot) {
            rows.positionViewAtIndex(slot, ListView.Contain)
            const row = findChild(panel, "voicegroupRow_" + slot)
            const icon = findChild(panel, "voicegroupTypeIcon_" + slot)
            verify(!!row && !!icon, "every populated family renders its glyph")
            compare(row.typeName, types[slot],
                    "the type column publishes family names through tooltip and accessible text")
            compare(icon.Accessible.name, types[slot],
                    "the type column publishes family names through tooltip and accessible text")
            compare(icon.ToolTip.text, types[slot],
                    "the type column publishes family names through tooltip and accessible text")
            compare(row.typeIconKey, keys[slot], "every populated family renders its glyph")
        }
        controller.selectSlot(13)
        rows.positionViewAtIndex(13, ListView.Contain)
        const blank = findChild(panel, "voicegroupRow_13")
        const blankIcon = findChild(panel, "voicegroupTypeIcon_13")
        verify(blank && blankIcon && blank.title.indexOf("[Blank]") >= 0
               && blank.typeName === "" && blank.typeIconKey === -1
               && blankIcon.Accessible.name === "",
               "blank rows publish no type, glyph or accessible name")
        const headers = app.trackHeadersPresenter()
        headers.configureViewport(panel.width, panel.height, app.baseFontPx, 1)
        const headerX = headers.voiceLineRect.x + headers.voiceLineRect.width / 2
        const headerY = headers.rowHeight / 2
        verify(headers.beginPointer(headerX, headerY, Qt.LeftButton, Qt.NoModifier),
               "the header press remains active while the voicegroup changes")
        const selector = findChild(panel, "vgArgCombo")
        selector.forceActiveFocus()
        selector.editText = "fixture_alt"
        selector.contentItem.forceActiveFocus()
        keyClick(Qt.Key_Return)
        verify(waitForNative(function() {
            return controller.bankLoadName === "fixture_alt"
                   || app.lastSaveError.length > 0
        }, 15000), "a typed alternate group commits while a header press lands: "
                   + app.lastSaveError + " edit=" + selector.editText
                   + " selector=" + controller.selectorText
                   + " load=" + controller.bankLoadName)
        compare(app.lastSaveError, "")
        headers.endPointer(headerX, headerY, Qt.LeftButton, Qt.NoModifier)
        verify(headers.beginPointer(headerX, headerY, Qt.LeftButton, Qt.NoModifier)
               && headers.endPointer(headerX, headerY, Qt.LeftButton, Qt.NoModifier)
               && controller.currentSlot === 0 && controller.revealSlotId === 0,
               "the next header press restores the primary track")
        const alt = ["Square 1 (Alt)", "Square 2 (Alt)", "Wave (Alt)", "Noise (Alt)"]
        for (let i = 0; i < alt.length; ++i) {
            const slot = i + 2
            rows.positionViewAtIndex(slot, ListView.Contain)
            const row = findChild(panel, "voicegroupRow_" + slot)
            const icon = findChild(panel, "voicegroupTypeIcon_" + slot)
            verify(row && icon && row.altChip && row.typeIconKey % 2 === 1
                   && row.typeName === alt[i] && icon.Accessible.name === alt[i],
                   "alternate groups publish alt family names on grey chips")
        }
        app.requestUndo()
        verify(waitForNative(function() {
            return controller.bankLoadName === "fixture_rich"
                   && controller.selectorText === "fixture_rich"
        }, 15000), "undo restores the home voicegroup binding")
        controller.selectSlot(12)
        verify(headers.beginPointer(headerX, headerY, Qt.LeftButton, Qt.NoModifier)
               && headers.endPointer(headerX, headerY, Qt.LeftButton, Qt.NoModifier)
               && controller.currentSlot === 0,
               "the next header press restores the primary track")
    }

    function test_blankTemplateAndDockWidth() {
        const controller = app.voiceListController()
        const baseline = panel.Layout.minimumWidth
        controller.selectSlot(13)
        const draft = controller.editorModel()
        const notice = findChild(panel, "voicegroupEditorNotice")
        const type = findChild(panel, "vgTypeCombo")
        const add = findChild(panel, "vgNewSampleButton")
        const edit = findChild(panel, "vgEditSampleButton")
        tryCompare(notice, "visible", false)
        verify(draft.editable && !notice.visible && draft.macro === 0
               && add.width === edit.width && add.height === edit.height,
               "a blank slot shows no notice, matching buttons and the DirectSound default: "
               + "editable=" + draft.editable + " notice=" + notice.visible
               + " macro=" + draft.macro + " sizes=" + add.width + "x" + add.height
               + "," + edit.width + "x" + edit.height)
        draft.changeType(3, "")
        verify(waitForNative(function() {
            return draft.macro === 3 && controller.bankDirty
        }, 15000), "the blank template materializes Square 1 undoably")
        compare(type.currentValue, 3)
        app.requestUndo()
        verify(waitForNative(function() {
            return draft.macro === 0 && !controller.bankDirty
        }, 15000), "the blank template materializes Square 1 undoably")
        app.requestRedo()
        verify(waitForNative(function() {
            return draft.macro === 3 && controller.bankDirty
        }, 15000), "the blank template materializes Square 1 undoably")
        app.requestUndo()
        verify(waitForNative(function() { return !controller.bankDirty }, 15000),
               "blank materialization undo settles the bank")
        for (const slot of [0, 4, 6, 7, 8, 13]) {
            controller.selectSlot(slot)
            compare(panel.Layout.minimumWidth, baseline,
                    "the dock's minimum width ignores the selected voice's family")
        }
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

    function cleanup() {
        if (!fullShell)
            return
        fullShell.close()
        if (fullShell.shellPresenter.session.songTabs.pendingCloseId >= 0)
            fullShell.shellPresenter.session.songTabs.confirmDiscard()
        fullShell.destroy()
        fullShell = null
        wait(0)
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
        cleanup()
    }

    function test_yPickerReturnFallbackAndWaveUndo() {
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const draft = controller.editorModel()
        const sampleOriginal = draft.symbol
        function openPicker() {
            const trigger = findChild(panel, "vgSamplePickerButton")
            mouseClick(trigger, trigger.width / 2, trigger.height / 2)
            const popup = findChild(panel, "vgSamplePickerPopup")
            tryCompare(popup, "opened", true)
            return popup
        }
        let popup = openPicker()
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
        draft.changeType(7, "ProgrammableWaveData_fixture_pulse")
        verify(waitForNative(function() { return draft.macro === 7 }, 15000),
               "wave mode lists the catalog's waves with full symbols")
        popup = openPicker()
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
            compareRole(findChild(popup, "vgSamplePickerLoop"), "body", "sample picker loop")
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
            if (symbol === "DirectSoundWaveData_fixture_loop")
                verify(findChild(popup, "vgSamplePickerLoop").visible
                       && controller.pickerSampleLoop,
                       "the sampled loop publishes a mounted loop badge")
            mouseClick(item, item.width / 2, item.height / 2)
            tryCompare(popup, "opened", false)
            verify(waitForNative(function() { return draft.symbol === symbol }, 15000),
                   "second click commits " + symbol)
            compare(controller.pickerSampleDetail, "", "popup close ends the audition")
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

    function test_zzSynthMintAndMountedSave() {
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const draft = controller.editorModel()
        compare(controller.canMintSynths, true)
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
