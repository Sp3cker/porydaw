// DISPOSABLE static Voicegroup reference — merge-day geometry/color/strings, not behavior.
// Mirrors src/ui/voicegroupbrowser.{h,cpp} layout and strings. Editor rows are all
// shown statically; production gates them per family in setEditorRowsVisible and that
// behavior is proven by src/checks/visual/browsers.cpp, not here. No controller
// coupling: no VoicegroupSource/LoadedBankView/AudioEngine reference, no emitted
// signals. Deliberately NOT referenced by Main.qml or CMakeLists.txt so the frozen
// prototype smoke is untouched. Delete when the real source-backed panel lands in
// swift-qml-grid; do not wire production behavior through this file.
//
// Production notes captured here:
// - Selector row: "voicegroup_" label + editable combo (objectName vgArgCombo),
//   placeholder "No song loaded" / "Loading...", tooltip with -G explanation.
// - Tree: 3 columns Voice/Type/ADSR, Voice stretch, Type fixed at icon +
//   padding, 128 stable rows never cleared; row text "NNN  <name>" with the
//   DirectSoundWave[Data_] prefix shed; type cell is a themed icon (here a
//   sized placeholder carrying the display name as tooltip); ADSR engine values.
// - Used-by-song rows: 30% accent tint + "Used by this song" tooltip.
// - Loading: every row "NNN  Loading...", selector/editors disabled in place,
//   geometry never shifts.
// - Editor form rows: notice, Type, Sample/symbol + picker + New/Edit glyph
//   buttons, Sweep (time/dir/shift), Duty, Period, Waveform, Duty LFO (4 spins),
//   ADSR (4 spins), New… button. Buttons are NoFocus; Space stays transport.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

pragma ComponentBehavior: Bound

