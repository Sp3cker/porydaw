pragma ComponentBehavior: Bound
import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

Dialog {
    id: dialog
    objectName: "songConfirmationDialog"
    required property SongDockController controller
    required property real baseFontPx
    required property var layoutSpaces
    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    width: Math.min(parent.width - 2 * dialog.baseFontPx, 30 * dialog.baseFontPx)
    title: dialog.controller.confirmation === "register" ? qsTr("Register Song") : qsTr("Delete Song")
    standardButtons: Dialog.Ok | Dialog.Cancel
    onAccepted: dialog.controller.acceptConfirmation(alsoVoicegroup.checked)
    onClosed: {
        if (dialog.controller.confirmation.length > 0)
            dialog.controller.cancelConfirmation()
    }
    onRejected: dialog.controller.cancelConfirmation()
    function confirmationActionText(): string {
        return dialog.controller.confirmation === "register" ? qsTr("Register") : qsTr("Delete")
    }
    Component.onCompleted: {
        const ok = (dialog.footer as DialogButtonBox).standardButton(Dialog.Ok)
        if (ok) {
            ok.text = Qt.binding(dialog.confirmationActionText)
        }
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
