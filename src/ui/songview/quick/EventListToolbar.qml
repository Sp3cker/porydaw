import QtQuick
import PorydawApp

Item {
    id: toolbar
    required property Item page
    required property EventListPresenter controller

    component ToolbarButton: Item {
        id: control
        required property Item page

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
            objectName: control.objectName + "Text"

            anchors.left: parent.left
            anchors.leftMargin: page.headerHorizontalPadding
            anchors.right: control.showArrow ? buttonArrow.left : parent.right
            anchors.rightMargin: control.showArrow ? page.headerHorizontalPadding / 2
                                                    : page.headerHorizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: control.pressed ? page.buttonPressedText : page.buttonText
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
            objectName: control.objectName + "Arrow"

            anchors.right: parent.right
            anchors.rightMargin: page.headerHorizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            visible: control.showArrow
            color: control.pressed ? page.buttonPressedText : page.buttonText
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

        Accessible.role: Accessible.Button
        Accessible.name: control.label
        Accessible.description: control.toolTip
        Accessible.focusable: true
        Accessible.onPressAction: control.triggered()
    }
        HoverHint {
            source: toolbar
        }

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
            page: toolbar.page

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
            onTriggered: {
                const position = mapToItem(page, width / 2, height)
                page.controller.openChunkMenu(position.x, position.y)
            }
        }

        ToolbarButton {
            id: filterButton
            page: toolbar.page

            objectName: "eventListFilter"
            x: chunkButton.x + chunkButton.width + page.headerHorizontalPadding
            y: 0
            width: Math.max(0, Math.min(implicitWidth, Math.max(0, toolbar.width * 0.3)))
            label: page.controller ? page.controller.filterSummary : ""
            toolTip: qsTr("Which event types are shown")
            showArrow: true
            enabled: page.controller && page.controller.visible
            onTriggered: {
                const position = mapToItem(page, width / 2, height)
                page.controller.openFilterMenu(position.x, position.y)
            }
        }

        ToolbarButton {
            id: addButton
            page: toolbar.page

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
            page: toolbar.page

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
        anchorRect: toolbar.toolTipAnchorRect
        toolTipText: toolbar.toolTipText
        visibleForControl: !!toolbar.toolTipControl && (!page.controller || !page.controller.menuOpen)
        controlFont: page.controlFont
        backgroundColor: page.toolTipBackground
        textColor: page.toolTipTextColor
        outlineColor: page.toolTipOutline
        z: 20
    }
}
