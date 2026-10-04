pragma ComponentBehavior: Bound
import QtQuick
import PorydawStyle
import Porydaw.Ui
import PorydawApp

SplitView {
    id: dock
    objectName: "swiftDockColumn"
    orientation: Qt.Vertical
    required property SongDockController controller
    required property ApplicationSession applicationSession
    required property var colors
    readonly property real baseFontPx: dock.applicationSession.baseFontPx
    // Normalized usable-height fraction persisted as swiftDock/songsRatio.
    // Divider write-back keeps both panes' controls and one complete list row.
    property real songsRatio: 0.5

    readonly property real clampedRatio: Math.min(0.75, Math.max(0.25, dock.songsRatio))
    // Carve the handle out of the usable height so layout cannot ratchet the
    // persisted ratio down on successive passes.
    readonly property real handleH: 6
    // Fixed chrome plus one complete row in each pane; the SplitView enforces
    // these while dragging so neither pane collapses.
    readonly property real songsMinHeight: Math.ceil(dock.baseFontPx * 7)
    readonly property real voiceMinHeight: Math.ceil(dock.baseFontPx * 6.5)

    function noteSongsHeight(): void {
        const avail = songsWrap.height + voiceWrap.height
        if (dock.height <= 0 || avail <= 0)
            return
        // Only divider drags have settled pane heights inside a constant dock;
        // initial layout and resizing must not rewrite the restored ratio.
        const slack = dock.height - avail
        if (slack < 4 || slack > 8)
            return
        if (songsWrap.height <= dock.songsMinHeight + 0.5
                || voiceWrap.height <= dock.voiceMinHeight + 0.5)
            return
        const next = Math.min(0.75, Math.max(0.25, songsWrap.height / avail))
        if (Math.abs(next - dock.songsRatio) > 0.001)
            dock.songsRatio = next
    }

    // Plain clipped wrappers own split geometry without leaking panel implicit
    // heights; the panels keep standalone geometry and scroll their own lists.
    Item {
        id: songsWrap
        SplitView.fillWidth: true
        SplitView.fillHeight: true
        SplitView.preferredHeight: dock.height > dock.handleH
            ? (dock.height - dock.handleH) * dock.clampedRatio : 0
        SplitView.minimumHeight: dock.songsMinHeight
        clip: true
        onHeightChanged: dock.noteSongsHeight()

        SongsPanel {
            objectName: "swiftSongsPanel"
            anchors.fill: parent
            controller: dock.controller
            colors: dock.colors
            applicationSession: dock.applicationSession
        }
    }

    Item {
        id: voiceWrap
        SplitView.fillWidth: true
        SplitView.fillHeight: true
        SplitView.preferredHeight: dock.height > dock.handleH
            ? (dock.height - dock.handleH) * (1 - dock.clampedRatio) : 0
        SplitView.minimumHeight: dock.voiceMinHeight
        clip: true
        onHeightChanged: dock.noteSongsHeight()

        VoicegroupPanel {
            anchors.fill: parent
            applicationSession: dock.applicationSession
            controller: dock.applicationSession.voiceListController()
        }
    }
}
