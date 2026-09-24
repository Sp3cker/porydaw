pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: promptRoot
    objectName: "velocityPrompt"
    required property var model
    required property var promptPalette
    property var hintService: null
    property bool hintScopeAllowed: true
    signal closed(bool restoreFocus)
    readonly property bool opened: model.promptOpen
    property bool consumingOutsidePress: false
    visible: opened || consumingOutsidePress
    enabled: visible
    function finishOutsidePress() {
        consumingOutsidePress = false
    }
    z: 100
    onOpenedChanged: {
        if (opened)
            Qt.callLater(prompt.activateInitialFocus)
        else
            closed(true)
    }
    MouseArea {
        objectName: "velocityPromptUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        preventStealing: true
        onPressed: mouse => {
            // Keep the modal underlay alive through the matching release.
            // Otherwise closing on press exposes the roll to a right release
            // that can clear selection or start another interaction.
            mouse.accepted = true
            if (mouse.x < prompt.x || mouse.x >= prompt.x + prompt.width
                    || mouse.y < prompt.y || mouse.y >= prompt.y + prompt.height) {
                promptRoot.consumingOutsidePress = true
                prompt.cancelDisplayed()
            }
        }
        onReleased: Qt.callLater(promptRoot.finishOutsidePress)
        onCanceled: Qt.callLater(promptRoot.finishOutsidePress)
    }

    PromptCard {
        id: prompt
        visible: promptRoot.opened

        objectName: "velocityPromptCard"
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        appearance: Object.assign({}, promptRoot.model.promptAppearance, {
            font: Qt.font(promptRoot.model.promptFont),
            background: promptRoot.promptPalette.windowBackground,
            outline: promptRoot.promptPalette.outline, text: promptRoot.promptPalette.windowText,
            focus: promptRoot.promptPalette.focusOutline,
            buttonBackground: promptRoot.promptPalette.buttonBackground,
            buttonText: promptRoot.promptPalette.buttonText,
            pressedBackground: promptRoot.promptPalette.buttonPressedBackground,
            pressedText: promptRoot.promptPalette.buttonPressedText
        })

        readonly property int draft: Number(promptRoot.model.promptDraft)

        function acceptDisplayed() {
            const committed = velocityInput.commitDisplayed()
            if (committed !== null)
                acceptCommitted(committed)
        }

        function acceptCommitted(committed) {
            if (!promptRoot.opened)
                return
            promptRoot.model.updatePromptDraft(String(committed))
            promptRoot.model.acceptPrompt()
        }

        function cancelDisplayed() {
            if (!promptRoot.opened)
                return
            promptRoot.model.cancelPrompt()
        }
        function activateInitialFocus() {
            velocityInput.focusInput(Qt.PopupFocusReason)
            velocityInput.selectAll()
        }
        Component.onCompleted: if (promptRoot.opened) Qt.callLater(activateInitialFocus)
        Keys.onShortcutOverride: event => event.accepted = event.key !== Qt.Key_Space

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
        Accessible.name: promptRoot.model.promptTitle

        Text {
            objectName: "velocityPromptTitle"
            color: prompt.appearance.text
            font: prompt.appearance.font
            text: promptRoot.model.promptTitle
            renderType: Text.NativeRendering
        }

        Text {
            objectName: "velocityPromptLabel"
            color: prompt.appearance.text
            font: prompt.appearance.font
            text: promptRoot.model.promptLabel
            renderType: Text.NativeRendering
        }

        DragInput {
            id: velocityInput

            hintService: promptRoot.hintService
            hintScopeAllowed: promptRoot.hintScopeAllowed
            appearance: prompt.appearance
            value: prompt.draft
            minimumValue: promptRoot.model.promptMinimum
            maximumValue: promptRoot.model.promptMaximum
            inputObjectName: "noteVelocityInput"
            accessibleName: promptRoot.model.promptLabel
            accessibleDescription: promptRoot.model.promptTitle
            onValueCommitted: committed => promptRoot.model.updatePromptDraft(String(committed))
            onEditingAccepted: (committed) => prompt.acceptCommitted(committed)
            textInput.KeyNavigation.tab: acceptButton
            textInput.KeyNavigation.backtab: cancelButton
        }

        Row {
            spacing: prompt.appearance.spacing

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
}
