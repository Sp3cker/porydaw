pragma ComponentBehavior: Bound
pragma ValueTypeBehavior: Addressable, Assertable

import QtQuick
import QtQuick.Controls.Fusion as Fusion
import QtQuick.Templates as T
import Porydaw.Icons

// Fusion's check box frame with a glyph check mark, shared by CheckBox and MenuItem.
Rectangle {
    id: indicator

    required property T.AbstractButton control
    readonly property T.CheckBox checkBox: control as T.CheckBox
    property real baseLightness: 1.6

    implicitWidth: Math.round(control.font.pixelSize * 1.1)
    implicitHeight: implicitWidth
    color: control.down
        ? (Fusion.Fusion.mergedColors(indicator.control.palette.base, indicator.control.palette.windowText, 85) as color)
        : (Qt.lighter(indicator.control.palette.base, baseLightness) as color)
    border.color: control.visualFocus
        ? (Fusion.Fusion.highlightedOutline(indicator.control.palette) as color)
        : (Qt.lighter(Fusion.Fusion.outline(indicator.control.palette), 1.1) as color)

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
        visible: indicator.checkBox ? indicator.checkBox.checkState === Qt.Checked
                                    : indicator.control.checked
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Math.round(indicator.width / 4)
        color: indicator.control.palette.text
        visible: indicator.checkBox && indicator.checkBox.checkState === Qt.PartiallyChecked
    }
}
