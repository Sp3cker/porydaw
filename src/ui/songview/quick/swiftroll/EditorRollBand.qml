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
    width: root.width
    height: Math.max(root.height - editorDrawer.height - otherEventsBand.height
                     - root.scrollbarBreadth, 0)
    z: 1

        TrackHeaderBand {
            id: trackHeaders
            x: 0
            y: root.gridModel.rulerHeight
            width: root.headersModel.trackHeaderWidth
            height: Math.max(parent.height - y, 0)
            onWidthChanged: root.configureViewport()
            onHeightChanged: root.configureViewport()
            bandRect: Qt.rect(0, 0, width, height)
            bandVisible: rollBandContent.visible
            model: root.headersModel
            controlFont: Qt.font(root.headersModel.controlFont)
            hintService: root.hintService
            hintScopeAllowed: !root.hintScopeCovered
        }

        // The roll owns a keyboard-local coordinate space beside the headers.
        Item {
            id: rollStack
            x: root.headersModel.trackHeaderWidth
            width: Math.max(parent.width - x - root.scrollbarBreadth, 0)
            height: parent.height
            clip: true


            Item {
                id: rollGutterSide
                objectName: "timelineQuickRollGutter"
                visible: !root.showEvents
                y: root.gridModel.rulerHeight
                width: root.gridModel.keyboardWidth
                height: Math.max(parent.height - y, 0)
                clip: true
                MouseArea {
                    id: gutterInput
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    onPressed: function(mouse) {
                        root.gridModel.beginKeyboardPointer(mouse.y)
                        mouse.accepted = true
                    }
                    onPositionChanged: function(mouse) {
                        if (pressed)
                            root.gridModel.updateKeyboardPointer(mouse.y)
                        else
                            root.gridModel.updateHover(mouse.x, mouse.y)
                    }
                    onReleased: function(mouse) {
                        root.gridModel.endKeyboardPointer()
                        mouse.accepted = true
                    }
                    onCanceled: root.gridModel.endKeyboardPointer()
                    onExited: {
                        if (!pressed)
                            root.gridModel.clearKeyboardHover()
                    }
                    z: 10
                }
                HoverHint {
                    source: gutterInput
                    hintService: root.hintService
                    scopeAllowed: !root.hintScopeCovered
                    gestureOwning: gutterInput.pressed
                    profile: HintProfiles.RollGutter
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        root.deliverWheel(event, true)
                        event.accepted = true
                    }
                }
            }

            Item {
                id: rollPlot
                objectName: "timelineQuickRollPlot"
                visible: !root.showEvents
                x: root.gridModel.keyboardWidth
                y: root.gridModel.rulerHeight
                width: Math.max(parent.width - x, 0)
                height: Math.max(parent.height - y, 0)
                clip: true

                onWidthChanged: root.configureViewport()
                onHeightChanged: root.configureViewport()
                Item {
                    id: pianoGridSurface
                    objectName: "pianoGridSurface"
                    anchors.fill: parent

                    PianoRollCanvas {
                        bandSide: rollContentBand
                        plotSide: pianoGridSurface
                        gridModel: root.gridModel
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
                            root.gridModel.dragDistance = Qt.styleHints.startDragDistance

                        ItemCursor {
                            readonly property var kinds: [
                                { shape: Qt.ArrowCursor, source: "" },
                                { shape: Qt.OpenHandCursor, source: "" },
                                { shape: Qt.ArrowCursor, source: "qrc:/cursors/left-drag.png" },
                                { shape: Qt.ArrowCursor, source: "qrc:/cursors/right-drag.png" },
                                { shape: Qt.ClosedHandCursor, source: "" }
                            ]
                            readonly property var current: kinds[root.gridModel.cursorKind]
                            objectName: "swiftRollCursor"
                            target: rollInput
                            shape: current.shape
                            source: current.source
                            extent: root.gridModel.resizeCursorExtent
                            devicePixelRatio: root.gridModel.devicePixelRatio
                        }

                        onPressed: function(mouse) {
                            rollInput.forceActiveFocus(Qt.MouseFocusReason)
                            rollMoves.flush()
                            if (mouse.button === Qt.MiddleButton)
                                root.gridModel.beginPan(mouse.x, mouse.y)
                            else if (mouse.button === Qt.RightButton) {
                                rightSweepActive = (mouse.modifiers & Qt.ShiftModifier) !== 0
                                if (rightSweepActive) {
                                    root.rulerMenu.beginSweep(mouse.x, mouse.y, mouse.modifiers)
                                } else {
                                    root.timeSelectionMenuPosition = mapToItem(root, mouse.x, mouse.y)
                                    root.rulerMenu.openTimeSelection(mouse.x)
                                    timeMenuPressHandled = root.rulerMenu.menuKind === 2
                                    root.timeMenuFocus = timeMenuPressHandled
                                    if (!timeMenuPressHandled)
                                        root.gridModel.beginRightPointer(mouse.x, mouse.y, mouse.modifiers)
                                }
                            }
                            else
                                root.gridModel.beginPointer(mouse.x, mouse.y, mouse.modifiers)
                            mouse.accepted = true
                        }
                        onDoubleClicked: function(mouse) {
                            rollMoves.flush()
                            if (mouse.button === Qt.LeftButton)
                                root.gridModel.doublePointer(mouse.x, mouse.y)
                            mouse.accepted = true
                        }
                        onPositionChanged: function(mouse) {
                            rollMoves.enqueue(mouse.x, mouse.y, mouse.buttons, mouse.modifiers)
                        }
                        onReleased: function(mouse) {
                            rollMoves.flush()
                            if (mouse.button === Qt.MiddleButton)
                                root.gridModel.endPan()
                            else if (mouse.button === Qt.RightButton) {
                                if (rightSweepActive)
                                    root.rulerMenu.endSweep(mouse.x, mouse.y)
                                else if (!timeMenuPressHandled)
                                    root.gridModel.endRightPointer(mouse.x, mouse.y, mouse.modifiers)
                                rightSweepActive = false
                                timeMenuPressHandled = false
                            }
                            else
                                root.gridModel.endPointer(mouse.x, mouse.y)
                            mouse.accepted = true
                        }
                        onCanceled: {
                            rollMoves.flush()
                            timeMenuPressHandled = false
                            if (rightSweepActive)
                                root.rulerMenu.cancelSweep()
                            rightSweepActive = false
                            root.gridModel.inputCancelled(root.cancelReasonPointerUngrabbed)
                        }
                        onExited: {
                            rollMoves.flush()
                            if (pressedButtons === Qt.NoButton)
                                root.gridModel.clearKeyboardHover()
                        }
                        MoveCoalescer {
                            id: rollMoves
                            dispatch: (x, y, buttons, modifiers) => {
                                if (buttons & Qt.MiddleButton)
                                    root.gridModel.updatePan(x, y)
                                else if (buttons & Qt.RightButton) {
                                    if (rollInput.rightSweepActive)
                                        root.rulerMenu.updateSweep(x, y)
                                    else if (!rollInput.timeMenuPressHandled)
                                        root.gridModel.updateRightPointer(x, y, modifiers)
                                }
                                else if (buttons & Qt.LeftButton)
                                    root.gridModel.updatePointer(x, y, modifiers)
                                else
                                    root.gridModel.updateHover(x, y)
                            }
                        }
                    }
                    HoverHint {
                        id: rollHint
                        source: rollInput
                        hintService: root.hintService
                        scopeAllowed: !root.hintScopeCovered
                        gestureOwning: rollInput.pressed
                        profile: HintProfiles.RollPlot
                    }
                }

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        root.deliverWheel(event, false)
                        event.accepted = true
                    }
                }
            }
            Item {
                id: rollContentBand
                objectName: "rollContentBand"
                visible: !root.showEvents
                y: root.gridModel.rulerHeight
                width: parent.width
                height: Math.max(parent.height - y, 0)
                z: 3
            }
        }

        Item {
            id: eventListHost
            x: root.headersModel.trackHeaderWidth
            y: root.gridModel.rulerHeight
            width: Math.max(parent.width - x, 0)
            height: Math.max(parent.height - y, 0)
            z: 4
            visible: false

            Loader {
                id: eventPage
                anchors.fill: parent
                active: false
                onLoaded: {
                    if (root.eventListPresenter) {
                        root.eventListPresenter.setVisible(root.showEvents)
                    }
                    if (root.showEvents && root.visible)
                        Qt.callLater(function() {
                            if (root.showEvents && eventPage.item)
                                eventPage.item.forceActiveFocus(Qt.OtherFocusReason)
                        })
                }
                sourceComponent: Component {
                    EventListPage {
                        objectName: "eventListPage"
                        presenter: root.eventListPresenter
                    }
                }
            }
        }

    EditorRulerBand {
        id: rulerModule
        root: rollBandContent.root
        rollStack: rollStack
        rollBandContent: rollBandContent
        gridMenuLoader: root.menus.gridMenuLoader
    }
}
