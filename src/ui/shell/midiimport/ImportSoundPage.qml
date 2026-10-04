pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import PorydawApp

Item {
    id: page
    required property list<string> voicegroupOptions
    required property string voicegroupText
    required property int volume
    required property int reverb
    required property int priority
    required property bool exactGate
    required property bool extendedClocks
    required property bool noCompression
    required property GridPalette colors
    required property TypographyFonts typography
    required property LayoutSpaces layoutSpaces
    signal voicegroupEdited(string text)
    signal volumeEdited(int value)
    signal reverbEdited(int value)
    signal priorityEdited(int value)
    signal exactGateEdited(bool value)
    signal extendedClocksEdited(bool value)
    signal noCompressionEdited(bool value)
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
            model: page.voicegroupOptions
            currentIndex: page.voicegroupOptions.indexOf(page.voicegroupText)
            editText: page.voicegroupText
            onEditTextChanged: { if (activeFocus) page.voicegroupEdited(editText) }
            onActivated: page.voicegroupEdited(currentText)
            ToolTip.text: qsTr("The symbol is \"voicegroup_\" + this name (mid2agb -G).")
            ToolTip.visible: hovered
        }
        Label { Layout.row: 1; Layout.column: 0; text: qsTr("Master volume (-V):"); color: page.colors.windowText }
        SpinBox { objectName: "importVolume"; Layout.row: 1; Layout.column: 1; from: 0; to: 127; value: page.volume; onValueModified: page.volumeEdited(value) }
        Label { Layout.row: 2; Layout.column: 0; text: qsTr("Reverb (-R):"); color: page.colors.windowText }
        SpinBox { objectName: "importReverb"; Layout.row: 2; Layout.column: 1; from: 0; to: 127; value: page.reverb; onValueModified: page.reverbEdited(value) }
        Label { Layout.row: 3; Layout.column: 0; text: qsTr("Priority (-P):"); color: page.colors.windowText }
        SpinBox { objectName: "importPriority"; Layout.row: 3; Layout.column: 1; from: 0; to: 127; value: page.priority; onValueModified: page.priorityEdited(value) }
        CheckBox { objectName: "importExactGate"; Layout.row: 4; Layout.column: 1; text: qsTr("Exact gate time (-E)"); checked: page.exactGate; onToggled: page.exactGateEdited(checked) }
        CheckBox { objectName: "importExtendedClocks"; Layout.row: 5; Layout.column: 1; text: qsTr("48 clocks per beat (-X)"); checked: page.extendedClocks; onToggled: page.extendedClocksEdited(checked) }
        CheckBox { objectName: "importNoCompression"; Layout.row: 6; Layout.column: 1; text: qsTr("Disable compression (-N)"); checked: page.noCompression; onToggled: page.noCompressionEdited(checked) }
        Item { Layout.row: 7; Layout.columnSpan: 2; Layout.fillHeight: true }
    }
}
