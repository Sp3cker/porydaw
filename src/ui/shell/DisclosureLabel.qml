pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Icons

// A disclosure button's content: a right (closed) or down (open) triangle glyph
// followed by the button's text, both in the button's text ink.
Row {
    id: root
    required property var control
    required property bool expanded
    spacing: Math.round(root.control.font.pixelSize / 3)

    AppIcon {
        anchors.verticalCenter: parent.verticalCenter
        width: root.control.font.pixelSize
        height: width
        icon: root.expanded ? Icons.disclosureOpen : Icons.disclosureClosed
        color: root.control.palette.buttonText
    }
    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.control.text
        font: root.control.font
        color: root.control.palette.buttonText
        renderType: Text.NativeRendering
    }
}
