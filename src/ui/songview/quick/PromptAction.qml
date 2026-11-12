pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp

Item {
    id: action
    required property PromptStyle appearance
    property string text: ""
    signal activated()
    implicitWidth: chrome.implicitWidth
    implicitHeight: chrome.implicitHeight
    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.focusable: enabled
    Accessible.onPressAction: activate()

    function activate(): void {
        if (enabled)
            activated()
    }

    Keys.onReturnPressed: event => { activate(); event.accepted = true }
    Keys.onEnterPressed: event => { activate(); event.accepted = true }
    Keys.onShortcutOverride: event => event.accepted =
        event.key === Qt.Key_Return || event.key === Qt.Key_Enter

    PromptButton {
        id: chrome
        anchors.fill: parent
        appearance: action.appearance
        text: action.text
        activeFocusOnTab: false
        Accessible.ignored: true
        Keys.enabled: false
        border.color: action.activeFocus ? appearance.focus : appearance.outline
        onActivated: {
            action.forceActiveFocus(Qt.MouseFocusReason)
            action.activate()
        }
    }
}
