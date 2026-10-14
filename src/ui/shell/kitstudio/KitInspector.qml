pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

ScrollView {
    id: view
    objectName: "splitStudioInspector"
    required property KitStudioWorkflow workflow
    required property KitStudioPresenter editor
    required property GridPalette colors
    required property real unit
    required property real paneSpacing
    required property font captionFont
    ScrollBar.vertical.policy: ScrollBar.AsNeeded
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
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
        required property real paneSpacing
        default property alias content: sectionBody.data
        Layout.fillWidth: true
        spacing: section.paneSpacing
        Label { text: section.title; font: section.captionFont; color: section.colors.secondaryText }
        ColumnLayout {
            id: sectionBody
            Layout.fillWidth: true
            spacing: section.paneSpacing
        }
    }

    ColumnLayout {
        width: view.availableWidth
        spacing: 2 * view.paneSpacing
        Section {
            title: qsTr("Sample rate"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
            RowLayout {
                Layout.fillWidth: true
                spacing: view.paneSpacing
                Label { text: qsTr("File"); color: view.colors.windowText }
                Item { Layout.fillWidth: true }
                Label { text: view.editor.fileRateText; color: view.colors.windowText }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: view.paneSpacing
                Label { text: qsTr("Saved at"); color: view.colors.windowText }
                Item { Layout.fillWidth: true }
                ComboBox {
                    objectName: "splitStudioSavedRate"
                    model: view.editor.rateChoices
                    currentIndex: view.workflow.sourceRateIndex(view.editor.sourceRate)
                    onActivated: index => view.workflow.chooseSourceRate(index)
                }
            }
        }
        Section {
            title: qsTr("Selected key"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
            visible: view.editor.selectedZone >= 0
            RowLayout {
                Layout.fillWidth: true
                spacing: view.paneSpacing
                Label {
                    text: view.workflow.keyName(view.editor.selectedZoneFirstKey)
                    font.pixelSize: 2 * view.unit
                    color: view.colors.windowText
                }
                Label { text: "%1".arg(view.editor.selectedZoneFirstKey); color: view.colors.windowText }
                Item { Layout.fillWidth: true }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: view.paneSpacing
                Label { text: qsTr("Slice"); color: view.colors.windowText }
                Label {
                    Layout.fillWidth: true
                    text: view.editor.selectedZoneSampleName
                    color: view.colors.windowText
                    elide: Text.ElideRight
                }
            }
        }
        Section {
            title: qsTr("Pitch"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
            visible: view.editor.selectedZone >= 0
            RowLayout {
                Layout.fillWidth: true
                spacing: view.paneSpacing
                Label { text: qsTr("Plays at"); color: view.colors.windowText }
                Item { Layout.fillWidth: true }
                SpinBox {
                    id: rootSpin
                    Layout.preferredWidth: 5 * view.unit
                    from: 0
                    to: 127
                    value: view.editor.selectedZoneRootKey
                    Accessible.name: qsTr("Root key")
                    numberFormat: view.workflow.noteFormat
                    onValueModified: view.editor.setZoneRootKey(value)
                }
            }
        }
        Section {
            title: qsTr("Pan"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
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
                Label { text: qsTr("L"); color: view.colors.windowText }
                Item { Layout.fillWidth: true }
                Label { text: "%1".arg(view.editor.selectedZonePan); color: view.colors.windowText }
                Item { Layout.fillWidth: true }
                Label { text: qsTr("R"); color: view.colors.windowText }
            }
        }
        Section {
            title: qsTr("Envelope"); colors: view.colors; captionFont: view.captionFont; paneSpacing: view.paneSpacing
            visible: view.editor.selectedZone >= 0
            RowLayout {
                Layout.fillWidth: true
                spacing: view.paneSpacing
                Label { Layout.preferredWidth: 6 * view.unit; text: qsTr("Attack"); color: view.colors.windowText }
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
                Label { Layout.preferredWidth: 6 * view.unit; text: qsTr("Decay"); color: view.colors.windowText }
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
                Label { Layout.preferredWidth: 6 * view.unit; text: qsTr("Sustain"); color: view.colors.windowText }
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
                Label { Layout.preferredWidth: 6 * view.unit; text: qsTr("Release"); color: view.colors.windowText }
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
