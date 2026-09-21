pragma ComponentBehavior: Bound

import QtQuick
import ".." as Shared

Item {
    id: prompt

    objectName: "velocityPrompt"
    required property var model
    property var hintService: null
    property bool hintScopeAllowed: true
    signal closed(bool restoreFocus)

    readonly property bool opened: model !== null && model !== undefined && model.promptOpen
    visible: opened
    enabled: opened
    z: 100

    readonly property QtObject appearance: QtObject {
        id: promptAppearance

        readonly property color background: "#F0F0F0"
        readonly property color outline: "#8C857F"
        readonly property color text: "#302C29"
        readonly property color focus: "#B9E8EE"
        readonly property color buttonBackground: "#E7E1DB"
        readonly property color buttonText: "#302C29"
        readonly property color pressedBackground: "#B9E8EE"
        readonly property real borderWidth: 1
        readonly property real radius: 4
        readonly property real dialogPadding: 12
        readonly property real spacing: 8
        readonly property real horizontalPadding: 8
        readonly property real verticalPadding: 4
        readonly property real buttonPadding: 4
        readonly property real dragThreshold: 10
        readonly property font font: Qt.font({ pixelSize: 14 })
    }

    onOpenedChanged: {
        if (opened)
            Qt.callLater(takeFocus)
        else
            closed(true)
    }
    onVisibleChanged: if (visible) Qt.callLater(takeFocus)

    function takeFocus() {
        if (!opened || !visible)
            return
        velocityInput.focusInput(Qt.PopupFocusReason)
        velocityInput.selectAll()
    }
    function acceptDisplayed() {
        const committed = velocityInput.commitDisplayed()
        if (committed !== null)
            acceptCommitted(committed)
    }
    function acceptCommitted(committed) {
        if (!opened)
            return
        model.updatePromptDraft(String(committed))
        model.acceptPrompt()
    }
    function cancelDisplayed() {
        if (opened)
            model.cancelPrompt()
    }

    MouseArea {
        objectName: "velocityPromptUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: (mouse) => {
            if (mouse.x < card.x || mouse.x >= card.x + card.width
                    || mouse.y < card.y || mouse.y >= card.y + card.height)
                prompt.cancelDisplayed()
            mouse.accepted = true
        }
    }

    Shared.PromptCard {
        id: card

        objectName: "velocityPromptCard"
        anchors.centerIn: parent
        appearance: promptAppearance

        Keys.onShortcutOverride: (event) => event.accepted = true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape)
                prompt.cancelDisplayed()
            event.accepted = true
        }
        Keys.onReleased: (event) => event.accepted = true

        Accessible.role: Accessible.Client
        Accessible.name: prompt.opened ? prompt.model.promptTitle : ""

        Text {
            objectName: "velocityPromptTitle"
            color: promptAppearance.text
            font: promptAppearance.font
            text: prompt.opened ? prompt.model.promptTitle : ""
            renderType: Text.NativeRendering
        }
        Text {
            objectName: "velocityPromptLabel"
            color: promptAppearance.text
            font: promptAppearance.font
            text: prompt.opened ? prompt.model.promptLabel : ""
            renderType: Text.NativeRendering
        }
        Shared.DragInput {
            id: velocityInput

            hintService: prompt.hintService
            hintScopeAllowed: prompt.hintScopeAllowed
            appearance: promptAppearance
            value: prompt.opened ? Number(prompt.model.promptDraft) : 1
            minimumValue: prompt.opened ? prompt.model.promptMinimum : 1
            maximumValue: prompt.opened ? prompt.model.promptMaximum : 127
            inputObjectName: "noteVelocityInput"
            accessibleName: prompt.opened ? prompt.model.promptLabel : ""
            accessibleDescription: prompt.opened ? prompt.model.promptTitle : ""
            onValueCommitted: (committed) => {
                if (prompt.opened)
                    prompt.model.updatePromptDraft(String(committed))
            }
            onEditingAccepted: (committed) => prompt.acceptCommitted(committed)
            textInput.KeyNavigation.tab: acceptButton
            textInput.KeyNavigation.backtab: cancelButton
        }
        Row {
            spacing: promptAppearance.spacing

            Shared.PromptButton {
                id: acceptButton

                objectName: "noteVelocityAccept"
                appearance: promptAppearance
                text: qsTr("OK")
                minimumWidth: velocityInput.implicitWidth
                onActivated: prompt.acceptDisplayed()
                KeyNavigation.tab: cancelButton
                KeyNavigation.backtab: velocityInput.textInput
            }
            Shared.PromptButton {
                id: cancelButton

                objectName: "noteVelocityCancel"
                appearance: promptAppearance
                text: qsTr("Cancel")
                minimumWidth: velocityInput.implicitWidth
                onActivated: prompt.cancelDisplayed()
                KeyNavigation.tab: velocityInput.textInput
                KeyNavigation.backtab: acceptButton
            }
        }
    }
}
