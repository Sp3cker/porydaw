pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.qmlmodels
import PorydawApp

Item {
    id: table

    required property Item page
    required property EventListPresenter controller
    required property FontMetrics tableFontMetrics
    required property FontMetrics headerFontMetrics
    property bool tableLayoutPending: false
    property alias eventTable: eventTable



    function boundedContentX(value: real): real {
        const maximum = Math.max(0, eventTable.contentWidth - eventTable.width)
        return Math.max(0, Math.min(maximum, value))
    }

    function boundedContentY(value: real): real {
        const maximum = Math.max(0, eventTable.contentHeight - eventTable.height)
        return Math.max(0, Math.min(maximum, value))
    }
    function requestTableLayout(): void {
        if (table.tableLayoutPending)
            return
        table.tableLayoutPending = true
        Qt.callLater(table.applyTableLayout)
    }

    function applyTableLayout(): void {
        table.tableLayoutPending = false
        eventTable.forceLayout()
    }

    function widthForColumn(column: int): real {
        return table.page.columnWidth(column)
    }

    function heightForRow(row: int): real {
        return table.page.rowHeight
    }
    // QListModel is one-dimensional; the existing TableView remains the
    // seven-column renderer while Swift owns the cell values and row policy.
    function publishTableRows(): void {
        tableRows.clear()
        for (let row = 0; row < table.controller.rowCount; ++row)
            tableRows.appendRow({c0: row, c1: row, c2: row, c3: row,
                                 c4: row, c5: row, c6: row})
    }

    Connections {
        target: table.page.controller
        function onTableRevisionChanged(): void { table.publishTableRows() }
    }

    Item {
        id: tableHeader
        objectName: "eventListHeader"

        // Column labels and resizers have no modifier-dependent action;
        // one empty claim covers them all.
        HoverHint {
            source: tableHeader
        }

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: table.page.headerHeight
        clip: true

        Rectangle {
            width: table.page.rowHeaderWidth
            height: parent.height
            color: table.page.headerBackground
            border.width: 1
            border.color: table.page.headerOutline
        }

        Item {
            id: headerViewport

            x: table.page.rowHeaderWidth
            width: eventTable.width
            height: parent.height
            clip: true

            Item {
                id: headerContent

                x: -eventTable.contentX
                width: Math.max(headerViewport.width, eventTable.contentWidth)
                height: parent.height

                Repeater {
                    model: table.page.columnCount

                    delegate: Item {
                        id: section
                        required property int index

                        property int sectionColumn: section.index
                        x: table.page.columnOffset(sectionColumn)
                        width: table.page.columnWidth(sectionColumn)
                        height: headerContent.height

                        Rectangle {
                            anchors.fill: parent
                            color: table.page.headerBackground
                            border.width: 1
                            border.color: table.page.headerOutline
                        }

                        Text {
                            objectName: "eventListColumnHeaderLabel" + section.sectionColumn
                            anchors.fill: parent
                            anchors.leftMargin: table.page.headerHorizontalPadding
                            anchors.rightMargin: table.page.headerHorizontalPadding
                            clip: true
                            color: table.page.headerText
                            font: table.page.headerFont
                            text: table.page.headerLabels.length > section.sectionColumn
                                  ? table.page.headerLabels[section.sectionColumn] : ""
                            textFormat: Text.PlainText
                            renderType: Text.NativeRendering
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            horizontalAlignment: table.page.controller
                                                 && (table.page.controller.headerAlignment(
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
                            visible: section.sectionColumn < table.page.resizableColumnCount
                            enabled: visible
                            cursorShape: Qt.SplitHCursor
                            z: 2
                            property real pressPageX: 0
                            property real pressWidth: 0

                            onPressed: (mouse) => {
                                pressPageX = mapToItem(table.page, mouse.x, mouse.y).x
                                pressWidth = table.page.persistedColumnWidth(section.sectionColumn)
                                table.page.controller.setPointerDown(true)
                            }
                            onPositionChanged: (mouse) => {
                                if (!pressed)
                                    return
                                const pageX = mapToItem(table.page, mouse.x, mouse.y).x
                                table.page.controller.resizeColumn(section.sectionColumn,
                                                             Math.max(table.page.minimumColumnWidth(
                                                                          section.sectionColumn),
                                                                      pressWidth + pageX - pressPageX))
                                table.requestTableLayout()
                            }
                            onReleased: table.page.resetPointerState()
                            onCanceled: table.page.resetPointerState()
                        }
                    }
                }
            }
        }

        Rectangle {
            x: table.page.rowHeaderWidth + eventTable.width
            width: table.page.scrollbarBreadth
            height: parent.height
            color: table.page.headerBackground
            border.width: 1
            border.color: table.page.headerOutline
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
            readonly property int firstVisibleRow: Math.max(
                0, Math.floor(eventTable.contentY / table.page.rowHeight))
            readonly property int visibleRowCount: Math.max(0, Math.min(
                eventTable.rows - firstVisibleRow,
                Math.ceil((eventTable.contentY + eventTable.height) / table.page.rowHeight)
                    - firstVisibleRow))

            width: table.page.rowHeaderWidth
            height: eventTable.height
            clip: true

            Rectangle {
                anchors.fill: parent
                color: table.page.headerBackground
                border.width: 1
                border.color: table.page.headerOutline
            }

            Repeater {
                model: rowHeader.visibleRowCount

                delegate: Item {
                    id: rowHeaderDelegate
                    required property int index
                    property int headerRow: rowHeader.firstVisibleRow + rowHeaderDelegate.index
                    y: rowHeaderDelegate.headerRow * table.page.rowHeight - eventTable.contentY
                    width: rowHeader.width
                    height: table.page.rowHeight

                    HoverHint {
                        source: parent
                        profile: HintProfiles.EventRows
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: table.page.rowIsSelected(rowHeaderDelegate.headerRow) ? table.page.tableSelectedBackground
                                                                     : rowHeaderDelegate.headerRow % 2
                                                                       ? table.page.tableAlternateBackground
                                                                       : table.page.tableBackground
                    }

                    Text {
                        objectName: "eventListRowHeaderLabel"
                        anchors.fill: parent
                        anchors.leftMargin: table.page.headerHorizontalPadding
                        anchors.rightMargin: table.page.headerHorizontalPadding
                        color: table.page.rowIsSelected(rowHeaderDelegate.headerRow) ? table.page.tableSelectedText
                                                                     : table.page.headerText
                        font: table.page.headerFont
                        text: rowHeaderDelegate.headerRow + 1
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
                            table.page.selectRow(rowHeaderDelegate.headerRow, mouse.modifiers)
                            table.page.navigationFocusRequested()
                        }
                    }
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: table.page.headerOutline
            }
        }

        TableView {
            id: eventTable

            objectName: "eventListTable"
            anchors.left: rowHeader.right
            anchors.right: parent.right
            anchors.rightMargin: table.page.scrollbarBreadth
            height: Math.max(0, parent.height - table.page.scrollbarBreadth)
            clip: true
            model: TableModel {
                id: tableRows
                TableModelColumn { display: "c0" }
                TableModelColumn { display: "c1" }
                TableModelColumn { display: "c2" }
                TableModelColumn { display: "c3" }
                TableModelColumn { display: "c4" }
                TableModelColumn { display: "c5" }
                TableModelColumn { display: "c6" }
            }
            reuseItems: !table.page.editing
            interactive: !table.page.draggingRows
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false
            pointerNavigationEnabled: false
            columnSpacing: 0
            rowSpacing: 0
            columnWidthProvider: table.widthForColumn
            rowHeightProvider: table.heightForRow
            delegate: EventListCell {
                id: eventCellDelegate
                page: table.page
                tableOwner: table
                controller: table.controller
                display: eventCellDelegate.page.controller.cellDisplay(row, column)
                edit: eventCellDelegate.page.controller.cellEdit(row, column)
                tickString: eventCellDelegate.page.controller.tickString(row)
                cellFont: column === 0 || (column >= 2 && column <= 4)
                          ? eventCellDelegate.page.tableFont : eventCellDelegate.page.bodyFont
                alignment: eventCellDelegate.page.controller.headerAlignment(column)
                rowKind: eventCellDelegate.page.controller.rowKind(row)
            }

            onWidthChanged: table.requestTableLayout()
        }

        Rectangle {
            id: dropIndicator

            objectName: "eventListDropIndicator"
            x: eventTable.x
            y: eventTable.y + table.page.dragDropGap * table.page.rowHeight - eventTable.contentY - height / 2
            width: eventTable.width
            height: Math.max(2, Math.ceil(table.page.rowHeight / 8))
            visible: table.page.draggingRows && table.page.dragDropGap >= 0
            color: table.page.reorderIndicator
            z: 4
        }

        TimelineScrollbar {
            id: verticalScrollbar

            objectName: "eventListVerticalScrollBar"
            x: eventTable.x + eventTable.width
            y: eventTable.y
            width: table.page.scrollbarBreadth
            height: eventTable.height
            orientation: Qt.Vertical
            minimum: 0
            maximum: Math.max(0, eventTable.contentHeight - eventTable.height)
            value: eventTable.contentY
            pageStep: eventTable.height
            singleStep: table.page.rowHeight
            minimumThumbLength: table.page.rowHeight
            handleColor: table.page.scrollbarHandle
            handleHoverColor: table.page.scrollbarHandleHover
            externalVisible: table.page.controller && table.page.controller.visible
            accessibleName: qsTr("Event list")
            thumbObjectName: "eventListVerticalScrollThumb"
            z: 5

            onValueRequested: (value) => eventTable.contentY = value
            onWheelRequested: (pixelX, pixelY, angleX, angleY, inverted) => {
                const horizontal = Math.abs(pixelX) > Math.abs(pixelY)
                                   || (pixelY === 0 && Math.abs(angleX) > Math.abs(angleY))
                if (horizontal)
                    return
                const delta = pixelY !== 0 ? pixelY : angleY / 120 * table.page.rowHeight
                if (delta !== 0)
                    eventTable.contentY = table.boundedContentY(eventTable.contentY
                                                               + (inverted ? delta : -delta))
            }
        }

        TimelineScrollbar {
            id: horizontalScrollbar

            objectName: "eventListHorizontalScrollBar"
            x: eventTable.x
            y: eventTable.y + eventTable.height
            width: eventTable.width
            height: table.page.scrollbarBreadth
            orientation: Qt.Horizontal
            minimum: 0
            maximum: Math.max(0, eventTable.contentWidth - eventTable.width)
            value: eventTable.contentX
            pageStep: eventTable.width
            singleStep: Math.max(1, table.page.persistedColumnWidth(0))
            minimumThumbLength: table.page.scrollbarBreadth
            handleColor: table.page.scrollbarHandle
            handleHoverColor: table.page.scrollbarHandleHover
            externalVisible: table.page.controller && table.page.controller.visible
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
                    eventTable.contentX = table.boundedContentX(eventTable.contentX
                                                               + (inverted ? delta : -delta))
            }
        }

        Rectangle {
            id: tableCorner

            objectName: "eventListCorner"
            x: eventTable.x + eventTable.width
            y: eventTable.y + eventTable.height
            width: table.page.scrollbarBreadth
            height: table.page.scrollbarBreadth
            color: table.page.headerBackground
            border.width: 1
            border.color: table.page.headerOutline

            HoverHint {
                source: tableCorner
            }
        }
    }
}
