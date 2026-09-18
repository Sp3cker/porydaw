import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root

    required property QtObject songTabs
    readonly property Item currentPage: tabs.currentPage
    readonly property QtObject gridModel: currentPage ? currentPage.gridModel : null
    readonly property QtObject audio: currentPage ? currentPage.audio : null
    readonly property var pitchBridge: currentPage ? currentPage.pitchBridge : null
    readonly property string contextualHint: currentPage ? currentPage.contextualHint : ""
    readonly property var gridPalette: gridModel ? gridModel.palette : ({
            windowBackground: "#C9C1BB",
            chromeBackground: "#BDB5AF",
            separator: "#5B5652",
            outline: "#8C857F",
            tabBackground: "#E1DBD6",
            tabHoverBackground: "#ECE7E1",
            tabSelectedBackground: "#B9E8EE",
            windowText: "#302C29",
            secondaryText: "#57514C",
            playhead: "#E24242"
        })
    readonly property bool gridShortcutsEnabled: currentPage !== null && songTabs.pendingCloseId < 0 && !currentPage.noteMenuOpen && !currentPage.pitchEditorOpen

    function resetDemo() {
        if (currentPage)
            currentPage.resetDemo();
    }

    function escapePressed() {
        if (currentPage)
            currentPage.escapePressed();
    }


    Shortcut {
        sequence: "Space"
        enabled: root.gridShortcutsEnabled
        onActivated: root.audio.togglePlayback()
    }
    Shortcut {
        sequences: ["Delete", "Backspace"]
        enabled: root.gridShortcutsEnabled
        onActivated: root.gridModel.deleteSelection()
    }
    Shortcut {
        sequence: "G"
        enabled: root.gridShortcutsEnabled
        onActivated: root.currentPage.pitchEditorRequested()
    }


    FontLoader {
        id: bodyFace
        source: "qrc:/fonts/AtkinsonHyperlegibleNext-Regular.ttf"
    }
    FontLoader {
        id: semiboldFace
        source: "qrc:/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf"
    }
    FontLoader {
        id: monoFace
        source: "qrc:/fonts/AtkinsonHyperlegibleMono-Regular.ttf"
    }
    readonly property real baseFontPx: appFontInfo.pixelSize
    readonly property real bodyScale: 1.125
    readonly property real bodyPx: Math.max(1, Math.round(baseFontPx * bodyScale))

    FontInfo {
        id: appFontInfo
        font: Qt.application.font
    }

    font.family: bodyFace.font.family
    font.pixelSize: root.bodyPx


    visible: true
    width: 1280
    height: 800
    title: "Porydaw — Swift Grid Prototype"
    color: root.gridPalette.windowBackground


    component ChromeButton: Rectangle {
        id: button
        required property string text
        signal clicked
        implicitWidth: caption.implicitWidth + Math.round(root.baseFontPx)
        implicitHeight: Math.round(root.baseFontPx * 2)
        activeFocusOnTab: true
        opacity: enabled ? 1 : 0.5
        color: pointer.pressed ? "#F5B61C" : pointer.containsMouse ? "#E7E2DC" : root.gridPalette.windowBackground
        border.width: 1 / Screen.devicePixelRatio
        border.color: root.gridPalette.outline
        Accessible.role: Accessible.Button
        Accessible.name: text
        Accessible.onPressAction: clicked()
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Text {
            id: caption
            anchors.centerIn: parent
            text: button.text
            font: root.font
            color: root.gridPalette.windowText
            renderType: Text.NativeRendering
        }
        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                button.forceActiveFocus(Qt.MouseFocusReason);
                button.clicked();
            }
        }
    }

    header: ToolBar {
        enabled: root.currentPage !== null && root.songTabs.pendingCloseId < 0
        background: Rectangle {
            color: root.gridPalette.chromeBackground
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: root.gridPalette.separator
            }
        }
        contentItem: RowLayout {
            spacing: Math.round(root.baseFontPx * 0.5)

            Text {
                text: "Piano grid prototype — mus_route101 fixture"
                color: root.gridPalette.windowText
                font.pixelSize: root.bodyPx
                Layout.leftMargin: Math.round(root.baseFontPx * 0.5)
            }
            Text {
                text: root.contextualHint.length > 0 ? root.contextualHint : root.gridModel ? root.gridModel.statusText : ""
                color: root.gridPalette.secondaryText
                font.pixelSize: root.bodyPx
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            ChromeButton {
                objectName: "transportPlayPause"
                text: root.audio && root.audio.playing ? "Pause" : "Play"
                enabled: root.audio !== null && root.audio.ready
                onClicked: root.audio.togglePlayback()
            }
            ChromeButton {
                objectName: "transportStop"
                text: "Stop"
                enabled: root.audio !== null && root.audio.ready
                onClicked: root.audio.stop()
            }
            Text {
                objectName: "audioBackendStatus"
                text: !root.audio ? "" : root.audio.errorText.length > 0 ? "Audio unavailable: " + root.audio.errorText : root.audio.backendName + (root.audio.usingNullBackend ? " (null)" : "")
                color: root.audio && root.audio.errorText.length > 0 ? root.gridPalette.playhead : root.gridPalette.secondaryText
                font.pixelSize: root.bodyPx
                elide: Text.ElideRight
            }
            ChromeButton {
                text: "Reset"
                onClicked: root.resetDemo()
                Layout.rightMargin: Math.round(root.baseFontPx * 0.5)
            }
        }
    }

    SongTabs {
        id: tabs
        anchors.fill: parent
        controller: root.songTabs
        font: root.font
        baseFontPx: root.baseFontPx
        monoFamily: monoFace.font.family
        gridPalette: root.gridPalette
    }

}
