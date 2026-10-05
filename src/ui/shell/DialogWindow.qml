pragma ComponentBehavior: Bound

import QtQuick

// Base of every secondary Porydaw window: a native top-level dialog (platform open
// animation) that returns activation to its transient parent when it hides.
ThemedWindow {
    id: dialog
    property bool escapeCloses: true

    flags: Qt.Dialog
    modality: Qt.WindowModal
    color: dialog.colors.windowBackground

    function present(): void {
        dialog.show()
        dialog.raise()
        dialog.requestActivate()
    }

    onVisibleChanged: {
        if (dialog.visible || !dialog.transientParent)
            return
        const owner = dialog.transientParent
        Qt.callLater(() => {
            if (!dialog.visible && owner.visible) {
                owner.raise()
                owner.requestActivate()
            }
        })
    }

    Shortcut {
        objectName: "dialogEscapeShortcut"
        sequence: "Esc"
        context: Qt.WindowShortcut
        enabled: dialog.escapeCloses
        onActivated: dialog.close()
    }
}
