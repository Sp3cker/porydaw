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
    TabsDrawerProbe { id: fileProbe }
    ApplicationSession { id: app }
    property int saveStarts: 0
    property int saveFinishes: 0
    Connections {
        target: app
        function onSaveInProgressChanged() {
            if (app.saveInProgress)
                ++testCase.saveStarts
            else
                ++testCase.saveFinishes
        }
    }
    property var fullShell: null
    property int shellSaveStarts: 0
    property int shellSaveFinishes: 0
    Connections {
        target: fullShell ? fullShell.shellPresenter.session : null
        function onSaveInProgressChanged() {
            if (fullShell.shellPresenter.session.saveInProgress)
                ++testCase.shellSaveStarts
            else
                ++testCase.shellSaveFinishes
        }
    }
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
        controller.selectSlot(13)
        rows.positionViewAtIndex(13, ListView.Contain)
        const altBlank = findChild(panel, "voicegroupRow_13")
        verify(altBlank && !altBlank.used && altBlank.title.indexOf("[Blank]") >= 0,
               "the alternate fixture offers a selectable blank bank slot")
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

    function test_zzzzzUnifiedSaveAndUndoRestorationReceipts() {
        fullShell = fullShellComponent.createObject(null)
        const shell = fullShell
        shell.requestActivate()
        tryCompare(shell, "active", true)
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
        fullShell = fullShellComponent.createObject(null)
        const shell = fullShell
        shell.requestActivate()
        tryCompare(shell, "active", true)
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

    function test_zzSynthMintAndMountedSave() {
        const controller = app.voiceListController()
        controller.selectSlot(0)
        const draft = controller.editorModel()
        compare(controller.canMintSynths, true)
        draft.changeType(0, "DirectSoundWaveData_fixture_loop")
        verify(waitForNative(function() {
            return draft.macro === 0 && !draft.isSynth && controller.currentSlot === 0
        }, 15000), "slot zero is a non-synth DirectSound voice before Synth selection")
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
