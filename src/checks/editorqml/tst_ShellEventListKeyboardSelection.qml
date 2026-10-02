import QtQuick
import QtQuick.Controls
import QtTest
import "RollNoteFaces.js" as RollNoteFaces

ShellEventListSupport {
    function test_keyboardSelectionStaysOnMountedEventRows() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        waitForShellScene()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song load settles")
        verify(session.songOpen, session.lastSaveError)
        let surface = null
        tryVerify(function() {
            const tab = findChild(shell.sceneLoader.item,
                                  "songTab_" + session.songTabs.selectedId)
            surface = tab ? findChild(tab, "swiftRollOverlay") : null
            return surface && surface.gridModel.renderedNoteCount > 0
        }, 5000, "the mounted roll publishes selectable notes")
        const grid = surface.gridModel
        const roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible)
        const notes = JSON.parse(grid.fetchNoteSummary())
        let chosenNote = null
        const renderer = findChild(surface, "timelineRendererPlot")
        for (const note of notes) {
            const center = RollNoteFaces.center(renderer, roll, note.id)
            if (!center)
                continue
            if (center.x > 1 && center.y > 1 && center.x < roll.width - 1
                && center.y < roll.height - 1) {
                mouseClick(roll, center.x, center.y)
                chosenNote = note
                break
            }
        }
        verify(chosenNote !== null, "the roll exposes a note for window Copy")
        tryVerify(function() {
            return JSON.parse(grid.fetchNoteSummary()).some(function(note) {
                return note.id === chosenNote.id && note.selected
            })
        }, 3000, "a real roll click selects the note before event-list focus")
        shell.shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        let page = null
        tryVerify(function() {
            page = findChild(shell.sceneLoader.item, "eventListPage")
            return page !== null && page.visible
        }, 3000, "event list is mounted")
        const presenter = session.eventListPresenter()
        verify(presenter.rowCount >= 4, "event-list fixture has at least four rows")
        page.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(page, "activeFocus", true, 3000, "event list owns keyboard focus")
        presenter.selectRow(0, Qt.NoModifier)
        keyClick(Qt.Key_Down)
        compare(presenter.currentRow, 1, "Down moves the event-row cursor")
        keyClick(Qt.Key_Up)
        compare(presenter.currentRow, 0, "Up moves the event-row cursor")
        keyClick(Qt.Key_A, Qt.ControlModifier)
        for (let row = 0; row < presenter.rowCount; ++row)
            verify(presenter.isSelected(row), "Select All targets every event row")
        let copyShortcut = null
        const contentLoader = findChild(shell, "shellContentLoader")
        verify(contentLoader !== null && contentLoader.status === Loader.Ready,
               "the deferred window controls are mounted")
        for (const delegate of contentLoader.item.children) {
            const objects = delegate.data
            for (const object of objects || []) {
                if (object.objectName === "shellShortcut_roll.copy")
                    copyShortcut = object
            }
        }
        verify(copyShortcut !== null, "window Copy shortcut is mounted")
        copySpy.target = copyShortcut
        copySpy.clear()
        keySequence(StandardKey.Copy)
        compare(copySpy.count, 1, "window Copy runs exactly once under event-list focus")
        const clip = JSON.parse(bootstrap.copiedClipSummary())
        compare(clip[0], 1, "window Copy exports the selected roll track")
        compare(clip[1], 1, "window Copy exports one selected roll note")
        compare(clip[2], chosenNote.pitch, "clipboard retains the selected note pitch")
        for (let row = 0; row < presenter.rowCount; ++row)
            verify(presenter.isSelected(row), "Copy does not retarget the event-row selection")
        const playhead = session.playheadPresenter()
        compare(playhead.playing, false)
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", true, 3000,
                   "event-list focus yields Space to the window transport")
        keyClick(Qt.Key_Space)
        tryCompare(playhead, "playing", false, 3000)
        let moveRow = -1
        for (let row = 1; row < presenter.rowCount; ++row) {
            if (presenter.rowKind(row) === 0 && presenter.rowKind(row - 1) === 0
                && presenter.isLegalDrop(row, row - 1)
                && presenter.cellDisplay(row, 6) !== presenter.cellDisplay(row - 1, 6)) {
                moveRow = row
                break
            }
        }
        verify(moveRow > 0, "fixture has distinguishable same-tick event neighbors")
        const beforeMoveCount = presenter.rowCount
        const earlierSummary = presenter.cellDisplay(moveRow - 1, 6)
        const movedSummary = presenter.cellDisplay(moveRow, 6)
        presenter.selectRow(moveRow, Qt.NoModifier)
        keyClick(Qt.Key_Up, Qt.AltModifier)
        compare(presenter.cellDisplay(moveRow - 1, 6), movedSummary,
                "Alt+Up moves the selected event ahead of its same-tick neighbor")
        compare(presenter.cellDisplay(moveRow, 6), earlierSummary,
                "the displaced event remains in the next row")
        compare(presenter.rowCount, beforeMoveCount, "reordering preserves the event count")
        const afterMoveNote = JSON.parse(grid.fetchNoteSummary()).find(function(note) {
            return note.id === chosenNote.id
        })
        verify(afterMoveNote !== undefined && afterMoveNote.selected
               && afterMoveNote.tick === chosenNote.tick
               && afterMoveNote.pitch === chosenNote.pitch,
               "same-tick reorder preserves the unrelated selected roll note")
        let protectedRow = -1
        for (let row = 0; row < presenter.rowCount; ++row) {
            if (presenter.rowKind(row) === 0 && presenter.rowTick(row) === chosenNote.tick) {
                protectedRow = row
                break
            }
        }
        verify(protectedRow >= 0, "the selected roll note has an event-list row")
        function uniqueTick(row) {
            const tick = presenter.rowTick(row)
            for (let other = 0; other < presenter.rowCount; ++other) {
                if (other !== row && presenter.rowTick(other) === tick)
                    return false
            }
            return true
        }
        let victim = -1
        for (let row = 0; row < presenter.rowCount; ++row) {
            if (presenter.rowKind(row) === 0 && uniqueTick(row)
                && presenter.rowTick(row) !== chosenNote.tick
                && presenter.rowTick(row) !== chosenNote.tick + chosenNote.duration) {
                victim = row
                break
            }
        }
        verify(victim >= 0, "fixture has a deletable raw event")
        presenter.selectRow(victim, Qt.NoModifier)
        const table = findChild(page, "eventListTable")
        verify(table !== null, "the mounted table is available for in-cell editing")
        table.positionViewAtRow(victim, TableView.Contain)
        tryVerify(function() {
            return table.itemAtCell(Qt.point(page.currentColumn, victim)) !== null
        }, 3000, "the selected event cell is rendered before F2")
        keyClick(Qt.Key_F2)
        tryCompare(presenter, "editing", true, 3000,
                   "F2 opens the focused event cell")
        let editor = null
        tryVerify(function() {
            editor = findChild(page, "eventListTickEditor")
            return editor !== null && editor.activeFocus
        }, 3000, "event cell receives text focus")
        keyClick(Qt.Key_A, Qt.ControlModifier)
        compare(editor.selectedText, editor.text,
                "Select All stays in the focused cell while editing")
        verify(presenter.isSelected(victim), "cell Select All leaves the event selection intact")
        keyClick(Qt.Key_Escape)
        tryCompare(presenter, "editing", false, 3000)
        tryCompare(page, "activeFocus", true, 3000,
                   "leaving the event cell restores page navigation focus")
        compare(page.navigationEnabled, true)
        let secondVictim = -1
        for (let row = victim + 1; row < presenter.rowCount; ++row) {
            if (presenter.rowKind(row) === 0 && uniqueTick(row)
                && presenter.rowTick(row) !== chosenNote.tick
                && presenter.rowTick(row) !== chosenNote.tick + chosenNote.duration) {
                secondVictim = row
                break
            }
        }
        verify(secondVictim > victim, "fixture has two unrelated raw event rows")
        const firstTick = presenter.rowTick(victim)
        const secondTick = presenter.rowTick(secondVictim)
        presenter.selectRow(-1, Qt.NoModifier)
        let firstCell = null
        table.positionViewAtRow(victim, TableView.Contain)
        tryVerify(function() {
            firstCell = table.itemAtCell(Qt.point(0, victim))
            return firstCell !== null
        }, 3000, "first victim is visible for the pointer")
        mouseClick(firstCell, firstCell.width / 2, firstCell.height / 2)
        let secondCell = null
        table.positionViewAtRow(secondVictim, TableView.Contain)
        tryVerify(function() {
            secondCell = table.itemAtCell(Qt.point(0, secondVictim))
            return secondCell !== null
        }, 3000, "second victim is visible for the pointer")
        mouseClick(secondCell, secondCell.width / 2, secondCell.height / 2,
                   Qt.LeftButton, Qt.ControlModifier)
        verify(presenter.isSelected(victim) && presenter.isSelected(secondVictim),
               "Ctrl-click selects both unrelated event rows")
        tryCompare(page, "activeFocus", true, 3000)
        const beforeDelete = presenter.rowCount
        keyClick(Qt.Key_Delete)
        tryCompare(presenter, "rowCount", beforeDelete - 2, 3000,
                   "Delete removes exactly two event rows, not the roll selection")
        compare(presenter.currentRow, -1,
                "the Delete key removes the selected rows and clears their cursor")
        for (let row = 0; row < presenter.rowCount; ++row)
            verify(!presenter.isSelected(row), "the Delete key clears every selected event row")
        for (let row = 0; row < presenter.rowCount; ++row)
            verify(presenter.rowTick(row) !== firstTick
                   && presenter.rowTick(row) !== secondTick,
                   "both deleted raw-event ticks are absent from the Event List")
        const survivor = JSON.parse(grid.fetchNoteSummary()).find(function(note) {
            return note.id === chosenNote.id
        })
        verify(survivor !== undefined && survivor.selected
               && survivor.tick === chosenNote.tick && survivor.pitch === chosenNote.pitch
               && survivor.duration === chosenNote.duration && survivor.duration > 0,
               "event-row Delete preserves the unrelated selected roll note")
    }
    function test_tickBoundariesThroughMountedEditor() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        waitForShellScene()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song load settles")
        verify(session.songOpen, session.lastSaveError)
        shell.shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        let page = null
        tryVerify(function() {
            page = findChild(shell.sceneLoader.item, "eventListPage")
            return page !== null && page.visible
        }, 3000, "event list is mounted")
        const presenter = session.eventListPresenter()
        verify(presenter.rowCount >= 3, "fixture has editable rows and an EOT sentinel")
        const table = findChild(page, "eventListTable")
        verify(table !== null, "the mounted table is available for in-cell editing")
        tryCompare(table, "rows", presenter.rowCount, 3000,
                   "EOT fixture rows populate the mounted table before cell lookup")

        function eotLabel() {
            const eotRow = presenter.rowCount - 1
            const cell = table.itemAtCell(Qt.point(1, eotRow))
            if (!cell)
                return null
            for (const child of cell.children) {
                if (child instanceof Text && child.text === "End of track")
                    return child
            }
            return null
        }
        function mountedEotLabel() {
            table.positionViewAtRow(presenter.rowCount - 1, TableView.AlignBottom)
            table.forceLayout()
            tryVerify(function() {
                return table.itemAtCell(Qt.point(1, presenter.rowCount - 1)) !== null
            }, 3000, "the EOT Type cell is instantiated")
            tryVerify(function() { return eotLabel() !== null }, 3000,
                      "the EOT label cell is rendered")
            return eotLabel()
        }
        compare(mountedEotLabel().color, presenter.rowCount % 2 === 0 ? page.tableText
                                                                   : page.tableSecondaryText,
                "the EOT label resolves muted ink for the base stripe or row ink on the alternate stripe")

        let note = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.rowType(row) === 1) {
                note = row
                break
            }
        }
        verify(note >= 0, "fixture has a note-on row")
        page.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(page, "activeFocus", true, 3000)
        page.currentColumn = 0
        presenter.selectRow(note, Qt.NoModifier)
        compare(presenter.currentRow, note)
        table.positionViewAtRow(note, TableView.Contain)
        tryVerify(function() {
            return table.itemAtCell(Qt.point(0, note)) !== null
        }, 3000, "the tick cell is rendered before F2")
        const originalTick = presenter.tickString(note)
        keyClick(Qt.Key_F2)
        tryCompare(presenter, "editing", true, 3000, "F2 opens the tick cell")
        let editor = null
        tryVerify(function() {
            editor = findChild(page, "eventListTickEditor")
            return editor !== null && editor.activeFocus
        }, 3000, "the tick editor takes text focus")
        keyClick(Qt.Key_A, Qt.ControlModifier)
        const noTick = "4294967295"
        for (let i = 0; i < noTick.length; ++i)
            keyClick(noTick.charCodeAt(i))
        keyClick(Qt.Key_Return)
        verify(presenter.editing, "typed kNoTick keeps the editor open")
        compare(presenter.tickString(note), originalTick,
                "typed kNoTick leaves the displayed tick unchanged")
        keyClick(Qt.Key_Escape)
        tryCompare(presenter, "editing", false, 3000)
        tryCompare(page, "activeFocus", true, 3000,
                   "leaving the tick cell restores page navigation focus")
        keyClick(Qt.Key_F2)
        tryCompare(presenter, "editing", true, 3000, "F2 re-opens the tick cell")
        tryVerify(function() {
            editor = findChild(page, "eventListTickEditor")
            return editor !== null && editor.activeFocus
        }, 3000, "the reopened tick editor takes text focus")
        keyClick(Qt.Key_A, Qt.ControlModifier)
        const maxTick = "4294967294"
        for (let i = 0; i < maxTick.length; ++i)
            keyClick(maxTick.charCodeAt(i))
        compare(editor.text, maxTick, "the typed kMaxTick digits replace the cell text")
        keyClick(Qt.Key_Return)
        tryCompare(presenter, "editing", false, 3000,
                   "typed kMaxTick commits and closes the editor")
        let moved = -1
        for (let row = 0; row < presenter.rowCount - 1; ++row) {
            if (presenter.tickString(row) === maxTick) {
                moved = row
                break
            }
        }
        verify(moved >= 0, "the committed row republishes at kMaxTick")
        compare(presenter.rowType(moved), 1,
                "the kMaxTick row keeps its note-on type")

        tryCompare(page, "activeFocus", true, 3000)
        const beforeDelete = presenter.rowCount
        presenter.selectRow(0, Qt.NoModifier)
        keyClick(Qt.Key_Delete)
        tryCompare(presenter, "rowCount", beforeDelete - 1, 3000,
                   "deleting one row flips the EOT row's stripe parity")
        compare(mountedEotLabel().color, (presenter.rowCount - 1) % 2 === 1 ? page.tableText
                                                                          : page.tableSecondaryText,
                "the flipped stripe parity keeps the muted EOT ink AA against its fill")
    }
}
