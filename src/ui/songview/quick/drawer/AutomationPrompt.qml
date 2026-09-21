// The Automation prompter: the page's captured value form and its captured
// lane-delete confirmation.
//
// The page owns every captured fact (revision, track, parameter, point or range
// identity, before-value, the confirmation's written-event count, the validation
// domain and the draft). This file renders that captured state and delivers real
// pointer, keyboard and accessibility input back to the owner; it reads no
// document, re-resolves no target and holds no rule of its own.
//
// Cancellation: an outside press, Escape, a section hide, a window deactivation,
// a document/track/parameter replacement and a scene retirement all end the form
// without a write — a stale capture commits nothing and restores focus.
//
// Bare Space is claimed only by the value form's own text field, which is the
// explicit text-entry surface this modal keeps; every other control claims plain
// Return/Enter alone, so the window transport keeps bare Space.
pragma ComponentBehavior: Bound

import QtQuick

FocusScope {
    id: promptRoot

    objectName: "automationPrompt"

    /// The page's published model for the current document. A `QtObject`-typed
    /// property cannot hold the bridged Swift object, so the page hands it over
    /// as the variant the rest of the composition uses for bridged owners.
    required property var model
    /// The page whose coordinate space the published anchor is stated in. The
    /// prompt is composed into the container's modal layer, so the card is
    /// centred in whatever surface hosts this prompt.
    property var pageItem: null

    signal closed()

    /// The page's own publication decides modality: this file renders the open
    /// form and delivers the input that drives it. The flag is read through a
    /// `var`-typed bridge object, whose nested properties a binding does not
    /// track across this component boundary, so the form follows the page's own
    /// change signal.
    property bool showing: false

    readonly property bool ready: promptRoot.model !== null && promptRoot.model !== undefined
    readonly property int kind: promptRoot.ready ? promptRoot.model.promptKind : 0
    readonly property bool confirming: promptRoot.kind === 1
    readonly property string title: promptRoot.ready ? promptRoot.model.promptTitle : ""
    readonly property string fieldLabel: promptRoot.ready ? promptRoot.model.promptLabel : ""
    readonly property string message: promptRoot.ready ? promptRoot.model.promptMessage : ""
    readonly property string draft: promptRoot.ready ? promptRoot.model.promptDraft : ""
    readonly property string error: promptRoot.ready ? promptRoot.model.promptError : ""
    readonly property int minimum: promptRoot.ready ? promptRoot.model.promptMinimum : 0
    readonly property int maximum: promptRoot.ready ? promptRoot.model.promptMaximum : 0
    readonly property real baseFontPx: promptRoot.ready && promptRoot.model.baseFontPx > 0
                                       ? promptRoot.model.baseFontPx : 13
    readonly property real padding: Math.max(1, Math.round(promptRoot.baseFontPx / 2))
    readonly property real buttonHeight: Math.max(1, Math.round(promptRoot.baseFontPx * 1.8))

    anchors.fill: parent
    visible: showing
    enabled: showing
    z: 100

    onShowingChanged: {
        if (showing) {
            promptRoot.scheduleFocus()
        } else {
            promptRoot.closed()
        }
    }

    /// The field takes active focus on the pass after the item is really shown: a
    /// `forceActiveFocus` in the same pass as the visibility change lands on an
    /// item the scene graph has not shown yet. The deferred call re-checks the
    /// form's own state, so a page destroyed with its prompt open leaves nothing
    /// that touches a dead item.
    function scheduleFocus() {
        Qt.callLater(promptRoot.takeFocus)
    }

    function takeFocus() {
        if (!promptRoot.visible || !promptRoot.ready)
            return
        if (promptRoot.confirming)
            accept.forceActiveFocus(Qt.PopupFocusReason)
        else if (field.visible)
            field.forceActiveFocus(Qt.PopupFocusReason)
    }

    function acceptDraft() {
        if (promptRoot.ready)
            promptRoot.model.acceptPromptDraft()
    }

    function cancelDraft() {
        if (promptRoot.ready)
            promptRoot.model.cancelPrompt()
    }

    // The underlay: an outside press dismisses without committing, and swallows
    // the release so no pointer action lands on the page behind it.
    MouseArea {
        objectName: "automationPromptUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onPressed: (mouse) => {
            promptRoot.cancelDraft()
            mouse.accepted = true
        }
    }

    Rectangle {
        id: card

        objectName: "automationPromptCard"
        anchors.centerIn: parent
        width: Math.max(Math.round(promptRoot.baseFontPx * 18),
                        promptRoot.confirming
                        ? messageText.implicitWidth + 2 * promptRoot.padding
                        : field.implicitWidth + 2 * promptRoot.padding)
        height: column.implicitHeight + 2 * promptRoot.padding
        radius: 4
        color: "#F0F0F0"
        border.width: 1
        border.color: "#8C857F"
        focus: true

        Keys.onEscapePressed: (event) => {
            event.accepted = true
            promptRoot.cancelDraft()
        }

        Column {
            id: column

            anchors.centerIn: parent
            spacing: promptRoot.padding

            Text {
                objectName: "automationPromptTitle"
                text: promptRoot.title
                color: "#302C29"
                font.pixelSize: Math.max(1, Math.round(promptRoot.baseFontPx))
                font.bold: true
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
            }

            Text {
                objectName: "automationPromptLabel"
                visible: !promptRoot.confirming
                text: promptRoot.fieldLabel
                color: "#302C29"
                font.pixelSize: Math.max(1, Math.round(promptRoot.baseFontPx))
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
            }

            Text {
                id: messageText

                objectName: "automationPromptMessage"
                visible: promptRoot.confirming
                width: Math.min(implicitWidth, Math.round(promptRoot.baseFontPx * 26))
                text: promptRoot.message
                color: "#302C29"
                font.pixelSize: Math.max(1, Math.round(promptRoot.baseFontPx))
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
            }

            TextInput {
                id: field

                objectName: "automationPromptInput"
                visible: !promptRoot.confirming
                width: Math.max(Math.round(promptRoot.baseFontPx * 8), implicitWidth)
                // The model owns the draft: the field shows what the model
                // published and reports edits back, so a replaced or cancelled
                // prompt can never leave a stale value behind.
                text: promptRoot.draft
                color: "#302C29"
                font.pixelSize: Math.max(1, Math.round(promptRoot.baseFontPx))
                horizontalAlignment: TextInput.AlignHCenter
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: promptRoot.minimum
                                          top: promptRoot.maximum }
                activeFocusOnTab: true

                onTextEdited: if (promptRoot.ready)
                                  promptRoot.model.updatePromptDraft(text)

                // The field's own keys, claimed before the window shortcuts so
                // Space and Return never leak to the transport while it is live.
                Keys.onShortcutOverride: (event) => {
                    if (event.key === Qt.Key_Space || event.key === Qt.Key_Return
                            || event.key === Qt.Key_Enter)
                        event.accepted = true
                }
                Keys.onReturnPressed: (event) => {
                    event.accepted = true
                    promptRoot.acceptDraft()
                }
                Keys.onEnterPressed: (event) => {
                    event.accepted = true
                    promptRoot.acceptDraft()
                }
                Keys.onEscapePressed: (event) => {
                    event.accepted = true
                    promptRoot.cancelDraft()
                }
                Accessible.role: Accessible.EditableText
                Accessible.name: promptRoot.title
                Accessible.description: promptRoot.error.length > 0
                                        ? promptRoot.error : promptRoot.fieldLabel
            }

            Text {
                objectName: "automationPromptError"
                visible: promptRoot.error.length > 0
                width: Math.round(promptRoot.baseFontPx * 14)
                text: promptRoot.error
                color: "#B00000"
                font.pixelSize: Math.max(1, Math.round(promptRoot.baseFontPx))
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
            }

            Row {
                spacing: promptRoot.padding

                Rectangle {
                    id: accept

                    objectName: "automationPromptAccept"
                    width: Math.round(promptRoot.baseFontPx * 6)
                    height: promptRoot.buttonHeight
                    radius: 3
                    color: promptRoot.error.length > 0 ? "#D0C8C2" : "#B9E8EE"
                    border.width: 1
                    border.color: "#8C857F"
                    activeFocusOnTab: true

                    function activate() { promptRoot.acceptDraft() }

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("OK")
                        color: "#302C29"
                        font.pixelSize: Math.max(1, Math.round(promptRoot.baseFontPx))
                        textFormat: Text.PlainText
                        renderType: Text.NativeRendering
                    }

                    Keys.onReturnPressed: (event) => {
                        event.accepted = true
                        accept.activate()
                    }
                    Keys.onEnterPressed: (event) => {
                        event.accepted = true
                        accept.activate()
                    }
                    Keys.onEscapePressed: (event) => {
                        event.accepted = true
                        promptRoot.cancelDraft()
                    }
                    Keys.onShortcutOverride: (event) => event.accepted =
                        event.key === Qt.Key_Return || event.key === Qt.Key_Enter

                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Accept")
                    Accessible.focusable: true
                    Accessible.onPressAction: accept.activate()

                    MouseArea {
                        anchors.fill: parent
                        onClicked: accept.activate()
                    }
                }

                Rectangle {
                    id: cancel

                    objectName: "automationPromptCancel"
                    width: Math.round(promptRoot.baseFontPx * 6)
                    height: promptRoot.buttonHeight
                    radius: 3
                    color: "#E7E1DB"
                    border.width: 1
                    border.color: "#8C857F"
                    activeFocusOnTab: true

                    function activate() { promptRoot.cancelDraft() }

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Cancel")
                        color: "#302C29"
                        font.pixelSize: Math.max(1, Math.round(promptRoot.baseFontPx))
                        textFormat: Text.PlainText
                        renderType: Text.NativeRendering
                    }

                    Keys.onReturnPressed: (event) => {
                        event.accepted = true
                        cancel.activate()
                    }
                    Keys.onEnterPressed: (event) => {
                        event.accepted = true
                        cancel.activate()
                    }
                    Keys.onEscapePressed: (event) => {
                        event.accepted = true
                        promptRoot.cancelDraft()
                    }
                    Keys.onShortcutOverride: (event) => event.accepted =
                        event.key === Qt.Key_Return || event.key === Qt.Key_Enter

                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Cancel")
                    Accessible.focusable: true
                    Accessible.onPressAction: cancel.activate()

                    MouseArea {
                        anchors.fill: parent
                        onClicked: cancel.activate()
                    }
                }
            }
        }
    }
}
