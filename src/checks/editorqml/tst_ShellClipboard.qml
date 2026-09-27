import QtQuick
import QtTest

ShellClipboardSupport {

    function test_nativeMimeDisplacedBySongFilterCopy() {
        openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        var source = editableNotes(grid).find(function(note) {
            var center = noteCenter(roll, surface, note.id)
            return center && center.x > 1 && center.y > 1
                && center.x < roll.width - 1 && center.y < roll.height - 1
        })
        verify(source !== undefined, "a mounted note accepts native Copy")
        grid.setTrack(source.track)
        var center = noteCenter(roll, surface, source.id)
        mouseClick(roll, center.x, center.y, Qt.LeftButton)
        verify(waitForNative(function() {
            return noteById(grid, source.id).selected
                && shell.shellPresenter.actionEnabled("roll.copy")
        }, 5000), "pointer selection enables production Copy")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Copy)
        verify(waitForNative(function() {
            return clipProbe.readClipJson().length > 0 && clipProbe.clipSummary() !== "[]"
        }, 5000), "mounted Copy leaves readable and decodable native clip MIME")

        var search = findChild(shell, "songListSearch")
        verify(search && search.visible, "the production song filter is mounted")
        mouseClick(search, search.width / 2, search.height / 2)
        tryCompare(search, "activeFocus", true, 3000)
        keyClick(Qt.Key_R)
        keyClick(Qt.Key_O)
        keyClick(Qt.Key_U)
        keyClick(Qt.Key_T)
        keyClick(Qt.Key_E)
        tryCompare(search, "text", "route")
        search.selectAll()
        keySequence(StandardKey.Copy)
        verify(waitForNative(function() {
            return clipProbe.readClipJson() === ""
        }, 5000), "foreign text Copy displaces the native clip MIME")
        compare(clipProbe.clipSummary(), "[]",
                "foreign text clipboard decodes to no song clip")
        keyClick(Qt.Key_Backspace)
        tryCompare(search, "text", "")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        compare(shell.shellPresenter.actionEnabled("roll.paste"), false,
                "song Paste is unavailable after foreign text Copy")
    }

    function test_noteDeleteAndCutKeys() {
        var session = openRoute101()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the real roll input is mounted")
        var visible = []
        var all = editableNotes(grid)
        for (var vi = 0; vi < all.length; ++vi) {
            var probe = findChild(surface, "gridNote_" + all[vi].id)
            if (!probe)
                continue
            var center = probe.mapToItem(roll, probe.width / 2, probe.height / 2)
            if (center.x > 1 && center.y > 1 && center.x < roll.width - 1 && center.y < roll.height - 1)
                visible.push(all[vi])
        }
        verify(visible.length >= 2, "the staged song shows two notes to delete")
        visible.sort(function(a, b) {
            return a.tick !== b.tick ? a.tick - b.tick : a.id - b.id
        })
        var first = null
        var second = null
        for (var pi = 0; pi + 1 < visible.length; ++pi) {
            if (visible[pi].track === visible[pi + 1].track) {
                first = visible[pi]
                second = visible[pi + 1]
                break
            }
        }
        verify(first !== null && second !== null, "two visible notes share one track")
        grid.setTrack(first.track)
        verify(waitForNative(function() {
            return grid.trackIndex === first.track
        }, 5000), "the source track is presented")
        var firstCenter = noteCenter(roll, surface, first.id)
        verify(firstCenter !== null, "the first note renders")
        mouseClick(roll, firstCenter.x, firstCenter.y, Qt.LeftButton)
        var secondCenter = noteCenter(roll, surface, second.id)
        verify(secondCenter !== null, "the second note renders")
        mouseClick(roll, secondCenter.x, secondCenter.y, Qt.LeftButton, Qt.ShiftModifier)
        verify(waitForNative(function() {
            return selectedCount(grid) === 2
        }, 5000), "real pointer input selects both notes")
        var beforeDelete = gridNotes(grid)
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        verify(shell.shellPresenter.actionEnabled("roll.delete"), "Delete is enabled")
        keyClick(Qt.Key_Delete)
        verify(waitForNative(function() {
            var current = gridNotes(grid)
            return current.length === beforeDelete.length - 2
                && noteById(grid, first.id) === null
                && noteById(grid, second.id) === null
        }, 5000), "real Delete removes both selected notes")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return gridNotes(grid).length === beforeDelete.length
                && noteById(grid, first.id) !== null
                && noteById(grid, second.id) !== null
        }, 5000), "Undo restores both deleted notes")
        firstCenter = noteCenter(roll, surface, first.id)
        verify(firstCenter !== null, "the restored first note renders")
        mouseClick(roll, firstCenter.x, firstCenter.y, Qt.LeftButton)
        secondCenter = noteCenter(roll, surface, second.id)
        verify(secondCenter !== null, "the restored second note renders")
        mouseClick(roll, secondCenter.x, secondCenter.y, Qt.LeftButton, Qt.ShiftModifier)
        verify(waitForNative(function() {
            return selectedCount(grid) === 2
        }, 5000), "real pointer input re-selects both notes")
        verify(shell.shellPresenter.actionEnabled("roll.cut"), "Cut is enabled")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.Cut)
        var cutText = ""
        verify(waitForNative(function() {
            var current = gridNotes(grid)
            if (current.length !== beforeDelete.length - 2)
                return false
            cutText = clipProbe.readClipJson()
            return cutText.length > 0
        }, 5000), "real Cut removes both notes and publishes clip bytes")
        var cut = JSON.parse(cutText)
        compare(cut.format, 1, "cut format")
        compare(cut.span, 0, "cut span is a note selection")
        compare(cut.tracks.length, 1, "cut tracks")
        compare(cut.tracks[0].track, first.track, "cut track")
        compare(cut.tracks[0].notes.length, 2, "cut notes")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return gridNotes(grid).length === beforeDelete.length
        }, 5000), "Undo restores both cut notes")
        var pasteBase = gridNotes(grid)
        var pasteEnd = 0
        for (var pe = 0; pe < pasteBase.length; ++pe)
            pasteEnd = Math.max(pasteEnd, pasteBase[pe].tick + pasteBase[pe].duration)
        var pasteCursor = (Math.floor((pasteEnd + grid.snapTicks - 1) / grid.snapTicks) + 2) * grid.snapTicks
        grid.setEditCursorTick(pasteCursor)
        compare(grid.editCursorTick, pasteCursor, "the paste cursor is staged clear")
        verify(waitForNative(function() {
            return shell.shellPresenter.actionEnabled("roll.paste")
        }, 5000), "Paste is enabled with the cut clip")
        keySequence(StandardKey.Paste)
        verify(waitForNative(function() {
            return gridNotes(grid).length === beforeDelete.length + 2
        }, 5000), "Paste reinserts the cut payload")
    }
}
