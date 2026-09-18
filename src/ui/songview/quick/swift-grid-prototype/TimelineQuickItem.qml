import QtQuick

Item {
    id: root

    // Direct binding to one of GridScene's semantically named rect models
    // (e.g. scene.rulerMarks, scene.pianoNoteFills).
    required property var rects

    Repeater {
        model: root.rects

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
