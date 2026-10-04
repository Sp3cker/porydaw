pragma ComponentBehavior: Bound

import QtQuick
import PorydawApp

FocusScope {
    id: page

    anchors.fill: parent
    clip: true

    required property EventListPresenter presenter
    readonly property EventListPresenter controller: presenter
    readonly property var appearance: controller ? controller.appearance : ({})
    readonly property var headerLabels: controller ? controller.headerLabels : []
    // Revision invalidates membership bindings without copying selection into QML.
    readonly property int selectionRevision: controller ? controller.selectionRevision : 0

    readonly property int columnCount: 7
    readonly property int resizableColumnCount: 6

    property int currentColumn: 0
    // Window-wide shortcuts must only operate while that input owns navigation.
    property bool navigationInputActive: activeFocus

    readonly property int editingRow: controller ? controller.editingRow : -1
    readonly property int editingColumn: controller ? controller.editingColumn : -1
    property int dragFromRow: -1
    property int dragDropGap: -1
    property bool draggingRows: false

    readonly property bool editing: controller && controller.editing
    readonly property bool navigationEnabled: controller && controller.visible && navigationInputActive
                                             && !editing && !controller.menuOpen

    readonly property font bodyFont: Qt.font(appearanceValue("bodyFont", ({})))
    readonly property font tableFont: Qt.font(appearanceValue("tableFont", ({})))
    readonly property font headerFont: Qt.font(appearanceValue("headerFont", ({})))
    readonly property font controlFont: Qt.font(appearanceValue("controlFont", ({})))

    readonly property color tableBackground: appearanceValue("tableBackground", "transparent")
    readonly property color tableAlternateBackground: appearanceValue("tableAlternateBackground",
                                                                        tableBackground)
    readonly property color tableText: appearanceValue("tableText", "transparent")
    readonly property color tableSecondaryText: appearanceValue("tableSecondaryText", tableText)
    readonly property color tableSelectedBackground: appearanceValue("tableSelectedBackground",
                                                                       "transparent")
    readonly property color tableSelectedText: appearanceValue("tableSelectedText", tableText)
    readonly property color tableOutline: appearanceValue("tableOutline", "transparent")
    readonly property color playheadTint: appearanceValue("playheadTint", "#2CE24244")
    readonly property color headerBackground: appearanceValue("headerBackground", tableBackground)
    readonly property color headerText: appearanceValue("headerText", tableText)
    readonly property color headerOutline: appearanceValue("headerOutline", tableOutline)
    readonly property color buttonBackground: appearanceValue("buttonBackground", tableBackground)
    readonly property color buttonText: appearanceValue("buttonText", tableText)
    readonly property color buttonHoverBackground: appearanceValue("buttonHoverBackground",
                                                                      buttonBackground)
    readonly property color buttonPressedBackground: appearanceValue("buttonPressedBackground",
                                                                        buttonHoverBackground)
    readonly property color buttonPressedText: appearanceValue("buttonPressedText", buttonText)
    readonly property color disabledText: appearanceValue("disabledText", tableSecondaryText)
    readonly property color buttonOutline: appearanceValue("buttonOutline", tableOutline)
    readonly property color inputBackground: appearanceValue("inputBackground", tableBackground)
    readonly property color inputText: appearanceValue("inputText", tableText)
    readonly property color inputOutline: appearanceValue("inputOutline", tableOutline)
    readonly property color focusOutline: appearanceValue("focusOutline", inputOutline)
    readonly property color scrollbarHandle: appearanceValue("scrollbarHandle", tableOutline)
    readonly property color scrollbarHandleHover: appearanceValue("scrollbarHandleHover",
                                                                     scrollbarHandle)
    readonly property color toolTipBackground: appearanceValue("toolTipBackground", buttonBackground)
    readonly property color toolTipTextColor: appearanceValue("toolTipText", buttonText)
    readonly property color toolTipOutline: appearanceValue("toolTipOutline", buttonOutline)
    readonly property color reorderIndicator: appearanceValue("reorderIndicator", focusOutline)

    readonly property real cellHorizontalPadding: Math.max(4, Math.ceil(tableMetrics.height / 3))
    readonly property real headerHorizontalPadding: Math.max(4, Math.ceil(headerMetrics.height / 3))
    readonly property real rowHeight: Math.max(1, Math.ceil(tableMetrics.height + 6))
    readonly property real toolbarHeight: Math.max(rowHeight, Math.ceil(controlMetrics.height + 4))
    readonly property real headerHeight: Math.max(rowHeight, Math.ceil(headerMetrics.height + 8))
    readonly property real scrollbarBreadth: Math.max(10, Math.ceil(tableMetrics.height * 0.85))
    readonly property real rowHeaderWidth: Math.max(Math.ceil(headerMetrics.advanceWidth(
                                                          String(Math.max(1, table.eventTable.rows)))
                                                          + 2 * headerHorizontalPadding),
                                                    Math.ceil(headerMetrics.height * 2))
    readonly property real summaryMinimumWidth: Math.max(
                                                       tableMetrics.advanceWidth(qsTr("End of track"))
                                                       + 2 * cellHorizontalPadding,
                                                       headerMetrics.advanceWidth(qsTr("Summary"))
                                                       + 2 * headerHorizontalPadding)

    signal navigationFocusRequested()
    onNavigationFocusRequested: navigationFocus.forceActiveFocus(Qt.OtherFocusReason)
    Component.onCompleted: {
        controller.setVisible(visible)
        table.publishTableRows()
    }

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

    function appearanceValue(name: string, fallback: var): var {
        const value = appearance ? appearance[name] : undefined
        return value === undefined || value === null ? fallback : value
    }

    function valueText(value: var): string {
        return value === undefined || value === null ? "" : String(value)
    }

    // R7: dependency read; stays uncompiled until Wave B publishes this as row data.
    function rowIsSelected(row) {
        const revision = selectionRevision
        return controller && controller.isSelected(row)
    }


    // R7: dependency read; stays uncompiled until Wave B publishes this as row data.
    function persistedColumnWidth(column) {
        const revision = controller ? controller.columnWidthsRevision : 0
        const candidate = controller ? Number(controller.savedColumnWidth(column))
                                     : minimumColumnWidth(column)
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
        const item = panel.rowItem(row)
        if (!item || !item.active)
            return
        const actionId = item.itemData.actionId
        controller.activateMenuAction(actionId)
        if (controller.menuOpen) {
            Qt.callLater(function() {
                if (!page.controller.menuOpen)
                    return
                for (let index = 0; index < panel.rowCount; ++index) {
                    const candidate = panel.rowItem(index)
                    if (candidate && candidate.itemData.actionId === actionId) {
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
            const cell = table.eventTable.itemAtCell(Qt.point(page.currentColumn, row))
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
    onVisibleChanged: {
        if (controller)
            controller.setVisible(visible)
    }

    Connections {
        target: page.controller

        function onColumnWidthsRevisionChanged(): void {
            table.requestTableLayout()
        }

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
