pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

Item {
    id: view
    objectName: "splitStudioInspector"
    required property KitStudioWorkflow workflow
    required property KitStudioPresenter editor
    required property GridPalette colors
    required property real unit
    required property real paneSpacing
    required property font captionFont
    readonly property list<string> envelopeStages: [qsTr("Attack"), qsTr("Decay"), qsTr("Sustain"), qsTr("Release")]
    function setEnvelopeStage(stage: int, value: real): void {
        const v = Math.round(value)
        const e = view.editor
        e.setZoneAdsr(stage === 0 ? v : e.selectedZoneAttack, stage === 1 ? v : e.selectedZoneDecay,
                      stage === 2 ? v : e.selectedZoneSustain, stage === 3 ? v : e.selectedZoneRelease)
    }

    Rectangle {
        anchors.fill: parent
        color: view.colors.menuBackground
    }
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: Math.max(1, Math.round(view.unit / 13))
        color: view.colors.outline
    }
    ScrollView {
        anchors.fill: parent
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: view.width - 2.5 * view.unit
            x: 1.25 * view.unit
            y: 1.25 * view.unit
            spacing: view.unit * 0.9
            StudioSection {
                title: qsTr("Sample rate"); colors: view.colors; captionFont: view.captionFont; unit: view.unit
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6.5 * view.unit; text: qsTr("File"); color: view.colors.secondaryText }
                    Label { Layout.fillWidth: true; text: view.editor.fileRateText; color: view.colors.windowText }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6.5 * view.unit; text: qsTr("Saved at"); color: view.colors.secondaryText }
                    ComboBox {
                        objectName: "splitStudioSavedRate"
                        Layout.fillWidth: true
                        model: view.editor.rateChoices
                        currentIndex: view.workflow.sourceRateIndex(view.editor.sourceRate)
                        onActivated: index => view.workflow.chooseSourceRate(index)
                    }
                }
            }
            StudioSection {
                title: qsTr("Selected key"); colors: view.colors; captionFont: view.captionFont; unit: view.unit
                visible: view.editor.selectedZone >= 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label {
                        text: view.workflow.keyName(view.editor.selectedZoneFirstKey)
                        font.pixelSize: 2 * view.unit
                        font.bold: true
                        color: view.colors.windowText
                    }
                    Rectangle {
                        Layout.preferredHeight: 1.7 * view.unit
                        Layout.preferredWidth: chipLabel.implicitWidth + 1.5 * view.unit
                        radius: 0.85 * view.unit
                        color: view.colors.buttonBackground
                        Label {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: "%1".arg(view.editor.selectedZoneFirstKey)
                            font: view.captionFont
                            color: view.colors.secondaryText
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6.5 * view.unit; text: qsTr("Slice"); color: view.colors.secondaryText }
                    Label {
                        Layout.fillWidth: true
                        text: view.editor.selectedZoneSampleName
                        color: view.colors.windowText
                        elide: Text.ElideRight
                    }
                }
            }
            StudioSection {
                title: qsTr("Pitch"); colors: view.colors; captionFont: view.captionFont; unit: view.unit
                visible: view.editor.selectedZone >= 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6.5 * view.unit; text: qsTr("Plays at"); color: view.colors.secondaryText }
                    NoteStepper {
                        Layout.fillWidth: true
                        colors: view.colors
                        unit: view.unit
                        format: view.workflow.noteFormat
                        keyValue: view.editor.selectedZoneRootKey
                        onStepped: value => view.editor.setZoneRootKey(value)
                    }
                }
            }
            StudioSection {
                title: qsTr("Pan"); colors: view.colors; captionFont: view.captionFont; unit: view.unit
                visible: view.editor.selectedZone >= 0 && view.editor.selectedZonePanEnabled
                Slider {
                    Layout.fillWidth: true
                    from: -64
                    to: 63
                    stepSize: 1
                    value: view.editor.selectedZonePan
                    Accessible.name: qsTr("Pan")
                    onMoved: view.editor.setZonePan(Math.round(value))
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { text: qsTr("L"); color: view.colors.secondaryText }
                    Item { Layout.fillWidth: true }
                    Label { text: "%1".arg(view.editor.selectedZonePan); color: view.colors.windowText }
                    Item { Layout.fillWidth: true }
                    Label { text: qsTr("R"); color: view.colors.secondaryText }
                }
            }
            StudioSection {
                title: qsTr("Envelope"); colors: view.colors; captionFont: view.captionFont; unit: view.unit
                visible: view.editor.selectedZone >= 0
                Repeater {
                    model: view.envelopeStages
                    RowLayout {
                        id: stage
                        required property int index
                        required property string modelData
                        readonly property int level: index === 0 ? view.editor.selectedZoneAttack
                            : index === 1 ? view.editor.selectedZoneDecay
                            : index === 2 ? view.editor.selectedZoneSustain : view.editor.selectedZoneRelease
                        Layout.fillWidth: true
                        spacing: view.paneSpacing
                        Label { Layout.preferredWidth: 6 * view.unit; text: stage.modelData; color: view.colors.secondaryText }
                        Slider {
                            Layout.fillWidth: true
                            from: 0
                            to: 255
                            stepSize: 1
                            value: stage.level
                            Accessible.name: stage.modelData
                            onMoved: view.setEnvelopeStage(stage.index, value)
                        }
                        Label { Layout.preferredWidth: 3 * view.unit; horizontalAlignment: Text.AlignRight; text: "%1".arg(stage.level); color: view.colors.windowText }
                    }
                }
            }
            Button {
                Layout.fillWidth: true
                text: qsTr("Remove from Key")
                palette.buttonText: view.colors.errorText
                visible: view.editor.selectedZone >= 0
                onClicked: view.editor.deleteZone(view.editor.selectedZone)
            }
            Item { Layout.fillHeight: true }
        }
    }
}
