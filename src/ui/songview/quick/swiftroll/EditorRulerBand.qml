pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import Porydaw.Icons

Item {
    id: rulerModule
    final required property EditorSurface root
    final required property Item rollStack
    final required property Item rollBandContent
    final required property Loader gridMenuLoader
    final property alias rulerInput: rulerInput
    property string divisionText
    property string feelText
    property color toolTipBackground
    property color toolTipText
    property color toolTipOutline
    Binding {
        when: rulerModule.root.gridModel !== null && rulerModule.root.headersModel !== null
        restoreMode: Binding.RestoreNone
        rulerBand.height: rulerModule.root.gridModel?.rulerHeight
        rulerGutter.width: rulerModule.root.gridModel?.keyboardWidth
        rulerGutter.color: rulerModule.root.gridModel?.palette?.chromeBackground
        rulerSeparator.y: rulerModule.root.gridModel?.rulerHeight - 0.5
        rulerSeparator.width: rulerModule.root.gridModel?.keyboardWidth
        rulerSeparator.height: 1 / rulerModule.root.gridModel?.devicePixelRatio
        rulerSeparator.color: rulerModule.root.gridModel?.palette?.separator
        rulerPlot.x: rulerModule.root.gridModel?.keyboardWidth
        rulerMarks.revision: rulerModule.root.gridModel?.scene?.displayRevision
        rulerControls.width: rulerModule.root.headersModel?.trackHeaderWidth + rulerModule.root.gridModel?.keyboardWidth
        rulerControls.height: rulerModule.root.gridModel?.rulerHeight
        rulerControls.controlsStroke: 1 / (rulerModule.root.gridModel?.devicePixelRatio > 0
                                          ? rulerModule.root.gridModel?.devicePixelRatio : 1)
        gridLabel.color: rulerModule.root.gridModel?.palette?.primaryText
        rulerModule.divisionText: rulerModule.root.gridModel?.gridDivisionControlText
        rulerModule.feelText: rulerModule.root.gridModel?.gridFeelControlText
        rulerModule.toolTipBackground: rulerModule.root.gridModel?.palette?.chromeBackground
        rulerModule.toolTipText: rulerModule.root.gridModel?.palette?.windowText
        rulerModule.toolTipOutline: rulerModule.root.gridModel?.palette?.outline
    }
            Item {
                id: rulerBand
                parent: rulerModule.rollStack
                objectName: "timelineQuickRuler"
                width: parent.width
                clip: true

                Rectangle {
                    id: rulerGutter
                    objectName: "timelineQuickRulerGutterChrome"
                    height: parent.height
                }
                Rectangle {
                    id: rulerSeparator
                }

                Item {
                    id: rulerPlot
                    width: Math.max(parent.width - x, 0)
                    height: parent.height
                    clip: true

                    DisplayList {
                        id: rulerMarks
                        anchors.fill: parent
                        objectName: "timelineQuickRulerMarks"
                        clip: true
                        source: rulerModule.root.gridModel?.scene ?? null
                        list: 2
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
                            const tick = rulerModule.root.timeSigHost.timeSigChipTick(mouse.x, mouse.y)
                            if (tick >= 0)
                                rulerModule.root.timeSigHost.openTimeSigPrompt(tick)
                        }
                        onPressed: (mouse) => {
                            rulerMoves.flush()
                            if (mouse.button === Qt.LeftButton) {
                                rulerModule.root.rulerMenu.beginSweep(mouse.x, mouse.y, mouse.modifiers)
                            } else if (mouse.button === Qt.RightButton) {
                                rulerModule.root.timeMenuFocus = false
                                rulerModule.root.timeSigHost.captureTimeSigMenuPress(mouse.x, mouse.y)
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
                                rulerModule.root.rulerMenu.endSweep(mouse.x, mouse.y)
                            } else if (mouse.button === Qt.RightButton) {
                                rulerModule.root.timeSigMenuPosition = mapToItem(rulerModule.root, mouse.x, mouse.y)
                                rulerModule.root.timeSigHost.openTimeSigMenu()
                            }
                        }
                        onCanceled: {
                            rulerMoves.flush()
                            rulerModule.root.rulerMenu.cancelSweep()
                        }
                        MoveCoalescer {
                            id: rulerMoves
                            dispatch: rulerMoves.dispatchMove
                            function dispatchMove(x: real, y: real, buttons: int, modifiers: int): void {
                                rulerModule.root.rulerMenu.updateSweep(x, y)
                            }
                        }
                    }
                }
            }
        Item {
            id: rulerControls
            parent: rulerModule.rollBandContent
            objectName: "timelineRulerControls"
            clip: true
            readonly property real controlsInset: 8
            readonly property real controlsGap: 4
            property real controlsStroke
            readonly property font controlsFont: rulerModule.root.bodyFont
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

                function openMenu(): void {
                    rulerModule.root.gridMenuPosition = mapToItem(rulerModule.root, width / 2, height)
                    rulerModule.root.gridModel.openGridMenu(menuKind)
                    Qt.callLater(function() {
                        if (rulerModule.gridMenuLoader.item)
                            (rulerModule.gridMenuLoader.item as Item).forceActiveFocus(Qt.PopupFocusReason)
                    })
                }

                Rectangle {
                    id: gridControlBackground
                    objectName: "gridControlBackground"
                    anchors.fill: parent
                    border.width: rulerControls.controlsStroke
                    Binding {
                        when: rulerModule.root.gridModel !== null
                        restoreMode: Binding.RestoreNone
                        gridControlBackground.color: gridControl.controlPressed
                            ? rulerModule.root.gridModel?.palette?.buttonPressedBackground
                            : rulerModule.root.gridModel?.palette?.buttonHoverBackground
                        gridControlBackground.border.color: rulerModule.root.gridModel?.palette?.outline
                        gridControlLabel.color: rulerModule.root.gridModel?.palette?.buttonText
                        gridControlArrow.color: rulerModule.root.gridModel?.palette?.buttonText
                    }
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
                    font: rulerControls.controlsFont
                    text: gridControl.controlText
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    verticalAlignment: Text.AlignVCenter
                }
                AppIcon {
                    id: gridControlArrow
                    objectName: "gridControlArrow"
                    anchors.right: parent.right
                    anchors.rightMargin: rulerControls.controlsGap
                    anchors.verticalCenter: parent.verticalCenter
                    width: rulerControls.controlsFont.pixelSize
                    height: width
                    icon: Icons.comboArrow
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
                controlText: rulerModule.divisionText
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
                controlText: rulerModule.feelText
                menuKind: 2
                controlToolTip: qsTr("Straight or triplet beat subdivisions.")
            }
        }
    RulerToolTip {
        id: rulerToolTip
        objectName: "timelineRulerToolTip"
        parent: rulerModule.root
        z: 4
        overlayRoot: rulerModule.root
        anchorRect: {
            const control = divisionControl.controlHovered ? divisionControl : feelControl
            const point = control.mapToItem(rulerModule.root, 0, 0)
            const row = rulerControls.mapToItem(rulerModule.root, 0, 0)
            return Qt.rect(point.x, row.y, control.width, rulerControls.height)
        }
        toolTipText: divisionControl.controlHovered
            ? divisionControl.controlToolTip : feelControl.controlToolTip
        visibleForControl: divisionControl.controlHovered || feelControl.controlHovered
        controlFont: rulerControls.controlsFont
        backgroundColor: rulerModule.toolTipBackground
        textColor: rulerModule.toolTipText
        outlineColor: rulerModule.toolTipOutline
    }
}
