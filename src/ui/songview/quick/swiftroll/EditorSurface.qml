import QtQuick
import "../drawer"

Item {
    id: root
    objectName: "swiftRollOverlay"
    clip: true
    required property QtObject applicationSession
    property url drawerPreferenceLocation: ""
    readonly property int cancelReasonPointerUngrabbed: 1
    readonly property int cancelReasonHidden: 2
    readonly property var gridModel: applicationSession.gridPresenter()
    readonly property var drawerPresenter: applicationSession.drawerPresenter()
    readonly property int noteCount: gridModel.renderedNoteCount
    readonly property string appliedRevisionText: gridModel.appliedRevisionText

    // The drawer's bar row is measured in the application font, as production's
    // chromeRowHeight() measures its dock and tab rows.
    FontMetrics {
        id: applicationFontMetrics
        font: Application.font
    }

    onWidthChanged: configureViewport()
    onHeightChanged: configureViewport()
    onVisibleChanged: {
        // Cancellation goes through the session, which fans out to the grid and
        // the drawer; a document-scoped grid presenter may already be released
        // while the surface is still being hidden.
        if (!visible && root.applicationSession)
            root.applicationSession.cancelGridInput(root.cancelReasonHidden)
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

    // The drawer holds the bottom of the surface, so the roll band keeps only
    // the height the drawer leaves it.
    Item {
        id: rollBandContent
        objectName: "swiftRollBand"
        width: root.width
        height: Math.max(root.height - editorDrawer.height, 0)
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
            // The band carries only the height the drawer leaves, so the plot
            // and the viewport push follow the band rather than the surface.
            height: parent.height
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
                    // The drawer returns focus here when no section stays visible.
                    activeFocusOnTab: true

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

    // The container owns its chrome and publishes drawer-local rectangles; the
    // composition places it at the bottom and the container sizes its own height
    // from the presenter. The container names itself.
    EditorDrawer {
        id: editorDrawer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        z: 2

        applicationSession: root.applicationSession
        presenter: root.drawerPresenter
        drawerPalette: root.gridModel.palette
        preferenceLocation: root.drawerPreferenceLocation
    }

    function configureViewport() {
        var dpr = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
        root.gridModel.configureViewport(Math.max(rollPlot.width, 1.0),
                                         Math.max(rollPlot.height, 1.0),
                                         root.gridModel.baseFontPx, dpr)
        // The drawer maps its sections against the same gutter and base font the
        // roll renders with, so both pushes carry the same facts.
        root.drawerPresenter.configureLayout(root.width, root.height,
                                             root.gridModel.keyboardWidth,
                                             root.gridModel.baseFontPx,
                                             applicationFontMetrics.lineSpacing)
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
