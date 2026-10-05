pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp
import Porydaw.Icons

ColumnLayout {
    id: editor
    objectName: "voicegroupEditor"
    required property VoiceListController controller
    required property GridPalette colors
    required property ApplicationSession applicationSession
    readonly property real baseFontPx: applicationSession.baseFontPx
    readonly property VoiceEditorController draft: controller.editorModel() as VoiceEditorController
    readonly property int spacingPx: Math.max(1, Math.round(baseFontPx * 0.16))
    readonly property int regularHeight: Math.round(baseFontPx * 1.83)
    readonly property int spinHeight: Math.round(baseFontPx * 2.08)
    readonly property int noticeHeight: Math.round(baseFontPx * 1.17)
    readonly property int buttonHeight: Math.round(baseFontPx * 1.67)
    // Native QFormLayout sizes its label column to the widest visible
    // caption: Sample in DS voices, Sweep in Square 1 voices.
    readonly property real fieldLabelWidth: baseFontPx *
                                            (draft.macro >= 3 && draft.macro <= 6 ? 3.6 : 4.1)
    readonly property bool isCgb: draft.macro >= 3 && draft.macro <= 10
    readonly property bool hasSymbol: draft.editable
                                      && (draft.macro <= 2 || draft.macro === 7
                                          || draft.macro === 8 || draft.macro >= 11)
    readonly property bool hasSweep: draft.editable && (draft.macro === 3 || draft.macro === 4)
    readonly property bool hasDuty: draft.editable && (draft.macro >= 3 && draft.macro <= 6)
    readonly property bool hasPeriod: draft.editable && (draft.macro === 9 || draft.macro === 10)
    readonly property bool hasAdsr: draft.editable && draft.macro !== 11 && draft.macro !== 12
    readonly property bool hasSynth: draft.editable && draft.isSynth
    readonly property bool hasPulse: hasSynth && draft.waveform === 0
    readonly property int visibleRows: 1 + (hasSymbol ? 1 : 0) + (hasSweep ? 1 : 0)
                                       + (hasDuty ? 1 : 0) + (hasPeriod ? 1 : 0) + (hasAdsr ? 1 : 0)
                                       + (hasSynth ? 1 : 0) + (hasPulse ? 1 : 0)
                                       + (draft.editable && draft.notice.length > 0 ? 1 : 0)
    // The editor takes only its native form height, not the tree's fill-height slack.
    Layout.minimumHeight: 0
    Layout.fillHeight: false
    Layout.preferredHeight: (draft.editable ? regularHeight
                                           + (draft.notice.length > 0 ? noticeHeight : 0)
                                           : noticeHeight)
                            + (hasSymbol ? regularHeight : 0)
                            + (hasSweep ? spinHeight : 0)
                            + (hasDuty ? regularHeight : 0)
                            + (hasPeriod ? regularHeight : 0)
                            + (hasAdsr ? spinHeight : 0)
                            + (hasSynth ? regularHeight : 0)
                            + (hasPulse ? spinHeight : 0)
                            + buttonHeight + (visibleRows + 1) * spacingPx
    spacing: spacingPx

    component VoiceTypeChoice: QtObject {
        required property string name
        required property int macro
    }

    Label {
        objectName: "voicegroupEditorNotice"
        Layout.fillWidth: true
        visible: editor.draft.notice.length > 0
        text: editor.draft.notice
        wrapMode: Text.WordWrap
        color: editor.colors.primaryText
        Layout.preferredHeight: editor.noticeHeight
    }

    RowLayout {
        visible: editor.draft.editable
        Layout.minimumHeight: 0
        Layout.preferredHeight: editor.baseFontPx * 1.83
        spacing: editor.spacingPx
        Label {
            text: qsTr("Type")
            Layout.preferredWidth: editor.fieldLabelWidth
            color: editor.colors.primaryText
        }
        ComboBox {
            id: typePicker
            objectName: "vgTypeCombo"
            Layout.fillWidth: true
            Layout.minimumHeight: 0
            Layout.preferredHeight: editor.baseFontPx * 1.85
            readonly property list<VoiceTypeChoice> choices: [
                VoiceTypeChoice { name: qsTr("Sample"); macro: 0 },
                VoiceTypeChoice { name: qsTr("Sample (no resample)"); macro: 1 },
                VoiceTypeChoice { name: qsTr("Sample (alt)"); macro: 2 },
                VoiceTypeChoice { name: qsTr("Drumkit"); macro: 12 },
                VoiceTypeChoice { name: qsTr("Square 1"); macro: 3 },
                VoiceTypeChoice { name: qsTr("Square 2"); macro: 5 },
                VoiceTypeChoice { name: qsTr("Wave"); macro: 7 },
                VoiceTypeChoice { name: qsTr("Noise"); macro: 9 },
                VoiceTypeChoice { name: qsTr("Synth (Golden Sun)"); macro: -1 }
            ]
            model: editor.controller.canMintSynths || editor.controller.synthChoices.length > 0
                   || editor.draft.isSynth ? typePicker.choices : typePicker.choices.slice(0, 8)
            textRole: "name"
            valueRole: "macro"
            currentIndex: indexOfValue(editor.draft.isSynth ? -1
                                                              : editor.draft.macro === 11 ? 0
                                                                                          : editor.draft.macro)
            onActivated: index => editor.draft.changeType(valueAt(index), editor.draft.symbol)
        }
    }

    RowLayout {
        visible: editor.hasSymbol
        Layout.preferredHeight: editor.baseFontPx * 1.83
        Layout.minimumHeight: 0
        spacing: editor.spacingPx
        Label {
            text: editor.draft.isSynth ? qsTr("Synth")
                  : editor.draft.macro === 7 || editor.draft.macro === 8 ? qsTr("Wave")
                  : editor.draft.macro === 12 ? qsTr("Drumkit") : qsTr("Sample")
            Layout.preferredWidth: editor.fieldLabelWidth
            color: editor.colors.primaryText
        }
        SamplePicker {
            objectName: "vgSymbolPicker"
            visible: editor.draft.macro !== 12 && !editor.draft.isSynth
            Layout.fillWidth: true
            Layout.preferredHeight: editor.baseFontPx * 1.5
            Layout.minimumHeight: 0
            controller: editor.controller
            draft: editor.draft
            colors: editor.colors
            applicationSession: editor.applicationSession
            waveMode: editor.draft.macro === 7 || editor.draft.macro === 8
            onPicked: symbol => editor.draft.changeType(editor.draft.macro, symbol)
        }
        ComboBox {
            objectName: "vgSynthCombo"
            visible: editor.draft.isSynth
            Layout.fillWidth: true
            Layout.preferredHeight: editor.regularHeight
            model: editor.controller.synthChoices
            currentIndex: editor.controller.synthChoices.indexOf(editor.draft.symbol)
            displayText: editor.draft.symbol
            onActivated: editor.draft.changeType(-1, currentText)
        }
        ComboBox {
            objectName: "vgDrumkitCombo"
            visible: editor.draft.macro === 12
            Layout.fillWidth: true
            Layout.preferredHeight: editor.baseFontPx * 1.5
            editable: true
            model: editor.controller.drumkitSymbols
            editText: editor.draft.symbol
            onActivated: editor.draft.changeType(editor.draft.macro, currentText)
            onAccepted: editor.draft.changeType(editor.draft.macro, editText)
        }
        ToolButton {
            objectName: "vgNewSampleButton"
            visible: editor.draft.macro <= 2 && !editor.draft.isSynth
            Layout.preferredWidth: editor.baseFontPx * 2.08
            Layout.minimumHeight: 0
            Layout.preferredHeight: editor.baseFontPx * 1.83
            text: "+"
            onClicked: editor.controller.requestNewSample(editor.controller.currentSlot)
        }
        // Built only for DirectSound voices, the only ones that offer sample editing.
        Loader {
            active: editor.draft.macro <= 2 && !editor.draft.isSynth
            visible: active
            Layout.preferredWidth: editor.baseFontPx * 2.08
            Layout.preferredHeight: editor.baseFontPx * 1.83
            Layout.minimumHeight: 0
            sourceComponent: ToolButton {
                id: editSample
                objectName: "vgEditSampleButton"
                text: qsTr("Edit Sample")
                contentItem: Item {
                    AppIcon {
                        anchors.centerIn: parent
                        width: Math.round(editor.baseFontPx)
                        height: width
                        icon: Icons.editSample
                        color: editSample.palette.buttonText
                    }
                }
                onClicked: editor.controller.requestEditSample(editor.controller.currentSlot)
            }
        }
    }

    RowLayout {
        visible: editor.hasSynth
        Layout.preferredHeight: editor.regularHeight
        Layout.minimumHeight: 0
        spacing: editor.spacingPx
        Label {
            text: qsTr("Waveform")
            Layout.preferredWidth: editor.fieldLabelWidth
            color: editor.colors.primaryText
        }
        ComboBox {
            objectName: "vgSynthWaveformCombo"
            Layout.fillWidth: true
            readonly property list<string> choices: [qsTr("Pulse"), qsTr("Saw"), qsTr("Triangle")]
            model: choices
            currentIndex: editor.draft.waveform
            onActivated: index => editor.draft.changeSynth("waveform", index)
        }
    }

    RowLayout {
        visible: editor.hasPulse
        Layout.preferredHeight: editor.spinHeight
        Layout.minimumHeight: 0
        spacing: editor.spacingPx
        Label {
            text: qsTr("Duty LFO")
            Layout.preferredWidth: editor.fieldLabelWidth
            color: editor.colors.primaryText
        }
        Repeater {
            model: ListModel {
                ListElement { name: "BaseDuty"; field: "baseDuty"; detail: qsTr("Base duty cycle") }
                ListElement { name: "DutyStep"; field: "dutyStep"; detail: qsTr("Step per frame") }
                ListElement { name: "ModDepth"; field: "modDepth"; detail: qsTr("Modulation amount") }
                ListElement { name: "Phase"; field: "phase"; detail: qsTr("LFO phase offset") }
            }
            SpinBox {
                required property string name
                required property string field
                required property string detail
                objectName: "vgSynth" + name + "Spin"
                Layout.fillWidth: true
                Layout.minimumWidth: editor.baseFontPx * 3.3
                Layout.preferredHeight: editor.spinHeight
                Layout.minimumHeight: 0
                from: 0
                to: 255
                value: field === "baseDuty" ? editor.draft.baseDuty
                       : field === "dutyStep" ? editor.draft.dutyStep
                       : field === "modDepth" ? editor.draft.modDepth : editor.draft.phase
                ToolTip.text: detail
                ToolTip.visible: hovered
                onValueModified: editor.draft.changeSynth(field, value)
            }
        }
    }

    RowLayout {
        visible: editor.hasSweep
        Layout.preferredHeight: editor.spinHeight
        Layout.minimumHeight: 0
        spacing: editor.spacingPx
        Label {
            text: qsTr("Sweep")
            Layout.preferredWidth: editor.fieldLabelWidth
            color: editor.colors.primaryText
        }
        SpinBox {
            objectName: "vgSweepSpin"
            Layout.fillWidth: true
            Layout.preferredHeight: editor.spinHeight
            Layout.minimumHeight: 0
            from: 0; to: 127
            value: editor.draft.sweep
            onValueModified: editor.draft.change("sweep", value)
        }
    }
    RowLayout {
        visible: editor.hasDuty
        Layout.preferredHeight: editor.regularHeight
        Layout.minimumHeight: 0
        spacing: editor.spacingPx
        Label {
            text: qsTr("Duty")
            Layout.preferredWidth: editor.fieldLabelWidth
            color: editor.colors.primaryText
        }
        ComboBox {
            objectName: "vgDutyCombo"
            Layout.fillWidth: true
            readonly property list<string> choices: ["12.5%", "25%", "50%", "75%"]
            model: choices
            currentIndex: editor.draft.duty
            onActivated: index => editor.draft.change("duty", index)
        }
    }
    RowLayout {
        visible: editor.hasPeriod
        Layout.preferredHeight: editor.regularHeight
        spacing: editor.spacingPx
        Layout.minimumHeight: 0
        Label {
            text: qsTr("Period")
            Layout.preferredWidth: editor.fieldLabelWidth
            color: editor.colors.primaryText
        }
        ComboBox {
            objectName: "vgPeriodCombo"
            Layout.fillWidth: true
            readonly property list<string> choices: [qsTr("0 (15-bit, hiss)"), qsTr("1 (7-bit, metallic)")]
            model: choices
            currentIndex: editor.draft.period
            onActivated: index => editor.draft.change("period", index)
        }
    }
    RowLayout {
        visible: editor.hasAdsr
        Layout.preferredHeight: editor.spinHeight
        Layout.minimumHeight: 0
        spacing: editor.spacingPx
        Label {
            text: qsTr("ADSR")
            Layout.preferredWidth: editor.fieldLabelWidth
            color: editor.colors.primaryText
        }
        Repeater {
            readonly property list<string> fields: ["attack", "decay", "sustain", "release"]
            model: fields
            SpinBox {
                required property int index
                required property string modelData
                objectName: "vg" + (index === 0 ? "Attack" : index === 1 ? "Decay"
                                   : index === 2 ? "Sustain" : "Release") + "Spin"
                Layout.fillWidth: true
                Layout.minimumWidth: editor.baseFontPx * 3.3
                Layout.preferredHeight: editor.baseFontPx * 2.08
                Layout.minimumHeight: 0
                from: 0
                to: editor.isCgb ? (modelData === "sustain" ? 15 : 7) : 255
                value: modelData === "attack" ? editor.draft.attack
                       : modelData === "decay" ? editor.draft.decay
                       : modelData === "sustain" ? editor.draft.sustain : editor.draft.release
                onValueModified: editor.draft.change(modelData, value)
            }
        }
    }
    RowLayout {
        Layout.topMargin: editor.spacingPx
        Layout.preferredHeight: editor.buttonHeight
        Layout.minimumHeight: 0
        Button {
            objectName: "vgNewVoicegroupButton"
            text: qsTr("New...")
            Layout.preferredHeight: editor.buttonHeight
            Layout.minimumHeight: 0
            focusPolicy: Qt.NoFocus
            onClicked: editor.controller.requestNewVoicegroup()
        }
        Button {
            objectName: "vgSaveButton"
            text: qsTr("Save")
            Layout.preferredHeight: editor.buttonHeight
            Layout.minimumHeight: 0
            enabled: editor.controller.bankDirty
            onClicked: editor.controller.requestSave()
        }
    }
}
