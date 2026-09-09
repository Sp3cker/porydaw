// The shared Quick window owns a persistent StackLayout page per open song.
// Each page attaches its canvas once and retains its own focus descendant.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Porydaw.Ui

FocusScope {
    id: root

    // Sole widget-to-workspace editor-focus entry.
    function enterEditor(reason) {
        editorArea.forceActiveFocus(reason)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        SongTabStrip {
            id: strip
            objectName: "songTabStrip"

            Layout.fillWidth: true
            Layout.preferredHeight: workspaceChrome.stripHeight
            onSessionAccepted: (reason) => root.enterEditor(reason)
        }

        FocusScope {
            id: editorArea
            focus: true

            Layout.fillWidth: true
            Layout.fillHeight: true

            StackLayout {
                id: pageStack

                anchors.fill: parent
                currentIndex: workspaceTabs.selectedIndex

                Repeater {
                    id: pageRepeater

                    model: workspaceTabs
                    delegate: FocusScope {
                        id: pageDelegate

                        required property var session
                        required property var quickView
                        required property bool ready
                        required property int index

                        // A page attaches only after completion and window association.
                        property bool componentComplete: false
                        property bool sceneAttached: false

                        focus: StackLayout.isCurrentItem && ready
                        enabled: StackLayout.isCurrentItem && ready

                        Window.onWindowChanged: attachWhenReady()
                        Component.onCompleted: {
                            componentComplete = true
                            attachWhenReady()
                        }

                        function attachWhenReady() {
                            if (!componentComplete || sceneAttached
                                || Window.window === null)
                                return
                            sceneAttached = true
                            quickView.attachToPage(pageDelegate)
                        }
                    }
                }
            }

            // The empty state lives beside the stack, never inside it, so it
            // can never become a page or disturb the model-bound index.
            Text {
                anchors.centerIn: parent
                visible: pageRepeater.count === 0
                text: qsTr("No songs open")
                textFormat: Text.PlainText
                color: workspaceChrome.disabledText
                font: workspaceChrome.font
                renderType: Text.NativeRendering
            }
        }
    }
}
