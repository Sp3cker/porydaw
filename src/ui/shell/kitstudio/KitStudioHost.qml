pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs as NativeDialogs
import Porydaw.Ui
import PorydawApp

Item {
    id: host
    required property KitStudioWorkflow workflow
    required property ApplicationSession applicationSession
    required property Window hostWindow
    required property GridPalette colors
    readonly property SplitStudioWindow window: windowLoader.item as SplitStudioWindow
    NativeDialogs.MessageDialog {
        id: alert
        objectName: "splitStudioAlert"
        parentWindow: host.window ? host.window : host.hostWindow
        title: qsTr("Split Studio")
        buttons: NativeDialogs.MessageDialog.Ok
    }
    OrphanCleanupDialog {
        parent: host.hostWindow.contentItem
        workflow: host.workflow
        colors: host.colors
        baseFontPx: host.applicationSession.baseFontPx
        layoutSpaces: host.applicationSession.layoutSpaces
    }
    Loader {
        id: windowLoader
        active: host.workflow.windowOpen
        sourceComponent: SplitStudioWindow {
            workflow: host.workflow
            applicationSession: host.applicationSession
            editor: {
                void host.workflow.presenterRevision
                return host.workflow.presenter()
            }
            library: host.workflow.library()
            colors: host.colors
            transientParent: host.hostWindow
        }
        onLoaded: (item as SplitStudioWindow).present()
        onStatusChanged: if (status === Loader.Null) host.workflow.windowReleased()
    }
    Connections {
        target: host.workflow
        function onAlertRevisionChanged(): void { alert.text = host.workflow.alertText; alert.open() }
    }
}
