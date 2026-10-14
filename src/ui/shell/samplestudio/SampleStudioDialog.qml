pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

DialogWindow {
    id: dialog
    objectName: "sampleStudioDialog"
    required property SampleStudioWorkflow workflow
    required property SampleLibraryModel library
    required property ApplicationSession applicationSession
    required property SampleStudioPresenter editor
    required property SampleLoopTools tools
    required property MarkerWaveformModel waveformModel
    required property SampleStudioAudition audition
    readonly property real unit: applicationSession.baseFontPx
    readonly property real spacing: applicationSession.layoutSpaces.one
    modality: Qt.ApplicationModal
    width: 75 * unit
    height: 53.33 * unit
    minimumWidth: 58 * unit
    minimumHeight: 23.33 * unit
    title: editor.windowTitle
    font: applicationSession.typographyFonts.body
    onClosing: workflow.cancel()
    onVisibleChanged: if (visible) openSourcePicker()

    function openSourcePicker(): void {
        if (!dialog.visible || !dialog.workflow.pickerRequested || picker.visible) return
        picker.currentFolder = dialog.workflow.pickerFolder
        picker.open()
    }

    FileDialog {
        id: picker
        objectName: "shellImportSamplePicker"
        title: qsTr("Import Sample")
        nameFilters: [qsTr("Audio files (*.wav *.aif *.aiff *.mp3 *.flac *.ogg *.sf2)"),
                      qsTr("All files (*)")]
        fileMode: FileDialog.OpenFile
        parentWindow: dialog
        onAccepted: dialog.workflow.chooseSource(selectedFile)
        onRejected: dialog.workflow.cancelSource()
    }
    MessageDialog {
        id: alert
        objectName: "shellSampleStudioAlert"
        buttons: MessageDialog.Ok
        parentWindow: dialog
    }
    MessageDialog {
        objectName: "shellSampleStudioStereoPrompt"
        title: qsTr("Import Sample")
        text: dialog.workflow.stereoPromptText
        buttons: MessageDialog.Yes | MessageDialog.No
        parentWindow: dialog
        visible: dialog.visible && dialog.workflow.stereoPromptOpen
        onButtonClicked: (button) => dialog.workflow.answerStereoPrompt(button === MessageDialog.Yes)
        onRejected: dialog.workflow.cancelStereoPrompt()
    }
    Connections {
        target: dialog.workflow
        function onPickerRequestedChanged(): void {
            if (dialog.workflow.pickerRequested)
                dialog.openSourcePicker()
            else
                picker.close()
        }
        function onAlertRevisionChanged(): void {
            if (!dialog.workflow.editorOpen) return
            alert.title = dialog.workflow.alertTitle
            alert.text = dialog.workflow.alertText
            alert.open()
        }
    }

    Shortcut {
        objectName: "sampleStudioCloseShortcut"
        sequences: [StandardKey.Close]
        context: Qt.WindowShortcut
        onActivated: dialog.close()
    }
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
    component AuditionValidatedField: ValidatedTextField {
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
    component SectionHeader: Label {
        color: dialog.colors.secondaryText
        font: dialog.applicationSession.typographyFonts.caption
    }
    component FieldLabel: Label {
        color: dialog.colors.windowText
        Layout.preferredWidth: 7 * dialog.unit
        elide: Text.ElideRight
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
        RowLayout {
            objectName: "sampleBrowserSplitter"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: dialog.spacing
            SampleLibraryPane {
                library: dialog.library
                colors: dialog.colors
                studioWindow: dialog
                unit: dialog.unit
                paneSpacing: dialog.spacing
                Layout.preferredWidth: 22 * dialog.unit
                Layout.minimumWidth: 14 * dialog.unit
                Layout.fillHeight: true
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 20 * dialog.unit
                spacing: dialog.spacing
                RowLayout {
                    Layout.fillWidth: true
                    spacing: dialog.spacing
                    Item { Layout.fillWidth: true }
                    AuditionButton {
                        Layout.preferredWidth: 2.5 * dialog.unit
                        text: "↶"
                        Accessible.name: qsTr("Undo")
                        enabled: dialog.editor.canUndo
                        onClicked: dialog.editor.undo()
                    }
                    AuditionButton {
                        Layout.preferredWidth: 2.5 * dialog.unit
                        text: "↷"
                        Accessible.name: qsTr("Redo")
                        enabled: dialog.editor.canRedo
                        onClicked: dialog.editor.redo()
                    }
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 1.5 * dialog.unit
                        Layout.alignment: Qt.AlignVCenter
                        color: dialog.colors.outline
                    }
                    AuditionButton {
                        Layout.preferredWidth: 2.5 * dialog.unit
                        text: "−"
                        Accessible.name: qsTr("Zoom out")
                        enabled: dialog.editor.hasSource
                        onClicked: dialog.waveformModel.zoom(waveform.width / 2, -1)
                    }
                    AuditionButton {
                        Layout.preferredWidth: 2.5 * dialog.unit
                        text: "+"
                        Accessible.name: qsTr("Zoom in")
                        enabled: dialog.editor.hasSource
                        onClicked: dialog.waveformModel.zoom(waveform.width / 2, 1)
                    }
                    AuditionButton {
                        text: qsTr("Fit")
                        enabled: dialog.editor.hasSource
                        onClicked: dialog.waveformModel.fit()
                    }
                }
                SampleWaveform {
                    id: waveform
                    objectName: "sampleStudioWaveform"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 6 * dialog.unit
                    model: dialog.waveformModel
                    colors: dialog.colors
                    baseFontPx: dialog.unit
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: dialog.spacing
                    enabled: dialog.editor.hasSource
                    AuditionButton {
                        objectName: "sampleStudioPlay"
                        text: dialog.audition.playText
                        enabled: dialog.audition.available && dialog.editor.hasSource
                        onClicked: dialog.audition.toggle()
                    }
                    Label { text: qsTr("Audition key"); color: dialog.colors.windowText }
                    AuditionValidatedField {
                        id: auditionKey
                        objectName: "sampleStudioAuditionKey"
                        colors: dialog.colors
                        Layout.preferredWidth: 8 * dialog.unit
                        text: dialog.audition.auditionKeyText
                        invalid: dialog.audition.auditionKeyInvalid
                        onEditingFinished: dialog.audition.setAuditionKeyText(text)
                    }
                    AuditionCheckBox {
                        text: qsTr("Use voice ADSR")
                        visible: dialog.audition.hasDestinationAdsr
                        checked: dialog.audition.useDestinationAdsr
                        onToggled: dialog.audition.setUseDestinationAdsr(checked)
                    }
                    Item { Layout.fillWidth: true }
                }
            }
            ScrollView {
                id: inspectorScroll
                objectName: "sampleStudioControlsScroll"
                Layout.preferredWidth: 28 * dialog.unit
                Layout.minimumWidth: 20 * dialog.unit
                Layout.fillHeight: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                clip: true
                ColumnLayout {
                    width: inspectorScroll.availableWidth
                    spacing: 2 * dialog.spacing
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: dialog.spacing
                        SectionHeader { text: qsTr("Sample") }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: dialog.spacing
                            FieldLabel { text: qsTr("Name") }
                            AuditionValidatedField {
                                id: nameField
                                objectName: "sampleStudioName"
                                colors: dialog.colors
                                Layout.fillWidth: true
                                text: dialog.editor.sampleName
                                readOnly: dialog.editor.nameReadOnly || !dialog.editor.hasSource
                                invalid: dialog.editor.nameInvalid
                                onTextEdited: dialog.editor.setSampleName(text)
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: dialog.spacing
                        enabled: dialog.editor.hasSource
                        SectionHeader { text: qsTr("Trim") }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: dialog.spacing
                            FieldLabel { text: qsTr("Crop range") }
                            AuditionSpinBox {
                                Layout.fillWidth: true
                                from: 0
                                to: dialog.editor.sourceFrameCount
                                value: dialog.editor.cropStart
                                onValueModified: dialog.editor.setCropStart(value)
                            }
                            AuditionSpinBox {
                                Layout.fillWidth: true
                                from: 0
                                to: dialog.editor.sourceFrameCount
                                value: dialog.editor.cropEnd
                                onValueModified: dialog.editor.setCropEnd(value)
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: dialog.spacing
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: dialog.spacing
                            SectionHeader {
                                Layout.fillWidth: true
                                text: qsTr("Loop")
                            }
                            AuditionCheckBox {
                                objectName: "sampleStudioLoop"
                                enabled: dialog.editor.hasSource
                                text: qsTr("On")
                                checked: dialog.editor.loopOn
                                onToggled: dialog.tools.setLoopEnabled(checked)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: dialog.spacing
                            visible: dialog.tools.loopBodyVisible
                            enabled: dialog.editor.hasSource
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: dialog.spacing
                                FieldLabel { text: qsTr("Start") }
                                AuditionSpinBox {
                                    Layout.fillWidth: true
                                    from: 0
                                    to: dialog.editor.sourceFrameCount
                                    value: dialog.editor.loopStart
                                    onValueModified: dialog.editor.setLoopStart(value)
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: dialog.spacing
                                FieldLabel { text: qsTr("End") }
                                AuditionSpinBox {
                                    Layout.fillWidth: true
                                    from: 0
                                    to: dialog.editor.sourceFrameCount
                                    value: dialog.editor.loopEnd
                                    onValueModified: dialog.editor.setLoopEnd(value)
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: dialog.spacing
                                FieldLabel { text: qsTr("Seam") }
                                Label {
                                    visible: dialog.tools.seamBadgeVisible
                                    text: dialog.tools.seamBadgeText
                                    color: dialog.tools.seamBadgeSeverity === 0 ? dialog.colors.windowText
                                        : dialog.tools.seamBadgeSeverity === 1 ? dialog.colors.warningText
                                        : dialog.colors.errorText
                                }
                                Item { Layout.fillWidth: true }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: dialog.spacing
                                AuditionButton {
                                    text: qsTr("Try Another Loop")
                                    enabled: dialog.tools.canTryAnother
                                    onClicked: dialog.tools.tryAnotherLoop()
                                }
                                AuditionButton {
                                    text: qsTr("Refine")
                                    onClicked: dialog.tools.refineLoop()
                                }
                                Item { Layout.fillWidth: true }
                            }
                            AuditionCheckBox {
                                text: qsTr("Smooth seam")
                                checked: dialog.tools.crossfadeOn
                                onToggled: dialog.tools.setCrossfade(checked)
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: dialog.spacing
                        enabled: dialog.editor.hasSource
                        SectionHeader { text: qsTr("Pitch") }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: dialog.spacing
                            FieldLabel { text: qsTr("Base key") }
                            AuditionValidatedField {
                                id: baseKeyField
                                objectName: "sampleStudioBaseKey"
                                colors: dialog.colors
                                Layout.fillWidth: true
                                text: dialog.editor.baseKeyText
                                invalid: dialog.editor.baseKeyInvalid
                                onEditingFinished: dialog.editor.setBaseKeyText(text)
                            }
                        }
                        AuditionButton {
                            text: dialog.tools.pitchApplyText
                            visible: dialog.tools.pitchApplyVisible
                            onClicked: dialog.tools.applyDetectedPitch()
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: dialog.spacing
                        enabled: dialog.editor.hasSource
                        SectionHeader { text: qsTr("Sample rate") }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: dialog.spacing
                            FieldLabel { text: qsTr("File") }
                            Label {
                                objectName: "sampleStudioFileRate"
                                Layout.fillWidth: true
                                text: dialog.editor.fileRateText
                                color: dialog.colors.windowText
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: dialog.spacing
                            FieldLabel { text: qsTr("Saved at") }
                            AuditionComboBox {
                                id: rate
                                objectName: "sampleStudioRate"
                                Layout.fillWidth: true
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
                            Layout.fillWidth: true
                            spacing: dialog.spacing
                            FieldLabel { text: qsTr("ROM") }
                            Label {
                                objectName: "sampleStudioRom"
                                Layout.fillWidth: true
                                text: dialog.editor.romText
                                color: dialog.colors.windowText
                            }
                        }
                    }
                    AuditionButton {
                        id: advanced
                        Layout.fillWidth: true
                        enabled: dialog.editor.hasSource
                        objectName: "sampleStudioAdvanced"
                        checkable: true
                        text: qsTr("Advanced")
                        contentItem: DisclosureLabel { control: advanced; expanded: advanced.checked }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: dialog.spacing
                        visible: advanced.checked
                        enabled: dialog.editor.hasSource
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: dialog.spacing
                            FieldLabel { text: qsTr("Fine tune") }
                            AuditionValidatedField {
                                Layout.fillWidth: true
                                colors: dialog.colors
                                text: dialog.editor.fineTuneText
                                invalid: dialog.editor.fineTuneInvalid
                                onEditingFinished: dialog.editor.commitFineTuneCentsText(text)
                            }
                            Label { text: qsTr("cents"); color: dialog.colors.windowText }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: dialog.spacing
                            FieldLabel { text: qsTr("Normalize") }
                            AuditionComboBox {
                                Layout.fillWidth: true
                                model: dialog.editor.normalizeChoices
                                currentIndex: dialog.editor.normalizeMode
                                onActivated: index => dialog.editor.setNormalizeMode(index)
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: dialog.spacing
                            FieldLabel { text: qsTr("Applied gain") }
                            Label {
                                Layout.fillWidth: true
                                text: dialog.editor.gainReadout
                                color: dialog.colors.windowText
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: dialog.spacing
            Label {
                objectName: "sampleStudioFileName"
                Layout.fillWidth: true
                text: dialog.editor.loadedFileName
                elide: Text.ElideRight
                color: dialog.colors.secondaryText
            }
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
