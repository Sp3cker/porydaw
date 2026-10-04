pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui

Item {
    id: rollBandContent
    required property Item root
    required property Item editorDrawer
    required property Item otherEventsBand
    property alias trackHeaders: trackHeaders
    property alias rollStack: rollStack
    property alias rollPlot: rollPlot
    property alias rollInput: rollInput
    property alias rollHint: rollHint
    property alias eventListHost: eventListHost
    property alias eventPage: eventPage
    property alias rulerInput: rulerModule.rulerInput
    objectName: "swiftRollBand"
    width: rollBandContent.root.width
    height: Math.max(rollBandContent.root.height - editorDrawer.height - otherEventsBand.height
                     - rollBandContent.root.scrollbarBreadth, 0)
    z: 1

        TrackHeaderBand {
            id: trackHeaders
            x: 0
            y: rollBandContent.root.gridModel.rulerHeight
            width: rollBandContent.root.headersModel.trackHeaderWidth
            height: Math.max(parent.height - y, 0)
            onWidthChanged: rollBandContent.root.configureViewport()
            onHeightChanged: rollBandContent.root.configureViewport()
            bandRect: Qt.rect(0, 0, width, height)
            bandVisible: rollBandContent.visible
            model: rollBandContent.root.headersModel
            controlFont: Qt.font(rollBandContent.root.headersModel.controlFont)
            hintService: rollBandContent.root.hintService
            hintScopeAllowed: !rollBandContent.root.hintScopeCovered
        }

        // The roll owns a keyboard-local coordinate space beside the headers.
        Item {
            id: rollStack
            x: rollBandContent.root.headersModel.trackHeaderWidth
            width: Math.max(parent.width - x - rollBandContent.root.scrollbarBreadth, 0)
            height: parent.height
            clip: true


            Item {
                id: rollGutterSide
                objectName: "timelineQuickRollGutter"
                visible: !rollBandContent.root.showEvents
                y: rollBandContent.root.gridModel.rulerHeight
                width: rollBandContent.root.gridModel.keyboardWidth
                height: Math.max(parent.height - y, 0)
                clip: true
                MouseArea {
                    id: gutterInput
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    onPressed: function(mouse) {
                        rollBandContent.root.gridModel.beginKeyboardPointer(mouse.y)
                        mouse.accepted = true
                    }
                    onPositionChanged: function(mouse) {
                        if (pressed)
                            rollBandContent.root.gridModel.updateKeyboardPointer(mouse.y)
                        else
                            rollBandContent.root.gridModel.updateHover(mouse.x, mouse.y, mouse.modifiers)
                    }
                    onReleased: function(mouse) {
                        rollBandContent.root.gridModel.endKeyboardPointer()
                        mouse.accepted = true
                    }
                    onCanceled: rollBandContent.root.gridModel.endKeyboardPointer()
                    onExited: {
                        if (!pressed)
                            rollBandContent.root.gridModel.clearKeyboardHover()
                    }
                    z: 10
                }
                HoverHint {
                    source: gutterInput
                    hintService: rollBandContent.root.hintService
                    scopeAllowed: !rollBandContent.root.hintScopeCovered
                    gestureOwning: gutterInput.pressed
                    profile: HintProfiles.RollGutter
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        rollBandContent.root.deliverWheel(event, true)
                        event.accepted = true
                    }
                }
            }

            Item {
                id: rollPlot
                objectName: "timelineQuickRollPlot"
                visible: !rollBandContent.root.showEvents
                x: rollBandContent.root.gridModel.keyboardWidth
                y: rollBandContent.root.gridModel.rulerHeight
                width: Math.max(parent.width - x, 0)
                height: Math.max(parent.height - y, 0)
                clip: true

                onWidthChanged: rollBandContent.root.configureViewport()
                onHeightChanged: rollBandContent.root.configureViewport()
                Item {
                    id: pianoGridSurface
                    objectName: "pianoGridSurface"
                    anchors.fill: parent

                    PianoRollCanvas {
                        bandSide: rollContentBand
                        plotSide: pianoGridSurface
                        gridModel: rollBandContent.root.gridModel
                    }

                    MouseArea {
                        id: rollInput
                        objectName: "swiftRollInput"
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        preventStealing: true
                        hoverEnabled: true
                        // The drawer returns focus here when no section stays visible.
                        activeFocusOnTab: true
                        property bool timeMenuPressHandled: false
                        property bool rightSweepActive: false

                        Component.onCompleted:
                            rollBandContent.root.gridModel.dragDistance = Qt.styleHints.startDragDistance

                        ItemCursor {
                            readonly property list<int> shapes: [
                                Qt.ArrowCursor, Qt.OpenHandCursor, Qt.ArrowCursor,
                                Qt.ArrowCursor, Qt.ClosedHandCursor, Qt.SizeVerCursor
                            ]
                            readonly property list<string> sources: [
                                "", "", "qrc:/cursors/left-drag.png",
                                "qrc:/cursors/right-drag.png", "", ""
                            ]
                            objectName: "swiftRollCursor"
                            target: rollInput
                            shape: shapes[rollBandContent.root.gridModel.cursorKind]
                            source: sources[rollBandContent.root.gridModel.cursorKind]
                            extent: rollBandContent.root.gridModel.resizeCursorExtent
                            devicePixelRatio: rollBandContent.root.gridModel.devicePixelRatio
                        }

                        onPressed: function(mouse) {
                            rollInput.forceActiveFocus(Qt.MouseFocusReason)
                            rollMoves.flush()
                            if (mouse.button === Qt.MiddleButton)
                                rollBandContent.root.gridModel.beginPan(mouse.x, mouse.y)
                            else if (mouse.button === Qt.RightButton) {
                                rightSweepActive = (mouse.modifiers & Qt.ShiftModifier) !== 0
                                if (rightSweepActive) {
                                    rollBandContent.root.rulerMenu.beginSweep(mouse.x, mouse.y, mouse.modifiers)
                                } else {
                                    rollBandContent.root.timeSelectionMenuPosition = mapToItem(rollBandContent.root, mouse.x, mouse.y)
                                    rollBandContent.root.rulerMenu.openTimeSelection(mouse.x)
                                    timeMenuPressHandled = rollBandContent.root.rulerMenu.menuKind === 2
                                    rollBandContent.root.timeMenuFocus = timeMenuPressHandled
                                    if (!timeMenuPressHandled)
                                        rollBandContent.root.gridModel.beginRightPointer(mouse.x, mouse.y, mouse.modifiers)
                                }
                            }
                            else
                                rollBandContent.root.gridModel.beginPointer(mouse.x, mouse.y, mouse.modifiers)
                            mouse.accepted = true
                        }
                        onDoubleClicked: function(mouse) {
                            rollMoves.flush()
                            if (mouse.button === Qt.LeftButton)
                                rollBandContent.root.gridModel.doublePointer(mouse.x, mouse.y)
                            mouse.accepted = true
                        }
                        onPositionChanged: function(mouse) {
                            rollMoves.enqueue(mouse.x, mouse.y, mouse.buttons, mouse.modifiers)
                        }
                        onReleased: function(mouse) {
                            rollMoves.flush()
                            if (mouse.button === Qt.MiddleButton)
                                rollBandContent.root.gridModel.endPan()
                            else if (mouse.button === Qt.RightButton) {
                                if (rightSweepActive)
                                    rollBandContent.root.rulerMenu.endSweep(mouse.x, mouse.y)
                                else if (!timeMenuPressHandled)
                                    rollBandContent.root.gridModel.endRightPointer(mouse.x, mouse.y, mouse.modifiers)
                                rightSweepActive = false
                                timeMenuPressHandled = false
                            }
                            else {
                                rollBandContent.root.gridModel.endPointer(mouse.x, mouse.y)
                                rollBandContent.root.gridModel.updateHover(mouse.x, mouse.y, mouse.modifiers)
                            }
                            mouse.accepted = true
                        }
                        onCanceled: {
                            rollMoves.flush()
                            timeMenuPressHandled = false
                            if (rightSweepActive)
                                rollBandContent.root.rulerMenu.cancelSweep()
                            rightSweepActive = false
                            rollBandContent.root.gridModel.inputCancelled(rollBandContent.root.cancelReasonPointerUngrabbed)
                        }
                        onExited: {
                            rollMoves.flush()
                            if (pressedButtons === Qt.NoButton)
                                rollBandContent.root.gridModel.clearKeyboardHover()
                        }
                        MoveCoalescer {
                            id: rollMoves
                            dispatch: rollMoves.dispatchMove
                            function dispatchMove(x: real, y: real, buttons: int, modifiers: int): void {
                                if (buttons & Qt.MiddleButton)
                                    rollBandContent.root.gridModel.updatePan(x, y)
                                else if (buttons & Qt.RightButton) {
                                    if (rollInput.rightSweepActive)
                                        rollBandContent.root.rulerMenu.updateSweep(x, y)
                                    else if (!rollInput.timeMenuPressHandled)
                                        rollBandContent.root.gridModel.updateRightPointer(x, y, modifiers)
                                }
                                else if (buttons & Qt.LeftButton)
                                    rollBandContent.root.gridModel.updatePointer(x, y, modifiers)
                                else
                                    rollBandContent.root.gridModel.updateHover(x, y, modifiers)
                            }
                        }
                    }
                    HoverHint {
                        id: rollHint
                        source: rollInput
                        hintService: rollBandContent.root.hintService
                        scopeAllowed: !rollBandContent.root.hintScopeCovered
                        gestureOwning: rollInput.pressed
                        profile: HintProfiles.RollPlot
                    }
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        rollBandContent.root.deliverWheel(event, false)
                        event.accepted = true
                    }
                }
            }
            Item {
                id: rollContentBand
                objectName: "rollContentBand"
                visible: !rollBandContent.root.showEvents
                y: rollBandContent.root.gridModel.rulerHeight
                width: parent.width
                height: Math.max(parent.height - y, 0)
                z: 3
            }
        }

        Item {
            id: eventListHost
            x: rollBandContent.root.headersModel.trackHeaderWidth
            y: rollBandContent.root.gridModel.rulerHeight
            width: Math.max(parent.width - x, 0)
            height: Math.max(parent.height - y, 0)
            z: 4
            visible: false

            Loader {
                id: eventPage
                anchors.fill: parent
                active: false
                onLoaded: {
                    if (rollBandContent.root.eventListPresenter) {
                        rollBandContent.root.eventListPresenter.setVisible(rollBandContent.root.showEvents)
                    }
                    if (rollBandContent.root.showEvents && rollBandContent.root.visible)
                        Qt.callLater(function() {
                            if (rollBandContent.root.showEvents && eventPage.item)
                                (eventPage.item as Item).forceActiveFocus(Qt.OtherFocusReason)
                        })
                }
                sourceComponent: Component {
                    EventListPage {
                        objectName: "eventListPage"
                        presenter: rollBandContent.root.eventListPresenter
                    }
                }
            }
        }

    EditorRulerBand {
        id: rulerModule
        root: rollBandContent.root
        rollStack: rollStack
        rollBandContent: rollBandContent
        gridMenuLoader: rollBandContent.root.menus.gridMenuLoader
    }
}
