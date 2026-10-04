pragma ComponentBehavior: Bound

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

        implicitWidth: buttonText.implicitWidth + 2 * control.page.headerHorizontalPadding
                       + (showArrow ? buttonArrow.implicitWidth + control.page.headerHorizontalPadding / 2 : 0)
        implicitHeight: control.page.toolbarHeight
        height: control.page.toolbarHeight
        opacity: enabled ? 1 : 0.5
        activeFocusOnTab: true

        Rectangle {
            anchors.fill: parent
            color: control.pressed ? control.page.buttonPressedBackground
                  : control.hovered ? control.page.buttonHoverBackground : control.page.buttonBackground
            border.width: 1
            border.color: control.page.buttonOutline
        }

        Text {
            id: buttonText
            objectName: control.objectName + "Text"

            anchors.left: parent.left
            anchors.leftMargin: control.page.headerHorizontalPadding
            anchors.right: control.showArrow ? buttonArrow.left : parent.right
            anchors.rightMargin: control.showArrow ? control.page.headerHorizontalPadding / 2
                                                    : control.page.headerHorizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: control.pressed ? control.page.buttonPressedText : control.page.buttonText
            font: control.page.controlFont
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
            anchors.rightMargin: control.page.headerHorizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            visible: control.showArrow
            color: control.pressed ? control.page.buttonPressedText : control.page.buttonText
            font: control.page.controlFont
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
        height: toolbar.page.toolbarHeight
        clip: true

        Rectangle {
            anchors.fill: parent
            color: toolbar.page.headerBackground
            border.width: 1
            border.color: toolbar.page.headerOutline
        }

        ToolbarButton {
            id: chunkButton
            page: toolbar.page

            objectName: "eventListChunk"
            x: chunkButton.page.headerHorizontalPadding
            y: 0
            width: Math.max(0, Math.min(implicitWidth, Math.max(0, toolbar.width * 0.35)))
            label: chunkButton.page.controller && chunkButton.page.controller.chunk >= 0
                   && chunkButton.page.controller.chunk < chunkButton.page.controller.chunkLabels.length
                   ? chunkButton.page.controller.chunkLabels[chunkButton.page.controller.chunk] : ""
            toolTip: qsTr("The MIDI file chunk shown (follows the selected track)")
            showArrow: true
            enabled: chunkButton.page.controller && chunkButton.page.controller.visible
            onTriggered: {
                const position = mapToItem(chunkButton.page, width / 2, height)
                chunkButton.page.controller.openChunkMenu(position.x, position.y)
            }
        }

        ToolbarButton {
            id: filterButton
            page: toolbar.page

            objectName: "eventListFilter"
            x: chunkButton.x + chunkButton.width + filterButton.page.headerHorizontalPadding
            y: 0
            width: Math.max(0, Math.min(implicitWidth, Math.max(0, toolbar.width * 0.3)))
            label: filterButton.page.controller ? filterButton.page.controller.filterSummary : ""
            toolTip: qsTr("Which event types are shown")
            showArrow: true
            enabled: filterButton.page.controller && filterButton.page.controller.visible
            onTriggered: {
                const position = mapToItem(filterButton.page, width / 2, height)
                filterButton.page.controller.openFilterMenu(position.x, position.y)
            }
        }

        ToolbarButton {
            id: addButton
            page: toolbar.page

            objectName: "eventListAdd"
            x: filterButton.x + filterButton.width + addButton.page.headerHorizontalPadding
            y: 0
            label: qsTr("+ Add")
            toolTip: qsTr("Insert an event at the edit cursor (a copy of the current row, if any)")
            enabled: addButton.page.controller && addButton.page.controller.visible
            onTriggered: addButton.page.controller.addEvent()
        }

        ToolbarButton {
            id: removeButton
            page: toolbar.page

            objectName: "eventListRemove"
            x: addButton.x + addButton.width + removeButton.page.headerHorizontalPadding
            y: 0
            label: qsTr("Delete")
            toolTip: qsTr("Delete the selected events (Del)")
            enabled: removeButton.page.controller && removeButton.page.controller.visible
            onTriggered: removeButton.page.controller.deleteSelected()
        }

        Text {
            id: countLabel

            anchors.left: removeButton.right
            anchors.leftMargin: toolbar.page.headerHorizontalPadding
            anchors.right: parent.right
            anchors.rightMargin: toolbar.page.headerHorizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: toolbar.page.headerText
            font: toolbar.page.controlFont
            text: toolbar.page.controller ? toolbar.page.controller.countText : ""
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideLeft
            maximumLineCount: 1
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
        }
    readonly property ToolbarButton toolTipControl: chunkButton.hovered ? chunkButton
                                          : filterButton.hovered ? filterButton
                                          : addButton.hovered ? addButton
                                          : removeButton.hovered ? removeButton : null
    readonly property string toolTipText: toolTipControl ? toolTipControl.toolTip : ""
    readonly property rect toolTipAnchorRect: {
        if (!toolTipControl)
            return Qt.rect(0, 0, 0, 0)
        const topLeft = toolTipControl.mapToItem(toolbar.page, 0, 0)
        return Qt.rect(topLeft.x, topLeft.y, toolTipControl.width, toolTipControl.height)
    }

    RulerToolTip {
        parent: toolbar.page
        overlayRoot: toolbar.page
        anchorRect: toolbar.toolTipAnchorRect
        toolTipText: toolbar.toolTipText
        visibleForControl: !!toolbar.toolTipControl && (!toolbar.page.controller || !toolbar.page.controller.menuOpen)
        controlFont: toolbar.page.controlFont
        backgroundColor: toolbar.page.toolTipBackground
        textColor: toolbar.page.toolTipTextColor
        outlineColor: toolbar.page.toolTipOutline
        z: 20
    }
}
