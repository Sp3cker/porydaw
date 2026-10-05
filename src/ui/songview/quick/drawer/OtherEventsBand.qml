pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Porydaw.Ui
import PorydawApp as App

Rectangle {
    id: band
    objectName: "timelineOtherEventsBand"
    required final property App.OtherEventsBandPresenter presenter
    required final property App.GridPalette colors
    required final property App.PianoGrid gridModel
    required final property EditorSurface overlayRoot
    required final property real timelineSplitX
    required final property real plotWidth
    required final property font applicationFont
    height: presenter.bandHeight
    color: colors.chromeBackground

    Rectangle {
        anchors.top: parent.top
        width: band.width
        height: 1
        color: band.colors.separator
    }

    Text {
        id: gutterLabel
        objectName: "timelineOtherEventsLabel"
        x: band.presenter.gutterInset
        width: Math.max(0, band.timelineSplitX - x)
        height: band.height
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
        height: band.height
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        enabled: band.presenter !== null && band.gridModel !== null
        onEntered: {
            if (band.presenter) band.presenter.pointerLeft()
        }

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
        height: band.height
        clip: true

        Rectangle {
            objectName: "timelineOtherEventsPreRoll"
            width: Math.min(plot.width, Math.max(0, -band.overlayRoot.scrollX))
            height: plot.height
            color: band.colors.rulerPreRollMask
        }

        Item {
            id: markerContent
            width: plot.width
            height: plot.height
            x: -band.overlayRoot.scrollX
            Repeater {
                id: markerRepeater
                objectName: "timelineOtherEventsMarkers"
                model: band.presenter.markers
                delegate: Shape {
                    id: marker
                    required property var model
                    readonly property real markerX: model.x
                    required property color color
                    objectName: "timelineOtherEventsMarker"
                    x: marker.markerX - band.presenter.markerHalfWidth
                    y: (band.height - height) / 2
                    width: 2 * band.presenter.markerHalfWidth
                    height: 2 * band.presenter.markerHalfHeight
                    ShapePath {
                        fillColor: marker.color
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
        }

        MouseArea {
            objectName: "timelineOtherEventsInput"
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            hoverEnabled: true
            enabled: band.presenter !== null && band.gridModel !== null
            onPositionChanged: (mouse) => {
                if (band.presenter) band.presenter.pointerMoved(mouse.x, mouse.y)
            }
            onExited: {
                if (band.presenter) band.presenter.pointerLeft()
            }

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
