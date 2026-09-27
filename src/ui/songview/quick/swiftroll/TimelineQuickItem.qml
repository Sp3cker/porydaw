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

        // One dict role for geometry: three role reads per model change instead
        // of a model fetch plus per-property metaCall round-trips.
        delegate: Rectangle {
            required property var frame
            required property string fillColor
            required property string primitiveName

            objectName: primitiveName
            x: frame.x
            y: frame.y
            width: frame.width
            height: frame.height
            color: fillColor
        }
    }
}
