pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

Item {
    id: view
    objectName: "splitStudioInspector"
    required property KitStudioWorkflow workflow
    required property KitStudioPresenter editor
    required property GridPalette colors
    required property real unit
    required property real paneSpacing
    required property font captionFont
    function pushAttack(v: real): void {
        view.editor.setZoneAdsr(
            Math.round(v), view.editor.selectedZoneDecay, view.editor.selectedZoneSustain,
            view.editor.selectedZoneRelease)
    }
    function pushDecay(v: real): void {
        view.editor.setZoneAdsr(
            view.editor.selectedZoneAttack, Math.round(v), view.editor.selectedZoneSustain,
            view.editor.selectedZoneRelease)
    }
    function pushSustain(v: real): void {
        view.editor.setZoneAdsr(
            view.editor.selectedZoneAttack, view.editor.selectedZoneDecay, Math.round(v),
            view.editor.selectedZoneRelease)
    }
    function pushRelease(v: real): void {
        view.editor.setZoneAdsr(
            view.editor.selectedZoneAttack, view.editor.selectedZoneDecay, view.editor.selectedZoneSustain,
            Math.round(v))
    }

    component Section: ColumnLayout {
        id: section
        required property string title
        required property GridPalette colors
        required property font captionFont
        required property real unit
        default property alias content: sectionBody.data
        Layout.fillWidth: true
        spacing: section.unit
        Label {
            text: section.title
            font: section.captionFont
            color: section.colors.secondaryText
            Component.onCompleted: {
                font.letterSpacing = section.unit / 13
                font.capitalization = Font.AllUppercase
            }
        }
        ColumnLayout {
            id: sectionBody
            Layout.fillWidth: true
            spacing: section.unit * 0.7
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: section.unit
            Layout.preferredHeight: 1
            color: section.colors.outline
        }
    }

    Rectangle {
        anchors.fill: parent
        color: view.colors.menuBackground
    }
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: Math.max(1, Math.round(view.unit / 13))
        color: view.colors.outline
    }
    ScrollView {
        anchors.fill: parent
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ColumnLayout {
            width: view.width - 2.5 * view.unit
            x: 1.25 * view.unit
            y: 1.25 * view.unit
            spacing: view.unit * 0.9
            Section {
                title: qsTr("Sample rate"); colors: view.colors; captionFont: view.captionFont; unit: view.unit
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6.5 * view.unit; text: qsTr("File"); color: view.colors.secondaryText }
                    Label { Layout.fillWidth: true; text: view.editor.fileRateText; color: view.colors.windowText }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6.5 * view.unit; text: qsTr("Saved at"); color: view.colors.secondaryText }
                    ComboBox {
                        objectName: "splitStudioSavedRate"
                        Layout.fillWidth: true
                        model: view.editor.rateChoices
                        currentIndex: view.workflow.sourceRateIndex(view.editor.sourceRate)
                        onActivated: index => view.workflow.chooseSourceRate(index)
                    }
                }
            }
            Section {
                title: qsTr("Selected key"); colors: view.colors; captionFont: view.captionFont; unit: view.unit
                visible: view.editor.selectedZone >= 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label {
                        text: view.workflow.keyName(view.editor.selectedZoneFirstKey)
                        font.pixelSize: 2 * view.unit
                        font.bold: true
                        color: view.colors.windowText
                    }
                    Rectangle {
                        Layout.preferredHeight: 1.7 * view.unit
                        Layout.preferredWidth: chipLabel.implicitWidth + 1.5 * view.unit
                        radius: 0.85 * view.unit
                        color: view.colors.buttonBackground
                        Label {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: "%1".arg(view.editor.selectedZoneFirstKey)
                            font: view.captionFont
                            color: view.colors.secondaryText
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6.5 * view.unit; text: qsTr("Slice"); color: view.colors.secondaryText }
                    Label {
                        Layout.fillWidth: true
                        text: view.editor.selectedZoneSampleName
                        color: view.colors.windowText
                        elide: Text.ElideRight
                    }
                }
            }
            Section {
                title: qsTr("Pitch"); colors: view.colors; captionFont: view.captionFont; unit: view.unit
                visible: view.editor.selectedZone >= 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6.5 * view.unit; text: qsTr("Plays at"); color: view.colors.secondaryText }
                    NoteStepper {
                        Layout.fillWidth: true
                        colors: view.colors
                        unit: view.unit
                        format: view.workflow.noteFormat
                        keyValue: view.editor.selectedZoneRootKey
                        onStepped: value => view.editor.setZoneRootKey(value)
                    }
                }
            }
            Section {
                title: qsTr("Pan"); colors: view.colors; captionFont: view.captionFont; unit: view.unit
                visible: view.editor.selectedZone >= 0 && view.editor.selectedZonePanEnabled
                Slider {
                    Layout.fillWidth: true
                    from: -64
                    to: 63
                    stepSize: 1
                    value: view.editor.selectedZonePan
                    Accessible.name: qsTr("Pan")
                    onMoved: view.editor.setZonePan(Math.round(value))
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { text: qsTr("L"); color: view.colors.secondaryText }
                    Item { Layout.fillWidth: true }
                    Label { text: "%1".arg(view.editor.selectedZonePan); color: view.colors.windowText }
                    Item { Layout.fillWidth: true }
                    Label { text: qsTr("R"); color: view.colors.secondaryText }
                }
            }
            Section {
                title: qsTr("Envelope"); colors: view.colors; captionFont: view.captionFont; unit: view.unit
                visible: view.editor.selectedZone >= 0
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6 * view.unit; text: qsTr("Attack"); color: view.colors.secondaryText }
                    Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: 255
                        stepSize: 1
                        value: view.editor.selectedZoneAttack
                        Accessible.name: qsTr("Attack")
                        onMoved: view.pushAttack(value)
                    }
                    Label { Layout.preferredWidth: 3 * view.unit; horizontalAlignment: Text.AlignRight; text: "%1".arg(view.editor.selectedZoneAttack); color: view.colors.windowText }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6 * view.unit; text: qsTr("Decay"); color: view.colors.secondaryText }
                    Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: 255
                        stepSize: 1
                        value: view.editor.selectedZoneDecay
                        Accessible.name: qsTr("Decay")
                        onMoved: view.pushDecay(value)
                    }
                    Label { Layout.preferredWidth: 3 * view.unit; horizontalAlignment: Text.AlignRight; text: "%1".arg(view.editor.selectedZoneDecay); color: view.colors.windowText }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6 * view.unit; text: qsTr("Sustain"); color: view.colors.secondaryText }
                    Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: 255
                        stepSize: 1
                        value: view.editor.selectedZoneSustain
                        Accessible.name: qsTr("Sustain")
                        onMoved: view.pushSustain(value)
                    }
                    Label { Layout.preferredWidth: 3 * view.unit; horizontalAlignment: Text.AlignRight; text: "%1".arg(view.editor.selectedZoneSustain); color: view.colors.windowText }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: view.paneSpacing
                    Label { Layout.preferredWidth: 6 * view.unit; text: qsTr("Release"); color: view.colors.secondaryText }
                    Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: 255
                        stepSize: 1
                        value: view.editor.selectedZoneRelease
                        Accessible.name: qsTr("Release")
                        onMoved: view.pushRelease(value)
                    }
                    Label { Layout.preferredWidth: 3 * view.unit; horizontalAlignment: Text.AlignRight; text: "%1".arg(view.editor.selectedZoneRelease); color: view.colors.windowText }
                }
            }
            Button {
                Layout.fillWidth: true
                text: qsTr("Remove from Key")
                palette.buttonText: view.colors.errorText
                visible: view.editor.selectedZone >= 0
                onClicked: view.editor.deleteZone(view.editor.selectedZone)
            }
            Item { Layout.fillHeight: true }
        }
    }
}
