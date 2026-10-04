pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Fusion as Fusion
import Porydaw.Icons

// Fusion's check box frame with a glyph check mark, shared by CheckBox and MenuItem.
Rectangle {
    id: indicator

    required property Item control
    property real baseLightness: 1.6

    implicitWidth: Math.round(control.font.pixelSize * 1.1)
    implicitHeight: implicitWidth
    color: control.down ? Fusion.Fusion.mergedColors(control.palette.base, control.palette.windowText, 85)
                        : Qt.lighter(control.palette.base, baseLightness)
    border.color: control.visualFocus ? Fusion.Fusion.highlightedOutline(control.palette)
                                      : Qt.lighter(Fusion.Fusion.outline(control.palette), 1.1)

    Rectangle {
        x: 1
        y: 1
        width: indicator.width - 2
        height: 1
        color: Fusion.Fusion.topShadow
        visible: indicator.control.enabled && !indicator.control.down
    }

    AppIcon {
        anchors.fill: parent
        anchors.margins: 2
        icon: Icons.check
        color: indicator.control.palette.text
        visible: indicator.control.checkState === Qt.Checked
                 || (indicator.control.checked && indicator.control.checkState === undefined)
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.round(indicator.width / 4)
        color: indicator.control.palette.text
        visible: indicator.control.checkState === Qt.PartiallyChecked
    }
}
