pragma ComponentBehavior: Bound

import QtQuick
import PorydawApp

// The shell's window-scope action shortcuts for one window. Native Qt
// ShortcutOverride arbitration lets that window's focused item claim a key.
Repeater {
    id: shortcuts
    required property ShellPresenter shell
    required property string namePrefix
    property bool available: true
    model: shortcuts.shell.windowActionIds
    delegate: Item {
        id: shortcutDelegate
        required property string modelData
        final readonly property ShellActionState actionState: shortcuts.shell.action(modelData)
        // Qt's resolved alternates: the first on the named Shortcut, the rest beside it.
        readonly property list<string> sequenceTexts: shortcuts.shell.actionSequences(modelData)
        readonly property bool enabledHere: shortcutDelegate.actionState.enabled && shortcuts.available
        width: 0
        height: 0
        Shortcut {
            objectName: shortcuts.namePrefix + shortcutDelegate.modelData
            sequence: shortcutDelegate.sequenceTexts.length > 0 ? shortcutDelegate.sequenceTexts[0] : ""
            context: Qt.WindowShortcut
            enabled: shortcutDelegate.enabledHere && shortcutDelegate.sequenceTexts.length > 0
            onActivated: shortcuts.shell.activate(shortcutDelegate.modelData)
        }
        Repeater {
            model: Math.max(0, shortcutDelegate.sequenceTexts.length - 1)
            delegate: Item {
                id: alternate
                required property int index
                width: 0
                height: 0
                Shortcut {
                    sequence: shortcutDelegate.sequenceTexts[alternate.index + 1]
                    context: Qt.WindowShortcut
                    enabled: shortcutDelegate.enabledHere
                    onActivated: shortcuts.shell.activate(shortcutDelegate.modelData)
                }
            }
        }
    }
}
