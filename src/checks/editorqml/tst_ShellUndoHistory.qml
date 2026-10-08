import QtQuick
import QtTest
import Porydaw.Ui

ShellMenusSupport {
    id: testCase
    name: "ShellUndoHistory"

    function child(name) {
        const item = findChild(shell, name)
        verify(!!item, "Object exists")
        return item
    }

    function historyRow(index) {
        const item = child("undoHistoryList").itemAtIndex(index)
        verify(!!item, "Object exists")
        return item
    }

    function label(index) {
        const item = findChild(historyRow(index), "undoHistoryLabel")
        verify(!!item, "Object exists")
        return item
    }

    function documentNotes(grid) {
        const notes = JSON.parse(grid.fetchNoteSummary())
        for (const note of notes)
            delete note.selected
        return JSON.stringify(notes)
    }

    function waitForCount(count) {
        const list = child("undoHistoryList")
        const ready = waitForNative(function() {
            return list.count === count && shell.shellPresenter.session.undoHistory.canJump
                && list.itemAtIndex(count - 1) !== null
        }, 5000)
        verify(ready, "history count=" + list.count + ", expected=" + count
               + ", canJump=" + shell.shellPresenter.session.undoHistory.canJump
               + ", row=" + list.itemAtIndex(count - 1))
    }

    function openHistory() {
        openShell()
        openSong()
        const presenter = shell.shellPresenter
        presenter.activate("view.undo_history")
        tryCompare(presenter, "undoHistoryVisible", true)
        tryCompare(child("shellUndoHistoryDock"), "visible", true)
        waitForCount(1)
        return presenter
    }

    function editThreeSteps(presenter) {
        const grid = presenter.session.gridPresenter()
        const history = presenter.session.undoHistory
        const original = documentNotes(grid)
        presenter.activate("roll.select_all")
        presenter.activate("roll.transpose_up")
        waitForCount(2)
        const firstLabel = label(0).text
        const afterFirst = documentNotes(grid)
        verify(afterFirst !== original)
        presenter.activate("roll.delete")
        waitForCount(3)
        const secondLabel = label(0).text
        const afterSecond = documentNotes(grid)
        verify(afterSecond !== afterFirst)
        grid.setEditCursorTick(Math.max(grid.snapTicks, grid.editCursorTick + grid.snapTicks))
        presenter.activate("edit.set_loop_start")
        waitForCount(4)
        tryCompare(history, "currentRow", 0)
        return { original: original, afterFirst: afterFirst, afterSecond: afterSecond,
                 labels: [qsTr("Set loop"), secondLabel, firstLabel, qsTr("Opened")] }
    }

    function waitForPosition(presenter, row) {
        verify(waitForNative(function() {
            return presenter.session.undoHistory.currentRow === row
                && presenter.session.undoHistory.canJump
        }, 5000))
    }

    function test_viewActionCloseAndDockCoexistence() {
        openShell()
        const presenter = shell.shellPresenter
        const dock = child("shellUndoHistoryDock")
        compare(presenter.undoHistoryVisible, false)
        compare(dock.visible, false)
        compare(presenter.action("view.undo_history").enabled, false)
        openSong()
        compare(presenter.action("view.undo_history").label, qsTr("Undo History"))
        compare(presenter.actionSequences("view.undo_history").length, 0)
        presenter.activate("view.undo_history")
        tryCompare(dock, "visible", true)
        tryCompare(presenter.action("view.undo_history"), "checked", true)
        presenter.activate("view.polyphony_debugger")
        const polyDock = child("shellPolyphonyDock")
        tryCompare(polyDock, "visible", true)
        verify(waitForPolish(dock))
        verify(polyDock.mapToItem(dock, polyDock.width, 0).x <= 0)
        const close = child("shellUndoHistoryClose")
        mouseClick(close, close.width / 2, close.height / 2)
        tryCompare(dock, "visible", false)
        tryCompare(presenter.action("view.undo_history"), "checked", false)
        presenter.activate("view.undo_history")
        tryCompare(dock, "visible", true)
        const list = child("undoHistoryList")
        list.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(list, "activeFocus", true)
        keyClick(Qt.Key_Escape)
        tryCompare(presenter, "undoHistoryVisible", false)
        tryCompare(dock, "visible", false)
        compare(polyDock.visible, true)
    }

    function test_newestFirstBaseJumpRedoAndDimming() {
        const presenter = openHistory()
        const fixture = editThreeSteps(presenter)
        const session = presenter.session
        const grid = session.gridPresenter()
        const pane = child("undoHistoryDock")
        const list = child("undoHistoryList")
        for (let index = 0; index < fixture.labels.length; ++index) {
            const row = historyRow(index)
            compare(label(index).text, fixture.labels[index])
            compare(label(index).text, row.step.label)
            compare(row.step.isBase, index === 3)
            compare(row.step.applied, true)
            compare(label(index).color, session.palette.windowText)
        }
        compare(pane.em, shell.chromeBaseFontPx)
        compare(label(0).font.pixelSize, shell.chromeTypography.body.pixelSize)
        compare(historyRow(0).step.isCurrent, true)
        compare(historyRow(3).step.isSaved, true)
        const base = historyRow(3)
        mouseClick(base, base.width / 2, base.height / 2)
        waitForPosition(presenter, 3)
        tryCompare(session, "canUndo", false)
        tryCompare(session, "canRedo", true)
        tryCompare(session, "songDocumentDirty", false)
        compare(documentNotes(grid), fixture.original)
        tryCompare(pane, "highlightedRow", 3)
        compare(base.step.isCurrent, true)
        const position = findChild(base, "undoHistoryPositionMarker")
        const saved = findChild(base, "undoHistorySavedMarker")
        verify(!!position, "Object exists")
        verify(!!saved, "Object exists")
        verify(position.text.length > 0 && saved.text.length > 0)
        for (let index = 0; index < 3; ++index) {
            tryCompare(label(index), "color", session.palette.secondaryText)
            compare(label(index).enabled, true)
            compare(historyRow(index).enabled, true)
            compare(historyRow(index).step.applied, false)
        }
        list.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(list, "activeFocus", true)
        keyClick(Qt.Key_Up)
        keyClick(Qt.Key_Up)
        tryCompare(pane, "highlightedRow", 1)
        compare(session.undoHistory.currentRow, 3)
        keyClick(Qt.Key_Return)
        waitForPosition(presenter, 1)
        compare(documentNotes(grid), fixture.afterSecond)
        compare(historyRow(0).step.applied, false)
        compare(historyRow(1).step.applied, true)
        tryCompare(label(1), "color", session.palette.windowText)
        keyClick(Qt.Key_Down)
        tryCompare(pane, "highlightedRow", 2)
        keyClick(Qt.Key_Enter)
        waitForPosition(presenter, 2)
        compare(documentNotes(grid), fixture.afterFirst)
    }

    function test_windowUndoAndSpaceKeepDockFocus() {
        const presenter = openHistory()
        const fixture = editThreeSteps(presenter)
        const list = child("undoHistoryList")
        const pane = child("undoHistoryDock")
        const session = presenter.session
        list.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(list, "activeFocus", true)
        keySequence(StandardKey.Undo)
        waitForPosition(presenter, 1)
        tryCompare(pane, "highlightedRow", 1)
        keySequence(StandardKey.Undo)
        waitForPosition(presenter, 2)
        compare(documentNotes(session.gridPresenter()), fixture.afterFirst)
        tryCompare(pane, "highlightedRow", 2)
        keyClick(Qt.Key_Up)
        tryCompare(pane, "highlightedRow", 1)
        keySequence(StandardKey.Undo)
        waitForPosition(presenter, 3)
        tryCompare(pane, "highlightedRow", 1)
        compare(session.canUndo, false)
        compare(documentNotes(session.gridPresenter()), fixture.original)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Down)
        tryCompare(pane, "highlightedRow", 3)
        presenter.activate("roll.select_all")
        presenter.activate("roll.transpose_up")
        waitForCount(2)
        tryCompare(pane, "highlightedRow", 1)
        const playhead = session.playheadPresenter()
        compare(playhead.playing, false)
        list.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Space)
        verify(waitForNative(function() { return playhead.playing }, 5000))
        tryCompare(list, "activeFocus", true)
        keyClick(Qt.Key_Space)
        verify(waitForNative(function() { return !playhead.playing }, 5000))
        compare(presenter.undoHistoryVisible, true)
    }
}
