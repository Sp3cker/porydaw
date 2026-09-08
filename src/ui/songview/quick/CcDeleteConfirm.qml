import QtQuick

Item {
    id: prompt

    required property var bridge

    objectName: "ccDeleteConfirm"
    implicitWidth: content.implicitWidth + 2 * bridge.ccDeletePromptAppearance.dialogPadding
    implicitHeight: content.implicitHeight + 2 * bridge.ccDeletePromptAppearance.dialogPadding
    focus: true

    property bool finishing: false

    function acceptDisplayed() {
        if (finishing)
            return
        finishing = true
        bridge.acceptCcDeletePrompt()
    }

    function cancelDisplayed() {
        if (finishing)
            return
        finishing = true
        bridge.cancelCcDeletePrompt()
    }

    // Cancel holds the initial focus, so a bare Return cancels without any
    // navigation; Tab moves to Delete and Backtab returns.
    function activateInitialFocus() {
        cancelButton.forceActiveFocus(Qt.PopupFocusReason)
    }
    Component.onCompleted: Qt.callLater(activateInitialFocus)

    // The focused button claims its own keys first. This terminal sink accepts
    // every declined key so timeline commands never leak out of the shared
    // popup session.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape)
            cancelDisplayed()
        event.accepted = true
    }
    Keys.onReleased: (event) => event.accepted = true

    Accessible.role: Accessible.Client
    Accessible.name: bridge.ccDeletePromptTitle

    Rectangle {
        anchors.fill: parent
        color: bridge.ccDeletePromptAppearance.background
        border.width: bridge.ccDeletePromptAppearance.borderWidth
        border.color: bridge.ccDeletePromptAppearance.outline
        radius: bridge.ccDeletePromptAppearance.radius
    }

    Column {
        id: content

        x: bridge.ccDeletePromptAppearance.dialogPadding
        y: bridge.ccDeletePromptAppearance.dialogPadding
        spacing: bridge.ccDeletePromptAppearance.spacing

        Text {
            color: bridge.ccDeletePromptAppearance.text
            font: bridge.ccDeletePromptAppearance.font
            text: bridge.ccDeletePromptTitle
            renderType: Text.NativeRendering
        }

        Text {
            color: bridge.ccDeletePromptAppearance.text
            font: bridge.ccDeletePromptAppearance.font
            text: bridge.ccDeletePromptMessage
            renderType: Text.NativeRendering
        }

        Row {
            spacing: bridge.ccDeletePromptAppearance.spacing

            Rectangle {
                id: acceptButton

                objectName: "acceptButton"
                activeFocusOnTab: true
                KeyNavigation.tab: cancelButton
                KeyNavigation.backtab: cancelButton
                Accessible.role: Accessible.Button
                Accessible.name: acceptText.text
                function activate() {
                    prompt.acceptDisplayed()
                }
                function activateFromKeyboard(event) {
                    activate()
                    event.accepted = true
                }

                width: Math.max(acceptText.implicitWidth, cancelText.implicitWidth)
                       + 2 * bridge.ccDeletePromptAppearance.buttonPadding
                height: acceptText.implicitHeight
                        + 2 * bridge.ccDeletePromptAppearance.buttonPadding
                color: acceptTap.pressed ? bridge.ccDeletePromptAppearance.pressedBackground
                                         : bridge.ccDeletePromptAppearance.buttonBackground
                border.width: bridge.ccDeletePromptAppearance.borderWidth
                border.color: activeFocus ? bridge.ccDeletePromptAppearance.focus
                                          : bridge.ccDeletePromptAppearance.outline
                radius: bridge.ccDeletePromptAppearance.radius

                Text {
                    id: acceptText

                    anchors.centerIn: parent
                    color: bridge.ccDeletePromptAppearance.buttonText
                    font: bridge.ccDeletePromptAppearance.font
                    text: qsTr("Delete")
                    renderType: Text.NativeRendering
                }
                Keys.onReturnPressed: (event) => acceptButton.activateFromKeyboard(event)
                Keys.onEnterPressed: (event) => acceptButton.activateFromKeyboard(event)
                Keys.onSpacePressed: (event) => acceptButton.activateFromKeyboard(event)
                Keys.onShortcutOverride: (event) => event.accepted =
                    event.key === Qt.Key_Space || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter

                Accessible.focusable: true
                Accessible.onPressAction: acceptButton.activate()

                TapHandler {
                    id: acceptTap

                    onTapped: acceptButton.activate()
                }
            }
            Rectangle {
                id: cancelButton

                objectName: "cancelButton"
                activeFocusOnTab: true
                KeyNavigation.tab: acceptButton
                KeyNavigation.backtab: acceptButton
                Accessible.role: Accessible.Button
                Accessible.name: cancelText.text
                function activate() {
                    prompt.cancelDisplayed()
                }
                function activateFromKeyboard(event) {
                    activate()
                    event.accepted = true
                }

                width: Math.max(acceptText.implicitWidth, cancelText.implicitWidth)
                       + 2 * bridge.ccDeletePromptAppearance.buttonPadding
                height: cancelText.implicitHeight
                        + 2 * bridge.ccDeletePromptAppearance.buttonPadding
                color: cancelTap.pressed ? bridge.ccDeletePromptAppearance.pressedBackground
                                         : bridge.ccDeletePromptAppearance.buttonBackground
                border.width: bridge.ccDeletePromptAppearance.borderWidth
                border.color: activeFocus ? bridge.ccDeletePromptAppearance.focus
                                          : bridge.ccDeletePromptAppearance.outline
                radius: bridge.ccDeletePromptAppearance.radius

                Text {
                    id: cancelText

                    anchors.centerIn: parent
                    color: bridge.ccDeletePromptAppearance.buttonText
                    font: bridge.ccDeletePromptAppearance.font
                    text: qsTr("Cancel")
                    renderType: Text.NativeRendering
                }
                Keys.onReturnPressed: (event) => cancelButton.activateFromKeyboard(event)
                Keys.onEnterPressed: (event) => cancelButton.activateFromKeyboard(event)
                Keys.onSpacePressed: (event) => cancelButton.activateFromKeyboard(event)
                Keys.onShortcutOverride: (event) => event.accepted =
                    event.key === Qt.Key_Space || event.key === Qt.Key_Return
                    || event.key === Qt.Key_Enter

                Accessible.focusable: true
                Accessible.onPressAction: cancelButton.activate()

                TapHandler {
                    id: cancelTap

                    onTapped: cancelButton.activate()
                }
            }
        }
    }
}
