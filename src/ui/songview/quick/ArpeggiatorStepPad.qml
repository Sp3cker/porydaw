pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Fusion as Fusion
import Porydaw.Ui
import PorydawApp as App

Fusion.AbstractButton {
    id: pad

    required property App.PromptStyle appearance
    required property App.GridPalette colors
    required property real baseFontPx
    required property int stepIndex
    required property bool stepOn
    required property bool accented
    required property bool playing
    signal edited(bool accent)

    implicitWidth: baseFontPx * 2.6
    implicitHeight: baseFontPx * 2.8
    focusPolicy: Qt.StrongFocus
    Accessible.name: qsTr("Step %1").arg(stepIndex + 1)
    Accessible.checkable: true
    Accessible.checked: stepOn
    Accessible.description: qsTr("%1. %2. Return toggles step; Shift+Return or right click toggles accent.")
        .arg(stepOn ? qsTr("On") : qsTr("Off"))
        .arg(accented ? qsTr("Accented") : qsTr("No accent"))
    Accessible.onPressAction: pad.edited(false)
    onClicked: pad.edited(false)
    Keys.onReturnPressed: event => { pad.edited((event.modifiers & Qt.ShiftModifier) !== 0); event.accepted = true }
    Keys.onEnterPressed: event => { pad.edited((event.modifiers & Qt.ShiftModifier) !== 0); event.accepted = true }

    background: Rectangle {
        radius: pad.appearance.radius
        color: pad.enabled && (pad.down || pad.stepOn) ? pad.colors.buttonPressedBackground : pad.colors.buttonBackground
        border.width: pad.playing ? pad.appearance.borderWidth * 3 : pad.appearance.borderWidth
        border.color: pad.activeFocus ? pad.appearance.focus : pad.playing ? pad.colors.playhead : pad.colors.outline
    }
    contentItem: Text {
        text: qsTr("%1%2%3").arg(pad.playing ? "▶ " : "").arg(pad.stepIndex + 1).arg(pad.accented ? " •" : "")
        font: pad.appearance.font
        color: !pad.enabled ? pad.colors.disabledText : pad.down || pad.stepOn ? pad.colors.buttonPressedText : pad.colors.buttonText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        renderType: Text.NativeRendering
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.LeftButton
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton || (mouse.modifiers & Qt.ShiftModifier)) {
                pad.forceActiveFocus(Qt.MouseFocusReason)
                pad.edited(true)
                mouse.accepted = true
            } else {
                mouse.accepted = false
            }
        }
    }
}
