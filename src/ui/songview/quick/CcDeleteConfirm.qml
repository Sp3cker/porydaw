import QtQuick

PromptCard {
    id: prompt

    required property var bridge

    objectName: "ccDeleteConfirm"
    appearance: bridge.ccDeletePromptAppearance

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

    Text {
        color: appearance.text
        font: appearance.font
        text: bridge.ccDeletePromptTitle
        renderType: Text.NativeRendering
    }

    Text {
        color: appearance.text
        font: appearance.font
        text: bridge.ccDeletePromptMessage
        renderType: Text.NativeRendering
    }

    Row {
        spacing: appearance.spacing

        PromptButton {
            id: acceptButton

            objectName: "acceptButton"
            appearance: prompt.appearance
            text: qsTr("Delete")
            minimumWidth: cancelButton.labelWidth + 2 * appearance.buttonPadding
            KeyNavigation.tab: cancelButton
            KeyNavigation.backtab: cancelButton
            onActivated: prompt.acceptDisplayed()
        }

        PromptButton {
            id: cancelButton

            objectName: "cancelButton"
            appearance: prompt.appearance
            text: qsTr("Cancel")
            minimumWidth: acceptButton.labelWidth + 2 * appearance.buttonPadding
            KeyNavigation.tab: acceptButton
            KeyNavigation.backtab: acceptButton
            onActivated: prompt.cancelDisplayed()
        }
    }
}
