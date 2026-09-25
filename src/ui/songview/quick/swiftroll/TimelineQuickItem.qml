import QtQuick
import QtBridge 1.0
import Porydaw.Ui

Item {
    id: root

    // Direct binding to one of GridScene's semantically named rect models
    // (e.g. scene.rulerMarks, scene.pianoNoteFills).
    required property var rects
    property bool batched: false
    readonly property bool batchingActive: root.batched
                                           && GraphicsInfo.api !== GraphicsInfo.Software

    QuickDisplayList {
        id: batch

        anchors.fill: parent
        rects: root.batchingActive ? root.rects : null
        visible: root.batchingActive
    }

    Repeater {
        model: root.batchingActive ? null : root.rects

        delegate: Rectangle {
            required property var model
            required property string fillColor
            required property string primitiveName

            objectName: primitiveName
            x: model.x
            y: model.y
            width: model.width
            height: model.height
            color: fillColor
        }
    }
}
