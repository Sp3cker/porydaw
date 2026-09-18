import QtQuick

Item {
    id: root

    required property real baseFontPx
    required property font menuFont
    signal chosen(string command)

    property bool opened: false
    property point origin: Qt.point(0, 0)
    readonly property int padding: Math.round(baseFontPx * 0.5)
    readonly property int gap: Math.round(baseFontPx * 0.25)
    readonly property int verticalPadding: Math.round(baseFontPx * 0.125)
    readonly property int textWidth: Math.round(Math.max(pitchText.advanceWidth, deleteText.advanceWidth))
    readonly property int shortcutWidth: Math.round(Math.max(pitchShortcut.advanceWidth, deleteShortcut.advanceWidth))

    visible: opened
    focus: opened

    function openAt(point) {
        origin = Qt.point(Math.max(gap, Math.min(point.x, width - panel.menuWidth - gap)), Math.max(gap, Math.min(point.y, height - panel.menuHeight - gap)));
        panel.highlightedRow = -1;
        panel.pressedRow = -1;
        opened = true;
        forceActiveFocus();
    }

    function close() {
        opened = false;
    }

    function hoverRow(menuPanel, row) {
        menuPanel.highlightedRow = row;
    }

    function activateRow(menuPanel, row) {
        const command = actions.get(row).itemId;
        close();
        chosen(command);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            close();
        } else if (event.key === Qt.Key_Down) {
            panel.highlightedRow = (panel.highlightedRow + 1) % actions.count;
        } else if (event.key === Qt.Key_Up) {
            panel.highlightedRow = panel.highlightedRow <= 0 ? actions.count - 1 : panel.highlightedRow - 1;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && panel.highlightedRow >= 0) {
            activateRow(panel, panel.highlightedRow);
        } else {
            event.accepted = false;
            return;
        }
        event.accepted = true;
    }

    FontMetrics {
        id: metrics
        font: root.menuFont
    }

    component NativeMetrics: TextMetrics {
        font: root.menuFont
        renderType: Text.NativeRendering
    }
    NativeMetrics {
        id: pitchText
        text: actions.get(0).text
    }
    NativeMetrics {
        id: deleteText
        text: actions.get(1).text
    }
    NativeMetrics {
        id: pitchShortcut
        text: actions.get(0).shortcutText
    }
    NativeMetrics {
        id: deleteShortcut
        text: actions.get(1).shortcutText
    }

    ListModel {
        id: actions
        ListElement {
            itemId: "pitch"
            text: "Pitch Bend…"
            shortcutText: "G"
            checkable: false
            checked: false
            enabled: true
            separator: false
            hasSubmenu: false
        }
        ListElement {
            itemId: "delete"
            text: "Delete"
            shortcutText: "⌫"
            checkable: false
            checked: false
            enabled: true
            separator: false
            hasSubmenu: false
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: root.close()
    }

    QuickMenuPanel {
        id: panel
        anchors.fill: parent
        host: root
        menuModel: actions
        rootLevel: true
        appearance: ({
                background: "#D2D0CA",
                outline: "#8C857F",
                text: "#302C29",
                hoverBackground: "#E7E2DC",
                hoverText: "#302C29",
                pressedBackground: "#F5B61C",
                pressedText: "#302C29",
                disabledText: "#8B847E",
                separator: "#5B5652",
                font: root.menuFont
            })
        rowHeight: Math.round(metrics.height) + 2 * root.verticalPadding
        textX: root.padding
        menuWidth: 2 + 2 * root.padding + root.textWidth + root.gap + root.shortcutWidth
        menuHeight: 2 + actions.count * rowHeight
        shortcutRight: menuWidth - 1 - root.padding
        textRight: shortcutRight - root.shortcutWidth - root.gap
        menuOrigin: root.origin
    }
}
