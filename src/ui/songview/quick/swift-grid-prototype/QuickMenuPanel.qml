import QtQuick

Item {
    id: panel

    required property var host
    required property var menuModel

    required property var appearance
    property bool rootLevel: false
    property int rowHeight: 0
    property int separatorHeight: 1
    property int checkX: -1
    property int checkWidth: 0
    property int textX: 0
    property int textRight: 0
    property int shortcutRight: -1
    property int arrowRight: -1
    property int arrowWidth: 0
    property int menuWidth: 0
    property int menuHeight: 0
    property point menuOrigin: Qt.point(0, 0)
    property int highlightedRow: -1
    property int pressedRow: -1

    objectName: rootLevel ? "quickMenuPanelRoot" : "quickMenuPanelSubmenu"

    onHighlightedRowChanged: {
        if (highlightedRow >= 0)
            list.positionViewAtIndex(highlightedRow, ListView.Contain);
    }

    readonly property color backgroundColor: appearance.background
    readonly property color outlineColor: appearance.outline
    readonly property color textColor: appearance.text
    readonly property color hoverBackgroundColor: appearance.hoverBackground
    readonly property color hoverTextColor: appearance.hoverText
    readonly property color pressedBackgroundColor: appearance.pressedBackground
    readonly property color pressedTextColor: appearance.pressedText
    readonly property color disabledTextColor: appearance.disabledText
    readonly property color separatorColor: appearance.separator
    readonly property font menuFont: appearance.font

    function rowItem(row) {
        return list.itemAtIndex(row);
    }

    function rowSceneRect(row) {
        const rowItem = list.itemAtIndex(row);
        if (!rowItem)
            return Qt.rect(0, 0, 0, 0);
        const scene = rowItem.mapToItem(null, 0, 0);
        return Qt.rect(scene.x, scene.y, rowItem.width, rowItem.height);
    }

    Rectangle {
        id: frame
        objectName: "quickMenuFrame"

        x: panel.menuOrigin.x
        y: panel.menuOrigin.y
        width: panel.menuWidth
        height: panel.menuHeight
        color: panel.backgroundColor
        border.color: panel.outlineColor
        border.width: 1

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
        }

        ListView {
            id: list

            anchors.fill: parent
            anchors.margins: frame.border.width
            model: panel.menuModel
            interactive: contentHeight > height
            keyNavigationEnabled: false
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Item {
                id: row

                enabled: row.active
                width: ListView.view.width
                height: model.separator ? panel.separatorHeight : panel.rowHeight

                readonly property bool active: !model.separator && model.enabled
                readonly property color rowTextColor: {
                    if (!model.enabled && !model.separator)
                        return panel.disabledTextColor;
                    if (panel.pressedRow === index)
                        return panel.pressedTextColor;
                    if (panel.highlightedRow === index)
                        return panel.hoverTextColor;
                    return panel.textColor;
                }

                Rectangle {
                    anchors.fill: parent
                    visible: row.active
                    color: panel.pressedRow === index ? panel.pressedBackgroundColor : panel.highlightedRow === index ? panel.hoverBackgroundColor : "transparent"
                }

                Rectangle {
                    visible: model.separator
                    width: parent.width
                    height: model.separator ? panel.separatorHeight : 0
                    y: (parent.height - height) / 2
                    color: panel.separatorColor
                }

                Item {
                    id: tick

                    visible: model.checkable && model.checked && !model.separator
                    x: panel.checkX
                    y: (row.height - width) / 2
                    width: panel.checkWidth
                    height: width

                    readonly property real stroke: Math.max(2, width / 5)

                    Rectangle {
                        width: tick.width * 0.65
                        height: tick.stroke
                        color: row.rowTextColor
                        rotation: -45
                        x: tick.width * 0.55 - width / 2
                        y: tick.height * 0.45 - height / 2
                    }

                    Rectangle {
                        width: tick.width * 0.30
                        height: tick.stroke
                        color: row.rowTextColor
                        rotation: 45
                        x: tick.width * 0.215 - width / 2
                        y: tick.height * 0.575 - height / 2
                    }
                }

                Text {
                    x: panel.textX
                    width: Math.max(0, panel.textRight - panel.textX)
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    color: row.rowTextColor
                    font: panel.menuFont
                    text: model.text
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                }

                Text {
                    visible: panel.shortcutRight >= 0
                    x: panel.textRight
                    width: Math.max(0, panel.shortcutRight - panel.textRight)
                    height: parent.height
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    color: Qt.alpha(row.rowTextColor, 0.6)
                    font: panel.menuFont
                    text: model.shortcutText
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                }

                Item {
                    id: arrow

                    visible: model.hasSubmenu && !model.separator
                    x: panel.arrowRight - width
                    y: (row.height - height) / 2
                    width: panel.arrowWidth
                    height: width * 2
                    clip: true

                    Rectangle {
                        width: arrow.height * 0.7
                        height: width
                        color: row.rowTextColor
                        rotation: 45
                        x: -width / 2
                        y: arrow.height / 2 - height / 2
                    }
                }

                HoverHandler {
                    enabled: row.active
                    cursorShape: Qt.ArrowCursor
                    onHoveredChanged: {
                        if (hovered)
                            panel.host.hoverRow(panel, index);
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onPressed: mouse => {
                        mouse.accepted = true;
                        if (!row.active)
                            return;
                        panel.pressedRow = index;
                    }
                    onReleased: mouse => {
                        const releasedHere = panel.pressedRow === index && mouse.x >= 0 && mouse.x < width && mouse.y >= 0 && mouse.y < height;
                        panel.pressedRow = -1;
                        if (releasedHere)
                            panel.host.activateRow(panel, index);
                    }
                    onCanceled: panel.pressedRow = -1
                }

                Accessible.role: model.separator ? Accessible.Separator : Accessible.MenuItem
                Accessible.name: model.text
            }
        }

        Accessible.role: Accessible.PopupMenu
        Accessible.name: rootLevel ? qsTr("Menu") : qsTr("Submenu")
    }
}
