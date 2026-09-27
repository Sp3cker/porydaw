import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellVoicegroupSupport {
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

}
