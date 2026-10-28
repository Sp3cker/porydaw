pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import PorydawApp

// Rounded mockup toggle: accent track when on, knob slides right. Enter/Return toggles
// with focus; bare Space stays with the window audition command.
Item {
    id: toggle
    required property GridPalette colors
    required property real unit
    property bool checked: false
    property string text: ""
    signal toggled(bool checked)
    readonly property real hairline: Math.max(1, Math.round(toggle.unit / 13))
    implicitWidth: innerRow.implicitWidth
    implicitHeight: innerRow.implicitHeight
    activeFocusOnTab: true
    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
            toggle.toggled(!toggle.checked)
            event.accepted = true
        }
    }
    Accessible.role: Accessible.CheckBox
    Accessible.name: toggle.text
    Accessible.checked: toggle.checked
    Accessible.onPressAction: toggle.toggled(!toggle.checked)
    Accessible.onToggleAction: toggle.toggled(!toggle.checked)
    RowLayout {
        id: innerRow
        anchors.fill: parent
        spacing: toggle.unit * 0.6
        Rectangle {
            id: track
            Layout.preferredWidth: 2.15 * toggle.unit
            Layout.preferredHeight: 1.23 * toggle.unit
            radius: height / 2
            color: toggle.checked ? toggle.colors.tabSelectedBackground : toggle.colors.buttonBackground
            border.color: toggle.activeFocus ? toggle.colors.focusOutline
                : toggle.checked ? toggle.colors.tabSelectedBackground : toggle.colors.outline
            border.width: toggle.activeFocus ? 2 * toggle.hairline : toggle.hairline
            Rectangle {
                readonly property real inset: Math.round(toggle.unit / 4)
                width: track.height - 2 * inset
                height: width
                radius: height / 2
                anchors.verticalCenter: parent.verticalCenter
                x: toggle.checked ? track.width - width - inset : inset
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
