pragma ComponentBehavior: Bound
// Shared prompt button chrome; owners supply labels and activation semantics.
import QtQuick
import Porydaw.Ui

Rectangle {
    id: button

    required property var appearance

    property string text: ""
    property real minimumWidth: 0
    readonly property real labelWidth: label.implicitWidth
    // VoicePicker buttons historically leave Space/Return/Enter to shortcut
    // dispatch; the prompt family claims them. Callers keep that difference.
    property bool claimsShortcuts: true

    signal activated()

    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: label.text
    Accessible.focusable: enabled
    Accessible.onPressAction: button.activate()

    implicitWidth: Math.max(labelWidth + 2 * appearance.buttonPadding, minimumWidth)
    implicitHeight: label.implicitHeight + 2 * appearance.buttonPadding
    color: tap.pressed ? appearance.pressedBackground : appearance.buttonBackground
    border.width: appearance.borderWidth
    border.color: activeFocus ? appearance.focus : appearance.outline
    radius: appearance.radius
    opacity: enabled ? 1 : 0.5

    function activate(): void {
        if (enabled)
            button.activated()
    }

    Text {
        id: label

        anchors.centerIn: parent
        // Older appearance maps fall back to the normal button ink.
        color: (!button.enabled ? button.appearance?.disabledText
                : tap.pressed ? button.appearance?.pressedText : null)
               ?? button.appearance?.buttonText ?? "transparent"
        font: button.appearance.font
        text: button.text
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
