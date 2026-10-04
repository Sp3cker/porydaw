pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Porydaw.Ui
import Porydaw.Icons

Rectangle {
    id: control
    required property QtObject colors
    required property string label
    required property var icon
    required property int baseFontPx
    required property var typography
    property bool checked: false
    property bool actionable: true
    signal activated()

    objectName: "transportButton"
    width: Math.round(Math.min(baseFontPx, 12) * 2.75)
    height: width
    Layout.minimumWidth: Math.round(Math.min(baseFontPx, 12) * 2.75)
    Layout.maximumWidth: Layout.minimumWidth
    radius: Qt.font(control.typography.body).pixelSize / 6
    color: checked ? colors.buttonPressedBackground
           : hover.hovered ? colors.buttonHoverBackground : "transparent"
    enabled: actionable
    focus: false
    activeFocusOnTab: actionable
    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.description: checked ? qsTr("On") : qsTr("Off")

    readonly property color foreground: actionable ? (checked ? colors.buttonPressedText
                                                              : colors.buttonText)
                                                   : colors.disabledText
    AppIcon {
        anchors.centerIn: parent
        height: Math.round(Math.min(control.baseFontPx, 12) * 1.9)
        width: height
        icon: control.icon
        color: control.foreground
    }
    HoverHandler { id: hover }
    TapHandler {
        enabled: control.actionable
        onTapped: control.activated()
    }
    Keys.onReturnPressed: function(event: KeyEvent): void {
        if (control.actionable) { control.activated(); event.accepted = true }
    }
    Keys.onEnterPressed: function(event: KeyEvent): void {
        if (control.actionable) { control.activated(); event.accepted = true }
    }
}
