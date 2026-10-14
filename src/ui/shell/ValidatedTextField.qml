pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import PorydawApp

// A text field outlined in the palette's error ink while `invalid`; Swift decides validity.
TextField {
    id: field
    required property GridPalette colors
    property bool invalid: false

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: 2
        border.color: field.colors.errorText
        border.width: Math.max(1, Math.round(field.font.pixelSize / 7))
        visible: field.invalid
    }
}
