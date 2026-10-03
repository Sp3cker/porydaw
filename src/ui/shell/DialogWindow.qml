import QtQuick

// Base of every secondary Porydaw window: a native top-level dialog (platform open
// animation) that returns activation to its transient parent when it hides.
ThemedWindow {
    id: dialog
    property bool escapeCloses: true

    flags: Qt.Dialog
    modality: Qt.WindowModal
    color: colors.windowBackground

    function present() {
        show()
        raise()
        requestActivate()
    }

    onVisibleChanged: {
        if (visible || !transientParent)
            return
        const owner = transientParent
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
