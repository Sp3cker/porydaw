pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Fusion as Fusion
import PorydawStyle
import PorydawApp

Item {
    id: page
    required property EngineSettingsStore store
    required property GridPalette colors
    required property real unit
    required property TypographyFonts typography
    readonly property real labelWidth: 125 + 102 * (unit - 1)
    readonly property list<string> voicegroups: store.voicegroups

    function finishVoicegroupEdit(): void {
        if (voicegroup.activeFocus && voicegroup.editText !== page.store.voicegroup)
            page.store.changeVoicegroup(voicegroup.editText)
    }
    function finishTuningEdit(): void {
        if (tuningFrequency.edited)
            page.store.changeMasterTuningFrequency(tuningFrequency.text)
        tuningFrequency.edited = false
        tuningFrequency.text = page.store.masterTuningFrequencyText
    }
    function reset(): void {
        voicegroup.currentIndex = page.voicegroups.indexOf(page.store.voicegroup)
        voicegroup.editText = page.store.voicegroup
        volume.value = page.store.masterVolume
        songReverb.value = page.store.reverb
        songPriority.value = page.store.priority
        gate.checked = page.store.exactGate
        clocks.checked = page.store.extendedClocks
        compression.checked = page.store.noCompression
        tuningFrequency.edited = false
        tuningFrequency.text = page.store.masterTuningFrequencyText
    }

    Binding {
        target: page.store.reverbFormat
        property: "defaultText"
        value: qsTr("Default (50)")
    }

    Column {
        y: 11 * page.unit
        width: page.width
        // Legacy fork spacing is pinned by tst_ShellSettings reference rects.
        spacing: 6
        SettingsFieldRow {
            width: page.width; unit: page.unit; labelWidth: page.labelWidth
            colors: page.colors; typography: page.typography
            label: qsTr("Voicegroup:"); compact: true; bottomInset: page.unit - 1
            ComboBox {
                id: voicegroup
                objectName: "song.voicegroup"
                anchors.fill: parent
                editable: true; model: page.voicegroups
                editText: page.store.voicegroup
                font: page.typography.body
                currentIndex: page.voicegroups.indexOf(page.store.voicegroup)
                onModelChanged: {
                    if (!activeFocus) {
                        currentIndex = page.voicegroups.indexOf(page.store.voicegroup)
                        editText = page.store.voicegroup
                    }
                }
                onEditTextChanged: {
                    if (activeFocus && editText !== page.store.voicegroup)
                        page.store.changeVoicegroup(editText)
                }
                onActivated: page.store.changeVoicegroup(currentText)
                ToolTip.visible: hovered
                ToolTip.text: qsTr("The symbol is voicegroup_ + this name (mid2agb -G).")
            }
        }
        SettingsFieldRow {
            width: page.width; unit: page.unit; labelWidth: page.labelWidth
            colors: page.colors; typography: page.typography
            label: qsTr("Master volume (-V):")
            SpinBox {
                id: volume
                objectName: "song.volume"
                anchors.fill: parent
                from: 0; to: 127; value: page.store.masterVolume
                font: page.typography.body
                editable: true
                onValueModified: page.store.changeMasterVolume(value)
                ToolTip.visible: hovered
                ToolTip.text: qsTr("mid2agb -V: scales every track volume (VOL × master ÷ 128).")
            }
        }
        SettingsFieldRow {
            width: page.width; unit: page.unit; labelWidth: page.labelWidth
            colors: page.colors; typography: page.typography
            label: qsTr("Reverb (-R):")
            SpinBox {
                id: songReverb
                objectName: "song.reverb"
                anchors.fill: parent
                from: -1; to: 127; value: page.store.reverb
                font: page.typography.body
                editable: true
                numberFormat: page.store.reverbFormat
                onValueModified: page.store.changeReverb(value)
                ToolTip.visible: hovered
                ToolTip.text: qsTr("mid2agb -R: song reverb level. Default leaves -R unspecified (50).")
            }
        }
        SettingsFieldRow {
            width: page.width; unit: page.unit; labelWidth: page.labelWidth
            colors: page.colors; typography: page.typography
            label: qsTr("Priority (-P):")
            SpinBox {
                id: songPriority
                objectName: "song.priority"
                anchors.fill: parent
                from: 0; to: 127; value: page.store.priority
                font: page.typography.body
                editable: true
                onValueModified: page.store.changePriority(value)
                ToolTip.visible: hovered
                ToolTip.text: qsTr("mid2agb -P: player priority (fanfares interrupt music).")
            }
        }
        // Legacy fork checkbox sizes are pinned by tst_ShellSettings reference rects.
        CheckBox {
            id: gate
            objectName: "song.exact-gate"
            width: page.width; height: 16 + 12 * (page.unit - 1)
            text: qsTr("Exact gate time (-E)"); checked: page.store.exactGate
            font: page.typography.body
            onClicked: page.store.changeExactGate(checked)
        }
        CheckBox {
            id: clocks
            objectName: "song.extended-clocks"
            width: page.width; height: 16 + 12 * (page.unit - 1)
            text: qsTr("48 clocks per beat (-X)"); checked: page.store.extendedClocks
            font: page.typography.body
            onClicked: page.store.changeExtendedClocks(checked)
        }
        CheckBox {
            id: compression
            objectName: "song.no-compression"
            width: page.width; height: 16 + 12 * (page.unit - 1)
            text: qsTr("Disable compression (-N)"); checked: page.store.noCompression
            font: page.typography.body
            onClicked: page.store.changeNoCompression(checked)
        }
    }
    Text {
        // Legacy fork footer position is pinned by tst_ShellSettings reference rects.
        x: 0; y: 199 * page.unit
        text: qsTr("Saved to this song's mid2agb flags (midi.cfg or songs.mk).")
        font: page.typography.body
        color: page.colors.secondaryText
    }
    Column {
        x: 0; y: 230 * page.unit
        width: page.width
        spacing: 8 * page.unit

        Text {
            text: qsTr("Master tuning (TUNE)")
            font: page.typography.body
            color: page.colors.windowText
        }
        Row {
            id: tuningRow
            width: parent.width
            spacing: 16 * page.unit
            Fusion.Dial {
                id: tuningDial
                objectName: "song.master-tuning"
                width: 72 * page.unit; height: 72 * page.unit
                from: page.store.masterTuningMinimumUnits
                to: page.store.masterTuningMaximumUnits
                stepSize: 1
                snapMode: Fusion.Dial.SnapAlways
                value: page.store.masterTuningUnits
                font: page.typography.body
                Accessible.name: qsTr("Song master tuning")
                Accessible.description: qsTr("One step is 1/64 semitone. Arrow keys change one step.")
                onMoved: page.store.changeMasterTuningUnits(Math.round(value))
            }
            Column {
                width: tuningRow.width - tuningDial.width - tuningRow.spacing
                spacing: 6 * page.unit
                Row {
                    spacing: 8 * page.unit
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("A4 Hz:")
                        font: page.typography.body
                        color: page.colors.windowText
                    }
                    Fusion.TextField {
                        id: tuningFrequency
                        objectName: "song.master-tuning-hz"
                        property bool edited: false
                        width: 100 * page.unit
                        font: page.typography.body
                        Component.onCompleted: tuningFrequency.text = page.store.masterTuningFrequencyText
                        selectByMouse: true
                        Accessible.name: qsTr("Nominal A4 frequency in Hz")
                        onTextEdited: tuningFrequency.edited = true
                        onActiveFocusChanged: {
                            if (activeFocus && !tuningFrequency.edited)
                                tuningFrequency.text = page.store.masterTuningFrequencyText
                        }
                        onEditingFinished: page.finishTuningEdit()
                    }
                    Button {
                        objectName: "song.master-tuning-reset"
                        text: qsTr("Reset to 440")
                        font: page.typography.body
                        onClicked: page.store.changeMasterTuningUnits(0)
                    }
                }
                Text {
                    objectName: "song.master-tuning-readback"
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Nominal A4: %1 Hz · %2 cents · %3 units")
                          .arg(page.store.masterTuningNominalFrequencyText)
                          .arg(page.store.masterTuningCentsText)
                          .arg(page.store.masterTuningUnits)
                    font: page.typography.body
                    color: page.colors.windowText
                }
            }
        }
        Text {
            objectName: "song.master-tuning-warning"
            width: parent.width
            wrapMode: Text.WordWrap
            text: qsTr("Warning: applying a master-tuning edit replaces all tracks’ Fine tune / TUNE (CC24) automation. Undo restores it.")
            font: page.typography.body
            color: page.colors.warningText
        }
        Text {
            objectName: "song.master-tuning-range"
            width: parent.width
            wrapMode: Text.WordWrap
            text: qsTr("Supported range: −64…+63 units. Each step is 1/64 semitone (1.5625 cents).")
            font: page.typography.body
            color: page.colors.secondaryText
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: qsTr("Saved MIDI exports ordinary TUNE commands; no converter changes needed. A4 is quantized and nominal, not exact for fixed-rate PCM or noise/PSG voices.")
            font: page.typography.body
            color: page.colors.secondaryText
        }
    }
    Connections {
        target: page.store
        function onMasterTuningFrequencyTextChanged(): void {
            if (!tuningFrequency.activeFocus && !tuningFrequency.edited)
                tuningFrequency.text = page.store.masterTuningFrequencyText
        }
    }
}
