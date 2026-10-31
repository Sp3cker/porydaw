pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp

// Creates the Virtual MIDI Keyboard window on its first show and keeps it, so a
// hidden keyboard costs nothing and keeps its place; the presenter owns visibility.
Item {
    id: host
    required property VirtualKeyboardPresenter presenter
    required property ShellPresenter shell
    required property ShellWindow hostWindow
    readonly property VirtualKeyboardWindow window: windowLoader.item as VirtualKeyboardWindow
    readonly property bool wanted: host.presenter.visible
    property bool requested: false
    onWantedChanged: host.sync()
    Component.onCompleted: host.sync()

    function sync(): void {
        if (host.presenter.visible)
            host.requested = true
        const keyboard = host.window
        if (!keyboard)
            return
        if (host.presenter.visible)
            keyboard.present()
        else
            keyboard.dismiss()
    }

    Loader {
        id: windowLoader
        objectName: "virtualKeyboardLoader"
        active: host.requested
        sourceComponent: VirtualKeyboardWindow {
            presenter: host.presenter
            shell: host.shell
            hostWindow: host.hostWindow
            applicationSession: host.shell.session
            colors: host.hostWindow.colors
            transientParent: host.hostWindow
        }
        onLoaded: host.sync()
    }
}
