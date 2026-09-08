import QtQuick

PromptCard {
    id: prompt

    required property var bridge

    objectName: "noteVelocityPrompt"
    appearance: bridge.velocityPromptAppearance

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
    // out of the shared popup session.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape)
            cancelDisplayed()
        event.accepted = true
    }
    Keys.onReleased: (event) => event.accepted = true

    Accessible.role: Accessible.Client
    Accessible.name: bridge.velocityPromptTitle

    Text {
        color: appearance.text
        font: appearance.font
        text: bridge.velocityPromptTitle
        renderType: Text.NativeRendering
    }

    Text {
        color: appearance.text
        font: appearance.font
        text: bridge.velocityPromptLabel
        renderType: Text.NativeRendering
    }

    DragInput {
        id: velocityInput

        appearance: prompt.appearance
        value: prompt.draft
        minimumValue: bridge.velocityPromptMinimumValue
        maximumValue: bridge.velocityPromptMaximumValue
        inputObjectName: "noteVelocityInput"
        accessibleName: bridge.velocityPromptLabel
        accessibleDescription: bridge.velocityPromptTitle
        onValueCommitted: (committed) => prompt.draft = committed
        onEditingAccepted: (committed) => prompt.acceptCommitted(committed)
        textInput.KeyNavigation.tab: acceptButton
        textInput.KeyNavigation.backtab: cancelButton
    }

    Row {
        spacing: appearance.spacing

        PromptButton {
            id: acceptButton

            objectName: "noteVelocityAccept"
            appearance: prompt.appearance
            text: qsTr("OK")
            minimumWidth: velocityInput.implicitWidth
            onActivated: prompt.acceptDisplayed()
            KeyNavigation.tab: cancelButton
            KeyNavigation.backtab: velocityInput.textInput
        }

        PromptButton {
            id: cancelButton

            objectName: "noteVelocityCancel"
            appearance: prompt.appearance
            text: qsTr("Cancel")
            minimumWidth: velocityInput.implicitWidth
            KeyNavigation.tab: velocityInput.textInput
            KeyNavigation.backtab: acceptButton
            onActivated: prompt.cancelDisplayed()
        }
    }
}
