pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import Porydaw.Icons
import PorydawApp

// Tool button showing one icon-font glyph one text unit tall, dimmed when disabled.
ToolButton {
    id: button
    required property IconSpec glyph
    required property GridPalette colors
    required property real unit
    contentItem: Item {
        implicitWidth: glyphIcon.width
        implicitHeight: glyphIcon.height
        AppIcon {
            id: glyphIcon
            anchors.centerIn: parent
            width: Math.round(button.unit)
            height: width
            icon: button.glyph
            color: button.enabled ? button.colors.windowText : button.colors.disabledText
        }
    }
}
