import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellWindowSupport {
    function test_seededEventListRestoresBothStates() {
        bootstrap.resetPreferences()
        openTwoSongShell()
        var session = shell.shellPresenter.session
        var tabs = session.songTabs
        var original = tabs.selectedPage
        compare(tabs.selectedTabShowsEvents, false,
                "a seeded hidden event list restores hidden")
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return tabs.selectedPage !== original && tabs.tabCount === 2
        }, 30000), "the reloaded tab installs a fresh timeline")
        compare(tabs.selectedTabShowsEvents, false,
                "a seeded hidden event list restores hidden")
        tabs.setSelectedTabEventsVisible(true)
        original = tabs.selectedPage
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return tabs.selectedPage !== original && tabs.tabCount === 2
        }, 30000), "the visible event list survives a fresh timeline")
        compare(tabs.selectedTabShowsEvents, true,
                "a seeded visible event list restores visible")
    }

    function test_dCopyFromOneSongTabPastesIntoAnother() {
        var firstId = openTwoSongShell()
        var tabs = shell.shellPresenter.session.songTabs
        var secondId = tabs.selectedId
        var source = selectedSurface()
        verify(source && source.gridModel, "the source tab has a grid")
        compare(source.visible, true, "the selected ready source page accepts roll input")
        selectDrawnVelocityNote(source)
        var sourceSummary = source.gridModel.fetchNoteSummary()
        var selected = JSON.parse(sourceSummary).filter(function(note) { return note.selected })
        compare(selected.length, 1, "one source note is selected")
        var sourceRoll = findChild(source, "swiftRollInput")
        sourceRoll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(sourceRoll, "activeFocus", true, 3000)
        keySequence(StandardKey.Copy)
        compare(JSON.parse(bootstrap.copiedClipSummary())[2], selected[0].pitch,
                "Copy places the selected source note on the host clipboard")
        var search = findChild(shell, "songListSearch")
        verify(search, "the production chrome search is available beside both tabs")
        search.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(search, "activeFocus", true, 3000,
                   "intentional chrome focus precedes the real tab switch")

        var firstButton = findChild(shell.sceneLoader.item, "songTabSelect_" + firstId)
        verify(firstButton, "the destination tab control exists")
        mouseClick(firstButton, firstButton.width / 3, firstButton.height / 2)
        tryCompare(tabs, "selectedId", firstId, 3000)
        compare(search.activeFocus, true,
                "switching ready tabs preserves the intentional chrome text focus")
        var destination = selectedSurface()
        verify(destination && destination.gridModel, "the destination tab has a grid")
        tryCompare(findChild(shell.sceneLoader.item, "songTab_" + secondId),
                   "visible", false, 3000,
                   "the inactive ready source page stops receiving input")
        tryCompare(findChild(shell.sceneLoader.item, "songTab_" + firstId),
                   "visible", true, 3000,
                   "the destination ready page replaces the source")
        compare(search.activeFocus, true,
                "the destination stays unfocused until the user enters its editor")
        var destinationBefore = JSON.parse(destination.gridModel.fetchNoteSummary())
        var destinationIDs = destinationBefore.map(function(note) { return note.id })
        var destinationTrack = destination.gridModel.trackIndex
        var destinationRoll = findChild(destination, "swiftRollInput")
        mouseClick(destinationRoll, destinationRoll.width - 2, destinationRoll.height - 2)
        tryCompare(destinationRoll, "activeFocus", true, 3000)
        tryVerify(function() { return focusBelongsTo(findChild(shell.sceneLoader.item,
                                                      "songTab_" + firstId)) }, 3000,
                  "pointer entry transfers chrome focus to the selected ready editor")
        compare(sourceRoll.activeFocus, false, "tab input cannot remain with the inactive source")
        keySequence(StandardKey.Paste)
        verify(waitForNative(function() {
            var notes = JSON.parse(destination.gridModel.fetchNoteSummary())
            return notes.some(function(note) {
                return destinationIDs.indexOf(note.id) < 0
                    && note.pitch === selected[0].pitch && note.track === destinationTrack
                    && note.selected
            })
        }, 5000), "Paste inserts and selects the copied note in the destination track")
        var destinationAfter = JSON.parse(destination.gridModel.fetchNoteSummary())
        var inserted = destinationAfter.filter(function(note) {
            return destinationIDs.indexOf(note.id) < 0
        })
        compare(inserted.length, 1, "Paste changes only the destination by one note")
        compare(destination.gridModel.editCursorTick, inserted[0].tick + inserted[0].duration,
                "Paste advances the destination edit cursor past the inserted note")

        var secondButton = findChild(shell.sceneLoader.item, "songTabSelect_" + secondId)
        verify(secondButton, "the source tab control still exists")
        mouseClick(secondButton, secondButton.width / 3, secondButton.height / 2)
        tryCompare(tabs, "selectedId", secondId, 3000)
        compare(selectedSurface().gridModel.fetchNoteSummary(), sourceSummary,
                "cross-tab Paste leaves the source song unchanged")

        mouseClick(firstButton, firstButton.width / 3, firstButton.height / 2)
        tryCompare(tabs, "selectedId", firstId, 3000,
                   "the destination is active when the close-all walk begins")
        compare(shell.shellPresenter.session.documentDirty, true,
                "only the pasted destination has unsaved changes")
        shell.close()
        verify(waitForNative(function() {
            return tabs.pendingCloseId === firstId
        }, 5000), "the window close walk pauses at the dirty destination")
        compare(tabs.tabCount, 2, "the dirty gate cannot silently close a tab")
        compare(destination.gridModel.fetchNoteSummary(), JSON.stringify(destinationAfter),
                "the dirty gate preserves the pasted note")
        var discard = findChild(shell, "songTabDiscard")
        verify(discard && discard.visible, "the close gate exposes Discard")
        mouseClick(discard, discard.width / 2, discard.height / 2)
        verify(waitForNative(function() {
            return shell.shellPresenter.closeReady && tabs.tabCount === 0
                && shell.sceneLoader.item === null
        }, 5000), "Discard advances the remaining clean tab and detaches the scene")
        compare(tabs.pendingCloseId, -1, "the close-all gate is fully resolved")
    }
}
