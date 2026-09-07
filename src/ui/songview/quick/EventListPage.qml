import QtQuick

Item {
    id: page

    anchors.fill: parent
    clip: true

    // The controller owns document state, selection semantics, editing commits,
    // menus, and legal reorder bounds. This renderer owns only the rendered
    // table's local focus, pointer, and scroll geometry.
    readonly property var controller: eventListController
    readonly property var appearance: controller ? controller.appearance : ({})
    readonly property var headerLabels: controller ? controller.headerLabels : []
    // This makes selectedRowsChanged invalidate bindings; membership stays O(1).
    readonly property var selectedRows: controller ? controller.selectedRows : []


    readonly property int columnCount: 7
    readonly property int resizableColumnCount: 6
    readonly property var defaultColumnWidths: [70, 120, 36, 56, 56, 140]

    property int currentColumn: 0
    // Bound by TimelineCanvas to its sibling TimelineInputItem.activeFocus.
    // Window-wide shortcuts must only operate while that input owns navigation.
    property bool navigationInputActive: false

    readonly property int editingRow: controller ? controller.editingRow : -1
    readonly property int editingColumn: controller ? controller.editingColumn : -1
    property int dragFromRow: -1
    property int dragDropGap: -1
    property bool tableLayoutPending: false
    property bool draggingRows: false

    readonly property bool editing: controller && controller.editing
    readonly property bool navigationEnabled: controller && controller.visible && navigationInputActive
                                             && !editing && !controller.menuOpen

    readonly property font bodyFont: appearanceValue("bodyFont", controlFont)
    readonly property font tableFont: appearanceValue("tableFont", bodyFont)
    readonly property font headerFont: appearanceValue("headerFont", bodyFont)
    readonly property font controlFont: appearanceValue("controlFont", Qt.application.font)

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
                                                          String(Math.max(1, eventTable.rows)))
                                                          + 2 * headerHorizontalPadding),
                                                    Math.ceil(headerMetrics.height * 2))
    readonly property real summaryMinimumWidth: Math.max(
                                                       tableMetrics.advanceWidth(qsTr("End of track"))
                                                       + 2 * cellHorizontalPadding,
                                                       headerMetrics.advanceWidth(qsTr("Summary"))
                                                       + 2 * headerHorizontalPadding)

    signal navigationFocusRequested()

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

    function appearanceValue(name, fallback) {
        const value = appearance ? appearance[name] : undefined
        return value === undefined || value === null ? fallback : value
    }

    function valueText(value) {
        return value === undefined || value === null ? "" : String(value)
    }

    function rowIsSelected(row) {
        const selectionRevision = selectedRows
        return controller && controller.isSelected(row)
    }

    function persistedColumnWidth(column) {
        const widths = controller ? controller.columnWidths : []
        const candidate = widths && column < widths.length ? Number(widths[column])
                                                           : defaultColumnWidths[column]
        return Math.max(minimumColumnWidth(column), candidate)
    }

    function minimumColumnWidth(column) {
        const label = headerLabels.length > column ? headerLabels[column] : ""
        return Math.max(Math.ceil(tableMetrics.height * 2),
                        Math.ceil(headerMetrics.advanceWidth(label) + 2 * headerHorizontalPadding))
    }

    function persistedColumnsWidth() {
        let width = 0
        for (let column = 0; column < resizableColumnCount; ++column)
            width += persistedColumnWidth(column)
        return width
    }

    function columnWidth(column) {
        if (column < resizableColumnCount)
            return persistedColumnWidth(column)
        return Math.max(summaryMinimumWidth, eventTable.width - persistedColumnsWidth())
    }

    function columnOffset(column) {
        let offset = 0
        for (let index = 0; index < column; ++index)
            offset += columnWidth(index)
        return offset
    }

    function boundedContentX(value) {
        const maximum = Math.max(0, eventTable.contentWidth - eventTable.width)
        return Math.max(0, Math.min(maximum, value))
    }

    function boundedContentY(value) {
        const maximum = Math.max(0, eventTable.contentHeight - eventTable.height)
        return Math.max(0, Math.min(maximum, value))
    }

    function beginCellEdit(cell) {
        if (!controller || editing || !cell || !cell.editable)
            return

        currentColumn = cell.column
        if (cell.column === 1) {
            controller.openTypeMenu(cell.mapToItem(null, cell.width / 2, cell.height))
            return
        }

        if (!controller.beginEditing(cell.row, cell.column))
            return

        Qt.callLater(function() {
            if (page.editing && cell.editing)
                cell.focusEditor()
        })
    }

    function finishCellEdit(commit, text, returnNavigationFocus) {
        if (!controller || !editing)
            return false

        const finished = controller.finishEditing(text, commit)
        if (finished && returnNavigationFocus)
            navigationFocusRequested()
        return finished
    }
    function requestTableLayout() {
        if (tableLayoutPending)
            return
        tableLayoutPending = true
        Qt.callLater(function() {
            tableLayoutPending = false
            eventTable.forceLayout()
        })
    }



    function resetPointerState() {
        if (controller)
            controller.setPointerDown(false)
        dragFromRow = -1
        dragDropGap = -1
        draggingRows = false
    }


    function legalDropGap(gap) {
        return controller && dragFromRow >= 0 && gap >= 0 && gap <= eventTable.rows
                && controller.isLegalDrop(dragFromRow, gap)
    }

    function updateDragGap(cell, mouse) {
        const position = cell.mapToItem(eventTable, mouse.x, mouse.y)
        const gap = Math.max(0, Math.min(eventTable.rows,
                                         Math.floor((eventTable.contentY + position.y + rowHeight / 2)
                                                    / rowHeight)))
        dragDropGap = legalDropGap(gap) ? gap : -1
    }

    function selectRow(row, modifiers) {
        if (!controller || row < 0 || row >= eventTable.rows)
            return
        controller.selectRow(row, modifiers)
    }

    function moveCurrentRow(delta, modifiers) {
        if (!controller || eventTable.rows <= 0)
            return
        const current = controller.currentRow >= 0 ? controller.currentRow : 0
        const target = Math.max(0, Math.min(eventTable.rows - 1, current + delta))
        if (target === current && controller.currentRow >= 0)
            return
        selectRow(target, modifiers)
        eventTable.positionViewAtRow(target, TableView.Contain)
    }

    function moveCurrentColumn(delta) {
        currentColumn = Math.max(0, Math.min(columnCount - 1, currentColumn + delta))
        eventTable.positionViewAtColumn(currentColumn, TableView.Contain)
    }

    function editCurrentCell() {
        if (!controller || controller.currentRow < 0)
            return
        const row = controller.currentRow
        eventTable.positionViewAtCell(Qt.point(page.currentColumn, row), TableView.Contain)
        Qt.callLater(function() {
            const cell = eventTable.itemAtCell(Qt.point(page.currentColumn, row))
            page.beginCellEdit(cell)
        })
    }

    function pageCurrent(delta, modifiers) {
        const pageRows = Math.max(1, Math.floor(eventTable.height / rowHeight))
        moveCurrentRow(delta * pageRows, modifiers)
    }

    component ToolbarButton: Item {
        id: control

        property string label: ""
        property string toolTip: ""
        property bool showArrow: false
        readonly property bool hovered: hoverHandler.hovered
        readonly property bool pressed: tapHandler.pressed
        signal triggered()

        implicitWidth: buttonText.implicitWidth + 2 * page.headerHorizontalPadding
                       + (showArrow ? buttonArrow.implicitWidth + page.headerHorizontalPadding / 2 : 0)
        implicitHeight: page.toolbarHeight
        height: page.toolbarHeight
        opacity: enabled ? 1 : 0.5
        activeFocusOnTab: true

        Rectangle {
            anchors.fill: parent
            color: control.pressed ? page.buttonPressedBackground
                  : control.hovered ? page.buttonHoverBackground : page.buttonBackground
            border.width: 1
            border.color: page.buttonOutline
        }

        Text {
            id: buttonText

            anchors.left: parent.left
            anchors.leftMargin: page.headerHorizontalPadding
            anchors.right: control.showArrow ? buttonArrow.left : parent.right
            anchors.rightMargin: control.showArrow ? page.headerHorizontalPadding / 2
                                                    : page.headerHorizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: page.buttonText
            font: page.controlFont
            text: control.label
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            maximumLineCount: 1
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            id: buttonArrow

            anchors.right: parent.right
            anchors.rightMargin: page.headerHorizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            visible: control.showArrow
            color: page.buttonText
            font: page.controlFont
            text: "\u25be"
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
        }

        HoverHandler {
            id: hoverHandler
        }

        TapHandler {
            id: tapHandler

            acceptedButtons: Qt.LeftButton
            enabled: control.enabled
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: control.triggered()
        }

        Keys.onReturnPressed: (event) => {
            control.triggered()
            event.accepted = true
        }
        Keys.onEnterPressed: (event) => {
            control.triggered()
            event.accepted = true
        }
        Keys.onSpacePressed: (event) => {
            control.triggered()
            event.accepted = true
        }

        Accessible.role: Accessible.Button
        Accessible.name: control.label
        Accessible.description: control.toolTip
        Accessible.focusable: true
        Accessible.onPressAction: control.triggered()
    }

    component EventCell: Item {
        id: cell

        required property int row
        required property int column
        required property var display
        required property var edit
        required property var tickString
        required property font cellFont
        required property int alignment
        required property var rowKind

        property real pressX: 0
        property real pressY: 0
        property bool pressWasCurrent: false

        readonly property bool rawRow: rowKind === 0
        readonly property bool endRow: rowKind === 2
        readonly property bool editing: page.editingRow === row && page.editingColumn === column
        readonly property bool current: page.controller && page.controller.currentRow === row
                                        && page.currentColumn === column
        readonly property bool selected: page.rowIsSelected(row)
        readonly property bool numericEditor: column >= 2 && column <= 4
        readonly property bool tickEditor: column === 0
        readonly property bool blobEditor: column === 5
        readonly property bool editable: {
            const editValue = edit
            return page.controller && page.controller.isCellEditable(row, column)
        }
        readonly property string displayedText: tickEditor ? page.valueText(tickString)
                                                           : page.valueText(display)
        readonly property string editorText: tickEditor ? page.valueText(tickString)
                                                        : page.valueText(edit)
        readonly property int horizontalAlignment: (alignment & Text.AlignRight)
                                                  ? Text.AlignRight : Text.AlignLeft

        implicitWidth: page.columnWidth(column)
        implicitHeight: page.rowHeight

        function focusEditor() {
            if (!editor.visible)
                return
            editor.forceActiveFocus(Qt.MouseFocusReason)
            editor.selectAll()
        }

        function finishEditor(returnNavigationFocus) {
            if (!editing)
                return
            const finished = page.finishCellEdit(true, editor.text, returnNavigationFocus)
            if (!finished && returnNavigationFocus)
                focusEditor()
        }

        function stepEditor(delta) {
            if (!page.controller || !page.controller.canStepEditing())
                return false
            editor.text = page.controller.steppedEditingText(editor.text, delta)
            return true
        }


        Rectangle {
            anchors.fill: parent
            color: cell.selected ? page.tableSelectedBackground
                  : page.controller && page.controller.playRow === cell.row ? page.playheadTint
                  : cell.row % 2 ? page.tableAlternateBackground : page.tableBackground
            border.width: cell.current ? 1 : 0
            border.color: page.focusOutline
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: page.tableOutline
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: page.tableOutline
        }

        Text {
            anchors.fill: parent
            anchors.leftMargin: page.cellHorizontalPadding
            anchors.rightMargin: page.cellHorizontalPadding
            visible: !cell.editing || cell.column === 1
            clip: true
            color: cell.selected ? page.tableSelectedText
                                 : cell.endRow ? page.tableSecondaryText : page.tableText
            font: cell.cellFont
            text: cell.displayedText
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: cell.horizontalAlignment
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            anchors.fill: parent
            visible: editor.visible
            color: page.inputBackground
            border.width: 1
            border.color: editor.activeFocus ? page.focusOutline : page.inputOutline
        }


        TextInput {
            id: editor

            objectName: !visible ? "" : cell.tickEditor ? "eventListTickEditor"
                                                    : cell.numericEditor ? "eventListNumericEditor"
                                                                         : "eventListBlobEditor"
            anchors.fill: parent
            visible: cell.editing && cell.column !== 1
            clip: true
            color: page.inputText
            font: cell.cellFont
            leftPadding: page.cellHorizontalPadding
            rightPadding: page.cellHorizontalPadding
            topPadding: 1
            bottomPadding: 1
            selectionColor: page.focusOutline
            selectedTextColor: page.inputText
            renderType: TextInput.NativeRendering
            horizontalAlignment: cell.horizontalAlignment
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            persistentSelection: true
            inputMethodHints: cell.tickEditor || cell.numericEditor ? Qt.ImhDigitsOnly
                                                                     : Qt.ImhNone

            onVisibleChanged: {
                if (visible)
                    text = cell.editorText
            }
            onEditingFinished: cell.finishEditor(false)
            onActiveFocusChanged: {
                if (!activeFocus && cell.editing)
                    page.finishCellEdit(false, "", false)
            }

            Keys.onReturnPressed: (event) => {
                cell.finishEditor(true)
                event.accepted = true
            }
            Keys.onEnterPressed: (event) => {
                cell.finishEditor(true)
                event.accepted = true
            }
            Keys.onEscapePressed: (event) => {
                page.finishCellEdit(false, "", true)
                event.accepted = true
            }
            Keys.onUpPressed: (event) => {
                if (cell.stepEditor(event.modifiers & Qt.ControlModifier ? 10 : 1))
                    event.accepted = true
            }
            Keys.onDownPressed: (event) => {
                if (cell.stepEditor(event.modifiers & Qt.ControlModifier ? -10 : -1))
                    event.accepted = true
            }
        }

        MouseArea {
            id: cellMouse

            anchors.fill: parent
            enabled: !cell.editing
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            preventStealing: cell.rawRow
            cursorShape: cell.editable ? Qt.IBeamCursor : Qt.ArrowCursor

            onPressed: (mouse) => {
                cell.pressX = mouse.x
                cell.pressY = mouse.y
                cell.pressWasCurrent = page.controller && page.controller.currentRow === cell.row
                                       && page.rowIsSelected(cell.row)
                page.currentColumn = cell.column
                if (mouse.button === Qt.RightButton) {
                    if (!page.rowIsSelected(cell.row))
                        page.selectRow(cell.row, Qt.NoModifier)
                } else {
                    page.selectRow(cell.row, mouse.modifiers)
                }
                if (page.controller)
                    page.controller.setPointerDown(true)
                page.dragFromRow = mouse.button === Qt.LeftButton && cell.rawRow ? cell.row : -1
                page.dragDropGap = -1
                page.draggingRows = false
            }

            onPositionChanged: (mouse) => {
                if (!pressed || !(mouse.buttons & Qt.LeftButton) || page.dragFromRow !== cell.row)
                    return
                if (!page.draggingRows) {
                    const dx = mouse.x - cell.pressX
                    const dy = mouse.y - cell.pressY
                    const distance = Math.sqrt(dx * dx + dy * dy)
                    if (distance < Qt.styleHints.startDragDistance)
                        return
                    page.draggingRows = true
                }
                page.updateDragGap(cell, mouse)
            }

            onReleased: (mouse) => {
                const moved = page.draggingRows && page.dragFromRow === cell.row
                const gap = page.dragDropGap
                if (page.controller)
                    page.controller.setPointerDown(false)

                if (mouse.button === Qt.RightButton) {
                    page.controller.focusRow(cell.row)
                    page.controller.openRowMenu(cell.mapToItem(null, mouse.x, mouse.y))
                } else if (moved) {
                    if (gap >= 0)
                        page.controller.commitDrop(cell.row, gap)
                    page.navigationFocusRequested()
                } else {
                    if (cell.pressWasCurrent && mouse.modifiers === Qt.NoModifier)
                        page.beginCellEdit(cell)
                    page.navigationFocusRequested()
                }
                page.resetPointerState()
            }

            onCanceled: page.resetPointerState()
            onDoubleClicked: (mouse) => {
                if (mouse.button === Qt.LeftButton)
                    page.beginCellEdit(cell)
            }
        }

    }

    Item {
        id: toolbar

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: page.toolbarHeight
        clip: true

        Rectangle {
            anchors.fill: parent
            color: page.headerBackground
            border.width: 1
            border.color: page.headerOutline
        }

        ToolbarButton {
            id: chunkButton

            objectName: "eventListChunk"
            x: page.headerHorizontalPadding
            y: 0
            width: Math.max(0, Math.min(implicitWidth, Math.max(0, toolbar.width * 0.35)))
            label: page.controller && page.controller.chunk >= 0
                   && page.controller.chunk < page.controller.chunkLabels.length
                   ? page.controller.chunkLabels[page.controller.chunk] : ""
            toolTip: qsTr("The MIDI file chunk shown (follows the selected track)")
            showArrow: true
            enabled: page.controller && page.controller.visible
            onTriggered: page.controller.openChunkMenu(mapToItem(null, width / 2, height))
        }

        ToolbarButton {
            id: filterButton

            objectName: "eventListFilter"
            x: chunkButton.x + chunkButton.width + page.headerHorizontalPadding
            y: 0
            width: Math.max(0, Math.min(implicitWidth, Math.max(0, toolbar.width * 0.3)))
            label: page.controller ? page.controller.filterSummary : ""
            toolTip: qsTr("Which event types are shown")
            showArrow: true
            enabled: page.controller && page.controller.visible
            onTriggered: page.controller.openFilterMenu(mapToItem(null, width / 2, height))
        }

        ToolbarButton {
            id: addButton

            objectName: "eventListAdd"
            x: filterButton.x + filterButton.width + page.headerHorizontalPadding
            y: 0
            label: qsTr("+ Add")
            toolTip: qsTr("Insert an event at the edit cursor (a copy of the current row, if any)")
            enabled: page.controller && page.controller.visible
            onTriggered: page.controller.addEvent()
        }

        ToolbarButton {
            id: removeButton

            objectName: "eventListRemove"
            x: addButton.x + addButton.width + page.headerHorizontalPadding
            y: 0
            label: qsTr("Delete")
            toolTip: qsTr("Delete the selected events (Del)")
            enabled: page.controller && page.controller.visible
            onTriggered: page.controller.deleteSelected()
        }

        Text {
            id: countLabel

            anchors.left: removeButton.right
            anchors.leftMargin: page.headerHorizontalPadding
            anchors.right: parent.right
            anchors.rightMargin: page.headerHorizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: page.headerText
            font: page.controlFont
            text: page.controller ? page.controller.countText : ""
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideLeft
            maximumLineCount: 1
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    Item {
        id: tableHeader
        objectName: "eventListHeader"

        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: page.headerHeight
        clip: true

        Rectangle {
            width: page.rowHeaderWidth
            height: parent.height
            color: page.headerBackground
            border.width: 1
            border.color: page.headerOutline
        }

        Item {
            id: headerViewport

            x: page.rowHeaderWidth
            width: eventTable.width
            height: parent.height
            clip: true

            Item {
                id: headerContent

                x: -eventTable.contentX
                width: Math.max(headerViewport.width, eventTable.contentWidth)
                height: parent.height

                Repeater {
                    model: page.columnCount

                    delegate: Item {
                        id: section

                        property int sectionColumn: index
                        x: page.columnOffset(sectionColumn)
                        width: page.columnWidth(sectionColumn)
                        height: headerContent.height

                        Rectangle {
                            anchors.fill: parent
                            color: page.headerBackground
                            border.width: 1
                            border.color: page.headerOutline
                        }

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: page.headerHorizontalPadding
                            anchors.rightMargin: page.headerHorizontalPadding
                            clip: true
                            color: page.headerText
                            font: page.headerFont
                            text: page.headerLabels.length > section.sectionColumn
                                  ? page.headerLabels[section.sectionColumn] : ""
                            textFormat: Text.PlainText
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            horizontalAlignment: page.controller
                                                 && (page.controller.headerAlignment(
                                                         section.sectionColumn)
                                                     & Text.AlignRight)
                                                 ? Text.AlignRight : Text.AlignLeft
                            verticalAlignment: Text.AlignVCenter
                        }

                        MouseArea {
                            id: resizeHandle

                            objectName: "eventListColumnResizeHandle" + section.sectionColumn
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 8
                            visible: section.sectionColumn < page.resizableColumnCount
                            enabled: visible
                            cursorShape: Qt.SplitHCursor
                            z: 2
                            property real pressPageX: 0
                            property real pressWidth: 0

                            onPressed: (mouse) => {
                                pressPageX = mapToItem(page, mouse.x, mouse.y).x
                                pressWidth = page.persistedColumnWidth(section.sectionColumn)
                                page.controller.setPointerDown(true)
                            }
                            onPositionChanged: (mouse) => {
                                if (!pressed)
                                    return
                                const pageX = mapToItem(page, mouse.x, mouse.y).x
                                page.controller.resizeColumn(section.sectionColumn,
                                                             Math.max(page.minimumColumnWidth(
                                                                          section.sectionColumn),
                                                                      pressWidth + pageX - pressPageX))
                                page.requestTableLayout()
                            }
                            onReleased: page.resetPointerState()
                            onCanceled: page.resetPointerState()
                        }
                    }
                }
            }
        }

        Rectangle {
            x: page.rowHeaderWidth + eventTable.width
            width: page.scrollbarBreadth
            height: parent.height
            color: page.headerBackground
            border.width: 1
            border.color: page.headerOutline
        }
    }

    Item {
        id: tableRegion

        anchors.top: tableHeader.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true

        Item {
            id: rowHeader

            width: page.rowHeaderWidth
            height: eventTable.height
            clip: true

            Rectangle {
                anchors.fill: parent
                color: page.headerBackground
                border.width: 1
                border.color: page.headerOutline
            }

            Repeater {
                model: eventTable.topRow >= 0 && eventTable.bottomRow >= eventTable.topRow
                       ? eventTable.bottomRow - eventTable.topRow + 1 : 0

                delegate: Item {
                    property int headerRow: eventTable.topRow + index
                    y: headerRow * page.rowHeight - eventTable.contentY
                    width: rowHeader.width
                    height: page.rowHeight

                    Rectangle {
                        anchors.fill: parent
                        color: page.rowIsSelected(parent.headerRow) ? page.tableSelectedBackground
                                                                     : parent.headerRow % 2
                                                                       ? page.tableAlternateBackground
                                                                       : page.tableBackground
                    }

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: page.headerHorizontalPadding
                        anchors.rightMargin: page.headerHorizontalPadding
                        color: page.rowIsSelected(parent.headerRow) ? page.tableSelectedText
                                                                     : page.headerText
                        font: page.headerFont
                        text: parent.headerRow + 1
                        textFormat: Text.PlainText
                        renderType: Text.NativeRendering
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        cursorShape: Qt.ArrowCursor
                        onClicked: (mouse) => {
                            page.selectRow(parent.headerRow, mouse.modifiers)
                            page.navigationFocusRequested()
                        }
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: page.headerOutline
            }
        }

        TableView {
            id: eventTable

            objectName: "eventListTable"
            anchors.left: rowHeader.right
            anchors.right: parent.right
            anchors.rightMargin: page.scrollbarBreadth
            height: Math.max(0, parent.height - page.scrollbarBreadth)
            clip: true
            model: page.controller ? page.controller.model : null
            reuseItems: !page.editing
            interactive: !page.draggingRows
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false
            pointerNavigationEnabled: false
            columnSpacing: 0
            rowSpacing: 0
            columnWidthProvider: function(column) {
                return page.columnWidth(column)
            }
            rowHeightProvider: function(row) {
                return page.rowHeight
            }
            delegate: EventCell {}

            onWidthChanged: page.requestTableLayout()
        }

        Rectangle {
            id: dropIndicator

            objectName: "eventListDropIndicator"
            x: eventTable.x
            y: eventTable.y + page.dragDropGap * page.rowHeight - eventTable.contentY - height / 2
            width: eventTable.width
            height: Math.max(2, Math.ceil(page.rowHeight / 8))
            visible: page.draggingRows && page.dragDropGap >= 0
            color: page.reorderIndicator
            z: 4
        }

        TimelineScrollbar {
            id: verticalScrollbar

            objectName: "eventListVerticalScrollBar"
            x: eventTable.x + eventTable.width
            y: eventTable.y
            width: page.scrollbarBreadth
            height: eventTable.height
            orientation: Qt.Vertical
            minimum: 0
            maximum: Math.max(0, eventTable.contentHeight - eventTable.height)
            value: eventTable.contentY
            pageStep: eventTable.height
            singleStep: page.rowHeight
            minimumThumbLength: page.rowHeight
            handleColor: page.scrollbarHandle
            handleHoverColor: page.scrollbarHandleHover
            externalVisible: page.controller && page.controller.visible
            accessibleName: qsTr("Event list")
            thumbObjectName: "eventListVerticalScrollThumb"
            z: 5

            onValueRequested: (value) => eventTable.contentY = value
            onWheelRequested: (pixelX, pixelY, angleX, angleY, inverted) => {
                const horizontal = Math.abs(pixelX) > Math.abs(pixelY)
                                   || (pixelY === 0 && Math.abs(angleX) > Math.abs(angleY))
                if (horizontal)
                    return
                const delta = pixelY !== 0 ? pixelY : angleY / 120 * page.rowHeight
                if (delta !== 0)
                    eventTable.contentY = page.boundedContentY(eventTable.contentY
                                                               + (inverted ? delta : -delta))
            }
        }

        TimelineScrollbar {
            id: horizontalScrollbar

            objectName: "eventListHorizontalScrollBar"
            x: eventTable.x
            y: eventTable.y + eventTable.height
            width: eventTable.width
            height: page.scrollbarBreadth
            orientation: Qt.Horizontal
            minimum: 0
            maximum: Math.max(0, eventTable.contentWidth - eventTable.width)
            value: eventTable.contentX
            pageStep: eventTable.width
            singleStep: Math.max(1, page.persistedColumnWidth(0))
            minimumThumbLength: page.scrollbarBreadth
            handleColor: page.scrollbarHandle
            handleHoverColor: page.scrollbarHandleHover
            externalVisible: page.controller && page.controller.visible
            accessibleName: qsTr("Event list columns")
            thumbObjectName: "eventListHorizontalScrollThumb"
            z: 5

            onValueRequested: (value) => eventTable.contentX = value
            onWheelRequested: (pixelX, pixelY, angleX, angleY, inverted) => {
                const vertical = Math.abs(pixelY) > Math.abs(pixelX)
                                 || (pixelX === 0 && Math.abs(angleY) > Math.abs(angleX))
                if (vertical)
                    return
                const delta = pixelX !== 0 ? pixelX : angleX / 120 * singleStep
                if (delta !== 0)
                    eventTable.contentX = page.boundedContentX(eventTable.contentX
                                                               + (inverted ? delta : -delta))
            }
        }

        Rectangle {
            x: eventTable.x + eventTable.width
            y: eventTable.y + eventTable.height
            width: page.scrollbarBreadth
            height: page.scrollbarBreadth
            color: page.headerBackground
            border.width: 1
            border.color: page.headerOutline
        }
    }

    readonly property var toolTipControl: chunkButton.hovered ? chunkButton
                                          : filterButton.hovered ? filterButton
                                          : addButton.hovered ? addButton
                                          : removeButton.hovered ? removeButton : null
    readonly property string toolTipText: toolTipControl ? toolTipControl.toolTip : ""
    readonly property rect toolTipAnchorRect: {
        if (!toolTipControl)
            return Qt.rect(0, 0, 0, 0)
        const topLeft = toolTipControl.mapToItem(page, 0, 0)
        return Qt.rect(topLeft.x, topLeft.y, toolTipControl.width, toolTipControl.height)
    }

    RulerToolTip {
        parent: page
        overlayRoot: page
        anchorRect: page.toolTipAnchorRect
        toolTipText: page.toolTipText
        visibleForControl: !!page.toolTipControl && (!page.controller || !page.controller.menuOpen)
        controlFont: page.controlFont
        backgroundColor: page.toolTipBackground
        textColor: page.toolTipTextColor
        outlineColor: page.toolTipOutline
        z: 20
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
    Shortcut {
        sequence: "Home"
        enabled: page.navigationEnabled
        onActivated: page.moveCurrentRow(-eventTable.rows, Qt.NoModifier)
    }
    Shortcut {
        sequence: "End"
        enabled: page.navigationEnabled
        onActivated: page.moveCurrentRow(eventTable.rows, Qt.NoModifier)
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
        sequences: [StandardKey.SelectAll]
        enabled: page.navigationEnabled
        onActivated: page.controller.selectAll()
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

    Connections {
        target: page.controller

        function onColumnWidthsChanged() {
            page.requestTableLayout()
        }

        function onScrollToRow(row) {
            if (row >= 0)
                eventTable.positionViewAtRow(row, TableView.Contain)
        }


        function onVisibleChanged() {
            if (!page.controller.visible && page.editing)
                page.finishCellEdit(false, "", false)
        }
    }
}
