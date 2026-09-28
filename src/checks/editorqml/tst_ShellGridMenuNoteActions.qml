import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellGridMenuSupport {
    id: testCase

    function test_noteCommandRowsDispatchOnSelectedNote() {
        openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var original = JSON.parse(grid.fetchNoteSummary())
        var snap = grid.snapTicks
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var start = Math.ceil((grid.cameraScrollX + roll.width / 3) / pixelsPerTick / snap) * snap
        var pitchRow = -1
        for (var row = Math.ceil(grid.cameraScrollY / grid.rowHeight) + 2;
             row < Math.floor((grid.cameraScrollY + roll.height) / grid.rowHeight) - 2;
             ++row) {
            var pitch = 127 - row
            if (!original.some(function(note) {
                return note.pitch === pitch && note.tick < start + 7 * snap
                    && note.tick + note.duration > start
            })) {
                pitchRow = row
                break
            }
        }
        verify(pitchRow >= 0 && (start + 7 * snap) * pixelsPerTick - grid.cameraScrollX < roll.width,
               "seven snap cells are free and visible for the note commands")
        var y = (pitchRow + 0.5) * grid.rowHeight - grid.cameraScrollY
        var x = start * pixelsPerTick - grid.cameraScrollX + grid.drawThreshold / 2
        var endX = (start + 2.5 * snap) * pixelsPerTick - grid.cameraScrollX
        mousePress(roll, x, y, Qt.LeftButton)
        mouseMove(roll, endX, y, -1, Qt.LeftButton)
        mouseRelease(roll, endX, y, Qt.LeftButton)
        var source = null
        tryVerify(function() {
            source = JSON.parse(grid.fetchNoteSummary()).find(function(note) {
                return original.every(function(previous) { return previous.id !== note.id })
            })
            return source !== undefined
        }, 3000)
        verify(source.pitch === 127 - pitchRow && source.tick === start,
               "physical note lands at selected row and cell: " + grid.fetchNoteSummary()
               + " expected tick " + start + " pitch " + (127 - pitchRow))
        verify(source.duration === 3 * snap,
               "the physical draw creates a three-cell source (duration "
               + source.duration + ", snap " + snap + ")")
        var centerX = (start + snap) * pixelsPerTick - grid.cameraScrollX
        mouseClick(roll, centerX, y, Qt.LeftButton)
        var menu = noteMenu()
        function activate(actionId, atX) {
            mouseClick(roll, atX, y, Qt.RightButton)
            tryCompare(menu, "visible", true)
            var row = findChild(menu, "shellContextAction_" + actionId)
            verify(row !== null && row.enabled, "the mounted note menu has enabled " + actionId)
            mouseClick(row, row.width / 2, row.height / 2)
            tryCompare(menu, "visible", false)
        }
        activate("roll.duplicate_time", centerX)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(note) {
            return note.tick === start + 3 * snap && note.pitch === source.pitch
                && note.duration === 3 * snap
        }), "the Duplicate row copies its selected note one span later")
        mouseClick(roll, centerX, y, Qt.LeftButton)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(note) {
            return note.tick === start && note.pitch === source.pitch
                && note.selected && note.duration === 3 * snap
        }), "clicking the original selects the three-cell source before Split")
        var divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        clickRow(divisionMenu, 3)
        tryCompare(grid, "gridSelectionMenuId", 16)
        tryVerify(function() { return grid.visibleGridTicks === snap }, 3000)
        tryVerify(function() { return findChild(surface(), "quickMenuPanelRoot") === null }, 3000)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(note) {
            return note.tick === start && note.pitch === source.pitch && note.selected
        }), "grid division changes retain the selected source")
        activate("roll.split", centerX)
        var pieces = JSON.parse(grid.fetchNoteSummary()).filter(function(note) {
            return note.pitch === source.pitch && note.tick >= start
                && note.tick < start + 3 * snap && note.duration === snap
        })
        compare(pieces.length, 3, "the Split row yields three grid pieces: " + grid.fetchNoteSummary())
        activate("roll.join", centerX)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(note) {
            return note.tick === start && note.pitch === source.pitch
                && note.duration === 3 * snap
        }), "the Join row merges the selected three pieces")
    }

    function test_noteMenuRetargetAndDismiss() {
        openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var targets = noteTargets()
        verify(targets.length > 1, "two drawn primary notes accept note menus")
        var first = targets[0]
        mouseClick(roll, first.point.x, first.point.y, Qt.RightButton)
        var menu = noteMenu()
        tryCompare(menu, "visible", true)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(note) {
            return note.id === first.note.id && note.selected
        }), "a right release over an unselected note selects it and opens the note menu")
        verify(menu.itemAt(0).objectName === "shellContextAction_edit.set_velocity"
               && findChild(menu, "shellContextAction_roll.paste") === null,
               "the rendered note menu leads with Set Velocity and omits Paste")
        var second = null
        for (var index = 1; index < targets.length; ++index) {
            var point = roll.mapToItem(null, targets[index].point.x, targets[index].point.y)
            if (point.x < menu.x || point.x > menu.x + menu.width
                || point.y < menu.y || point.y > menu.y + menu.height) {
                second = targets[index]
                break
            }
        }
        verify(second !== null, "a second drawn note lies outside the open menu")
        var before = noteLayout()
        var revision = grid.appliedRevisionText
        var cursor = grid.editCursorTick
        var position = roll.mapToItem(shell.contentItem, second.point.x, second.point.y)
        mousePress(shell.contentItem, position.x, position.y, Qt.RightButton)
        tryCompare(menu, "visible", true, 3000)
        verify(menu.visible && JSON.parse(grid.fetchNoteSummary()).some(function(note) {
            return note.id === second.note.id && note.selected
        }), "an outside right press retargets the open note menu to the note under the cursor")
        mouseRelease(shell.contentItem, position.x, position.y, Qt.RightButton)
        compare(noteLayout(), before, "the retarget release leaves the timeline untouched")
        compare(grid.appliedRevisionText, revision)
        compare(grid.editCursorTick, cursor)
        var miss = noteMenuMiss(menu)
        verify(miss !== null, "an empty plot point lies outside the retargeted menu")
        mousePress(shell.contentItem, miss.x, miss.y, Qt.RightButton)
        compare(menu.visible, false,
                "an outside right press on an empty row dismisses the note menu without editing")
        mouseRelease(shell.contentItem, miss.x, miss.y, Qt.RightButton)
        compare(noteLayout(), before)
        compare(grid.appliedRevisionText, revision)
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(note) {
            return note.id === second.note.id && note.selected
        }), "the empty-space release preserves the retargeted note selection")
    }

    function test_noteMenuPromptRoundTripWithHiddenDrawer() {
        var session = openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var drawer = surface().drawerPresenter
        var drawerItem = control("editorDrawer")
        for (var kind = 0; kind < 3; ++kind)
            drawer.setSectionVisible(kind, false, false)
        drawerItem.visible = false
        compare(drawerItem.visible, false, "the drawer is hidden before the prompt opens")
        var target = noteTargets()[0]
        verify(target !== undefined, "a visible fixture note can be seeded at velocity 73")
        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        var menu = noteMenu()
        tryCompare(menu, "visible", true)
        var row = menu.itemAt(0)
        mouseClick(row, row.width / 2, row.height / 2)
        var model = surface().velocityModel
        tryCompare(model, "promptOpen", true)
        tryVerify(function() { return findChild(surface(), "noteVelocityInput") !== null }, 3000)
        var field = findChild(surface(), "noteVelocityInput")
        tryCompare(field, "activeFocus", true)
        field.selectAll()
        keyClick(Qt.Key_7)
        keyClick(Qt.Key_3)
        keyClick(Qt.Key_Return)
        tryCompare(model, "promptOpen", false)
        verify(waitForNative(function() {
            return JSON.parse(grid.fetchNoteSummary()).some(function(note) {
                return note.id === target.note.id && note.velocity === 73
            })
        }, 5000), "the mounted fixture note is seeded at velocity 73")
        var before = noteLayout()
        var baselineRevision = grid.appliedRevisionText
        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        tryCompare(menu, "visible", true)
        row = menu.itemAt(0)
        mouseClick(row, row.width / 2, row.height / 2)
        tryCompare(model, "promptOpen", true)
        tryVerify(function() { return findChild(surface(), "noteVelocityInput") !== null }, 3000)
        var card = findChild(surface(), "velocityPromptCard")
        field = findChild(surface(), "noteVelocityInput")
        verify(card !== null && field !== null && card.visible && card.width > 0
               && card.height > 0 && !drawerItem.visible && !menu.visible,
               "the prompt renders over the roll while the drawer is hidden")
        tryCompare(field, "activeFocus", true)
        verify(field.text === "73" && field.selectedText === "73",
               "the Set Velocity row opens the prompt over the roll with the note's velocity selected")
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_5)
        compare(noteLayout(), before, "typing the velocity draft does not edit the timeline")
        compare(grid.appliedRevisionText, baselineRevision)
        keyClick(Qt.Key_Return)
        tryCompare(model, "promptOpen", false)
        verify(roll.activeFocus, "accepting the prompt restores roll focus; active item "
               + (shell.activeFocusItem ? shell.activeFocusItem.objectName : "<none>"))
        verify(JSON.parse(grid.fetchNoteSummary()).some(function(note) {
            return note.id === target.note.id && note.velocity === 95
        }), "accepting the mounted prompt changes the captured note")
        var accepted = noteLayout()
        verify(accepted !== before && grid.appliedRevisionText !== baselineRevision
               && session.canUndo, "the mounted acceptance commits one undoable edit")
        shell.shellPresenter.activate("edit.undo")
        verify(waitForNative(function() {
            return noteLayout() === before && session.canRedo
        }, 5000), "one undo restores the exact pre-prompt note layout")
        compare(session.canUndo, true, "the earlier fixture edit remains after undoing acceptance")
        compare(grid.lastVelocity, 95, "undo leaves the pencil latch at the accepted value")

        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        tryCompare(menu, "visible", true)
        row = menu.itemAt(0)
        mouseClick(row, row.width / 2, row.height / 2)
        tryCompare(model, "promptOpen", true)
        tryVerify(function() { return findChild(surface(), "noteVelocityInput") !== null }, 3000)
        field = findChild(surface(), "noteVelocityInput")
        tryCompare(field, "activeFocus", true)
        compare(field.selectedText, "73")
        var unchangedRevision = grid.appliedRevisionText
        var unchangedLayout = noteLayout()
        keyClick(Qt.Key_Return)
        tryCompare(model, "promptOpen", false)
        verify(noteLayout() === unchangedLayout
               && grid.appliedRevisionText === unchangedRevision && session.canRedo
               && grid.lastVelocity === 73,
               "accepting an unchanged velocity over the roll writes nothing and relatches the pencil")
        var snap = grid.snapTicks
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var duration = Math.max(snap, Math.ceil(grid.drawThreshold / pixelsPerTick / snap) * snap)
        var start = Math.ceil((grid.cameraScrollX + roll.width / 3) / pixelsPerTick / snap) * snap
        var draw = null
        var occupied = JSON.parse(grid.fetchNoteSummary())
        for (var rowIndex = Math.ceil(grid.cameraScrollY / grid.rowHeight) + 2;
             rowIndex < Math.floor((grid.cameraScrollY + roll.height) / grid.rowHeight) - 2;
             ++rowIndex) {
            var pitch = 127 - rowIndex
            if (!occupied.some(function(note) {
                return note.pitch === pitch && note.tick < start + duration
                    && note.tick + note.duration > start
            })) {
                draw = { x: start * pixelsPerTick - grid.cameraScrollX
                             + grid.drawThreshold / 2,
                         y: (rowIndex + 0.5) * grid.rowHeight - grid.cameraScrollY }
                break
            }
        }
        verify(draw !== null && draw.x + duration * pixelsPerTick < roll.width,
               "a free displayed cell accepts the relatched pencil")
        var drawEnd = draw.x + duration * pixelsPerTick - grid.drawThreshold / 2
        mousePress(roll, draw.x, draw.y, Qt.LeftButton)
        mouseMove(roll, drawEnd, draw.y, -1, Qt.LeftButton)
        mouseRelease(roll, drawEnd, draw.y, Qt.LeftButton)
        verify(waitForNative(function() {
            return JSON.parse(grid.fetchNoteSummary()).some(function(note) {
                return occupied.every(function(previous) { return previous.id !== note.id })
                    && note.velocity === 73
            })
        }, 5000), "the unchanged prompt acceptance supplies the next drawn note's velocity")

        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        tryCompare(menu, "visible", true)
        row = menu.itemAt(0)
        mouseClick(row, row.width / 2, row.height / 2)
        tryCompare(model, "promptOpen", true)
        tryVerify(function() { return findChild(surface(), "noteVelocityInput") !== null }, 3000)
        field = findChild(surface(), "noteVelocityInput")
        tryCompare(field, "activeFocus", true)
        var beforeEscape = noteLayout()
        var revision = grid.appliedRevisionText
        keyClick(Qt.Key_Escape)
        tryCompare(model, "promptOpen", false)
        verify(noteLayout() === beforeEscape && grid.appliedRevisionText === revision
               && roll.activeFocus, "Escape closes the prompt over the roll without writing")
    }

    function test_noteMenuRetiresOnDocumentEditAndPreservesOtherFocus() {
        var session = openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var target = noteTargets()[0]
        verify(target !== undefined, "a mounted note accepts a context menu")
        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        var menu = noteMenu()
        tryCompare(menu, "visible", true)
        var before = noteLayout()
        var revision = grid.appliedRevisionText
        grid.performCommand(5)
        tryCompare(menu, "visible", false)
        verify(grid.appliedRevisionText !== revision
               && noteLayout() !== before && session.canUndo,
               "a document edit retires the open note menu synchronously")
        shell.shellPresenter.activate("edit.undo")
        verify(waitForNative(function() { return noteLayout() === before }, 5000),
               "undo restores the note edited while its menu was open")
        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        tryCompare(menu, "visible", true)
        var row = menu.itemAt(0)
        mouseClick(row, row.width / 2, row.height / 2)
        var model = surface().velocityModel
        tryCompare(model, "promptOpen", true)
        tryVerify(function() { return findChild(surface(), "noteVelocityInput") !== null }, 3000)
        var field = findChild(surface(), "noteVelocityInput")
        tryCompare(field, "activeFocus", true)
        var ruler = control("timelineRulerInput")
        ruler.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(ruler, "activeFocus", true)
        model.cancelPrompt()
        tryCompare(model, "promptOpen", false)
        compare(ruler.activeFocus, true,
                "closing the prompt does not steal focus from another control")
    }

    function test_noteMenuKeyboardDeleteAndEscape() {
        var session = openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var targets = noteTargets()
        verify(targets.length > 2)
        mouseClick(roll, targets[0].point.x, targets[0].point.y, Qt.LeftButton)
        mouseClick(roll, targets[1].point.x, targets[1].point.y,
                   Qt.LeftButton, Qt.ControlModifier)
        tryVerify(function() {
            return JSON.parse(grid.fetchNoteSummary()).filter(function(note) {
                return note.selected
            }).length === 2
        }, 3000)
        var nudge = findChild(shell, "shellAction_roll.nudge_right")
        verify(nudge !== null, "the mounted Edit menu owns Nudge Right")
        tryCompare(nudge, "enabled", true, 3000,
                   "the mounted Nudge Right row enables for the note selection")
        var deleteNotes = findChild(shell, "shellAction_roll.delete")
        tryVerify(function() { return deleteNotes !== null && deleteNotes.enabled }, 3000,
                  "the mounted Edit menu owns an enabled Delete row before a gesture")
        verify(findChild(shell, "shellAction_roll.copy") !== null
               && findChild(shell, "shellAction_roll.paste") !== null
               && findChild(shell, "shellAction_edit.undo") !== null
               && findChild(shell, "shellAction_edit.redo") !== null,
               "the mounted Edit menu owns Copy Paste Undo and Redo")
        var before = JSON.parse(grid.fetchNoteSummary())
        var selectedIds = before.filter(function(note) { return note.selected })
            .map(function(note) { return note.id }).sort()
        var layout = noteLayout()
        var revision = grid.appliedRevisionText
        var canUndo = session.canUndo
        var canRedo = session.canRedo
        mouseClick(roll, targets[0].point.x, targets[0].point.y, Qt.RightButton)
        var menu = noteMenu()
        tryCompare(menu, "visible", true, 3000, "right click opens the mounted note menu")
        compare(JSON.stringify(JSON.parse(grid.fetchNoteSummary()).filter(function(note) {
            return note.selected
        }).map(function(note) { return note.id }).sort()), JSON.stringify(selectedIds),
                "opening the note menu preserves an existing multi-selection")
        keyClick(Qt.Key_Escape)
        tryVerify(function() {
            var ids = JSON.parse(grid.fetchNoteSummary()).filter(function(note) {
                return note.selected
            }).map(function(note) { return note.id }).sort()
            return !menu.visible && JSON.stringify(ids) === JSON.stringify(selectedIds)
                && grid.appliedRevisionText === revision
                && session.canUndo === canUndo && session.canRedo === canRedo
        }, 3000, "Escape closes the grid menu preserving the selection without a history entry")
        mouseClick(roll, targets[0].point.x, targets[0].point.y, Qt.RightButton)
        tryCompare(menu, "visible", true)
        var deleteRow = findChild(menu, "shellContextAction_roll.delete")
        verify(deleteRow !== null && deleteRow.enabled)
        for (var step = 0; step < menu.count && !deleteRow.highlighted; ++step)
            keyClick(Qt.Key_Down)
        verify(deleteRow.highlighted, "arrow traversal reaches the note menu Delete row")
        keyClick(Qt.Key_Return)
        var expected = JSON.stringify(before.filter(function(note) {
            return selectedIds.indexOf(note.id) < 0
        }).map(function(note) {
            return [note.track, note.tick, note.duration, note.pitch, note.velocity]
        }).sort())
        tryVerify(function() {
            return !menu.visible && noteLayout() === expected
        }, 3000, "Return activates the highlighted grid menu row")
        compare(JSON.stringify(JSON.parse(grid.fetchNoteSummary()).map(function(note) {
            return note.id
        }).sort()), JSON.stringify(before.filter(function(note) {
            return selectedIds.indexOf(note.id) < 0
        }).map(function(note) { return note.id }).sort()),
                "keyboard Delete removes the selected identities and keeps every other note")
        session.requestUndo()
        verify(waitForNative(function() { return noteLayout() === layout }, 5000),
               "one undo restores exactly the keyboard-deleted notes")
    }

}
