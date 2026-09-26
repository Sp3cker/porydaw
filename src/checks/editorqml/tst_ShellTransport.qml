import QtQuick
import QtCore
import QtTest
import "GatedVisualsHelpers.js" as Helpers
import "NativeWait.js" as NativeWait
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

TestCase {
    id: testCase
    name: "ShellTransport"
    when: windowShown
    width: 1100
    height: 700
    visible: true

    property var shell: null
    property var settings: null
    ShellQmlBootstrap { id: bootstrap }
    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        settings = settingsComponent.createObject(testCase)
        verify(settings !== null, "genuine QtCore.Settings is available")
    }
    function cleanupTestCase() {
        if (settings) {
            settings.destroy()
            settings = null
            wait(0)
        }
        verify(bootstrap.clearSettings(), "transport settings stay isolated from user preferences")
    }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 700; visible: true } }
    Component { id: settingsComponent; Settings {} }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openShell() {
        // Every explicit-open test starts without a stale startup recipe.
        settings.setValue("lastProjectDir", "")
        settings.sync()
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production ShellWindow instantiates")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var transport = findChild(shell, "transportToolbar")
        verify(transport !== null, "the mounted header owns the production transport")
        return transport
    }

    function openSong() {
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the song open reaches the actual project backend")
        verify(session.songOpen, "the fixture song loads: " + session.lastSaveError)
        var transport = findChild(shell, "transportToolbar")
        verify(waitForNative(function() { return transport.presenter.state !== 0 }, 5000),
               "transport observes the loaded audio timeline")
        return transport
    }

    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "close-all reaches the dirty-song gate or completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 5000),
                   "close completes after discarding the fixture edits")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function test_transportButtonMenuCommandParity() {
        var bar = openShell()
        const authority = shell.shellPresenter
        const ids = ["transport.go_to_start", "transport.play", "transport.pause",
                     "transport.stop", "transport.loop", "transport.follow_playhead",
                     "transport.resonance"]
        const names = ["transport.go-to-start", "transport.play", "transport.pause",
                       "transport.stop", "transport.loop", "transport.follow-playhead",
                       "transport.resonance"]
        function button(index) { return findChild(bar, names[index]) }
        function menu(index) { return findChild(shell, "shellAction_" + ids[index]) }
        function parity(index, expected) {
            const control = button(index)
            verify(control !== null, ids[index] + " button is mounted")
            compare(authority.actionEnabled(ids[index]), expected,
                    ids[index] + " reports its expected availability")
            tryCompare(control, "actionable", expected, 3000,
                       ids[index] + " button matches command authority")
            tryCompare(control, "enabled", expected, 3000,
                       ids[index] + " rendered enabled state matches authority")
            if (index < 6) {
                const item = menu(index)
                verify(item !== null, ids[index] + " menu item is mounted")
                tryCompare(item, "enabled", expected, 3000,
                           ids[index] + " menu availability matches the button")
            }
        }
        for (let index = 0; index < ids.length; ++index)
            parity(index, false)

        bar = openSong()
        const transport = bar.presenter
        const clock = findChild(bar, "transportTimeLabel")
        parity(0, true)
        parity(1, true)
        parity(2, false)
        parity(3, false)
        parity(4, true)
        parity(5, true)
        const playPause = findChild(shell, "shellAction_transport.play_pause")
        verify(playPause !== null, "Play/Pause menu item is mounted")
        verify(authority.actionEnabled("transport.play_pause"),
               "Play/Pause command authority enables the window shortcut")
        compare(playPause.enabled, authority.actionEnabled("transport.play_pause"),
                "Play/Pause menu and shortcut share enabled authority")
        parity(6, true)

        mouseClick(button(1), button(1).width / 2, button(1).height / 2)
        tryCompare(transport, "state", 3, 3000,
                   "Play button starts real audio playback")
        parity(1, false)
        parity(2, true)
        parity(3, true)
        menu(2).triggered()
        tryCompare(transport, "state", 2, 3000,
                   "Pause menu pauses the same audio transport")
        menu(1).triggered()
        tryCompare(transport, "state", 3, 3000,
                   "Play menu resumes the same audio transport")
        mouseClick(button(2), button(2).width / 2, button(2).height / 2)
        tryCompare(transport, "state", 2, 3000,
                   "Pause button produces the same paused audio state")
        mouseClick(button(3), button(3).width / 2, button(3).height / 2)
        tryCompare(transport, "state", 1, 3000,
                   "Stop button stops and rewinds audio")
        verify(waitForNative(function() {
            transport.refresh()
            return clock.text.startsWith("0:00.0 / ")
        }, 3000), "Stop button rewinds the real audio playhead")
        menu(1).triggered()
        tryCompare(transport, "state", 3, 3000)
        menu(3).triggered()
        tryCompare(transport, "state", 1, 3000,
                   "Stop menu produces the same stopped audio state")
        verify(waitForNative(function() {
            transport.refresh()
            return clock.text.startsWith("0:00.0 / ")
        }, 3000), "Stop menu rewinds the real audio playhead")
        parity(3, false)

        menu(1).triggered()
        tryCompare(transport, "state", 3, 3000)
        verify(waitForNative(function() {
            transport.refresh()
            return !clock.text.startsWith("0:00.0 / ")
        }, 3000), "playback advances before comparing the seek routes")
        mouseClick(button(0), button(0).width / 2, button(0).height / 2)
        verify(waitForNative(function() {
            transport.refresh()
            return clock.text.startsWith("0:00.0 / ")
        }, 3000), "Go to Start button seeks the actual audio playhead")
        verify(waitForNative(function() {
            transport.refresh()
            return !clock.text.startsWith("0:00.0 / ")
        }, 3000), "audio advances again before the menu seek")
        menu(0).triggered()
        verify(waitForNative(function() {
            transport.refresh()
            return clock.text.startsWith("0:00.0 / ")
        }, 3000), "Go to Start menu seeks the same audio playhead")
        menu(3).triggered()
        tryCompare(transport, "state", 1, 3000)

        const loopBefore = transport.loopEnabled
        mouseClick(button(4), button(4).width / 2, button(4).height / 2)
        compare(transport.loopEnabled, !loopBefore,
                "Loop button changes native audio loop state")
        tryCompare(menu(4), "checked", !loopBefore, 3000,
                   "Loop menu mirrors the button's checked state")
        menu(4).triggered()
        compare(transport.loopEnabled, loopBefore,
                "Loop menu changes the same audio loop state")
        tryCompare(button(4), "checked", loopBefore, 3000,
                   "Loop button mirrors the menu's checked state")

        const followBefore = transport.followPlayhead
        mouseClick(button(5), button(5).width / 2, button(5).height / 2)
        compare(transport.followPlayhead, !followBefore,
                "Follow button changes the playhead policy")
        tryCompare(menu(5), "checked", !followBefore, 3000,
                   "Follow menu mirrors the button's checked state")
        menu(5).triggered()
        compare(transport.followPlayhead, followBefore,
                "Follow menu restores the same playhead policy")
        tryCompare(button(5), "checked", followBefore, 3000,
                   "Follow button mirrors the menu's checked state")

        const resonanceBefore = transport.resonanceSuppression
        mouseClick(button(6), button(6).width / 2, button(6).height / 2)
        compare(transport.resonanceSuppression, !resonanceBefore,
                "resonance button updates native audio through command authority")
        authority.activate("transport.resonance")
        compare(transport.resonanceSuppression, resonanceBefore,
                "the authority restores the same native resonance state")
        tryCompare(button(6), "checked", resonanceBefore, 3000,
                   "resonance button mirrors the authority's checked state")
        compare(authority.session.documentDirty, false,
                "transport parity actions never dirty the document")
    }

    function test_transportControlTransitionsAndSettings() {
        var bar = openShell()
        var clock = findChild(bar, "transportTimeLabel")
        var play = findChild(bar, "transport.play")
        var pause = findChild(bar, "transport.pause")
        var stop = findChild(bar, "transport.stop")
        var rewind = findChild(bar, "transport.go-to-start")
        compare(clock.text, "0:00.0 / 0:00.0", "unloaded clock is zeroed")
        compare(play.actionable, false, "unloaded song cannot play")
        compare(rewind.actionable, false, "unloaded song cannot seek")

        bar = openSong()
        var sceneTop = shell.sceneLoader.mapToItem(shell.contentItem, 0, 0).y
        var toolbarBottom = bar.mapToItem(shell.contentItem, 0, bar.height).y
        verify(sceneTop >= toolbarBottom, "editor viewport starts below the top transport bar")
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return clock.text !== "0:00.0 / 0:00.0"
        }, 5000), "loaded song length reaches the clock after audio binding")
        verify(clock.text.startsWith("0:00.0 / "), "loaded clock includes current/total time")
        compare(bar.presenter.measureText, "1:1",
                "the accessible opening measure and beat are one-based")
        compare(play.actionable, true, "loaded song can start playback")
        mouseClick(play, play.width / 2, play.height / 2)
        tryCompare(bar.presenter, "state", 3, 3000)
        tryCompare(play, "actionable", false, 3000,
                   "playing disables duplicate Play")
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return !clock.text.startsWith("0:00.0 / ")
        }, 3000), "the mounted clock follows the real audio playhead")
        compare(pause.actionable, true, "Pause becomes available during playback")
        mouseClick(pause, pause.width / 2, pause.height / 2)
        tryCompare(bar.presenter, "state", 2, 3000)
        mouseClick(stop, stop.width / 2, stop.height / 2)
        tryCompare(bar.presenter, "state", 1, 3000)
        mouseClick(rewind, rewind.width / 2, rewind.height / 2)
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return clock.text.startsWith("0:00.0 / ")
        }, 3000), "rewind seeks the real audio playhead")

        var loop = findChild(bar, "transport.loop")
        var beforeLoop = bar.presenter.loopEnabled
        mouseClick(loop, loop.width / 2, loop.height / 2)
        compare(bar.presenter.loopEnabled, !beforeLoop, "loop switch reaches audio engine")
        var follow = findChild(bar, "transport.follow-playhead")
        var beforeFollow = bar.presenter.followPlayhead
        mouseClick(follow, follow.width / 2, follow.height / 2)
        compare(bar.presenter.followPlayhead, !beforeFollow, "follow switch updates playhead policy")
        var resonance = findChild(bar, "transport.resonance")
        compare(bar.presenter.outputVolume, 100, "the application output defaults to 100 percent")
        compare(shell.shellPresenter.session.documentDirty, false,
                "the song begins clean before app-level volume changes")
        var beforeResonance = bar.presenter.resonanceSuppression
        mouseClick(resonance, resonance.width / 2, resonance.height / 2)
        compare(bar.presenter.resonanceSuppression, !beforeResonance,
                "resonance switch reaches native audio")

        var output = findChild(bar, "transportOutputVolume")
        verify(output !== null && output.visible, "application volume dial is mounted")
        compare(output.value, 100, "the mounted dial displays the default output volume")
        mouseWheel(output, output.width / 2, output.height / 2, 0, -120)
        tryCompare(bar.presenter, "outputVolume", 90, 3000)
        compare(shell.shellPresenter.session.documentDirty, false,
                "changing output volume never dirties the song")
        bar.presenter.setOutputVolume(50)
        tryCompare(output, "value", 50, 1000)
        mouseClick(output, output.width / 2, output.height / 2)
        compare(bar.presenter.outputVolume, 50, "dial tap does not change its value")
        mousePress(output, output.width / 2, output.height / 2, Qt.LeftButton)
        mouseMove(output, output.width / 2, output.height / 2 + 11, -1, Qt.LeftButton)
        mouseRelease(output, output.width / 2, output.height / 2 + 11, Qt.LeftButton)
        verify(bar.presenter.outputVolume > 50, "dial drag down increases output volume")
        bar.presenter.setOutputVolume(50)
        tryCompare(output, "value", 50, 1000)
        mousePress(output, output.width / 2, output.height / 2, Qt.LeftButton)
        mouseMove(output, output.width / 2, output.height / 2 - 11, -1, Qt.LeftButton)
        mouseRelease(output, output.width / 2, output.height / 2 - 11, Qt.LeftButton)
        verify(bar.presenter.outputVolume < 50, "dial drag up decreases output volume")
        compare(shell.shellPresenter.session.documentDirty, false,
                "dial drags do not commit song settings")

        var master = findChild(bar, "transportMasterVolume")
        verify(master !== null, "song master volume is mounted")
        master.focusInput(Qt.OtherFocusReason)
        master.selectAll()
        keyClick(Qt.Key_8)
        keyClick(Qt.Key_7)
        keyClick(Qt.Key_Return)
        tryCompare(bar.presenter, "masterVolume", 87, 3000)
        compare(shell.shellPresenter.session.documentDirty, true,
                "song master volume does dirty the document")
        master.focusInput(Qt.OtherFocusReason)
        keyClick(Qt.Key_Space)
        tryCompare(bar.presenter, "state", 3, 3000,
                   "Space still starts playback with the volume field focused")
        compare(master.value, 87, "Space does not insert into the numeric field")
        keyClick(Qt.Key_Space)
        tryCompare(bar.presenter, "state", 2, 3000,
                   "the same Space shortcut pauses playback")
        var outputAcrossTabs = bar.presenter.outputVolume
        var session = shell.shellPresenter.session
        session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return session.songTabs.tabCount === 2 || session.lastSaveError.length > 0
        }, 30000), "second song opens in its own tab")
        verify(session.songTabs.tabCount === 2, "both tabs are mounted")
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return bar.presenter.masterVolume !== 87
        }, 5000), "song master volume switches with the selected tab")
        compare(bar.presenter.outputVolume, outputAcrossTabs,
                "application output volume survives tab selection")
        session.openSong("mus_route101")
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return bar.presenter.masterVolume === 87
        }, 5000), "first song retains its edited master volume")
        tryCompare(master, "value", 87, 3000,
                   "the mounted master-volume field restores the edited song value")

        var startingTempo = bar.presenter.tempo
        var midX = clock.width / 2
        var midY = clock.height / 2
        mousePress(clock, midX, midY, Qt.LeftButton)
        mouseMove(clock, midX, midY - 20, -1, Qt.LeftButton)
        mouseRelease(clock, midX, midY - 20, Qt.LeftButton)
        verify(waitForNative(function() {
            return bar.presenter.tempo > startingTempo
        }, 3000), "time label's upward scrub commits a faster song tempo")
        cleanup()
        bar = openShell()
        compare(bar.presenter.outputVolume, outputAcrossTabs,
                "application output preference survives a fresh shell session")
    }

    function test_outputVolumeSurvivesShellRelaunch() {
        var bar = openShell()
        var output = findChild(bar, "transportOutputVolume")
        verify(output !== null && output.visible, "application volume dial is mounted")
        // Seed the preference through the dial's own commit signal — the same
        // valueCommitted path wheel/keys use (input plumbing is covered by the
        // transitions test); this test's contract is the Settings round-trip.
        output.valueCommitted(87)
        tryCompare(bar.presenter, "outputVolume", 87, 3000)
        cleanup()
        bar = openShell()
        // Capture before restoring so a mismatch still writes back the default.
        var restored = bar.presenter.outputVolume
        output = findChild(bar, "transportOutputVolume")
        output.valueCommitted(100)
        tryCompare(bar.presenter, "outputVolume", 100, 3000)
        compare(restored, 87,
                "application output preference survives a fresh shell session")
    }

    function test_explicitOpenSupersedesStartupRestoreDuringPlayback() {
        settings.setValue("lastProjectDir", bootstrap.projectRoot)
        settings.setValue("lastOpenSongs", ["mus_littleroot_test"])
        settings.setValue("lastSongLabel", "mus_littleroot_test")
        settings.sync()
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
        mouseClick(highlight, highlight.width / 2, highlight.height / 2)
        compare(bar.presenter.scaleHighlight, true, "Highlight toggle edits the selected tab")
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
        compare(bar.presenter.scaleFold, true, "first tab restores Fold")
    }

    function test_visualReferenceProfiles_data() {
        return [ { tag: "font12", fontPx: 12 }, { tag: "font16", fontPx: 16 } ]
    }

    function test_visualReferenceProfiles(data) {
        var bar = openShell()
        bar = openSong()
        bar.baseFontPx = data.fontPx
        var actionRegions = ["transport.go-to-start", "transport.play", "transport.pause",
                             "transport.stop", "transport.loop", "transport.follow-playhead",
                             "transport.resonance", "transportScaleRoot", "transportScaleType",
                             "transportScaleHighlight", "transportScaleFold"]
        wait(50)
        for (var dpr = 1; dpr <= 2; ++dpr) {
            var baseline = JSON.parse(bootstrap.transportReferenceJson(dpr, data.fontPx))
            compare(bar.width, baseline.image.width, "transport reference width")
            compare(bar.height, baseline.image.height, "transport reference height")
            for (var i = 0; i < baseline.regions.length; ++i) {
                var region = baseline.regions[i]
                if (region.name !== "transportTimeLabel"
                        && region.name !== "transportMasterVolume"
                        && region.name !== "transportMasterVolumeCaption"
                        && region.name !== "transportOutputVolume"
                        && region.name !== "transportOutputVolumeCaption"
                        && region.name !== "transportVolumeSpacer"
                        && actionRegions.indexOf(region.name) < 0)
                    continue
                var item = findChild(bar, region.name)
                verify(item !== null, region.name + " exists in the mounted transport")
                compare(item.visible, true, region.name + " matches baseline visibility")
                var origin = item.mapToItem(bar, 0, 0)
                verify(Math.abs(origin.x - region.x) <= 8,
                       region.name + " x differs from " + baseline.profile
                       + ": " + origin.x + " vs " + region.x)
                verify(Math.abs(origin.y - region.y) <= 4,
                       region.name + " y differs from " + baseline.profile
                       + ": " + origin.y + " vs " + region.y)
                verify(Math.abs(item.width - region.w) <= 6,
                       region.name + " width differs from " + baseline.profile
                       + ": " + item.width + " vs " + region.w)
            }
        }
        var captured = false
        verify(bar.grabToImage(function(result) {
            captured = result.saveToFile(bootstrap.transportCapturePath(data.fontPx))
        }), "transport capture starts")
        tryVerify(function() { return captured }, 3000, "the mounted pane screenshot is saved")
    }

    function glyphRendersInk(bar, item, expectedHex) {
        waitForRendering(bar)
        var image = grabImage(bar)
        verify(image.width > 0 && image.height > 0,
               "the transport bar renders a frame for " + item.objectName)
        var dpr = image.width / bar.width
        var origin = item.mapToItem(bar, 0, 0)
        var expected = Helpers.channels(expectedHex)
        var x0 = Math.max(0, Math.floor(origin.x * dpr))
        var y0 = Math.max(0, Math.floor(origin.y * dpr))
        var x1 = Math.min(image.width - 1,
                          Math.floor((origin.x + item.width) * dpr))
        var y1 = Math.min(image.height - 1,
                          Math.floor((origin.y + item.height) * dpr))
        for (var y = y0; y <= y1; ++y)
            for (var x = x0; x <= x1; ++x)
                if (Helpers.colorsNear(
                        [image.red(x, y), image.green(x, y), image.blue(x, y)],
                        expected, 40))
                    return true
        return false
    }

    function test_transportGlyphTintMatchesEnabledState() {
        var bar = openShell()
        openSong()
        var play = findChild(bar, "transport.play")
        var pause = findChild(bar, "transport.pause")
        verify(play !== null, "the play button is mounted")
        verify(pause !== null, "the pause button is mounted")
        tryCompare(play, "actionable", true, 3000)
        verify(!pause.actionable, "pause stays disabled while stopped")
        verify(glyphRendersInk(bar, play, bar.colors.buttonText),
               "the enabled play glyph renders in buttonText ink")
        verify(glyphRendersInk(bar, pause, bar.colors.disabledText),
               "the disabled pause glyph renders in disabledText ink")
    }

    function rollSurface() {
        if (!shell || !shell.sceneLoader.item)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function menuActionRow(menu, actionId) {
        for (var index = 0; index < menu.rowCount; ++index) {
            var row = menu.rowItem(index)
            if (row && row.itemData.actionId === actionId)
                return row
        }
        return null
    }

    function test_rulerSeekPresentsTargetWhilePausedAndGuardsWhileStopped() {
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
               "stopped seek leaves the playhead at origin")
        bar.presenter.refresh()
        verify(clock.text.startsWith("0:00.0 / "), "stopped seek leaves the transport clock")
        keyClick(Qt.Key_Escape)
        tryCompare(session, "timeSigMenuOpen", false)
        verify(waitForNative(function() {
            return findChild(surface, "quickMenuPanelRoot") === null
        }, 3000), "the dismissed menu panel leaves the visible scene")
        surface.rulerMenu.beginSweep(0, 0)
        surface.rulerMenu.endSweep(0)
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
        verify(Math.abs(session.playheadPresenter().tick - targetCursor) < 0.001,
               "the paused press immediately presents the exact target on the shared playhead")
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
        verify(waitForNative(function() {
            bar.presenter.refresh()
            return clock.text !== pausedClock
                && Math.round(session.playheadPresenter().tick / grid.ticksPerBeat)
                    === Math.round(targetCursor / grid.ticksPerBeat)
        }, 3000), "paused audio seek updates the mounted clock and lands in the target beat")
        compare(bar.presenter.state, 2, "ruler seek preserves the paused transport")
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
        firstSurface.rulerMenu.beginSweep(oldTargetX, 0)
        firstSurface.rulerMenu.endSweep(oldTargetX)
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
        surface.rulerMenu.beginSweep(cursorX, 0)
        surface.rulerMenu.endSweep(cursorX)
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
        mouseClick(play, play.width / 2, play.height / 2)
        verify(waitForNative(function() { return bar.presenter.state === 3 }, 3000),
               "toolbar Play resumes when its action completes")
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

    function test_cancelledSweepAndHiddenMixDoNotPublishIntoSelectedWorkspace() {
        var bar = openShell()
        var session = shell.shellPresenter.session
        openSong()
        verify(waitForNative(function() { return rollSurface() !== null }, 10000),
               "the first tab mounts its roll")
        var first = rollSurface()
        var ruler = findChild(first, "timelineRulerInput")
        var cursor = first.gridModel.editCursorTick
        first.rulerMenu.beginSweep(ruler.width * 0.4, 0)
        session.cancelGridInput(0)
        first.rulerMenu.endSweep(ruler.width * 0.4)
        compare(first.gridModel.editCursorTick, cursor,
                "a late ruler release after input cancellation cannot commit its seek")
        first.rulerMenu.beginSweep(ruler.width * 0.4, 0)
        first.rulerMenu.endSweep(ruler.width * 0.4)
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
        first.rulerMenu.beginSweep(ruler.width * 0.8, 0)
        firstTab.cancelGridInput(0)
        first.rulerMenu.endSweep(ruler.width * 0.8)
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
}
