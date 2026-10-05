import QtQuick
import QtQuick.Controls
import QtTest
import ShellQmlCheck 1.0
import Porydaw.Ui

ShellLaneSupport {
    id: testCase
    name: "ShellSettings"
    when: windowShown
    width: 960
    height: 640
    visible: true

    ShellQmlBootstrap { id: bootstrap }
    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }
    readonly property var nativeSettings: bootstrap.preferences

    Component { id: engineGeometryComponent; EngineSettingsPage {} }
    Component { id: songGeometryComponent; SongSettingsPage {} }

    function checkPinnedRect(root, name, x, y, width, height) {
        const child = findChild(root, name)
        verify(child !== null, name + " is mounted")
        const point = child.mapToItem(root, 0, 0)
        compare(point.x, x, name + " pinned x")
        compare(point.y, y, name + " pinned y")
        compare(child.width, width, name + " pinned width")
        compare(child.height, height, name + " pinned height")
    }
    function test_fieldRectsAtTwoFontScales_data() {
        return [{ tag: "font12", unit: 1 }, { tag: "font18", unit: 1.5 }]
    }
    function test_fieldRectsAtTwoFontScales(data) {
        const presenter = createShell()
        const unit = data.unit
        const delta = unit - 1
        const properties = { store: presenter.settingsStore,
                             colors: presenter.session.grid.palette,
                             typography: presenter.session.typographyFonts,
                             unit: unit, width: 520, height: 500 }
        const engine = engineGeometryComponent.createObject(testCase, properties)
        const song = songGeometryComponent.createObject(testCase, properties)
        verify(engine !== null && song !== null, "production settings pages load")
        try {
            const engineX = 105 + 84 * delta
            checkPinnedRect(engine, "engine.polyphony", engineX, 11 * unit,
                            520 - engineX, 25 + 15 * delta)
            checkPinnedRect(engine, "pcmMixerCombo", engineX, 42 + 27 * delta,
                            520 - engineX, 22 + 12 * delta)
            checkPinnedRect(engine, "engine.mix-rate", engineX, 70 + 39 * delta,
                            520 - engineX, 22 + 12 * delta)
            checkPinnedRect(engine, "engine.analog-filter", 0, 98 + 51 * delta,
                            520, 16 + 12 * delta)
            checkPinnedRect(engine, "engine.restore-defaults", 0, 120 + 63 * delta,
                            118 + 99 * delta, 18 + 12 * delta)
            const songX = 125 + 102 * delta
            checkPinnedRect(song, "song.voicegroup", songX, 11 * unit,
                            520 - songX, 22 + 12 * delta)
            for (const row of [["song.volume", 39, 24], ["song.reverb", 70, 39],
                               ["song.priority", 101, 54]])
                checkPinnedRect(song, row[0], songX, row[1] + row[2] * delta,
                                520 - songX, 25 + 15 * delta)
            for (const row of [["song.exact-gate", 132, 69],
                               ["song.extended-clocks", 154, 81],
                               ["song.no-compression", 176, 93]])
                checkPinnedRect(song, row[0], 0, row[1] + row[2] * delta,
                                520, 16 + 12 * delta)
        } finally {
            engine.destroy()
            song.destroy()
        }
    }
    function initTestCase() {
        nativeSettings.setString("engine.pcmMixer", "sappy")
        nativeSettings.setInt("engine.maxPcmChannels", 8)
        nativeSettings.setInt("engine.pcmMixRate", 21024)
        nativeSettings.setBool("engine.analogFilter", true)
    }
    laneBootstrap: bootstrap
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
    function dialog() {
        findChild(shell, "shellSettingsLoader").active = true
        return findChild(shell, "shellSettingsDialog")
    }
    function selectThemeTab() {
        const tab = findChild(dialog(), "settingsThemeTab")
        verify(!!tab, "settings dialog exposes the Theme tab")
        mouseClick(tab, tab.width / 2, tab.height / 2)
        tryCompare(dialog(), "selectedTab", 2)
    }
    function reference(profile, page) {
        const baseline = JSON.parse(bootstrap.settingsReferenceJson(profile, page))
        const tabBar = baseline.regions.find(function(entry) { return entry.name === "tab-bar" })
        // The widget reference has two tabs; Theme adds one Engine-sized tab.
        tabBar.w += 64 + 42 * (dialog().unit - 1)
        return baseline
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
        const body = presenter.session.typographyFonts.body
        compare(dialog().unit, presenter.session.baseFontPx / 12,
                "settings layout unit derives from session base")
        for (const name of ["settingsEngineTab", "pcmMixerCombo", "engine.polyphony",
                            "engine.mix-rate", "engine.analog-filter",
                            "engine.restore-defaults"]) {
            const control = findChild(dialog(), name)
            compare(control.font.family, body.family, name + " uses body family")
            compare(control.font.pixelSize, body.pixelSize, name + " uses body size")
            compare(control.font.weight, body.weight, name + " keeps body weight")
        }
        const engineRegions = ["tabs", "tab-bar", "button-box", "engine.polyphony",
                               "pcmMixerCombo", "engine.mix-rate", "engine.analog-filter",
                               "engine.restore-defaults"]
        const baseline = reference("macos-dpr1-font12", "engine")
        for (const name of engineRegions)
            checkRegion(baseline, name, findChild(dialog(), name), 6)
        capture("engine", presenter.session.baseFontPx)
        compare(findChild(dialog(), "pcmMixerCombo").currentIndex, 1)
        model.changeMixer("ipatix")
        model.changeMaxPcmChannels(7)
        model.changeMixRate(13379)
        model.changeAnalogFilter(false)
        findChild(dialog(), "settingsApply").clicked()
        tryVerify(function() {
            return nativeSettings.string("engine.pcmMixer", "") === "ipatix"
        }, 5000, "Apply persisted the actual mixer value")
        compare(nativeSettings.int("engine.maxPcmChannels", -1), 7)
        compare(nativeSettings.int("engine.pcmMixRate", -1), 13379)
        compare(nativeSettings.bool("engine.analogFilter", true), false)
        nativeSettings.setString("engine.pcmMixer", "invalid")
        dialog().close()
        const second = shellComponent.createObject(null)
        verify(second !== null)
        tryCompare(second.shellPresenter.settingsStore, "mixer", "ipatix")
        second.destroy()
        nativeSettings.setString("engine.pcmMixer", "sappy")
    }
    function test_reopeningDiscardsCancelledDraft() {
        const presenter = createShell()
        const model = presenter.settingsStore
        presenter.activate("edit.engine_settings")
        tryCompare(dialog(), "visible", true)
        const savedChannels = model.maxPcmChannels
        const field = findChild(dialog(), "engine.polyphony")
        verify(!!field, "Object exists")
        const changedChannels = savedChannels > 1 ? savedChannels - 1 : 2
        field.value = changedChannels
        model.changeMaxPcmChannels(changedChannels)
        const cancel = findChild(dialog(), "settingsCancel")
        verify(!!cancel, "Object exists")
        mouseClick(cancel, cancel.width / 2, cancel.height / 2)
        tryCompare(dialog(), "visible", false)
        presenter.activate("edit.engine_settings")
        tryCompare(dialog(), "visible", true)
        const reopenedField = findChild(dialog(), "engine.polyphony")
        verify(!!reopenedField, "Object exists")
        tryCompare(model, "maxPcmChannels", savedChannels)
        tryCompare(reopenedField, "value", savedChannels)
    }
    function test_escapeDismissesAndRestoresWindowFocus() {
        const presenter = createShell()
        shell.requestActivate()
        tryCompare(shell, "active", true)
        presenter.activate("edit.engine_settings")
        const settings = dialog()
        tryCompare(settings, "visible", true)
        tryCompare(settings, "active", true)
        const body = findChild(settings, "settingsBody")
        verify(body, "settings dialog body receives key events")
        keyClick(Qt.Key_Escape)
        tryCompare(settings, "visible", false)
        tryCompare(shell, "active", true)
    }
    function test_gridContrastPreviewApplyAndRevert() {
        nativeSettings.setString("theme.mode", "vanilla")
        nativeSettings.setInt("theme.grid-line-contrast", 50)
        const presenter = createShell()
        const app = presenter.session
        app.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() { return app.songOpen || app.lastSaveError.length > 0 }, 30000),
               "grid contrast fixture song loads: " + app.lastSaveError)
        verify(app.songOpen, "grid contrast fixture opens a mounted song")
        verify(waitForNative(function() {
            return shell.sceneLoader !== null && shell.sceneLoader.status === Loader.Ready
        }, 10000), "the grid contrast fixture mounts its editor scene")
        const page = findChild(shell.sceneLoader.item, "songTab_" + app.songTabs.selectedId)
        const surface = page ? findChild(page, "swiftRollOverlay") : null
        verify(surface && surface.gridModel, "the grid contrast journey has a mounted roll")
        const palette = surface.gridModel.palette
        function alpha(color) {
            return Math.round(color.a * 255)
        }
        compare(alpha(palette.gridLine), 63, "the mounted grid begins at the default opacity")

        presenter.activate("edit.engine_settings")
        tryCompare(dialog(), "visible", true)
        selectThemeTab()
        let slider = findChild(dialog(), "gridLineContrastSlider")
        verify(!!slider, "the Theme settings page exposes the contrast control")
        tryCompare(slider, "value", 50)
        function dragContrast(targetX) {
            mousePress(slider, slider.handle.x + slider.handle.width / 2, slider.height / 2)
            mouseMove(slider, targetX, slider.height / 2)
            mouseRelease(slider, targetX, slider.height / 2)
        }
        dragContrast(slider.handle.width / 2)
        tryCompare(slider, "value", 0)
        tryCompare(presenter, "gridLineContrast", 0)
        compare(alpha(palette.gridLine), 0, "soft preview removes opacity from the mounted grid")
        compare(nativeSettings.int("theme.grid-line-contrast", -1), 50,
                "live preview does not commit the contrast preference")

        dragContrast(slider.width - slider.handle.width / 2)
        tryCompare(slider, "value", 100)
        tryCompare(presenter, "gridLineContrast", 100)
        compare(alpha(palette.gridLine), 255, "strong preview makes the mounted grid opaque")
        const apply = findChild(dialog(), "settingsApply")
        verify(!!apply, "the mounted settings dialog has an Apply button")
        verify(apply.enabled && apply.width > 0 && apply.height > 0,
               "Apply remains available after grid preview")
        mouseClick(apply, apply.width / 2, apply.height / 2)
        verify(waitForNative(function() {
            return nativeSettings.int("theme.grid-line-contrast", -1) === 100
        }, 5000), "A047 Apply commits grid-line contrast 100 to preferences")

        dragContrast(slider.handle.width / 2)
        tryCompare(presenter, "gridLineContrast", 0)
        compare(alpha(palette.gridLine), 0, "moving away previews the soft grid again")
        const cancel = findChild(dialog(), "settingsCancel")
        verify(!!cancel, "the mounted settings dialog has a Cancel button")
        mouseClick(cancel, cancel.width / 2, cancel.height / 2)
        tryCompare(presenter, "gridLineContrast", 100)
        compare(alpha(palette.gridLine), 255, "Cancel restores the committed strong grid")
        presenter.activate("edit.engine_settings")
        tryCompare(dialog(), "visible", true)
        selectThemeTab()
        slider = findChild(dialog(), "gridLineContrastSlider")
        tryCompare(slider, "value", 100)
        dragContrast(slider.handle.width / 2)
        tryCompare(presenter, "gridLineContrast", 0)
        dialog().close()
        tryCompare(presenter, "gridLineContrast", 100)
        compare(alpha(palette.gridLine), 255, "closing after another preview restores strong grid")
        presenter.activate("edit.engine_settings")
        tryCompare(dialog(), "visible", true)
        selectThemeTab()
        slider = findChild(dialog(), "gridLineContrastSlider")
        tryCompare(slider, "value", 100)
        compare(nativeSettings.int("theme.grid-line-contrast", -1), 100,
                "reopening preserves the committed grid contrast")
        nativeSettings.setInt("theme.grid-line-contrast", 50)
    }
    function test_themeModePreviewCommitAndRevert() {
        nativeSettings.setString("theme.mode", "vanilla")
        nativeSettings.setInt("theme.grid-line-contrast", 50)
        const presenter = createShell()
        const palette = presenter.session.palette
        tryCompare(presenter, "themeMode", "vanilla")
        presenter.activate("edit.engine_settings")
        tryCompare(dialog(), "visible", true)
        selectThemeTab()
        const group = findChild(dialog(), "themeModeGroup")
        verify(!!group, "theme picker group rides the mounted settings dialog")
        const vanilla = findChild(dialog(), "vanillaModeButton")
        const dark = findChild(dialog(), "darkNeutralHighModeButton")
        const immaterial = findChild(dialog(), "immaterialModeButton")
        verify(!!vanilla && !!dark && !!immaterial, "theme picker shows its three fork mode buttons")
        compare(vanilla.text, "Vanilla", "vanilla mode button keeps the fork label")
        compare(dark.text, "Dark Neutral High", "dark mode button keeps the fork label")
        compare(immaterial.text, "Immaterial", "immaterial mode button keeps the fork label")
        for (const entry of [["vanillaModeLabel", "vanilla"], ["darkNeutralHighModeLabel", "dark-neutral-high"], ["immaterialModeLabel", "immaterial"]]) {
            const label = findChild(dialog(), entry[0])
            verify(!!label, entry[1] + " mode button exposes its label item")
            verify(label.implicitWidth <= label.width + 1 && !label.truncated, entry[1] + " mode label is fully visible without elision")
        }
        tryCompare(vanilla, "checked", true)
        compare(palette.chromeBackground.toString().toUpperCase(), "#BDB5AF",
                "mounted settings reflect the committed vanilla chrome")
        mouseClick(dark, dark.width / 2, dark.height / 2)
        tryCompare(presenter, "themeMode", "dark-neutral-high")
        tryCompare(dark, "checked", true)
        compare(palette.chromeBackground.toString().toUpperCase(), "#424242",
                "clicking dark previews the dark chrome live")
        compare(nativeSettings.string("theme.mode", ""), "vanilla",
                "mode preview does not persist the theme preference")
        mouseClick(immaterial, immaterial.width / 2, immaterial.height / 2)
        tryCompare(presenter, "themeMode", "immaterial")
        compare(palette.chromeBackground.toString().toUpperCase(), "#363941",
                "clicking immaterial previews the immaterial chrome live")
        const cancel = findChild(dialog(), "settingsCancel")
        verify(!!cancel, "the mounted settings dialog has a Cancel button")
        mouseClick(cancel, cancel.width / 2, cancel.height / 2)
        tryCompare(presenter, "themeMode", "vanilla")
        compare(palette.chromeBackground.toString().toUpperCase(), "#BDB5AF",
                "Cancel reverts the previewed mode to the committed vanilla chrome")
        compare(nativeSettings.string("theme.mode", ""), "vanilla",
                "cancelled preview leaves the persisted mode alone")
        presenter.activate("edit.engine_settings")
        tryCompare(dialog(), "visible", true)
        selectThemeTab()
        tryCompare(findChild(dialog(), "vanillaModeButton"), "checked", true)
        const darkAgain = findChild(dialog(), "darkNeutralHighModeButton")
        mouseClick(darkAgain, darkAgain.width / 2, darkAgain.height / 2)
        tryCompare(presenter, "themeMode", "dark-neutral-high")
        const apply = findChild(dialog(), "settingsApply")
        verify(!!apply, "the mounted settings dialog has an Apply button")
        mouseClick(apply, apply.width / 2, apply.height / 2)
        verify(waitForNative(function() {
            return nativeSettings.string("theme.mode", "") === "dark-neutral-high"
        }, 5000), "Apply commits the previewed dark mode to preferences")
        compare(presenter.themeMode, "dark-neutral-high",
                "Apply keeps the committed dark mode applied")
        dialog().close()
        tryCompare(dialog(), "visible", false)
        presenter.activate("edit.engine_settings")
        tryCompare(dialog(), "visible", true)
        selectThemeTab()
        tryCompare(findChild(dialog(), "darkNeutralHighModeButton"), "checked", true)
        compare(nativeSettings.string("theme.mode", ""), "dark-neutral-high",
                "reopening preserves the committed dark mode")
        nativeSettings.setString("theme.mode", "vanilla")
        nativeSettings.setInt("theme.grid-line-contrast", 50)
    }
    function test_themeModeGeometryStableAcrossPreview() {
        nativeSettings.setString("theme.mode", "vanilla")
        nativeSettings.setInt("theme.grid-line-contrast", 50)
        const presenter = createShell()
        tryCompare(presenter, "themeMode", "vanilla")
        presenter.activate("edit.engine_settings")
        tryCompare(dialog(), "visible", true)
        selectThemeTab()
        const content = dialog().contentItem
        function frame(item) {
            const mapped = item.mapToItem(content, 0, 0)
            return [mapped.x, mapped.y, item.width, item.height]
        }
        const beforeSize = [dialog().width, dialog().height]
        const buttons = [findChild(dialog(), "vanillaModeButton"),
                         findChild(dialog(), "darkNeutralHighModeButton"),
                         findChild(dialog(), "immaterialModeButton")]
        verify(buttons[0] && buttons[1] && buttons[2], "all three mode buttons mount for geometry")
        const before = [frame(buttons[0]), frame(buttons[1]), frame(buttons[2])]
        mouseClick(buttons[1], buttons[1].width / 2, buttons[1].height / 2)
        tryCompare(presenter, "themeMode", "dark-neutral-high")
        wait(0)
        compare([dialog().width, dialog().height], beforeSize,
                "settings size is unchanged across a mode preview click")
        for (let index = 0; index < 3; ++index)
            compare(frame(buttons[index]), before[index],
                    "mode button " + index + " geometry is unchanged across a mode preview click")
        dialog().close()
        tryCompare(presenter, "themeMode", "vanilla")
        nativeSettings.setString("theme.mode", "vanilla")
    }
    function test_songFlagsAndReferenceGeometry() {
        const presenter = createShell()
        const app = presenter.session
        app.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() { return app.songOpen || app.lastSaveError.length > 0 }, 30000),
               "song loads: " + app.lastSaveError)
        presenter.activate("edit.song_settings")
        tryCompare(dialog(), "visible", true)
        verify(waitForNative(function() {
            return presenter.settingsStore.voicegroups.indexOf("fixture_rich") >= 0
        }, 5000), "the deferred voicegroup catalog reaches the song settings dialog")
        compare(dialog().selectedTab, 1)
        const model = presenter.settingsStore
        compare(model.songAvailable, true)
        compare(model.songLabel, "mus_route101")
        const body = app.typographyFonts.body
        compare(dialog().unit, app.baseFontPx / 12,
                "song settings geometry follows the session base")
        for (const name of ["settingsSongTab", "song.voicegroup", "song.volume",
                            "song.reverb", "song.priority", "song.exact-gate",
                            "song.extended-clocks", "song.no-compression"]) {
            const control = findChild(dialog(), name)
            compare(control.font.family, body.family, name + " uses body family")
            compare(control.font.pixelSize, body.pixelSize, name + " uses body size")
            compare(control.font.weight, body.weight, name + " keeps regular weight")
        }
        const songRegions = ["tabs", "tab-bar", "button-box", "song.voicegroup",
                             "song.volume", "song.reverb", "song.priority",
                             "song.exact-gate", "song.extended-clocks",
                             "song.no-compression"]
        const baseline = reference("macos-dpr1-font12", "song")
        compare(baseline.image.width, 560)
        verify(model.voicegroups.indexOf("fixture_rich") >= 0)
        for (const name of songRegions)
            checkRegion(baseline, name, findChild(dialog(), name), 6)
        capture("song", app.baseFontPx)
        compare(model.voicegroup, "fixture_rich", "song config voicegroup is presented")
        compare(findChild(dialog(), "song.voicegroup").editText, model.voicegroup,
                "editable selector preserves the current song's voicegroup")
        compare(app.documentDirty, false, "loaded song starts clean")
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
