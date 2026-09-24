import QtQuick
import QtQuick.Controls

SplitView {
    id: dock
    objectName: "swiftDockColumn"
    orientation: Qt.Vertical
    required property var controller
    required property QtObject applicationSession
    required property var colors
    required property font applicationFont
    required property real baseFontPx
    // Normalized fraction of this split's usable height assigned to Songs.
    // The shell persists it as swiftDock/songsRatio the same way it persists
    // swiftDock/columnWidth; divider write-back clamps it so both panes keep
    // their fixed controls and at least one complete list row.
    property real songsRatio: 0.5

    readonly property real clampedRatio: Math.min(0.75, Math.max(0.25, songsRatio))
    // Default SplitView handle thickness. Both preferred heights are carved
    // out of the usable height (dock minus handle): preferred sizes that sum
    // past the available space make the splitter short the first pane by the
    // handle on every pass, and the write-back below would ratchet the saved
    // ratio down to its clamp.
    readonly property real handleH: 6
    // Fixed chrome plus one complete row in each pane; the SplitView enforces
    // these while dragging so neither pane collapses.
    readonly property real songsMinHeight: Math.ceil(baseFontPx * 7)
    readonly property real voiceMinHeight: Math.ceil(baseFontPx * 6.5)

    function noteSongsHeight() {
        const avail = songsWrap.height + voiceWrap.height
        if (dock.height <= 0 || avail <= 0)
            return
        // A divider drag resizes both panes inside a constant dock height, so
        // the heights always account for the whole dock minus the handle. A
        // mid-layout frame (growth, resize, initial settle) leaves stale pane
        // heights behind and must never rewrite the restored ratio.
        const slack = dock.height - avail
        if (slack < 4 || slack > 8)
            return
        if (songsWrap.height <= dock.songsMinHeight + 0.5
                || voiceWrap.height <= dock.voiceMinHeight + 0.5)
            return
        const next = Math.min(0.75, Math.max(0.25, songsWrap.height / avail))
        if (Math.abs(next - songsRatio) > 0.001)
            songsRatio = next
    }

    // Plain wrappers own the split geometry (SplitView never sizes an item
    // below its content implicit height, so the panels' full content heights
    // must not leak into the divider math) and clip overflow; the panels keep
    // their standalone geometry inside and scroll their lists themselves.
    Item {
        id: songsWrap
        SplitView.fillWidth: true
        SplitView.fillHeight: true
        SplitView.preferredHeight: dock.height > handleH
            ? (dock.height - handleH) * dock.clampedRatio : 0
        SplitView.minimumHeight: dock.songsMinHeight
        clip: true
        onHeightChanged: dock.noteSongsHeight()

        SongsPanel {
            objectName: "swiftSongsPanel"
            anchors.fill: parent
            controller: dock.controller
            colors: dock.colors
            applicationFont: dock.applicationFont
            baseFontPx: dock.baseFontPx
        }
    }

    Item {
        id: voiceWrap
        SplitView.fillWidth: true
        SplitView.fillHeight: true
        SplitView.preferredHeight: dock.height > handleH
            ? (dock.height - handleH) * (1 - dock.clampedRatio) : 0
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
