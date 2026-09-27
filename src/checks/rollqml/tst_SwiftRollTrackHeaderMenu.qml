import QtQuick
import QtTest

SwiftRollTrackHeadersSupport {
    function test_zMountedMenuDispatchAndDismissal() {
        var h = surface().headersModel
        var rows = item("timelineTrackHeaderRows")
        var panel = openHeaderMenu(0)
        compare(panel.rowCount, 5, "the header menu lists the fork's five actions")
        var labels = ["Change voice...", "Show voice in voicegroup", "Rename track...",
                      "Duplicate track", "Delete track"]
        for (var n = 1; n <= 5; ++n) {
            var row = menuRow(n)
            compare(row.itemData.text, labels[n - 1],
                    "the header menu lists fork action " + n)
            compare(row.itemData.actionId, n,
                    "the header menu dispatch id matches fork action " + n)
        }
        verify(menuRow(4).enabled, "duplicate below capacity stays enabled")
        var before = rows.count
        var originalTitles = [rows.itemAt(0).title, rows.itemAt(1).title]
        var initialUndo = bootstrap.timeSigUndoIndex()
        chooseHeaderAction(4)
        tryCompare(rows, "count", before + 1, 5000,
                   "duplicate adds a track from the mounted menu")
        compare(h.menuOpen, false, "duplicate dispatch closes the mounted menu")
        tryCompare(item("timelineTrackHeadersInput"), "activeFocus", true, 5000,
                   "duplicate dispatch restores header keyboard focus")
        compare(bootstrap.timeSigUndoIndex(), initialUndo + 1,
                "duplicate runs one document command")
        openHeaderMenu(0)
        chooseHeaderAction(5)
        tryCompare(rows, "count", before, 5000,
                   "delete removes a track from the mounted menu")
        compare(h.menuOpen, false, "delete dispatch closes the mounted menu")
        tryCompare(item("timelineTrackHeadersInput"), "activeFocus", true, 5000,
                   "delete dispatch restores header keyboard focus")
        compare(bootstrap.timeSigUndoIndex(), initialUndo + 2,
                "delete runs one document command")
        verify(bootstrap.undoTimeSignature(), "the delete command is undoable")
        verify(waitForNative(function() { return rows.count === before + 1 }, 5000),
               "undo restores the deleted row")
        compare(rows.itemAt(0).title, originalTitles[0],
                "undo restores the deleted track's title")
        verify(bootstrap.undoTimeSignature(), "the duplicate command is undoable")
        verify(waitForNative(function() { return rows.count === before }, 5000),
               "undo removes the duplicated row")
        compare(rows.itemAt(0).title, originalTitles[0],
                "undo restores the source track")
        compare(rows.itemAt(1).title, originalTitles[1],
                "undo restores the neighboring track")
        compare(bootstrap.timeSigUndoIndex(), initialUndo,
                "duplicate and delete each contribute exactly one undoable command")
        var readOnlyUndo = bootstrap.timeSigUndoIndex()
        voiceRequestSpy.clear()
        openHeaderMenu(0)
        chooseHeaderAction(1)
        tryCompare(h, "menuOpen", false, 5000,
                   "change voice closes the mounted menu")
        tryCompare(voiceRequestSpy, "count", 1, 5000,
                   "change voice requests the selected track's picker")
        compare(voiceRequestSpy.signalArguments[0][0], 0,
                "the voice picker request targets the mounted header track")
        var pickerLoader = item("headerVoicePickerLoader")
        tryCompare(pickerLoader, "active", true, 5000,
                   "Change voice closes the menu before the picker opens")
        tryVerify(function() {
            return pickerLoader.item !== null
                && findChild(pickerLoader.item, "voicePickerTitle") !== null
        })
        compare(findChild(pickerLoader.item, "voicePickerTitle").text, "Track 1 voice",
                "the mounted header picker names the targeted track")
        tryCompare(findChild(pickerLoader.item, "voicePickerSearch"), "activeFocus", true,
                   5000, "menu Change voice opens the picker with search focused")
        keyClick("1")
        keyClick("2")
        keyClick("7")
        tryCompare(findChild(pickerLoader.item, "voicePickerList"), "count", 1, 5000,
                   "menu Change voice filters the mounted picker to its matching program")
        var menuVoiceRow = findChild(pickerLoader.item, "voicePickerRow_127")
        verify(menuVoiceRow !== null && menuVoiceRow.visible,
               "menu Change voice exposes the visible filtered program row")
        compare(bootstrap.timeSigUndoIndex(), readOnlyUndo,
                "change voice requests the picker without a document write")
        mouseClick(findChild(pickerLoader.item, "voicePickerUnderlay"), 1, 1)
        tryCompare(pickerLoader, "active", false, 5000,
                   "outside press dismisses the mounted menu's voice picker")
        tryCompare(item("timelineTrackHeadersInput"), "activeFocus", true, 5000,
                   "outside picker dismissal restores header focus")
        compare(bootstrap.timeSigUndoIndex(), readOnlyUndo,
                "outside picker dismissal never writes a voice")
        var beforeTitles = [rows.itemAt(0).title, rows.itemAt(1).title]
        openHeaderMenu(0)
        chooseHeaderAction(2)
        tryCompare(h, "menuOpen", false, 5000,
                   "show voice in voicegroup closes the menu")
        compare(rows.count, before, "show voice in voicegroup writes no track")
        compare(rows.itemAt(0).title, beforeTitles[0],
                "show voice in voicegroup preserves the requested track title")
        compare(rows.itemAt(1).title, beforeTitles[1],
                "show voice in voicegroup preserves the neighbor title")
        tryCompare(item("timelineTrackHeadersInput"), "activeFocus", true, 5000,
                   "show voice returns focus to the header band")
        compare(bootstrap.timeSigUndoIndex(), readOnlyUndo,
                "show voice reveals without a document write")
        verify(rows.count === before && !h.menuOpen
               && item("timelineTrackHeadersInput").activeFocus
               && bootstrap.timeSigUndoIndex() === readOnlyUndo,
               "the header menu dispatches all five actions and restores band focus")
        openHeaderMenu(0)
        keyClick(Qt.Key_Escape)
        tryCompare(h, "menuOpen", false, 5000,
                   "escape dismisses the open header menu")
        tryCompare(item("timelineTrackHeadersInput"), "activeFocus", true, 5000,
                   "escape dismissal restores header keyboard focus")
        openHeaderMenu(0)
        var input = item("timelineTrackHeadersInput")
        var frame = item("quickMenuFrame")
        var outside = null
        for (var i = 0; i < rows.count && !outside; ++i)
            for (var fraction of [0.08, 0.5, 0.92]) {
                var px = input.width * fraction
                var py = i * h.rowHeight + h.rowHeight / 2
                var point = input.mapToItem(null, px, py)
                var corner = frame.mapToItem(null, 0, 0)
                if (point.x < corner.x || point.x >= corner.x + frame.width
                    || point.y < corner.y || point.y >= corner.y + frame.height) {
                    outside = { x: px, y: py }
                    break
                }
            }
        verify(outside !== null)
        mousePress(input, outside.x, outside.y)
        tryCompare(h, "menuOpen", false, 5000,
                   "an outside press dismisses the open header menu")
        mouseRelease(input, outside.x, outside.y)
        compare(h.menuOpen, false,
                "an outside release does not reopen the header menu")
        compare(rows.count, before, "an outside press writes nothing")
        tryCompare(input, "activeFocus", true, 5000,
                   "the band keeps keyboard focus across outside dismissal")
    }

    function test_zMountedHeaderVoicePickerJourneys() {
        var s = surface()
        var h = s.headersModel
        var rows = item("timelineTrackHeaderRows")
        var input = item("timelineTrackHeadersInput")
        var model = session.headerVoicePickerModel()
        var baselineCount = rows.count
        var initialUndo = bootstrap.timeSigUndoIndex()
        verify(bootstrap.seedDuplicateInitialVoice(0, 31, 37),
               "the document fixture seeds two real first-tick voice changes")
        compare(bootstrap.timeSigUndoIndex(), initialUndo + 1,
                "the duplicate-tick fixture is one undoable document write")
        voiceRequestSpy.clear()
        var lastPickerClosed = false
        function openVoice() {
            if (lastPickerClosed) {
                wait(Qt.styleHints.mouseDoubleClickInterval + 1)
                lastPickerClosed = false
            }
            var first = rows.itemAt(0)
            var beforeRequests = voiceRequestSpy.count
            mouseDoubleClickSequence(input,
                first.subtitleRect.x + first.subtitleRect.width / 2,
                first.subtitleRect.y + first.subtitleRect.height / 2)
            tryCompare(voiceRequestSpy, "count", beforeRequests + 1, 5000,
                       "the voice-cell gesture requests one production picker")
            compare(model.pickerOpen, true,
                    "the requested voice picker remains open through gesture release")
            tryCompare(session, "headerVoicePickerOpen", true, 5000,
                       "double-clicking a voice cell opens the Track N voice picker")
            var loader = item("headerVoicePickerLoader")
            tryVerify(function() { return loader.item !== null })
            tryCompare(findChild(loader.item, "voicePickerSearch"), "activeFocus", true, 5000,
                       "the mounted picker receives keyboard input before a key gesture")
            return loader.item
        }
        function closePicker() {
            tryCompare(session, "headerVoicePickerOpen", false, 5000)
            tryCompare(item("headerVoicePickerLoader"), "item", null, 5000,
                       "closing the picker unmounts its modal input")
            tryCompare(input, "activeFocus", true, 5000,
                       "closing the picker returns focus to the header band")
            lastPickerClosed = true
        }
        var picker = openVoice()
        compare(findChild(picker, "voicePickerTitle").text, "Track 1 voice",
                "double-clicking a voice cell opens the Track N voice picker")
        compare(model.pickerIndex, 37,
                "the last duplicate on the first tick initializes the picker")
        tryCompare(findChild(picker, "voicePickerSearch"), "activeFocus", true, 5000,
                   "the header picker opens with search focused")
        var search = findChild(picker, "voicePickerSearch")
        keyClick("1")
        keyClick("2")
        keyClick("7")
        tryCompare(model, "pickerFilter", "127", 5000,
                   "typing in the picker filters to matching voices")
        tryCompare(findChild(picker, "voicePickerList"), "count", 1, 5000,
                   "typing in the picker filters to matching voices")
        compare(model.pickerIndex, 0,
                "the visible match resolves to the requested program")
        verify(bootstrap.observeHeaderVoiceAudition(),
               "the production picker audition callback is observable")
        var row = findChild(picker, "voicePickerRow_127")
        verify(row !== null, "the filtered voice row is mounted")
        mousePress(row, row.width / 2, row.height / 2)
        compare(bootstrap.headerVoiceAuditionEvents(), "127:60:112",
                "auditioning a row previews program/key/velocity and releases to silence")
        mouseRelease(row, row.width / 2, row.height / 2)
        compare(bootstrap.headerVoiceAuditionEvents(), "127:60:112,127:60:0",
                "auditioning a row previews program/key/velocity and releases to silence")
        bootstrap.stopObservingHeaderVoiceAudition()
        search.text = "zzzz-unmatched-voice"
        tryCompare(findChild(picker, "voicePickerList"), "count", 0, 5000,
                   "unmatched filtering removes all voices")
        tryCompare(findChild(picker, "voicePickerAccept"), "enabled", false, 5000,
                   "accept stays disabled with no selection")
        keyClick(Qt.Key_Return)
        compare(session.headerVoicePickerOpen, true,
                "Return with no matching voice cannot accept the picker")
        keyClick(Qt.Key_Escape)
        closePicker()
        compare(bootstrap.timeSigUndoIndex(), initialUndo + 1,
                "dismissing the picker writes nothing and reopens cleanly")

        picker = openVoice()
        compare(model.pickerIndex, 37,
                "dismissing the picker writes nothing and reopens cleanly")
        mouseClick(findChild(picker, "voicePickerAccept"))
        closePicker()
        compare(bootstrap.timeSigUndoIndex(), initialUndo + 1,
                "accepting the unchanged voice writes nothing")

        picker = openVoice()
        search = findChild(picker, "voicePickerSearch")
        search.text = "127"
        tryCompare(model, "pickerIndex", 0, 5000)
        var beforeChangeRevision = bootstrap.timeSigRevision()
        mouseClick(findChild(picker, "voicePickerAccept"))
        closePicker()
        compare(bootstrap.timeSigUndoIndex(), initialUndo + 2,
                "accepting writes the voice, rebuilds sorted/unique, undo restores and redo re-applies")
        compare(bootstrap.timeSigRevision(), beforeChangeRevision + 1,
                "accepting the voice writes exactly one document revision")
        picker = openVoice()
        compare(model.pickerIndex, 127,
                "accepted voice reopens as the last first-tick program")
        keyClick(Qt.Key_Escape)
        closePicker()
        verify(bootstrap.undoTimeSignature(), "the voice change is undoable")
        picker = openVoice()
        compare(model.pickerIndex, 37,
                "undo restores the former initial voice")
        keyClick(Qt.Key_Escape)
        closePicker()
        verify(bootstrap.redoTimeSignature(), "the voice change is redoable")
        picker = openVoice()
        compare(model.pickerIndex, 127,
                "redo reapplies the accepted initial voice")
        keyClick(Qt.Key_Escape)
        closePicker()

        picker = openVoice()
        search = findChild(picker, "voicePickerSearch")
        keyClick("1")
        keyClick("2")
        keyClick("7")
        tryCompare(model, "pickerIndex", 0, 5000)
        verify(bootstrap.observeHeaderVoiceAudition(),
               "the remap audition observer wraps the production audio callback")
        row = findChild(picker, "voicePickerRow_127")
        verify(row !== null && row.visible, "the filtered remap voice row is visible")
        mousePress(row, row.width / 2, row.height / 2)
        compare(bootstrap.headerVoiceAuditionEvents(), "127:60:112",
                "holding the remapped picker previews the selected voice")
        var beforeRemap = bootstrap.timeSigRevision()
        verify(bootstrap.moveHeaderTrack(0, 1),
               "a real track move structurally remaps the open picker target")
        closePicker()
        compare(bootstrap.headerVoiceAuditionEvents(), "127:60:112,127:60:0",
                "remapping while held releases audition exactly once to silence")
        bootstrap.stopObservingHeaderVoiceAudition()
        var afterRemap = bootstrap.timeSigRevision()
        compare(afterRemap, beforeRemap + 1,
                "a structural remap while the picker is open writes one revision")
        session.completeTrackHeaderVoiceRequest(126)
        compare(bootstrap.timeSigRevision(), afterRemap,
                "stale picker completion cannot write into the remapped slot")
        verify(bootstrap.undoTimeSignature(), "undo restores track order after remap")
        compare(bootstrap.timeSigUndoIndex(), initialUndo + 2,
                "the remap command leaves the earlier voice change intact")
        tryCompare(input, "activeFocus", true, 5000,
                   "the header band has focus before the add-track gesture")

        var add = rows.itemAt(rows.count - 1)
        verify(add.isAddTrack, "the last row is the production add-track control")
        mouseClick(input, h.trackHeaderWidth / 2,
                   (rows.count - 1) * h.rowHeight + h.rowHeight / 2)
        tryCompare(session, "headerVoicePickerOpen", true, 5000,
                   "the add row opens the New track voice picker")
        tryCompare(item("headerVoicePickerLoader"), "active", true, 5000)
        tryVerify(function() { return item("headerVoicePickerLoader").item !== null },
                  5000, "the add picker mounts before inspecting its contents")
        picker = item("headerVoicePickerLoader").item
        compare(findChild(picker, "voicePickerTitle").text, "New track voice",
                "the add row opens the New track voice picker")
        compare(model.pickerIndex, 0,
                "the add picker initially selects program zero")
        tryCompare(findChild(picker, "voicePickerSearch"), "activeFocus", true, 5000,
                   "the add picker focuses its search field")
        var beforeAddRevision = bootstrap.timeSigRevision()
        var beforeAddUndo = bootstrap.timeSigUndoIndex()
        search = findChild(picker, "voicePickerSearch")
        keyClick("1")
        keyClick("2")
        keyClick("7")
        tryCompare(findChild(picker, "voicePickerList"), "count", 1, 5000,
                   "filtering the add picker reveals the selected voice")
        verify(bootstrap.observeHeaderVoiceAudition(),
               "the add picker auditions through the production audio callback")
        row = findChild(picker, "voicePickerRow_127")
        verify(row !== null && row.visible, "the filtered add-picker voice is visible")
        mousePress(row, row.width / 2, row.height / 2)
        compare(bootstrap.headerVoiceAuditionEvents(), "127:60:112",
                "holding the add-picker voice previews the selected instrument")
        mouseClick(findChild(picker, "voicePickerUnderlay"), 1, 1)
        closePicker()
        compare(bootstrap.headerVoiceAuditionEvents(), "127:60:112,127:60:0",
                "outside dismissal releases the add-picker audition exactly once")
        bootstrap.stopObservingHeaderVoiceAudition()
        compare(bootstrap.timeSigUndoIndex(), beforeAddUndo,
                "outside dismissal cancels add without a document write")
        mouseClick(input, h.trackHeaderWidth / 2,
                   (rows.count - 1) * h.rowHeight + h.rowHeight / 2)
        tryCompare(session, "headerVoicePickerOpen", true, 5000,
                   "the add picker reopens after cancellation")
        tryVerify(function() { return item("headerVoicePickerLoader").item !== null },
                  5000, "the reopened add picker mounts before accepting input")
        picker = item("headerVoicePickerLoader").item
        search = findChild(picker, "voicePickerSearch")
        tryCompare(search, "activeFocus", true, 5000,
                   "reopened add picker focuses its search")
        search.text = "zz-no-such-voice"
        tryCompare(findChild(picker, "voicePickerAccept"), "enabled", false, 5000,
                   "unmatched add search disables acceptance")
        keyClick(Qt.Key_Return)
        compare(session.headerVoicePickerOpen, true,
                "Return cannot accept an add picker without a voice")
        search.text = "127"
        tryCompare(findChild(picker, "voicePickerList"), "count", 1, 5000,
                   "matching add search exposes the selected program")
        verify(bootstrap.observeHeaderVoiceAudition(),
               "reopened add picker keeps the production audition callback")
        row = findChild(picker, "voicePickerRow_127")
        verify(row !== null && row.visible, "the reopened add picker exposes the visible program row")
        mousePress(row, row.width / 2, row.height / 2)
        compare(bootstrap.headerVoiceAuditionEvents(), "127:60:112",
                "reopened add picker auditions program 127 at middle C")
        mouseRelease(row, row.width / 2, row.height / 2)
        compare(bootstrap.headerVoiceAuditionEvents(), "127:60:112,127:60:0",
                "reopened add picker releases program 127 to silence")
        bootstrap.stopObservingHeaderVoiceAudition()
        tryCompare(model, "pickerHasMatch", true, 5000,
                   "the selected add voice becomes acceptable")
        keyClick(Qt.Key_Return)
        closePicker()
        tryCompare(rows, "count", baselineCount + 1, 5000,
                   "accepting the add picker creates one track")
        compare(s.gridModel.trackIndex, baselineCount - 1,
                "accepting the add picker selects the new track")
        compare(bootstrap.timeSigRevision(), beforeAddRevision + 1,
                "accepting the add picker writes exactly one revision")
        compare(bootstrap.timeSigUndoIndex(), beforeAddUndo + 1,
                "accepting the add picker writes exactly one undo entry")
        verify(bootstrap.undoTimeSignature(), "undo removes the added track")
        tryCompare(rows, "count", baselineCount, 5000)
        verify(bootstrap.undoTimeSignature(), "undo restores the pre-fixture voice lane")
        verify(bootstrap.undoTimeSignature(), "undo removes the duplicate-tick fixture")
        compare(bootstrap.timeSigUndoIndex(), initialUndo,
                "the picker journey leaves the shared document at its original undo index")
    }

}
