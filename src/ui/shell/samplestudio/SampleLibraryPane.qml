pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import PorydawStyle
import Porydaw.Ui
import Porydaw.Icons
import PorydawApp
Item {
    id: pane
    objectName: "sampleLibraryPanel"
    required property SampleLibraryModel library
    required property GridPalette colors
    required property Window studioWindow
    required property real unit
    required property real paneSpacing
    function navigateFolder(row: int): void {
        if (row < 0 || row >= folders.count)
            return
        files.currentIndex = -1
        pane.library.selectFolder(row)
        pane.alignFolderCursor()
    }

    function navigateToParent(row: int): void {
        const parent = pane.library.parentFolderRow(row)
        if (parent >= 0 && parent !== row)
            pane.navigateFolder(parent)
    }

    function alignFolderCursor(): void {
        folders.forceLayout()
        const row = pane.library.selectedFolderRow()
        if (row >= 0)
            folders.positionViewAtIndex(row, ListView.Contain)
        folders.currentIndex = row
    }

    function folderRowAt(row: int): FolderRow {
        folders.forceLayout()
        if (row < 0 || row >= folders.count)
            return null
        folders.positionViewAtIndex(row, ListView.Contain)
        folders.forceLayout()
        return folders.itemAtIndex(row) as FolderRow
    }
    property bool folderDropHover: false

    FolderDialog {
        id: folderPicker
        objectName: "sampleLibraryFolderPicker"
        title: qsTr("Add Folder to Library")
        parentWindow: pane.studioWindow
        onAccepted: {
            files.currentIndex = -1
            pane.library.addFolder(selectedFolder)
            pane.alignFolderCursor()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: pane.colors.menuBackground
    }
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: Math.max(1, Math.round(pane.unit / 13))
        color: pane.colors.outline
    }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: pane.paneSpacing * 1.5
        spacing: pane.paneSpacing
        RowLayout {
            Layout.fillWidth: true
            spacing: pane.paneSpacing
            Label {
                Layout.fillWidth: true
                text: qsTr("Library")
                font.bold: true
                color: pane.colors.windowText
            }
            ToolButton {
                objectName: "sampleLibraryAdd"
                text: "+"
                Accessible.name: qsTr("Add Folder")
                onClicked: folderPicker.open()
            }
        }
        ListView {
            id: folders
            objectName: "sampleLibraryFolders"
            Accessible.role: Accessible.List
            Accessible.name: qsTr("Library folders")
            Accessible.focusable: true
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(folders.contentHeight, 16 * pane.unit)
            activeFocusOnTab: true
            onActiveFocusChanged: {
                if (activeFocus)
                    pane.alignFolderCursor()
            }
            currentIndex: -1
            highlightFollowsCurrentItem: false
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => {
                if (event.modifiers !== Qt.NoModifier)
                    return
                if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                    const row = folders.currentIndex < 0 ? 0
                        : Math.max(0, Math.min(folders.count - 1,
                                                folders.currentIndex + (event.key === Qt.Key_Down ? 1 : -1)))
                    pane.navigateFolder(row)
                    event.accepted = true
                    return
                }
                if (event.key !== Qt.Key_Left && event.key !== Qt.Key_Right)
                    return
                const row = pane.folderRowAt(folders.currentIndex)
                if (!row)
                    return
                if (event.key === Qt.Key_Right && row.hasChildren && !row.expanded) {
                    pane.library.toggleFolder(row.index)
                } else if (event.key === Qt.Key_Left && row.hasChildren && row.expanded) {
                    pane.library.toggleFolder(row.index)
                } else if (event.key === Qt.Key_Left) {
                    pane.navigateToParent(row.index)
                }
                event.accepted = true
            }
            clip: true
            model: pane.library.folders
            delegate: FolderRow {}
            component FolderRow: Rectangle {
                id: folderRow
                objectName: "sampleLibraryFolderRow"
                required property int index
                required property string title
                required property int depth
                required property bool expanded
                required property bool hasChildren
                required property bool selected
                width: folders.width
                height: 2.15 * pane.unit
                radius: pane.unit / 3
                color: folderRow.selected ? pane.colors.selectionFill : "transparent"
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const row = folderRow.index
                        pane.navigateFolder(row)
                        folders.forceActiveFocus()
                    }
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: folderRow.depth * pane.unit + pane.paneSpacing
                    anchors.rightMargin: pane.paneSpacing
                    spacing: pane.paneSpacing / 2
                    Item {
                        Layout.preferredWidth: pane.unit
                        Layout.fillHeight: true
                        Label {
                            anchors.centerIn: parent
                            visible: folderRow.hasChildren
                            text: folderRow.expanded ? "▾" : "▸"
                            color: pane.colors.windowText
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: folderRow.hasChildren
                            onClicked: pane.library.toggleFolder(folderRow.index)
                        }
                    }
                    Label {
                        text: "▤"
                        color: pane.colors.windowText
                    }
                    Label {
                        objectName: "sampleLibraryFolderName"
                        Layout.fillWidth: true
                        text: folderRow.title
                        elide: Text.ElideRight
                        color: pane.colors.windowText
                    }
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            visible: files.visible
            Layout.preferredHeight: Math.max(1, Math.round(pane.unit / 13))
            color: pane.colors.outline
        }
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !files.visible
            DropZone {
                objectName: "sampleLibraryDropZone"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: Math.min(parent.height, 10 * pane.unit)
                visible: folders.count === 0
                colors: pane.colors
                unit: pane.unit
                glyph: Icons.addFolder
                dropHover: pane.folderDropHover
                Accessible.name: qsTr("Add Folder")
                onActivated: folderPicker.open()
            }
        }
        ListView {
            id: files
            objectName: "sampleLibraryFiles"
            Accessible.role: Accessible.List
            Accessible.name: qsTr("Library audio files")
            Accessible.focusable: true
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: pane.library.filesVisible
            clip: true
            activeFocusOnTab: true
            currentIndex: -1
            model: pane.library.files
            onCurrentIndexChanged: {
                if (currentIndex < 0)
                    pane.library.clearFileSelection()
                else
                    pane.library.selectFile(currentIndex)
            }
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => {
                if ((event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                        && event.modifiers === Qt.NoModifier) {
                    if (!event.isAutoRepeat)
                        pane.library.togglePreview()
                    event.accepted = true
                }
            }
            delegate: Rectangle {
                id: fileRow
                objectName: "sampleLibraryFileRow"
                required property int index
                required property string name
                required property string fileURL
                required property bool selected
                width: files.width
                height: 2.15 * pane.unit
                radius: pane.unit / 3
                color: fileRow.selected ? pane.colors.tabSelectedBackground : "transparent"
                Drag.active: rowDrag.active
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.mimeData: { "text/uri-list": fileRow.fileURL }
                DragHandler {
                    id: rowDrag
                    target: null
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: pane.paneSpacing
                    anchors.rightMargin: pane.paneSpacing
                    spacing: pane.paneSpacing / 2
                    Label {
                        text: "♪"
                        color: fileRow.selected ? pane.colors.selectionText : pane.colors.windowText
                    }
                    Label {
                        objectName: "sampleLibraryFileName"
                        Layout.fillWidth: true
                        verticalAlignment: Text.AlignVCenter
                        text: fileRow.name
                        elide: Text.ElideRight
                        color: fileRow.selected ? pane.colors.selectionText : pane.colors.windowText
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const row = fileRow.index
                        files.currentIndex = row
                        files.forceActiveFocus()
                        pane.library.clickFile(row)
                    }
                    onDoubleClicked: pane.library.activateFile(fileRow.index)
                }
            }
        }
        Label {
            objectName: "sampleLibraryError"
            Layout.fillWidth: true
            visible: text.length > 0
            text: pane.library.statusText
            wrapMode: Text.Wrap
            color: pane.colors.errorText
        }
        Button {
            objectName: "sampleLibraryOpen"
            Layout.fillWidth: true
            Layout.preferredHeight: 2.15 * pane.unit
            text: qsTr("Open File…")
            onClicked: pane.library.requestOpenFile()
        }
        Button {
            id: libraryAdvanced
            objectName: "sampleLibraryAdvanced"
            checkable: true
            text: qsTr("Advanced")
            contentItem: DisclosureLabel { control: libraryAdvanced; expanded: libraryAdvanced.checked }
        }
        ColumnLayout {
            Layout.fillWidth: true
            visible: libraryAdvanced.checked
            Button {
                objectName: "sampleLibraryRemove"
                text: qsTr("Remove Folder from List")
                enabled: pane.library.canRemove
                onClicked: {
                    files.currentIndex = -1
                    pane.library.removeSelectedRoot()
                    pane.alignFolderCursor()
                }
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: pane.colors.selectionEdge
        border.width: Math.max(2, Math.round(pane.unit / 6))
        visible: pane.folderDropHover && folders.count > 0
    }
    // Only folder drags respond; file rows dragged out of the pane pass over it silently.
    DropArea {
        anchors.fill: parent
        onEntered: drag => {
            pane.folderDropHover = drag.hasUrls && pane.library.areFolders(drag.getDataAsString("text/uri-list"))
            drag.accepted = pane.folderDropHover
        }
        onExited: pane.folderDropHover = false
        onDropped: drop => {
            const accepted = pane.folderDropHover
            pane.folderDropHover = false
            if (!accepted)
                return
            files.currentIndex = -1
            for (let i = 0; i < drop.urls.length; ++i)
                pane.library.addFolder("%1".arg(drop.urls[i]))
            pane.alignFolderCursor()
            drop.acceptProposedAction()
        }
    }
}
