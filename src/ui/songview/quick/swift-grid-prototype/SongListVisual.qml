// DISPOSABLE static Songlist reference — merge-day geometry/color/strings, not behavior.
// Mirrors src/ui/songlistpanel.{h,cpp} layout and strings. Search, category, and
// sort controls are visual only: they do not filter (production filtering lives
// in songlistpanel.cpp rebuildList/matchesFilters and is proven by
// src/checks/workspace/session.cpp). No controller coupling: no
// SongTabsController/SongRegistry/ProjectService reference, no emitted signals.
// Deliberately NOT referenced by Main.qml or CMakeLists.txt so the frozen
// prototype smoke is untouched. Delete when the real ProjectService-backed list
// lands in swift-qml-grid; do not wire production behavior through this file.
// Deletion trigger: drop this file once the grid-worktree list exists, or after
// ~2 weeks even without one — the frozen visual baselines
// (src/checks/fixtures/visual/*/songlist/) remain the adjudicating oracles.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

pragma ComponentBehavior: Bound

FocusScope {
    id: root

    required property font font
    required property real baseFontPx
    required property var gridPalette

    // Representative rows covering every production row state: registered,
    // unregistered stray, partially registered.
    property var songs: [
        { songId: 101, label: "mus_route101", registered: true, gaps: [] },
        { songId: 102, label: "mus_rival", registered: true, gaps: [] },
        { songId: 201, label: "se_door", registered: true, gaps: [] },
        { songId: 202, label: "se_fanfare", registered: false, gaps: [] },
        { songId: 301, label: "ph_ah", registered: true, gaps: ["song_table.inc"] },
        { songId: 402, label: "stray", registered: false, gaps: [] }
    ]
    // Loaded song, shown selected. Local visual state only.
    property int currentSongId: 101

    readonly property int pad: Math.max(1, Math.round(baseFontPx * 0.5))
    readonly property color warnColor: "#C08030"
    readonly property color rowText: gridPalette.windowText
    readonly property color dimText: gridPalette.secondaryText
    readonly property color selectedRow: gridPalette.tabSelectedBackground

    // Production row-text rule (songlistpanel.cpp rebuildList): label plus the
    // registration suffix. Pure string rule, kept so the suffix styling stays visible.
    function rowTextFor(song) {
        if (!song.registered)
            return song.label + qsTr("  ⚠ not registered");
        if (song.gaps.length > 0)
            return song.label + qsTr("  ⚠ not fully registered");
        return song.label;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: root.pad

        TextField {
            objectName: "songListSearch"
            Layout.fillWidth: true
            font: root.font
            placeholderText: qsTr("Filter songs (Ctrl+F)")
            // Bare Space stays the window play/pause toggle: never accepted here.
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: root.pad

            ComboBox {
                objectName: "songListCategory"
                Layout.fillWidth: true
                font: root.font
                // Static snapshot of production category format:
                // "All (N)", friendly prefix names with counts, "Other (N)".
                model: ["All (6)", qsTr("Music (mus_) (2)"), qsTr("Sound effects (se_) (2)"), qsTr("Other (2)")]
            }
            ComboBox {
                objectName: "songListSort"
                font: root.font
                model: [qsTr("ID order"), qsTr("A–Z")]
                ToolTip.text: qsTr("Sort by song ID or alphabetically")
                ToolTip.visible: hovered
            }
        }

        ListView {
            id: songList
            objectName: "songList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.songs
            delegate: ItemDelegate {
                id: rowDelegate
                required property var modelData
                required property int index
                width: songList.width
                font: root.font
                highlighted: modelData.songId === root.currentSongId
                text: root.rowTextFor(modelData)
                ToolTip.visible: hovered && (modelData.gaps.length > 0 || !modelData.registered)
                ToolTip.text: !modelData.registered ? qsTr("This song's .mid exists but song_table.inc has no entry. Right-click → Register Song.") : qsTr("This song is missing its entry in: %1. Right-click → Register Song completes it.").arg(modelData.gaps.join(", "))
                contentItem: Text {
                    text: rowDelegate.text
                    font: root.font
                    elide: Text.ElideRight
                    renderType: Text.NativeRendering
                    color: !rowDelegate.modelData.registered || rowDelegate.modelData.gaps.length > 0 ? root.warnColor : root.rowText
                }
                background: Rectangle {
                    visible: rowDelegate.highlighted
                    color: root.selectedRow
                }
                onClicked: {
                    songList.currentIndex = index;
                    root.currentSongId = modelData.songId;
                }
                onDoubleClicked: root.currentSongId = modelData.songId;
            }

            // Visual-only context menu: labels mirror production, actions are local no-ops.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onPressed: mouse => {
                    const at = songList.indexAt(mouse.x, songList.contentY + mouse.y);
                    if (at < 0)
                        return;
                    songList.currentIndex = at;
                    songMenu.song = songList.model[at];
                    songMenu.popup();
                }
            }

            Menu {
                id: songMenu
                property var song
                MenuItem {
                    text: qsTr("Open")
                    onTriggered: root.currentSongId = songMenu.song.songId
                }
                MenuItem {
                    text: qsTr("Open in New Tab")
                    onTriggered: root.currentSongId = songMenu.song.songId
                }
                MenuSeparator {}
                MenuItem {
                    text: qsTr("Register Song")
                    enabled: songMenu.song !== undefined && (!songMenu.song.registered || songMenu.song.gaps.length > 0)
                }
                MenuItem {
                    text: qsTr("Delete Song…")
                }
            }
        }

        Label {
            objectName: "songListCount"
            font: root.font
            color: root.dimText
            text: qsTr("%1 songs").arg(root.songs.length)
        }
    }
}
