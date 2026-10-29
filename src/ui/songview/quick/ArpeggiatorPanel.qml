pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Fusion as Fusion
import Porydaw.Ui
import PorydawApp as App

PromptOverlay {
    id: root
    objectName: "arpeggiatorPanel"
    required property App.ArpeggiatorPresenter model
    required focusOrigin
    property App.MouseHints hintService: null
    readonly property real unit: model.baseFontPx
    overlayOpen: model.isOpen
    cardItem: card
    underlayObjectName: "arpeggiatorUnderlay"
    dismissOnlyOutsideCard: true
    consumeDismissPress: true
    preventUnderlayStealing: true
    z: 100
    onInitialFocusRequested: master.focusItem.forceActiveFocus(Qt.PopupFocusReason)
    onOverlayClosed: restoreFocusIfOwned()
    onDismissRequested: model.close()

    component Caption: Text {
        font: root.model.bodyFont
        color: root.model.colors.windowText
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
    }

    component Choice: Fusion.Button {
        id: choice
        property bool selected: false
        font: root.model.bodyFont
        focusPolicy: Qt.StrongFocus
        implicitHeight: label.implicitHeight + root.model.promptStyle.buttonPadding * 2
        implicitWidth: label.implicitWidth + root.model.promptStyle.buttonPadding * 2
        Accessible.name: text
        Accessible.description: selected ? qsTr("Selected") : ""
        contentItem: Text {
            id: label
            text: choice.text
            font: choice.font
            color: !choice.enabled ? root.model.colors.disabledText
                : choice.down || choice.selected ? root.model.colors.buttonPressedText : root.model.colors.buttonText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            renderType: Text.NativeRendering
        }
        background: Rectangle {
            radius: root.model.promptStyle.radius
            color: choice.down || choice.selected ? root.model.colors.buttonPressedBackground : root.model.colors.buttonBackground
            border.width: root.model.promptStyle.borderWidth
            border.color: choice.activeFocus ? root.model.promptStyle.focus : root.model.colors.outline
        }
    }

    component Selector: RowLayout {
        id: selector
        property string text: ""
        property bool selected: false
        property string description: ""
        property bool exclusive: true
        signal clicked()
        spacing: root.model.promptStyle.spacing

        Fusion.Button {
            id: toggle
            Layout.preferredWidth: root.unit * 1.6
            Layout.preferredHeight: root.unit * 1.3
            focusPolicy: Qt.StrongFocus
            Accessible.name: selector.text
            Accessible.description: qsTr("%1. %2")
                .arg(selector.selected ? qsTr("On") : qsTr("Off")).arg(selector.description)
            Accessible.role: selector.exclusive ? Accessible.RadioButton : Accessible.CheckBox
            Accessible.checkable: true
            Accessible.checked: selector.selected
            onClicked: selector.clicked()
            Keys.onReturnPressed: event => { selector.clicked(); event.accepted = true }
            Keys.onEnterPressed: event => { selector.clicked(); event.accepted = true }
            contentItem: Item {}
            background: Rectangle {
                radius: root.model.promptStyle.radius
                color: toggle.down || selector.selected
                    ? root.model.colors.buttonPressedBackground : root.model.colors.buttonBackground
                border.width: root.model.promptStyle.borderWidth
                border.color: toggle.activeFocus ? root.model.promptStyle.focus : root.model.colors.outline
            }
        }
        Text {
            text: selector.text
            font: root.model.bodyFont
            color: selector.enabled ? root.model.colors.windowText : root.model.colors.disabledText
            renderType: Text.NativeRendering
            textFormat: Text.PlainText
            Accessible.ignored: true
        }
    }

    component Knob: ArpeggiatorKnob {
        appearance: root.model.promptStyle
        colors: root.model.colors
        baseFontPx: root.unit
        hintService: root.hintService
    }

    PromptCard {
        id: card
        objectName: "arpeggiatorCard"
        anchors.centerIn: parent
        appearance: root.model.promptStyle
        width: implicitWidth
        height: implicitHeight
        Accessible.role: Accessible.Dialog
        Accessible.name: qsTr("Track arpeggiator")
        Keys.onShortcutOverride: event => event.accepted = event.key !== Qt.Key_Space
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape)
                root.model.close()
            event.accepted = true
        }
        Keys.onReleased: event => event.accepted = true

        ColumnLayout {
            width: Math.min(Math.max(0, root.width - 2 * card.appearance.dialogPadding),
                            Math.max(root.unit * 58, controls.implicitWidth, pads.implicitWidth))
            spacing: card.appearance.spacing

            RowLayout {
                Layout.fillWidth: true
                Caption { text: qsTr("Arpeggiator"); font.bold: true }
                Item { Layout.fillWidth: true }
                Caption { text: root.model.sourceLabel }
                Caption { text: root.model.rangeLabel }
            }

            RowLayout {
                id: controls
                Layout.fillWidth: true
                spacing: root.unit * 1.5
                Column {
                    Layout.alignment: Qt.AlignTop
                    spacing: card.appearance.spacing
                    Knob {
                        id: master
                        objectName: "arpeggiatorMaster"
                        label: qsTr("Master")
                        suffix: qsTr("%")
                        minimumValue: 0; maximumValue: 100
                        value: root.model.masterVelocity
                        onValueCommitted: value => root.model.setParameter("masterVelocity", value)
                    }
                    Knob {
                        objectName: "arpeggiatorTranspose"
                        label: qsTr("Transpose")
                        minimumValue: -12; maximumValue: 12
                        value: root.model.transpose
                        onValueCommitted: value => root.model.setParameter("transpose", value)
                    }
                    Knob {
                        objectName: "arpeggiatorAccent"
                        label: qsTr("Accent")
                        suffix: qsTr("%")
                        minimumValue: -100; maximumValue: 100
                        value: root.model.accentAmount
                        onValueCommitted: value => root.model.setParameter("accentAmount", value)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: card.appearance.spacing
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: root.unit
                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            Caption { text: qsTr("Rate") }
                            Repeater {
                                readonly property list<int> rateIndices: [7, 9, 11]
                                model: rateIndices
                                delegate: Selector {
                                    required property int modelData
                                    Layout.fillWidth: true
                                    text: root.model.rateLabels[modelData]
                                    selected: root.model.rateIndex === modelData
                                    enabled: { root.model.stepRevision; return root.model.rateAvailable(modelData) }
                                    onClicked: root.model.setParameter("rateIndex", modelData)
                                }
                            }
                            Choice {
                                id: customRate
                                Layout.fillWidth: true
                                text: qsTr("More: %1").arg(root.model.rateLabels[root.model.rateIndex])
                                onClicked: rateMenu.open()
                                Fusion.Menu {
                                    id: rateMenu
                                    Repeater {
                                        model: root.model.rateLabels
                                        delegate: Fusion.MenuItem {
                                            required property int index
                                            required property string modelData
                                            text: modelData
                                            font: root.model.bodyFont
                                            checkable: true
                                            checked: root.model.rateIndex === index
                                            enabled: { root.model.stepRevision; return root.model.rateAvailable(index) }
                                            onTriggered: root.model.setParameter("rateIndex", index)
                                        }
                                    }
                                }
                            }
                            Caption { text: qsTr("Trigger"); Layout.topMargin: card.appearance.spacing }
                            Selector {
                                text: qsTr("Keyboard")
                                exclusive: false
                                selected: root.model.restartOnNoteOn
                                description: qsTr("Restart the pattern on source note-on. When off, restart at the pattern length.")
                                onClicked: root.model.setRestartOnNoteOn(!root.model.restartOnNoteOn)
                            }
                        }
                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            Caption { text: qsTr("Mode") }
                            Repeater {
                                readonly property list<string> labels: [qsTr("Up"), qsTr("Down"), qsTr("Up / Down"), qsTr("Manual"), qsTr("Poly"), qsTr("Custom")]
                                model: labels
                                delegate: Selector {
                                    required property int index
                                    required property string modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    selected: root.model.mode === index
                                    onClicked: root.model.setParameter("mode", index)
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            Caption { text: qsTr("Octave") }
                            Repeater {
                                model: 4
                                delegate: Selector {
                                    required property int index
                                    Layout.fillWidth: true
                                    text: qsTr("%1 octave(s)").arg(index + 1)
                                    selected: root.model.octaves === index + 1
                                    onClicked: root.model.setParameter("octaves", index + 1)
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            Caption { text: qsTr("Insert") }
                            Repeater {
                                readonly property list<string> labels: [qsTr("Off"), qsTr("Lowest"), qsTr("Highest")]
                                model: labels
                                delegate: Selector {
                                    required property int index
                                    required property string modelData
                                    Layout.fillWidth: true
                                    text: modelData
                                    selected: root.model.insert === index
                                    enabled: { root.model.stepRevision; return root.model.insertAvailable(index) }
                                    onClicked: root.model.setParameter("insert", index)
                                }
                            }
                        }
                    }
                    Caption { text: qsTr("Custom pattern · 1–9 / R / –") }
                    Fusion.TextField {
                        id: pattern
                        objectName: "arpeggiatorCustomPattern"
                        Layout.fillWidth: true
                        font: root.model.bodyFont
                        text: root.model.customPattern
                        maximumLength: 8
                        selectByMouse: true
                        Keys.onSpacePressed: event => {
                            if (!event.isAutoRepeat)
                                root.model.toggleAudition()
                            event.accepted = true
                        }
                        Accessible.name: qsTr("Custom pattern")
                        Accessible.description: qsTr("Up to eight characters. 1–9 select pitches, R chooses randomly, and hyphen is unused padding.")
                        onTextEdited: root.model.setCustomPattern(text)
                        color: root.model.colors.windowText
                        selectionColor: card.appearance.selection
                        selectedTextColor: root.model.colors.selectionText
                        background: Rectangle {
                            color: root.model.colors.inputBackground
                            border.width: card.appearance.borderWidth
                            border.color: pattern.activeFocus ? card.appearance.focus : root.model.colors.outline
                            radius: card.appearance.radius
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                Column {
                    Layout.alignment: Qt.AlignTop
                    spacing: card.appearance.spacing
                    Knob {
                        objectName: "arpeggiatorShuffle"
                        label: qsTr("Shuffle")
                        suffix: qsTr("%")
                        minimumValue: 0; maximumValue: 99
                        value: root.model.shuffle
                        onValueCommitted: value => root.model.setParameter("shuffle", value)
                    }
                    Knob {
                        objectName: "arpeggiatorGate"
                        label: qsTr("Gate")
                        suffix: qsTr("%")
                        description: qsTr("10–100 percent; 101 is Tie. Effective clock duration is shown below.")
                        minimumValue: 10; maximumValue: 101
                        value: root.model.gate
                        onValueCommitted: value => root.model.setParameter("gate", value)
                    }
                    Choice {
                        objectName: "arpeggiatorAudition"
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.model.isAuditioning ? qsTr("Stop audition") : qsTr("Audition")
                        selected: root.model.isAuditioning
                        enabled: root.model.canCopy || root.model.isAuditioning
                        onClicked: root.model.toggleAudition()
                    }
                    Knob {
                        objectName: "arpeggiatorSteps"
                        label: qsTr("Steps")
                        minimumValue: 1; maximumValue: 32
                        value: root.model.steps
                        onValueCommitted: value => root.model.setParameter("steps", value)
                    }
                }
            }

            GridLayout {
                id: pads
                Layout.fillWidth: true
                columns: 16
                rowSpacing: card.appearance.spacing / 2
                columnSpacing: card.appearance.spacing / 2
                Repeater {
                    id: padRepeater
                    model: 32
                    delegate: ArpeggiatorStepPad {
                        required property int index
                        objectName: "arpeggiatorStep" + (index + 1)
                        Layout.fillWidth: true
                        appearance: card.appearance
                        colors: root.model.colors
                        baseFontPx: root.unit
                        stepIndex: index
                        enabled: index < root.model.steps
                        stepOn: { root.model.stepRevision; return root.model.stepEnabled(index) }
                        accented: { root.model.stepRevision; return root.model.stepAccented(index) }
                        playing: root.model.currentStep === index
                        onEdited: accent => root.model.toggleStep(index, accent)
                        Keys.onLeftPressed: event => { const target = padRepeater.itemAt((index + root.model.steps - 1) % root.model.steps); if (target) target.forceActiveFocus(); event.accepted = true }
                        Keys.onRightPressed: event => { const target = padRepeater.itemAt((index + 1) % root.model.steps); if (target) target.forceActiveFocus(); event.accepted = true }
                        Keys.onUpPressed: event => { const target = padRepeater.itemAt(index >= 16 ? index - 16 : index); if (target) target.forceActiveFocus(); event.accepted = true }
                        Keys.onDownPressed: event => { const target = padRepeater.itemAt(index + 16 < root.model.steps ? index + 16 : index); if (target) target.forceActiveFocus(); event.accepted = true }
                    }
                }
            }
            Caption {
                text: qsTr("Pads: click / Return = on or off · right click / Shift+Return = accent · • accented · ▶ playing")
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            Caption {
                objectName: "arpeggiatorTiming"
                text: root.model.timingLabel
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
            Caption {
                objectName: "arpeggiatorStatus"
                Layout.fillWidth: true
                text: root.model.status
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                Choice {
                    objectName: "arpeggiatorCopyNotes"
                    text: qsTr("Copy Notes")
                    enabled: root.model.canCopy
                    onClicked: root.model.copyNotes()
                }
                Choice {
                    objectName: "arpeggiatorReshuffle"
                    text: qsTr("Reshuffle")
                    onClicked: root.model.reshuffle()
                }
                Item { Layout.fillWidth: true }
                Choice {
                    objectName: "arpeggiatorClose"
                    text: qsTr("Close")
                    onClicked: root.model.close()
                    KeyNavigation.tab: master.focusItem
                }
            }
        }
    }
}
