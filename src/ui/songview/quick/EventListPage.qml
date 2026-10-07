pragma ComponentBehavior: Bound

import QtQuick
import PorydawApp
import Porydaw.Ui

FocusScope {
    id: page

    anchors.fill: parent
    clip: true

    final required property EventListPresenter presenter
    final readonly property EventListPresenter controller: presenter
    final readonly property list<string> headerLabels: controller.headerLabels

    final readonly property int columnCount: 7
    final readonly property int resizableColumnCount: 6

    final property int currentColumn: 0
    // Window-wide shortcuts must only operate while that input owns navigation.
    final property bool navigationInputActive: activeFocus

    final readonly property int editingRow: controller ? controller.editingRow : -1
    final readonly property int editingColumn: controller ? controller.editingColumn : -1
    final property int dragFromRow: -1
    final property int dragDropGap: -1
    final property bool draggingRows: false

    final readonly property bool editing: controller && controller.editing
    final readonly property bool navigationEnabled: controller && controller.visible && navigationInputActive
                                             && !editing && !controller.menuOpen

    final readonly property font bodyFont: controller.fonts.body
    final readonly property font tableFont: controller.fonts.tableMono
    final readonly property font headerFont: controller.fonts.caption
    final readonly property font controlFont: controller.fonts.body

    final readonly property color tableBackground: controller.colors.menuBackground
    final readonly property color tableAlternateBackground: controller.colors.alternateBackground
    final readonly property color tableText: controller.colors.windowText
    final readonly property color tableSecondaryText: controller.colors.secondaryText
    final readonly property color tableSelectedBackground: controller.colors.tabSelectedBackground
    final readonly property color tableSelectedText: controller.colors.selectionText
    final readonly property color tableOutline: controller.colors.outline
    final readonly property color playheadTint: controller.playheadTint
    final readonly property color headerBackground: controller.colors.chromeBackground
    final readonly property color headerText: controller.colors.windowText
    final readonly property color headerOutline: controller.colors.outline
    final readonly property color buttonBackground: controller.colors.buttonBackground
    final readonly property color buttonText: controller.colors.buttonText
    final readonly property color buttonHoverBackground: controller.colors.buttonHoverBackground
    final readonly property color buttonPressedBackground: controller.colors.buttonPressedBackground
    final readonly property color buttonPressedText: controller.colors.buttonPressedText
    final readonly property color disabledText: controller.colors.disabledText
    final readonly property color buttonOutline: controller.colors.outline
    final readonly property color inputBackground: controller.colors.buttonHoverBackground
    final readonly property color inputText: controller.colors.windowText
    final readonly property color inputOutline: controller.colors.outline
    final readonly property color focusOutline: controller.colors.focusOutline
    final readonly property color scrollbarHandle: controller.colors.scrollbarHandle
    final readonly property color scrollbarHandleHover: controller.colors.outline
    final readonly property color toolTipBackground: controller.colors.inputBackground
    final readonly property color toolTipTextColor: controller.colors.windowText
    final readonly property color toolTipOutline: controller.colors.outline
    final readonly property color reorderIndicator: controller.colors.focusOutline

    final readonly property real cellHorizontalPadding: Math.max(4, Math.ceil(tableMetrics.height / 3))
    final readonly property real headerHorizontalPadding: Math.max(4, Math.ceil(headerMetrics.height / 3))
    final readonly property real rowHeight: Math.max(1, Math.ceil(tableMetrics.height + 6))
    final readonly property real toolbarHeight: Math.max(rowHeight, Math.ceil(controlMetrics.height + 4))
    final readonly property real headerHeight: Math.max(rowHeight, Math.ceil(headerMetrics.height + 8))
    final readonly property real scrollbarBreadth: Math.max(10, Math.ceil(tableMetrics.height * 0.85))
    final readonly property string rowCountText: Math.max(1, table.eventTable.rows)
    final readonly property real rowHeaderWidth: Math.max(Math.ceil(headerMetrics.advanceWidth(
                                                          rowCountText)
                                                          + 2 * headerHorizontalPadding),
                                                    Math.ceil(headerMetrics.height * 2))
    final readonly property real summaryMinimumWidth: Math.max(
                                                       tableMetrics.advanceWidth(qsTr("End of track"))
                                                       + 2 * cellHorizontalPadding,
                                                       headerMetrics.advanceWidth(qsTr("Summary"))
                                                       + 2 * headerHorizontalPadding)

    signal navigationFocusRequested()
    onNavigationFocusRequested: navigationFocus.forceActiveFocus(Qt.OtherFocusReason)

    // The scope remembers its last focused child. Return from cell editing
    // to a non-text leaf so Delete and Select All reach the shared router.
    Item {
        id: navigationFocus
        focus: true
    }

    FontMetrics {
        id: tableMetrics
        font: page.tableFont
    }

    FontMetrics {
        id: headerMetrics
        font: page.headerFont
    }

    FontMetrics {
        id: controlMetrics
        font: page.controlFont
    }

    EventListToolbar {
        id: toolbar
        page: parent
        controller: page.controller
    }

    EventListTable {
        id: table
        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        page: parent
        controller: page.controller
        tableFontMetrics: tableMetrics
        headerFontMetrics: headerMetrics
    }

    function rowIsSelected(row: int): bool {
        if (row < 0 || row >= controller.rowCount)
            return false
        const handle = controller.rowHandle(row)
        return handle && handle.selected
    }

    function persistedColumnWidth(column: int): real {
        let candidate = minimumColumnWidth(column)
        switch (column) {
        case 0: candidate = controller.tickColumnWidth; break
        case 1: candidate = controller.typeColumnWidth; break
        case 2: candidate = controller.channelColumnWidth; break
        case 3: candidate = controller.data1ColumnWidth; break
        case 4: candidate = controller.data2ColumnWidth; break
        case 5: candidate = controller.dataColumnWidth; break
        }
        return Math.max(minimumColumnWidth(column), candidate)
    }

    function minimumColumnWidth(column: int): real {
        const label = headerLabels.length > column ? headerLabels[column] : ""
        return Math.max(Math.ceil(tableMetrics.height * 2),
                        Math.ceil(headerMetrics.advanceWidth(label) + 2 * headerHorizontalPadding))
    }

    function persistedColumnsWidth(): real {
        let width = 0
        for (let column = 0; column < resizableColumnCount; ++column)
            width += persistedColumnWidth(column)
        return width
    }

    function columnWidth(column: int): real {
        if (column < resizableColumnCount)
            return persistedColumnWidth(column)
        return Math.max(summaryMinimumWidth, table.eventTable.width - persistedColumnsWidth())
    }

    function columnOffset(column: int): real {
        let offset = 0
        for (let index = 0; index < column; ++index)
            offset += columnWidth(index)
        return offset
    }

    function hoverRow(panel: QuickMenuPanel, row: int): void { panel.highlightedRow = row }

    function activateRow(panel: QuickMenuPanel, row: int): void {
        const item = controller.menuItem(row)
        if (!item || !item.enabled || item.separator)
            return
        const actionId = item.actionId
        controller.activateMenuAction(actionId)
        if (controller.menuOpen) {
            Qt.callLater(function() {
                if (!page.controller.menuOpen)
                    return
                for (let index = 0; index < panel.rowCount; ++index) {
                    const candidate = page.controller.menuItem(index)
                    if (candidate && candidate.actionId === actionId) {
                        page.hoverRow(panel, index)
                        return
                    }
                }
            })
        }
    }

    function beginCellEdit(cell: EventListCell): void {
        if (!controller || editing || !cell || !cell.editable)
            return

        currentColumn = cell.column
        if (cell.column === 1) {
            const position = cell.mapToItem(page, cell.width / 2, cell.height)
            controller.openTypeMenu(position.x, position.y)
            return
        }

        if (!controller.beginEditing(cell.row, cell.column))
            return

        Qt.callLater(function() {
            if (page.editing && cell.editing)
                cell.focusEditor()
        })
    }

    function finishCellEdit(commit: bool, text: string, returnNavigationFocus: bool): bool {
        if (!controller || !editing)
            return false

        const finished = controller.finishEditing(text, commit)
        if (finished && returnNavigationFocus)
            navigationFocusRequested()
        return finished
    }



    function resetPointerState(): void {
        if (controller)
            controller.setPointerDown(false)
        dragFromRow = -1
        dragDropGap = -1
        draggingRows = false
    }


    function legalDropGap(gap: int): bool {
        return controller && dragFromRow >= 0 && gap >= 0 && gap <= table.eventTable.rows
                && controller.isLegalDrop(dragFromRow, gap)
    }

    function updateDragGap(cell: EventListCell, mouse: MouseEvent): void {
        const position = cell.mapToItem(table.eventTable, mouse.x, mouse.y)
        const gap = Math.max(0, Math.min(table.eventTable.rows,
                                         Math.floor((table.eventTable.contentY + position.y + rowHeight / 2)
                                                    / rowHeight)))
        dragDropGap = legalDropGap(gap) ? gap : -1
    }

    function selectRow(row: int, modifiers: int): void {
        if (!controller || row < 0 || row >= table.eventTable.rows)
            return
        controller.selectRow(row, modifiers)
    }


    function moveCurrentRow(delta: int, modifiers: int): void {
        if (!controller || table.eventTable.rows <= 0)
            return
        const current = controller.currentRow >= 0 ? controller.currentRow : 0
        const target = Math.max(0, Math.min(table.eventTable.rows - 1, current + delta))
        if (target === current && controller.currentRow >= 0)
            return
        selectRow(target, modifiers)
        table.eventTable.positionViewAtRow(target, TableView.Contain)
    }

    function moveCurrentColumn(delta: int): void {
        currentColumn = Math.max(0, Math.min(columnCount - 1, currentColumn + delta))
        table.eventTable.positionViewAtColumn(currentColumn, TableView.Contain)
    }

    function editCurrentCell(): void {
        if (!controller || controller.currentRow < 0)
            return
        const row = controller.currentRow
        table.eventTable.positionViewAtCell(Qt.point(page.currentColumn, row), TableView.Contain)
        Qt.callLater(function() {
            const cell = table.eventTable.itemAtCell(Qt.point(page.currentColumn, row)) as EventListCell
            page.beginCellEdit(cell)
        })
    }

    function pageCurrent(delta: int, modifiers: int): void {
        const pageRows = Math.max(1, Math.floor(table.eventTable.height / rowHeight))
        moveCurrentRow(delta * pageRows, modifiers)
    }

    Shortcut {
        sequence: "Up"
        enabled: page.navigationEnabled
        onActivated: page.moveCurrentRow(-1, Qt.NoModifier)
    }
    Shortcut {
        sequence: "Down"
        enabled: page.navigationEnabled
        onActivated: page.moveCurrentRow(1, Qt.NoModifier)
    }
    Shortcut {
        sequence: "Shift+Up"
        enabled: page.navigationEnabled
        onActivated: page.moveCurrentRow(-1, Qt.ShiftModifier)
    }
    Shortcut {
        sequence: "Shift+Down"
        enabled: page.navigationEnabled
        onActivated: page.moveCurrentRow(1, Qt.ShiftModifier)
    }
    Shortcut {
        sequence: "Left"
        enabled: page.navigationEnabled
        onActivated: page.moveCurrentColumn(-1)
    }
    Shortcut {
        sequence: "Right"
        enabled: page.navigationEnabled
        onActivated: page.moveCurrentColumn(1)
    }
    // Home belongs to row navigation here; elsewhere the window resets transport.
    Keys.onShortcutOverride: event => event.accepted = page.navigationEnabled
        && event.key === Qt.Key_Home && event.modifiers === Qt.NoModifier
    Keys.onPressed: event => {
        event.accepted = page.navigationEnabled && event.key === Qt.Key_Home
            && event.modifiers === Qt.NoModifier
        if (event.accepted)
            page.moveCurrentRow(-table.eventTable.rows, Qt.NoModifier)
    }
    Shortcut {
        sequence: "End"
        enabled: page.navigationEnabled
        onActivated: page.moveCurrentRow(table.eventTable.rows, Qt.NoModifier)
    }
    Shortcut {
        sequence: "PageUp"
        enabled: page.navigationEnabled
        onActivated: page.pageCurrent(-1, Qt.NoModifier)
    }
    Shortcut {
        sequence: "PageDown"
        enabled: page.navigationEnabled
        onActivated: page.pageCurrent(1, Qt.NoModifier)
    }
    Shortcut {
        sequence: "F2"
        enabled: page.navigationEnabled
        onActivated: page.editCurrentCell()
    }
    Shortcut {
        sequence: "Return"
        enabled: page.navigationEnabled
        onActivated: page.editCurrentCell()
    }
    Shortcut {
        sequence: "Enter"
        enabled: page.navigationEnabled
        onActivated: page.editCurrentCell()
    }

    EventListMenu {
        anchors.fill: parent
        page: parent
        controller: page.controller
        headerFontMetrics: headerMetrics
        controlFontMetrics: controlMetrics
    }

    Connections {
        target: page.controller

        function onTickColumnWidthChanged(): void { table.requestTableLayout() }
        function onTypeColumnWidthChanged(): void { table.requestTableLayout() }
        function onChannelColumnWidthChanged(): void { table.requestTableLayout() }
        function onData1ColumnWidthChanged(): void { table.requestTableLayout() }
        function onData2ColumnWidthChanged(): void { table.requestTableLayout() }
        function onDataColumnWidthChanged(): void { table.requestTableLayout() }

        function onScrollToRow(row: int): void {
            if (row >= 0)
                table.eventTable.positionViewAtRow(row, TableView.Contain)
        }


        function onVisibleChanged(): void {
            if (!page.controller.visible && page.editing)
                page.finishCellEdit(false, "", false)
        }
    }
}
