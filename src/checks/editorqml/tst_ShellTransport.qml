import QtQuick
import QtCore
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import "../../ui/shell"

TestCase {
    name: "ShellTransport"
    when: windowShown
    width: 1100
    height: 700
    visible: true

    property var shell: null
    ShellQmlBootstrap { id: bootstrap }
    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
    }
    function cleanupTestCase() {
        verify(bootstrap.clearSettings(), "transport settings stay isolated from user preferences")
    }
    Component { id: shellComponent; ShellWindow { width: 1100; height: 700; visible: true } }

    function waitForNative(predicate, timeoutMs) {
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function openShell() {
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

    function test_visualReferenceProfiles_data() {
        return [ { tag: "font12", fontPx: 12 }, { tag: "font16", fontPx: 16 } ]
    }

    function test_visualReferenceProfiles(data) {
        var bar = openShell()
        bar = openSong()
        bar.baseFontPx = data.fontPx
        var actionRegions = ["transport.go-to-start", "transport.play", "transport.pause",
                             "transport.stop", "transport.loop", "transport.follow-playhead",
                             "transport.resonance"]
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
}
