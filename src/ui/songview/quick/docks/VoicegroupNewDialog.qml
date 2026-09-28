import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import Porydaw.Ui

Basic.Dialog {
    id: dialog
    objectName: "voicegroupNewDialog"
    required property var controller
    required property real baseFontPx
    required property var layoutSpaces
    readonly property bool hasCopySource: controller.newVoicegroupCopyLabel.length > 0
    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    width: Math.min(parent.width - 2 * baseFontPx, 30 * baseFontPx)
    title: qsTr("New Voicegroup")
    standardButtons: Dialog.Ok | Dialog.Cancel
    onOpened: nameField.forceActiveFocus()
    onAccepted: {
        controller.newVoicegroupName = nameField.text
        controller.newVoicegroupUseCopy = hasCopySource && sourceCombo.currentIndex === 0
        controller.acceptNewVoicegroup()
    }
    onRejected: controller.cancelNewVoicegroup()
    onClosed: {
        if (controller.newVoicegroupPrompt)
            controller.cancelNewVoicegroup()
    }
    Component.onCompleted: {
        const ok = dialog.footer.standardButton(Dialog.Ok)
        if (ok) {
            ok.text = qsTr("Create")
            ok.enabled = Qt.binding(function() {
                return dialog.controller.isValidVoicegroupName(nameField.text)
                    && dialog.controller.newVoicegroupNameAvailable(nameField.text)
            })
        }
    }
    contentItem: ColumnLayout {
        spacing: dialog.layoutSpaces.four
        Label {
            objectName: "voicegroupNewPrompt"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Create a voicegroup from the current bank:")
        }
        TextField {
            id: nameField
            objectName: "voicegroupNewName"
            Layout.fillWidth: true
            placeholderText: qsTr("my_voicegroup")
            text: dialog.controller.newVoicegroupName
            onTextChanged: dialog.controller.newVoicegroupName = text
            onAccepted: {
                if (dialog.footer.standardButton(Dialog.Ok).enabled)
                    dialog.accept()
            }
        }
        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("Source")
        }
        ComboBox {
            id: sourceCombo
            objectName: "voicegroupNewSource"
            Layout.fillWidth: true
            model: dialog.hasCopySource
                ? [qsTr("Copy of %1").arg(dialog.controller.newVoicegroupCopyLabel),
                   qsTr("Empty (dummy template)")]
                : [qsTr("Empty (dummy template)")]
        }
    }
}
