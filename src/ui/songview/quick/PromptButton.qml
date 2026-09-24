// Shared Accept/Cancel chrome for the canvas prompt family: pressed/focus
// border states, Return/Enter/Space activation, tap handling, and button
// accessibility. Owners keep semantics — objectName, tab navigation, and the
// activated handler — and pass their label plus an optional width floor so
// paired buttons stay visually aligned with an input or each other.
import QtQuick

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

    function activate() {
        if (enabled)
            button.activated()
    }

    Text {
        id: label

        anchors.centerIn: parent
        // Pressed and inactive states must keep a legal ink for their
        // surface: pressedText on the pressed fill, disabledText inside a
        // disabled button. Appearances that predate a key fall back to the
        // normal button ink; a missing appearance draws nothing, never throws.
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
    // Claim the activation keys so window shortcuts never steal them from a
    // focused prompt button; VoicePicker buttons keep their historical
    // pass-through via claimsShortcuts: false.
    Keys.onShortcutOverride: (event) => event.accepted = claimsShortcuts &&
        (event.key === Qt.Key_Space || event.key === Qt.Key_Return
         || event.key === Qt.Key_Enter)

    TapHandler {
        id: tap

        onTapped: button.activate()
    }
}
