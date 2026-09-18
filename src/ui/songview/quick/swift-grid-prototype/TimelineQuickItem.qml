import QtQuick

Item {
    id: root

    enum Layer {
        RulerGutterChrome = 0,
        RulerChrome = 1,
        RulerMarks = 2,
        PianoGridRows = 3,
        PianoGridTime = 4,
        PianoNoteFills = 5,
        PianoDrawPreviewFill = 6,
        PianoNoteBordersAndSelection = 7,
        PianoOverlay = 8,
        PianoKeyboardKeys = 9,
        PianoKeyboardHighlights = 10
    }

    required property QtObject scene
    required property int sceneLayer

    Repeater {
        model: root.scene ? root.scene["layer" + root.sceneLayer] : null

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
