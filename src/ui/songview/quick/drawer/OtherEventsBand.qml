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
    final property color chromeBackground
    final property color separator
    final property color windowText
    final property color rulerPreRollMask
    final property color inputBackground
    final property color outline
    final property rect toolTipAnchor
    final property string toolTipText
    Binding {
        when: band.colors !== null
        restoreMode: Binding.RestoreNone
        band.chromeBackground: band.colors?.chromeBackground
        band.separator: band.colors?.separator
        band.windowText: band.colors?.windowText
        band.rulerPreRollMask: band.colors?.rulerPreRollMask
        band.inputBackground: band.colors?.inputBackground
        band.outline: band.colors?.outline
    }
    Binding on toolTipAnchor {
        when: band.presenter !== null
        value: Qt.rect(band.x + band.timelineSplitX + band.presenter?.toolTipX,
                       band.y + band.presenter?.toolTipY, 0, 0)
        restoreMode: Binding.RestoreNone
    }
    Binding on toolTipText {
        when: band.presenter !== null
        value: band.presenter?.toolTipText
        restoreMode: Binding.RestoreNone
    }
    final property real markerHalfWidth
    final property real markerHalfHeight
    Binding on markerHalfWidth {
        when: band.presenter !== null
        value: band.presenter?.markerHalfWidth
        restoreMode: Binding.RestoreNone
    }
    Binding on markerHalfHeight {
        when: band.presenter !== null
        value: band.presenter?.markerHalfHeight
        restoreMode: Binding.RestoreNone
    }
    Binding on height {
        when: band.presenter !== null
        value: band.presenter?.bandHeight
        restoreMode: Binding.RestoreNone
    }
    color: band.chromeBackground

    Rectangle {
        anchors.top: parent.top
        width: band.width
        height: 1
        color: band.separator
    }

    Text {
        id: gutterLabel
        objectName: "timelineOtherEventsLabel"
        Binding on x {
            when: band.presenter !== null
            value: band.presenter?.gutterInset
            restoreMode: Binding.RestoreNone
        }
        width: Math.max(0, band.timelineSplitX - x)
        height: band.height
        verticalAlignment: Text.AlignVCenter
        font: band.applicationFont
        color: band.windowText
        Binding on text {
            when: band.presenter !== null
            value: qsTr("Other events (%1)").arg(band.presenter?.labelCount)
            restoreMode: Binding.RestoreNone
        }
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
            color: band.rulerPreRollMask
        }

        Item {
            id: markerContent
            width: plot.width
            height: plot.height
            x: -band.overlayRoot.scrollX
            Repeater {
                id: markerRepeater
                objectName: "timelineOtherEventsMarkers"
                model: band.presenter?.markers
                delegate: Shape {
                    id: marker
                    required property var model
                    readonly property real markerX: model.x
                    required property color color
                    objectName: "timelineOtherEventsMarker"
                    x: marker.markerX - band.markerHalfWidth
                    y: (band.height - height) / 2
                    width: 2 * band.markerHalfWidth
                    height: 2 * band.markerHalfHeight
                    ShapePath {
                        fillColor: marker.color
                        strokeWidth: 0
                        startX: band.markerHalfWidth
                        startY: 0
                        PathLine { x: 2 * band.markerHalfWidth; y: band.markerHalfHeight }
                        PathLine { x: band.markerHalfWidth; y: 2 * band.markerHalfHeight }
                        PathLine { x: 0; y: band.markerHalfHeight }
                        PathLine { x: band.markerHalfWidth; y: 0 }
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
        anchorRect: band.toolTipAnchor
        toolTipText: band.toolTipText
        visibleForControl: band.visible && band.presenter !== null && band.presenter.toolTipVisible
        controlFont: band.applicationFont
        backgroundColor: band.inputBackground
        textColor: band.windowText
        outlineColor: band.outline
    }
}
