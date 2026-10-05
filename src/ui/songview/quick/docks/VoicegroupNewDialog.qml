pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp
import QtQuick.Templates as T

Dialog {
    id: dialog
    objectName: "voicegroupNewDialog"
    required property VoiceListController controller
    required property real baseFontPx
    required property LayoutSpaces layoutSpaces
    readonly property bool hasCopySource: controller.newVoicegroupCopyLabel !== ""
    final readonly property T.DialogButtonBox buttonBox: footer as T.DialogButtonBox
    final property T.AbstractButton createButton: null
    function canCreate(): bool {
        return dialog.controller.isValidVoicegroupName(nameField.text)
            && dialog.controller.newVoicegroupNameAvailable(nameField.text)
    }
    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape
    width: Math.min(parent.width - 2 * baseFontPx, 30 * baseFontPx)
    title: qsTr("New Voicegroup")
    standardButtons: Dialog.Ok | Dialog.Cancel
    onOpened: {
        dialog.createButton = dialog.buttonBox.standardButton(Dialog.Ok)
        dialog.createButton.text = qsTr("Create")
        nameField.forceActiveFocus()
    }
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
    Binding {
        target: dialog.createButton
        property: "enabled"
        value: dialog.canCreate()
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
                if (dialog.createButton.enabled)
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
            readonly property list<string> choices: dialog.hasCopySource
                ? [qsTr("Copy of %1").arg(dialog.controller.newVoicegroupCopyLabel),
                   qsTr("Empty (dummy template)")]
                : [qsTr("Empty (dummy template)")]
            model: sourceCombo.choices
        }
    }
}
