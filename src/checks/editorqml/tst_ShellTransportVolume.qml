import QtQuick
import QtQuick.Controls
import QtTest
import "GatedVisualsHelpers.js" as Helpers

ShellTransportSupport {

    function test_volumeIsolationAcrossRealInputAndTabs() {
        settings.setInt("outputVolume", 37)
        settings.synchronize()
        const bar = openShell()
        openSong()
        const session = shell.shellPresenter.session
        const dial = findChild(bar, "transportOutputVolume")
        const master = findChild(bar, "transportMasterVolume")
        compare(bar.presenter.outputVolume, 37,
                "staged output 37 restores to the mounted presenter")
        compare(dial.value, 37,
                "staged output 37 paints in the mounted dial")
        tryCompare(master, "enabled", true, 3000,
                   "loaded song master volume editor accepts input")
        const original = master.value
        compare(original, bar.presenter.masterVolume,
                "loaded master field reflects the selected song")
        const x = dial.width / 2
        const y = dial.height / 2
        mouseClick(dial, x, y)
        compare(dial.value, 37,
                "stationary mounted dial click preserves restored output 37")
        compare(session.documentDirty, false,
                "stationary output click leaves the song clean")
        compare(session.canUndo, false,
                "stationary output click creates no song undo")
        mousePress(dial, x, y, Qt.LeftButton)
        mouseMove(dial, x, y + 10, -1, Qt.LeftButton)
        mouseRelease(dial, x, y + 10, Qt.LeftButton)
        tryCompare(dial, "value", 42, 3000,
                   "pointer drag to 42 updates the output dial")
        compare(settings.int("outputVolume", -1), 42,
                "pointer drag to 42 persists the global output preference")
        compare(master.value, original,
                "output drag to 42 cannot change song master volume")
        compare(session.documentDirty, false,
                "output drag to 42 cannot dirty the song")
        compare(session.canUndo, false,
                "output drag to 42 creates no song undo")
        cleanup()
        settings.setInt("outputVolume", 37)
        settings.synchronize()
        const restored = openShell()
        openSong()
        restored.presenter.refresh()
        const field = findChild(restored, "transportMasterVolume")
        const output = findChild(restored, "transportOutputVolume")
        const tabs = shell.shellPresenter.session.songTabs
        const firstId = tabs.selectedId
        tryCompare(field, "value", restored.presenter.masterVolume, 3000,
                   "first song field settles to its loaded cfg before editing")
        const firstValue = field.value
        const edited = firstValue === 87 ? 86 : 87
        field.focusInput(Qt.OtherFocusReason)
        field.selectAll()
        for (const digit of String(edited))
            keyClick(Qt.Key_0 + Number(digit))
        keyClick(Qt.Key_Return)
        tryCompare(field, "value", edited, 3000,
                   "typed master volume edits the first song")
        verify(waitForNative(function() {
            return restored.presenter.masterVolume === edited
                && shell.shellPresenter.session.documentDirty
        }, 3000), "typed master volume reaches the first song and makes it dirty: original="
                   + firstValue + " edited=" + edited + " field=" + field.value
                   + " presenter=" + restored.presenter.masterVolume
                   + " dirty=" + shell.shellPresenter.session.documentDirty)
        compare(output.value, 37,
                "song master editing cannot move the global output dial")
        shell.shellPresenter.session.openSong("mus_littleroot_test")
        verify(waitForNative(function() {
            return tabs.tabCount === 2 && tabs.selectedId !== firstId
                && restored.presenter.state !== 0
        }, 30000), "second song selects its own toolbar volume")
        compare(field.value, restored.presenter.masterVolume,
                "second tab field displays its selected song volume")
        compare(output.value, 37,
                "global output 37 survives tab selection")
        compare(shell.shellPresenter.session.documentDirty, false,
                "second song remains clean after first song edit")
        tabs.selectTab(firstId)
        tryCompare(field, "value", edited, 3000,
                   "returning to first tab restores its edited master value")
        shell.shellPresenter.session.requestUndo()
        verify(waitForNative(function() {
            restored.presenter.refresh()
            return field.value === firstValue && !shell.shellPresenter.session.documentDirty
        }, 3000), "undo restores first song volume in mounted field")
        compare(shell.shellPresenter.session.documentDirty, false,
                "undo returns first song to its clean state")
        field.focusInput(Qt.OtherFocusReason)
        field.selectAll()
        const stopped = restored.presenter.state
        keyClick(Qt.Key_5)
        compare(restored.presenter.state, stopped,
                "numeric-field digit stays local and never starts transport")
        const draft = findChild(field, "transportMasterVolumeInput")
        compare(draft.text, "5",
                "numeric-field digit appears only in the focused draft")
        keyClick(Qt.Key_Space)
        tryCompare(restored.presenter, "state", 3, 3000,
                   "bare Space from numeric chrome starts the window transport")
        const highlight = findChild(restored, "transportScaleHighlight")
        mouseClick(highlight, highlight.width / 2, highlight.height / 2)
        keyClick(Qt.Key_Space)
        tryCompare(restored.presenter, "state", 2, 3000,
                   "scale chrome leaves bare Space to window transport")
        settings.setInt("outputVolume", 100)
        settings.synchronize()
    }

    function test_outputDialEndpointPixels() {
        const bar = openShell(12)
        const dial = findChild(bar, "transportOutputVolume")
        verify(dial !== null && dial.visible, "painted output dial is mounted")
        waitForRendering(bar)
        const image = grabImage(bar)
        const ratio = image.width / bar.width
        const center = dial.mapToItem(bar, dial.width / 2, dial.height / 2)
        const radius = dial.radiusPx - dial.inset * 1.5
        const ink = Helpers.channels(bar.colors.outline)
        function tickInk(degrees) {
            const radians = degrees * Math.PI / 180
            const px = Math.round((center.x + Math.cos(radians) * radius) * ratio)
            const py = Math.round((center.y - Math.sin(radians) * radius) * ratio)
            for (let yy = py - 2; yy <= py + 2; ++yy)
                for (let xx = px - 2; xx <= px + 2; ++xx)
                    if (xx >= 0 && xx < image.width && yy >= 0 && yy < image.height
                            && Helpers.colorsNear([image.red(xx, yy), image.green(xx, yy),
                                                   image.blue(xx, yy)], ink, 8))
                        return true
            return false
        }
        verify(tickInk(240), "painted dial has a tick at 240 degrees")
        verify(tickInk(-60), "painted dial has a tick at minus 60 degrees")
        verify(!tickInk(270), "painted dial leaves 270 degrees without a tick")
    }

    function test_outputDialIncrementalDrag() {
        const bar = openShell()
        const output = findChild(bar, "transportOutputVolume")
        bar.presenter.setOutputVolume(40)
        const x = output.width / 2
        const y = output.height / 2
        mousePress(output, x, y, Qt.LeftButton)
        compare(bar.presenter.outputVolume, 40,
                "pressing the output dial without dragging leaves the volume unchanged")
        mouseMove(output, x, y + 140, -1, Qt.LeftButton)
        tryCompare(bar.presenter, "outputVolume", 100)
        mouseMove(output, x, y + 130, -1, Qt.LeftButton)
        compare(bar.presenter.outputVolume, 95,
                "dragging the output dial accumulates steps from the pointer's last position")
        mouseRelease(output, x, y + 130, Qt.LeftButton)
        mouseWheel(output, x, y, 0, -1200)
        tryCompare(output, "value", 0, 3000,
                   "mounted output dial input clamps to zero")
        mouseWheel(output, x, y, 0, -120)
        compare(output.value, 0,
                "lower output bound rejects further pointer reduction")
        mouseWheel(output, x, y, 0, 1200)
        tryCompare(output, "value", 100, 3000,
                   "mounted output dial input clamps to one hundred")
        mouseWheel(output, x, y, 0, 120)
        compare(output.value, 100,
                "upper output bound rejects further pointer increase")
    }

    function test_outputDialFineDragAndTooltip() {
        const bar = openShell()
        const output = findChild(bar, "transportOutputVolume")
        bar.presenter.setOutputVolume(40)
        const x = output.width / 2
        const y = output.height / 2
        keyPress(Qt.Key_Shift)
        mousePress(output, x, y, Qt.LeftButton, Qt.ShiftModifier)
        mouseMove(output, x, y + 10, -1, Qt.LeftButton, Qt.ShiftModifier)
        mouseRelease(output, x, y + 10, Qt.LeftButton, Qt.ShiftModifier)
        keyRelease(Qt.Key_Shift)
        compare(bar.presenter.outputVolume, 42,
                "shift dragging the output dial uses the fine rate")
        compare(output.ToolTip.text,
                "Application output volume. Does not change the song volume or saved song settings.",
                "the output dial tooltip explains it does not change the song volume")
        output.valueCommitted(100)
    }

    function test_outputVolumeSurvivesShellRelaunch() {
        var bar = openShell()
        var output = findChild(bar, "transportOutputVolume")
        verify(output !== null && output.visible, "application volume dial is mounted")
        // Seed through the dial's own valueCommitted path; input plumbing is covered by the
        // transitions test, and this test's contract is the Settings round-trip.
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
}
