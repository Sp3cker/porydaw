pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Fusion as Fusion
import Porydaw.Icons

// Fusion's SpinBox with glyph step arrows.
Fusion.SpinBox {
    id: control

    up.indicator: Rectangle {
        x: control.mirrored ? 1 : control.width - width - 1
        y: 1
        height: control.height / 2 - 1
        implicitWidth: Math.round(control.font.pixelSize * 1.25)
        implicitHeight: Math.round(control.font.pixelSize * 0.75)
        radius: 2
        color: control.up.pressed ? Fusion.Fusion.buttonColor(control.palette, false, true, true)
                                  : "transparent"

        AppIcon {
            anchors.fill: parent
            icon: Icons.spinUp
            color: control.palette.buttonText
        }
    }

    down.indicator: Rectangle {
        x: control.mirrored ? 1 : control.width - width - 1
        y: control.height - height - 1
        height: control.height / 2 - 1
        implicitWidth: Math.round(control.font.pixelSize * 1.25)
        implicitHeight: Math.round(control.font.pixelSize * 0.75)
        radius: 2
        color: control.down.pressed ? Fusion.Fusion.buttonColor(control.palette, false, true, true)
                                    : "transparent"

        AppIcon {
            anchors.fill: parent
            icon: Icons.spinDown
            color: control.palette.buttonText
        }
    }
}
