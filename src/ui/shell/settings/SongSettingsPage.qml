pragma ComponentBehavior: Bound

import QtQuick
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
    function reset(): void {
        voicegroup.currentIndex = page.voicegroups.indexOf(page.store.voicegroup)
        voicegroup.editText = page.store.voicegroup
        volume.value = page.store.masterVolume
        songReverb.value = page.store.reverb
        songPriority.value = page.store.priority
        gate.checked = page.store.exactGate
        clocks.checked = page.store.extendedClocks
        compression.checked = page.store.noCompression
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
                onAccepted: page.finishVoicegroupEdit()
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
                textFromValue: function(value: int): string { return value === -1 ? qsTr("Default (50)") : String(value) }
                valueFromText: function(text: string): real { return text.startsWith(qsTr("Default")) ? -1 : parseInt(text, 10) }
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
}
