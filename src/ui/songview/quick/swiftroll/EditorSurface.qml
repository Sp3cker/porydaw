import QtQuick

Item {
    id: root
    objectName: "swiftRollOverlay"
    clip: true
    required property QtObject applicationSession
    readonly property int cancelReasonPointerUngrabbed: 1
    readonly property int cancelReasonHidden: 2
    readonly property var gridModel: applicationSession.gridPresenter()
    readonly property int noteCount: gridModel.renderedNoteCount
    readonly property string appliedRevisionText: gridModel.appliedRevisionText

    onWidthChanged: configureViewport()
    onHeightChanged: configureViewport()
    onVisibleChanged: {
        if (!visible)
            gridModel.inputCancelled(cancelReasonHidden)
    }

    Connections {
        target: root.gridModel
        function onContextMenuRequested(x, y) {
            root.applicationSession.requestGridContextMenu(x, y)
        }
    }

    Rectangle {
        objectName: "swiftRollBackground"
        anchors.fill: parent
        color: root.gridModel.palette.rollBackground
        z: -1
    }

    Item {
        id: rollBandContent
        width: root.width
        height: root.height
        z: 1

        Item {
            id: rollGutterSide
            objectName: "timelineQuickRollGutter"
            width: root.gridModel.keyboardWidth
            height: parent.height
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

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    root.deliverWheel(event, true)
                }
            }
        }

        Item {
            id: rollPlot
            objectName: "timelineQuickRollPlot"
            x: root.gridModel.keyboardWidth
            width: Math.max(root.width - root.gridModel.keyboardWidth, 0)
            height: root.height
            clip: true

            onWidthChanged: root.configureViewport()
            onHeightChanged: root.configureViewport()

            Item {
                id: pianoGridSurface
                objectName: "pianoGridSurface"
                anchors.fill: parent

                PianoRollCanvas {
                    bandSide: rollBandContent
                    gutterSide: rollGutterSide
                    plotSide: pianoGridSurface
                    timelineScene: root.gridModel.scene
                }

                MouseArea {
                    id: rollInput
                    objectName: "swiftRollInput"
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    preventStealing: true
                    hoverEnabled: true

                    cursorShape: {
                        switch (root.gridModel.cursorKind) {
                        case 1: return Qt.OpenHandCursor
                        case 2:
                        case 3: return Qt.SizeHorCursor
                        default: return Qt.ArrowCursor
                        }
                    }

                    onPressed: function(mouse) {
                        if (mouse.button === Qt.RightButton)
                            root.gridModel.beginRightPointer(mouse.x, mouse.y)
                        else
                            root.gridModel.beginPointer(mouse.x, mouse.y, mouse.modifiers)
                        mouse.accepted = true
                    }
                    onDoubleClicked: function(mouse) {
                        if (mouse.button === Qt.LeftButton)
                            root.gridModel.doublePointer(mouse.x, mouse.y)
                        mouse.accepted = true
                    }
                    onPositionChanged: function(mouse) {
                        if (mouse.buttons & Qt.RightButton)
                            root.gridModel.updateRightPointer(mouse.x, mouse.y)
                        else if (mouse.buttons & Qt.LeftButton)
                            root.gridModel.updatePointer(mouse.x, mouse.y)
                        else
                            root.gridModel.updateHover(mouse.x, mouse.y)
                    }
                    onReleased: function(mouse) {
                        if (mouse.button === Qt.RightButton)
                            root.gridModel.endRightPointer(mouse.x, mouse.y)
                        else
                            root.gridModel.endPointer(mouse.x, mouse.y)
                        mouse.accepted = true
                    }
                    onCanceled: root.gridModel.inputCancelled(root.cancelReasonPointerUngrabbed)
                    onExited: {
                        if (pressedButtons === Qt.NoButton)
                            root.gridModel.clearKeyboardHover()
                    }
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    root.deliverWheel(event, false)
                }
            }
        }
    }

    function configureViewport() {
        var dpr = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
        root.gridModel.configureViewport(Math.max(rollPlot.width, 1.0),
                                         Math.max(rollPlot.height, 1.0),
                                         root.gridModel.baseFontPx, dpr)
    }

    function deliverWheel(event, overGutter) {
        root.gridModel.handleWheel(event.angleDelta.x, event.angleDelta.y,
                                   event.pixelDelta.x, event.pixelDelta.y,
                                   event.modifiers, event.phase, overGutter,
                                   event.x, event.y)
        event.accepted = true
    }

    Component.onCompleted: configureViewport()
}
