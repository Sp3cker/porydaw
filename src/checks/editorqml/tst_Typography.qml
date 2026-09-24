import QtCore
import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui

TestCase {
    id: testCase
    name: "Typography"
    when: windowShown
    width: 960
    height: 640
    visible: true

    property var shell: null

    ShellQmlBootstrap { id: bootstrap }
    Component { id: bodyTextComponent; Text { text: "probe" } }
    Component { id: shellComponent; ShellWindow { visible: true } }
    FontMetrics { id: normalTitleCheck }
    FontMetrics { id: boldTitleCheck }

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
    }

    function cleanupTestCase() {
        verify(bootstrap.clearSettings(), "removed only the private native settings")
    }

    function cleanup() {
        if (!shell)
            return
        shell.destroy()
        shell = null
        wait(0)
    }

    function waitForNative(predicate, timeoutMs) {
        var deadline = Date.now() + timeoutMs
        while (!predicate() && Date.now() < deadline) {
            bootstrap.pumpMainRunLoop()
            wait(10)
        }
        return predicate()
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

    function openOneSongShell() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000)
        verify(session.songOpen, "Route 101 loads from the staged project"
               + openDiagnostics(session))
        tryCompare(session.songTabs, "tabCount", 1)
        tryVerify(function() {
            var surface = selectedSurface()
            return surface !== null && surface.visible && surface.width > 0
        }, 5000, "the real tab page is mounted and drawn")
    }

    function selectedSurface() {
        var pages = shell.sceneLoader.item
        if (!pages)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(pages, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function centersClose(first, second) {
        return Math.abs(first.x - second.x) < 0.01 && Math.abs(first.y - second.y) < 0.01
    }

    function test_bodyFontAndMetrics() {
        shell = shellComponent.createObject(null)
        verify(shell !== null, "the production ShellWindow loads")
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        compare(Qt.application.organization, "sp3cker",
                "the shell keeps the production organization identity")
        compare(shell.title, "Porydaw", "the shell keeps the production title")
        tryVerify(function() {
            return shell.font.family === "Atkinson Hyperlegible Next"
        }, 5000, "the resolved base font carries the bundled Next family")
        compare(shell.font.pixelSize, shell.bodyFontPx,
                "the base font resolves to the threaded body size")
        compare(shell.font.hintingPreference, Font.PreferNoHinting,
                "the base font prefers no hinting")
        compare(shell.font.weight, Font.Normal, "the base font keeps Normal weight")
        compare(shell.font.features["tnum"], 1, "the base font enables tabular figures")
        verify(shell.bodyFontPx >= 1, "the threaded body size is never degenerate")
        compare(shell.width, shell.bodyFontPx * 72,
                "window width threads the body size into geometry")
        compare(shell.height, shell.bodyFontPx * 48,
                "window height threads the body size into geometry")
        var label = bodyTextComponent.createObject(shell.contentItem)
        verify(label !== null, "a body-text probe mounts in the real window")
        label.font = shell.font
        compare(label.font.family, "Atkinson Hyperlegible Next",
                "body text shows the restored Next family")
        label.destroy()
    }

    function test_selectedTitleCentering() {
        openOneSongShell()
        var surface = selectedSurface()
        verify(surface && surface.visible, "the selected production EditorSurface is visible")
        var headers = findChild(surface, "timelineTrackHeaderRows")
        verify(headers && headers.count > 0, "the original track header delegates are mounted")
        normalTitleCheck.font = Qt.font(surface.headersModel.normalTitleFont)
        boldTitleCheck.font = Qt.font(surface.headersModel.boldTitleFont)
        tryVerify(function() {
            for (var i = 0; i < headers.count; ++i) {
                var row = headers.itemAt(i)
                if (!row || !row.titleBold || row.isAddTrack)
                    continue
                var label = boldTitleCheck.elidedText(row.title, Text.ElideRight,
                                                      row.titleRect.width)
                var normal = normalTitleCheck.tightBoundingRect(label)
                var bold = boldTitleCheck.tightBoundingRect(label)
                var offset = row.selectedTitleOffset
                var displayed = {
                    x: bold.x + bold.width / 2 + offset.x,
                    y: bold.y + bold.height / 2 + offset.y
                }
                var reference = {
                    x: normal.x + normal.width / 2,
                    y: normal.y + normal.height / 2
                }
                if (centersClose(displayed, reference))
                    return true
            }
            return false
        }, 5000, "the bold title stays centered on the regular title")
        var row = null
        for (var j = 0; j < headers.count; ++j) {
            var candidate = headers.itemAt(j)
            if (candidate && candidate.titleBold && !candidate.isAddTrack) {
                row = candidate
                break
            }
        }
        verify(row !== null, "a selected bold title row is mounted")
        compare(row.titleFont.features["tnum"], 1,
                "the title map emits tabular figures")
        var rendered = bodyTextComponent.createObject(shell.contentItem)
        verify(rendered !== null, "a map-rendered probe mounts in the real window")
        rendered.font = Qt.font(row.titleFont)
        compare(rendered.font.hintingPreference, Font.PreferNoHinting,
                "the rendered title carries the unhinted preference")
        rendered.destroy()
    }
}
