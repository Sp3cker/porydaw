import QtQuick
import QtQuick.Dialogs
import Porydaw.Ui

Item {
    id: host
    required property QtObject controller
    required property Window hostWindow
    required property QtObject colors
    required property QtObject applicationSession

    FileDialog {
        id: picker
        objectName: "shellImportMidiPicker"
        title: qsTr("Import MIDI")
        nameFilters: [qsTr("MIDI (*.mid)")]
        fileMode: FileDialog.OpenFile
        currentFolder: host.controller.startFolder
        onAccepted: host.controller.chooseSource(selectedFile.toString())
    }
    MessageDialog {
        id: warning
        objectName: "shellImportMidiWarning"
        buttons: MessageDialog.Ok
        parentWindow: wizard.visible ? wizard : host.hostWindow
    }
    MidiImportWizard {
        id: wizard
        objectName: "midiImportWizard"
        controller: host.controller
        colors: host.colors
        applicationSession: host.applicationSession
        transientParent: host.hostWindow
    }
    Connections {
        target: host.controller
        function onSourcePickerRequested() { picker.open() }
        function onWarningRequested(title, message) {
            warning.title = title
            warning.text = message
            warning.open()
        }
        function onWizardOpenChanged() {
            if (host.controller.wizardOpen)
                wizard.present()
            else
                wizard.close()
        }
    }
}
