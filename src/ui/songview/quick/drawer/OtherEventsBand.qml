import QtQuick
import QtQuick.Shapes
import Porydaw.Ui

Rectangle {
    id: band
    objectName: "timelineOtherEventsBand"
    required property QtObject presenter
    required property QtObject colors
    required property QtObject gridModel
    required property Item overlayRoot
    required property real timelineSplitX
    required property real plotWidth
    required property font applicationFont
    height: presenter.bandHeight
    color: colors.chromeBackground

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: 1
        color: band.colors.separator
    }

    Text {
        id: gutterLabel
        objectName: "timelineOtherEventsLabel"
        x: band.presenter.gutterInset
        width: Math.max(0, band.timelineSplitX - x)
        height: parent.height
        verticalAlignment: Text.AlignVCenter
        font: band.applicationFont
        color: band.colors.windowText
        text: qsTr("Other events (%1)").arg(band.presenter.labelCount)
        elide: Text.ElideRight
    }

    MouseArea {
        id: gutterInput
        objectName: "timelineOtherEventsGutterInput"
        width: band.timelineSplitX
        height: parent.height
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        onEntered: band.presenter.pointerLeft()

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                band.gridModel.handleWheel(event.angleDelta.x, event.angleDelta.y,
                    event.pixelDelta.x, event.pixelDelta.y, event.modifiers,
                    event.phase, true, event.x, event.y)
                event.accepted = true
            }
        }
    }

    Item {
        id: plot
        x: band.timelineSplitX
        width: band.plotWidth
        height: parent.height
        clip: true

        Rectangle {
            objectName: "timelineOtherEventsPreRoll"
            width: band.presenter.preRollWidth
            height: parent.height
            color: band.colors.rulerPreRollMask
        }

        Repeater {
            id: markerRepeater
            objectName: "timelineOtherEventsMarkers"
            model: band.presenter.markers
            delegate: Shape {
                required property var model
                objectName: "timelineOtherEventsMarker"
                x: model.x - band.presenter.markerHalfWidth
                y: (band.height - height) / 2
                width: 2 * band.presenter.markerHalfWidth
                height: 2 * band.presenter.markerHalfHeight
                ShapePath {
                    fillColor: model.color
                    strokeWidth: 0
                    startX: band.presenter.markerHalfWidth
                    startY: 0
                    PathLine { x: 2 * band.presenter.markerHalfWidth; y: band.presenter.markerHalfHeight }
                    PathLine { x: band.presenter.markerHalfWidth; y: 2 * band.presenter.markerHalfHeight }
                    PathLine { x: 0; y: band.presenter.markerHalfHeight }
                    PathLine { x: band.presenter.markerHalfWidth; y: 0 }
                }
                Accessible.ignored: true
            }
        }

        MouseArea {
            objectName: "timelineOtherEventsInput"
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            onPositionChanged: (mouse) => band.presenter.pointerMoved(mouse.x, mouse.y)
            onExited: band.presenter.pointerLeft()

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: (event) => {
                    band.gridModel.handleWheel(event.angleDelta.x, event.angleDelta.y,
                        event.pixelDelta.x, event.pixelDelta.y, event.modifiers,
                        event.phase, false, event.x, event.y)
                    event.accepted = true
                }
            }
        }
    }

    RulerToolTip {
        objectName: "timelineOtherEventsToolTip"
        parent: band.overlayRoot
        z: 5
        overlayRoot: band.overlayRoot
        anchorRect: Qt.rect(band.x + band.timelineSplitX + band.presenter.toolTipX,
                            band.y + band.presenter.toolTipY, 0, 0)
        toolTipText: band.presenter.toolTipText
        visibleForControl: band.visible && band.presenter.toolTipVisible
        controlFont: band.applicationFont
        backgroundColor: band.colors.inputBackground
        textColor: band.colors.windowText
        outlineColor: band.colors.outline
    }
}
