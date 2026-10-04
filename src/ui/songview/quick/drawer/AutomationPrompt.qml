pragma ComponentBehavior: Bound
import QtQuick
import Porydaw.Ui
import PorydawApp as App

FocusScope {
    id: root
    objectName: "automationPrompt"
    required final property App.AutomationPage model
    final property App.MouseHints hintService: null
    final property Item pageItem: null
    final property bool showing: false
    readonly final property bool confirming: model !== null && model.promptKind === 1
    final property App.GridPalette promptPalette: null
    readonly final property App.PromptStyle promptAppearance: root.model.promptStyle
    readonly final property App.PromptStyle inputAppearance: root.model.promptInputStyle
    signal closed()
    anchors.fill: parent
    visible: showing && model !== null
    enabled: showing && model !== null
    z: 100
    property bool finishing: false
    function takeFocus(): void {
        if (!root.showing || !root.model) return
        if (root.confirming) cancel.forceActiveFocus(Qt.PopupFocusReason)
        else { field.focusInput(Qt.PopupFocusReason); field.selectAll() }
    }
    onShowingChanged: {
        if (showing) { finishing = false; Qt.callLater(root.takeFocus) }
        else closed()
    }
    function acceptDraft(): void {
        if (!root.model || root.finishing || (!root.confirming && !field.textInput.acceptableInput)) return
        root.finishing = true
        if (!root.confirming) root.model.updatePromptDraft(field.textInput.text)
        root.model.acceptPromptDraft()
    }
    function cancelDraft(): void {
        if (!root.model || root.finishing) return
        root.finishing = true
        root.model.cancelPrompt()
    }
    MouseArea {
        objectName: "automationPromptUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: root.cancelDraft()
    }
    MouseArea {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }
    PromptCard {
        id: card
        objectName: "automationPromptCard"
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        appearance: root.promptAppearance
        Keys.onShortcutOverride: event => event.accepted = event.key !== Qt.Key_Space
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) root.cancelDraft()
            event.accepted = true
        }
        Keys.onReleased: event => event.accepted = true
        Text {
            objectName: "automationPromptTitle"
            text: root.model ? root.model.promptTitle : ""
            color: root.promptAppearance.text
            font: root.promptAppearance.font
            renderType: Text.NativeRendering
        }
        Text {
            objectName: "automationPromptMessage"
            visible: root.confirming
            text: root.model ? root.model.promptMessage : ""
            color: root.promptAppearance.text
            font: root.promptAppearance.font
            renderType: Text.NativeRendering
        }
        Text {
            objectName: "automationPromptLabel"
            visible: !root.confirming
            text: root.model ? root.model.promptLabel : ""
            color: root.promptAppearance.text
            font: root.promptAppearance.font
            renderType: Text.NativeRendering
        }
        DragInput {
            id: field

            visible: !root.confirming
            width: root.model ? root.model.promptInputWidth : 0
            height: implicitHeight
            adjustmentsEnabled: false
            inputObjectName: "automationPromptInput"
            accessibleName: root.model ? root.model.promptLabel : ""
            appearance: root.inputAppearance
            value: root.model ? +root.model.promptDraft : 0
            minimumValue: root.model ? root.model.promptMinimum : 0
            maximumValue: root.model ? root.model.promptMaximum : 0
            onValueCommitted: committed => {
                if (root.model) root.model.updatePromptDraft("" + committed)
            }
            onEditingAccepted: committed => root.acceptDraft()
            HoverHint {
                source: field.textInput
                hintService: root.hintService
                scopeAllowed: root.showing
                profile: HintProfiles.TextSelection
            }
        }
        Connections {
            target: field.textInput
            function onActiveFocusChanged(): void {
                if (root.model && root.showing && !field.textInput.activeFocus && !root.confirming)
                    root.cancelDraft()
            }
        }
        Text {
            objectName: "automationPromptError"
            visible: root.model !== null && root.model.promptError.length > 0
            text: root.model ? root.model.promptError : ""
            color: root.promptPalette ? root.promptPalette.errorText : "transparent"
            font: root.promptAppearance.font
            renderType: Text.NativeRendering
        }
        Row {
            visible: root.confirming
            spacing: root.promptAppearance.spacing
            PromptButton {
                id: accept
                objectName: "automationPromptAccept"
                appearance: root.promptAppearance
                text: root.confirming ? qsTr("Delete") : qsTr("OK")
                minimumWidth: cancel.labelWidth + 2 * root.promptAppearance.buttonPadding
                KeyNavigation.tab: cancel
                KeyNavigation.backtab: cancel
                onActivated: root.acceptDraft()
            }
            PromptButton {
                id: cancel
                objectName: "automationPromptCancel"
                appearance: root.promptAppearance
                text: qsTr("Cancel")
                minimumWidth: accept.labelWidth + 2 * root.promptAppearance.buttonPadding
                KeyNavigation.tab: accept
                KeyNavigation.backtab: accept
                onActivated: root.cancelDraft()
            }
        }
    }
}
