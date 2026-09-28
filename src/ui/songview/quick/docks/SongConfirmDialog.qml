import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import Porydaw.Ui

Basic.Dialog {
    id: dialog
    objectName: "songConfirmationDialog"
    required property var controller
    required property real baseFontPx
    required property var layoutSpaces
    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    width: Math.min(parent.width - 2 * baseFontPx, 30 * baseFontPx)
    title: controller.confirmation === "create" ? qsTr("New Song")
        : controller.confirmation === "register" ? qsTr("Register Song") : qsTr("Delete Song")
    standardButtons: Dialog.Ok | Dialog.Cancel
    onAccepted: controller.acceptConfirmation(alsoVoicegroup.checked)
    onOpened: {
        if (controller.confirmation === "create")
            nameField.forceActiveFocus()
    }
    onClosed: {
        if (controller.confirmation.length > 0)
            controller.cancelConfirmation()
    }
    onRejected: controller.cancelConfirmation()
    Component.onCompleted: {
        const ok = dialog.footer.standardButton(Dialog.Ok)
        if (ok) {
            ok.text = Qt.binding(function() {
                return controller.confirmation === "create" ? qsTr("Create")
                    : controller.confirmation === "register" ? qsTr("Register") : qsTr("Delete")
            })
            ok.enabled = Qt.binding(function() {
                return controller.confirmation !== "create"
                    || controller.validNewSongLabel(nameField.text)
            })
        }
    }
    contentItem: ColumnLayout {
        spacing: dialog.layoutSpaces.four
        Label {
            objectName: "songConfirmationPrompt"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: dialog.controller.confirmation === "create"
                ? qsTr("Create a song from the current song:")
                : dialog.controller.confirmation === "register"
                    ? qsTr("Register %1 as %2?").arg(dialog.controller.confirmationLabel)
                        .arg(dialog.controller.registrationConstant)
                    : qsTr("Delete %1?").arg(dialog.controller.confirmationLabel)
        }
        TextField {
            id: nameField
            objectName: "songNewName"
            Layout.fillWidth: true
            visible: dialog.controller.confirmation === "create"
            placeholderText: qsTr("mus_new_song")
            onTextChanged: dialog.controller.newSongLabel = text
            onAccepted: {
                if (dialog.footer.standardButton(Dialog.Ok).enabled)
                    dialog.accept()
            }
        }
        Label {
            objectName: "songConfirmationDetail"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: dialog.controller.confirmationDetail
            visible: text.length > 0
        }
        CheckBox {
            id: alsoVoicegroup
            objectName: "songDeleteVoicegroup"
            Layout.fillWidth: true
            visible: dialog.controller.confirmation === "delete"
                && dialog.controller.deletableVoicegroup.length > 0
            checked: true
            text: qsTr("Also delete voicegroup %1 (used only by this song)")
                .arg(dialog.controller.deletableVoicegroup)
        }
    }
}
