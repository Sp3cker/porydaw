import QtQuick
import QtQuick.Controls.Basic

Item {
    id: page
    required property QtObject store
    required property QtObject colors
    required property real unit
    required property font applicationFont
    readonly property real labelWidth: 125 + 102 * (unit - 1)
    readonly property real fieldX: labelWidth
    readonly property real fieldWidth: width - fieldX

    function finishVoicegroupEdit() {
        if (voicegroup.activeFocus && voicegroup.editText !== store.voicegroup)
            store.changeVoicegroup(voicegroup.editText)
    }
    function reset() {
        voicegroup.currentIndex = store.voicegroups.indexOf(store.voicegroup)
        voicegroup.editText = store.voicegroup
        volume.value = store.masterVolume
        songReverb.value = store.reverb
        songPriority.value = store.priority
        gate.checked = store.exactGate
        clocks.checked = store.extendedClocks
        compression.checked = store.noCompression
    }

    Text {
        x: 0; y: 11 * page.unit; width: page.labelWidth; height: 22 + 12 * (page.unit - 1)
        text: qsTr("Voicegroup:"); color: page.colors.windowText
        font.family: page.applicationFont.family; font.pixelSize: 12 * page.unit
        font.weight: Font.Bold; verticalAlignment: Text.AlignVCenter
    }
    ComboBox {
        id: voicegroup
        objectName: "song.voicegroup"
        x: page.fieldX; y: 11 * page.unit
        width: page.fieldWidth; height: 22 + 12 * (page.unit - 1)
        editable: true; model: page.store.voicegroups
        font.weight: Font.Bold
        editText: page.store.voicegroup
        currentIndex: page.store.voicegroups.indexOf(page.store.voicegroup)
        onModelChanged: {
            if (!activeFocus) {
                currentIndex = page.store.voicegroups.indexOf(page.store.voicegroup)
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
    Text {
        x: 0; y: 39 + 24 * (page.unit - 1); width: page.labelWidth; height: 25 + 15 * (page.unit - 1)
        text: qsTr("Master volume (-V):"); color: page.colors.windowText
        font.family: page.applicationFont.family; font.pixelSize: 12 * page.unit
        font.weight: Font.Bold; verticalAlignment: Text.AlignVCenter
    }
    SpinBox {
        id: volume
        objectName: "song.volume"
        x: page.fieldX; y: 39 + 24 * (page.unit - 1)
        width: page.fieldWidth; height: 25 + 15 * (page.unit - 1)
        from: 0; to: 127; value: page.store.masterVolume
        editable: true
        font.weight: Font.Bold
        onValueModified: page.store.changeMasterVolume(value)
        ToolTip.visible: hovered
        ToolTip.text: qsTr("mid2agb -V: scales every track volume (VOL × master ÷ 128).")
    }
    Text {
        x: 0; y: 70 + 39 * (page.unit - 1); width: page.labelWidth; height: 25 + 15 * (page.unit - 1)
        text: qsTr("Reverb (-R):"); color: page.colors.windowText
        font.family: page.applicationFont.family; font.pixelSize: 12 * page.unit
        font.weight: Font.Bold; verticalAlignment: Text.AlignVCenter
    }
    SpinBox {
        id: songReverb
        objectName: "song.reverb"
        x: page.fieldX; y: 70 + 39 * (page.unit - 1)
        width: page.fieldWidth; height: 25 + 15 * (page.unit - 1)
        from: -1; to: 127; value: page.store.reverb
        editable: true
        font.weight: Font.Bold
        textFromValue: value => value === -1 ? qsTr("Default (50)") : String(value)
        valueFromText: text => text.startsWith(qsTr("Default")) ? -1 : parseInt(text, 10)
        onValueModified: page.store.changeReverb(value)
        ToolTip.visible: hovered
        ToolTip.text: qsTr("mid2agb -R: song reverb level. Default leaves -R unspecified (50).")
    }
    Text {
        x: 0; y: 101 + 54 * (page.unit - 1); width: page.labelWidth; height: 25 + 15 * (page.unit - 1)
        text: qsTr("Priority (-P):"); color: page.colors.windowText
        font.family: page.applicationFont.family; font.pixelSize: 12 * page.unit
        font.weight: Font.Bold; verticalAlignment: Text.AlignVCenter
    }
    SpinBox {
        id: songPriority
        objectName: "song.priority"
        x: page.fieldX; y: 101 + 54 * (page.unit - 1)
        width: page.fieldWidth; height: 25 + 15 * (page.unit - 1)
        from: 0; to: 127; value: page.store.priority
        editable: true
        font.weight: Font.Bold
        onValueModified: page.store.changePriority(value)
        ToolTip.visible: hovered
        ToolTip.text: qsTr("mid2agb -P: player priority (fanfares interrupt music).")
    }
    CheckBox {
        id: gate
        objectName: "song.exact-gate"
        x: 0; y: 132 + 69 * (page.unit - 1); width: page.width; height: 16 + 12 * (page.unit - 1)
        text: qsTr("Exact gate time (-E)"); checked: page.store.exactGate
        font.weight: Font.Bold
        onClicked: page.store.changeExactGate(checked)
    }
    CheckBox {
        id: clocks
        objectName: "song.extended-clocks"
        x: 0; y: 154 + 81 * (page.unit - 1); width: page.width; height: 16 + 12 * (page.unit - 1)
        text: qsTr("48 clocks per beat (-X)"); checked: page.store.extendedClocks
        font.weight: Font.Bold
        onClicked: page.store.changeExtendedClocks(checked)
    }
    CheckBox {
        id: compression
        objectName: "song.no-compression"
        x: 0; y: 176 + 93 * (page.unit - 1); width: page.width; height: 16 + 12 * (page.unit - 1)
        text: qsTr("Disable compression (-N)"); checked: page.store.noCompression
        font.weight: Font.Bold
        onClicked: page.store.changeNoCompression(checked)
    }
    Text {
        x: 0; y: 199 * page.unit
        text: qsTr("Saved to this song's mid2agb flags (midi.cfg or songs.mk).")
        color: page.colors.secondaryText; font: page.applicationFont
    }
}
