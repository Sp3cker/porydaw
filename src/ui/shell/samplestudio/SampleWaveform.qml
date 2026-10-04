pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp

Item {
    id: surface
    required property SampleWaveformModel model
    required property QtObject colors
    required property real baseFontPx
    property bool dragging: false

    function resizeModel(): void {
        surface.model.setViewport(surface.width, surface.height - seam.height)
        surface.model.setSeamViewport(seam.width, seam.height)
        surface.model.setBaseFontPx(surface.baseFontPx)
    }
    onWidthChanged: resizeModel()
    onHeightChanged: resizeModel()
    Component.onCompleted: resizeModel()

    Rectangle {
        anchors.fill: parent
        color: surface.colors.windowBackground
    }
    DisplayList {
        id: waveformList
        objectName: "sampleWaveformDisplay"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: seam.top
        clip: true
        source: surface.model
        list: 0
        revision: surface.model.displayRevision
    }
    DisplayList {
        id: seam
        objectName: "sampleSeamDisplay"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 8 * surface.baseFontPx
        clip: true
        source: surface.model
        list: 1
        revision: surface.model.displayRevision
    }
    MouseArea {
        id: input
        anchors.fill: waveformList
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: surface.model.handleAt(mouseX, mouseY) !== 0
                     ? Qt.SizeHorCursor : Qt.ArrowCursor
        onPressed: mouse => {
            surface.dragging = surface.model.press(mouse.x, mouse.y)
            mouse.accepted = true
        }
        onPositionChanged: mouse => {
            if (pressed) surface.model.drag(mouse.x)
        }
        onReleased: {
            surface.model.release()
            surface.dragging = false
        }
        onCanceled: {
            surface.model.release()
            surface.dragging = false
        }
        onWheel: wheel => {
            surface.model.zoom(wheel.x, wheel.angleDelta.y / 120)
            wheel.accepted = true
        }
        onDoubleClicked: surface.model.fit()
    }
}
