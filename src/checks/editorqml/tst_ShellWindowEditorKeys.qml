import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
    function test_cForeignWindowKeepsSoloLocal() {
        openTwoSongShell()
        var surface = selectedSurface()
        verify(surface && surface.visible, "the selected song page is mounted")
        var headers = findChild(surface, "timelineTrackHeaderRows")
        verify(headers && headers.count > 0, "the track headers are mounted")
        var firstTrack = headers.itemAt(surface.gridModel.trackIndex)
        verify(firstTrack && !firstTrack.isAddTrack, "the selected track is actionable")
        selectDrawnVelocityNote(surface)
        compare(firstTrack.soloChecked, false, "Solo starts off on the selected track")
        var soloShortcut = windowShortcut("shellShortcut_roll.solo_tracks")
        verify(soloShortcut, "the production window Solo shortcut is mounted")
        soloActivatedSpy.target = soloShortcut
        soloActivatedSpy.clear()

        var foreign = foreignWindowComponent.createObject(null)
        verify(foreign !== null, "the foreign window loads")
        try {
            foreign.requestActivate()
            tryCompare(foreign, "active", true, 3000)
            tryCompare(shell, "active", false, 3000)
            var field = findChild(foreign, "foreignSoloField")
            verify(field, "the foreign window has its own text field")
            field.selectAll()
            field.forceActiveFocus(Qt.OtherFocusReason)
            tryCompare(field, "activeFocus", true, 3000)
            keyClick(Qt.Key_S)
            tryCompare(field, "text", "s", 3000)
            compare(firstTrack.soloChecked, false,
                    "a foreign-window S does not Solo the main song")
            compare(soloActivatedSpy.count, 0,
                    "a foreign-window S never activates the main window shortcut")
        } finally {
            foreign.destroy()
        }
    }

    function test_gEditorRoutedNoteKeysAndChromeArrows() {
        openTwoSongShell()
        var surface = selectedSurface()
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the focused roll receives editor keys")
        selectDrawnVelocityNote(surface)
        var grid = surface.gridModel
        var chosen = JSON.parse(grid.noteSummary).filter(function(note) { return note.selected })
        compare(chosen.length, 1, "the pointer selected one source note")
        var original = chosen[0]
        function selectedNote() {
            var selection = JSON.parse(grid.noteSummary).filter(function(note) {
                return note.selected && note.id === original.id
            })
            compare(selection.length, 1, "the edited source note stays selected")
            return selection[0]
        }
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_Up)
        compare(selectedNote().pitch, original.pitch + 1, "Up transposes one semitone")
        keyClick(Qt.Key_Down)
        compare(selectedNote().pitch, original.pitch, "Down reverses Up")
        keyClick(Qt.Key_Up, Qt.ShiftModifier)
        compare(selectedNote().pitch, original.pitch + 12, "Shift+Up transposes an octave")
        keyClick(Qt.Key_Down, Qt.ShiftModifier)
        compare(selectedNote().pitch, original.pitch, "Shift+Down reverses the octave")
        keyClick(Qt.Key_Right)
        verify(selectedNote().tick > original.tick, "Right nudges the selected note forward")
        keyClick(Qt.Key_Left)
        compare(selectedNote().tick, original.tick, "Left returns the selected note")
        keyClick(Qt.Key_Right, Qt.ShiftModifier)
        verify(selectedNote().duration > original.duration,
               "Shift+Right lengthens the selected note")
        keyClick(Qt.Key_Left, Qt.ShiftModifier)
        compare(selectedNote().duration, original.duration,
                "Shift+Left restores the selected note duration")

        var drawer = findChild(surface, "editorDrawer")
        var grip = findChild(drawer, "drawerHandle_velocity")
        verify(grip && grip.visible, "the drawer resize grip is available")
        grip.forceActiveFocus(Qt.TabFocusReason)
        tryCompare(grip, "activeFocus", true, 3000)
        var beforeGrip = grid.noteSummary
        var heightBefore = surface.drawerPresenter.section(
                    bootstrap.velocitySectionKind()).bodyHeight
        keyClick(Qt.Key_Up)
        verify(surface.drawerPresenter.section(bootstrap.velocitySectionKind()).bodyHeight
               > heightBefore, "grip Up resizes the drawer locally")
        keyClick(Qt.Key_Down)
        compare(surface.drawerPresenter.section(bootstrap.velocitySectionKind()).bodyHeight,
                heightBefore, "grip Down restores its height")
        keyClick(Qt.Key_Left)
        keyClick(Qt.Key_Right)
        compare(grid.noteSummary, beforeGrip, "grip arrows never mutate selected notes")
        var revisionBeforeGrip = grid.appliedRevisionText
        var gripY = grip.height / 2
        mousePress(grip, grip.width / 2, gripY, Qt.LeftButton)
        mouseMove(grip, grip.width / 2, gripY - Qt.styleHints.startDragDistance * 2,
                  -1, Qt.LeftButton)
        var resizedHeight = surface.drawerPresenter.section(
                    bootstrap.velocitySectionKind()).bodyHeight
        verify(resizedHeight !== heightBefore,
               "the held drawer grip changes the section height")
        keyClick(Qt.Key_Delete)
        verify(grid.noteSummary === beforeGrip
               && grid.appliedRevisionText === revisionBeforeGrip,
               "drawer resize drag consumes Delete without editing the selected note")
        keyClick(Qt.Key_Escape)
        var cancelledHeight = surface.drawerPresenter.section(
                    bootstrap.velocitySectionKind()).bodyHeight
        mouseMove(grip, grip.width / 2, gripY + Qt.styleHints.startDragDistance * 2,
                  -1, Qt.LeftButton)
        compare(surface.drawerPresenter.section(bootstrap.velocitySectionKind()).bodyHeight,
                cancelledHeight, "Escape freezes the cancelled drawer resize")
        mouseRelease(grip, grip.width / 2, gripY, Qt.LeftButton)
        compare(grid.noteSummary, beforeGrip,
                "drawer resize Escape keeps the selected note intact")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_Right)
        verify(selectedNote().tick > original.tick,
               "note editing resumes after the drawer resize releases")
        keyClick(Qt.Key_Escape)
        compare(JSON.parse(grid.noteSummary).some(function(note) { return note.selected }),
                false, "the next idle Escape clears selection after the resize")
    }

    function test_gMultiNoteArrowSelectionAndHistory() {
        openTwoSongShell()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        selectDrawnVelocityNote(surface)
        var initiallySelected = JSON.parse(grid.noteSummary).find(function(note) {
            return note.selected && !note.ghost
        })
        var other = JSON.parse(grid.noteSummary).find(function(note) {
            var item = findChild(surface, "gridNote_" + note.id)
            return !note.selected && !note.ghost && item && item.visible
                   && item.width > 0 && item.height > 0
        })
        verify(initiallySelected && other, "two visible notes can form an arrow selection")
        var item = findChild(surface, "gridNote_" + other.id)
        var point = item.mapToItem(roll, item.width / 2, item.height / 2)
        mouseClick(roll, point.x, point.y, Qt.LeftButton, Qt.ShiftModifier)
        var before = JSON.parse(grid.noteSummary)
        var selected = before.filter(function(note) { return note.selected }).map(function(note) {
            return note.id
        })
        compare(selected.length, 2, "the click extends the note selection")
        var unchanged = before.filter(function(note) { return !note.selected })
        verify(unchanged.length > 0, "unselected notes remain for the invariance check")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        var directions = [
            { key: Qt.Key_Up, tick: 0, pitch: 1 },
            { key: Qt.Key_Down, tick: 0, pitch: -1 },
            { key: Qt.Key_Right, tick: grid.snapTicks, pitch: 0 }
        ]
        for (var direction of directions) {
            keyClick(direction.key)
            var after = JSON.parse(grid.noteSummary)
            verify(selected.every(function(id) {
                var previous = before.find(function(note) { return note.id === id })
                var current = after.find(function(note) { return note.id === id })
                return current && current.tick === previous.tick + direction.tick
                       && current.pitch === previous.pitch + direction.pitch
            }), "only selected notes move by one key or one snap")
            compare(JSON.stringify(after.filter(function(note) { return !note.selected })),
                    JSON.stringify(unchanged), "unselected notes stay byte-identical")
            compare(JSON.stringify(after.filter(function(note) { return note.selected })
                                          .map(function(note) { return note.id })),
                    JSON.stringify(selected), "the selection vector is identical after the arrow")
            keySequence(StandardKey.Undo)
            verify(waitForNative(function() {
                return grid.noteSummary === JSON.stringify(before)
            }, 3000), "one undo restores the pre-arrow state")
            keySequence(StandardKey.Redo)
            verify(waitForNative(function() {
                return grid.noteSummary === JSON.stringify(after)
            }, 3000), "one redo reapplies the selected-note arrow")
            keySequence(StandardKey.Undo)
            verify(waitForNative(function() {
                return grid.noteSummary === JSON.stringify(before)
            }, 3000))
        }
        keyClick(Qt.Key_Right)
        keyClick(Qt.Key_Left)
        compare(grid.noteSummary, JSON.stringify(before),
                "Left moves the selected notes back by one snap")
    }

    function test_iEditorCommandDeliveryAndTextLocalKeys() {
        openTwoSongShell()
        var surface = selectedSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        verify(roll && roll.visible, "the production roll routes editor commands")
        selectDrawnVelocityNote(surface)
        var original = JSON.parse(grid.noteSummary).filter(function(note) { return note.selected })[0]
        verify(original, "the selected fixture note is available")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keyClick(Qt.Key_D, Qt.ControlModifier)
        var duplicated = JSON.parse(grid.noteSummary).filter(function(note) {
            return note.selected && note.id !== original.id
                && note.pitch === original.pitch && note.tick > original.tick
        })
        compare(duplicated.length, 1, "Ctrl+D duplicates and selects the original note")
        keySequence(StandardKey.SelectAll)
        var selectedForJoin = JSON.parse(grid.noteSummary).filter(function(note) {
            return note.selected && note.track === original.track
        })
        verify(selectedForJoin.some(function(note) { return note.id === original.id })
               && selectedForJoin.some(function(note) { return note.id === duplicated[0].id }),
               "Select All includes both same-track notes")
        keyClick(Qt.Key_J, Qt.ControlModifier)
        var joined = JSON.parse(grid.noteSummary)
        verify(joined.filter(function(note) { return note.track === original.track }).length
               < selectedForJoin.length,
               "Ctrl+J merges the adjacent same-pitch notes")
        var selectedJoined = joined.filter(function(note) {
            return note.selected && note.track === original.track
                && note.pitch === original.pitch && note.duration > grid.snapTicks
        })
        verify(selectedJoined.length > 0, "Join selects a subdividable merged note")
        keyClick(Qt.Key_E, Qt.ControlModifier)
        var split = JSON.parse(grid.noteSummary)
        verify(split.length > joined.length, "Ctrl+E splits selected notes on grid boundaries")
        verify(split.some(function(note) { return note.selected && note.pitch === original.pitch }),
               "Split keeps the resulting note fragments selected")

        var beforeCut = split.length
        keySequence(StandardKey.Cut)
        var afterCut = JSON.parse(grid.noteSummary)
        verify(afterCut.length < beforeCut, "Cut deletes selected notes from the focused roll")
        var cutClip = JSON.parse(bootstrap.copiedClipSummary())
        compare(cutClip[0], 1, "Cut writes a decodable single-track clipboard clip")
        verify(cutClip[1] > 0, "Cut preserves at least one copied note")
        keySequence(StandardKey.Paste)
        var afterPaste = JSON.parse(grid.noteSummary)
        verify(afterPaste.length > afterCut.length, "Paste inserts clipboard notes into the roll")
        verify(afterPaste.some(function(note) { return note.selected }),
               "Paste selects at least one inserted note")

        var textProbe = textProbeComponent.createObject(shell.contentItem,
                                                        { x: 20, y: 20 })
        verify(textProbe, "a text editor mounts in the real window")
        textProbe.text = "text"
        textProbe.cursorPosition = 0
        textProbe.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(textProbe, "activeFocus", true, 3000)
        var notesBeforeLocalKeys = grid.noteSummary
        keyClick(Qt.Key_D, Qt.ControlModifier)
        compare(grid.noteSummary, notesBeforeLocalKeys,
                "text-focused Duplicate never changes the musical notes")
        keyClick(Qt.Key_Delete)
        compare(textProbe.text, "ext", "text-focused Delete edits the local text")
        compare(grid.noteSummary, notesBeforeLocalKeys,
                "text-focused Delete never deletes selected notes")
        textProbe.destroy()

        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true, 3000)
        keySequence(StandardKey.SelectAll)
        var selectedAll = JSON.parse(grid.noteSummary).filter(function(note) {
            return note.selected && note.track === original.track
        })
        verify(selectedAll.length > 0, "Select All targets the currently focused roll track")
        keyClick(Qt.Key_Delete)
        var remaining = JSON.parse(grid.noteSummary)
        compare(remaining.filter(function(note) { return note.track === original.track }).length,
                0, "Delete removes only the selected track's notes")
    }
}
