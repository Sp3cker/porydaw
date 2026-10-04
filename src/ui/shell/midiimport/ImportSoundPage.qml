pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts

Item {
    id: page
    required property QtObject controller
    required property QtObject colors
    required property var typography
    required property var layoutSpaces
    onVisibleChanged: { if (visible) voicegroup.forceActiveFocus() }
    GridLayout {
        anchors.fill: parent
        anchors.margins: page.layoutSpaces.three
        columns: 2
        columnSpacing: page.layoutSpaces.three
        rowSpacing: page.layoutSpaces.three
        Label { Layout.row: 0; Layout.column: 0; text: qsTr("Voicegroup:"); color: page.colors.windowText }
        ComboBox {
            id: voicegroup
            objectName: "importVoicegroup"
            Layout.row: 0
            Layout.column: 1
            Layout.fillWidth: true
            editable: true
            model: page.controller.voicegroupOptions
            currentIndex: page.controller.voicegroupOptions.indexOf(page.controller.voicegroupText)
            editText: page.controller.voicegroupText
            onEditTextChanged: { if (activeFocus) page.controller.changeVoicegroupText(editText) }
            onActivated: page.controller.changeVoicegroupText(currentText)
            ToolTip.text: qsTr("The symbol is \"voicegroup_\" + this name (mid2agb -G).")
            ToolTip.visible: hovered
        }
        Label { Layout.row: 1; Layout.column: 0; text: qsTr("Master volume (-V):"); color: page.colors.windowText }
        SpinBox { objectName: "importVolume"; Layout.row: 1; Layout.column: 1; from: 0; to: 127; value: page.controller.volume; onValueModified: page.controller.changeVolume(value) }
        Label { Layout.row: 2; Layout.column: 0; text: qsTr("Reverb (-R):"); color: page.colors.windowText }
        SpinBox { objectName: "importReverb"; Layout.row: 2; Layout.column: 1; from: 0; to: 127; value: page.controller.reverb; onValueModified: page.controller.changeReverb(value) }
        Label { Layout.row: 3; Layout.column: 0; text: qsTr("Priority (-P):"); color: page.colors.windowText }
        SpinBox { objectName: "importPriority"; Layout.row: 3; Layout.column: 1; from: 0; to: 127; value: page.controller.priority; onValueModified: page.controller.changePriority(value) }
        CheckBox { objectName: "importExactGate"; Layout.row: 4; Layout.column: 1; text: qsTr("Exact gate time (-E)"); checked: page.controller.exactGate; onToggled: page.controller.changeExactGate(checked) }
        CheckBox { objectName: "importExtendedClocks"; Layout.row: 5; Layout.column: 1; text: qsTr("48 clocks per beat (-X)"); checked: page.controller.extendedClocks; onToggled: page.controller.changeExtendedClocks(checked) }
        CheckBox { objectName: "importNoCompression"; Layout.row: 6; Layout.column: 1; text: qsTr("Disable compression (-N)"); checked: page.controller.noCompression; onToggled: page.controller.changeNoCompression(checked) }
        Item { Layout.row: 7; Layout.columnSpan: 2; Layout.fillHeight: true }
    }
}
