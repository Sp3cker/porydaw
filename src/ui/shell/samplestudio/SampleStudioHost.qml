pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import Porydaw.Ui
import PorydawApp

Item {
    id: host
    required property SampleStudioWorkflow workflow
    required property Window hostWindow
    required property ApplicationSession applicationSession
    required property QtObject colors

    FileDialog {
        id: picker
        objectName: "shellImportSamplePicker"
        title: qsTr("Import Sample")
        nameFilters: [qsTr("Audio files (*.wav *.aif *.aiff *.mp3 *.flac *.ogg *.sf2)"),
                      qsTr("All files (*)")]
        fileMode: FileDialog.OpenFile
        currentFolder: host.workflow.pickerFolder
        onAccepted: host.workflow.chooseSource(selectedFile.toString())
        onRejected: host.workflow.cancelSource()
    }
    MessageDialog {
        id: alert
        objectName: "shellSampleStudioAlert"
        buttons: MessageDialog.Ok
        parentWindow: (studio.item as SampleStudioDialog)?.visible
                      ? (studio.item as SampleStudioDialog) : host.hostWindow
    }
    MessageDialog {
        id: stereo
        objectName: "shellSampleStudioStereoPrompt"
        title: qsTr("Import Sample")
        text: host.workflow.stereoPromptText
        buttons: MessageDialog.Yes | MessageDialog.No
        parentWindow: host.hostWindow
        onButtonClicked: (button) => host.workflow.answerStereoPrompt(button === MessageDialog.Yes)
    }
    Loader {
        id: studio
        active: host.workflow.editorOpen
        sourceComponent: SampleStudioDialog {
            objectName: "sampleStudioDialog"
            workflow: host.workflow
            applicationSession: host.applicationSession
            colors: host.colors
            editor: host.workflow.editor()
            tools: host.workflow.loopTools()
            waveformModel: host.workflow.waveform()
            audition: host.workflow.audition()
            transientParent: host.hostWindow
        }
        onLoaded: (studio.item as SampleStudioDialog).present()
    }
    Loader {
        id: zones
        active: host.workflow.zonePickerOpen
        sourceComponent: Sf2ZonePickerDialog {
            workflow: host.workflow
            picker: host.workflow.zonePicker()
            applicationSession: host.applicationSession
            colors: host.colors
            transientParent: host.hostWindow
        }
        onLoaded: (zones.item as Sf2ZonePickerDialog).present()
    }
    Connections {
        target: host.workflow
        function onPickerRequestedChanged(): void {
            if (host.workflow.pickerRequested) picker.open()
        }
        function onAlertRevisionChanged(): void {
            alert.title = host.workflow.alertTitle
            alert.text = host.workflow.alertText
            alert.open()
        }
        function onStereoPromptOpenChanged(): void {
            if (host.workflow.stereoPromptOpen) stereo.open()
            else stereo.close()
        }
    }
}
