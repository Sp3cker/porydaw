import QtQuick
import QtQuick.Controls
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import "../../ui/shell"
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellEventList"
    when: windowShown
    width: 1100
    height: 720
    visible: true

    property var shell: null
    readonly property var settings: bootstrap.preferences
    property var typographyPage: null
    property alias bootstrap: bootstrapObject
    property alias tickEditorFontInfo: tickEditorFontInfoObject
    property alias eventTableMetrics: eventTableMetricsObject
    property alias copySpy: copySpyObject
    property alias shellComponent: shellFactory
    FontInfo {
        id: tickEditorFontInfoObject
        font: Qt.application.font
    }
    FontMetrics {
        id: eventTableMetricsObject
        font: typographyPage ? typographyPage.tableFont : Qt.application.font
    }
    ShellQmlBootstrap { id: bootstrapObject }
    SignalSpy { id: copySpyObject; signalName: "activated" }
    Component {
        id: shellFactory
        ShellWindow { width: 1100; height: 720; visible: true }
    }

    function init() {
        verify(bootstrap.resetPreferences(), "each shell starts with fresh window state")
    }

    function waitForNative(predicate, timeoutMs) {
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
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
        copySpy.target = null
        typographyPage = null
        shell.destroy()
        shell = null
        wait(0)
    }
    function openEventListFixture() {
        settings.setString("lastProjectDir", "")
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        const session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), "event-list fixture loads")
        verify(session.songOpen, session.lastSaveError)
        shell.shellPresenter.activate("view.event_list")
        tryCompare(session.songTabs, "selectedTabShowsEvents", true, 3000)
        let page = null
        tryVerify(function() {
            page = findChild(shell.sceneLoader.item, "eventListPage")
            return page !== null && page.visible
        }, 3000, "event-list page mounts")
        const table = findChild(page, "eventListTable")
        verify(table, "event-list table mounts")
        return { session: session, page: page, table: table,
                 presenter: session.eventListPresenter() }
    }
    function cellAt(table, row, column) {
        table.positionViewAtRow(row, TableView.Contain)
        table.forceLayout()
        tryVerify(function() {
            return table.itemAtCell(Qt.point(column, row)) !== null
        }, 3000, "the target event cell is rendered")
        return table.itemAtCell(Qt.point(column, row))
    }
}
