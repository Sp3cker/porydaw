import QtQuick
import QtQuick.Controls
import QtQml.Models

Item {
    id: contextRoot
    property bool noteMenuSwallowingRelease: false
    required property var root
    required property var shell
    required property var editorScene
    required property var bodyMetrics
    readonly property alias menu: gridContextMenu
    Component {
        id: contextRow
        MenuItem {
            id: contextAction
            required property string modelData
            property int menuOrdinal: -1
            objectName: "shellContextAction_" + modelData
            text: shell.actionLabel(modelData)
            readonly property string shortcutText: shell.actionShortcut(modelData)
            readonly property color foreground: !enabled ? root.colors.disabledText
                : down ? root.colors.buttonPressedText : root.colors.windowText
            Accessible.description: shortcutText
            hoverEnabled: true
            padding: root.chromeSpacing.one
            contentItem: Item {
                implicitWidth: caption.implicitWidth + (hint.visible
                    ? hint.implicitWidth + bodyMetrics.averageCharacterWidth * 2 : 0)
                implicitHeight: Math.max(caption.implicitHeight, hint.implicitHeight)
                Text {
                    id: caption
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: contextAction.text
                    font: contextAction.font
                    color: contextAction.foreground
                }
                Text {
                    id: hint
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text.length > 0
                    text: contextAction.shortcutText
                    font: contextAction.font
                    color: contextAction.foreground
                }
            }
            background: Rectangle {
                color: contextAction.down ? root.colors.buttonPressedBackground
                    : contextAction.highlighted ? root.colors.menuHoverBackground
                    : root.colors.menuBackground
            }
            enabled: {
                root.actionRevision
                return shell.actionEnabled(modelData)
            }
            onTriggered: shell.activate(modelData)
        }
    }
    Item {
        parent: Overlay.overlay
        anchors.fill: parent
        z: 1
        visible: gridContextMenu.visible || contextRoot.noteMenuSwallowingRelease
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            onPressed: (mouse) => {
                contextRoot.noteMenuSwallowingRelease = true
                if (mouse.button === Qt.RightButton) {
                    const surface = editorScene.selectedEditorSurface()
                    const point = mapToItem(null, mouse.x, mouse.y)
                    gridContextMenu.close()
                    if (surface)
                        surface.retargetNoteMenu(point.x, point.y)
                } else {
                    gridContextMenu.close()
                }
                mouse.accepted = true
            }
            onReleased: Qt.callLater(() => contextRoot.noteMenuSwallowingRelease = false)
            onCanceled: Qt.callLater(() => contextRoot.noteMenuSwallowingRelease = false)
        }
    }
    Menu {
        id: gridContextMenu
        objectName: "shellGridContextMenu"
        readonly property int headActionCount: shell.contextHeadActionIds.length
        parent: Overlay.overlay
        popupType: Popup.Item
        z: 2
        font: Qt.font(root.chromeTypography.body)
        closePolicy: Popup.CloseOnEscape
        palette.window: root.colors.menuBackground
        palette.dark: root.colors.outline
        onAboutToShow: ++root.actionRevision
        // Async workspace incubation adds Instantiator rows before the static separator
        // exists, so rows insert by ordinal; ShellMenuBar's separator-anchor would misorder.
        function insertContextItem(ordinal, item) {
            item.menuOrdinal = ordinal
            let position = 0
            while (position < gridContextMenu.count
                   && gridContextMenu.itemAt(position).menuOrdinal < ordinal)
                ++position
            gridContextMenu.insertItem(position, item)
        }
        Instantiator {
            model: shell.contextHeadActionIds
            delegate: contextRow
            onObjectAdded: (index, object) => gridContextMenu.insertContextItem(index, object)
            onObjectRemoved: (index, object) => gridContextMenu.removeItem(object)
        }
        Instantiator {
            model: 1
            delegate: MenuSeparator {
                property int menuOrdinal: -1
            }
            onObjectAdded: (index, object) => gridContextMenu.insertContextItem(
                gridContextMenu.headActionCount, object)
            onObjectRemoved: (index, object) => gridContextMenu.removeItem(object)
        }

        Instantiator {
            model: shell.contextBodyActionIds
            delegate: contextRow
            onObjectAdded: (index, object) => gridContextMenu.insertContextItem(
                gridContextMenu.headActionCount + 1 + index, object)
            onObjectRemoved: (index, object) => gridContextMenu.removeItem(object)
        }
    }
}
