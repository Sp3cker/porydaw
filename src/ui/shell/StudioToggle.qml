pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import PorydawApp

// Rounded mockup toggle: accent track when on, knob slides right.
Item {
    id: toggle
    required property GridPalette colors
    required property real unit
    property bool checked: false
    property string text: ""
    signal toggled(bool checked)
    implicitWidth: innerRow.implicitWidth
    implicitHeight: innerRow.implicitHeight
    Accessible.role: Accessible.CheckBox
    Accessible.name: toggle.text
    Accessible.checked: toggle.checked
    RowLayout {
        id: innerRow
        anchors.fill: parent
        spacing: toggle.unit * 0.6
    Rectangle {
        Layout.preferredWidth: 2.15 * toggle.unit
        Layout.preferredHeight: 1.23 * toggle.unit
        radius: height / 2
        color: toggle.checked ? toggle.colors.tabSelectedBackground : toggle.colors.buttonBackground
        border.color: toggle.checked ? toggle.colors.tabSelectedBackground : toggle.colors.outline
        border.width: 1
        Rectangle {
            width: parent.height - 6
            height: parent.height - 6
            radius: height / 2
            anchors.verticalCenter: parent.verticalCenter
            x: toggle.checked ? parent.width - width - 3 : 3
            color: toggle.checked ? toggle.colors.selectionText : toggle.colors.secondaryText
            Behavior on x {
                NumberAnimation {
                    duration: 80
                }
            }
        }
    }
    Label {
        text: toggle.text
        color: toggle.colors.windowText
        verticalAlignment: Text.AlignVCenter
    }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: toggle.toggled(!toggle.checked)
    }
}
