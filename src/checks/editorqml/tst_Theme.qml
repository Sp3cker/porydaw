import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

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
    readonly property var settings: bootstrap.preferences

    ShellQmlBootstrap { id: bootstrap }

    Component { id: shellComponent; ShellWindow { width: 960; height: 640; visible: true } }


    function cleanup() {
        // No songs open in this lane, so no close-all walk is needed.
        if (shell) {
            shell.destroy()
            shell = null
            wait(0)
        }
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
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
        settings.setString("theme.mode", data.mode)
        settings.setInt("theme.grid-line-contrast", data.contrast)
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
        compare(settings.string("theme.mode", ""), data.mode)
        compare(settings.int("theme.grid-line-contrast", -1), data.contrast)
        closeThemedShell()
    }

    function test_themeRepair() {
        // Empty mode and unparseable contrast repair to vanilla/50 with
        // canonical writeback, without the test_b legacy-key fixture.
        settings.setString("theme.mode", "")
        settings.setString("theme.grid-line-contrast", "banana")
        openThemedShell()
        tryCompare(shell.shellPresenter, "themeMode", "vanilla")
        compare(shell.shellPresenter.gridLineContrast, 50)
        compare(settings.string("theme.mode", ""), "vanilla")
        compare(settings.int("theme.grid-line-contrast", -1), 50)
        closeThemedShell()
    }

    function test_gridContrastDirection() {
        settings.setString("theme.mode", "vanilla")
        settings.setInt("theme.grid-line-contrast", 50)
        openThemedShell()
        tryCompare(shell.shellPresenter, "themeMode", "vanilla")
        var palette = shell.shellPresenter.session.palette
        var baseline = palette.gridLine
        var roll = palette.rollBackground

        settings.setInt("theme.grid-line-contrast", 0)
        shell.shellPresenter.restoreAppearance()
        verify(waitForNative(function() {
            return palette.gridLine !== baseline
        }, 3000), "contrast 0 moves the applied grid")
        var softened = palette.gridLine
        verify(hexChannels(softened).a < hexChannels(baseline).a,
               "contrast 0 lowers the applied grid alpha")
        verify(contrastRatio(softened, roll) < contrastRatio(baseline, roll),
               "contrast 0 loses grid contrast against the roll")

        settings.setInt("theme.grid-line-contrast", 100)
        shell.shellPresenter.restoreAppearance()
        verify(waitForNative(function() {
            return palette.gridLine !== softened
        }, 3000), "contrast 100 moves the applied grid again")
        var strengthened = palette.gridLine
        verify(hexChannels(strengthened).a > hexChannels(baseline).a,
               "contrast 100 raises the applied grid alpha")
        verify(contrastRatio(strengthened, roll) > contrastRatio(baseline, roll),
               "contrast 100 gains grid contrast against the roll")

        settings.setInt("theme.grid-line-contrast", 50)
        shell.shellPresenter.restoreAppearance()
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
        settings.setString("theme.mode", "vanilla")
        settings.setInt("theme.grid-line-contrast", 50)
        openThemedShell()
        tryCompare(shell.shellPresenter, "themeMode", "vanilla")
        var palette = shell.shellPresenter.session.palette
        var menu = findChild(shell, "shellGridContextMenu")
        verify(menu, "the production context menu exists")
        var copyItem = findChild(menu, "shellContextAction_roll.copy")
        verify(copyItem, "Copy is a real context-menu action")
        const body = shell.shellPresenter.session.typographyFonts.body
        compare(menu.font.family, body.family, "grid context menu resolves body family")
        compare(menu.font.pixelSize, body.pixelSize, "grid context menu resolves body size")
        compare(copyItem.font.weight, body.weight, "context items inherit body weight")
        compare(copyItem.padding, shell.shellPresenter.session.layoutSpaces.one,
                "context-item padding follows the One token")
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
        settings.setString("theme.mode", "dark-neutral-high")
        shell.shellPresenter.restoreAppearance()
        verify(waitForNative(function() {
            return copyItem.background.color.toString().toUpperCase() === "#424242"
        }, 3000), "menu chrome follows the theme switch")
        compare(copyItem.foreground.toString().toUpperCase(), "#A0A0A0",
                "menu ink follows the theme switch")
        closeThemedShell()
    }
}
