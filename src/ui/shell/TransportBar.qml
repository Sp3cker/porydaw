import QtQuick
import QtQuick.Layouts
import QtCore
import QtQuick.Controls.Basic as Basic
import Porydaw.Ui as Shared

Rectangle {
    id: bar
    objectName: "transportToolbar"
    required property QtObject presenter
    required property QtObject colors
    required property int baseFontPx
    required property bool songAvailable
    onSongAvailableChanged: { if (presenter) presenter.refresh() }
    required property font toolbarFont
    required property font clockFont
    readonly property int toolExtent: Math.round(Math.min(baseFontPx, 12) * 2.75)
    readonly property int inset: Math.max(1, Math.round(baseFontPx / 4))
    implicitHeight: toolExtent + Math.round(baseFontPx / 2) - 2
    color: colors.chromeBackground
    readonly property int edgeMargin: Math.max(1, Math.round(baseFontPx / 6))
    readonly property bool outputFits: width >= 2 * edgeMargin + 15 + 7 * toolExtent
        + Math.ceil(clockHintWidth) + 6 * inset
        + transportScaleSlot.Layout.preferredWidth + Math.round(baseFontPx * 2.25) + 2
        + captionMetrics.advanceWidth(qsTr("Volume")) + 3 * inset + Math.round(baseFontPx / 2)
        + Math.round(baseFontPx * 6 + 18)
        + captionMetrics.advanceWidth(qsTr("Output")) + 3 * inset + Math.round(baseFontPx / 2)
        + Math.round(baseFontPx * 5 / 3) + 2 * Math.round(baseFontPx / 4)

    TextMetrics {
        id: clockMetrics
        font: bar.clockFont
        text: "99:59.9 / 99:59.9"
    }
    readonly property real clockHintWidth: clockMetrics.advanceWidth
    FontMetrics { id: captionMetrics; font: bar.toolbarFont }
    QtObject {
        id: inputAppearance
        property font font: bar.toolbarFont
        property color background: bar.colors.buttonBackground
        property color text: bar.colors.buttonText
        property color outline: bar.colors.outline
        property color focus: bar.colors.focusOutline
        property real borderWidth: 1
        property real radius: bar.inset / 2
        property real horizontalPadding: bar.inset
        property real verticalPadding: 0
        property real dragThreshold: bar.inset
    }
    Loader {
        id: volumeSettingsLoader
        active: false
        sourceComponent: Settings { property int outputVolume: 100 }
    }
    function restoreOutputVolume() {
        volumeSettingsLoader.active = true
        presenter.setOutputVolume(volumeSettingsLoader.item.outputVolume)
    }

    Timer {
        interval: 100
        repeat: true
        running: bar.visible && bar.songAvailable
        onTriggered: bar.presenter.refresh()
    }

    RowLayout {
        id: controls
        spacing: Math.max(1, Math.round(bar.baseFontPx / 12))
        anchors.fill: parent
        anchors.leftMargin: bar.edgeMargin
        anchors.rightMargin: bar.edgeMargin

        TransportButton {
            objectName: "transport.go-to-start"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            label: qsTr("Go to Start"); symbol: "◀◀"
            actionable: bar.presenter.state !== 0
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.presenter.goToStart()
        }
        TransportButton {
            objectName: "transport.play"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            label: qsTr("Play"); symbol: "▶"; iconSource: "qrc:/icons/transport-play.svg"
            actionable: bar.presenter.state > 0 && bar.presenter.state !== 3
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.presenter.play()
        }
        TransportButton {
            objectName: "transport.pause"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            label: qsTr("Pause"); symbol: "Ⅱ"; iconSource: "qrc:/icons/transport-pause.svg"
            actionable: bar.presenter.state === 3
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.presenter.pause()
        }
        TransportButton {
            objectName: "transport.stop"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            label: qsTr("Stop"); symbol: "■"
            actionable: bar.presenter.state > 1
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.presenter.stop()
        }
        TransportButton {
            objectName: "transport.loop"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            label: qsTr("Loop"); symbol: "⟲"; iconSource: "qrc:/icons/transport-loop.svg"
            checked: bar.presenter.loopEnabled
            actionable: bar.presenter.state !== 0
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.presenter.setLoopEnabled(!bar.presenter.loopEnabled)
        }
        TransportButton {
            objectName: "transport.follow-playhead"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            label: qsTr("Follow Playhead"); symbol: "▶▶"; iconSource: "qrc:/icons/transport-follow.svg"
            checked: bar.presenter.followPlayhead
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.presenter.setFollowPlayhead(!bar.presenter.followPlayhead)
        }
        TransportButton {
            objectName: "transport.resonance"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            label: qsTr("Suppress Resonances"); symbol: "◖))"
            checked: bar.presenter.resonanceSuppression
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.presenter.setResonanceSuppression(!bar.presenter.resonanceSuppression)
        }
        Text {
            objectName: "transportTimeLabel"
            Layout.preferredWidth: Math.ceil(bar.clockHintWidth) + 6 * bar.inset
            Layout.minimumWidth: Layout.preferredWidth
            Layout.maximumWidth: Layout.preferredWidth
            Layout.preferredHeight: bar.toolExtent
            leftPadding: 3 * bar.inset
            rightPadding: 3 * bar.inset
            verticalAlignment: Text.AlignVCenter
            font: bar.clockFont
            renderType: Text.NativeRendering
            color: bar.colors.windowText
            text: bar.presenter.timeText
            elide: Text.ElideRight
            Accessible.role: Accessible.StaticText
            Accessible.description: qsTr("Measure and beat: %1. Loop: %2. Tempo: %3 BPM. Drag vertically to scrub tempo.")
                                        .arg(bar.presenter.measureText)
                                        .arg(bar.presenter.loopBounds)
                                        .arg(bar.presenter.tempo)
            Basic.ToolTip.text: qsTr("Tempo: %1 BPM. Drag vertically to scrub.").arg(bar.presenter.tempo)
            Basic.ToolTip.visible: clockHover.hovered && bar.presenter.state !== 0
            HoverHandler { id: clockHover }
            MouseArea {
                anchors.fill: parent
                enabled: bar.presenter.state !== 0
                property real pressedY: 0
                property int pressedTempo: 0
                onPressed: mouse => {
                    pressedY = mouse.y
                    pressedTempo = bar.presenter.tempo
                }
                onReleased: mouse => {
                    const distance = pressedY - mouse.y
                    if (Math.abs(distance) < bar.inset) return
                    const next = Math.max(20, Math.min(255,
                        pressedTempo + Math.trunc(distance * 0.5)))
                    if (next !== bar.presenter.tempo) bar.presenter.setTempo(next)
                }
            }
        }

        // transportScaleSlot: the later scale lane replaces this passive,
        // baseline-sized key-signature display with its four interactive controls.
        Item {
            id: transportScaleSlot
            objectName: "transportScaleSlot"
            readonly property int rootWidth: Math.round(bar.baseFontPx * 4 + 7)
            readonly property int typeWidth: Math.round(bar.baseFontPx * 13 + 22)
            readonly property int foldWidth: Math.round(bar.baseFontPx * 2.5 + 14)
            // Combo-box text metrics plus native chrome, measured at the widget's
            // two reference fonts; the scale-selector lane replaces this slot.
            Layout.maximumWidth: rootWidth + typeWidth + bar.toolExtent + foldWidth + 3
            Layout.preferredWidth: rootWidth + typeWidth + bar.toolExtent + foldWidth + 3
            Layout.preferredHeight: bar.toolExtent
            Text {
                objectName: "transportKeySignature"
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: bar.inset
                text: bar.presenter.keySignature
                width: transportScaleSlot.rootWidth
                font: bar.toolbarFont
                color: bar.presenter.state === 0 ? bar.colors.disabledText : bar.colors.windowText
                Accessible.role: Accessible.StaticText
                Accessible.name: qsTr("Key signature")
            }
            Text {
                anchors.left: parent.left
                anchors.leftMargin: transportScaleSlot.rootWidth + 1
                anchors.verticalCenter: parent.verticalCenter
                text: bar.presenter.keySignature.endsWith("m") ? qsTr("Minor") : qsTr("Major")
                font: bar.toolbarFont
                color: bar.presenter.state === 0 ? bar.colors.disabledText : bar.colors.windowText
            }
        }
        Item {
            objectName: "transportVolumeSpacer"
            Layout.fillWidth: bar.outputFits
            Layout.minimumWidth: Math.round(bar.baseFontPx * 2.25)
            Layout.maximumWidth: bar.outputFits ? bar.width
                                                : Math.round(bar.baseFontPx * 2.25)
            Layout.preferredHeight: bar.toolExtent
            Layout.preferredWidth: bar.outputFits ? -1 : Layout.minimumWidth
        }
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: bar.toolExtent
            color: bar.colors.separator
        }
        Text {
            objectName: "transportMasterVolumeCaption"
            Layout.preferredWidth: captionMetrics.advanceWidth(qsTr("Volume"))
                + 3 * bar.inset + Math.round(bar.baseFontPx / 2)
            Layout.preferredHeight: bar.toolExtent
            verticalAlignment: Text.AlignVCenter
            leftPadding: 2 * bar.inset
            font: bar.toolbarFont
            color: bar.presenter.state === 0 ? bar.colors.disabledText : bar.colors.windowText
            text: qsTr("Volume")
        }
        Shared.DragInput {
            objectName: "transportMasterVolume"
            inputObjectName: "transportMasterVolumeInput"
            accessibleName: qsTr("Master volume")
            accessibleDescription: qsTr("Song master volume saved with song settings")
            appearance: inputAppearance
            enabled: bar.presenter.state !== 0
            value: bar.presenter.masterVolume
            minimumValue: 0
            maximumValue: 127
            Layout.preferredWidth: Math.round(bar.baseFontPx * 6 + 18)
            Layout.preferredHeight: Math.round(bar.baseFontPx * 2.1)
            onValueCommitted: committed => bar.presenter.setMasterVolume(committed)
        }
        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: bar.toolExtent
            color: bar.colors.separator
            visible: bar.outputFits
        }
        Text {
            objectName: "transportOutputVolumeCaption"
            Layout.preferredWidth: captionMetrics.advanceWidth(qsTr("Output"))
                + 3 * bar.inset + Math.round(bar.baseFontPx / 2)
            Layout.preferredHeight: bar.toolExtent
            verticalAlignment: Text.AlignVCenter
            leftPadding: 2 * bar.inset
            visible: bar.outputFits
            font: bar.toolbarFont
            color: bar.colors.windowText
            text: qsTr("Output")
        }
        TransportOutputDial {
            colors: bar.colors
            baseFontPx: bar.baseFontPx
            value: bar.presenter.outputVolume
            visible: bar.outputFits
            Accessible.description: qsTr("Does not change the song volume")
            Basic.ToolTip.text: qsTr("Does not change the song volume")
            Basic.ToolTip.visible: hovered
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
            onValueCommitted: percent => {
                bar.presenter.setOutputVolume(percent)
                if (volumeSettingsLoader.status === Loader.Ready)
                    volumeSettingsLoader.item.outputVolume = percent
            }
        }
        // QToolBar still reserves its clipped output controls at large fonts.
        // Absorb the unavailable trailing space here rather than stretching
        // the buttons, clock or scale strip away from their widget positions.
        Item {
            visible: !bar.outputFits
            Layout.fillWidth: true
            Layout.minimumWidth: 0
        }
    }
}
