import QtCore
import QtQuick
import QtQuick.Controls
import QtTest
import ShellQmlCheck 1.0
import "../../ui/shell"

TestCase {
    id: testCase
    name: "ShellSettings"
    when: windowShown
    width: 960
    height: 640
    visible: true

    ShellQmlBootstrap { id: bootstrap }
    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }
    Component { id: settingsComponent; Settings { category: "engine" } }
    property var shell: null
    property var nativeSettings: null

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        nativeSettings = settingsComponent.createObject(testCase)
        nativeSettings.setValue("pcmMixer", "sappy")
        nativeSettings.setValue("maxPcmChannels", 8)
        nativeSettings.setValue("pcmMixRate", 21024)
        nativeSettings.setValue("analogFilter", true)
        nativeSettings.sync()
    }
    function cleanupTestCase() {
        nativeSettings.destroy()
        wait(0)
        verify(bootstrap.clearSettings(), "settings fixture remains isolated")
    }
    function waitForNative(predicate, timeoutMs) {
        const deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }
    function cleanup() {
        if (!shell)
            return
        const settingsDialog = dialog()
        if (settingsDialog && settingsDialog.visible)
            settingsDialog.close()
        const app = shell.shellPresenter.session
        if (app.songOpen) {
            shell.close()
            if (waitForNative(function() { return app.songTabs.pendingCloseId >= 0 }, 2000))
                app.songTabs.confirmDiscard()
            verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 5000),
                   "dirty song close completes")
        }
        shell.destroy()
        shell = null
        wait(0)
    }
    function createShell() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "production shell loads")
        tryCompare(shell.shellPresenter.settingsStore, "mixer", "sappy")
        return shell.shellPresenter
    }
    function dialog() { return findChild(shell, "shellSettingsDialog") }
    function reference(profile, page) {
        return JSON.parse(bootstrap.settingsReferenceJson(profile, page))
    }
    function checkRegion(baseline, name, child, tolerance) {
        const expected = baseline.regions.find(function(entry) { return entry.name === name })
        verify(expected !== undefined && child !== null, name + " is present")
        const mapped = child.mapToItem(dialog().contentItem, 0, 0)
        verify(Math.abs(mapped.x - expected.x) <= tolerance
               && Math.abs(mapped.y - expected.y) <= tolerance
               && Math.abs(child.width - expected.w) <= tolerance
               && Math.abs(child.height - expected.h) <= tolerance,
               name + " measured " + mapped.x + "," + mapped.y + " "
               + child.width + "x" + child.height + "; widget "
               + expected.x + "," + expected.y + " " + expected.w + "x" + expected.h)
    }
    function useFont(px) {
        dialog().applicationFont = Qt.font({family: dialog().applicationFont.family,
                                            pixelSize: px})
        wait(0)
    }
    function capture(page, px) {
        var saved = false
        verify(findChild(dialog(), "settingsBody").grabToImage(function(result) {
            saved = result.saveToFile(bootstrap.settingsCapturePath(page, px))
        }), page + " settings capture starts")
        tryVerify(function() { return saved }, 3000, page + " settings image is saved")
    }
    function test_engineRoundTripAndInvalidMixer() {
        const presenter = createShell()
        const model = presenter.settingsStore
        compare(model.maxPcmChannels, 8)
        compare(model.mixRate, 21024)
        compare(model.analogFilter, true)
        presenter.activate("edit.engine_settings")
        tryCompare(dialog(), "visible", true)
        compare(dialog().selectedTab, 0)
        compare(findChild(dialog(), "settingsSongTab").enabled, false)
        compare(findChild(dialog(), "pcmMixerCombo").count, 2)
        compare(findChild(dialog(), "pcmMixerCombo").textAt(0), "Ipatix")
        compare(findChild(dialog(), "pcmMixerCombo").textAt(1), "Sappy")
        useFont(12)
        const engineRegions = ["tabs", "tab-bar", "button-box", "engine.polyphony",
                               "pcmMixerCombo", "engine.mix-rate", "engine.analog-filter",
                               "engine.restore-defaults"]
        const baseline = reference("macos-dpr1-font12", "engine")
        for (const name of engineRegions)
            checkRegion(baseline, name, findChild(dialog(), name), 6)
        capture("engine", 12)
        useFont(16)
        const larger = reference("macos-dpr2-font16", "engine")
        for (const name of engineRegions)
            checkRegion(larger, name, findChild(dialog(), name), 6)
        capture("engine", 16)
        compare(findChild(dialog(), "pcmMixerCombo").currentIndex, 1)
        model.changeMixer("ipatix")
        model.changeMaxPcmChannels(7)
        model.changeMixRate(13379)
        model.changeAnalogFilter(false)
        findChild(dialog(), "settingsApply").clicked()
        nativeSettings.sync()
        tryVerify(function() { return String(nativeSettings.value("pcmMixer")) === "ipatix" }, 5000,
                  "Apply persisted the actual mixer value")
        compare(Number(nativeSettings.value("maxPcmChannels")), 7)
        compare(Number(nativeSettings.value("pcmMixRate")), 13379)
        compare(String(nativeSettings.value("analogFilter")), "false")
        nativeSettings.setValue("pcmMixer", "invalid")
        nativeSettings.sync()
        dialog().close()
        const second = shellComponent.createObject(null)
        verify(second !== null)
        tryCompare(second.shellPresenter.settingsStore, "mixer", "ipatix")
        second.destroy()
        nativeSettings.setValue("pcmMixer", "sappy")
        nativeSettings.sync()
    }
    function test_songFlagsAndReferenceGeometry() {
        const presenter = createShell()
        const app = presenter.session
        app.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() { return app.songOpen || app.lastSaveError.length > 0 }, 30000),
               "song loads: " + app.lastSaveError)
        presenter.activate("edit.song_settings")
        tryCompare(dialog(), "visible", true)
        compare(dialog().selectedTab, 1)
        const model = presenter.settingsStore
        compare(model.songAvailable, true)
        compare(model.songLabel, "mus_route101")
        useFont(12)
        const songRegions = ["tabs", "tab-bar", "button-box", "song.voicegroup",
                             "song.volume", "song.reverb", "song.priority",
                             "song.exact-gate", "song.extended-clocks",
                             "song.no-compression"]
        const baseline = reference("macos-dpr1-font12", "song")
        compare(baseline.image.width, 560)
        verify(model.voicegroups.indexOf("fixture_rich") >= 0)
        for (const name of songRegions)
            checkRegion(baseline, name, findChild(dialog(), name), 6)
        capture("song", 12)
        compare(model.voicegroup, "fixture_rich", "song config voicegroup is presented")
        compare(findChild(dialog(), "song.voicegroup").editText, model.voicegroup,
                "editable selector preserves the current song's voicegroup")
        compare(app.documentDirty, false, "loaded song starts clean")
        useFont(16)
        const larger = reference("macos-dpr2-font16", "song")
        for (const name of songRegions)
            checkRegion(larger, name, findChild(dialog(), name), 6)
        capture("song", 16)
        findChild(dialog(), "settingsApply").clicked()
        verify(waitForNative(function() { return !model.isApplying }, 10000))
        compare(app.documentDirty, false, "unchanged Apply does not dirty the song")
        model.changeMasterVolume(110)
        model.changeReverb(50)
        model.changePriority(7)
        model.changeExactGate(false)
        model.changeExtendedClocks(true)
        model.changeNoCompression(true)
        findChild(dialog(), "settingsApply").clicked()
        verify(waitForNative(function() { return !model.isApplying && app.documentDirty }, 10000),
               "song settings became an undoable dirty document")
        app.requestSave()
        verify(waitForNative(function() { return !app.saveInProgress && !app.documentDirty }, 20000),
               "the normal save receipt includes the changed song flags: " + app.lastSaveError)
        const line = bootstrap.settingsSavedFlags()
        for (const flag of ["-V110", "-R50", "-P7", "-X", "-N"])
            verify(line.indexOf(flag) >= 0, flag + " reached midi.cfg: " + line)
        verify(line.indexOf("-E") < 0, "unchecked exact gate was removed: " + line)
    }
}
