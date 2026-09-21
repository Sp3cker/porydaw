pragma ComponentBehavior: Bound
import QtQuick
import ".." as Shared

FocusScope {
    id: root
    objectName: "automationPrompt"
    required property var model
    property var hintService: pageItem ? pageItem.hintService : null
    property var pageItem: null
    property bool showing: false
    readonly property bool confirming: model.promptKind === 1
    readonly property real baseFontPx: model.baseFontPx
    QtObject {
        id: promptAppearance
        readonly property color background: "#F0F0F0"
        readonly property color text: "#302C29"
        readonly property color outline: "#8C857F"
        readonly property color focus: "#4477AA"
        readonly property real borderWidth: 1
        readonly property real radius: 4
        readonly property real dialogPadding: root.baseFontPx / 2
        readonly property real spacing: root.baseFontPx / 3
        readonly property real buttonPadding: root.baseFontPx / 3
        readonly property color buttonBackground: "#E7E1DB"
        readonly property color pressedBackground: "#D0C8C0"
        readonly property color buttonText: "#302C29"
        readonly property font font: Qt.font(root.model.captionFont)
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
        else { field.forceActiveFocus(Qt.PopupFocusReason); field.selectAll() }
    }
    onShowingChanged: {
        if (showing) { finishing = false; Qt.callLater(takeFocus) }
        else closed()
    }
    function acceptDraft() {
        console.log("AUTOMATION_PROMPT_ACCEPT", showing, confirming, finishing,
                    activeFocus, field.activeFocus, cancel.activeFocus, model.promptKind,
                    field.acceptableInput, field.text)
        if (finishing || (!confirming && !field.acceptableInput)) return
        finishing = true
        if (!confirming) model.updatePromptDraft(field.text)
        model.acceptPromptDraft()
        console.log("AUTOMATION_PROMPT_ACCEPT_RESULT", model.promptOpen, model.promptError)
    }
    function cancelDraft() {
        console.log("AUTOMATION_PROMPT_CANCEL", showing, confirming, finishing,
                    activeFocus, field.activeFocus, cancel.activeFocus, model.promptKind)
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
        onPressed: mouse => console.log("AUTOMATION_PROMPT_SHIELD_PRESS", mouse.x, mouse.y,
                                       root.model.promptTitle, root.model.promptMessage,
                                       titleText.text, titleText.height, titleText.font.pixelSize,
                                       messageText.text, messageText.height, messageText.font.pixelSize)
        onReleased: mouse => console.log("AUTOMATION_PROMPT_SHIELD_RELEASE", mouse.x, mouse.y)
        onWheel: wheel => wheel.accepted = true
    }
    Shared.PromptCard {
        id: card
        objectName: "automationPromptCard"
        // Popup content is above the outside-click filter and its card shield.
        z: 1
        anchors.centerIn: parent
        width: implicitWidth
        height: implicitHeight
        appearance: promptAppearance
        minimumWidth: root.baseFontPx * 18
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) root.cancelDraft()
            event.accepted = true
        }
        Keys.onReleased: event => event.accepted = true
        Text {
            id: titleText
            objectName: "automationPromptTitle"
            text: root.model.promptTitle
            color: promptAppearance.text
            font: promptAppearance.font
            renderType: Text.NativeRendering
        }
        Text {
            id: messageText
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
        Rectangle {
            visible: !root.confirming
            width: root.baseFontPx * 16
            height: root.baseFontPx * 2
            color: promptAppearance.buttonBackground
            border.width: 1
            border.color: field.activeFocus ? promptAppearance.focus : promptAppearance.outline
            TextInput {
                id: field
                objectName: "automationPromptInput"
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                text: root.model.promptDraft
                color: promptAppearance.text
                font: promptAppearance.font
                clip: true
                selectByMouse: true
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                validator: IntValidator {
                    bottom: root.model.promptMinimum
                    top: root.model.promptMaximum
                }
                onActiveFocusChanged: if (root.showing && !activeFocus && !root.confirming)
                    root.cancelDraft()
                Keys.onReturnPressed: event => { root.acceptDraft(); event.accepted = true }
                Keys.onEnterPressed: event => { root.acceptDraft(); event.accepted = true }
                Keys.onEscapePressed: event => { root.cancelDraft(); event.accepted = true }
                Keys.onShortcutOverride: event => event.accepted = true
                Accessible.role: Accessible.EditableText
                Accessible.name: root.model.promptLabel
                Accessible.focusable: true
            }
            Shared.HoverHint {
                source: field
                hintService: root.hintService
                scopeAllowed: root.showing
                profile: Shared.HintProfiles.TextSelection
            }
        }
        Text {
            objectName: "automationPromptError"
            visible: root.model.promptError.length > 0
            text: root.model.promptError
            color: "#B00000"
            font: promptAppearance.font
            renderType: Text.NativeRendering
        }
        Row {
            visible: root.confirming
            spacing: promptAppearance.spacing
            Shared.PromptButton {
                id: accept
                objectName: "automationPromptAccept"
                appearance: promptAppearance
                text: root.confirming ? qsTr("Delete") : qsTr("OK")
                minimumWidth: cancel.labelWidth + 2 * promptAppearance.buttonPadding
                KeyNavigation.tab: cancel
                KeyNavigation.backtab: cancel
                onActivated: {
                    console.log("AUTOMATION_PROMPT_BUTTON", activeFocus, width, height)
                    root.acceptDraft()
                }
            }
            Shared.PromptButton {
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
