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



    function boundedContentX(value) {
        const maximum = Math.max(0, eventTable.contentWidth - eventTable.width)
        return Math.max(0, Math.min(maximum, value))
    }

    function boundedContentY(value) {
        const maximum = Math.max(0, eventTable.contentHeight - eventTable.height)
        return Math.max(0, Math.min(maximum, value))
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
    // QListModel is one-dimensional; the existing TableView remains the
    // seven-column renderer while Swift owns the cell values and row policy.
    function publishTableRows() {
        tableRows.clear()
        for (let row = 0; row < controller.rowCount; ++row)
            tableRows.appendRow({c0: row, c1: row, c2: row, c3: row,
                                 c4: row, c5: row, c6: row})
    }

    Connections {
        target: page.controller
        function onTableRevisionChanged() { table.publishTableRows() }
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
                            objectName: "eventListColumnHeaderLabel" + section.sectionColumn
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
                                table.requestTableLayout()
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
            readonly property int firstVisibleRow: Math.max(
                0, Math.floor(eventTable.contentY / page.rowHeight))
            readonly property int visibleRowCount: Math.max(0, Math.min(
                eventTable.rows - firstVisibleRow,
                Math.ceil((eventTable.contentY + eventTable.height) / page.rowHeight)
                    - firstVisibleRow))

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
                model: rowHeader.visibleRowCount

                delegate: Item {
                    property int headerRow: rowHeader.firstVisibleRow + index
                    y: headerRow * page.rowHeight - eventTable.contentY
                    width: rowHeader.width
                    height: page.rowHeight

                    HoverHint {
                        source: parent
                        profile: HintProfiles.EventRows
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: page.rowIsSelected(parent.headerRow) ? page.tableSelectedBackground
                                                                     : parent.headerRow % 2
                                                                       ? page.tableAlternateBackground
                                                                       : page.tableBackground
                    }

                    Text {
                        objectName: "eventListRowHeaderLabel"
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
            delegate: EventListCell {
                page: table.page
                tableOwner: table
                controller: table.controller
                display: page.controller.cellDisplay(row, column)
                edit: page.controller.cellEdit(row, column)
                tickString: page.controller.tickString(row)
                cellFont: column === 0 || (column >= 2 && column <= 4)
                          ? page.tableFont : page.bodyFont
                alignment: page.controller.headerAlignment(column)
                rowKind: page.controller.rowKind(row)
            }

            onWidthChanged: table.requestTableLayout()
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
                    eventTable.contentX = table.boundedContentX(eventTable.contentX
                                                               + (inverted ? delta : -delta))
            }
        }

        Rectangle {
            id: tableCorner

            objectName: "eventListCorner"
            x: eventTable.x + eventTable.width
            y: eventTable.y + eventTable.height
            width: page.scrollbarBreadth
            height: page.scrollbarBreadth
            color: page.headerBackground
            border.width: 1
            border.color: page.headerOutline

            HoverHint {
                source: tableCorner
            }
        }
    }
}
