import QtQuick
import QtQuick.Controls
import Porydaw.Ui

SplitView {
    id: dock
    objectName: "swiftDockColumn"
    orientation: Qt.Vertical
    required property var controller
    required property QtObject applicationSession
    required property var colors
    required property font applicationFont
    required property real baseFontPx
    // Normalized fraction of this split's height assigned to Songs. The shell
    // persists it as swiftDock/songsRatio the same way it persists
    // swiftDock/columnWidth; divider write-back clamps it so both panes keep
    // their fixed controls and at least one complete list row.
    property real songsRatio: 0.5

    readonly property real clampedRatio: Math.min(0.75, Math.max(0.25, songsRatio))
    // Fixed chrome plus one complete row in each pane; the SplitView enforces
    // these while dragging so neither pane collapses.
    readonly property real songsMinHeight: Math.ceil(baseFontPx * 7)
    readonly property real voiceMinHeight: Math.ceil(baseFontPx * 6.5)

    function noteSongsHeight() {
        if (dock.height <= 0)
            return
        const next = Math.min(0.75, Math.max(0.25, songsPane.height / dock.height))
        if (Math.abs(next - songsRatio) > 0.001)
            songsRatio = next
    }

    SongsPanel {
        id: songsPane
        objectName: "swiftSongsPanel"
        SplitView.fillWidth: true
        SplitView.fillHeight: true
        SplitView.preferredHeight: dock.height > 0 ? dock.height * dock.clampedRatio : 0
        SplitView.minimumHeight: dock.songsMinHeight
        controller: dock.controller
        colors: dock.colors
        applicationFont: dock.applicationFont
        baseFontPx: dock.baseFontPx
        onHeightChanged: dock.noteSongsHeight()
    }

    VoicegroupPanel {
        id: voicePane
        SplitView.fillWidth: true
        SplitView.fillHeight: true
        SplitView.minimumHeight: dock.voiceMinHeight
        applicationSession: dock.applicationSession
        controller: dock.applicationSession.voiceListController()
    }
}
