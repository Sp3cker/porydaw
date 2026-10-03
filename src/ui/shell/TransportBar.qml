import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Porydaw.Ui
import PorydawApp
import Porydaw.Icons

Rectangle {
    id: bar
    objectName: "transportToolbar"
    required property TransportBarPresenter presenter
    required property QtObject shell
    required property int actionRevision
    required property QtObject colors
    required property int baseFontPx
    required property bool songAvailable
    onSongAvailableChanged: { if (presenter) presenter.refresh() }
    required property var typography
    required property var layoutSpaces
    readonly property int toolExtent: Math.round(Math.min(baseFontPx, 12) * 2.75)
    readonly property int inset: layoutSpaces.one
    implicitHeight: toolExtent + layoutSpaces.two - 2
    color: colors.chromeBackground
    readonly property int edgeMargin: Math.max(1, Math.round(baseFontPx / 6))
    readonly property int toolbarSeparatorExtent: 6
    // Invoking FontMetrics methods alone does not track a change to their font.
    readonly property real masterCaptionWidth: {
        captionMetrics.font
        return Math.ceil(captionMetrics.boundingRect(qsTr("Volume")).width)
            + layoutSpaces.two + layoutSpaces.one
    }
    readonly property real outputCaptionWidth: {
        captionMetrics.font
        return Math.ceil(captionMetrics.boundingRect(qsTr("Output")).width)
            + layoutSpaces.two + layoutSpaces.one
    }
    readonly property bool outputFits: width >= 2 * edgeMargin + 15 + 7 * toolExtent
        + Math.ceil(clockHintWidth) + 6 * inset
        + transportScaleSlot.Layout.preferredWidth + Math.round(baseFontPx * 2.25) + 2
        + masterCaptionWidth
        + Math.round(baseFontPx * 6 + 18)
        + outputCaptionWidth
        + Math.round(baseFontPx * 5 / 3) + 2 * Math.round(baseFontPx / 4)

    TextMetrics {
        id: clockMetrics
        font: Qt.font(bar.typography.bodyMono)
        text: "99:59.9 / 99:59.9"
    }
    readonly property real clockHintWidth: clockMetrics.advanceWidth
    FontMetrics { id: captionMetrics; font: Qt.font(bar.typography.body) }
    QtObject {
        id: inputAppearance
        property font font: Qt.font(bar.typography.body)
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
    function restoreOutputVolume() {
        presenter.restoreOutputVolume()
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
            typography: bar.typography
            label: qsTr("Go to Start"); icon: Icons.goToStart
            actionable: {
                bar.actionRevision
                return bar.shell.actionEnabled("transport.go_to_start")
            }
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.shell.activate("transport.go_to_start")
        }
        TransportButton {
            objectName: "transport.play"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            typography: bar.typography
            label: qsTr("Play"); icon: Icons.play
            actionable: {
                bar.actionRevision
                return bar.shell.actionEnabled("transport.play")
            }
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.shell.activate("transport.play")
        }
        TransportButton {
            objectName: "transport.pause"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            typography: bar.typography
            label: qsTr("Pause"); icon: Icons.pause
            actionable: {
                bar.actionRevision
                return bar.shell.actionEnabled("transport.pause")
            }
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.shell.activate("transport.pause")
        }
        TransportButton {
            objectName: "transport.stop"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            typography: bar.typography
            label: qsTr("Stop"); icon: Icons.stop
            actionable: {
                bar.actionRevision
                return bar.shell.actionEnabled("transport.stop")
            }
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.shell.activate("transport.stop")
        }
        TransportButton {
            objectName: "transport.loop"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            typography: bar.typography
            label: qsTr("Loop"); icon: Icons.loop
            checked: {
                bar.actionRevision
                return bar.shell.actionChecked("transport.loop")
            }
            actionable: {
                bar.actionRevision
                return bar.shell.actionEnabled("transport.loop")
            }
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.shell.activate("transport.loop")
        }
        TransportButton {
            objectName: "transport.follow-playhead"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            typography: bar.typography
            label: qsTr("Follow Playhead"); icon: Icons.followPlayhead
            checked: {
                bar.actionRevision
                return bar.shell.actionChecked("transport.follow_playhead")
            }
            actionable: {
                bar.actionRevision
                return bar.shell.actionEnabled("transport.follow_playhead")
            }
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.shell.activate("transport.follow_playhead")
        }
        TransportButton {
            objectName: "transport.resonance"
            colors: bar.colors; baseFontPx: bar.baseFontPx
            typography: bar.typography
            label: qsTr("Suppress Resonances"); icon: Icons.resonance
            checked: {
                bar.actionRevision
                bar.presenter.resonanceSuppression
                return bar.shell.actionChecked("transport.resonance")
            }
            actionable: {
                bar.actionRevision
                return bar.shell.actionEnabled("transport.resonance")
            }
            Layout.preferredWidth: bar.toolExtent
            Layout.preferredHeight: bar.toolExtent
            onActivated: bar.shell.activate("transport.resonance")
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
            font: Qt.font(bar.typography.bodyMono)
            renderType: Text.NativeRendering
            color: bar.colors.windowText
            text: bar.presenter.timeText
            elide: Text.ElideRight
            Accessible.role: Accessible.StaticText
            Accessible.description: qsTr("Measure and beat: %1. Loop: %2. Tempo: %3 BPM.")
                                        .arg(bar.presenter.measureText)
                                        .arg(bar.presenter.loopBounds)
                                        .arg(bar.presenter.tempo)
        }

        Item {
            id: transportScaleSlot
            objectName: "transportScaleSlot"
            readonly property int rootWidth: Math.round(bar.baseFontPx * 4 + 7)
            readonly property int typeWidth: Math.round(bar.baseFontPx * 13 + 22)
            readonly property int foldWidth: Math.round(bar.baseFontPx * 2.5 + 14)
            readonly property int comboHeight: bar.baseFontPx + 10
            Layout.maximumWidth: rootWidth + typeWidth + bar.toolExtent + foldWidth + 3
            Layout.preferredWidth: Layout.maximumWidth
            Layout.preferredHeight: bar.toolExtent

            Controls.ComboBox {
                id: scaleRoot
                objectName: "transportScaleRoot"
                x: 0
                y: Math.round((transportScaleSlot.height - height) / 2)
                width: transportScaleSlot.rootWidth
                height: transportScaleSlot.comboHeight
                model: ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
                currentIndex: bar.presenter.scaleRoot
                onActivated: index => bar.presenter.setScaleRoot(index)
                enabled: bar.songAvailable
                activeFocusOnTab: false
                font: Qt.font(bar.typography.body)
                Controls.ToolTip.text: qsTr("Scale root note")
                Accessible.name: qsTr("Scale root note")
                background: Rectangle {
                    color: bar.colors.buttonBackground
                    border.color: bar.colors.outline
                    radius: bar.inset / 2
                }
            }
            Controls.ComboBox {
                id: scaleType
                objectName: "transportScaleType"
                x: transportScaleSlot.rootWidth + 1
                y: scaleRoot.y
                width: transportScaleSlot.typeWidth
                height: transportScaleSlot.comboHeight
                model: bar.presenter.scaleNames
                currentIndex: bar.presenter.scaleType
                onActivated: index => bar.presenter.setScaleType(index)
                enabled: bar.songAvailable
                activeFocusOnTab: false
                font: Qt.font(bar.typography.body)
                Controls.ToolTip.text: qsTr("Scale type")
                Accessible.name: qsTr("Scale type")
                background: Rectangle {
                    color: bar.colors.buttonBackground
                    border.color: bar.colors.outline
                    radius: bar.inset / 2
                }
            }
            TransportButton {
                id: highlight
                objectName: "transportScaleHighlight"
                x: scaleType.x + scaleType.width + 1
                y: 0
                colors: bar.colors
                baseFontPx: bar.baseFontPx
                typography: bar.typography
                label: qsTr("Highlight")
                icon: Icons.flat
                checked: bar.presenter.scaleHighlight
                actionable: bar.songAvailable
                activeFocusOnTab: false
                onActivated: bar.presenter.setScaleHighlight(!bar.presenter.scaleHighlight)
            }
            Rectangle {
                id: fold
                objectName: "transportScaleFold"
                x: highlight.x + highlight.width + 1
                y: Math.round((transportScaleSlot.height - height) / 2)
                width: transportScaleSlot.foldWidth
                height: bar.baseFontPx + 11
                radius: bar.inset / 2
                color: bar.presenter.scaleFold ? bar.colors.buttonPressedBackground
                       : foldHover.hovered ? bar.colors.buttonHoverBackground : "transparent"
                enabled: bar.songAvailable
                activeFocusOnTab: false
                Accessible.role: Accessible.CheckBox
                Accessible.name: qsTr("Fold")
                Accessible.checked: bar.presenter.scaleFold
                Controls.ToolTip.text: qsTr("Fold piano roll to pitches used by the selected track")
                Text {
                    anchors.centerIn: parent
                    text: qsTr("Fold")
                    font: Qt.font(bar.typography.body)
                    color: !fold.enabled ? bar.colors.disabledText : bar.presenter.scaleFold ? bar.colors.buttonPressedText : bar.colors.buttonText
                }
                HoverHandler { id: foldHover }
                TapHandler {
                    enabled: fold.enabled
                    onTapped: bar.presenter.setScaleFold(!bar.presenter.scaleFold)
                }
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
            Layout.preferredWidth: bar.toolbarSeparatorExtent
            Layout.preferredHeight: bar.toolExtent
            color: bar.colors.separator
        }
        Text {
            objectName: "transportMasterVolumeCaption"
            Layout.preferredWidth: bar.masterCaptionWidth
            Layout.preferredHeight: bar.toolExtent
            verticalAlignment: Text.AlignVCenter
            leftPadding: bar.layoutSpaces.two
            rightPadding: bar.layoutSpaces.one
            enabled: bar.presenter.state !== 0
            font: Qt.font(bar.typography.body)
            color: enabled ? bar.colors.windowText : bar.colors.disabledText
            text: qsTr("Volume")
        }
        DragInput {
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
            Layout.preferredWidth: bar.toolbarSeparatorExtent
            Layout.preferredHeight: bar.toolExtent
            color: bar.colors.separator
            visible: bar.outputFits
        }
        Text {
            objectName: "transportOutputVolumeCaption"
            Layout.preferredWidth: bar.outputCaptionWidth
            Layout.preferredHeight: bar.toolExtent
            verticalAlignment: Text.AlignVCenter
            leftPadding: bar.layoutSpaces.two
            rightPadding: bar.layoutSpaces.one
            visible: bar.outputFits
            font: Qt.font(bar.typography.body)
            color: bar.colors.windowText
            text: qsTr("Output")
        }
        TransportOutputDial {
            colors: bar.colors
            baseFontPx: bar.baseFontPx
            value: bar.presenter.outputVolume
            hintService: bar.shell.mouseHints
            visible: bar.outputFits
            Accessible.description: qsTr("Does not change the song volume")
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
            onValueCommitted: percent => bar.presenter.commitOutputVolume(percent)
        }
        Item {
            visible: !bar.outputFits
            Layout.fillWidth: true
            Layout.minimumWidth: 0
        }
    }
}
