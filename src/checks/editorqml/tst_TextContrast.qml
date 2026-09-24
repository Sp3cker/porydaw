import QtCore
import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import "../../ui/shell"
import "TextContrastAudit.js" as Audit

// Text legibility is the product's first visual requirement
// (docs/design/text-contrast.md). Every text item the production shell
// renders — window chrome, docks, drawer, pages, every popup and menu, and the
// settings window — is measured against the pixels drawn behind it, in every
// shipped theme. The offscreen platform supplies Qt's generic light palette,
// so any control text still inheriting the platform palette instead of the
// theme fails on the dark themes.
TestCase {
    id: testCase
    name: "TextContrast"
    when: windowShown
    width: 1280
    height: 800
    visible: true

    property var shell: null
    property var settings: null
    property var failures: []
    property var seenFailures: []
    property int measured: 0

    ShellQmlBootstrap { id: bootstrap }
    Component { id: settingsComponent; Settings {} }
    Component { id: shellComponent; ShellWindow { width: 1280; height: 800; visible: true } }

    readonly property var themes: [
        { mode: "vanilla", window: "#C9C1BB" },
        { mode: "dark-neutral-high", window: "#373737" },
        { mode: "immaterial", window: "#2E3138" },
    ]

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        settings = settingsComponent.createObject(testCase)
        verify(settings !== null)
        settings.setValue("lastProjectDir", "")
        settings.sync()
    }

    function cleanupTestCase() {
        if (settings) {
            settings.destroy()
            settings = null
            wait(0)
        }
        verify(bootstrap.clearSettings())
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
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "closing reaches the dirty gate or completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() {
                return shell.shellPresenter.closeReady
            }, 5000), "the scene is released")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function openShell() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
    }

    function applyTheme(theme) {
        shell.shellPresenter.restoreAppearance(theme.mode, "50", Qt.application.name)
        const palette = shell.shellPresenter.session.palette
        verify(waitForNative(function() {
            return palette.windowBackground === theme.window
        }, 3000), theme.mode + " is applied")
        waitForRendering(shell.contentItem)
    }

    function grab(root) {
        waitForRendering(root)
        return grabImage(root)
    }

    // One line per distinct theme/item/text/ink/surface; the first state that
    // showed it names it. Each line is also logged, since QTest truncates long
    // failure messages.
    function record(context, result) {
        measured += result.measured
        for (const failure of result.failures) {
            const key = [context.split(" ")[0], failure.where, failure.text,
                         failure.fg, failure.bg].join("|")
            if (seenFailures.indexOf(key) >= 0)
                continue
            seenFailures.push(key)
            const line = Audit.format(context, failure)
            console.warn("contrast: " + line)
            failures.push(line)
        }
    }

    function auditWindow(context) {
        const result = Audit.audit(shell.contentItem, grab,
                                   [].concat(Array.from(shell.data), [shell.menuBar]))
        record(context, result)
        return result.popups
    }

    function popupItem(popup) {
        return popup.background ? popup.background.parent : popup.contentItem.parent
    }

    // Opens every popup the window owns — menus, combo lists, prompts — one
    // at a time and audits only its own surface.
    function auditPopups(context, popups) {
        const done = []
        const queue = popups.slice()
        while (queue.length > 0) {
            const popup = queue.shift()
            if (done.indexOf(popup) >= 0)
                continue
            done.push(popup)
            // A disabled owner (combo, button) cannot open its popup.
            if (popup.parent && popup.parent.enabled === false)
                continue
            popup.open()
            if (!waitForNative(function() { return popup.opened }, 1000)) {
                popup.close()
                continue
            }
            const surface = popupItem(popup)
            if (surface) {
                const result = Audit.audit(surface, grab)
                record(context + " popup " + (popup.objectName || Audit.describe(surface)),
                       result)
                for (const nested of result.popups)
                    queue.push(nested)
            }
            popup.close()
            waitForNative(function() { return !popup.visible }, 1000)
        }
    }

    function auditSettings(context) {
        const dialog = findChild(shell, "shellSettingsDialog")
        verify(dialog !== null, "settings window exists")
        shell.shellPresenter.activate("edit.engine_settings")
        tryCompare(dialog, "visible", true, 3000)
        for (let tab = 0; tab < 2; ++tab) {
            if (tab === 1 && !findChild(dialog, "settingsSongTab").enabled)
                continue
            dialog.selectedTab = tab
            const result = Audit.audit(dialog.contentItem, grab)
            record(context + " settings tab " + tab, result)
            auditPopups(context + " settings tab " + tab, result.popups)
        }
        dialog.close()
        tryCompare(dialog, "visible", false, 3000)
    }

    function report(label) {
        verify(measured > 0, label + ": text items were measured")
        verify(failures.length === 0, label + ": " + failures.length
               + " text items below the WCAG AA floor (of " + measured + " measured):\n"
               + failures.join("\n"))
    }

    function resetTally() {
        failures = []
        seenFailures = []
        measured = 0
    }

    // One row per shipped theme; the runner gives each row its own process.
    function themeRows() {
        return themes.map(function(theme) { return { tag: theme.mode, theme: theme } })
    }

    function test_emptyShellText_data() { return themeRows() }

    function test_emptyShellText(data) {
        resetTally()
        openShell()
        applyTheme(data.theme)
        auditPopups(data.tag + " empty", auditWindow(data.tag + " empty"))
        auditSettings(data.tag + " empty")
        report(data.tag + " empty shell")
    }

    function test_songShellText_data() { return themeRows() }

    function test_songShellText(data) {
        resetTally()
        openShell()
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song load settles")
        verify(session.songOpen, session.lastSaveError)
        applyTheme(data.theme)
        const presenter = shell.shellPresenter
        const mode = data.tag
        session.voiceListController().selectSlot(0)
        auditPopups(mode + " song", auditWindow(mode + " song"))

        presenter.activate("view.polyphony_debugger")
        tryVerify(function() {
            const dock = findChild(shell, "shellPolyphonyDock")
            return dock !== null && dock.visible
        }, 3000, "polyphony dock opens")
        auditWindow(mode + " polyphony")
        presenter.activate("view.polyphony_debugger")

        presenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        auditPopups(mode + " events", auditWindow(mode + " events"))
        presenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", false, 3000)

        auditSettings(mode + " song")
        report(mode + " song shell")
    }
}
