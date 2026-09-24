import QtCore
import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import "../../ui/shell"

TestCase {
    id: testCase
    name: "ShellGridMenu"
    when: windowShown
    width: Math.round(baseMetrics.height * 76)
    height: Math.round(baseMetrics.height * 55)
    visible: true

    property var shell: null
    property var settings: null
    property var timeSigHost: null
    property int promptOpenCount: 0
    property bool menuClosedBeforePrompt: false
    FontMetrics { id: baseMetrics; font: Qt.application.font }

    ShellQmlBootstrap { id: bootstrap }
    Component { id: settingsComponent; Settings {} }
    Component {
        id: shellComponent
        ShellWindow {
            width: testCase.width
            height: testCase.height
            visible: true
        }
    }
    Connections {
        target: testCase.timeSigHost
        function onTimeSigPromptOpenChanged() {
            if (target.timeSigPromptOpen) {
                testCase.promptOpenCount++
                testCase.menuClosedBeforePrompt = !target.timeSigMenuOpen
            }
        }
    }

    function initTestCase() {
        Qt.application.name = bootstrap.settingsApplicationName
        Qt.application.organization = "sp3cker"
        Qt.application.domain = ""
        settings = settingsComponent.createObject(testCase)
        verify(settings !== null)
    }

    function cleanupTestCase() {
        if (settings) {
            settings.destroy()
            settings = null
            wait(0)
        }
        verify(bootstrap.clearSettings())
    }

    function cleanup() {
        if (!shell)
            return
        if (shell.shellPresenter.sceneActive) {
            shell.close()
            for (var step = 0; step < 20 && !shell.shellPresenter.closeReady; ++step) {
                if (shell.shellPresenter.session.songTabs.pendingCloseId >= 0)
                    shell.shellPresenter.session.songTabs.confirmDiscard()
                waitForNative(function() {
                    return shell.shellPresenter.closeReady
                        || shell.shellPresenter.session.songTabs.pendingCloseId >= 0
                }, 5000)
            }
            verify(shell.shellPresenter.closeReady)
        }
        shell.destroy()
        shell = null
        timeSigHost = null
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

    function openSong() {
        shell = shellComponent.createObject(null)
        verify(shell !== null)
        shell.requestActivate()
        tryCompare(shell, "active", true, 3000)
        var session = shell.shellPresenter.session
        session.openProjectAndSong(bootstrap.projectRoot, "mus_route101")
        verify(waitForNative(function() {
            return session.songOpen || session.lastSaveError.length > 0
        }, 30000), session.lastSaveError)
        verify(session.songOpen, session.lastSaveError)
        verify(waitForNative(function() {
            return surface() !== null && surface().gridModel.renderedNoteCount > 0
        }, 10000))
        timeSigHost = surface().timeSigHost
        return session
    }

    function surface() {
        if (!shell || !shell.sceneLoader.item)
            return null
        var tabs = shell.shellPresenter.session.songTabs
        var page = findChild(shell.sceneLoader.item, "songTab_" + tabs.selectedId)
        return page ? findChild(page, "swiftRollOverlay") : null
    }

    function control(name) {
        var item = findChild(surface(), name)
        verify(item !== null)
        return item
    }

    function panel() {
        verify(waitForNative(function() {
            return findChild(surface(), "quickMenuPanelRoot") !== null
        }, 5000))
        return findChild(surface(), "quickMenuPanelRoot")
    }

    function clickRow(menu, row) {
        tryVerify(function() { return menu.rowItem(row) !== null }, 3000)
        var item = menu.rowItem(row)
        verify(item !== null)
        mouseClick(item, item.width / 2, item.height / 2)
    }

    function openGrid(controlName, kind) {
        tryVerify(function() { return findChild(surface(), "quickMenuPanelRoot") === null }, 3000)
        mouseClick(control(controlName))
        tryCompare(surface().gridModel, "gridMenuKind", kind)
        return panel()
    }

    function assertRows(menu, ids, checkedId) {
        tryCompare(menu, "rowCount", ids.length)
        var checkedCount = 0
        for (var index = 0; index < ids.length; ++index) {
            tryVerify(function() { return menu.rowItem(index) !== null }, 3000)
            var row = menu.rowItem(index)
            compare(row.itemData.actionId, ids[index])
            compare(row.itemData.enabled, true)
            compare(row.itemData.checkable, true)
            compare(row.itemData.checked, ids[index] === checkedId)
            if (row.itemData.checked)
                checkedCount++
        }
        compare(checkedCount, 1)
    }

    function test_gridDivisionAndFeelMenusDispatchAndDismiss() {
        openSong()
        var grid = surface().gridModel
        var division = control("timelineRulerDivisionControl")
        var feel = control("timelineRulerFeelControl")
        verify(division.visible && feel.visible)
        var ids = [-4, -3, -2, -1, 0, 1, 2, 3, 4]
        var initialSnap = grid.snapTicks
        var divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        assertRows(divisionMenu, ids, 0)
        compare(grid.gridDivisionControlText, "Auto")
        clickRow(divisionMenu, 1)
        tryCompare(grid, "gridMenuKind", 0)
        tryCompare(grid, "gridDivisionControlText", "÷8")
        verify(grid.snapTicks < initialSnap)

        divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        assertRows(divisionMenu, ids, -3)
        var settledSnap = grid.snapTicks
        clickRow(divisionMenu, 1)
        tryCompare(grid, "gridMenuKind", 0)
        compare(grid.snapTicks, settledSnap)

        var feelMenu = openGrid("timelineRulerFeelControl", 2)
        assertRows(feelMenu, [0, 1], 0)
        compare(grid.gridFeelControlText, "Straight")
        clickRow(feelMenu, 1)
        tryCompare(grid, "gridMenuKind", 0)
        tryCompare(grid, "tripletGrid", true)
        compare(grid.gridFeelControlText, "Triplet")
        feelMenu = openGrid("timelineRulerFeelControl", 2)
        assertRows(feelMenu, [0, 1], 1)
        clickRow(feelMenu, 1)
        tryCompare(grid, "gridMenuKind", 0)
        compare(grid.tripletGrid, true)

        var ruler = control("timelineRulerInput")
        var beforeCursor = grid.editCursorTick
        var beforeSnap = grid.snapTicks
        feelMenu = openGrid("timelineRulerFeelControl", 2)
        var frame = findChild(feelMenu, "quickMenuFrame")
        verify(frame !== null)
        var outside = ruler.mapToItem(surface(), ruler.width * 0.85, ruler.height * 0.75)
        var frameOrigin = frame.mapToItem(surface(), 0, 0)
        verify(outside.x < frameOrigin.x || outside.x > frameOrigin.x + frame.width
               || outside.y < frameOrigin.y || outside.y > frameOrigin.y + frame.height)
        mouseClick(ruler, ruler.width * 0.85, ruler.height * 0.75)
        tryCompare(grid, "gridMenuKind", 0)
        compare(grid.tripletGrid, true)
        compare(grid.editCursorTick, beforeCursor)
        compare(grid.snapTicks, beforeSnap)

        openGrid("timelineRulerDivisionControl", 1)
        keyClick(Qt.Key_Escape)
        tryCompare(grid, "gridMenuKind", 0)
        compare(grid.gridDivisionControlText, "÷8")
        compare(grid.tripletGrid, true)
    }

    function test_actionRowsCloseBeforePromptAndDisabledRowsStayOpen() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        mouseClick(ruler, ruler.width * 0.5, ruler.height * 0.5, Qt.RightButton)
        tryCompare(session, "timeSigMenuOpen", true)
        var timeMenu = panel()
        tryCompare(timeMenu, "rowCount", 1)
        compare(timeMenu.rowItem(0).itemData.actionId, 9)
        compare(timeMenu.rowItem(0).itemData.enabled, true)
        clickRow(timeMenu, 0)
        tryCompare(session, "timeSigMenuOpen", false)
        tryCompare(session, "timeSigPromptOpen", true)
        tryCompare(testCase, "promptOpenCount", 1)
        compare(menuClosedBeforePrompt, true)
        session.cancelTimeSigPrompt()
        tryCompare(session, "timeSigPromptOpen", false)

        var headers = surface().headersModel
        var headerInput = control("timelineTrackHeadersInput")
        var rowY = Math.max(1, headers.rowHeight / 2)
        mouseClick(headerInput, headerInput.width * 0.5, rowY, Qt.RightButton)
        tryCompare(headers, "menuOpen", true)
        var headerMenu = panel()
        tryCompare(headerMenu, "rowCount", 5)
        for (var index = 0; index < 5; ++index) {
            tryVerify(function() { return headerMenu.rowItem(index) !== null }, 3000)
            compare(headerMenu.rowItem(index).itemData.actionId, index + 1)
        }
        var headerRows = control("timelineTrackHeaderRows")
        var beforeRows = headerRows.count
        clickRow(headerMenu, 3)
        tryCompare(headers, "menuOpen", false)
        tryCompare(headerRows, "count", beforeRows + 1)

        for (var attempts = 0; attempts < 20; ++attempts) {
            tryVerify(function() {
                return findChild(surface(), "quickMenuPanelRoot") === null
            }, 3000)
            mouseClick(headerInput, headerInput.width * 0.5, rowY, Qt.RightButton)
            tryCompare(headers, "menuOpen", true)
            headerMenu = panel()
            tryVerify(function() { return headerMenu.rowItem(3) !== null }, 3000)
            var duplicate = headerMenu.rowItem(3)
            verify(duplicate !== null)
            if (!duplicate.itemData.enabled)
                break
            clickRow(headerMenu, 3)
            tryCompare(headers, "menuOpen", false)
        }
        verify(attempts < 20)
        compare(duplicate.itemData.enabled, false)
        var beforeRevision = surface().appliedRevisionText
        clickRow(headerMenu, 3)
        tryCompare(headers, "menuOpen", true)
        compare(surface().appliedRevisionText, beforeRevision)
        keyClick(Qt.Key_Escape)
        tryCompare(headers, "menuOpen", false)
    }
}
