import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts

ApplicationWindow {
    id: root

    required property QtObject songTabs
    required property QtObject widgetInterop
    required property QtObject newSongWizard
    required property QtObject newSongResult
    readonly property bool widgetInteropBusy: widgetInterop !== null && widgetInterop.busy
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

    // Bootstrap boundary: install the native widget host (and smoke lane) only
    // after QApplication/QML are fully constructed.
    Component.onCompleted: widgetInterop.initializeHost()


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
                objectName: "widgetInteropWizardButton"
                text: "New Song…"
                Accessible.description: "Open the New Song wizard"
                enabled: !root.widgetInteropBusy && !root.newSongWizard.active
                onClicked: root.newSongWizard.begin()
            }
            ChromeButton {
                objectName: "widgetInteropMenuButton"
                text: "Widget Menu"
                Accessible.description: "Open a native menu over the piano grid"
                enabled: !root.widgetInteropBusy
                onClicked: {
                    // Window-local point for the native side: the button's
                    // bottom-left in contentItem coordinates (never scaled).
                    const origin = mapToItem(root.contentItem, 0, height);
                    root.widgetInterop.openMenu(origin.x, origin.y);
                }
            }
            Basic.ComboBox {
                id: fixtureChooser
                objectName: "widgetInteropFixtureChooser"
                enabled: !root.widgetInteropBusy
                implicitHeight: Math.round(root.baseFontPx * 2)
                implicitWidth: Math.round(root.baseFontPx * 14)
                font: root.font
                textRole: "text"
                valueRole: "kind"
                model: [
                    { text: "1: Settings (mock)", kind: 1 },
                    { text: "2: Sample Editor (mock)", kind: 2 },
                    { text: "3: SF2 Picker (mock)", kind: 3 },
                    { text: "4: Import MIDI (mock)", kind: 4 },
                    { text: "5: New Voicegroup (mock)", kind: 5 },
                    { text: "6: Export WAV (mock)", kind: 6 },
                    { text: "7: Progress (mock)", kind: 7 },
                    { text: "8: Open File (mock)", kind: 8 },
                    { text: "9: Save File (mock)", kind: 9 },
                    { text: "10: Directory (mock)", kind: 10 },
                    { text: "11: Confirmation (mock)", kind: 11 },
                    { text: "12: Error (mock)", kind: 12 },
                    { text: "13: About (mock)", kind: 13 }
                ]
                Accessible.name: "Standalone window fixture chooser (mock data, no project writes)"
                ToolTip.visible: hovered
                ToolTip.text: "Standalone widget fixture (mock data, no project writes)"
            }
            ChromeButton {
                objectName: "widgetInteropOpenButton"
                text: "Open"
                Accessible.description: "Open selected standalone window fixture with mock data (no project writes)"
                enabled: !root.widgetInteropBusy
                onClicked: root.widgetInterop.openWindowFixture(fixtureChooser.model[fixtureChooser.currentIndex].kind)
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

    Loader {
        active: root.newSongWizard.active
        sourceComponent: Component {
            NewSongWizard {
                controller: root.newSongWizard
                colors: root.gridPalette
                font: root.font
                transientParent: root
            }
        }
    }

}
