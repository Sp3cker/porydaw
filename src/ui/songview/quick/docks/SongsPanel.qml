pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import Porydaw.Ui

FocusScope {
    id: root
    objectName: "swiftSongsPanel"
    required property var controller
    required property var colors
    required property font applicationFont
    required property real baseFontPx
    readonly property var songs: controller.songListPresenter()
    readonly property int pad: Math.max(1, Math.round(baseFontPx * 0.25))

    function focusSearch() {
        search.forceActiveFocus()
        search.selectAll()
    }

    Connections {
        target: root.songs
        function onSearchFocusRequestChanged() { root.focusSearch() }
        function onSearchTextChanged() {
            if (search.text !== root.songs.searchText)
                search.text = root.songs.searchText
        }
        function onRevealRequestChanged() {
            for (let i = 0; i < list.count; ++i) {
                if (root.songs.songId(i) === root.songs.revealSongId) {
                    list.positionViewAtIndex(i, ListView.Center)
                    return
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.pad

        TextField {
            id: search
            objectName: "songListSearch"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.ceil(root.baseFontPx * (1.5 + 1 / 3))
            font: root.applicationFont
            placeholderText: qsTr("Filter songs (Ctrl+F)")
            text: root.songs.searchText
            onTextEdited: root.songs.updateSearch(text)
            onAccepted: root.songs.activateSelection()
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Up || event.key === Qt.Key_Down
                    || event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                    const page = Math.max(1, Math.floor(list.height / Math.max(1, root.baseFontPx * 1.4)))
                    const direction = event.key === Qt.Key_Up ? -1 : event.key === Qt.Key_Down ? 1
                                      : event.key === Qt.Key_PageUp ? -page : page
                    list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + direction))
                    const songId = root.songs.songId(list.currentIndex)
                    if (songId >= 0)
                        root.songs.selectSong(songId)
                    event.accepted = true
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: root.pad

            ComboBox {
                id: category
                property int categoryModelRevision: 0
                objectName: "songListCategory"
                Layout.fillWidth: true
                Layout.preferredHeight: search.height
                font: root.applicationFont
                model: root.songs.categories
                displayText: {
                    categoryModelRevision
                    return root.songs.categoryName(currentIndex)
                }
                delegate: ItemDelegate {
                    required property var model
                    required property int index
                    width: category.width
                    font: root.applicationFont
                    text: model.display.name
                    onClicked: {
                        const selectedIndex = index
                        root.songs.selectCategory(selectedIndex)
                        category.currentIndex = selectedIndex
                        category.popup.close()
                    }
                }
                onActivated: index => {
                    if (root.songs.categoryIndex !== index)
                        root.songs.selectCategory(index)
                }
                Component.onCompleted: currentIndex = root.songs.categoryIndex
                Connections {
                    target: root.songs
                    function onCategoryIndexChanged() { category.currentIndex = root.songs.categoryIndex }
                }
                Connections {
                    target: root.songs.categories
                    function onModelReset() { ++category.categoryModelRevision }
                }
            }
            ComboBox {
                id: sort
                objectName: "songListSort"
                Layout.preferredWidth: root.baseFontPx * 7.25
                Layout.preferredHeight: search.height
                font: root.applicationFont
                model: [qsTr("ID order"), qsTr("A–Z")]
                currentIndex: root.songs.sortIndex
                onActivated: index => root.songs.selectSort(index)
                ToolTip.text: qsTr("Sort by song ID or alphabetically")
                ToolTip.visible: hovered
                Connections {
                    target: root.songs
                    function onSortIndexChanged() { sort.currentIndex = root.songs.sortIndex }
                }
            }
        }

        ListView {
            id: list
            objectName: "songList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.songs.rows
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: false
            currentIndex: -1
            Rectangle {
                anchors.fill: parent
                z: -1
                color: root.colors.menuBackground
                border.color: root.colors.outline
                border.width: 1
            }
            delegate: ItemDelegate {
                id: row
                required property var model
                required property int index
                readonly property var song: model.display
                objectName: song ? "songListRow_" + song.songId : ""
                x: 1
                width: list.width - 2
                height: Math.ceil(root.baseFontPx * (song && song.warning ? 11 / 8 : 9 / 8))
                highlighted: !!song && song.selected
                padding: 0
                onClicked: {
                    if (!song)
                        return
                    root.songs.selectSong(song.songId)
                    list.currentIndex = index
                }
                onDoubleClicked: {
                    if (song)
                        root.songs.activateSong(song.songId)
                }
                contentItem: Text {
                    id: label
                    text: row.song ? row.song.text : ""
                    font: root.applicationFont
                    renderType: Text.NativeRendering
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    color: row.highlighted ? root.colors.selectionText
                           : row.song && row.song.warning ? root.colors.warningText
                                                          : root.colors.windowText
                }
                background: Rectangle {
                    visible: row.highlighted
                    color: root.colors.selectionRing
                }
                ToolTip.visible: hovered && !!song && song.warning
                                 && song.registrationGapText.length > 0
                ToolTip.text: song ? qsTr("This song is missing its entry in: %1. Right-click → Register Song completes it.").arg(song.registrationGapText) : ""
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: mouse => {
                        const clickedSongId = row.song?.songId ?? -1
                        if (clickedSongId < 0)
                            return
                        const clickedIndex = row.index
                        const position = mapToItem(Overlay.overlay, mouse.x, mouse.y)
                        songMenu.songId = clickedSongId
                        songMenu.canRegister = root.songs.canRegister(clickedSongId)
                        root.songs.selectSong(clickedSongId)
                        list.currentIndex = clickedIndex
                        songMenu.x = Math.max(0, Math.min(position.x, Overlay.overlay.width - songMenu.width))
                        songMenu.y = Math.max(0, Math.min(position.y, Overlay.overlay.height - songMenu.height))
                        songMenu.open()
                    }
                }
            }
            Keys.onReturnPressed: root.songs.activateSelection()
            Keys.onEnterPressed: root.songs.activateSelection()
        }

        Label {
            objectName: "songListCount"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.ceil(root.baseFontPx * 1.15)
            font: root.applicationFont
            color: root.colors.secondaryText
            text: root.songs.countText
        }
    }

    Basic.Popup {
        id: songMenu
        objectName: "songListContextMenu"
        parent: Overlay.overlay
        property int songId: -1
        property bool canRegister: false
        padding: 0
        width: Math.ceil(root.baseFontPx * 15)
        height: Math.ceil(root.baseFontPx * 1.7) * 4 + root.pad
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Item {}
        contentItem: QuickMenuPanel {
            id: menuPanel
            host: songMenu
            rootLevel: true
            rowObjectNamePrefix: "songs.menu."
            menuModel: [
                { actionId: "open", text: qsTr("Open") },
                { actionId: "newTab", text: qsTr("Open in New Tab") },
                { separator: true, text: "" },
                { actionId: "register", text: qsTr("Register Song"), enabled: songMenu.canRegister },
                { actionId: "delete", text: qsTr("Delete Song…") }
            ]
            menuWidth: songMenu.width
            menuHeight: songMenu.height
            rowHeight: Math.ceil(root.baseFontPx * 1.7)
            textX: root.baseFontPx
            textRight: songMenu.width - root.baseFontPx
            appearance: ({ background: root.colors.menuBackground,
                           outline: root.colors.outline,
                           text: root.colors.windowText,
                           disabledText: root.colors.secondaryText,
                           hoverBackground: root.colors.menuHoverBackground,
                           hoverText: root.colors.windowText,
                           separator: root.colors.outline,
                           font: root.applicationFont })
        }
        function hoverRow(panel, index) { panel.highlightedRow = index }
        function activateRow(panel, index) {
            const chosenId = songId
            switch (index) {
            case 0: root.songs.requestOpen(chosenId); break
            case 1: root.songs.requestOpenInNewTab(chosenId); break
            case 3: root.songs.requestRegister(chosenId); break
            case 4: root.songs.requestDelete(chosenId); break
            }
            close()
        }
    }
}
