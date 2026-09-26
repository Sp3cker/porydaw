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
    closePolicy: Popup.NoAutoClose
    width: Math.min(parent.width - 2 * baseFontPx, Math.max(28 * baseFontPx, 340))
    title: controller.confirmation === "register" ? qsTr("Register Song") : qsTr("Delete Song")
    standardButtons: Dialog.Ok | Dialog.Cancel
    onAccepted: controller.acceptConfirmation(alsoVoicegroup.checked)
    onRejected: controller.cancelConfirmation()
    Component.onCompleted: {
        const ok = dialog.footer.standardButton(Dialog.Ok)
        if (ok)
            ok.text = controller.confirmation === "register" ? qsTr("Register") : qsTr("Delete")
    }
    contentItem: ColumnLayout {
        spacing: dialog.layoutSpaces.four
        Label {
            objectName: "songConfirmationPrompt"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: dialog.controller.confirmation === "register"
                ? qsTr("Register %1 as %2?").arg(dialog.controller.confirmationLabel)
                    .arg(dialog.controller.registrationConstant)
                : qsTr("Delete %1?").arg(dialog.controller.confirmationLabel)
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
