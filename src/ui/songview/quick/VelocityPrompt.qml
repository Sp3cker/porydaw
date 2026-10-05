pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp as App

PromptOverlay {
    id: promptRoot
    objectName: "velocityPrompt"
    required final property App.VelocityPage model
    final property App.MouseHints hintService: null
    property bool hintScopeAllowed: true
    readonly property bool opened: model.promptOpen
    overlayOpen: opened
    cardItem: prompt
    underlayObjectName: "velocityPromptUnderlay"
    required focusOrigin
    dismissOnlyOutsideCard: true
    consumeDismissPress: true
    preventUnderlayStealing: true
    z: 100
    onInitialFocusRequested: prompt.activateInitialFocus()
    onOverlayClosed: restoreFocusIfOwned()
    onDismissRequested: prompt.cancelDisplayed()

    PromptCard {
        id: prompt
        visible: promptRoot.opened

        objectName: "velocityPromptCard"
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        appearance: promptRoot.model.promptStyle

        readonly property int draft: +promptRoot.model.promptDraft

        function acceptDisplayed(): void {
            const committed = velocityInput.commitDisplayed()
            if (committed !== null)
                acceptCommitted(committed)
        }

        function acceptCommitted(committed: int): void {
            if (!promptRoot.opened)
                return
            promptRoot.model.updatePromptDraft("" + committed)
            promptRoot.restoreFocusIfOwned()
            promptRoot.model.acceptPrompt()
        }

        function cancelDisplayed(): void {
            if (!promptRoot.opened)
                return
            promptRoot.restoreFocusIfOwned()
            promptRoot.model.cancelPrompt()
        }
        function activateInitialFocus(): void {
            velocityInput.focusInput(Qt.PopupFocusReason)
            velocityInput.selectAll()
        }
        Keys.onShortcutOverride: event => event.accepted = event.key !== Qt.Key_Space

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
            onValueCommitted: committed => promptRoot.model.updatePromptDraft("" + committed)
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
