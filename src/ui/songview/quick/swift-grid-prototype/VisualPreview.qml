// DISPOSABLE manual preview host for the static visual references
// (SongListVisual.qml, VoicegroupVisual.qml) — not part of the prototype smoke,
// Main.qml, or CMakeLists.txt. Open with qmlscene and flip `page` between
// "songlist" and "voicegroup" to eyeball merge-day geometry/colors. Delete with
// the Visual files when the real source-backed panels land.
import QtQuick
import QtQuick.Controls

pragma ComponentBehavior: Bound
ApplicationWindow {
    id: preview
    visible: true

    // "songlist" or "voicegroup".
    property string page: "songlist"

    width: page === "voicegroup" ? 420 : 340
    height: page === "voicegroup" ? 680 : 640
    title: page === "voicegroup" ? "Voicegroup visual-only preview (DISPOSABLE)" : "SongList visual-only preview (DISPOSABLE)"
    color: "#C9C1BB"

    readonly property real baseFontPx: 13
    readonly property var gridPalette: ({
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

    Label {
        id: fontSource
        visible: false
        font.pixelSize: Math.round(preview.baseFontPx * 1.125)
    }

    Loader {
        anchors.fill: parent
        sourceComponent: preview.page === "voicegroup" ? voicegroupPage : songListPage
    }

    Component {
        id: songListPage
        SongListVisual {
            font: fontSource.font
            baseFontPx: preview.baseFontPx
            gridPalette: preview.gridPalette
        }
    }

    Component {
        id: voicegroupPage
        VoicegroupVisual {
            font: fontSource.font
            baseFontPx: preview.baseFontPx
            gridPalette: preview.gridPalette
        }
    }
}
