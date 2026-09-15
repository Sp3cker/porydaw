// THROWAWAY composition experiment — not production code.
// One persistent song page inside the shell's StackLayout.
// Native responsibilities exercised here:
//   - FocusScope: Qt tracks the focused descendant; the page only gates
//     `focus`/`enabled` on selected && ready. No focus manager, no history.
//   - TextField: native typing/undo/selection; no synthetic key forwarding.
//   - Popup (Qt Quick Controls): real overlay popup with focus: true; it is
//     closed on deselection/readiness loss and Qt decides where focus lands.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

FocusScope {
    id: page

    required property string songId
    required property bool ready
    required property bool selected

    // The ONLY focus/input gate. Qt's scope rules do the rest.
    focus: selected && ready
    enabled: selected && ready

    property int editCount: 0
    SystemPalette { id: systemColors }

    // Fixed public surface for the shell/test driver.
    property alias editorA: editorA
    property alias editorB: editorB
    property alias canvas: canvas
    property alias popup: popup
    property alias popupEditor: popupEditor
    property alias popupButton: popupButton

    signal lifecycle(string kind, string pageId)

    objectName: "page_" + songId
    Accessible.name: "Song page " + songId

    Component.onCompleted: lifecycle("created", songId)
    Component.onDestruction: lifecycle("destroyed", songId)

    // Close the popup when the page loses selection or readiness.
    // Deliberately no onClosed focus restoration: we want to observe where
    // Qt puts focus natively.
    onSelectedChanged: if (!selected) popup.close()
    onReadyChanged: if (!ready) popup.close()

    Rectangle {
        anchors.fill: parent
        color: systemColors.window
        border.color: page.activeFocus ? systemColors.highlight : systemColors.mid
        border.width: page.activeFocus ? 2 : 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: fontMetrics.font.pixelSize
        spacing: fontMetrics.font.pixelSize / 2

        TextMetrics { id: fontMetrics }

        Label {
            objectName: "pageLabel_" + page.songId
            text: "Song " + page.songId
                  + " — edits: " + page.editCount
                  + (page.ready ? "" : " — NOT READY")
            font.bold: true
            Accessible.name: "Song " + page.songId + " status"
        }

        TextField {
            id: editorA
            objectName: "editorA_" + page.songId
            Accessible.name: "Editor A song " + page.songId
            Layout.fillWidth: true
            placeholderText: "Editor A (" + page.songId + ")"
            focus: true // initial focused descendant of this scope
        }

        TextField {
            id: editorB
            objectName: "editorB_" + page.songId
            Accessible.name: "Editor B song " + page.songId
            Layout.fillWidth: true
            placeholderText: "Editor B (" + page.songId + ")"
        }

        // Focusable "canvas": pressing K while it holds focus bumps editCount.
        Rectangle {
            id: canvas
            objectName: "canvas_" + page.songId
            Accessible.name: "Canvas song " + page.songId
            Layout.fillWidth: true
            Layout.preferredHeight: fontMetrics.font.pixelSize * 4
            activeFocusOnTab: true
            color: canvas.activeFocus ? systemColors.highlight : systemColors.base
            border.color: canvas.activeFocus ? systemColors.highlight : systemColors.mid
            border.width: 1

            // Pointer activation asks Qt for focus natively; no focus manager.
            TapHandler {
                onTapped: canvas.forceActiveFocus(Qt.MouseFocusReason)
            }

            Label {
                anchors.centerIn: parent
                text: "Canvas " + page.songId + " — press K"
                color: canvas.activeFocus ? systemColors.highlightedText : systemColors.text
            }

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_K) {
                    page.editCount += 1
                    event.accepted = true
                }
            }
        }

        Button {
            id: popupButton
            objectName: "popupButton_" + page.songId
            Accessible.name: "Open popup song " + page.songId
            text: "Popup " + page.songId
            onClicked: popup.open()
        }
    }

    Popup {
        id: popup
        objectName: "popup_" + page.songId
        focus: true // native popup takes focus while open
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        parent: page
        x: fontMetrics.font.pixelSize
        y: page.height - height - fontMetrics.font.pixelSize
        width: page.width - fontMetrics.font.pixelSize * 2
        height: fontMetrics.font.pixelSize * 4

        contentItem: TextField {
            id: popupEditor
            objectName: "popupEditor_" + page.songId
            Accessible.name: "Popup editor song " + page.songId
            placeholderText: "Popup editor (" + page.songId + ")"
            focus: true
        }
    }
}
