pragma ComponentBehavior: Bound
import QtQuick
import Porydaw.Ui

FocusScope {
    id: root
    objectName: "automationPrompt"
    required property var model
    property var hintService: pageItem ? pageItem.hintService : null
    property var pageItem: null
    property bool showing: false
    readonly property bool confirming: model.promptKind === 1
    readonly property var promptPalette: root.pageItem ? root.pageItem.gridPalette : null
    QtObject {
        id: promptAppearance
        readonly property color background: root.promptPalette ? root.promptPalette.windowBackground : "transparent"
        readonly property color text: root.promptPalette ? root.promptPalette.windowText : "transparent"
        readonly property color outline: root.promptPalette ? root.promptPalette.outline : "transparent"
        readonly property color focus: root.promptPalette ? root.promptPalette.focusOutline : "transparent"
        readonly property real borderWidth: root.model.promptAppearance.borderWidth
        readonly property real radius: root.model.promptAppearance.radius
        readonly property real dialogPadding: root.model.promptAppearance.dialogPadding
        readonly property real spacing: root.model.promptAppearance.spacing
        readonly property real buttonPadding: root.model.promptAppearance.buttonPadding
        readonly property real horizontalPadding: root.model.promptAppearance.horizontalPadding
        readonly property real verticalPadding: root.model.promptAppearance.verticalPadding
        readonly property real dragThreshold: root.model.promptAppearance.dragThreshold
        readonly property color buttonBackground: root.promptPalette ? root.promptPalette.buttonBackground : "transparent"
        readonly property color pressedBackground: root.promptPalette ? root.promptPalette.buttonPressedBackground : "transparent"
        readonly property color buttonText: root.promptPalette ? root.promptPalette.buttonText : "transparent"
        readonly property font font: Qt.font(root.model.promptFont)
    }
    signal closed()
    anchors.fill: parent
    visible: showing
    enabled: showing
    z: 100
    property bool finishing: false
    function takeFocus() {
        if (!showing) return
        if (confirming) cancel.forceActiveFocus(Qt.PopupFocusReason)
        else { field.focusInput(Qt.PopupFocusReason); field.selectAll() }
    }
    onShowingChanged: {
        if (showing) { finishing = false; Qt.callLater(takeFocus) }
        else closed()
    }
    function acceptDraft() {
        if (finishing || (!confirming && !field.textInput.acceptableInput)) return
        finishing = true
        if (!confirming) model.updatePromptDraft(field.textInput.text)
        model.acceptPromptDraft()
    }
    function cancelDraft() {
        if (finishing) return
        finishing = true
        model.cancelPrompt()
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
        appearance: promptAppearance
        Keys.onShortcutOverride: event => event.accepted = event.key !== Qt.Key_Space
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) root.cancelDraft()
            event.accepted = true
        }
        Keys.onReleased: event => event.accepted = true
        Text {
            objectName: "automationPromptTitle"
            text: root.model.promptTitle
            color: promptAppearance.text
            font: promptAppearance.font
            renderType: Text.NativeRendering
        }
        Text {
            objectName: "automationPromptMessage"
            visible: root.confirming
            text: root.model.promptMessage
            color: promptAppearance.text
            font: promptAppearance.font
            renderType: Text.NativeRendering
        }
        Text {
            objectName: "automationPromptLabel"
            visible: !root.confirming
            text: root.model.promptLabel
            color: promptAppearance.text
            font: promptAppearance.font
            renderType: Text.NativeRendering
        }
        DragInput {
            id: field

            visible: !root.confirming
            width: root.model ? root.model.promptInputWidth : 0
            height: implicitHeight
            adjustmentsEnabled: false
            inputObjectName: "automationPromptInput"
            accessibleName: root.model.promptLabel
            appearance: Object.assign({}, promptAppearance, {
                background: promptAppearance.buttonBackground
            })
            value: Number(root.model.promptDraft)
            minimumValue: root.model.promptMinimum
            maximumValue: root.model.promptMaximum
            onValueCommitted: committed => root.model.updatePromptDraft(String(committed))
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
            function onActiveFocusChanged() {
                if (root.showing && !field.textInput.activeFocus && !root.confirming)
                    root.cancelDraft()
            }
        }
        Text {
            objectName: "automationPromptError"
            visible: root.model.promptError.length > 0
            text: root.model.promptError
            color: root.promptPalette ? root.promptPalette.errorText : "transparent"
            font: promptAppearance.font
            renderType: Text.NativeRendering
        }
        Row {
            visible: root.confirming
            spacing: promptAppearance.spacing
            PromptButton {
                id: accept
                objectName: "automationPromptAccept"
                appearance: promptAppearance
                text: root.confirming ? qsTr("Delete") : qsTr("OK")
                minimumWidth: cancel.labelWidth + 2 * promptAppearance.buttonPadding
                KeyNavigation.tab: cancel
                KeyNavigation.backtab: cancel
                onActivated: root.acceptDraft()
            }
            PromptButton {
                id: cancel
                objectName: "automationPromptCancel"
                appearance: promptAppearance
                text: qsTr("Cancel")
                minimumWidth: accept.labelWidth + 2 * promptAppearance.buttonPadding
                KeyNavigation.tab: accept
                KeyNavigation.backtab: accept
                onActivated: root.cancelDraft()
            }
        }
    }
}
