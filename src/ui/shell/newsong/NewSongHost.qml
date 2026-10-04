pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import Porydaw.Ui
import PorydawApp

Item {
    id: host
    required property NewSongController controller
    required property Window hostWindow
    required property GridPalette colors
    required property ApplicationSession applicationSession

    MessageDialog {
        id: warning
        objectName: "shellNewSongWarning"
        buttons: MessageDialog.Ok
        parentWindow: wizard.visible ? wizard : host.hostWindow
    }
    NewSongWizard {
        id: wizard
        controller: host.controller
        colors: host.colors
        applicationSession: host.applicationSession
        transientParent: host.hostWindow
    }
    Connections {
        target: host.controller
        function onWarningRequested(title: string, message: string): void {
            warning.title = title
            warning.text = message
            warning.open()
        }
        function onWizardOpenChanged(): void {
            if (host.controller.wizardOpen)
                wizard.present()
            else
                wizard.close()
        }
    }
}
