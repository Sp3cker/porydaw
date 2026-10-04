pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQml.Models
import PorydawApp
import Porydaw.Ui

Item {
    id: contextRoot
    property bool noteMenuSwallowingRelease: false
    required final property ShellWindow root
    required final property ShellPresenter shell
    required final property SongTabs editorScene
    required final property FontMetrics bodyMetrics
    final readonly property alias menu: gridContextMenu

    function finishSwallowingRelease(): void {
        contextRoot.noteMenuSwallowingRelease = false
    }
    component ContextAction: MenuItem {
        id: contextAction
        required property string modelData
        final readonly property ShellActionState actionState: contextRoot.shell.action(modelData)
        property int menuOrdinal: -1
        objectName: "shellContextAction_" + modelData
        text: contextAction.actionState.label
        readonly property string shortcutText: contextAction.actionState.shortcut
        readonly property color foreground: !enabled ? contextRoot.root.colors.disabledText
            : down ? contextRoot.root.colors.buttonPressedText : contextRoot.root.colors.windowText
        Accessible.description: shortcutText
        hoverEnabled: true
        padding: contextRoot.root.chromeSpacing.one
        contentItem: Item {
            implicitWidth: caption.implicitWidth + (hint.visible
                ? hint.implicitWidth + contextRoot.bodyMetrics.averageCharacterWidth * 2 : 0)
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
            color: contextAction.down ? contextRoot.root.colors.buttonPressedBackground
                : contextAction.highlighted ? contextRoot.root.colors.menuHoverBackground
                : contextRoot.root.colors.menuBackground
        }
        enabled: contextAction.actionState.enabled
        onTriggered: contextRoot.shell.activate(modelData)
    }
    component ContextSeparator: MenuSeparator {
        property int menuOrdinal: -1
    }
    Component {
        id: contextRow
        ContextAction {}
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
                    const surface = contextRoot.editorScene.selectedEditorSurface() as EditorSurface
                    const point = mapToItem(null, mouse.x, mouse.y)
                    gridContextMenu.close()
                    if (surface)
                        surface.retargetNoteMenu(point.x, point.y)
                } else {
                    gridContextMenu.close()
                }
                mouse.accepted = true
            }
            onReleased: Qt.callLater(contextRoot.finishSwallowingRelease)
            onCanceled: Qt.callLater(contextRoot.finishSwallowingRelease)
        }
    }
    Menu {
        id: gridContextMenu
        objectName: "shellGridContextMenu"
        readonly property int headActionCount: contextRoot.shell.contextHeadActionIds.length
        parent: Overlay.overlay
        popupType: Popup.Item
        z: 2
        font: contextRoot.root.chromeTypography.body
        closePolicy: Popup.CloseOnEscape
        palette.window: contextRoot.root.colors.menuBackground
        palette.dark: contextRoot.root.colors.outline
        onAboutToShow: contextRoot.shell.refreshActionStates()
        // Async workspace incubation adds Instantiator rows before the static separator
        // exists, so rows insert by ordinal; ShellMenuBar's separator-anchor would misorder.
        function insertContextItem(ordinal: int, item: Item): void {
            const action = item as ContextAction
            if (action)
                action.menuOrdinal = ordinal
            else
                (item as ContextSeparator).menuOrdinal = ordinal
            let position = 0
            while (position < gridContextMenu.count) {
                const candidate = gridContextMenu.itemAt(position)
                const candidateAction = candidate as ContextAction
                const candidateOrdinal = candidateAction ? candidateAction.menuOrdinal
                    : (candidate as ContextSeparator).menuOrdinal
                if (candidateOrdinal >= ordinal)
                    break
                ++position
            }
            gridContextMenu.insertItem(position, item)
        }
        Instantiator {
            model: contextRoot.shell.contextHeadActionIds
            delegate: contextRow
            onObjectAdded: (index, object) => gridContextMenu.insertContextItem(index, object as Item)
            onObjectRemoved: (index, object) => gridContextMenu.removeItem(object as Item)
        }
        Instantiator {
            model: 1
            delegate: ContextSeparator {}
            onObjectAdded: (index, object) => gridContextMenu.insertContextItem(
                gridContextMenu.headActionCount, object as Item)
            onObjectRemoved: (index, object) => gridContextMenu.removeItem(object as Item)
        }

        Instantiator {
            model: contextRoot.shell.contextBodyActionIds
            delegate: contextRow
            onObjectAdded: (index, object) => gridContextMenu.insertContextItem(
                gridContextMenu.headActionCount + 1 + index, object as Item)
            onObjectRemoved: (index, object) => gridContextMenu.removeItem(object as Item)
        }
    }
}
