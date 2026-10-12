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
    required property GridPalette colors

    MessageDialog {
        id: alert
        objectName: host.workflow.editorOpen ? "" : "shellSampleStudioAlert"
        buttons: MessageDialog.Ok
        parentWindow: host.hostWindow
    }
    Loader {
        id: studio
        active: host.workflow.editorOpen
        sourceComponent: SampleStudioDialog {
            objectName: "sampleStudioDialog"
            workflow: host.workflow
            library: host.workflow.library() as SampleLibraryModel
            applicationSession: host.applicationSession
            colors: host.colors
            editor: host.workflow.editor() as SampleStudioPresenter
            tools: host.workflow.loopTools() as SampleLoopTools
            waveformModel: host.workflow.waveform() as SampleWaveformModel
            audition: host.workflow.audition() as SampleStudioAudition
            transientParent: host.hostWindow
        }
        onLoaded: (studio.item as SampleStudioDialog).present()
        onStatusChanged: {
            if (status === Loader.Null)
                host.workflow.editorReleased()
        }
    }
    Loader {
        id: zones
        active: host.workflow.zonePickerOpen
        sourceComponent: Sf2ZonePickerDialog {
            workflow: host.workflow
            picker: host.workflow.zonePicker() as Sf2ZonePickerPresenter
            applicationSession: host.applicationSession
            colors: host.colors
            transientParent: host.hostWindow
        }
        onLoaded: (zones.item as Sf2ZonePickerDialog).present()
        onStatusChanged: {
            if (status === Loader.Null)
                host.workflow.zonePickerReleased()
        }
    }
    Connections {
        target: host.workflow
        function onAlertRevisionChanged(): void {
            if (host.workflow.editorOpen) return
            alert.title = host.workflow.alertTitle
            alert.text = host.workflow.alertText
            alert.open()
        }
    }
}
