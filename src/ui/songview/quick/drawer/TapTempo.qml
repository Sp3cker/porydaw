// The Automation tap-tempo panel: the local surface of the page's Swift tap
// session.
//
// The page owner holds the whole session (`AutomationTapTempoSession`: the
// fixed interval ring, the clipped mean, the ready-to-commit rule and the
// tempo-scaled idle window). This file renders that state, delivers taps, a
// reset and the idle deadline back to the owner, and measures nothing: the
// monotonic reading is taken inside the owner at the tap's own event boundary,
// so no clock of this file's own exists and bare Space stays the window's
// transport.
//
// The panel is local rather than a modal: production keeps the plot live while a
// session accumulates, so it takes only its own input. It shows while the
// session is active and hides itself again when the session commits or resets;
// cancellation commits nothing.
pragma ComponentBehavior: Bound

import QtQuick

FocusScope {
    id: tapRoot

    objectName: "automationTapTempo"

    /// The page's published model for the current document. A `QtObject`-typed
    /// property cannot hold the bridged Swift object, so the page hands it over
    /// as the variant the rest of the composition uses for bridged owners.
    required property var model
    /// The page this panel belongs to, so it can place itself over the shared
    /// gutter column.
    property var hostPage: null

    /// The page's own publication decides visibility, exactly as the page's two
    /// modal surfaces read theirs.
    property bool showing: false

    readonly property bool ready: tapRoot.model !== null && tapRoot.model !== undefined
    readonly property int tapCount: tapRoot.ready ? tapRoot.model.tapTempoTapCount : 0
    readonly property int draftBpm: tapRoot.ready ? tapRoot.model.tapTempoDraftBpm : 0
    readonly property bool readyToCommit: tapRoot.ready ? tapRoot.model.tapTempoReady : false
    readonly property int idleCommitMs: tapRoot.ready
                                        ? Math.max(1, tapRoot.model.tapTempoIdleCommitMs) : 2000
    readonly property real baseFontPx: tapRoot.ready && tapRoot.model.baseFontPx > 0
                                       ? tapRoot.model.baseFontPx : 13
    readonly property real padding: Math.max(1, Math.round(tapRoot.baseFontPx / 2))
    readonly property real rowHeight: Math.max(1, Math.round(tapRoot.baseFontPx * 1.8))

    width: Math.max(Math.round(tapRoot.baseFontPx * 12), 4 * tapRoot.padding)
    height: 3 * tapRoot.rowHeight + 4 * tapRoot.padding
    x: tapRoot.hostPage ? Math.max(0, Math.min(tapRoot.hostPage.width - width,
                                               tapRoot.hostPage.plotOrigin + tapRoot.padding)) : 0
    y: 0
    visible: showing
    enabled: showing
    z: 20

    /// The idle deadline: one `tapTempoIdleElapsed` call lands the draft, exactly
    /// as production's tempo-scaled single-shot timer commits its session. Every
    /// tap restarts it, and a session that is no longer active stops it.
    Timer {
        id: idleCommit

        interval: tapRoot.idleCommitMs
        repeat: false
        running: false

        onTriggered: if (tapRoot.ready) tapRoot.model.tapTempoIdleElapsed()
    }

    Connections {
        target: tapRoot.model

        /// Every tap recomputes the draft, so the deadline follows the newest
        /// interval the owner published.
        function onTapTempoTapCountChanged() { tapRoot.restartDeadline() }
    }

    onShowingChanged: {
        if (showing)
            tapRoot.restartDeadline()
        else
            idleCommit.stop()
    }

    function restartDeadline() {
        if (!tapRoot.showing || !tapRoot.ready)
            return
        idleCommit.interval = tapRoot.idleCommitMs
        idleCommit.restart()
    }

    function tap() {
        if (tapRoot.ready)
            tapRoot.model.tapTempoTap()
        tapRoot.restartDeadline()
    }

    function reset() {
        idleCommit.stop()
        if (tapRoot.ready)
            tapRoot.model.resetTapTempo()
    }

    Keys.onEscapePressed: (event) => event.accepted = tapRoot.ready
                                      ? tapRoot.model.handleEscape() : false

    Rectangle {
        anchors.fill: parent
        color: "#F0F0F0"
        border.width: 1
        border.color: "#8C857F"
    }

    Column {
        anchors.centerIn: parent
        spacing: tapRoot.padding

        Text {
            objectName: "automationTapTempoDraft"
            anchors.horizontalCenter: parent.horizontalCenter
            text: tapRoot.tapCount >= 2 ? qsTr("%1 BPM").arg(tapRoot.draftBpm)
                                        : tapRoot.tapCount > 0 ? qsTr("…") : qsTr("Tap tempo")
            color: "#302C29"
            font.pixelSize: Math.max(1, Math.round(tapRoot.baseFontPx))
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
        }

        Text {
            objectName: "automationTapTempoCount"
            anchors.horizontalCenter: parent.horizontalCenter
            text: qsTr("%1 taps").arg(tapRoot.tapCount)
            color: "#57514C"
            font.pixelSize: Math.max(1, Math.round(tapRoot.baseFontPx))
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: tapRoot.padding

            Rectangle {
                id: tapPad

                objectName: "automationTapTempoPad"
                width: Math.round(tapRoot.baseFontPx * 5)
                height: tapRoot.rowHeight
                radius: 3
                color: tapPadPress.pressed ? "#B9E8EE" : "#E7E1DB"
                border.width: 1
                border.color: "#8C857F"
                activeFocusOnTab: true

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Tap")
                    color: "#302C29"
                    font.pixelSize: Math.max(1, Math.round(tapRoot.baseFontPx))
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                }

                Keys.onReturnPressed: (event) => {
                    tapRoot.tap()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    tapRoot.tap()
                    event.accepted = true
                }
                // Only plain Return/Enter are claimed: bare Space stays the
                // window's transport shortcut.
                Keys.onShortcutOverride: (event) => event.accepted =
                    event.key === Qt.Key_Return || event.key === Qt.Key_Enter

                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Tap")
                Accessible.description: tapRoot.readyToCommit
                                        ? qsTr("Draft tempo: %1 BPM").arg(tapRoot.draftBpm)
                                        : qsTr("Listening for tempo taps")
                Accessible.focusable: true
                Accessible.onPressAction: tapRoot.tap()

                MouseArea {
                    id: tapPadPress

                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onPressed: tapRoot.tap()
                }
            }

            Rectangle {
                id: resetControl

                objectName: "automationTapTempoReset"
                width: Math.round(tapRoot.baseFontPx * 5)
                height: tapRoot.rowHeight
                radius: 3
                color: resetPress.pressed ? "#D0C8C2" : "#E7E1DB"
                border.width: 1
                border.color: "#8C857F"
                activeFocusOnTab: true

                Text {
                    anchors.centerIn: parent
                    text: qsTr("Reset")
                    color: "#302C29"
                    font.pixelSize: Math.max(1, Math.round(tapRoot.baseFontPx))
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                }

                Keys.onReturnPressed: (event) => {
                    tapRoot.reset()
                    event.accepted = true
                }
                Keys.onEnterPressed: (event) => {
                    tapRoot.reset()
                    event.accepted = true
                }
                Keys.onShortcutOverride: (event) => event.accepted =
                    event.key === Qt.Key_Return || event.key === Qt.Key_Enter

                Accessible.role: Accessible.Button
                Accessible.name: qsTr("Reset tap tempo")
                Accessible.description: qsTr("Cancels the tap session without committing a tempo")
                Accessible.focusable: true
                Accessible.onPressAction: tapRoot.reset()

                MouseArea {
                    id: resetPress

                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onClicked: tapRoot.reset()
                }
            }
        }
    }
}
