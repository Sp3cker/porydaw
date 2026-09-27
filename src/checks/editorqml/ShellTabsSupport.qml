import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait
import "ShellTabsRenderingSupport.js" as Rendering

TestCase {
    id: testCase
    name: "ShellTabs"
    when: windowShown
    width: 1100
    height: 720
    visible: true
    property var shell: null
    readonly property var settings: fixtureBootstrap.preferences
    property alias bootstrap: fixtureBootstrap
    property alias fileProbe: fixtureProbe
    property alias shellComponent: fixtureShellComponent
    property alias tabBodyMetrics: fixtureBodyMetrics

    ShellQmlBootstrap { id: fixtureBootstrap }
    TabsDrawerProbe { id: fixtureProbe }

    Component { id: fixtureShellComponent; ShellWindow { width: 1100; height: 720; visible: true } }
    FontMetrics {
        id: fixtureBodyMetrics
        font: shell ? Qt.font(shell.shellPresenter.session.typographyFonts.body)
                    : Qt.font({family: "Atkinson Hyperlegible Next"})
    }
    function init() {
        verify(bootstrap.resetPreferences(), "each shell starts with fresh window state")
    }

    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            var settled = false
            for (var step = 0; step < 12 && !settled; ++step) {
                var gate = waitForNative(function() {
                    return shell.shellPresenter.closeReady
                        || shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                        || shell.shellPresenter.session.songTabs.pendingCloseBankTitle.length > 0
                }, 5000)
                if (!gate)
                    break
                if (shell.shellPresenter.closeReady) {
                    settled = true
                    break
                }
                shell.shellPresenter.session.songTabs.confirmDiscard()
                wait(50)
            }
            verify(shell.shellPresenter.closeReady,
                   "teardown waits for scene destruction and grid detach")
        }
        shell.destroy()
        shell = null
        wait(0)
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openDiagnostics(session) {
        var labels = []
        for (var i = 0; i < session.songCount() && i < 8; ++i)
            labels.push(session.songLabel(i))
        return " (projectRoot=" + bootstrap.projectRoot
            + "; projectOpen=" + session.projectOpen
            + "; songOpen=" + session.songOpen
            + "; stagedLabels=[" + labels.join(",") + "]"
            + "; lastSaveError=" + session.lastSaveError
            + "; status=" + shell.shellPresenter.statusText + ")"
    }

    function seedDrawerPrefs() {
        settings.setBool("editorDrawer.velocityVisible", true)
        settings.setInt("editorDrawer.velocityHeight", 173)
        settings.setBool("editorDrawer.automationVisible", true)
        settings.setInt("editorDrawer.automationHeight", 200)
        settings.setBool("editorDrawer.voiceChangesVisible", true)
        settings.setInt("editorDrawer.voiceChangesHeight", 200)
        settings.setString("editorDrawer.activePage", "velocity")
    }
    function openShell(labels) {
        settings.setString("lastProjectDir", "")
        seedDrawerPrefs()
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        var toolbar = findChild(shell, "transportToolbar")
        verify(toolbar !== null && toolbar.height > 0, "mounted transport has a measured height")
        shell.height += toolbar.height
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, labels[0])
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "the first song loads" + openDiagnostics(session))
        var ids = []
        tryCompare(session.songTabs, "tabCount", 1)
        ids.push(session.songTabs.selectedId)
        waitForPage(ids[0])
        for (var i = 1; i < labels.length; ++i) {
            session.openSong(labels[i])
            var expected = i + 1
            verify(waitForNative(function() {
                return session.songTabs.tabCount === expected
                    || session.lastSaveError.length > 0
            }, 30000), labels[i] + " appends a tab" + openDiagnostics(session))
            ids.push(session.songTabs.selectedId)
            waitForPage(ids[i])
        }
        return ids
    }

    function waitForPage(tabId) {
        var session = shell.shellPresenter.session
        verify(waitForNative(function() {
            var grid = testCase.gridOf(tabId)
            return grid !== null && grid.renderedNoteCount > 0
        }, 30000), "tab " + tabId + " publishes its rendered grid"
            + openDiagnostics(session))
        waitForRendering(tabsRoot())
    }

    function tabs() { return shell.shellPresenter.session.songTabs }
    function session() { return shell.shellPresenter.session }
    function tabsRoot() { return shell.sceneLoader.item }
    function strip() { return findChild(tabsRoot(), "songTabStrip") }
    function pages() { return findChild(tabsRoot(), "songTabPages") }
    function selectButton(tabId) { return findChild(tabsRoot(), "songTabSelect_" + tabId) }
    function closeButton(tabId) { return findChild(tabsRoot(), "songTabClose_" + tabId) }
    function scrollLeft() { return findChild(tabsRoot(), "songTabScrollLeft") }
    function scrollRight() { return findChild(tabsRoot(), "songTabScrollRight") }
    function pageOf(tabId) { return findChild(pages(), "songTab_" + tabId) }
    function surfaceOf(tabId) {
        var page = pageOf(tabId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }
    function gridOf(tabId) {
        var surface = surfaceOf(tabId)
        return surface ? surface.gridModel : null
    }
    function summaryOf(tabId) { return gridOf(tabId).noteSummary }
    function dialogButton(name) {
        var button = findChild(shell, name)
        if (button)
            return button
        var matches = collectAll(name)
        return matches.length > 0 ? matches[0] : null
    }
    function awaitGateButtons() {
        return waitForNative(function() {
            var save = dialogButton("songTabSave")
            var discard = dialogButton("songTabDiscard")
            var cancel = dialogButton("songTabCancel")
            return save !== null && discard !== null && cancel !== null
                && save.visible && discard.visible && cancel.visible
        }, 5000)
    }
    function collectByPrefix(item, prefix, found) {
        var collected = found || []
        if (!item)
            return collected
        if (String(item.objectName).indexOf(prefix) === 0)
            collected.push(item)
        if (!item.children)
            return collected
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectByPrefix(item.children[i], prefix, collected)
        return collected
    }

    function collectByName(item, name, found) {
        var collected = found || []
        if (!item)
            return collected
        if (item.objectName === name)
            collected.push(item)
        if (!item.children)
            return collected
        for (var i = 0; i < item.children.length; ++i)
            testCase.collectByName(item.children[i], name, collected)
        return collected
    }

    function tabOrderIds() {
        var buttons = testCase.collectByPrefix(tabsRoot(), "songTabSelect_", [])
        buttons.sort(function(a, b) { return a.x - b.x })
        return buttons.map(function(item) {
            return parseInt(String(item.objectName).slice("songTabSelect_".length), 10)
        })
    }

    function tabButtonVisible(tabId) {
        var button = selectButton(tabId)
        var stripItem = strip()
        if (!button || !stripItem || !button.visible)
            return false
        var visibleWidth = stripItem.width
        var left = scrollLeft()
        if (left && left.visible)
            visibleWidth = stripItem.width - left.parent.width
        var buttonLeft = button.x
        var buttonRight = button.x + button.width
        var viewportX = stripViewport().contentX
        return buttonLeft >= viewportX - 0.5
            && buttonRight <= viewportX + visibleWidth + 0.5
    }

    function stripViewport() {
        var stripItem = strip()
        for (var i = 0; i < stripItem.children.length; ++i) {
            var child = stripItem.children[i]
            if (child.contentX !== undefined && child.contentWidth !== undefined)
                return child
        }
        return null
    }

    function revealTab(tabId) {
        var button = selectButton(tabId)
        verify(button, "tab " + tabId + " has a strip button")
        var stripItem = strip()
        var center = stripItem.width / 2
        for (var attempt = 0; attempt < 64 && !tabButtonVisible(tabId); ++attempt) {
            var origin = button.mapToItem(stripItem, button.width / 2, button.height / 2)
            var pointsLeft = origin.x < center
            var control = pointsLeft ? scrollLeft() : scrollRight()
            verify(control && control.visible,
                   "the strip exposes a scroll control toward tab " + tabId)
            verify(control.enabled, "the scroll control is enabled before tab "
                   + tabId + " is revealed")
            mouseClick(control, control.width / 2, control.height / 2)
            wait(50)
        }
        verify(tabButtonVisible(tabId),
               "the strip's scroll controls revealed tab " + tabId)
    }

    function clickSelectTab(tabId) {
        revealTab(tabId)
        var button = selectButton(tabId)
        mouseClick(button, button.width / 3, button.height / 2)
        verify(waitForNative(function() {
            var page = pageOf(tabId)
            return tabs().selectedId === tabId && page !== null && page.visible
        }, 5000), "clicking tab " + tabId + " selects its page")
    }

    function pointFor(tabId, tick, pitch) { return Rendering.pointFor(testCase, tabId, tick, pitch) }
    function drawNote(tabId) { return Rendering.drawNote(testCase, tabId) }
    function regionOf(image, anchor, control) {
        return Rendering.regionOf(testCase, image, anchor, control)
    }
    function collectAll(prefix) { return Rendering.collectAll(testCase, prefix) }
    function channelsOf(color) { return Rendering.channelsOf(testCase, color) }
    function pixelDistance(image, x, y, target) {
        return Rendering.pixelDistance(testCase, image, x, y, target)
    }
    function changedPixels(before, after, region, limit) {
        return Rendering.changedPixels(testCase, before, after, region, limit)
    }
    function imagePixelDiffers(before, after, x, y) {
        return Rendering.imagePixelDiffers(testCase, before, after, x, y)
    }
    function matchingColorCount(image, region, target, tolerance) {
        return Rendering.matchingColorCount(testCase, image, region, target, tolerance)
    }
    function grabRegionStable(item, region) {
        return Rendering.grabRegionStable(testCase, item, region)
    }
    function grabUntilDifferent(item, reference, region) {
        return Rendering.grabUntilDifferent(testCase, item, reference, region)
    }
    function volumeAxisLabels(tabId) { return Rendering.volumeAxisLabels(testCase, tabId) }
}
