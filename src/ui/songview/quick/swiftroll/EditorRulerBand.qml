import QtQuick
import Porydaw.Ui

Item {
    id: rulerModule
    required property Item root
    required property Item rollStack
    required property Item rollBandContent
    required property Item gridMenuLoader
    property alias rulerInput: rulerInput
            Item {
                id: rulerBand
                parent: rollStack
                objectName: "timelineQuickRuler"
                width: parent.width
                height: root.gridModel.rulerHeight
                clip: true

                TimelineQuickItem {
                    objectName: "timelineQuickRulerGutterChrome"
                    width: root.gridModel.keyboardWidth
                    height: parent.height
                    rects: root.gridModel.scene.rulerGutterChrome
                    batched: true
                }

                Item {
                    x: root.gridModel.keyboardWidth
                    width: Math.max(parent.width - x, 0)
                    height: parent.height
                    clip: true

                    TimelineQuickItem {
                        anchors.fill: parent
                        objectName: "timelineQuickRulerChrome"
                        rects: root.gridModel.scene.rulerChrome
                        batched: true
                    }
                    Item {
                        id: rulerContent
                        x: -Math.round(root.gridModel.cameraScrollX * root.gridModel.devicePixelRatio)
                           / root.gridModel.devicePixelRatio
                        width: parent.width
                        height: parent.height
                    }
                    TimelineQuickItem {
                        parent: rulerContent
                        anchors.fill: parent
                        objectName: "timelineQuickRulerMarks"
                        rects: root.gridModel.scene.rulerMarks
                    }
                    Repeater {
                        parent: rulerContent
                        model: root.gridModel.scene.rulerTextModel
                        delegate: Text {
                            required property var labelSpec
                            required property string labelText
                            required property var labelFont
                            x: labelSpec.x
                            y: labelSpec.y
                            width: labelSpec.width
                            height: labelSpec.height
                            color: labelSpec.color
                            text: labelText
                            font: Qt.font(labelFont)
                            textFormat: Text.PlainText
                            renderType: Text.NativeRendering
                        }
                    }
                    MouseArea {
                        id: rulerInput
                        objectName: "timelineRulerInput"
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        activeFocusOnTab: true
                        onDoubleClicked: (mouse) => {
                            rulerMoves.flush()
                            if (mouse.button !== Qt.LeftButton)
                                return
                            const tick = root.timeSigHost.timeSigChipTick(mouse.x, mouse.y)
                            if (tick >= 0)
                                root.timeSigHost.openTimeSigPrompt(tick)
                        }
                        onPressed: (mouse) => {
                            rulerMoves.flush()
                            if (mouse.button === Qt.LeftButton) {
                                root.rulerMenu.beginSweep(mouse.x, mouse.y, mouse.modifiers)
                            } else if (mouse.button === Qt.RightButton) {
                                root.timeMenuFocus = false
                                root.timeSigHost.captureTimeSigMenuPress(mouse.x, mouse.y)
                            }
                        }
                        onPositionChanged: (mouse) => {
                            if (mouse.buttons & Qt.LeftButton)
                                rulerMoves.enqueue(mouse.x, mouse.y,
                                                   mouse.buttons, mouse.modifiers)
                        }
                        onReleased: (mouse) => {
                            rulerMoves.flush()
                            if (mouse.button === Qt.LeftButton) {
                                root.rulerMenu.endSweep(mouse.x, mouse.y)
                            } else if (mouse.button === Qt.RightButton) {
                                root.timeSigMenuPosition = mapToItem(root, mouse.x, mouse.y)
                                root.timeSigHost.openTimeSigMenu()
                            }
                        }
                        onCanceled: {
                            rulerMoves.flush()
                            root.rulerMenu.cancelSweep()
                        }
                        MoveCoalescer {
                            id: rulerMoves
                            dispatch: (x, y, buttons, modifiers) => {
                                root.rulerMenu.updateSweep(x, y)
                            }
                        }
                    }
                }
            }
        Item {
            id: rulerControls
            parent: rollBandContent
            objectName: "timelineRulerControls"
            width: root.headersModel.trackHeaderWidth
                + root.gridModel.keyboardWidth
            height: root.gridModel.rulerHeight
            clip: true
            readonly property real controlsInset: 8
            readonly property real controlsGap: 4
            readonly property real controlsStroke:
                1 / (root.gridModel.devicePixelRatio > 0
                     ? root.gridModel.devicePixelRatio : 1)
            readonly property font controlsFont: root.bodyFont
            readonly property real gridLabelWidth:
                Math.min(gridLabel.implicitWidth,
                         Math.max(0, width - controlsInset))
            readonly property real controlWidth:
                Math.max(0, (Math.max(0, width - controlsInset
                                      - gridLabelWidth - controlsGap)
                             - controlsGap) / 2)

            component GridRowControl: Item {
                id: gridControl
                required property string controlText
                required property int menuKind
                required property string controlToolTip
                readonly property bool controlHovered: gridArea.containsMouse
                readonly property bool controlPressed: gridArea.pressed
                activeFocusOnTab: true
                Keys.onReturnPressed: openMenu()
                Keys.onEnterPressed: openMenu()

                function openMenu() {
                    root.gridMenuPosition = mapToItem(root, width / 2, height)
                    root.gridModel.openGridMenu(menuKind)
                    Qt.callLater(function() {
                        if (gridMenuLoader.item)
                            gridMenuLoader.item.forceActiveFocus(Qt.PopupFocusReason)
                    })
                }

                Rectangle {
                    id: gridControlBackground
                    objectName: "gridControlBackground"
                    anchors.fill: parent
                    color: gridControl.controlPressed
                        ? root.gridModel.palette.buttonPressedBackground
                        : root.gridModel.palette.buttonHoverBackground
                    border.width: rulerControls.controlsStroke
                    border.color: root.gridModel.palette.outline
                }
                Text {
                    id: gridControlLabel
                    objectName: "gridControlLabel"
                    anchors.left: parent.left
                    anchors.leftMargin: rulerControls.controlsGap
                    anchors.right: gridControlArrow.left
                    anchors.rightMargin: rulerControls.controlsGap / 2
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    color: root.gridModel.palette.buttonText
                    font: rulerControls.controlsFont
                    text: gridControl.controlText
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    id: gridControlArrow
                    objectName: "gridControlArrow"
                    anchors.right: parent.right
                    anchors.rightMargin: rulerControls.controlsGap
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.gridModel.palette.buttonText
                    font: rulerControls.controlsFont
                    text: "▾"
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                }
                MouseArea {
                    id: gridArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: gridControl.openMenu()
                }
            }

            Text {
                id: gridLabel
                objectName: "timelineRulerGridLabel"
                x: rulerControls.controlsInset
                width: rulerControls.gridLabelWidth
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                color: root.gridModel.palette.primaryText
                font: rulerControls.controlsFont
                text: qsTr("Grid")
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            GridRowControl {
                id: divisionControl
                objectName: "timelineRulerDivisionControl"
                x: rulerControls.controlsInset + rulerControls.gridLabelWidth
                    + rulerControls.controlsGap
                y: Math.max(0, (parent.height - height) / 2)
                width: rulerControls.controlWidth
                height: Math.min(parent.height,
                    gridLabel.implicitHeight + rulerControls.controlsInset)
                controlText: root.gridModel.gridDivisionControlText
                menuKind: 1
                controlToolTip: qsTr("Editing snap grid. Auto follows the zoom one step finer than the drawn grid; a fixed division snaps to that note value; Clock snaps to the mid2agb clock grid.")
            }
            GridRowControl {
                id: feelControl
                objectName: "timelineRulerFeelControl"
                x: rulerControls.controlsInset + rulerControls.gridLabelWidth
                    + rulerControls.controlsGap + rulerControls.controlWidth
                    + rulerControls.controlsGap
                y: Math.max(0, (parent.height - height) / 2)
                width: rulerControls.controlWidth
                height: Math.min(parent.height,
                    gridLabel.implicitHeight + rulerControls.controlsInset)
                controlText: root.gridModel.gridFeelControlText
                menuKind: 2
                controlToolTip: qsTr("Straight or triplet beat subdivisions.")
            }
        }
    RulerToolTip {
        objectName: "timelineRulerToolTip"
        parent: root
        z: 4
        overlayRoot: root
        anchorRect: {
            const control = divisionControl.controlHovered ? divisionControl : feelControl
            const point = control.mapToItem(root, 0, 0)
            const row = rulerControls.mapToItem(root, 0, 0)
            return Qt.rect(point.x, row.y, control.width, rulerControls.height)
        }
        toolTipText: divisionControl.controlHovered
            ? divisionControl.controlToolTip : feelControl.controlToolTip
        visibleForControl: divisionControl.controlHovered || feelControl.controlHovered
        controlFont: rulerControls.controlsFont
        backgroundColor: root.gridModel.palette.chromeBackground
        textColor: root.gridModel.palette.windowText
        outlineColor: root.gridModel.palette.outline
    }
}
