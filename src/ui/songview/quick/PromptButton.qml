pragma ComponentBehavior: Bound
// Shared prompt button chrome; owners supply labels and activation semantics.
import QtQuick
import Porydaw.Ui
import PorydawApp

Rectangle {
    id: button

    required final property PromptStyle appearance

    final property string text: ""
    final property real minimumWidth: 0
    final readonly property real labelWidth: label.implicitWidth
    // VoicePicker buttons historically leave Space/Return/Enter to shortcut
    // dispatch; the prompt family claims them. Callers keep that difference.
    property bool claimsShortcuts: true

    signal activated()

    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: label.text
    Accessible.focusable: enabled
    Accessible.onPressAction: button.activate()

    implicitWidth: Math.max(button.labelWidth + 2 * button.appearance.buttonPadding,
                            button.minimumWidth)
    implicitHeight: label.implicitHeight + 2 * button.appearance.buttonPadding
    color: tap.pressed ? button.appearance.pressedBackground : button.appearance.buttonBackground
    border.width: button.appearance.borderWidth
    border.color: button.activeFocus ? button.appearance.focus : button.appearance.outline
    radius: button.appearance.radius
    opacity: enabled ? 1 : 0.5

    function activate(): void {
        if (enabled)
            button.activated()
    }

    Text {
        id: label

        anchors.centerIn: parent
        text: button.text
        color: !button.enabled ? button.appearance.disabledText
             : tap.pressed ? button.appearance.pressedText : button.appearance.buttonText
        font: button.appearance.font
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
    }

    Keys.onReturnPressed: (event) => {
        button.activate()
        event.accepted = true
    }
    Keys.onEnterPressed: (event) => {
        button.activate()
        event.accepted = true
    }
    Keys.onSpacePressed: (event) => {
        button.activate()
        event.accepted = true
    }
    // VoicePicker keeps pass-through via claimsShortcuts: false.
    Keys.onShortcutOverride: (event) => event.accepted = claimsShortcuts &&
        (event.key === Qt.Key_Space || event.key === Qt.Key_Return
         || event.key === Qt.Key_Enter)

    TapHandler {
        id: tap

        onTapped: button.activate()
    }
}
