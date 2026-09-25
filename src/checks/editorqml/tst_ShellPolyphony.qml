import QtQuick
import QtQuick.Controls
import QtTest
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellPolyphony"
    when: windowShown
    width: 960
    height: 760
    visible: true
    property var shell: null
    property var referencePane: null

    ShellQmlBootstrap { id: bootstrap }
    PolyphonyShellProbe { id: probe }
    Component { id: shellComponent; ShellWindow { width: 960; height: 820; visible: true } }
    Component { id: referenceComponent; PolyphonyPanel {} }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function createShell() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        shell = shellComponent.createObject(null)
        verify(shell, "the production shell mounts")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        return shell.shellPresenter
    }

    function cleanup() {
        if (referencePane) {
            referencePane.destroy()
            referencePane = null
        }
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            verify(waitForNative(function() {
                return shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                    || !shell.shellPresenter.sceneActive
            }, 5000), "the close gate completes")
            if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                shell.shellPresenter.session.songTabs.confirmDiscard()
            verify(waitForNative(function() { return shell.shellPresenter.closeReady }, 5000),
                   "the shell retires its editor scene")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function cleanupTestCase() {
        verify(bootstrap.clearSettings(), "the private polyphony settings domain is removed")
    }

    function panel() { return findChild(shell, "polyphonyPanel") }
    function dock() { return findChild(shell, "shellPolyphonyDock") }

    function test_viewActionAndEventNavigation() {
        var presenter = createShell()
        var session = presenter.session
        var poly = session.polyphony
        verify(!presenter.polyphonyVisible && !dock().visible,
               "the debugger starts hidden")
        compare(presenter.actionLabel("view.polyphony_debugger"), "Polyphony Debugger")
        verify(presenter.actionEnabled("view.polyphony_debugger"),
               "the View action is enabled before a document opens")
        presenter.activate("view.polyphony_debugger")
        tryVerify(function() { return presenter.polyphonyVisible }, 3000,
                  "ShellPresenter.activate toggles the tracked dock visibility")
        tryVerify(function() { return dock().visible }, 3000,
                  "ShellWindow dock reacts to the presenter visibility change")
        var mountedPanel = panel()
        verify(mountedPanel !== null && mountedPanel !== undefined,
               "PolyphonyPanel exists as a direct child of ShellWindow, outside the scene Loader")
        tryVerify(function() { return mountedPanel.visible }, 3000,
                  "the mounted polyphony pane follows its dock")
        var checkbox = findChild(panel(), "polyphonyInvert")
        verify(checkbox, "invert checkbox is mounted")
        mouseClick(checkbox, checkbox.width / 2, checkbox.height / 2)
        verify(poly.invertChecked, "the checkbox changes the renderer setting")
        var close = findChild(dock(), "shellPolyphonyClose")
        mouseClick(close, close.width / 2, close.height / 2)
        tryVerify(function() { return !presenter.polyphonyVisible }, 3000,
                  "close button dispatches the View action to ShellPresenter")
        tryVerify(function() { return !dock().visible }, 3000,
                  "closing hides the mounted dock and suspends its polling timer")
        verify(poly.invertChecked, "closing preserves the invert checkbox state")
        presenter.activate("view.polyphony_debugger")
        tryVerify(function() { return dock().visible }, 3000,
                  "the View action reopens the dock")
        verify(checkbox.checked, "reopening restores the checked option")

        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "song loading completes")
        verify(session.songOpen, "the mounted panel has a live document")

        var fixture = probe.fixturePresenter()
        referencePane = referenceComponent.createObject(testCase, {
            presenter: fixture, colors: session.palette, applicationFont: shell.font,
            width: 380, height: 600
        })
        verify(referencePane, "the production pane accepts the isolated diagnostic fixture")
        var row = findChild(referencePane, "polyphonyEventRow_2")
        verify(row, "the positioned event is rendered in the production log")
        var scroll = findChild(referencePane, "polyphonyScroll")
        scroll.contentY = Math.max(0, scroll.contentHeight - scroll.height)
        verify(waitForPolish(referencePane), "event log scrolls into the visible pane")
        var location = row.mapToItem(referencePane, 0, 0)
        verify(location.y >= 0 && location.y + row.height <= referencePane.height,
               "the positioned event row receives actual pointer input")
        var live = findChild(referencePane, "polyphonyEventRow_0")
        compare(probe.lastJumpTick(), -1, "no event has requested a navigation")
        mouseClick(live, live.width / 2, live.height / 2)
        compare(probe.lastJumpTick(), -1,
                "live overflow cannot request a document cursor jump")
        mouseClick(row, row.width / 2, row.height / 2)
        compare(probe.lastJumpTick(), 96,
                "clicking a positioned log row requests the event's document tick")
        var reset = findChild(referencePane, "polyphonyReset")
        mouseClick(reset, reset.width / 2, reset.height / 2)
        compare(fixture.eventCount, 0, "Reset clears visible diagnostic events")
        presenter.activate("view.polyphony_debugger")
        tryVerify(function() { return !dock().visible }, 3000,
                  "the same View action hides the mounted panel")
    }

    function compareRegion(reference, name, target, tolerance) {
        var expected = reference.regions.filter(function(region) { return region.name === name })[0]
        verify(expected, "widget baseline contains " + name)
        verify(target, "production pane exposes " + name)
        var position = target.mapToItem(referencePane, 0, 0)
        verify(Math.abs(position.x - expected.x) <= tolerance
            && Math.abs(position.y - expected.y) <= tolerance,
            name + " preserves widget position within " + tolerance + " px: "
            + position.x + "," + position.y + " vs " + expected.x + "," + expected.y)
        verify(Math.abs(target.width - expected.w) <= tolerance
            && Math.abs(target.height - expected.h) <= tolerance,
            name + " preserves widget size within " + tolerance + " px: "
            + target.width + "×" + target.height + " vs " + expected.w + "×" + expected.h)
    }

    function test_visualProfiles() {
        var profile = probe.profileName
        verify(typeof profile === "string",
               "profileName must bridge as a String; check PolyphonyShellProbe registration")
        if (profile.length === 0)
            skip("profile captures run in dedicated DPR children")
        var px = profile.indexOf("font16") >= 0 ? 16 : 12
        var presenter = createShell()
        shell.font.pixelSize = px
        var fixture = probe.fixturePresenter()
        referencePane = referenceComponent.createObject(testCase, {
            presenter: fixture, colors: presenter.session.palette,
            applicationFont: shell.font, width: 380, height: 600
        })
        var pane = referencePane
        verify(pane, "the production polyphony pane mounts with the isolated fixture")
        var states = ["narrow-vanilla", "wide-vanilla",
                      "narrow-darkneutralhigh", "wide-darkneutralhigh"]
        for (var i = 0; i < states.length; ++i) {
            var state = states[i]
            var json = probe.baseline(profile, state)
            verify(typeof json === "string" && json.length > 0,
                   state + " fixture is missing for " + profile
                   + " under src/checks/fixtures/visual/macos-" + profile + "/polyphony/")
            presenter.restoreAppearance(state.indexOf("darkneutralhigh") >= 0
                ? "dark-neutral-high" : "vanilla", "50", Qt.application.name)
            var baseline = JSON.parse(json)
            testCase.width = Math.max(testCase.width, baseline.image.width + 16)
            testCase.height = Math.max(testCase.height, baseline.image.height + 16)
            pane.width = baseline.image.width
            pane.height = baseline.image.height
            verify(waitForPolish(pane), "pane geometry settles before capture")
            var usageGroups = findChild(pane, "polyphonyUsageSection").children[1].children
            for (var group = 0; group < usageGroups.length; ++group) {
                if (usageGroups[group].children.length > 1)
                    verify(waitForPolish(usageGroups[group].children[1]),
                           "channel flow relayout settles at the profile width")
            }
            compare(pane.applicationFont.pixelSize, px, "the requested font reaches the production pane")
            compare(pane.Screen.devicePixelRatio, baseline.image.dpr,
                    "the profile child renders at the widget baseline DPR")
            compare(Math.round(pane.width), baseline.image.width, "the pane matches widget width")
            compare(Math.round(pane.height), baseline.image.height, "the pane matches widget height")
            compare(pane.wideLayout, state.indexOf("wide-") === 0,
                    "the widget's responsive breakpoint matches the frozen profile")
            verify(waitForPolish(pane), "fixture channel rows settle before geometry comparison")
            compareRegion(baseline, "poly.invert", findChild(pane, "polyphonyInvert"), px / 2)
            compareRegion(baseline, "poly.overflow-heading", findChild(pane, "polyphonyOverflowHeading"), px)
            compareRegion(baseline, "poly.overflow-table", findChild(pane, "polyphonyOverflowTable"), px * 2)
            compareRegion(baseline, "poly.overflow-row.0", findChild(pane, "polyphonyOverflowRow_0"), px)
            compareRegion(baseline, "poly.event-log", findChild(pane, "polyphonyEventLog"), px * 2)
            compareRegion(baseline, "poly.log-row.0", findChild(pane, "polyphonyEventRow_0"), px)
            compareRegion(baseline, "poly.usage-heading", findChild(pane, "polyphonyUsageHeading"), px)
            compareRegion(baseline, "poly.overflow-section", findChild(pane, "polyphonyOverflowSection"), px * 2)
            compareRegion(baseline, "poly.log-heading", findChild(pane, "polyphonyLogHeading"), px * 2)
            verify(waitForPolish(pane), "rich snapshot paints")
            var saved = false
            pane.grabToImage(function(result) {
                saved = result.saveToFile("file://" + probe.artifactPath(bootstrap.projectRoot,
                                                                         profile, state))
            })
            tryVerify(function() { return saved }, 5000,
                      state + " production pane captured against widget baseline")
        }
    }
}
