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
        settings.setValue("lastProjectDir", "")
        settings.sync()
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
        tryCompare(timeMenu, "rowCount", 9)
        tryVerify(function() { return timeMenu.rowItem(3) !== null && timeMenu.rowItem(7) !== null }, 3000)
        compare(timeMenu.rowItem(3).itemData.actionId, 2)
        compare(timeMenu.rowItem(3).itemData.enabled, true)
        compare(timeMenu.rowItem(7).itemData.actionId, 9)
        compare(timeMenu.rowItem(7).itemData.enabled, true)
        clickRow(timeMenu, 7)
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

    function test_shiftRightRollSweepOpensCanonicalTimeMenu() {
        var session = openSong()
        var roll = control("swiftRollInput")
        var grid = surface().gridModel
        var startX = roll.width * 0.3
        var endX = roll.width * 0.6
        var midX = (startX + endX) / 2
        var notes = JSON.parse(grid.noteSummary)
        var y = -1
        for (var row = Math.ceil(grid.cameraScrollY / grid.rowHeight);
             row < Math.min(128, Math.floor((grid.cameraScrollY + roll.height) / grid.rowHeight));
             ++row) {
            var pitch = 127 - row
            var occupied = notes.some(function(note) {
                var left = note.tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
                var right = (note.tick + note.duration) * grid.beatWidth
                    / grid.ticksPerBeat - grid.cameraScrollX
                return note.pitch === pitch && left < endX && right > startX
            })
            if (!occupied) {
                y = (row + 0.5) * grid.rowHeight - grid.cameraScrollY
                break
            }
        }
        verify(y > 0 && y < roll.height, "an empty visible roll row is available")
        var revision = grid.appliedRevisionText
        mousePress(roll, startX, y, Qt.RightButton, Qt.ShiftModifier)
        mouseMove(roll, endX, y, -1, Qt.RightButton, Qt.ShiftModifier)
        compare(session.gridCommandAvailable(0), true, "Copy is available during the sweep")
        compare(session.gridCommandAvailable(2), true, "Duplicate Time is available during the sweep")
        compare(session.gridCommandAvailable(17), true, "Clear Time Selection is available during the sweep")
        mouseRelease(roll, endX, y, Qt.RightButton, Qt.ShiftModifier)
        compare(grid.appliedRevisionText, revision, "sweeping selection does not edit notes")
        mouseClick(roll, midX, y, Qt.RightButton)
        var menu = panel()
        tryCompare(menu, "rowCount", 9)
        compare(menu.rowItem(0).itemData.actionId, 11)
        verify(menu.rowItem(0).itemData.enabled,
               "Copy is enabled in the rendered time menu after sweep")
        compare(menu.rowItem(4).itemData.actionId, 6)
        verify(menu.rowItem(4).itemData.enabled,
               "Duplicate Time is enabled in the rendered time menu after sweep")
        keyClick(Qt.Key_Escape)
        tryCompare(surface().rulerMenu, "isOpen", false)
    }

    function test_rulerLoopAndSelectedTimeRowsExecuteFromRenderedPanels() {
        openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var menuOwner = surface().rulerMenu
        var y = ruler.height * 0.75
        var startX = ruler.width * 0.28
        var endX = ruler.width * 0.55
        var midX = (startX + endX) / 2
        var before = grid.appliedRevisionText

        mouseClick(ruler, startX, y, Qt.RightButton)
        var menu = panel()
        tryVerify(function() { return menu.rowItem(3) !== null }, 3000)
        compare(menu.rowItem(3).itemData.actionId, 2)
        clickRow(menu, 3)
        tryCompare(menuOwner, "isOpen", false)
        tryVerify(function() { return grid.appliedRevisionText !== before }, 3000)
        tryCompare(ruler, "activeFocus", true)
        mouseClick(ruler, startX, y, Qt.RightButton)
        menu = panel()
        tryVerify(function() { return menu.rowItem(5) !== null }, 3000)
        compare(menu.rowItem(5).itemData.actionId, 4)
        compare(menu.rowItem(5).itemData.enabled, true)
        before = grid.appliedRevisionText
        clickRow(menu, 5)
        tryVerify(function() { return grid.appliedRevisionText !== before }, 3000)
        tryCompare(menuOwner, "isOpen", false)
        tryVerify(function() { return findChild(surface(), "quickMenuPanelRoot") === null }, 3000)

        mousePress(ruler, startX, y, Qt.LeftButton)
        mouseMove(ruler, endX, y, -1, Qt.LeftButton)
        mouseRelease(ruler, endX, y, Qt.LeftButton)
        mouseClick(ruler, midX, y, Qt.RightButton)
        menu = panel()
        tryVerify(function() { return menu.rowItem(0) !== null }, 3000)
        compare(menu.rowItem(0).itemData.actionId, 5)
        compare(menu.rowItem(0).itemData.enabled, true)
        before = grid.appliedRevisionText
        clickRow(menu, 0)
        tryVerify(function() { return grid.appliedRevisionText !== before }, 3000)

        var roll = control("swiftRollInput")
        mouseClick(roll, midX, roll.height * 0.5, Qt.RightButton)
        menu = panel()
        tryCompare(menu, "rowCount", 9)
        tryVerify(function() { return menu.rowItem(4) !== null && menu.rowItem(8) !== null }, 3000)
        compare(menu.rowItem(0).itemData.actionId, 11)
        compare(menu.rowItem(0).itemData.enabled, true)
        compare(menu.rowItem(4).itemData.actionId, 6)
        compare(menu.rowItem(4).itemData.enabled, true)
        before = grid.appliedRevisionText
        clickRow(menu, 8)
        tryCompare(menuOwner, "isOpen", false)
        tryCompare(roll, "activeFocus", true)
        compare(grid.appliedRevisionText, before)
        mouseClick(ruler, midX, y, Qt.RightButton)
        menu = panel()
        tryVerify(function() { return menu.rowItem(3) !== null }, 3000)
        compare(menu.rowItem(3).itemData.actionId, 2)
        keyClick(Qt.Key_Escape)
        tryCompare(menuOwner, "isOpen", false)
        tryCompare(ruler, "activeFocus", true)
    }
    function test_rulerInsertTimeOpensExistingPromptAndCommitsBars() {
        openSong()
        var ruler = control("timelineRulerInput")
        var menuOwner = surface().rulerMenu
        var grid = surface().gridModel
        var x = ruler.width * 0.28
        var y = ruler.height * 0.75
        var before = grid.appliedRevisionText
        mouseClick(ruler, x, y, Qt.RightButton)
        var menu = panel()
        compare(menu.rowItem(0).itemData.enabled, true)
        compare(menu.rowItem(0).itemData.actionId, 1)
        clickRow(menu, 0)
        tryCompare(menuOwner, "isOpen", false)
        tryCompare(menuOwner, "insertTimePromptOpen", true)
        tryVerify(function() { return findChild(surface(), "insertTimePrompt") !== null }, 3000)
        verify(findChild(surface(), "insertTimeBars") !== null)
        verify(findChild(surface(), "insertTimeBeats") !== null)
        verify(findChild(surface(), "insertTimeBeatFractions") !== null)
        compare(grid.appliedRevisionText, before)
        tryVerify(function() { return findChild(surface(), "insertTimeCancel") !== null }, 3000)
        mouseClick(control("insertTimeCancel"))
        tryCompare(menuOwner, "insertTimePromptOpen", false)
        compare(grid.appliedRevisionText, before)
        mouseClick(ruler, x, y, Qt.RightButton)
        menu = panel()
        clickRow(menu, 0)
        tryCompare(menuOwner, "insertTimePromptOpen", true)
        tryVerify(function() { return findChild(surface(), "insertTimeAccept") !== null }, 3000)
        mouseClick(control("insertTimeAccept"))
        tryCompare(menuOwner, "insertTimePromptOpen", false)
        tryVerify(function() { return grid.appliedRevisionText !== before }, 3000)
    }

}
