import QtCore
import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

// Theme persistence and applied-chrome observations through the production
// shell. Ports ThemeLayoutTest::themePersistence
// (tst_themelayout_color.cpp:270-303) and the commit-direction rules of the
// deleted tst_themelayout_settings.cpp dialog case: each seeded mode round-
// trips through ShellPresenter.restoreAppearance with canonical writeback,
// and grid contrast moves the applied grid chromatically. settingsRepair
// (custom/#000000/#FFFFFF/80) already lives in tst_ShellWindow.qml test_b
// and is not duplicated here.
TestCase {
    id: testCase
    name: "Theme"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null
    property var settings: null

    ShellQmlBootstrap { id: bootstrap }

    Component { id: settingsComponent; Settings {} }
    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }

    function initTestCase() {
        // Private native store like tst_ShellWindow.qml, never the caller's
        // preferences.
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
        verify(bootstrap.clearSettings(), "removed only the private native settings")
    }

    function cleanup() {
        // No songs open in this lane, so no close-all walk is needed.
        if (shell) {
            shell.destroy()
            shell = null
            wait(0)
        }
    }

    function waitForNative(predicate, timeoutMs) {
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
    }

    function openThemedShell() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
    }

    function closeThemedShell() {
        shell.destroy()
        shell = null
        wait(0)
    }

    function hexChannels(hex) {
        var body = hex.substring(1)
        var value = parseInt(body, 16)
        if (body.length === 8) {
            return {
                a: (value >> 24) & 255, r: (value >> 16) & 255,
                g: (value >> 8) & 255, b: value & 255
            }
        }
        return { a: 255, r: (value >> 16) & 255, g: (value >> 8) & 255, b: value & 255 }
    }

    function linearChannel(channel) {
        var c = channel / 255
        return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    }

    function luminance(hex) {
        var c = hexChannels(hex)
        return 0.2126 * linearChannel(c.r) + 0.7152 * linearChannel(c.g)
            + 0.0722 * linearChannel(c.b)
    }

    function contrastRatio(first, second) {
        var lighter = Math.max(luminance(first), luminance(second))
        var darker = Math.min(luminance(first), luminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    function test_themePersistence_data() {
        return [
            { tag: "vanilla", mode: "vanilla", contrast: 50, window: "#C9C1BB" },
            { tag: "dark", mode: "dark-neutral-high", contrast: 80, window: "#373737" },
            { tag: "immaterial", mode: "immaterial", contrast: 100, window: "#2E3138" },
        ]
    }

    function test_themePersistence(data) {
        // ThemeController.commit + fresh-controller restore: the seeded mode
        // round-trips through the production shell with canonical writeback.
        settings.setValue("theme/mode", data.mode)
        settings.setValue("theme/grid-line-contrast", data.contrast)
        settings.sync()
        openThemedShell()
        tryCompare(shell.shellPresenter, "themeMode", data.mode)
        compare(shell.shellPresenter.gridLineContrast, data.contrast)
        var palette = shell.shellPresenter.session.palette
        compare(palette.windowBackground, data.window)
        verify(contrastRatio(palette.windowText, palette.chromeBackground) >= 4.5,
               data.mode + ": applied menu-bar pair keeps the 4.5 floor")
        verify(contrastRatio(palette.buttonPressedText, palette.buttonPressedBackground) >= 4.5,
               data.mode + ": applied pressed pair keeps the 4.5 floor")
        verify(contrastRatio(palette.disabledText, palette.windowText) >= 1.3,
               data.mode + ": applied disabled pair keeps the 1.3 floor")
        settings.sync()
        compare(settings.value("theme/mode", null), data.mode)
        compare(Number(settings.value("theme/grid-line-contrast", null)), data.contrast)
        closeThemedShell()
    }

    function test_themeRepair() {
        // Empty mode and unparseable contrast repair to vanilla/50 with
        // canonical writeback, without the test_b legacy-key fixture.
        settings.setValue("theme/mode", "")
        settings.setValue("theme/grid-line-contrast", "banana")
        settings.sync()
        openThemedShell()
        tryCompare(shell.shellPresenter, "themeMode", "vanilla")
        compare(shell.shellPresenter.gridLineContrast, 50)
        settings.sync()
        compare(settings.value("theme/mode", null), "vanilla")
        compare(Number(settings.value("theme/grid-line-contrast", null)), 50)
        closeThemedShell()
    }

    function test_gridContrastDirection() {
        settings.setValue("theme/mode", "vanilla")
        settings.setValue("theme/grid-line-contrast", 50)
        settings.sync()
        openThemedShell()
        tryCompare(shell.shellPresenter, "themeMode", "vanilla")
        var palette = shell.shellPresenter.session.palette
        var baseline = palette.gridLine
        var roll = palette.rollBackground

        shell.shellPresenter.restoreAppearance("vanilla", "0", Qt.application.name)
        verify(waitForNative(function() {
            return palette.gridLine !== baseline
        }, 3000), "contrast 0 moves the applied grid")
        var softened = palette.gridLine
        verify(hexChannels(softened).a < hexChannels(baseline).a,
               "contrast 0 lowers the applied grid alpha")
        verify(contrastRatio(softened, roll) < contrastRatio(baseline, roll),
               "contrast 0 loses grid contrast against the roll")

        shell.shellPresenter.restoreAppearance("vanilla", "100", Qt.application.name)
        verify(waitForNative(function() {
            return palette.gridLine !== softened
        }, 3000), "contrast 100 moves the applied grid again")
        var strengthened = palette.gridLine
        verify(hexChannels(strengthened).a > hexChannels(baseline).a,
               "contrast 100 raises the applied grid alpha")
        verify(contrastRatio(strengthened, roll) > contrastRatio(baseline, roll),
               "contrast 100 gains grid contrast against the roll")

        shell.shellPresenter.restoreAppearance("vanilla", "50", Qt.application.name)
        verify(waitForNative(function() {
            return palette.gridLine === baseline
        }, 3000), "default contrast restores the pinned grid value")
        closeThemedShell()
    }
    function test_menuChromeFollowsTheme() {
        // Combo/popdown raster (tst_themelayout_chrome.cpp:78-133) and the
        // dark-baseline palette pins (:135-193) observe QWidget rendering
        // with no QWidget layer in the Swift app. The user-observable half —
        // menu chrome follows the applied theme — lives in ShellWindow's
        // Basic context-menu delegate bindings, asserted here.
        settings.setValue("theme/mode", "vanilla")
        settings.setValue("theme/grid-line-contrast", 50)
        settings.sync()
        openThemedShell()
        tryCompare(shell.shellPresenter, "themeMode", "vanilla")
        var palette = shell.shellPresenter.session.palette
        var menu = findChild(shell, "shellGridContextMenu")
        verify(menu, "the production context menu exists")
        var copyItem = findChild(menu, "shellContextAction_roll.copy")
        verify(copyItem, "Copy is a real context-menu action")
        compare(copyItem.background.color.toString().toUpperCase(), "#D2D0CA",
                "resting menu item shows the item surface")
        compare(copyItem.foreground.toString().toUpperCase(),
                palette.disabledText.toUpperCase(),
                "inactive menu text shows the disabled ink")
        copyItem.highlighted = true
        verify(waitForNative(function() {
            return copyItem.background.color.toString().toUpperCase() === "#E7E2DC"
        }, 3000), "highlighted menu item shows the item hover surface")
        copyItem.highlighted = false
        shell.shellPresenter.restoreAppearance("dark-neutral-high", "50",
                                               Qt.application.name)
        verify(waitForNative(function() {
            return copyItem.background.color.toString().toUpperCase() === "#424242"
        }, 3000), "menu chrome follows the theme switch")
        compare(copyItem.foreground.toString().toUpperCase(), "#A0A0A0",
                "menu ink follows the theme switch")
        closeThemedShell()
    }
}