FocusScope {
    id: root

    required property font font
    required property real baseFontPx
    required property var gridPalette

    // Fixture voices covering every production row/editor state.
    property var voices: [
        { slot: 0, name: "wave000", type: "Sample", adsr: "255 255 255 255", used: true, family: "sample", readOnly: false, blank: false },
        { slot: 4, name: "square1", type: "Square 1", adsr: "7 7 15 7", used: false, family: "square1", readOnly: false, blank: false },
        { slot: 7, name: "progwave", type: "ProgWave", adsr: "3 2 8 1", used: true, family: "wave", readOnly: false, blank: false },
        { slot: 9, name: "noise", type: "Noise", adsr: "5 5 10 5", used: false, family: "noise", readOnly: false, blank: false },
        { slot: 12, name: "cry_voice", type: "Cry", adsr: "0 0 0 0", used: false, family: "cry", readOnly: true, blank: false },
        { slot: 20, name: "keysplit", type: "Keysplit", adsr: "", used: false, family: "keysplit", readOnly: false, blank: false },
        { slot: 24, name: "drumkit", type: "Drumkit", adsr: "", used: false, family: "drumkit", readOnly: false, blank: false },
        { slot: 30, name: "synth_lead", type: "Synth (Golden Sun)", adsr: "200 180 220 190", used: false, family: "synth", readOnly: false, blank: false },
        { slot: 64, name: "", type: "Sample", adsr: "", used: false, family: "sample", readOnly: false, blank: true }
    ]
    property int currentSlot: 0
    property bool loading: false

    readonly property int pad: Math.max(1, Math.round(baseFontPx * 0.5))
    readonly property int halfPad: Math.max(1, Math.round(baseFontPx * 0.25))
    readonly property real iconPx: baseFontPx * 1.25
    readonly property color rowText: gridPalette.windowText
    readonly property color dimText: gridPalette.secondaryText
    readonly property color selectedRow: gridPalette.tabSelectedBackground
    readonly property color usedTint: "#4D50B9E8"
    readonly property color hairline: gridPalette.outline

    function rowLabel(voice) {
        if (root.loading)
            return "%1  %2".arg(voice.slot, 3, 10, "0").arg(qsTr("Loading..."));
        const shown = voice.name === "" ? voice.type : voice.name;
        return "%1  %2".arg(voice.slot, 3, 10, "0").arg(shown);
    }

    function currentVoice() {
        return root.voices.find(v => v.slot === root.currentSlot) ?? root.voices[0];
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.halfPad

        // ---- selector row: voicegroup_ + editable arg combo ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 2
            Layout.leftMargin: 4
            Layout.rightMargin: 4

            Label {
                font: root.font
                color: root.rowText
                text: "voicegroup_"
            }
            ComboBox {
                id: vgCombo
                objectName: "vgArgCombo"
                Layout.fillWidth: true
                font: root.font
                editable: true
                enabled: !root.loading
                model: ["abandoned_ship", "rival", "dummy"]
                ToolTip.text: qsTr("The song's voicegroup: the prefix plus this name form the symbol, e.g. \"abandoned_ship\" → voicegroup_abandoned_ship (mid2agb -G). Changing it is undoable.")
                ToolTip.visible: hovered
            }
        }

        // ---- tree header + rows ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    leftPadding: root.pad
                    font: root.font
                    color: root.dimText
                    text: qsTr("Voice")
                }
                Label {
                    Layout.preferredWidth: Math.round(root.iconPx + 2 * root.pad + 40)
                    font: root.font
                    color: root.dimText
                    text: qsTr("Type")
                }
                Label {
                    Layout.preferredWidth: 90
                    font: root.font
                    color: root.dimText
                    text: qsTr("ADSR")
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.hairline
            }

            ListView {
                id: voiceList
                objectName: "vgVoiceTree"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.voices
                delegate: ItemDelegate {
                    id: rowDelegate
                    required property var modelData
                    required property int index
                    width: voiceList.width
                    font: root.font
                    highlighted: modelData.slot === root.currentSlot
                    ToolTip.visible: hovered && modelData.used
                    ToolTip.text: qsTr("Used by this song")
                    contentItem: RowLayout {
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            leftPadding: root.pad
                            text: root.rowLabel(rowDelegate.modelData)
                            font: root.font
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                            color: root.rowText
                        }
                        // Type icon placeholder: production inks a themed glyph
                        // at iconPx; the display name rides as tooltip here.
                        Rectangle {
                            Layout.preferredWidth: Math.round(root.iconPx)
                            Layout.preferredHeight: Math.round(root.iconPx)
                            Layout.alignment: Qt.AlignVCenter
                            color: "transparent"
                            border.width: 1
                            border.color: root.hairline
                            Text {
                                anchors.centerIn: parent
                                text: rowDelegate.modelData.type.charAt(0)
                                font.pixelSize: Math.round(root.baseFontPx * 0.8)
                                color: root.dimText
                            }
                        }
                        Text {
                            Layout.preferredWidth: 90
                            text: rowDelegate.modelData.adsr
                            font: root.font
                            elide: Text.ElideRight
                            renderType: Text.NativeRendering
                            color: root.dimText
                        }
                    }
                    background: Rectangle {
                        color: {
                            if (rowDelegate.highlighted)
                                return root.selectedRow;
                            if (rowDelegate.modelData.used)
                                return root.usedTint;
                            return "transparent";
                        }
                    }
                    onClicked: root.currentSlot = modelData.slot
                }
            }
        }

        // ---- editor form for the selected voice ----
        GridLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.pad
            Layout.rightMargin: root.pad
            columns: 2
            columnSpacing: root.halfPad
            rowSpacing: root.halfPad
            enabled: !root.loading

            Label {
                objectName: "voicegroupEditorNotice"
                Layout.columnSpan: 2
                Layout.fillWidth: true
                font: root.font
                wrapMode: Text.WordWrap
                visible: text !== ""
                color: root.dimText
                text: {
                    const v = root.currentVoice();
                    if (v.readOnly)
                        return qsTr("This voice is read-only and cannot be edited.");
                    if (v.blank)
                        return qsTr("Empty slot: editing materializes a new voice here.");
                    return "";
                }
            }
            Label {
                font: root.font
                color: root.rowText
                text: qsTr("Type")
            }
            ComboBox {
                Layout.fillWidth: true
                font: root.font
                model: ["Sample", "Sample (no resample)", "Sample (alt)", "Keysplit (all)", "Square 1", "Square 2", "ProgWave", "Noise"]
            }
            Label {
                font: root.font
                color: root.rowText
                text: qsTr("Sample")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 2
                ComboBox {
                    Layout.fillWidth: true
                    font: root.font
                    editable: true
                    model: ["wave000", "wave001", "keysplit_table"]
                }
                ToolButton {
                    objectName: "vgNewSampleButton"
                    font: root.font
                    text: "+"
                    focusPolicy: Qt.NoFocus
                    ToolTip.text: qsTr("New sample: import a sample and assign it to this voice.")
                    ToolTip.visible: hovered
                }
                ToolButton {
                    objectName: "vgEditSampleButton"
                    font: root.font
                    text: "✎"
                    focusPolicy: Qt.NoFocus
                    ToolTip.text: qsTr("Edit sample: reopen this voice's sample in Sample Editor.")
                    ToolTip.visible: hovered
                }
            }
            Label {
                font: root.font
                color: root.rowText
                text: qsTr("Sweep")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.halfPad
                SpinBox {
                    Layout.fillWidth: true
                    font: root.font
                    from: 0
                    to: 7
                    ToolTip.text: qsTr("Speed: 128 Hz clocks between pitch steps (1 = fastest, 7 = slowest, Off = no sweep).")
                    ToolTip.visible: hovered
                }
                ComboBox {
                    Layout.fillWidth: true
                    font: root.font
                    model: [qsTr("Rise"), qsTr("Fall")]
                }
                SpinBox {
                    Layout.fillWidth: true
                    font: root.font
                    from: 0
                    to: 7
                }
            }
            Label {
                font: root.font
                color: root.rowText
                text: qsTr("ADSR")
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: root.halfPad
                Repeater {
                    id: adsrRepeater
                    model: [qsTr("Attack"), qsTr("Decay"), qsTr("Sustain"), qsTr("Release")]
                    SpinBox {
                        required property int index
                        Layout.fillWidth: true
                        from: 0
                        to: 255
                        ToolTip.text: adsrRepeater.model[index]
                        ToolTip.visible: hovered
                    }
                }
            }
            Button {
                text: qsTr("New…")
                focusPolicy: Qt.NoFocus
                ToolTip.text: qsTr("Create a new voicegroup file.")
                ToolTip.visible: hovered
            }
        }
    }
}
