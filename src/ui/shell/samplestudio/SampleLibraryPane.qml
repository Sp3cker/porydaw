pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import PorydawStyle
import Porydaw.Ui
import PorydawApp
ColumnLayout {
    id: pane
    objectName: "sampleLibraryPanel"
    required property SampleLibraryModel library
    required property GridPalette colors
    required property Window studioWindow
    required property real unit
    required property real paneSpacing
    spacing: pane.paneSpacing
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

    RowLayout {
        Layout.fillWidth: true
        Label {
            Layout.fillWidth: true
            text: qsTr("Library")
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
        Layout.fillHeight: true
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
            height: 2 * pane.unit
            color: folderRow.selected ? pane.colors.tabSelectedBackground : pane.colors.windowBackground
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
                anchors.leftMargin: folderRow.depth * pane.unit
                spacing: pane.paneSpacing
                Item {
                    Layout.preferredWidth: pane.unit
                    Layout.fillHeight: true
                    Label {
                        anchors.centerIn: parent
                        visible: folderRow.hasChildren
                        text: folderRow.expanded ? "▾" : "▸"
                        color: folderRow.selected ? pane.colors.selectionText : pane.colors.windowText
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: folderRow.hasChildren
                        onClicked: pane.library.toggleFolder(folderRow.index)
                    }
                }
                Label {
                    objectName: "sampleLibraryFolderName"
                    Layout.fillWidth: true
                    text: folderRow.title
                    elide: Text.ElideRight
                    color: folderRow.selected ? pane.colors.selectionText : pane.colors.windowText
                }
            }
        }
    }
    Label { text: qsTr("Audio files"); color: pane.colors.windowText }
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
            required property bool selected
            width: files.width
            height: 2 * pane.unit
            color: fileRow.selected ? pane.colors.tabSelectedBackground : pane.colors.windowBackground
            Label {
                objectName: "sampleLibraryFileName"
                anchors.fill: parent
                anchors.leftMargin: pane.paneSpacing
                verticalAlignment: Text.AlignVCenter
                text: fileRow.name
                elide: Text.ElideRight
                color: fileRow.selected ? pane.colors.selectionText : pane.colors.windowText
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
