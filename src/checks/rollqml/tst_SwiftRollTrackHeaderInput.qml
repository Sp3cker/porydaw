import QtQuick
import QtTest

SwiftRollTrackHeadersSupport {
    function test_renameEditorBoundToTrackRow() {
        var h = surface().headersModel
        var rows = item("timelineTrackHeaderRows")
        var input = item("timelineTrackHeadersInput")
        var first = rows.itemAt(0)
        verify(first !== null && !first.isAddTrack)
        var x = first.titleRect.x + first.titleRect.width / 2
        var y = first.titleRect.y + first.titleRect.height / 2
        mouseDoubleClickSequence(input, x, y, Qt.LeftButton)
        tryCompare(h, "renamingTrack", first.track)
        var rename = item("timelineTrackHeaderRename")
        var editor = rename.parent
        verify(editor !== null)
        tryCompare(editor, "visible", true)
        verify(near(editor.x, h.renameEditorRect.x))
        verify(near(editor.y, first.index * h.rowHeight - h.scrollY + h.renameEditorRect.y))
        verify(near(editor.width, h.renameEditorRect.width))
        verify(near(editor.height, h.renameEditorRect.height))
    }

    function test_reorderMarkerStaysInsideInput() {
        var h = surface().headersModel
        var rows = item("timelineTrackHeaderRows")
        var input = item("timelineTrackHeadersInput")
        verify(rows.count >= 2 && !rows.itemAt(1).isAddTrack)
        var first = rows.itemAt(0)
        var x = first.titleRect.x + first.titleRect.width / 2
        var y = first.titleRect.y + first.titleRect.height / 2
        mousePress(input, x, y, Qt.LeftButton)
        mouseMove(input, x, Math.min(input.height - 2, y + h.rowHeight), 10, Qt.LeftButton)
        var marker = item("timelineTrackHeaderReorderMarker")
        tryCompare(marker, "visible", true)
        verify(marker.y >= 0)
        verify(marker.y + marker.height <= input.height + testCase.tolerance)
        bootstrap.cancelInput()
        mouseRelease(input, x, y, Qt.LeftButton)
    }

    function test_headerMenuRenameRowActivates() {
        var h = surface().headersModel
        var first = item("timelineTrackHeaderRows").itemAt(0)
        var input = item("timelineTrackHeadersInput")
        verify(first !== null && !first.isAddTrack)
        mouseClick(input, first.titleRect.x + first.titleRect.width / 2,
                   first.titleRect.y + first.titleRect.height / 2, Qt.RightButton)
        tryCompare(h, "menuOpen", true)
        var row = null
        tryVerify(function() {
            row = findChild(surface(), "headerMenuRow_3")
            return row !== null
        })
        verify(row.enabled)
        mouseClick(row, row.width / 2, row.height / 2, Qt.LeftButton)
        tryCompare(h, "renamingTrack", first.track, 5000,
                   "rename action opens an editor on the targeted track")
        tryCompare(item("timelineTrackHeaderRename"), "visible", true, 5000,
                   "rename action mounts the track-header editor")
    }

    function test_headerMenuFrameHasOutsideInputPoint() {
        var h = surface().headersModel
        var first = item("timelineTrackHeaderRows").itemAt(0)
        var input = item("timelineTrackHeadersInput")
        verify(first !== null && !first.isAddTrack)
        var x = first.titleRect.x + first.titleRect.width / 2
        var y = first.titleRect.y + first.titleRect.height / 2
        mouseClick(input, x, y, Qt.RightButton)
        tryCompare(h, "menuOpen", true)
        tryVerify(function() { return findChild(surface(), "quickMenuPanelRoot") !== null },
                  5000, "mounted header menu panel loads")
        var panel = item("quickMenuPanelRoot")
        compare(panel.rowObjectNamePrefix, "headerMenuRow_")
        var frame = findChild(panel, "quickMenuFrame")
        verify(frame !== null)
        tryVerify(function() { return frame.visible && frame.width > 0 && frame.height > 0 },
                  5000, "visible=" + frame.visible + " width=" + frame.width
                        + " height=" + frame.height + " count=" + panel.rowCount
                        + " menuOpen=" + h.menuOpen)
        var outside = null
        for (var row = 0; row < item("timelineTrackHeaderRows").count && !outside; ++row) {
            for (var fraction of [0.08, 0.5, 0.92]) {
                var px = input.width * fraction
                var py = row * h.rowHeight + h.rowHeight / 2 - h.scrollY
                if (px < 0 || px >= input.width || py < 0 || py >= input.height)
                    continue
                var scene = input.mapToItem(null, px, py)
                var corner = frame.mapToItem(null, 0, 0)
                if (scene.x < corner.x || scene.x >= corner.x + frame.width
                        || scene.y < corner.y || scene.y >= corner.y + frame.height) {
                    outside = { x: px, y: py }
                    break
                }
            }
        }
        verify(outside !== null)
        mouseClick(input, outside.x, outside.y, Qt.LeftButton)
        tryCompare(h, "menuOpen", false)
    }
    function test_clickingHeaderTitleChangesSelectedRaster() {
        var rows = item("timelineTrackHeaderRows")
        var input = item("timelineTrackHeadersInput")
        var row = rows.itemAt(1)
        verify(row !== null && !row.isAddTrack)
        var beforeBold = row.titleBold
        waitForRendering(row)
        var before = grabImage(testCase)
        var dpr = before.width / testCase.width
        var origin = row.mapToItem(testCase, 0, 0)
        var x0 = Math.round(origin.x * dpr)
        var x1 = Math.round((origin.x + row.width) * dpr)
        var y0 = Math.round(origin.y * dpr)
        var y1 = Math.round((origin.y + row.height) * dpr)
        mouseClick(input, row.titleRect.x + row.titleRect.width / 2,
                   row.y + row.titleRect.y + row.titleRect.height / 2)
        tryVerify(function() { return row.titleBold !== beforeBold })
        waitForRendering(row)
        var after = grabImage(testCase)
        var within = x0 >= 0 && y0 >= 0 && x1 > x0 && y1 > y0
                     && x1 <= before.width && x1 <= after.width
                     && y1 <= before.height && y1 <= after.height
        var changed = false
        if (within) {
            for (var y = y0; y < y1 && !changed; ++y)
                for (var x = x0; x < x1; ++x)
                    if (before.pixel(x, y) !== after.pixel(x, y)) {
                        changed = true
                        break
                    }
        }
        verify(within && changed, "clicking a title selects the row and alters the retained raster")
    }

    function test_hoveringHeaderTitleDoesNotCreateTooltip() {
        var rows = item("timelineTrackHeaderRows")
        var input = item("timelineTrackHeadersInput")
        var row = rows.itemAt(0)
        verify(row !== null && !row.isAddTrack, "the hover resolves a track row")
        var x = row.titleRect.x + row.titleRect.width / 2
        var y = row.y + row.titleRect.y + row.titleRect.height / 2
        verify(x >= 0 && x < input.width && y >= 0 && y < input.height,
               "the header hover point resolves inside the title")
        mouseMove(input, x, y)
        tryCompare(input, "containsMouse", true, 5000,
                   "the header band's input accepts the title hover")
        wait(500)
        verify(findChild(surface(), "timelineTrackHeaderToolTip") === null,
               "hovering a header title does not create a tooltip")
    }

    function test_yRenameEscapeAndTransientCancellation() {
        var h = surface().headersModel
        var input = item("timelineTrackHeadersInput")
        var row = item("timelineTrackHeaderRows").itemAt(0)
        var title = row.title
        var revision = bootstrap.timeSigUndoIndex()
        openHeaderMenu(0)
        chooseHeaderAction(3)
        var rename = item("timelineTrackHeaderRename")
        var editor = rename.parent
        tryVerify(function() {
            return !h.menuOpen && h.renamingTrack === row.track && editor.visible
                   && rename.activeFocus
        }, 5000, "the rename editor takes focus after the menu closes")
        keyClick(Qt.Key_Escape)
        tryCompare(editor, "visible", false, 5000,
                   "Escape discards the mounted rename editor")
        wait(0)
        verify(!editor.visible && row.title === title
               && bootstrap.timeSigUndoIndex() === revision,
               "the rename editor takes focus and Escape discards it")
        tryCompare(item("swiftRollInput"), "activeFocus", true, 5000,
                   "cancelling the mounted rename returns focus to the roll input")
        openHeaderMenu(0)
        chooseHeaderAction(3)
        tryCompare(rename, "activeFocus", true)
        input.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(editor, "visible", false)
        wait(0)
        verify(!editor.visible && row.title === title
               && bootstrap.timeSigUndoIndex() === revision,
               "a transient cancelled rename stays hidden without writing")
        verify(!item("swiftRollInput").activeFocus,
               "a focus-loss cancel leaves the roll input unfocused")
    }

    function test_yStructuralRemapDismissesMenuAndRestoresFocus() {
        var h = surface().headersModel
        var input = item("timelineTrackHeadersInput")
        var rows = item("timelineTrackHeaderRows")
        var original = rows.count
        openHeaderMenu(0)
        chooseHeaderAction(4)
        tryCompare(rows, "count", original + 1)
        var undoIndex = bootstrap.timeSigUndoIndex()
        openHeaderMenu(0)
        verify(bootstrap.undoTimeSignature(),
               "undo structurally remaps the open menu target")
        verify(waitForNative(function() { return rows.count === original }, 5000),
               "the remapped header rows settle before focus restoration")
        tryCompare(h, "menuOpen", false)
        tryCompare(input, "activeFocus", true)
        verify(findChild(surface(), "quickMenuPanelRoot") === null
               && bootstrap.timeSigUndoIndex() === undoIndex - 1,
               "a structural remap cancels the open menu and returns focus to the band")
    }

    function test_zMountedRenameAndReorderCommit() {
        var h = surface().headersModel
        var rows = item("timelineTrackHeaderRows")
        var input = item("timelineTrackHeadersInput")
        var first = rows.itemAt(0)
        var x = first.titleRect.x + first.titleRect.width / 2
        var y = first.titleRect.y + first.titleRect.height / 2
        mouseDoubleClickSequence(input, x, y)
        tryCompare(h, "renamingTrack", 0)
        tryVerify(function() {
            return findChild(surface(), "quickMenuPanelRoot") === null
        }, 5000, "previous header popup unloads before editing")
        var rename = item("timelineTrackHeaderRename")
        tryCompare(rename, "activeFocus", true, 5000,
                   "the mounted editor accepts keyboard focus")
        rename.selectAll()
        keyClick("R")
        compare(rename.text, "R", "the uppercase first key edits the mounted input")
        for (var letter of "enamed")
            keyClick(letter)
        compare(rename.text, "Renamed", "keyboard input updates the mounted editor")
        keyClick(Qt.Key_Return)
        tryCompare(rows.itemAt(0), "title", "1 · Renamed", 5000,
                   "rename commits from the mounted editor")
        compare(h.renamingTrack, -1,
                "mounted rename closes its editor after commit")
        tryCompare(item("swiftRollInput"), "activeFocus", true, 5000,
                   "committing the mounted rename returns focus to the roll input")
        mousePress(input, x, y, Qt.LeftButton)
        mouseMove(input, x, y + h.rowHeight, 10, Qt.LeftButton)
        tryCompare(item("timelineTrackHeaderReorderMarker"), "visible", true)
        compare(h.reorderIndicatorY, h.rowHeight * 2,
                "mounted drag targets the slot after the second track")
        mouseRelease(input, x, y + h.rowHeight, Qt.LeftButton)
        tryCompare(rows.itemAt(1), "title", "2 · Renamed", 5000,
                   "reorder commits from a mounted drag")
    }

}
