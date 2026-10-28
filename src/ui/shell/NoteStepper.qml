pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import PorydawApp

// Note stepper: note name left, MIDI number faint right, arrows attached.
Rectangle {
    id: stepper
    required property GridPalette colors
    required property real unit
    required property NumberFieldFormat format
    property int keyValue: 60
    // Readout for tests and labels; Swift owns parsing and clamping.
    readonly property string text: stepper.format.text(stepper.keyValue)
    readonly property real hairline: Math.max(1, Math.round(stepper.unit / 13))
    signal stepped(int value)
    signal spacePressed()
    implicitHeight: 2.15 * stepper.unit
    implicitWidth: 10 * stepper.unit
    activeFocusOnTab: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space && event.modifiers === Qt.NoModifier && !event.isAutoRepeat) {
            stepper.spacePressed()
            event.accepted = true
        }
    }
    radius: 0.46 * stepper.unit
    color: stepper.colors.inputBackground
    border.color: stepper.colors.outline
    border.width: stepper.hairline
    Accessible.role: Accessible.SpinBox
    Accessible.name: stepper.format.text(stepper.keyValue)
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: stepper.unit * 0.6
        spacing: stepper.unit * 0.45
        Label {
            text: stepper.format.text(stepper.keyValue)
            color: stepper.colors.windowText
            verticalAlignment: Text.AlignVCenter
        }
        Label {
            text: "(%1)".arg(stepper.keyValue)
            color: stepper.colors.secondaryText
            verticalAlignment: Text.AlignVCenter
        }
        Item {
            Layout.fillWidth: true
        }
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1.5 * stepper.unit
            color: stepper.colors.buttonBackground
            border.color: stepper.colors.outline
            border.width: stepper.hairline
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                MouseArea {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    onClicked: stepper.stepped(stepper.keyValue + 1)
                    Label {
                        anchors.centerIn: parent
                        text: "▲"
                        font.pixelSize: Math.max(6, Math.round(stepper.unit * 0.55))
                        color: stepper.colors.secondaryText
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: stepper.hairline
                    color: stepper.colors.outline
                }
                MouseArea {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    onClicked: stepper.stepped(stepper.keyValue - 1)
                    Label {
                        anchors.centerIn: parent
                        text: "▼"
                        font.pixelSize: Math.max(6, Math.round(stepper.unit * 0.55))
                        color: stepper.colors.secondaryText
                    }
                }
            }
        }
    }
}
