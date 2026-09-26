import QtQuick
import QtTest
import PorydawApp
import ShellQmlCheck 1.0
import Porydaw.Ui
import "NativeWait.js" as NativeWait

TestCase {
    id: testCase
    name: "ShellGridMenu"
    when: windowShown
    width: Math.round(baseMetrics.height * 76)
    height: Math.round(baseMetrics.height * 55)
    visible: true

    property var shell: null
    readonly property var settings: bootstrap.preferences
    property var timeSigHost: null
    property int promptOpenCount: 0
    property bool menuClosedBeforePrompt: false
    FontMetrics { id: baseMetrics; font: Qt.application.font }

    ShellQmlBootstrap { id: bootstrap }
    GridInputClipProbe { id: clipProbe }
    SignalSpy { id: menuCursorSpy; signalName: "editCursorTickChanged" }
    SignalSpy { id: menuStatusSpy; signalName: "statusTextChanged" }
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
        return NativeWait.waitForNative(bootstrap, function(ms) { wait(ms) }, predicate, timeoutMs)
    }

    function openSong() {
        settings.setString("lastProjectDir", "")
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

    function rowTextEqualsControlText(menu, controlText) {
        for (var index = 0; index < menu.rowCount; ++index) {
            var row = menu.rowItem(index)
            if (row.itemData.checked) {
                compare(row.itemData.text, controlText)
                return
            }
        }
        fail("the menu has no checked row")
    }

    function alternateGridMenuId(id) {
        return id === 8 ? 16 : 8
    }

    function test_gridDivisionAndFeelMenusDispatchAndDismiss() {
        var session = openSong()
        var grid = surface().gridModel
        var division = control("timelineRulerDivisionControl")
        var feel = control("timelineRulerFeelControl")
        verify(division.visible && feel.visible)
        var ids = [-1, 4, 8, 16, 32, 0]
        var initialSnap = grid.snapTicks
        var divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        assertRows(divisionMenu, ids, grid.gridSelectionMenuId)
        var texts = ["Auto", "1/4", "1/8", "1/16", "1/32", "Clock"]
        for (var rung = 0; rung < texts.length; ++rung)
            compare(divisionMenu.rowItem(rung).itemData.text, texts[rung])
        compare(grid.gridSelectionMenuId, -1)
        compare(grid.gridDivisionControlText, "Auto")
        rowTextEqualsControlText(divisionMenu, grid.gridDivisionControlText)
        var pickedId = alternateGridMenuId(grid.gridSelectionMenuId)
        var pickedRow = ids.indexOf(pickedId)
        var pickedText = divisionMenu.rowItem(pickedRow).itemData.text
        compare(pickedText, "1/8")
        clickRow(divisionMenu, pickedRow)
        tryCompare(grid, "gridMenuKind", 0)
        tryCompare(grid, "gridSelectionMenuId", pickedId)
        compare(grid.gridDivisionControlText, pickedText)
        verify(grid.snapTicks !== initialSnap)

        divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        assertRows(divisionMenu, ids, grid.gridSelectionMenuId)
        rowTextEqualsControlText(divisionMenu, grid.gridDivisionControlText)
        var settledSnap = grid.snapTicks
        var settledText = grid.gridDivisionControlText
        clickRow(divisionMenu, pickedRow)
        tryCompare(grid, "gridMenuKind", 0)
        compare(grid.gridSelectionMenuId, pickedId)
        compare(grid.gridDivisionControlText, settledText)
        compare(grid.tripletGrid, false)
        compare(grid.snapTicks, settledSnap)

        division.forceActiveFocus()
        keyClick(Qt.Key_Return)
        tryCompare(grid, "gridMenuKind", 1)
        divisionMenu = panel()
        assertRows(divisionMenu, ids, grid.gridSelectionMenuId)
        rowTextEqualsControlText(divisionMenu, grid.gridDivisionControlText)
        tryCompare(divisionMenu.parent, "activeFocus", true)
        keyClick(Qt.Key_Escape)
        tryCompare(grid, "gridMenuKind", 0)
        grid.setEditCursorTick(96)
        compare(grid.editCursorTick, 96)
        divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        pickedId = alternateGridMenuId(grid.gridSelectionMenuId)
        pickedRow = ids.indexOf(pickedId)
        tryVerify(function() { return divisionMenu.rowItem(pickedRow) !== null }, 3000)
        pickedText = divisionMenu.rowItem(pickedRow).itemData.text
        compare(pickedText, "1/16")
        clickRow(divisionMenu, pickedRow)
        tryCompare(grid, "gridSelectionMenuId", pickedId)
        compare(grid.gridDivisionControlText, pickedText)
        compare(grid.editCursorTick, 96)

        divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        assertRows(divisionMenu, ids, grid.gridSelectionMenuId)
        rowTextEqualsControlText(divisionMenu, grid.gridDivisionControlText)
        keyClick(Qt.Key_Escape)
        tryCompare(grid, "gridMenuKind", 0)
        var feelMenu = openGrid("timelineRulerFeelControl", 2)
        assertRows(feelMenu, [0, 1], 0)
        compare(grid.gridFeelControlText, "Straight")
        rowTextEqualsControlText(feelMenu, grid.gridFeelControlText)
        clickRow(feelMenu, 1)
        tryCompare(grid, "gridMenuKind", 0)
        tryCompare(grid, "tripletGrid", true)
        compare(grid.gridFeelControlText, "Triplet")
        feelMenu = openGrid("timelineRulerFeelControl", 2)
        assertRows(feelMenu, [0, 1], 1)
        rowTextEqualsControlText(feelMenu, grid.gridFeelControlText)
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
        compare(grid.gridSelectionMenuId, 16)
        compare(grid.editCursorTick, beforeCursor)
        compare(grid.snapTicks, beforeSnap)
        compare(grid.gridDivisionControlText, "1/16")
        compare(grid.tripletGrid, true)

        openGrid("timelineRulerDivisionControl", 1)
        grid.dismissGridMenu()
        tryCompare(grid, "gridMenuKind", 0)
        tryVerify(function() { return findChild(surface(), "quickMenuPanelRoot") === null }, 3000)
        compare(grid.gridSelectionMenuId, 16)
        compare(grid.tripletGrid, true)
        compare(grid.gridDivisionControlText, "1/16")
        mouseClick(ruler, ruler.width / 2, ruler.height / 2, Qt.RightButton)
        tryCompare(session, "timeSigMenuOpen", true)
        compare(grid.gridSelectionMenuId, 16)
        compare(grid.tripletGrid, true)
        timeSigHost.closeTimeSigMenu()
        tryCompare(session, "timeSigMenuOpen", false)
        divisionMenu = openGrid("timelineRulerDivisionControl", 1)
        assertRows(divisionMenu, ids, grid.gridSelectionMenuId)
        compare(grid.tripletGrid, true)
        compare(grid.gridDivisionControlText, "1/16")
        keyClick(Qt.Key_Escape)
        tryCompare(grid, "gridMenuKind", 0)
    }

    function test_gridShortcutsWalkDenominationsAndFeel() {
        openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(roll, "activeFocus", true)
        compare(grid.gridSelectionMenuId, -1)
        keyClick(Qt.Key_1, Qt.ControlModifier)
        tryCompare(grid, "gridSelectionMenuId", 4)
        keyClick(Qt.Key_1, Qt.ControlModifier)
        tryCompare(grid, "gridSelectionMenuId", 8)
        keyClick(Qt.Key_2, Qt.ControlModifier)
        tryCompare(grid, "gridSelectionMenuId", 4)
        keyClick(Qt.Key_3, Qt.ControlModifier)
        tryCompare(grid, "tripletGrid", true)
        compare(grid.gridFeelControlText, "Triplet")
    }

    function test_gridControlsShowComboboxAffordance() {
        openSong()
        var palette = surface().gridModel.palette
        var pairs = [["timelineRulerDivisionControl", "gridDivisionControlText"],
                     ["timelineRulerFeelControl", "gridFeelControlText"]]
        for (var i = 0; i < pairs.length; ++i) {
            var item = control(pairs[i][0])
            compare(item.activeFocusOnTab, true)
            var background = findChild(item, "gridControlBackground")
            verify(background !== null)
            verify(background.border.width > 0)
            verify(Qt.colorEqual(background.border.color, palette.outline))
            verify(Qt.colorEqual(background.color, palette.buttonHoverBackground))
            var arrow = findChild(item, "gridControlArrow")
            verify(arrow !== null)
            compare(arrow.text, "▾")
            verify(Qt.colorEqual(arrow.color, palette.buttonText))
            var label = findChild(item, "gridControlLabel")
            verify(label !== null)
            compare(label.text, surface().gridModel[pairs[i][1]])
            verify(Qt.colorEqual(label.color, palette.buttonText))
        }
        var gridLabel = findChild(surface(), "timelineRulerGridLabel")
        verify(gridLabel !== null)
        compare(gridLabel.text, "Grid")
        verify(Qt.colorEqual(gridLabel.color, palette.primaryText))
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
        tryVerify(rulerMenuGone, 3000,
                  "clearing the time selection unmounts its panel before the ruler menu opens")
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

    function rulerTickX(tick) {
        var grid = surface().gridModel
        return tick * grid.beatWidth / grid.ticksPerBeat - grid.cameraScrollX
    }

    function rulerCellPixels() {
        var grid = surface().gridModel
        return Math.max(1, grid.snapTicks) * grid.beatWidth / grid.ticksPerBeat
    }

    function rulerPanel() {
        var menu = findChild(surface(), "quickMenuPanelRoot")
        return menu !== null && menu.rowObjectNamePrefix === "rulerMenuRow_" && menu.visible
            ? menu : null
    }

    function rulerMenuShown() {
        return rulerPanel() !== null
    }

    function rulerMenuGone() {
        return findChild(surface(), "quickMenuPanelRoot") === null && !timeSigHost.timeSigMenuOpen
    }

    function openRulerMenu(x, y) {
        tryVerify(rulerMenuGone, 3000)
        mouseClick(control("timelineRulerInput"), x, y, Qt.RightButton)
        tryCompare(timeSigHost, "timeSigMenuOpen", true)
        tryVerify(rulerMenuShown, 5000)
        var menu = rulerPanel()
        verify(rulerRowIndex(menu, 11) < 0)
        return menu
    }

    function openTimeMenu(x) {
        tryVerify(rulerMenuGone, 3000)
        var roll = control("swiftRollInput")
        mouseClick(roll, x, roll.height * 0.5, Qt.RightButton)
        tryVerify(rulerMenuShown, 5000)
        var menu = rulerPanel()
        tryCompare(menu, "rowCount", 9)
        verify(rulerRowIndex(menu, 11) === 0)
        return menu
    }

    function rulerRowIndex(menu, actionId) {
        tryVerify(function() { return menu.rowCount > 0 }, 3000)
        for (var index = 0; index < menu.rowCount; ++index) {
            tryVerify(function() { return menu.rowItem(index) !== null }, 3000)
            if (menu.rowItem(index).itemData.actionId === actionId)
                return index
        }
        return -1
    }

    function rulerRowEnabled(menu, actionId) {
        var index = rulerRowIndex(menu, actionId)
        verify(index >= 0)
        return menu.rowItem(index).itemData.enabled
    }

    function clearRulerLoop(x, y) {
        var menu = openRulerMenu(x, y)
        var index = rulerRowIndex(menu, 4)
        if (menu.rowItem(index).itemData.enabled) {
            clickRow(menu, index)
            tryVerify(rulerMenuGone, 3000)
            menu = openRulerMenu(x, y)
        }
        return menu
    }

    function loopMarkerAt(name, tick) {
        var marker = findChild(surface(), name)
        return marker !== null && Math.abs(marker.x + 0.5 - rulerTickX(tick)) <= 0.75
    }

    function loopMarkerAbsent(name) {
        return findChild(surface(), name) === null
    }

    function rulerLabelAt(text, tick) {
        var ruler = control("timelineRulerInput")
        var labels = ruler.parent.children
        var x = rulerTickX(tick)
        for (var index = 0; index < labels.length; ++index) {
            var label = labels[index]
            if (label.labelText === text && label.x >= x - 1
                && label.x <= x + surface().gridModel.baseFontPx)
                return true
        }
        return false
    }

    function noteLayout() {
        return JSON.stringify(JSON.parse(surface().gridModel.noteSummary).map(function(note) {
            return [note.track, note.tick, note.duration, note.pitch, note.velocity]
        }).sort())
    }

    function noteTargets() {
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        return JSON.parse(grid.noteSummary).filter(function(note) {
            return !note.ghost && note.track === grid.trackIndex
        }).map(function(note) {
            var item = findChild(surface(), "gridNote_" + note.id)
            if (!item || !item.visible || item.width < grid.drawThreshold * 2)
                return null
            var point = item.mapToItem(roll, item.width / 2, item.height / 2)
            return point.x > item.width && point.y > item.height
                && point.x < roll.width - item.width
                && point.y < roll.height - item.height
                ? { note: note, point: point } : null
        }).filter(function(target) { return target !== null })
    }

    function noteMenu() {
        var menu = findChild(shell, "shellGridContextMenu")
        verify(menu !== null, "the shell owns the note context menu")
        return menu
    }

    function noteMenuMiss(menu) {
        var roll = control("swiftRollInput")
        var targets = JSON.parse(surface().gridModel.noteSummary)
        for (var y = roll.height - surface().gridModel.rowHeight; y > 0;
             y -= surface().gridModel.rowHeight) {
            for (var x = roll.width - roll.height / 8; x > 0; x -= roll.width / 8) {
                var point = roll.mapToItem(null, x, y)
                if (point.x >= menu.x && point.x <= menu.x + menu.width
                    && point.y >= menu.y && point.y <= menu.y + menu.height)
                    continue
                var occupied = targets.some(function(note) {
                    var item = findChild(surface(), "gridNote_" + note.id)
                    if (!item || !item.visible)
                        return false
                    var top = item.mapToItem(roll, 0, 0)
                    return x >= top.x && x <= top.x + item.width
                        && y >= top.y && y <= top.y + item.height
                })
                if (!occupied)
                    return roll.mapToItem(shell.contentItem, x, y)
            }
        }
        return null
    }

    function test_noteMenuRetargetAndDismiss() {
        openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var targets = noteTargets()
        verify(targets.length > 1, "two drawn primary notes accept note menus")
        var first = targets[0]
        mouseClick(roll, first.point.x, first.point.y, Qt.RightButton)
        var menu = noteMenu()
        tryCompare(menu, "visible", true)
        verify(JSON.parse(grid.noteSummary).some(function(note) {
            return note.id === first.note.id && note.selected
        }), "a right release over an unselected note selects it and opens the note menu")
        verify(menu.itemAt(0).objectName === "shellContextAction_edit.set_velocity"
               && findChild(menu, "shellContextAction_roll.paste") === null,
               "the rendered note menu leads with Set Velocity and omits Paste")
        var second = null
        for (var index = 1; index < targets.length; ++index) {
            var point = roll.mapToItem(null, targets[index].point.x, targets[index].point.y)
            if (point.x < menu.x || point.x > menu.x + menu.width
                || point.y < menu.y || point.y > menu.y + menu.height) {
                second = targets[index]
                break
            }
        }
        verify(second !== null, "a second drawn note lies outside the open menu")
        var before = noteLayout()
        var revision = grid.appliedRevisionText
        var cursor = grid.editCursorTick
        var position = roll.mapToItem(shell.contentItem, second.point.x, second.point.y)
        mousePress(shell.contentItem, position.x, position.y, Qt.RightButton)
        tryCompare(menu, "visible", true, 3000)
        verify(menu.visible && JSON.parse(grid.noteSummary).some(function(note) {
            return note.id === second.note.id && note.selected
        }), "an outside right press retargets the open note menu to the note under the cursor")
        mouseRelease(shell.contentItem, position.x, position.y, Qt.RightButton)
        compare(noteLayout(), before, "the retarget release leaves the timeline untouched")
        compare(grid.appliedRevisionText, revision)
        compare(grid.editCursorTick, cursor)
        var miss = noteMenuMiss(menu)
        verify(miss !== null, "an empty plot point lies outside the retargeted menu")
        mousePress(shell.contentItem, miss.x, miss.y, Qt.RightButton)
        compare(menu.visible, false,
                "an outside right press on an empty row dismisses the note menu without editing")
        mouseRelease(shell.contentItem, miss.x, miss.y, Qt.RightButton)
        compare(noteLayout(), before)
        compare(grid.appliedRevisionText, revision)
        verify(JSON.parse(grid.noteSummary).some(function(note) {
            return note.id === second.note.id && note.selected
        }), "the empty-space release preserves the retargeted note selection")
    }

    function test_noteMenuPromptRoundTripWithHiddenDrawer() {
        var session = openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var drawer = surface().drawerPresenter
        var drawerItem = control("editorDrawer")
        for (var kind = 0; kind < 3; ++kind)
            drawer.setSectionVisible(kind, false, false)
        drawerItem.visible = false
        compare(drawerItem.visible, false, "the drawer is hidden before the prompt opens")
        var target = noteTargets()[0]
        verify(target !== undefined, "a visible fixture note can be seeded at velocity 73")
        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        var menu = noteMenu()
        tryCompare(menu, "visible", true)
        var row = menu.itemAt(0)
        mouseClick(row, row.width / 2, row.height / 2)
        var model = surface().velocityModel
        tryCompare(model, "promptOpen", true)
        tryVerify(function() { return findChild(surface(), "noteVelocityInput") !== null }, 3000)
        var field = findChild(surface(), "noteVelocityInput")
        tryCompare(field, "activeFocus", true)
        field.selectAll()
        keyClick(Qt.Key_7)
        keyClick(Qt.Key_3)
        keyClick(Qt.Key_Return)
        tryCompare(model, "promptOpen", false)
        verify(waitForNative(function() {
            return JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === target.note.id && note.velocity === 73
            })
        }, 5000), "the mounted fixture note is seeded at velocity 73")
        var before = noteLayout()
        var baselineRevision = grid.appliedRevisionText
        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        tryCompare(menu, "visible", true)
        row = menu.itemAt(0)
        mouseClick(row, row.width / 2, row.height / 2)
        tryCompare(model, "promptOpen", true)
        tryVerify(function() { return findChild(surface(), "noteVelocityInput") !== null }, 3000)
        var card = findChild(surface(), "velocityPromptCard")
        field = findChild(surface(), "noteVelocityInput")
        verify(card !== null && field !== null && card.visible && card.width > 0
               && card.height > 0 && !drawerItem.visible && !menu.visible,
               "the prompt renders over the roll while the drawer is hidden")
        tryCompare(field, "activeFocus", true)
        verify(field.text === "73" && field.selectedText === "73",
               "the Set Velocity row opens the prompt over the roll with the note's velocity selected")
        keyClick(Qt.Key_9)
        keyClick(Qt.Key_5)
        compare(noteLayout(), before, "typing the velocity draft does not edit the timeline")
        compare(grid.appliedRevisionText, baselineRevision)
        keyClick(Qt.Key_Return)
        tryCompare(model, "promptOpen", false)
        verify(roll.activeFocus, "accepting the prompt restores roll focus; active item "
               + (shell.activeFocusItem ? shell.activeFocusItem.objectName : "<none>"))
        verify(JSON.parse(grid.noteSummary).some(function(note) {
            return note.id === target.note.id && note.velocity === 95
        }), "accepting the mounted prompt changes the captured note")
        var accepted = noteLayout()
        verify(accepted !== before && grid.appliedRevisionText !== baselineRevision
               && session.canUndo, "the mounted acceptance commits one undoable edit")
        shell.shellPresenter.activate("edit.undo")
        verify(waitForNative(function() {
            return noteLayout() === before && session.canRedo
        }, 5000), "one undo restores the exact pre-prompt note layout")
        compare(session.canUndo, true, "the earlier fixture edit remains after undoing acceptance")
        compare(grid.lastVelocity, 95, "undo leaves the pencil latch at the accepted value")

        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        tryCompare(menu, "visible", true)
        row = menu.itemAt(0)
        mouseClick(row, row.width / 2, row.height / 2)
        tryCompare(model, "promptOpen", true)
        tryVerify(function() { return findChild(surface(), "noteVelocityInput") !== null }, 3000)
        field = findChild(surface(), "noteVelocityInput")
        tryCompare(field, "activeFocus", true)
        compare(field.selectedText, "73")
        var unchangedRevision = grid.appliedRevisionText
        var unchangedLayout = noteLayout()
        keyClick(Qt.Key_Return)
        tryCompare(model, "promptOpen", false)
        verify(noteLayout() === unchangedLayout
               && grid.appliedRevisionText === unchangedRevision && session.canRedo
               && grid.lastVelocity === 73,
               "accepting an unchanged velocity over the roll writes nothing and relatches the pencil")
        var snap = grid.snapTicks
        var pixelsPerTick = grid.beatWidth / grid.ticksPerBeat
        var duration = Math.max(snap, Math.ceil(grid.drawThreshold / pixelsPerTick / snap) * snap)
        var start = Math.ceil((grid.cameraScrollX + roll.width / 3) / pixelsPerTick / snap) * snap
        var draw = null
        var occupied = JSON.parse(grid.noteSummary)
        for (var rowIndex = Math.ceil(grid.cameraScrollY / grid.rowHeight) + 2;
             rowIndex < Math.floor((grid.cameraScrollY + roll.height) / grid.rowHeight) - 2;
             ++rowIndex) {
            var pitch = 127 - rowIndex
            if (!occupied.some(function(note) {
                return note.pitch === pitch && note.tick < start + duration
                    && note.tick + note.duration > start
            })) {
                draw = { x: start * pixelsPerTick - grid.cameraScrollX
                             + grid.drawThreshold / 2,
                         y: (rowIndex + 0.5) * grid.rowHeight - grid.cameraScrollY }
                break
            }
        }
        verify(draw !== null && draw.x + duration * pixelsPerTick < roll.width,
               "a free displayed cell accepts the relatched pencil")
        var drawEnd = draw.x + duration * pixelsPerTick - grid.drawThreshold / 2
        mousePress(roll, draw.x, draw.y, Qt.LeftButton)
        mouseMove(roll, drawEnd, draw.y, -1, Qt.LeftButton)
        mouseRelease(roll, drawEnd, draw.y, Qt.LeftButton)
        verify(waitForNative(function() {
            return JSON.parse(grid.noteSummary).some(function(note) {
                return occupied.every(function(previous) { return previous.id !== note.id })
                    && note.velocity === 73
            })
        }, 5000), "the unchanged prompt acceptance supplies the next drawn note's velocity")

        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        tryCompare(menu, "visible", true)
        row = menu.itemAt(0)
        mouseClick(row, row.width / 2, row.height / 2)
        tryCompare(model, "promptOpen", true)
        tryVerify(function() { return findChild(surface(), "noteVelocityInput") !== null }, 3000)
        field = findChild(surface(), "noteVelocityInput")
        tryCompare(field, "activeFocus", true)
        var beforeEscape = noteLayout()
        var revision = grid.appliedRevisionText
        keyClick(Qt.Key_Escape)
        tryCompare(model, "promptOpen", false)
        verify(noteLayout() === beforeEscape && grid.appliedRevisionText === revision
               && roll.activeFocus, "Escape closes the prompt over the roll without writing")
    }

    function test_noteMenuRetiresOnDocumentEditAndPreservesOtherFocus() {
        var session = openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var target = noteTargets()[0]
        verify(target !== undefined, "a mounted note accepts a context menu")
        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        var menu = noteMenu()
        tryCompare(menu, "visible", true)
        var before = noteLayout()
        var revision = grid.appliedRevisionText
        grid.performCommand(5)
        tryCompare(menu, "visible", false)
        verify(grid.appliedRevisionText !== revision
               && noteLayout() !== before && session.canUndo,
               "a document edit retires the open note menu synchronously")
        shell.shellPresenter.activate("edit.undo")
        verify(waitForNative(function() { return noteLayout() === before }, 5000),
               "undo restores the note edited while its menu was open")
        mouseClick(roll, target.point.x, target.point.y, Qt.RightButton)
        tryCompare(menu, "visible", true)
        var row = menu.itemAt(0)
        mouseClick(row, row.width / 2, row.height / 2)
        var model = surface().velocityModel
        tryCompare(model, "promptOpen", true)
        tryVerify(function() { return findChild(surface(), "noteVelocityInput") !== null }, 3000)
        var field = findChild(surface(), "noteVelocityInput")
        tryCompare(field, "activeFocus", true)
        var ruler = control("timelineRulerInput")
        ruler.forceActiveFocus(Qt.OtherFocusReason)
        tryCompare(ruler, "activeFocus", true)
        model.cancelPrompt()
        tryCompare(model, "promptOpen", false)
        compare(ruler.activeFocus, true,
                "closing the prompt does not steal focus from another control")
    }

    function sweepNoteRange() {
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var notes = JSON.parse(grid.noteSummary)
        var note = null
        for (var index = 0; index < notes.length && note === null; ++index) {
            var left = rulerTickX(notes[index].tick)
            var right = rulerTickX(notes[index].tick + notes[index].duration)
            if (!notes[index].ghost && notes[index].track === grid.trackIndex
                && left > ruler.width * 0.15 && right < ruler.width * 0.6)
                note = notes[index]
        }
        verify(note !== null, "a whole primary-track note lies inside the ruler sweep band")
        var startX = rulerTickX(note.tick) - rulerCellPixels()
        var endX = rulerTickX(note.tick + note.duration) + rulerCellPixels()
        var y = ruler.height * 0.75
        mousePress(ruler, startX, y, Qt.LeftButton)
        mouseMove(ruler, endX, y, -1, Qt.LeftButton)
        mouseRelease(ruler, endX, y, Qt.LeftButton)
        return { startX: startX, endX: endX, midX: (startX + endX) / 2 }
    }

    function test_rulerRightPressCapturesAndReleaseOpensAtReleasePosition() {
        openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var pressX = ruler.width * 0.3
        var releaseX = ruler.width * 0.42
        var y = ruler.height * 0.75
        var priorCursor = grid.editCursorTick
        verify(rulerMenuGone())
        mousePress(ruler, pressX, y, Qt.RightButton)
        compare(timeSigHost.timeSigMenuOpen, false,
                "ruler right press captures without opening a context menu")
        compare(grid.editCursorTick, priorCursor,
                "ruler right press does not seek before release")
        mouseMove(ruler, releaseX, y, -1, Qt.RightButton)
        compare(timeSigHost.timeSigMenuOpen, false,
                "moving the pressed pointer does not open the context menu")
        mouseRelease(ruler, releaseX, y, Qt.RightButton)
        tryVerify(rulerMenuShown, 3000,
                  "ruler right release opens the captured-tick menu")
        var menu = rulerPanel()
        var releasePoint = ruler.mapToItem(surface(), releaseX, y)
        compare(menu.menuOrigin.x, Math.round(Math.max(0, Math.min(releasePoint.x,
                                                            menu.width - menu.menuWidth))),
                "ruler menu is positioned at the release rather than press coordinate")
        verify(Math.abs(rulerTickX(grid.editCursorTick) - pressX) <= rulerCellPixels(),
               "release commits the captured press tick, not the release tick")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)
    }

    function test_rulerEscapeDismissesWithoutHistoryWriteAndRefocuses() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var owner = surface().rulerMenu
        var x = ruler.width * 0.3
        var y = ruler.height * 0.75
        mousePress(ruler, x, y, Qt.RightButton)
        mouseRelease(ruler, x, y, Qt.RightButton)
        tryCompare(owner, "isOpen", true)
        tryVerify(rulerMenuShown, 3000)
        var revision = grid.appliedRevisionText
        var canUndo = session.canUndo
        var canRedo = session.canRedo
        var cursor = grid.editCursorTick
        keyClick(Qt.Key_Escape)
        tryCompare(owner, "isOpen", false)
        tryVerify(rulerMenuGone, 3000)
        compare(grid.appliedRevisionText, revision,
                "Escape dismisses the ruler menu without changing the document")
        compare(session.canUndo, canUndo, "Escape does not add an undo entry")
        compare(session.canRedo, canRedo, "Escape does not change redo history")
        compare(grid.editCursorTick, cursor, "Escape keeps the committed ruler cursor")
        tryCompare(ruler, "activeFocus", true)
    }

    function test_rulerLoopRowsSetRemoveUndoAndDismissFromRenderedPanel() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var y = ruler.height * 0.75
        var startX = ruler.width * 0.3
        var endX = ruler.width * 0.45

        var menu = clearRulerLoop(startX, y)
        var removeIndex = rulerRowIndex(menu, 4)
        compare(menu.rowItem(removeIndex).itemData.enabled, false,
                "Remove Loop renders disabled once both loop markers are absent")
        var startTick = grid.editCursorTick
        verify(Math.abs(rulerTickX(startTick) - startX) <= rulerCellPixels() / 2 + 1,
               "the outside ruler press commits the clicked edit cursor")
        var revision = grid.appliedRevisionText
        clickRow(menu, removeIndex)
        wait(50)
        compare(rulerMenuShown() && timeSigHost.timeSigMenuOpen, true,
                "a click on the disabled Remove Loop row keeps the ruler menu open")
        compare(grid.appliedRevisionText, revision,
                "a click on the disabled Remove Loop row writes nothing")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000,
                  "Escape dismisses the ruler menu")
        compare(grid.appliedRevisionText, revision,
                "Escape dismisses the ruler menu without a write")
        compare(grid.editCursorTick, startTick,
                "Escape keeps the committed ruler cursor")
        tryVerify(function() { return ruler.activeFocus }, 3000,
                  "Escape returns focus to the ruler")

        menu = openRulerMenu(startX, y)
        var staleIndex = rulerRowIndex(menu, 2)
        grid.setEditCursorTick(startTick + Math.max(1, grid.snapTicks))
        clickRow(menu, staleIndex)
        tryVerify(rulerMenuGone, 3000)
        wait(50)
        compare(grid.appliedRevisionText, revision,
                "a cursor change between open and click retires Set Loop Start without a write")

        menu = openRulerMenu(startX, y)
        compare(grid.editCursorTick, startTick)
        var setStartIndex = rulerRowIndex(menu, 2)
        verify(menu.rowItem(setStartIndex).itemData.enabled)
        clickRow(menu, setStartIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the Set Loop Start activation closes the ruler menu")
        tryVerify(function() { return loopMarkerAt("loopStartMarker", startTick) }, 3000,
                  "Set Loop Start renders the loop start marker at the pressed tick")
        tryVerify(function() { return loopMarkerAbsent("loopEndMarker") }, 3000,
                  "Set Loop Start leaves the loop end absent")
        tryVerify(function() { return ruler.activeFocus }, 3000,
                  "the Set Loop Start activation returns focus to the ruler")

        menu = openRulerMenu(endX, y)
        var endTick = grid.editCursorTick
        verify(endTick > startTick)
        var setEndIndex = rulerRowIndex(menu, 3)
        verify(menu.rowItem(setEndIndex).itemData.enabled)
        clickRow(menu, setEndIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the Set Loop End activation closes the ruler menu")
        tryVerify(function() {
            return loopMarkerAt("loopEndMarker", endTick)
                && loopMarkerAt("loopStartMarker", startTick)
        }, 3000, "the isolated Set Loop End click renders the end marker and keeps the start")
        verify(grid.appliedRevisionText !== revision,
               "setting both loop markers advances the document revision")

        menu = openRulerMenu(startX, y)
        removeIndex = rulerRowIndex(menu, 4)
        verify(menu.rowItem(removeIndex).itemData.enabled,
               "Remove Loop renders enabled while both loop markers exist")
        clickRow(menu, removeIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the Remove Loop activation closes the ruler menu")
        tryVerify(function() {
            return loopMarkerAbsent("loopStartMarker") && loopMarkerAbsent("loopEndMarker")
        }, 3000, "Remove Loop clears both rendered loop markers")
        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAt("loopEndMarker", endTick) && loopMarkerAbsent("loopStartMarker")
        }, 5000), "the first undo after Remove Loop restores only the loop end marker")
        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAt("loopStartMarker", startTick) && loopMarkerAt("loopEndMarker", endTick)
        }, 5000), "the second undo after Remove Loop restores both loop markers")

        var selectionStart = startTick - Math.max(1, grid.snapTicks)
        mousePress(ruler, rulerTickX(selectionStart), y, Qt.LeftButton)
        mouseMove(ruler, rulerTickX(startTick), Math.max(0, y - grid.dragDistance),
                  -1, Qt.LeftButton)
        mouseRelease(ruler, rulerTickX(startTick), Math.max(0, y - grid.dragDistance),
                     Qt.LeftButton)
        menu = openRulerMenu(rulerTickX((selectionStart + startTick) / 2), y)
        var loopSelectionIndex = rulerRowIndex(menu, 5)
        verify(loopSelectionIndex >= 0 && menu.rowItem(loopSelectionIndex).itemData.enabled)
        clickRow(menu, loopSelectionIndex)
        tryVerify(rulerMenuGone, 3000)
        tryVerify(function() {
            return loopMarkerAt("loopStartMarker", selectionStart)
                && loopMarkerAt("loopEndMarker", startTick)
        }, 3000, "Loop from Selection renders the loop markers at the selection bounds")
        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAt("loopStartMarker", selectionStart)
                && loopMarkerAt("loopEndMarker", endTick)
        }, 5000), "the first undo after Loop from Selection restores only the old loop end")
        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAt("loopStartMarker", startTick) && loopMarkerAt("loopEndMarker", endTick)
        }, 5000), "the second undo after Loop from Selection restores the manual loop markers")

        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAt("loopStartMarker", startTick) && loopMarkerAbsent("loopEndMarker")
        }, 5000), "undoing Set Loop End restores only the loop start marker")
        session.requestUndo()
        verify(waitForNative(function() {
            return loopMarkerAbsent("loopStartMarker") && loopMarkerAbsent("loopEndMarker")
        }, 5000), "undoing Set Loop Start clears the loop start marker")

        menu = openRulerMenu(startX, y)
        var cursor = grid.editCursorTick
        revision = grid.appliedRevisionText
        var frame = findChild(menu, "quickMenuFrame")
        verify(frame !== null)
        var outsideX = ruler.width * 0.9
        var outside = ruler.mapToItem(surface(), outsideX, y)
        var frameOrigin = frame.mapToItem(surface(), 0, 0)
        verify(outside.x < frameOrigin.x || outside.x > frameOrigin.x + frame.width
               || outside.y < frameOrigin.y || outside.y > frameOrigin.y + frame.height)
        mouseClick(ruler, outsideX, y)
        tryVerify(rulerMenuGone, 3000,
                  "an outside press dismisses the ruler menu")
        tryVerify(function() { return findChild(surface(), "quickMenuPanelRoot") === null }, 3000,
                  "the outside dismissal unmounts the ruler menu panel")
        compare(grid.editCursorTick, cursor,
                "the outside dismissal does not retarget the ruler cursor")
        compare(grid.appliedRevisionText, revision, "the outside dismissal writes nothing")
    }

    function test_rulerSignatureChipPressesCommitExactTicksFromRenderedPanel() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var markerY = ruler.height * 0.25
        var tickY = grid.rulerMarkerRowHeight
        var cell = Math.max(1, grid.snapTicks)
        var seedX = ruler.width * 0.35
        verify(timeSigHost.timeSigChipTick(seedX, markerY) < 0)

        var menu = clearRulerLoop(seedX, markerY)
        var chipTick = grid.editCursorTick
        compare(rulerRowEnabled(menu, 10), false,
                "Remove Time Signature renders disabled before the chip is seeded")
        verify(rulerRowEnabled(menu, 9), "Edit Time Signature renders enabled in the cursor menu")
        clickRow(menu, rulerRowIndex(menu, 9))
        tryVerify(function() {
            return findChild(surface(), "quickMenuPanelRoot") === null && timeSigHost.timeSigPromptOpen
        }, 3000,
                  "the Edit Time Signature row closes the menu and opens the signature prompt")
        var revision = grid.appliedRevisionText
        timeSigHost.acceptTimeSigPrompt(5, 2)
        tryVerify(function() {
            return grid.appliedRevisionText !== revision && rulerLabelAt("5/4", chipTick)
        }, 3000, "F1: the 5/4 chip renders at the snap-aligned ruler tick")

        tryVerify(function() { return !timeSigHost.timeSigPromptOpen }, 3000)
        grid.setEditCursorTick(chipTick + 4 * cell)
        tryCompare(grid, "editCursorTick", chipTick + 4 * cell)
        menu = openRulerMenu(rulerTickX(chipTick), markerY)
        compare(grid.editCursorTick, chipTick,
                "F1: the snap-aligned chip press commits the chip's exact tick")
        verify(rulerRowEnabled(menu, 10),
               "F1: Remove Time Signature renders enabled at the snap-aligned chip")
        compare(rulerRowEnabled(menu, 4), false,
                "Remove Loop renders disabled at the chip while both loop markers are absent")
        verify(rulerRowIndex(menu, 5) < 0 && rulerRowIndex(menu, 6) < 0
               && rulerRowIndex(menu, 7) < 0 && rulerRowIndex(menu, 8) < 0,
               "the chip cursor menu exposes no selection-scoped rows without a time selection")
        verify(rulerRowEnabled(menu, 1), "the chip cursor menu offers an enabled Insert Time row")
        verify(rulerRowIndex(menu, 9) >= 0, "the chip cursor menu offers the Edit Time Signature row")
        revision = grid.appliedRevisionText
        clickRow(menu, rulerRowIndex(menu, 4))
        wait(50)
        compare(rulerMenuShown() && timeSigHost.timeSigMenuOpen, true,
                "a click on the disabled Remove Loop row keeps the chip menu open")
        compare(grid.appliedRevisionText, revision,
                "the disabled Remove Loop click leaves the document unchanged")
        clickRow(menu, rulerRowIndex(menu, 10))
        tryVerify(rulerMenuGone, 3000,
                  "the Remove Time Signature activation closes the ruler menu")
        tryVerify(function() {
            return grid.appliedRevisionText !== revision && !rulerLabelAt("5/4", chipTick)
        }, 3000, "Remove Time Signature deletes the explicit chip at its exact tick")

        var f3X = rulerTickX(chipTick + 2 * cell)
        verify(timeSigHost.timeSigChipTick(f3X, markerY) < 0)
        revision = grid.appliedRevisionText
        menu = openRulerMenu(f3X, tickY)
        compare(grid.editCursorTick, chipTick + 2 * cell)
        compare(rulerRowEnabled(menu, 10), false,
                "F3: Remove Time Signature renders disabled at a tick-row press without an explicit signature")
        clickRow(menu, rulerRowIndex(menu, 10))
        wait(50)
        compare(rulerMenuShown() && timeSigHost.timeSigMenuOpen, true,
                "a click on the disabled Remove Time Signature row keeps the menu open")
        compare(grid.appliedRevisionText, revision,
                "the disabled Remove Time Signature click leaves the document unchanged")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000,
                  "Escape dismisses the F3 ruler menu")
        session.requestUndo()
        verify(waitForNative(function() { return rulerLabelAt("5/4", chipTick) }, 5000),
               "one undo restores the removed F1 chip")
        menu = openRulerMenu(rulerTickX(chipTick), markerY)
        clickRow(menu, rulerRowIndex(menu, 10))
        tryVerify(rulerMenuGone, 3000)

        timeSigHost.openTimeSigPrompt(chipTick + 1)
        tryCompare(timeSigHost, "timeSigPromptOpen", true)
        revision = grid.appliedRevisionText
        timeSigHost.acceptTimeSigPrompt(7, 2)
        tryVerify(function() { return grid.appliedRevisionText !== revision }, 3000)
        tryVerify(function() { return !timeSigHost.timeSigPromptOpen }, 3000)
        grid.setEditCursorTick(chipTick + 4 * cell)
        tryCompare(grid, "editCursorTick", chipTick + 4 * cell)
        menu = openRulerMenu(rulerTickX(chipTick + 1), markerY)
        compare(grid.editCursorTick, chipTick + 1,
                "F2: the off-grid chip press commits the chip's exact event tick")
        verify(rulerRowEnabled(menu, 10),
               "F2: Remove Time Signature renders enabled at the exact off-grid chip tick")
        keyClick(Qt.Key_Escape)
        compare(timeSigHost.timeSigChipTick(rulerTickX(chipTick + 1), markerY),
                chipTick + 1, "a marker-row press commits the chip's exact tick")
        tryVerify(rulerMenuGone, 3000,
                  "Escape dismisses the exact-chip ruler menu")
        var offgridX = rulerTickX(chipTick + 1)
        mouseClick(ruler, offgridX, tickY, Qt.RightButton)
        tryVerify(rulerMenuShown, 3000)
        menu = rulerPanel()
        compare(grid.editCursorTick, chipTick + 1,
                "a tick-row ruler press ignores the signature chip")
        compare(rulerRowEnabled(menu, 10), false,
                "Remove Time Signature is disabled at the tick row while a chip exists")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)
        compare(timeSigHost.timeSigChipTick(offgridX, tickY), -1,
                "a tick-row double-click cannot target the signature chip")
    }

    function test_rulerClipboardRowsFollowClipAndTimeSelection() {
        openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var y = ruler.height * 0.75
        var cursorX = ruler.width * 0.85
        verify(bootstrap.clearClipboardProbe())

        var menu = openRulerMenu(cursorX, y)
        var pasteIndex = rulerRowIndex(menu, 13)
        verify(pasteIndex >= 0, "the cursor menu renders a Paste row")
        compare(menu.rowItem(pasteIndex).itemData.enabled, false,
                "the cursor menu disables Paste while the clipboard holds no decodable clip")
        verify(rulerRowIndex(menu, 11) < 0 && rulerRowIndex(menu, 12) < 0,
               "the cursor menu offers no Copy or Cut row without a time selection")
        var revision = grid.appliedRevisionText
        clickRow(menu, pasteIndex)
        wait(50)
        compare(rulerMenuShown() && timeSigHost.timeSigMenuOpen, true,
                "a click on the disabled cursor-menu Paste row keeps the menu open")
        compare(grid.appliedRevisionText, revision,
                "the disabled cursor-menu Paste click writes nothing")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)

        var range = sweepNoteRange()
        menu = openTimeMenu(range.midX)
        verify(rulerRowEnabled(menu, 11) && rulerRowEnabled(menu, 12),
               "Copy and Cut render enabled while a time selection is active")
        pasteIndex = rulerRowIndex(menu, 13)
        verify(pasteIndex >= 0, "the time-selection menu renders a Paste row")
        compare(menu.rowItem(pasteIndex).itemData.enabled, false,
                "the time-selection menu disables Paste while the clipboard holds no decodable clip")
        clickRow(menu, pasteIndex)
        wait(50)
        compare(rulerMenuShown(), true,
                "a click on the disabled time-menu Paste row keeps the menu open")
        compare(grid.appliedRevisionText, revision,
                "the disabled time-menu Paste click writes nothing")
        clickRow(menu, rulerRowIndex(menu, 11))
        tryVerify(rulerMenuGone, 3000,
                  "the Copy activation closes the time-selection menu")
        compare(grid.appliedRevisionText, revision, "the Copy row leaves the document unchanged")
        var clip = JSON.parse(bootstrap.copiedClipSummary())
        verify(clip.length === 3 && clip[0] > 0 && clip[1] > 0,
               "the Copy row writes a decodable non-empty range clip")

        menu = openTimeMenu(range.midX)
        pasteIndex = rulerRowIndex(menu, 13)
        verify(menu.rowItem(pasteIndex).itemData.enabled,
               "the reopened time-selection menu enables Paste for the copied range clip")
        var otherControl = control("timelineRulerDivisionControl")
        otherControl.forceActiveFocus()
        tryCompare(otherControl, "activeFocus", true)
        verify(bootstrap.clearClipboardProbe())
        tryVerify(rulerMenuGone, 3000,
                  "a clipboard eligibility flip retires the open time menu")
        compare(grid.appliedRevisionText, revision,
                "clipboard retirement does not edit the document")
        tryCompare(otherControl, "activeFocus", true)
        menu = openTimeMenu(range.midX)
        compare(rulerRowEnabled(menu, 13), false,
                "a rebuilt time menu disables Paste after clipboard clearing")
        clickRow(menu, rulerRowIndex(menu, 11))
        tryVerify(rulerMenuGone, 3000)

        menu = openTimeMenu(range.midX)
        pasteIndex = rulerRowIndex(menu, 13)
        verify(menu.rowItem(pasteIndex).itemData.enabled)
        clickRow(menu, pasteIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the enabled time-menu Paste activation closes the menu")

        menu = openRulerMenu(cursorX, y)
        verify(rulerRowIndex(menu, 11) < 0 && rulerRowIndex(menu, 12) < 0,
               "an outside ruler press drops Copy and Cut with the time selection")
        verify(rulerRowEnabled(menu, 13),
               "the reopened cursor menu enables Paste for the copied range clip")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)
    }

    function test_rulerSelectionInsertTimeRowsShiftNotesAndUndo() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var menuOwner = surface().rulerMenu

        var range = sweepNoteRange()
        var layout = noteLayout()
        var menu = openRulerMenu(range.midX, ruler.height * 0.75)
        verify(rulerRowIndex(menu, 5) >= 0, "the inside ruler press opens the in-selection menu")
        var insertIndex = rulerRowIndex(menu, 1)
        verify(menu.rowItem(insertIndex).itemData.enabled,
               "the in-selection menu offers an enabled Insert Time row")
        var revision = grid.appliedRevisionText
        clickRow(menu, insertIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the in-selection Insert Time activation closes the ruler menu")
        compare(menuOwner.insertTimePromptOpen, false)
        tryVerify(function() {
            return grid.appliedRevisionText !== revision && noteLayout() !== layout
        }, 3000, "the in-selection Insert Time row shifts the rendered notes")
        verify(Math.abs(rulerTickX(grid.editCursorTick) - range.startX) <= rulerCellPixels(),
               "the ruler Insert Time row parks the cursor at the selected start seam")
        compare(session.gridCommandAvailable(17), true,
                "the ruler insertion retains the time selection over the blank span")
        session.requestUndo()
        verify(waitForNative(function() { return noteLayout() === layout }, 5000),
               "one undo restores the rendered notes before the ruler insertion")

        range = sweepNoteRange()
        menu = openTimeMenu(range.midX)
        insertIndex = rulerRowIndex(menu, 1)
        verify(menu.rowItem(insertIndex).itemData.enabled,
               "the time-selection menu offers an enabled Insert Time row")
        revision = grid.appliedRevisionText
        clickRow(menu, insertIndex)
        tryVerify(rulerMenuGone, 3000,
                  "the time-menu Insert Time activation closes the menu")
        tryVerify(function() {
            return grid.appliedRevisionText !== revision && noteLayout() !== layout
        }, 3000, "the time-menu Insert Time row shifts the rendered notes")
        verify(Math.abs(rulerTickX(grid.editCursorTick) - range.startX) <= rulerCellPixels(),
               "the time-menu Insert Time row parks the cursor at the selected start seam")
        compare(session.gridCommandAvailable(17), true,
                "the time-menu insertion retains the time selection over the blank span")
        session.requestUndo()
        verify(waitForNative(function() { return noteLayout() === layout }, 5000),
               "one undo restores the rendered notes before the time-menu insertion")
    }

    function test_timeMenuRenderedPasteRejectsOverlapWithoutEmissions() {
        var session = openSong()
        var grid = surface().gridModel
        var range = sweepNoteRange()
        var notes = JSON.parse(grid.noteSummary)
        var latest = 0
        for (var index = 0; index < notes.length; ++index)
            latest = Math.max(latest, notes[index].tick + notes[index].duration)
        var destination = Math.ceil((latest + grid.snapTicks) / grid.snapTicks)
            * grid.snapTicks
        var clip = {
            format: 1, ticksPerBeat: grid.ticksPerBeat, span: 24, wholeLane: false,
            tracks: [{ track: grid.trackIndex, notes: [
                { relTick: 0, key: 55, duration: 12, velocity: 91 },
                { relTick: 1, key: 55, duration: 12, velocity: 91 }
            ] }], lanes: [], tempo: []
        }
        verify(clipProbe.writeClipJson(JSON.stringify(clip)))
        grid.setEditCursorTick(destination)
        var menu = openTimeMenu(range.midX)
        menuCursorSpy.target = grid
        menuStatusSpy.target = grid
        menuCursorSpy.clear()
        menuStatusSpy.clear()
        var before = grid.noteSummary
        var revision = grid.appliedRevisionText
        clickRow(menu, rulerRowIndex(menu, 13))
        compare(grid.noteSummary, before,
                "a conflicting range paste via the rendered row preserves the notes")
        compare(grid.appliedRevisionText, revision,
                "a conflicting range paste via the rendered row preserves the revision")
        compare(menuCursorSpy.count, 0,
                "a conflicting range paste via the rendered row emits no cursor movement")
        compare(menuStatusSpy.count, 0,
                "a conflicting range paste via the rendered row emits no status announcement")
        menuCursorSpy.target = null
        menuStatusSpy.target = null
    }

    function test_timeMenuRenderedRangePasteClearsSelectionAndAdvancesCursor() {
        var session = openSong()
        var grid = surface().gridModel
        var range = sweepNoteRange()
        var notes = JSON.parse(grid.noteSummary)
        var latest = 0
        for (var index = 0; index < notes.length; ++index)
            latest = Math.max(latest, notes[index].tick + notes[index].duration)
        var destination = Math.ceil((latest + grid.snapTicks) / grid.snapTicks)
            * grid.snapTicks
        var span = 2 * Math.max(1, grid.snapTicks)
        var clip = {
            format: 1, ticksPerBeat: grid.ticksPerBeat, span: span, wholeLane: false,
            tracks: [{ track: grid.trackIndex, notes: [
                { relTick: 0, key: 55, duration: span, velocity: 91 }
            ] }], lanes: [], tempo: []
        }
        verify(clipProbe.writeClipJson(JSON.stringify(clip)))
        grid.setEditCursorTick(destination)
        var menu = openTimeMenu(range.midX)
        menuCursorSpy.target = grid
        menuStatusSpy.target = grid
        menuCursorSpy.clear()
        menuStatusSpy.clear()
        var revision = grid.appliedRevisionText
        clickRow(menu, rulerRowIndex(menu, 13))
        tryVerify(rulerMenuGone, 3000)
        tryVerify(function() { return grid.appliedRevisionText !== revision }, 3000)
        compare(session.gridCommandAvailable(17), false,
                "an admitted range paste drops the time selection")
        compare(grid.editCursorTick, destination + span,
                "an admitted range paste via the rendered row advances by the clip span")
        compare(menuCursorSpy.count, 1,
                "an admitted paste publishes exactly one cursor move")
        compare(menuStatusSpy.count, 1,
                "an admitted paste publishes exactly one status update")
        verify(JSON.parse(grid.noteSummary).some(function(note) {
            return note.tick === destination && note.pitch === 55 && note.duration === span
        }), "an admitted range paste writes its note at the captured cursor")
        menuCursorSpy.target = null
        menuStatusSpy.target = null
    }


    function test_rulerDragThresholdAndRightDragMenu() {
        openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var start = ruler.width * 0.3
        var end = ruler.width * 0.45
        var y = ruler.height * 0.75
        mousePress(ruler, start, y, Qt.LeftButton)
        mouseMove(ruler, start + grid.dragDistance / 3, y, -1, Qt.LeftButton)
        mouseRelease(ruler, start + grid.dragDistance / 3, y, Qt.LeftButton)
        compare(shell.shellPresenter.session.gridCommandAvailable(17), false,
                "a sub-threshold ruler press releases as a cursor tap, not a selection")
        mousePress(ruler, start, y, Qt.LeftButton)
        mouseMove(ruler, end, y, -1, Qt.LeftButton)
        mouseRelease(ruler, end, y, Qt.LeftButton)
        compare(shell.shellPresenter.session.gridCommandAvailable(17), true,
                "a ruler drag past the drag threshold creates the exact snapped selection")
        mouseClick(ruler, ruler.width * 0.8, y, Qt.LeftButton)
        compare(shell.shellPresenter.session.gridCommandAvailable(17), true,
                "a left click outside the time selection keeps it")
        mousePress(ruler, start, y, Qt.RightButton)
        mouseMove(ruler, end, y, -1, Qt.RightButton)
        compare(shell.shellPresenter.session.gridCommandAvailable(17), true,
                "a ruler right-drag creates no time selection")
        mouseRelease(ruler, end, y, Qt.RightButton)
        tryVerify(rulerMenuShown, 3000,
                  "releasing a ruler right-drag opens the ruler menu")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000,
                  "Escape dismisses the right-drag ruler menu")
    }

    function test_controlRulerSweepPublishesSecondaryHeaderOverlay() {
        openSong()
        var grid = surface().gridModel
        var ruler = control("timelineRulerInput")
        var rows = control("timelineTrackHeaderRows")
        var notes = JSON.parse(grid.noteSummary)
        var note = null
        for (var index = 0; index < notes.length && note === null; ++index) {
            var candidate = notes[index]
            if (candidate.track !== grid.trackIndex
                && rulerTickX(candidate.tick) > ruler.width * 0.15
                && rulerTickX(candidate.tick + candidate.duration) < ruler.width * 0.6)
                note = candidate
        }
        verify(note !== null,
               "the fixture presents a secondary-track note inside the ruler viewport")
        var row = null
        for (var rowIndex = 0; rowIndex < rows.count; ++rowIndex) {
            if (rows.itemAt(rowIndex) && rows.itemAt(rowIndex).track === note.track) {
                row = rows.itemAt(rowIndex)
                break
            }
        }
        verify(row !== null, "the note's secondary header row is mounted")
        compare(row.overlayColor.a, 0)
        var startX = rulerTickX(note.tick) - rulerCellPixels()
        var endX = rulerTickX(note.tick + note.duration) + rulerCellPixels()
        var y = ruler.height * 0.75
        mousePress(ruler, startX, y, Qt.LeftButton, Qt.ControlModifier)
        mouseMove(ruler, endX, y, -1, Qt.LeftButton, Qt.ControlModifier)
        mouseRelease(ruler, endX, y, Qt.LeftButton, Qt.ControlModifier)
        compare(shell.shellPresenter.session.gridCommandAvailable(17), true,
                "a Control ruler drag adds the overlapping track to the scope")
        tryVerify(function() { return row.overlayColor.a > 0 }, 3000,
                  "the time-scoped secondary header publishes its selection overlay")
    }

    function test_rollKeysEditTimeScopedNotesAndEmptyClickClearsBand() {
        var session = openSong()
        var grid = surface().gridModel
        var roll = control("swiftRollInput")
        var range = sweepNoteRange()
        var initial = JSON.parse(grid.noteSummary)
        var covered = null
        for (var index = 0; index < initial.length && covered === null; ++index) {
            var note = initial[index]
            if (!note.ghost && note.track === grid.trackIndex
                && rulerTickX(note.tick) > range.startX
                && rulerTickX(note.tick + note.duration) < range.endX)
                covered = note
        }
        verify(covered !== null, "the selection covers a mounted primary-track note")
        roll.forceActiveFocus(Qt.OtherFocusReason)
        keyClick(Qt.Key_Up)
        tryVerify(function() {
            return JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === covered.id && note.pitch === covered.pitch + 1
            })
        }, 3000, "Up with an active time selection transposes the covered note")
        keyClick(Qt.Key_Right)
        tryVerify(function() {
            return JSON.parse(grid.noteSummary).some(function(note) {
                return note.id === covered.id && note.tick === covered.tick + grid.snapTicks
            })
        }, 3000, "Right with an active time selection nudges the covered note")
        compare(session.gridCommandAvailable(17), true,
                "Right with an active time selection retains the moved band")
        var oldStartX = range.startX + rulerCellPixels() / 2
        surface().rulerMenu.openTimeSelection(oldStartX)
        compare(surface().rulerMenu.menuKind, 0,
                "Right over an active time selection advances the band start")
        surface().rulerMenu.openTimeSelection(oldStartX + rulerCellPixels())
        compare(surface().rulerMenu.menuKind, 2,
                "the nudged time band still accepts a press inside its new bounds")
        surface().rulerMenu.close()
        var emptyX = oldStartX + rulerCellPixels()
        var emptyY = roll.height * 0.85
        var occupied = false
        var after = JSON.parse(grid.noteSummary)
        for (var noteIndex = 0; noteIndex < after.length; ++noteIndex) {
            var tile = findChild(surface(), "gridNote_" + after[noteIndex].id)
            if (!tile || after[noteIndex].ghost)
                continue
            var corner = tile.mapToItem(roll, 0, 0)
            occupied = occupied || (emptyX >= corner.x && emptyX < corner.x + tile.width
                                    && emptyY >= corner.y && emptyY < corner.y + tile.height)
        }
        verify(!occupied, "the in-band roll click targets empty note space")
        mouseClick(roll, emptyX, emptyY, Qt.LeftButton)
        compare(session.gridCommandAvailable(17), false,
                "a left click on empty roll space inside the selection clears it")
        compare(JSON.parse(grid.noteSummary).some(function(note) { return note.selected }), false,
                "time-selection keys and the empty click do not leak a note selection")
    }

    function test_rulerClearSelectionAndRetirementFocus() {
        var session = openSong()
        var ruler = control("timelineRulerInput")
        var grid = surface().gridModel
        var range = sweepNoteRange()
        mouseClick(ruler, range.midX, ruler.height * 0.75, Qt.RightButton)
        tryVerify(rulerMenuShown, 3000)
        var menu = rulerPanel()
        clickRow(menu, rulerRowIndex(menu, 8))
        tryVerify(rulerMenuGone, 3000,
                  "the Clear Time Selection row closes the menu and drops the selection")
        compare(session.gridCommandAvailable(17), false)
        menu = openRulerMenu(range.midX, ruler.height * 0.75)
        compare(rulerRowIndex(menu, 8), -1,
                "the rebuilt ruler menu drops selection-scoped rows after Clear Time Selection")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)
        menu = clearRulerLoop(range.startX, ruler.height * 0.75)
        clickRow(menu, rulerRowIndex(menu, 2))
        var markerTick = grid.editCursorTick
        tryVerify(function() { return loopMarkerAt("loopStartMarker", markerTick) }, 3000)
        menu = openRulerMenu(range.startX, ruler.height * 0.75)
        tryVerify(function() { return menu.parent.activeFocus }, 3000,
                  "the ruler menu host owns focus before the Undo edit")
        verify(surface().menuHostHeldFocus,
               "the menu focus witness is armed before the window Undo")
        verify(shell.shellPresenter.actionEnabled("edit.undo"),
               "Undo remains enabled at window level while the ruler menu is open")
        var undoRevision = grid.appliedRevisionText
        shell.shellPresenter.activate("edit.undo")
        verify(waitForNative(function() {
            return grid.appliedRevisionText !== undoRevision
                && loopMarkerAbsent("loopStartMarker")
        }, 5000), "the window Undo edits the open ruler menu's document")
        tryVerify(rulerMenuGone, 3000,
                  "a document edit retires the open ruler menu and refocuses the ruler band")
        tryVerify(function() { return loopMarkerAbsent("loopStartMarker") }, 3000)
        tryCompare(ruler, "activeFocus", true)
        menu = openRulerMenu(range.midX, ruler.height * 0.75)
        surface().rulerMenu.beginSweep(range.startX, ruler.height * 0.75, 0)
        surface().rulerMenu.updateSweep(range.endX, ruler.height * 0.75)
        surface().rulerMenu.endSweep(range.endX, ruler.height * 0.75)
        tryVerify(rulerMenuGone, 3000,
                  "a selection change retires the open ruler menu and refocuses the ruler band")
        tryCompare(ruler, "activeFocus", true)
    }

    function test_timeMenuEscapePreservesSelectionAndRefocuses() {
        openSong()
        var range = sweepNoteRange()
        var grid = surface().gridModel
        var revision = grid.appliedRevisionText
        openTimeMenu(range.midX)
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000, "Escape dismisses the time menu")
        compare(shell.shellPresenter.session.gridCommandAvailable(17), true,
                "the time selection survives a time-menu Escape")
        compare(grid.appliedRevisionText, revision,
                "a time-menu Escape writes nothing")
        tryCompare(control("swiftRollInput"), "activeFocus", true, 3000,
                   "a time-menu Escape refocuses the roll band")
    }


    function test_forkRulerAndTimeMenuWordingAndHints() {
        openSong()
        var ruler = control("timelineRulerInput")
        var menu = openRulerMenu(ruler.width * 0.6, ruler.height * 0.75)
        compare(menu.rowItem(rulerRowIndex(menu, 2)).itemData.text,
                "Set Loop Start at Edit Cursor", "the ruler cursor menu shows the fork row wording")
        compare(menu.rowItem(rulerRowIndex(menu, 13)).itemData.text,
                "Paste at Edit Cursor", "the ruler Paste row keeps the edit cursor wording")
        compare(menu.rowItem(rulerRowIndex(menu, 1)).itemData.shortcutText,
                shell.shellPresenter.actionShortcut("edit.insert_time"),
                "action-backed ruler rows show their native shortcut hint")
        verify(menu.shortcutRight > menu.textRight,
               "the rendered ruler panel reserves a visible shortcut column")
        keyClick(Qt.Key_Escape)
        tryVerify(rulerMenuGone, 3000)

        var range = sweepNoteRange()
        menu = openTimeMenu(range.midX)
        compare(menu.rowItem(rulerRowIndex(menu, 11)).itemData.text,
                "Copy Selection", "the shared time menu shows the fork row wording")
        compare(menu.rowItem(rulerRowIndex(menu, 13)).itemData.text,
                "Paste at Edit Cursor", "the shared time menu keeps the cursor wording")
        compare(menu.rowItem(rulerRowIndex(menu, 11)).itemData.shortcutText,
                shell.shellPresenter.actionShortcut("roll.copy"),
                "the time-menu Copy row shows the native shortcut")
        verify(menu.shortcutRight > menu.textRight,
               "the rendered time panel reserves a visible shortcut column")
    }

    function stageAutomationMenuPoint() {
        var view = surface()
        var toggle = findChild(view, "drawerToggle_automation")
        verify(toggle && toggle.visible, "the automation drawer toggle is mounted")
        mouseClick(toggle, toggle.width / 2, toggle.height / 2)
        var page = null
        tryVerify(function() {
            page = findChild(view, "automationPage")
            return page && page.visible && page.height > 0
        }, 3000, "the automation page is mounted")
        var plot = findChild(page, "automationPlotInput")
        verify(plot && plot.width > 0 && plot.height > 0, "the automation plot accepts a pointer")
        var y = plot.height / 2
        mousePress(plot, plot.width * 0.3, y, Qt.LeftButton)
        mouseMove(plot, plot.width * 0.45, y, -1, Qt.LeftButton)
        mouseRelease(plot, plot.width * 0.45, y, Qt.LeftButton)
        tryVerify(function() { return page.pageModel.nodeCount > 1 }, 3000,
                  "the plotted gesture writes a point")
        function writtenNode(item) {
            if (item.objectName === "automationNode" && item.model
                && !item.model.projected && !item.model.phantom)
                return item.model
            for (var index = 0; index < item.children.length; ++index) {
                var node = writtenNode(item.children[index])
                if (node)
                    return node
            }
            return null
        }
        var node = writtenNode(page)
        verify(node !== null, "the written point has a plotted hit target")
        return { page: page, plot: plot, node: node }
    }

    function test_automationPointMenuYieldsToPublishedDivisionMenu() {
        openSong()
        var staged = stageAutomationMenuPoint()
        var model = staged.page.pageModel
        var grid = surface().gridModel
        var revision = grid.appliedRevisionText
        mouseClick(staged.plot, staged.node.x, staged.node.y, Qt.RightButton)
        tryCompare(model, "menuOpen", true)
        compare(model.menuRowCount, 2, "the point menu captures the written node")
        mouseClick(control("timelineRulerDivisionControl"))
        tryCompare(grid, "gridMenuKind", 1)
        tryCompare(model, "menuOpen", false, 3000,
                   "the published division menu dismisses the open point menu")
        var menu = panel()
        var pickedId = alternateGridMenuId(grid.gridSelectionMenuId)
        clickRow(menu, [-1, 4, 8, 16, 32, 0].indexOf(pickedId))
        tryCompare(grid, "gridSelectionMenuId", pickedId)
        tryCompare(control("timelineRulerInput"), "activeFocus", true, 3000,
                   "the division pick returns focus to the publishing control")
        compare(grid.appliedRevisionText, revision, "the takeover and grid pick write no MIDI")
        compare(model.promptOpen, false, "a displaced point target cannot open a late prompt")
    }

    function test_automationBandMissFallsThroughToTimeMenu() {
        openSong()
        var staged = stageAutomationMenuPoint()
        var plot = staged.plot
        var model = staged.page.pageModel
        var startX = plot.width * 0.25
        var endX = plot.width * 0.65
        var midX = (startX + endX) / 2
        var y = plot.height * 0.15
        var revision = surface().gridModel.appliedRevisionText
        mousePress(plot, startX, y, Qt.RightButton)
        mouseMove(plot, endX, y, -1, Qt.RightButton)
        mouseRelease(plot, endX, y, Qt.RightButton)
        mouseClick(plot, midX, y, Qt.RightButton)
        tryCompare(surface().rulerMenu, "menuKind", 2, 3000,
                   "the fallback time menu opens from the automation band")
        var menu = panel()
        compare(menu.rowItem(0).itemData.actionId, 11,
                "the fallback menu renders the shared time-selection commands")
        keyClick(Qt.Key_Escape)
        tryCompare(surface().rulerMenu, "isOpen", false, 3000,
                   "Escape closes the band's fallback menu")
        compare(model.menuOpen, false, "the band miss never publishes an automation menu")
        compare(surface().gridModel.appliedRevisionText, revision,
                "the time selection and fallback dismissal write no MIDI")
    }

}
