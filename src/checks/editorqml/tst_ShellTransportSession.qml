import QtQuick
import QtTest

ShellTransportSupport {

    function test_explicitOpenSupersedesStartupRestoreDuringPlayback() {
        verify(bootstrap.seedStartupSong(bootstrap.projectRoot, "mus_littleroot_test"))
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production shell starts with a saved tab recipe")
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "an explicit song opens while startup restore is pending: "
                   + session.lastSaveError)
        compare(session.lastSaveError, "")
        compare(session.songTabs.selectedPage.title, "mus_route101",
                "the startup recipe never displaces the explicit open")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const bar = findChild(shell, "transportToolbar")
        const play = findChild(bar, "transport.play")
        tryCompare(play, "actionable", true, 3000)
        mouseClick(play, play.width / 2, play.height / 2)
        tryCompare(bar.presenter, "state", 3, 3000)
        wait(400)
        bar.presenter.refresh()
        compare(session.songTabs.selectedPage.title, "mus_route101")
        compare(session.songTabs.tabCount, 1, "startup does not append its saved tab")
        compare(bar.presenter.state, 3, "a late restore cannot stop explicit playback")
    }

    function test_scaleControlsFollowSelectedTab() {
        var bar = openShell()
        var root = findChild(bar, "transportScaleRoot")
        var type = findChild(bar, "transportScaleType")
        var highlight = findChild(bar, "transportScaleHighlight")
        var fold = findChild(bar, "transportScaleFold")
        verify(root && type && highlight && fold, "scale selector is mounted")
        verify(!root.enabled && !type.enabled && !highlight.enabled && !fold.enabled,
               "scale selector is unavailable before a song opens")
        bar = openSong()
        compare(root.currentIndex, 0, "new tab opens with C root")
        compare(type.currentIndex, 0, "new tab opens with Major scale")
        verify(!highlight.checked && !fold.Accessible.checked,
               "new tab opens with Highlight and Fold off")
        mouseClick(highlight, highlight.width / 2, highlight.height / 2)
        compare(bar.presenter.scaleHighlight, true, "Highlight toggle edits the selected tab")
        mouseClick(highlight, highlight.width / 2, highlight.height / 2)
        var toggledOff = !bar.presenter.scaleHighlight
        mouseClick(highlight, highlight.width / 2, highlight.height / 2)
        verify(toggledOff && bar.presenter.scaleHighlight,
               "Highlight toggles off and on from the transport control")
        mouseClick(fold, fold.width / 2, fold.height / 2)
        compare(bar.presenter.scaleFold, true, "Fold toggle edits the selected tab")
        bar.presenter.setScaleRoot(9)
        bar.presenter.setScaleType(2)
        tryCompare(root, "currentIndex", 9, 3000)
        tryCompare(type, "currentIndex", 2, 3000)
        var session = shell.shellPresenter.session
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 2 && bar.presenter.scaleRoot === 0
        }, 30000), "second tab restores independent default scale")
        compare(bar.presenter.scaleFold, false, "second tab does not inherit Fold")
        session.openSong("mus_route101")
        verify(waitForNative(function() {
            return bar.presenter.scaleRoot === 9 && bar.presenter.scaleType === 2
        }, 5000), "first tab restores its root and type")
        compare(bar.presenter.scaleHighlight, true, "first tab restores Highlight")
        tryCompare(root, "currentIndex", 9, 3000,
                   "mounted root selector follows the restored tab")
        tryCompare(type, "currentIndex", 2, 3000,
                   "mounted scale selector follows the restored tab")
        compare(highlight.checked, true, "mounted Highlight control follows the restored tab")
        compare(fold.Accessible.checked, true, "the first tab keeps its scale state after second-tab edits")
        compare(bar.presenter.scaleFold, true, "first tab restores Fold")
    }

    // Fork tabs_scale.cpp:58-157 drives root/type/Highlight/Fold across two tabs;
    // this journey reads Fold/Highlight at each point the existing journey skips.
    function test_scaleFoldHighlightPerTabTogglePaths() {
        var bar = openShell()
        var root = findChild(bar, "transportScaleRoot")
        var type = findChild(bar, "transportScaleType")
        var highlight = findChild(bar, "transportScaleHighlight")
        var fold = findChild(bar, "transportScaleFold")
        verify(root && type && highlight && fold, "toggle-path journey mounts the scale controls")
        bar = openSong()
        var session = shell.shellPresenter.session
        bar.presenter.setScaleRoot(9)
        bar.presenter.setScaleType(2)
        mouseClick(highlight, highlight.width / 2, highlight.height / 2)
        compare(bar.presenter.scaleHighlight, true, "toggle-path journey stages the first Highlight edit")
        verify(!bar.presenter.scaleFold, "first tab Fold stays off after its Highlight edit")
        mouseClick(highlight, highlight.width / 2, highlight.height / 2)
        compare(bar.presenter.scaleHighlight, false, "toggle-path journey stages the Highlight toggle off")
        verify(!bar.presenter.scaleFold, "first tab Fold stays off after its Highlight toggle")
        mouseClick(highlight, highlight.width / 2, highlight.height / 2)
        compare(bar.presenter.scaleHighlight, true, "toggle-path journey restores the first Highlight edit")
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 2 && bar.presenter.scaleRoot === 0
        }, 30000), "toggle-path journey opens the second tab with default scale")
        bar.presenter.setScaleRoot(2)
        bar.presenter.setScaleType(12)
        verify(waitForNative(function() {
            return bar.presenter.scaleRoot === 2 && bar.presenter.scaleType === 12
        }, 5000), "toggle-path journey stages the second tab root and type edits")
        mouseClick(fold, fold.width / 2, fold.height / 2)
        compare(bar.presenter.scaleFold, true, "toggle-path journey stages the second tab Fold edit")
        verify(!bar.presenter.scaleHighlight, "second tab Highlight stays off after its Fold edit")
        mouseClick(highlight, highlight.width / 2, highlight.height / 2)
        compare(bar.presenter.scaleHighlight, true, "toggle-path journey stages the second Highlight edit")
        mouseClick(highlight, highlight.width / 2, highlight.height / 2)
        compare(bar.presenter.scaleHighlight, false, "toggle-path journey stages the second Highlight toggle")
        mouseClick(highlight, highlight.width / 2, highlight.height / 2)
        compare(bar.presenter.scaleHighlight, true, "toggle-path journey restores the second Highlight edit")
        mouseClick(fold, fold.width / 2, fold.height / 2)
        verify(bar.presenter.scaleHighlight && !bar.presenter.scaleFold,
               "second tab Fold toggle clears Fold and keeps Highlight")
        mouseClick(fold, fold.width / 2, fold.height / 2)
        compare(bar.presenter.scaleFold, true, "toggle-path journey restores the second tab Fold edit")
        session.openSong("mus_route101")
        verify(waitForNative(function() {
            return bar.presenter.scaleRoot === 9 && bar.presenter.scaleType === 2
        }, 30000), "toggle-path journey reselects the first tab")
        verify(!bar.presenter.scaleFold, "first tab Fold stays off after the second tab enables Fold")
    }

    function test_rulerCommitMovesCursorOnlyInEveryTransportState() {
        var bar = openShell()
        var session = shell.shellPresenter.session
        openSong()
        var clock = findChild(bar, "transportTimeLabel")
        var play = findChild(bar, "transport.play")
        var pause = findChild(bar, "transport.pause")
        verify(waitForNative(function() { return rollSurface() !== null }, 10000),
               "the roll surface mounts for the fixture song")
        var surface = rollSurface()
        var grid = surface.gridModel
        var ruler = findChild(surface, "timelineRulerInput")
        verify(ruler !== null, "the ruler input mounts in the roll surface")
        var stoppedCursor = grid.editCursorTick
        mouseClick(ruler, ruler.width * 0.85, ruler.height * 0.5, Qt.RightButton)
        tryCompare(session, "timeSigMenuOpen", true)
        verify(waitForNative(function() {
            return findChild(surface, "quickMenuPanelRoot") !== null
        }, 5000), "the stopped ruler menu mounts before keyboard dismissal")
        var menu = findChild(surface, "quickMenuPanelRoot")
        tryCompare(menu.parent, "activeFocus", true, 3000,
                   "the stopped ruler menu owns Escape focus")
        verify(grid.editCursorTick !== stoppedCursor, "the stopped press commits the cursor")
        verify(Math.abs(session.playheadPresenter().tick) < 0.5,
               "stopped commit leaves the playhead at origin")
        bar.presenter.refresh()
        verify(clock.text.startsWith("0:00.0 / "), "stopped commit leaves the transport clock")
        keyClick(Qt.Key_Escape)
        tryCompare(session, "timeSigMenuOpen", false)
        verify(waitForNative(function() {
            return findChild(surface, "quickMenuPanelRoot") === null
        }, 3000), "the dismissed menu panel leaves the visible scene")
        grid.setEditCursorTick(0)
        verify(Math.abs(grid.editCursorTick) < 0.5,
               "resetting the stopped edit cursor keeps the next Play near the song start")
        compare(play.actionable, true, "loaded song can start playback")
        mouseClick(play, play.width / 2, play.height / 2)
        tryCompare(bar.presenter, "state", 3, 3000)
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return !clock.text.startsWith("0:00.0 / ")
        }, 5000), "playback advances the mounted clock")
        mouseClick(pause, pause.width / 2, pause.height / 2)
        tryCompare(bar.presenter, "state", 2, 3000)
        bar.presenter.refresh()
        var pausedClock = clock.text
        var pausedTick = session.playheadPresenter().tick
        mouseClick(ruler, ruler.width * 0.6, ruler.height * 0.5, Qt.RightButton)
        var targetCursor = grid.editCursorTick
        verify(targetCursor > pausedTick, "the paused ruler target is ahead of playback")
        verify(Math.abs(session.playheadPresenter().tick - pausedTick) < 0.5,
               "the paused press leaves the shared playhead at the pause point")
        tryCompare(session, "timeSigMenuOpen", true)
        verify(waitForNative(function() {
            return findChild(surface, "quickMenuPanelRoot") !== null
        }, 5000), "the paused ruler menu mounts before keyboard dismissal")
        menu = findChild(surface, "quickMenuPanelRoot")
        tryCompare(menu.parent, "activeFocus", true, 3000,
                   "the paused ruler menu owns Escape focus")
        keyClick(Qt.Key_Escape)
        tryCompare(session, "timeSigMenuOpen", false)
        verify(waitForNative(function() {
            return findChild(surface, "quickMenuPanelRoot") === null
        }, 3000), "the paused menu panel leaves the visible scene")
        bar.presenter.refresh()
        compare(clock.text, pausedClock,
                "the paused commit leaves the mounted clock at the pause point")
        compare(bar.presenter.state, 2, "ruler commit preserves the paused transport")
    }

    function test_backgroundRulerSeekCannotMoveSelectedSong() {
        var bar = openShell()
        var session = shell.shellPresenter.session
        openSong()
        verify(waitForNative(function() { return rollSurface() !== null }, 10000),
               "the first tab mounts its ruler")
        var firstSurface = rollSurface()
        var firstRuler = findChild(firstSurface, "timelineRulerInput")
        verify(firstRuler !== null, "the first tab has a ruler input")
        var firstCursor = firstSurface.gridModel.editCursorTick
        var firstId = session.songTabs.selectedId
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 2
                && session.songTabs.selectedId !== firstId
                && bar.presenter.state !== 0
        }, 30000), "the second song takes the selected workspace and audio engine")

        var play = findChild(bar, "transport.play")
        var pause = findChild(bar, "transport.pause")
        var clock = findChild(bar, "transportTimeLabel")
        mouseClick(play, play.width / 2, play.height / 2)
        tryCompare(bar.presenter, "state", 3, 3000)
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return !clock.text.startsWith("0:00.0 / ")
        }, 5000), "the selected song advances before the stale ruler event")
        mouseClick(pause, pause.width / 2, pause.height / 2)
        tryCompare(bar.presenter, "state", 2, 3000)
        bar.presenter.refresh()
        var selectedClock = clock.text
        var selectedTick = session.playheadPresenter().tick
        var oldTargetX = firstRuler.width * 0.85
        firstSurface.rulerMenu.beginSweep(oldTargetX, 0, 0)
        firstSurface.rulerMenu.endSweep(oldTargetX, 0)
        verify(firstSurface.gridModel.editCursorTick !== firstCursor,
               "the background tab actually commits its own ruler cursor")
        verify(Math.abs(session.playheadPresenter().tick - selectedTick) < 0.001,
               "a background ruler seek cannot move the selected song's shared playhead")
        bar.presenter.refresh()
        compare(clock.text, selectedClock, "the selected song clock remains at its paused position")
        compare(bar.presenter.state, 2, "a background ruler event preserves the selected transport")
    }

    function test_toolbarResumeAndSpaceRestartAtEditCursor() {
        var bar = openShell()
        var session = shell.shellPresenter.session
        openSong()
        verify(waitForNative(function() { return rollSurface() !== null }, 10000),
               "the song mounts its roll before transport input")
        var surface = rollSurface()
        var ruler = findChild(surface, "timelineRulerInput")
        var play = findChild(bar, "transport.play")
        var pause = findChild(bar, "transport.pause")
        verify(ruler && play && pause, "ruler and toolbar transport are mounted")
        var grid = surface.gridModel
        var cursorX = grid.beatWidth - grid.cameraScrollX
        verify(cursorX > 0 && cursorX < ruler.width,
               "one beat of the fixture is visible on the mounted ruler")
        surface.rulerMenu.beginSweep(cursorX, 0, 0)
        surface.rulerMenu.endSweep(cursorX, 0)
        var cursor = surface.gridModel.editCursorTick
        verify(cursor > 0, "the stopped edit cursor is away from the origin")
        verify(waitForNative(function() { return play.actionable && play.enabled }, 3000),
               "the mounted Play control becomes actionable for the loaded song")
        mouseClick(play, play.width / 2, play.height / 2)
        verify(waitForNative(function() { return bar.presenter.state === 3 }, 3000),
               "Play presents playing when its action completes")
        verify(Math.abs(session.playheadPresenter().tick - cursor) < 0.001,
               "stopped Play presents the edit-cursor target immediately")
        verify(waitForNative(function() {
            return session.playheadPresenter().tick > cursor + 8
        }, 5000), "the real playback advances beyond the edit cursor")
        verify(waitForNative(function() { return pause.actionable && pause.enabled }, 3000),
               "the mounted Pause control becomes actionable during playback")
        mouseClick(pause, pause.width / 2, pause.height / 2)
        verify(waitForNative(function() { return bar.presenter.state === 2 }, 3000),
               "Pause presents paused when its action completes")
        var paused = session.playheadPresenter().tick
        verify(waitForNative(function() { return play.actionable && play.enabled }, 3000),
               "the mounted Play control becomes actionable while paused")
        var beforeResume = session.playheadPresenter().tick
        mouseClick(play, play.width / 2, play.height / 2)
        verify(waitForNative(function() { return bar.presenter.state === 3 }, 3000),
               "toolbar Play resumes when its action completes")
        verify(waitForNative(function() {
            return session.playheadPresenter().tick > beforeResume
        }, 5000), "toolbar resume advances beyond its immediately preceding pause position")
        verify(session.playheadPresenter().tick > cursor + 8,
               "toolbar Play resumes beyond the cursor rather than restarting")
        verify(waitForNative(function() { return pause.actionable && pause.enabled }, 3000),
               "the mounted Pause control becomes actionable after resuming")
        mouseClick(pause, pause.width / 2, pause.height / 2)
        verify(waitForNative(function() { return bar.presenter.state === 2 }, 3000),
               "the resumed transport pauses")
        verify(session.playheadPresenter().tick >= paused - 1,
               "a resumed transport does not jump behind its prior pause point")
        var master = findChild(bar, "transportMasterVolume")
        verify(master !== null, "the Space route has a mounted focus target")
        master.focusInput(Qt.OtherFocusReason)
        keyClick(Qt.Key_Space)
        verify(waitForNative(function() { return bar.presenter.state === 3 }, 3000),
               "Space presents playing when its action completes")
        verify(Math.abs(session.playheadPresenter().tick - cursor) < 0.001,
               "Space restarts from the edit cursor instead of the pause point")
    }

    function test_homeHomesCursorWithoutMovingStoppedPlayhead() {
        var bar = openShell()
        var session = shell.shellPresenter.session
        openSong()
        verify(waitForNative(function() { return rollSurface() !== null }, 10000),
               "the roll surface mounts for the Home check")
        var home = rollSurface()
        var grid = home.gridModel
        var rewind = findChild(bar, "transport.go-to-start")
        var play = findChild(bar, "transport.play")
        verify(rewind && play, "rewind and play are mounted")
        grid.setEditCursorTick(grid.ticksPerBeat * 4)
        var cursor = grid.editCursorTick
        verify(cursor > 0, "the stopped edit cursor starts away from the origin")
        mouseClick(rewind, rewind.width / 2, rewind.height / 2)
        compare(grid.editCursorTick, 0, "Home homes the stopped edit cursor")
        verify(Math.abs(session.playheadPresenter().tick) < 0.5,
               "Home leaves the stopped playhead at the origin")
        mouseClick(play, play.width / 2, play.height / 2)
        tryCompare(bar.presenter, "state", 3, 3000)
        verify(session.playheadPresenter().tick < cursor,
               "Play after Home starts at the homed origin rather than the old cursor")
        var first = session.playheadPresenter().tick
        verify(waitForNative(function() {
            return session.playheadPresenter().tick > first + 8
        }, 5000), "playback advances from the homed origin")
    }

    function test_cancelledSweepAndHiddenMixDoNotPublishIntoSelectedWorkspace() {
        var bar = openShell()
        var session = shell.shellPresenter.session
        openSong()
        verify(waitForNative(function() { return rollSurface() !== null }, 10000),
               "the first tab mounts its roll")
        var first = rollSurface()
        var ruler = findChild(first, "timelineRulerInput")
        var cursor = first.gridModel.editCursorTick
        first.rulerMenu.beginSweep(ruler.width * 0.4, 0, 0)
        session.cancelGridInput(0)
        first.rulerMenu.endSweep(ruler.width * 0.4, 0)
        compare(first.gridModel.editCursorTick, cursor,
                "a late ruler release after input cancellation cannot commit its seek")
        first.rulerMenu.beginSweep(ruler.width * 0.4, 0, 0)
        first.rulerMenu.endSweep(ruler.width * 0.4, 0)
        verify(first.gridModel.editCursorTick !== cursor,
               "an uncancelled sweep still commits its ruler cursor")
        var firstId = session.songTabs.selectedId
        var firstTab = session.songTabs.selectedPage
        var firstHeaders = findChild(first, "timelineTrackHeaderRows")
        verify(firstHeaders && firstHeaders.count > 0, "the first tab has track headers")
        var firstTrack = firstHeaders.itemAt(0)
        verify(firstTrack && !firstTrack.isAddTrack, "the first tab has a playable track")
        var muteRect = firstTab.trackHeadersPresenter().muteButtonRect
        mouseClick(firstTrack, muteRect.x + muteRect.width / 2,
                   muteRect.y + muteRect.height / 2)
        tryCompare(firstTrack, "muteChecked", true)
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 2 && session.songTabs.selectedId !== firstId
                && bar.presenter.state !== 0 && rollSurface() !== null
        }, 30000), "the second tab binds its own audio and editor")
        var secondId = session.songTabs.selectedId
        var second = rollSurface()
        var secondHeaders = findChild(second, "timelineTrackHeaderRows")
        verify(secondHeaders && secondHeaders.count > 0, "the second tab has track headers")
        var secondTrack = secondHeaders.itemAt(0)
        verify(secondTrack && !secondTrack.isAddTrack, "the second tab has a playable track")
        compare(secondTrack.muteChecked, false, "the second tab does not inherit first-tab mute")
        firstTab.trackHeadersPresenter().activateSolo(0)
        tryCompare(firstTrack, "soloChecked", true)
        compare(secondTrack.soloChecked, false,
                "hidden solo publication cannot change the selected tab")
        var selectedTick = session.playheadPresenter().tick
        first.rulerMenu.beginSweep(ruler.width * 0.8, 0, 0)
        firstTab.cancelGridInput(0)
        first.rulerMenu.endSweep(ruler.width * 0.8, 0)
        verify(Math.abs(session.playheadPresenter().tick - selectedTick) < 0.001,
               "a late background ruler release cannot seek selected audio")
        session.songTabs.selectTab(firstId)
        tryCompare(session.songTabs, "selectedId", firstId)
        verify(waitForNative(function() {
            return firstTrack.muteChecked && firstTrack.soloChecked
        }, 3000), "reactivation restores the first tab's mute and solo state")
        session.songTabs.selectTab(secondId)
        tryCompare(secondTrack, "muteChecked", false)
        compare(secondTrack.soloChecked, false,
                "returning to the second tab does not retain first-tab masks")
        session.songTabs.selectTab(firstId)
        tryCompare(session.songTabs, "selectedId", firstId)
        var headersModel = firstTab.trackHeadersPresenter()
        var headerInput = findChild(first, "timelineTrackHeadersInput")
        verify(headerInput !== null, "the selected tab mounts its header input")
        verify(waitForNative(function() {
            return rollSurface() === first && headerInput.visible && headerInput.enabled
        }, 3000), "the first tab's mounted header is active again")
        var rowY = Math.max(1, headersModel.rowHeight / 2)
        var beforeCount = firstHeaders.count
        mouseClick(headerInput, headerInput.width * 0.5, rowY, Qt.RightButton)
        tryCompare(headersModel, "menuOpen", true)
        verify(waitForNative(function() {
            return findChild(first, "quickMenuPanelRoot") !== null
        }, 3000), "the selected header menu mounts")
        var menu = findChild(first, "quickMenuPanelRoot")
        tryVerify(function() { return menuActionRow(menu, 4) !== null }, 3000)
        var duplicate = menuActionRow(menu, 4)
        compare(duplicate.itemData.enabled, true)
        mouseClick(duplicate, duplicate.width / 2, duplicate.height / 2)
        tryCompare(headersModel, "menuOpen", false)
        tryCompare(firstHeaders, "count", beforeCount + 1)
        verify(waitForNative(function() {
            return findChild(first, "quickMenuPanelRoot") === null
        }, 3000), "the duplicate menu leaves the mounted scene")
        mouseClick(headerInput, headerInput.width * 0.5, rowY, Qt.RightButton)
        tryCompare(headersModel, "menuOpen", true)
        verify(waitForNative(function() {
            return findChild(first, "quickMenuPanelRoot") !== null
        }, 3000), "the removal menu mounts")
        menu = findChild(first, "quickMenuPanelRoot")
        tryVerify(function() { return menuActionRow(menu, 5) !== null }, 3000)
        var remove = menuActionRow(menu, 5)
        compare(remove.itemData.enabled, true)
        mouseClick(remove, remove.width / 2, remove.height / 2)
        tryCompare(headersModel, "menuOpen", false)
        tryCompare(firstHeaders, "count", beforeCount)
        var survivor = firstHeaders.itemAt(0)
        verify(survivor && !survivor.isAddTrack, "a playable track survives removal")
        compare(survivor.muteChecked, false,
                "deleting the muted track drops its mask instead of muting its successor")
        compare(survivor.soloChecked, false,
                "deleting the solo track drops its mask instead of soloing its successor")
    }
    // Fork selftest_timeline.cpp:146 drives Stop on an already-stopped
    // transport before the stopped audition; the stopped audition itself rides S007.
    function test_alreadyStoppedStopKeepsTransportStopped() {
        var bar = openShell()
        bar = openSong()
        var stop = findChild(bar, "transport.stop")
        verify(stop !== null, "the stopped transport mounts its real Stop control")
        tryCompare(bar.presenter, "state", 1, 3000,
                   "the freshly loaded song rests Stopped before any playback")
        mouseClick(stop, stop.width / 2, stop.height / 2)
        verify(waitForNative(function() {
            return !stop.actionable && bar.presenter.state === 1
        }, 3000), "Stop on the stopped transport is refused and it stays Stopped")
    }

    function test_liveEditAuditionAndFinalCloseDuringPlayback() {
        var bar = openShell()
        var session = shell.shellPresenter.session
        openSong()
        verify(waitForNative(function() { return rollSurface() !== null }, 10000),
               "the live-edit song mounts its roll before playing")
        var surface = rollSurface()
        var grid = surface.gridModel
        var roll = findChild(surface, "swiftRollInput")
        var gutter = findChild(surface, "timelineQuickRollGutter")
        var play = findChild(bar, "transport.play")
        var stop = findChild(bar, "transport.stop")
        verify(roll && gutter && play && stop, "real roll, keyboard and toolbar inputs mount")
        var initial = grid.fetchNoteSummary()
        var tabId = session.songTabs.selectedId
        grid.setCameraVScroll((127 - 61 + 0.5) * grid.rowHeight - roll.height / 2)
        var pitch = 61
        var tick = grid.snapTicks * 2
        var notes = JSON.parse(initial)
        while (notes.some(function(n) {
            return n.track === grid.trackIndex && n.pitch === pitch
        }))
            ++pitch
        var x = tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
        var y = (127 - pitch + 0.5) * grid.rowHeight - grid.cameraScrollY
        verify(x > 1 && x + grid.beatWidth + grid.snapTicks * grid.beatWidth
               / grid.ticksPerBeat < roll.width - 1 && y > grid.rowHeight
               && y < roll.height - 1, "a fresh note cell is visible in the roll")
        mouseClick(play, play.width / 2, play.height / 2)
        tryCompare(bar.presenter, "state", 3, 3000)
        mousePress(roll, x, y, Qt.LeftButton)
        mouseMove(roll, x + grid.beatWidth, y, -1, Qt.LeftButton)
        mouseRelease(roll, x + grid.beatWidth, y, Qt.LeftButton)
        var added = null
        verify(waitForNative(function() {
            added = JSON.parse(grid.fetchNoteSummary()).find(function(n) {
                return n.track === grid.trackIndex && !notes.some(function(old) {
                    return old.id === n.id
                })
            })
            return added !== undefined
        }, 3000), "a real roll draw commits a new note while the selected song plays")
        compare(session.documentDirty, true, "the mounted live note edit dirties its selected tab")
        compare(bar.presenter.state, 3, "mounted roll draw cannot stop playback")
        var item = findChild(surface, "gridNote_" + added.id)
        verify(item && item.visible, "the newly drawn note paints a movable face")
        var pxPerTick = grid.beatWidth / grid.ticksPerBeat
        var centerX = item.mapToItem(roll, item.width / 2, item.height / 2).x
        var centerY = (127 - added.pitch + 0.5) * grid.rowHeight - grid.cameraScrollY
        var dx = grid.snapTicks * pxPerTick
        verify(centerX > 1 && centerX + dx < roll.width - 1 && centerY > grid.rowHeight
               && centerY < roll.height - 1, "the new note has a real drag target")
        mouseMove(roll, centerX, centerY)
        mousePress(roll, centerX, centerY, Qt.LeftButton)
        mouseMove(roll, centerX + dx, centerY - grid.rowHeight, -1, Qt.LeftButton)
        mouseRelease(roll, centerX + dx, centerY - grid.rowHeight, Qt.LeftButton)
        verify(waitForNative(function() {
            return JSON.parse(grid.fetchNoteSummary()).some(function(n) {
                return n.id === added.id && n.pitch === added.pitch + 1
                    && n.tick === added.tick + grid.snapTicks
            })
        }, 3000), "real roll drag moves the playing note by one snap and one key")
        compare(bar.presenter.state, 3, "mounted note movement leaves playback Playing")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() {
            return JSON.parse(grid.fetchNoteSummary()).some(function(n) {
                return n.id === added.id && n.tick === added.tick
                    && n.pitch === added.pitch
            })
        }, 3000), "first mounted Undo restores the newly drawn note's position")
        keySequence(StandardKey.Undo)
        verify(waitForNative(function() { return grid.fetchNoteSummary() === initial }, 5000),
               "mounted Undo restores the entire pre-edit roll note state")
        compare(session.documentDirty, false, "mounted Undo restores the clean selected song")
        compare(bar.presenter.state, 3, "mounted Undo preserves the playing transport")
        var beforeAudition = session.playheadPresenter().tick
        var gutterKey = 127 - Math.floor((grid.cameraScrollY + gutter.height / 2)
                                         / grid.rowHeight)
        mousePress(gutter, gutter.width / 2, gutter.height / 2, Qt.LeftButton)
        compare(grid.hoverKey, gutterKey, "mounted keyboard press projects the hovered pitch")
        verify(waitForNative(function() {
            return session.playheadPresenter().tick > beforeAudition
        }, 5000), "keyboard gutter press leaves real song playback advancing")
        mouseRelease(gutter, gutter.width / 2, gutter.height / 2, Qt.LeftButton)
        compare(bar.presenter.state, 3, "releasing the keyboard press leaves playback Playing")
        mouseClick(stop, stop.width / 2, stop.height / 2)
        tryCompare(bar.presenter, "state", 1, 3000)
        mousePress(gutter, gutter.width / 2, gutter.height / 2, Qt.LeftButton)
        mouseRelease(gutter, gutter.width / 2, gutter.height / 2, Qt.LeftButton)
        compare(bar.presenter.state, 1, "keyboard press while stopped leaves transport Stopped")
        var close = findChild(shell.sceneLoader.item, "songTabClose_" + tabId)
        verify(close && close.visible, "the final tab exposes its mounted close button")
        mouseClick(close, close.width / 2, close.height / 2)
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return session.songTabs.tabCount === 0 && bar.presenter.state === 0
        }, 5000), "mounted final-tab close retires the stopped song and audio presentation")
    }

}
