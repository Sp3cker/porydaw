import QtQuick
import SwiftGrid 1.0

Item {
    id: root
    objectName: "swiftRollOverlay"
    clip: true
    property bool centeredOnNotes: false
    // Mirrors TimelineInputCancelReason::Hidden (timelineinput.h). The host
    // names cancel reasons; QML cannot import the C++ enum.
    readonly property int cancelReasonHidden: 2

    onWidthChanged: configureViewport()
    onHeightChanged: configureViewport()

    required property string documentToken
    required property int selectedTrack

    readonly property QtObject gridModel: swiftGridModel
    readonly property int noteCount: swiftGridModel.renderedNoteCount
    readonly property string appliedRevisionText: swiftGridModel.appliedRevisionText

    PianoGrid {
        id: swiftGridModel
        objectName: "swiftGridModel"
        readOnly: true
        documentToken: root.documentToken
        documentTrack: root.selectedTrack
    }

    Rectangle {
        objectName: "swiftRollBackground"
        anchors.fill: parent
        color: swiftGridModel.palette.rollBackground
        z: -1
    }

    Item {
        id: rollBandContent
        y: -flick.contentY
        width: root.width
        height: Math.max(swiftGridModel.gridHeight, 1)
        z: 1

        Item {
            id: rollGutterSide
            objectName: "timelineQuickRollGutter"
            width: swiftGridModel.keyboardWidth
            height: parent.height
            clip: true
        }

        MouseArea {
            width: rollGutterSide.width
            height: parent.height
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onPositionChanged: function (mouse) {
                swiftGridModel.hoverKeyboard(mouse.y);
            }
            onExited: function () {
                swiftGridModel.clearKeyboardHover();
            }
            z: 10
        }
    }

    Item {
        id: rollPlot
        objectName: "timelineQuickRollPlot"
        x: swiftGridModel.keyboardWidth
        width: Math.max(root.width - swiftGridModel.keyboardWidth, 0)
        height: root.height
        clip: true

        onWidthChanged: root.configureViewport()
        onHeightChanged: root.configureViewport()

        Flickable {
            id: flick
            objectName: "swiftRollViewport"
            anchors.fill: parent
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds

            contentWidth: pianoGridSurface.width
            contentHeight: pianoGridSurface.height
            onContentXChanged: swiftGridModel.setViewportScrollX(contentX)
            onContentYChanged: swiftGridModel.setViewportScroll(contentY)

            // Unified viewing scroll: WheelHandler captures wheel/pan over the
            // visible viewport; rollInput.onWheel forwards content-area wheel events.
            WheelHandler {
                id: viewportWheel
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    var dx = event.angleDelta.x !== 0 ? event.angleDelta.x : event.pixelDelta.x;
                    var dy = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y;
                    root.scrollBy(dx, dy);
                    event.accepted = true;
                }
            }
            Item {
                id: pianoGridSurface
                objectName: "pianoGridSurface"
                width: Math.max(swiftGridModel.gridWidth, 1)
                height: Math.max(swiftGridModel.gridHeight, 1)

                onVisibleChanged: {
                    if (!visible)
                        swiftGridModel.inputCancelled(root.cancelReasonHidden);
                }

                PianoRollCanvas {
                    bandSide: rollBandContent
                    gutterSide: rollGutterSide
                    plotSide: pianoGridSurface
                    timelineScene: swiftGridModel.scene
                }

                MouseArea {
                    id: rollInput
                    objectName: "swiftRollInput"
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    preventStealing: true
                    hoverEnabled: true

                    cursorShape: {
                        switch (swiftGridModel.cursorKind) {
                        case 1:
                            return Qt.OpenHandCursor;
                        case 2:
                        case 3:
                            return Qt.SizeHorCursor;
                        default:
                            return Qt.ArrowCursor;
                        }
                    }

                    onPressed: function (mouse) {
                        mouse.accepted = true;
                    }
                    onDoubleClicked: function (mouse) {
                        mouse.accepted = true;
                    }
                    onPositionChanged: function (mouse) {
                        swiftGridModel.hoverPointer(mouse.x, mouse.y);
                    }
                    onReleased: function (mouse) {
                        mouse.accepted = true;
                    }
                    onCanceled: function () {
                    }
                    onWheel: function (e) {
                        var dx = e.angleDelta.x !== 0 ? e.angleDelta.x : e.pixelDelta.x;
                        var dy = e.angleDelta.y !== 0 ? e.angleDelta.y : e.pixelDelta.y;
                        root.scrollBy(dx, dy);
                        e.accepted = true;
                    }
                }
            }
        }
    }

    function configureViewport() {
        var dpr = Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0;
        swiftGridModel.configureViewport(swiftGridModel.baseFontPx, dpr, Math.max(rollPlot.width, 1.0), Math.max(rollPlot.height, 1.0));
        if (rollPlot.height > 1 && !root.centeredOnNotes) {
            flick.contentY = swiftGridModel.initialScrollY;
            root.centeredOnNotes = true;
        }
    }
    function scrollBy(dx, dy) {
        var maxX = Math.max(0, flick.contentWidth - flick.width);
        var maxY = Math.max(0, flick.contentHeight - flick.height);
        flick.contentX = Math.max(0, Math.min(maxX, flick.contentX - dx));
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY - dy));
    }


    Component.onCompleted: {
        configureViewport();
    }
}
