// The Set Velocity prompt: a drawer-local modal value form, owned by the page's
// Swift model and carrying no legacy popup session, popup layer or Porydaw.Ui
// import.
//
// The model owns the transaction (captured targets, before-values, revision and
// validation). This file is the form: a text field, an accept and a cancel
// action, an underlay that dismisses, and the keyboard contract - Enter accepts,
// Escape cancels, Tab cycles input -> accept -> cancel -> input, and the field
// claims Space while it is focused so typing a draft never reaches the window
// transport.
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: prompt

    objectName: "velocityPrompt"

    /// The page's Swift model. A `QtObject`-typed property cannot hold the
    /// bridged Swift object the container's Loader injects, so the prompt reads it
    /// as the variant the rest of the composition uses for bridged owners.
    required property var model

    /// Emitted when the prompt really closed, so the page can return focus to the
    /// surface the interaction started on. `restoreFocus` is false for a
    /// replacement or a cancellation that is already moving focus itself.
    signal closed(bool restoreFocus)

    /// The model arrives through the page's own binding, which QML evaluates
    /// during construction; every read below is null-safe so a construction-order
    /// gap publishes nothing instead of a binding error.
    readonly property bool ready: prompt.model !== null && prompt.model !== undefined
    readonly property bool opened: prompt.ready && prompt.model.promptOpen
    readonly property string title: prompt.ready ? prompt.model.promptTitle : ""
    readonly property string fieldLabel: prompt.ready ? prompt.model.promptLabel : ""
    readonly property string draft: prompt.ready ? prompt.model.promptDraft : ""
    readonly property string error: prompt.ready ? prompt.model.promptError : ""
    readonly property int minimum: prompt.ready ? prompt.model.promptMinimum : 1
    readonly property int maximum: prompt.ready ? prompt.model.promptMaximum : 127

    visible: prompt.opened
    enabled: prompt.opened
    // The text field owns the active focus, taken when this item really becomes
    // visible; a scope-level `focus` here would re-target it in the same pass.
    z: 100

    onVisibleChanged: {
        if (prompt.visible && prompt.opened)
            prompt.scheduleFocus()
    }
    onOpenedChanged: {
        if (prompt.opened)
            prompt.scheduleFocus()
        else if (prompt.visible)
            prompt.closed(true)
    }

    /// The field takes active focus on the pass after the item is really shown:
    /// a `forceActiveFocus` in the same pass as the visibility change lands on an
    /// item the scene graph has not shown yet. The deferred call re-checks the
    /// prompt's own state, so a page destroyed with its prompt open leaves nothing
    /// that touches a dead item.
    function scheduleFocus() {
        Qt.callLater(prompt.takeFocus)
    }

    function takeFocus() {
        if (!prompt.opened || !prompt.visible || !prompt.ready)
            return
        field.forceActiveFocus(Qt.PopupFocusReason)
        field.selectAll()
    }


    // The underlay: an outside press dismisses without committing, and swallows
    // the release so no pointer action lands on the page behind it.
    MouseArea {
        objectName: "velocityPromptUnderlay"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: (mouse) => {
            prompt.cancelDraft()
            mouse.accepted = true
        }
    }

    Rectangle {
        id: card

        objectName: "velocityPromptCard"
        anchors.centerIn: parent
        width: Math.max(220, field.implicitWidth + 32)
        height: column.implicitHeight + 24
        radius: 4
        color: "#F0F0F0"
        border.width: 1
        border.color: "#8C857F"

        Column {
            id: column

            anchors.centerIn: parent
            spacing: 8

            Text {
                objectName: "velocityPromptTitle"
                text: prompt.title
                color: "#302C29"
                font.bold: true
                textFormat: Text.PlainText
            }

            Text {
                objectName: "velocityPromptLabel"
                text: prompt.fieldLabel
                color: "#302C29"
                textFormat: Text.PlainText
            }

            TextInput {
                id: field

                objectName: "noteVelocityInput"
                width: 120
                // The model owns the draft: the field shows what the model
                // published and reports edits back, so a replaced or cancelled
                // prompt can never leave a stale value behind.
                text: prompt.draft
                color: "#302C29"
                font.pixelSize: 14
                horizontalAlignment: TextInput.AlignHCenter
                inputMethodHints: Qt.ImhDigitsOnly
                validator: IntValidator { bottom: prompt.minimum
                                          top: prompt.maximum }
                activeFocusOnTab: true

                onTextEdited: if (prompt.ready) prompt.model.updatePromptDraft(text)

                // The field's own keys, claimed before the window shortcuts so
                // Space and Return never leak to the transport while it is live.
                Keys.onShortcutOverride: (event) => {
                    if (event.key === Qt.Key_Space || event.key === Qt.Key_Return
                            || event.key === Qt.Key_Enter)
                        event.accepted = true
                }
                Keys.onReturnPressed: (event) => {
                    event.accepted = true
                    prompt.acceptDraft()
                }
                Keys.onEnterPressed: (event) => {
                    event.accepted = true
                    prompt.acceptDraft()
                }
                Keys.onEscapePressed: (event) => {
                    event.accepted = true
                    prompt.cancelDraft()
                }
                Accessible.role: Accessible.EditableText
                Accessible.name: qsTr("Velocity value")
                Accessible.description: prompt.error.length > 0
                                        ? prompt.error
                                        : qsTr("Enter a velocity from 1 to 127")

            }

            Text {
                objectName: "velocityPromptError"
                visible: prompt.error.length > 0
                width: 180
                text: prompt.error
                color: "#B00000"
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
            }

            Row {
                spacing: 8

                Rectangle {
                    id: accept

                    objectName: "noteVelocityAccept"
                    width: 72
                    height: 24
                    radius: 3
                    color: prompt.error.length > 0 ? "#D0C8C2" : "#B9E8EE"
                    border.width: 1
                    border.color: "#8C857F"
                    activeFocusOnTab: true

                    function activate() { prompt.acceptDraft() }

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("OK")
                        color: "#302C29"
                        textFormat: Text.PlainText
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
                        prompt.cancelDraft()
                    }
                    Keys.onShortcutOverride: (event) => event.accepted =
                        event.key === Qt.Key_Return || event.key === Qt.Key_Enter

                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Accept velocity")
                    Accessible.focusable: true
                    Accessible.onPressAction: accept.activate()

                    MouseArea {
                        anchors.fill: parent
                        onClicked: accept.activate()
                    }
                }

                Rectangle {
                    id: cancel

                    objectName: "noteVelocityCancel"
                    width: 72
                    height: 24
                    radius: 3
                    color: "#E7E1DB"
                    border.width: 1
                    border.color: "#8C857F"
                    activeFocusOnTab: true

                    function activate() { prompt.cancelDraft() }

                    Text {
                        anchors.centerIn: parent
                        text: qsTr("Cancel")
                        color: "#302C29"
                        textFormat: Text.PlainText
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
                        prompt.cancelDraft()
                    }
                    Keys.onShortcutOverride: (event) => event.accepted =
                        event.key === Qt.Key_Return || event.key === Qt.Key_Enter

                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Cancel velocity")
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

    /// One acceptance through the model's transaction. An invalid draft stays
    /// open with its error published and no document write.
    function acceptDraft() {
        if (prompt.ready)
            prompt.model.acceptPrompt()
    }

    function cancelDraft() {
        if (prompt.ready)
            prompt.model.cancelPrompt()
    }
}
