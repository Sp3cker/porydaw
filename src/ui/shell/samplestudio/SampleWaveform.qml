pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp

Item {
    id: surface
    required property MarkerWaveformModel model
    required property GridPalette colors
    required property real baseFontPx
    signal pressStarted(int button)
    signal clicked(real x, real y)
    signal doubleClicked(real x, real y)

    function resizeModel(): void {
        surface.model.setViewport(surface.width, surface.height)
        surface.model.setBaseFontPx(surface.baseFontPx)
    }
    onWidthChanged: resizeModel()
    onHeightChanged: resizeModel()
    onModelChanged: resizeModel()
    Component.onCompleted: resizeModel()

    Rectangle {
        anchors.fill: parent
        color: surface.colors.windowBackground
    }
    DisplayList {
        id: waveformList
        objectName: "sampleWaveformDisplay"
        anchors.fill: parent
        clip: true
        source: surface.model
        list: 0
        revision: surface.model.displayRevision
    }
    MouseArea {
        id: input
        anchors.fill: waveformList
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: surface.model.handleAt(mouseX, mouseY) !== 0
                     ? Qt.SizeHorCursor : Qt.ArrowCursor
        property bool moved: false
        onPressed: mouse => {
            moved = false
            surface.pressStarted(mouse.button)
            surface.model.press(mouse.x, mouse.y)
        }
        onPositionChanged: mouse => {
            if (!pressed)
                return
            moved = true
            surface.model.drag(mouse.x)
        }
        onReleased: surface.model.release()
        onCanceled: surface.model.release()
        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton && !moved)
                surface.clicked(mouse.x, mouse.y)
        }
        onDoubleClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                surface.doubleClicked(mouse.x, mouse.y)
        }
        onWheel: wheel => {
            surface.model.zoom(wheel.x, wheel.angleDelta.y / 120)
            wheel.accepted = true
        }
    }
}
