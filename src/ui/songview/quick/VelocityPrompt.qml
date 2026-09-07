import QtQuick

Item {
    id: prompt

    required property var bridge

    objectName: "noteVelocityPrompt"
    implicitWidth: content.implicitWidth + 2 * bridge.velocityPromptAppearance.dialogPadding
    implicitHeight: content.implicitHeight + 2 * bridge.velocityPromptAppearance.dialogPadding
    focus: true

    property int draft: bridge.velocityPromptInitialValue
    property bool finishing: false

    function acceptDisplayed() {
        const committed = velocityInput.commitDisplayed()
        if (committed !== null)
            acceptCommitted(committed)
    }

    function acceptCommitted(committed) {
        if (finishing)
            return
        finishing = true
        bridge.acceptVelocityPrompt(committed)
    }

    function cancelDisplayed() {
        if (finishing)
            return
        finishing = true
        bridge.cancelVelocityPrompt()
    }
    function activateInitialFocus() {
        velocityInput.focusInput(Qt.PopupFocusReason)
        velocityInput.selectAll()
    }
    Component.onCompleted: Qt.callLater(activateInitialFocus)



    // The focused DragInput receives accepted text-edit keys first. This
    // terminal sink claims only declined keys so timeline commands never leak
    // out of the native modal window.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape)
            cancelDisplayed()
        event.accepted = true
    }
    Keys.onReleased: (event) => event.accepted = true

    Rectangle {
        anchors.fill: parent
        color: bridge.velocityPromptAppearance.background
        border.width: bridge.velocityPromptAppearance.borderWidth
        border.color: bridge.velocityPromptAppearance.outline
        radius: bridge.velocityPromptAppearance.radius
    }

    Column {
        id: content

        x: bridge.velocityPromptAppearance.dialogPadding
        y: bridge.velocityPromptAppearance.dialogPadding
        spacing: bridge.velocityPromptAppearance.spacing

        Text {
            color: bridge.velocityPromptAppearance.text
            font: bridge.velocityPromptAppearance.font
            text: bridge.velocityPromptLabel
            renderType: Text.NativeRendering
        }

        DragInput {
            id: velocityInput

            appearance: bridge.velocityPromptAppearance
            value: prompt.draft
            minimumValue: bridge.velocityPromptMinimumValue
            maximumValue: bridge.velocityPromptMaximumValue
            inputObjectName: "noteVelocityInput"
            accessibleName: bridge.velocityPromptLabel
            accessibleDescription: bridge.velocityPromptTitle
            onValueCommitted: (committed) => prompt.draft = committed
            onEditingAccepted: (committed) => prompt.acceptCommitted(committed)

        }

        Row {
            spacing: bridge.velocityPromptAppearance.spacing

            Rectangle {
                id: acceptButton

                objectName: "noteVelocityAccept"
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: acceptText.text
                function activate() {
                    prompt.acceptDisplayed()
                }
                function activateFromKeyboard(event) {
                    activate()
                    event.accepted = true
                }


                width: Math.max(acceptText.implicitWidth
                                + 2 * bridge.velocityPromptAppearance.buttonPadding,
                                velocityInput.implicitWidth)
                height: acceptText.implicitHeight
                        + 2 * bridge.velocityPromptAppearance.buttonPadding
                color: acceptTap.pressed ? bridge.velocityPromptAppearance.pressedBackground
                                         : bridge.velocityPromptAppearance.buttonBackground
                border.width: bridge.velocityPromptAppearance.borderWidth
                border.color: activeFocus ? bridge.velocityPromptAppearance.focus
                                          : bridge.velocityPromptAppearance.outline
                radius: bridge.velocityPromptAppearance.radius

                Text {
                    id: acceptText

                    anchors.centerIn: parent
                    color: bridge.velocityPromptAppearance.buttonText
                    font: bridge.velocityPromptAppearance.font
                    text: qsTr("OK")
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

                objectName: "noteVelocityCancel"
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: cancelText.text
                function activate() {
                    prompt.cancelDisplayed()
                }
                function activateFromKeyboard(event) {
                    activate()
                    event.accepted = true
                }


                width: Math.max(cancelText.implicitWidth
                                + 2 * bridge.velocityPromptAppearance.buttonPadding,
                                velocityInput.implicitWidth)
                height: cancelText.implicitHeight
                        + 2 * bridge.velocityPromptAppearance.buttonPadding
                color: cancelTap.pressed ? bridge.velocityPromptAppearance.pressedBackground
                                         : bridge.velocityPromptAppearance.buttonBackground
                border.width: bridge.velocityPromptAppearance.borderWidth
                border.color: activeFocus ? bridge.velocityPromptAppearance.focus
                                          : bridge.velocityPromptAppearance.outline
                radius: bridge.velocityPromptAppearance.radius

                Text {
                    id: cancelText

                    anchors.centerIn: parent
                    color: bridge.velocityPromptAppearance.buttonText
                    font: bridge.velocityPromptAppearance.font
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
