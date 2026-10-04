pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

DialogWindow {
    id: dialog
    objectName: "sampleStudioDialog"
    required property SampleStudioWorkflow workflow
    required property ApplicationSession applicationSession
    required property SampleStudioPresenter editor
    required property SampleLoopTools tools
    required property SampleWaveformModel waveformModel
    required property SampleStudioAudition audition
    readonly property real unit: applicationSession.baseFontPx
    readonly property real spacing: applicationSession.layoutSpaces.one
    modality: Qt.ApplicationModal
    width: 75 * unit
    height: 53.33 * unit
    minimumWidth: 40 * unit
    minimumHeight: 23.33 * unit
    title: editor.windowTitle
    font: applicationSession.typographyFonts.body
    onClosing: workflow.cancel()

    Shortcut { sequences: [StandardKey.Undo]; context: Qt.WindowShortcut; onActivated: dialog.editor.undo() }
    Shortcut { sequences: [StandardKey.Redo]; context: Qt.WindowShortcut; onActivated: dialog.editor.redo() }
    Timer { interval: 33; repeat: true; running: dialog.audition.playing; onTriggered: dialog.audition.tick() }
    function handleSpace(event: KeyEvent): void {
        if (event.key === Qt.Key_Space && event.modifiers === Qt.NoModifier) {
            if (!event.isAutoRepeat)
                dialog.audition.toggle()
            event.accepted = true
        }
    }
    component AuditionTextField: TextField {
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => dialog.handleSpace(event)
    }
    component AuditionSpinBox: SpinBox {
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => dialog.handleSpace(event)
    }
    component AuditionComboBox: ComboBox {
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => dialog.handleSpace(event)
    }
    component AuditionButton: Button {
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => dialog.handleSpace(event)
    }
    component AuditionCheckBox: CheckBox {
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => dialog.handleSpace(event)
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => dialog.handleSpace(event)
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: dialog.spacing
        spacing: dialog.spacing
        SplitView {
            id: split
            objectName: "sampleStudioSplitter"
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Vertical
            SampleWaveform {
                id: waveform
                objectName: "sampleStudioWaveform"
                SplitView.fillWidth: true
                SplitView.fillHeight: true
                SplitView.minimumHeight: 6 * dialog.unit
                model: dialog.waveformModel
                colors: dialog.colors
                baseFontPx: dialog.unit
            }
            ScrollView {
                id: controlScroll
                objectName: "sampleStudioControlsScroll"
                SplitView.fillWidth: true
                SplitView.preferredHeight: 26 * dialog.unit
                SplitView.minimumHeight: 6 * dialog.unit
                clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: controlScroll.availableWidth
                    spacing: dialog.spacing
                    RowLayout {
                        Label { text: qsTr("Name:"); color: dialog.colors.windowText }
                        AuditionTextField {
                            id: nameField
                            objectName: "sampleStudioName"
                            Layout.fillWidth: true
                            text: dialog.editor.sampleName
                            readOnly: dialog.editor.nameReadOnly
                            onTextEdited: dialog.editor.setSampleName(text)
                        }
                        Label { text: dialog.editor.nameStatus; color: dialog.colors.windowText }
                    }
                    AuditionCheckBox {
                        objectName: "sampleStudioLoop"
                        text: qsTr("Loop")
                        checked: dialog.editor.loopOn
                        onToggled: dialog.tools.setLoopEnabled(checked)
                    }
                    ColumnLayout {
                        visible: dialog.tools.loopBodyVisible
                        RowLayout {
                            Label {
                                visible: dialog.tools.seamBadgeVisible
                                text: dialog.tools.seamBadgeText
                                color: dialog.tools.seamBadgeSeverity === 0 ? dialog.colors.windowText
                                    : dialog.tools.seamBadgeSeverity === 1 ? dialog.colors.warningText
                                    : dialog.colors.errorText
                            }
                            AuditionButton { text: qsTr("Try another loop"); enabled: dialog.tools.canTryAnother; onClicked: dialog.tools.tryAnotherLoop() }
                            AuditionButton { text: qsTr("Refine"); onClicked: dialog.tools.refineLoop() }
                            Label { text: dialog.tools.suggestStatus; color: dialog.colors.windowText }
                        }
                        RowLayout {
                            Label { text: qsTr("Loop range:"); color: dialog.colors.windowText }
                            AuditionSpinBox { from: 0; to: dialog.editor.sourceFrameCount; value: dialog.editor.loopStart; onValueModified: dialog.editor.setLoopStart(value) }
                            Label { text: qsTr("to"); color: dialog.colors.windowText }
                            AuditionSpinBox { from: 0; to: dialog.editor.sourceFrameCount; value: dialog.editor.loopEnd; onValueModified: dialog.editor.setLoopEnd(value) }
                        }
                        AuditionCheckBox { text: qsTr("Smooth seam"); checked: dialog.tools.crossfadeOn; onToggled: dialog.tools.setCrossfade(checked) }
                    }
                    Label { objectName: "sampleStudioSource"; text: dialog.editor.sourceLine; color: dialog.colors.windowText }
                    RowLayout {
                        Label { text: qsTr("Base key:"); color: dialog.colors.windowText }
                        AuditionTextField {
                            id: baseKeyField
                            objectName: "sampleStudioBaseKey"
                            text: dialog.editor.baseKeyText
                            onEditingFinished: dialog.editor.setBaseKeyText(text)
                        }
                        AuditionButton {
                            text: dialog.tools.pitchApplyText
                            visible: dialog.tools.pitchApplyVisible
                            onClicked: dialog.tools.applyDetectedPitch()
                        }
                    }
                    RowLayout {
                        Label { text: qsTr("Target rate:"); color: dialog.colors.windowText }
                        AuditionComboBox {
                            id: rate
                            objectName: "sampleStudioRate"
                            editable: true
                            model: dialog.editor.rateChoices
                            currentIndex: dialog.editor.rateIndex
                            onActivated: index => dialog.editor.chooseRate(index)
                            onAccepted: dialog.editor.commitRateText(editText)
                            onActiveFocusChanged: {
                                if (!activeFocus && editText !== dialog.editor.rateText)
                                    dialog.editor.commitRateText(editText)
                            }
                        }
                    }
                    RowLayout {
                        AuditionButton {
                            objectName: "sampleStudioPlay"
                            text: dialog.audition.playText
                            enabled: dialog.audition.available
                            onClicked: dialog.audition.toggle()
                        }
                        Label { text: qsTr("Key:"); color: dialog.colors.windowText }
                        AuditionTextField {
                            id: auditionKey
                            objectName: "sampleStudioAuditionKey"
                            text: dialog.audition.auditionKeyText
                            onEditingFinished: dialog.audition.setAuditionKeyText(text)
                        }
                        AuditionCheckBox {
                            text: qsTr("Use destination voice ADSR")
                            visible: dialog.audition.hasDestinationAdsr
                            checked: dialog.audition.useDestinationAdsr
                            onToggled: dialog.audition.setUseDestinationAdsr(checked)
                        }
                    }
                    Label { text: dialog.editor.outputSummary; color: dialog.colors.windowText }
                    AuditionButton {
                        id: advanced
                        objectName: "sampleStudioAdvanced"
                        checkable: true
                        text: qsTr("Advanced")
                        contentItem: DisclosureLabel { control: advanced; expanded: advanced.checked }
                    }
                    ColumnLayout {
                        visible: advanced.checked
                        RowLayout {
                            Label { text: qsTr("Format:"); color: dialog.colors.windowText }
                            Label { text: dialog.editor.techDetail; color: dialog.colors.windowText }
                        }
                        RowLayout {
                            Label { text: qsTr("Crop range:"); color: dialog.colors.windowText }
                            AuditionSpinBox { from: 0; to: dialog.editor.sourceFrameCount; value: dialog.editor.cropStart; onValueModified: dialog.editor.setCropStart(value) }
                            AuditionSpinBox { from: 0; to: dialog.editor.sourceFrameCount; value: dialog.editor.cropEnd; onValueModified: dialog.editor.setCropEnd(value) }
                        }
                        RowLayout {
                            Label { text: qsTr("Fine tune (cents):"); color: dialog.colors.windowText }
                            AuditionTextField {
                                text: "" + dialog.editor.fineTuneCents
                                onEditingFinished: dialog.editor.setFineTuneCents(+text)
                            }
                        }
                        RowLayout {
                            Label { text: qsTr("Normalize:"); color: dialog.colors.windowText }
                            AuditionComboBox { model: dialog.editor.normalizeChoices; currentIndex: dialog.editor.normalizeMode; onActivated: index => dialog.editor.setNormalizeMode(index) }
                            Label { text: dialog.editor.gainReadout; color: dialog.colors.windowText }
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            AuditionButton { text: qsTr("Cancel"); onClicked: dialog.close() }
            AuditionButton {
                objectName: "sampleStudioCommit"
                text: dialog.editor.commitLabel
                enabled: dialog.editor.canCommit
                onClicked: dialog.workflow.accept()
            }
        }
    }
    }
}
