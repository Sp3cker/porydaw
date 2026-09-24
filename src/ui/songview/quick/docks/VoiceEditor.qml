pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Porydaw.Ui

ColumnLayout {
    id: editor
    objectName: "voicegroupEditor"
    required property QtObject controller
    required property var palette
    required property real baseFontPx
    readonly property var draft: controller.editorModel()
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
    readonly property int visibleRows: 1 + Number(hasSymbol) + Number(hasSweep)
                                       + Number(hasDuty) + Number(hasPeriod) + Number(hasAdsr)
    // QFormLayout's visible rows, half-space gaps, button inset, and outer
    // top offset. A nested ColumnLayout otherwise expands into the tree's
    // fill-height slack; this editor must take only its native form height.
    Layout.minimumHeight: 0
    Layout.fillHeight: false
    Layout.preferredHeight: (draft.editable ? regularHeight : noticeHeight)
                            + Number(hasSymbol) * regularHeight
                            + Number(hasSweep) * spinHeight
                            + Number(hasDuty) * regularHeight
                            + Number(hasPeriod) * regularHeight
                            + Number(hasAdsr) * spinHeight
                            + buttonHeight + (visibleRows + 1) * spacingPx
    spacing: spacingPx
    Layout.leftMargin: Math.round(baseFontPx * 0.33)
    Layout.rightMargin: Math.round(baseFontPx * 0.25)
    Layout.topMargin: Math.round(baseFontPx * 0.33)
    Layout.bottomMargin: 0

    Label {
        objectName: "voicegroupEditorNotice"
        Layout.fillWidth: true
        visible: !editor.draft.editable && text.length > 0
        text: editor.draft.notice
        wrapMode: Text.WordWrap
        font.pixelSize: editor.baseFontPx
        color: editor.palette.primaryText
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
            font.pixelSize: editor.baseFontPx
            color: editor.palette.primaryText
        }
        ComboBox {
            id: typePicker
            objectName: "vgTypeCombo"
            Layout.fillWidth: true
            Layout.minimumHeight: 0
            Layout.preferredHeight: editor.baseFontPx * 1.85
            font.pixelSize: editor.baseFontPx
            model: [{ name: qsTr("Sample"), macro: 0 },
                    { name: qsTr("Sample (no resample)"), macro: 1 },
                    { name: qsTr("Sample (alt)"), macro: 2 },
                    { name: qsTr("Drumkit"), macro: 12 },
                    { name: qsTr("Square 1"), macro: 3 },
                    { name: qsTr("Square 2"), macro: 5 },
                    { name: qsTr("Wave"), macro: 7 },
                    { name: qsTr("Noise"), macro: 9 }]
            textRole: "name"
            valueRole: "macro"
            currentIndex: indexOfValue(editor.draft.macro === 11 ? 0 : editor.draft.macro)
            onActivated: index => editor.draft.changeType(valueAt(index), editor.draft.symbol)
        }
    }

    RowLayout {
        visible: editor.hasSymbol
        Layout.preferredHeight: editor.baseFontPx * 1.83
        Layout.minimumHeight: 0
        spacing: editor.spacingPx
        Label {
            text: editor.draft.macro === 7 || editor.draft.macro === 8 ? qsTr("Wave")
                  : editor.draft.macro === 12 ? qsTr("Drumkit") : qsTr("Sample")
            Layout.preferredWidth: editor.fieldLabelWidth
            font.pixelSize: editor.baseFontPx
            color: editor.palette.primaryText
        }
        ComboBox {
            id: symbolPicker
            objectName: "vgSamplePickerButton"
            Layout.fillWidth: true
            Layout.preferredHeight: editor.baseFontPx * 1.5
            Layout.minimumHeight: 0
            editable: true
            font.pixelSize: editor.baseFontPx
            model: {
                editor.controller.catalogRevision
                return editor.draft.macro === 7 || editor.draft.macro === 8
                    ? editor.controller.waveChoices()
                    : editor.draft.macro === 12 ? editor.controller.drumkitChoices()
                    : editor.controller.samplePickerSymbols()
            }
            editText: editor.draft.symbol
            onActivated: editor.draft.changeType(editor.draft.macro, currentText)
            onAccepted: editor.draft.changeType(editor.draft.macro, editText)
        }
        ToolButton {
            objectName: "vgNewSampleButton"
            visible: editor.draft.macro <= 2
            Layout.preferredWidth: editor.baseFontPx * 2.08
            Layout.minimumHeight: 0
            Layout.preferredHeight: editor.baseFontPx * 1.83
            text: "+"
            font.pixelSize: editor.baseFontPx
            onClicked: editor.controller.requestNewSample(editor.controller.currentSlot)
        }
        ToolButton {
            objectName: "vgEditSampleButton"
            visible: editor.draft.macro <= 2 && !editor.draft.materializesBlank
            Layout.preferredWidth: editor.baseFontPx * 2.08
            Layout.preferredHeight: editor.baseFontPx * 1.83
            Layout.minimumHeight: 0
            text: "✎"
            font.pixelSize: editor.baseFontPx
            onClicked: editor.controller.requestEditSample(editor.controller.currentSlot)
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
            font.pixelSize: editor.baseFontPx
            color: editor.palette.primaryText
        }
        SpinBox {
            objectName: "vgSweepSpin"
            Layout.fillWidth: true
            Layout.preferredHeight: editor.spinHeight
            Layout.minimumHeight: 0
            from: 0; to: 127
            value: editor.draft.sweep
            font.pixelSize: editor.baseFontPx
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
            font.pixelSize: editor.baseFontPx
            color: editor.palette.primaryText
        }
        ComboBox {
            objectName: "vgDutyCombo"
            Layout.fillWidth: true
            model: ["12.5%", "25%", "50%", "75%"]
            currentIndex: editor.draft.duty
            font.pixelSize: editor.baseFontPx
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
            font.pixelSize: editor.baseFontPx
            color: editor.palette.primaryText
        }
        ComboBox {
            objectName: "vgPeriodCombo"
            Layout.fillWidth: true
            model: [qsTr("0 (15-bit, hiss)"), qsTr("1 (7-bit, metallic)")]
            currentIndex: editor.draft.period
            font.pixelSize: editor.baseFontPx
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
            font.pixelSize: editor.baseFontPx
            color: editor.palette.primaryText
        }
        Repeater {
            model: ["attack", "decay", "sustain", "release"]
            SpinBox {
                required property int index
                required property string modelData
                objectName: "vg" + modelData.charAt(0).toUpperCase()
                            + modelData.slice(1) + "Spin"
                Layout.fillWidth: true
                Layout.minimumWidth: editor.baseFontPx * 3.3
                Layout.preferredHeight: editor.baseFontPx * 2.08
                Layout.minimumHeight: 0
                from: 0
                to: editor.isCgb ? (modelData === "sustain" ? 15 : 7) : 255
                value: editor.draft[modelData]
                font.pixelSize: editor.baseFontPx
                onValueModified: editor.draft.change(modelData, value)
            }
        }
    }
    Button {
        text: qsTr("New...")
        Layout.topMargin: editor.spacingPx
        Layout.preferredHeight: editor.buttonHeight
        Layout.minimumHeight: 0
        font.pixelSize: editor.baseFontPx
        focusPolicy: Qt.NoFocus
        onClicked: editor.controller.requestNewVoicegroup()
    }
}
