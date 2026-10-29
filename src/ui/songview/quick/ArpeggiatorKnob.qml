pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Fusion as Fusion
import Porydaw.Ui
import PorydawApp as App

Column {
    id: control

    required property App.PromptStyle appearance
    required property App.GridPalette colors
    required property real baseFontPx
    required property string label
    required property int value
    required property int minimumValue
    required property int maximumValue
    property string suffix: ""
    property string description: ""
    property App.MouseHints hintService: null
    property alias focusItem: dial
    signal valueCommitted(int value)

    spacing: appearance.spacing / 2
    width: Math.max(baseFontPx * 7, title.implicitWidth, editor.implicitWidth)

    Text {
        id: title
        anchors.horizontalCenter: parent.horizontalCenter
        text: control.label
        font: control.appearance.font
        color: control.colors.windowText
        renderType: Text.NativeRendering
    }

    Fusion.Dial {
        id: dial
        anchors.horizontalCenter: parent.horizontalCenter
        width: control.baseFontPx * 3.5
        height: width
        from: control.minimumValue
        to: control.maximumValue
        stepSize: 1
        snapMode: Fusion.Dial.SnapAlways
        value: control.value
        wheelEnabled: true
        Accessible.name: control.label
        Accessible.description: control.description
        onMoved: control.valueCommitted(Math.round(value))
        background: Rectangle {
            implicitWidth: control.baseFontPx * 3.5
            implicitHeight: implicitWidth
            radius: width / 2
            color: control.colors.buttonBackground
            border.width: control.appearance.borderWidth
            border.color: dial.activeFocus ? control.appearance.focus : control.colors.outline
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.7
                height: width
                radius: width / 2
                color: control.colors.windowBackground
                border.width: control.appearance.borderWidth
                border.color: control.colors.outline
            }
        }
        handle: Item {
            x: dial.width / 2 - width / 2
            y: dial.height / 2 - height / 2
            width: control.baseFontPx / 3
            height: dial.height
            rotation: dial.angle
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.12
                width: parent.width
                height: control.baseFontPx * 0.7
                radius: width / 2
                color: control.colors.buttonText
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: control.appearance.spacing / 2
        DragInput {
            id: editor
            appearance: control.appearance
            inputObjectName: control.objectName + "Input"
            hintService: control.hintService
            value: control.value
            minimumValue: control.minimumValue
            maximumValue: control.maximumValue
            accessibleName: control.label
            accessibleDescription: control.description
            onValueCommitted: committed => control.valueCommitted(committed)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: control.value === 101 && control.maximumValue === 101 ? qsTr("Tie") : control.suffix
            font: control.appearance.font
            color: control.colors.windowText
            renderType: Text.NativeRendering
        }
    }
}
