pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

Dialog {
    id: dialog
    objectName: "splitStudioOrphanCleanupDialog"
    required property KitStudioWorkflow workflow
    required property GridPalette colors
    required property real baseFontPx
    required property LayoutSpaces layoutSpaces
    readonly property list<string> names: workflow.orphanCleanupNames
    anchors.centerIn: parent
    modal: true
    focus: true
    closePolicy: Popup.NoAutoClose
    width: Math.min(parent.width - 2 * dialog.baseFontPx, 36 * dialog.baseFontPx)
    title: qsTr("Clean up Split Studio samples?")
    visible: dialog.workflow.orphanCleanupOpen
    contentItem: ColumnLayout {
        spacing: dialog.layoutSpaces.four
        Label {
            objectName: "splitStudioOrphanPrompt"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: qsTr("These samples were created by Split Studio this app session and no voicegroup references them. Delete the checked files, or keep them?")
            color: dialog.colors.windowText
        }
        ListView {
            id: checklist
            acceptedButtons: Qt.NoButton
            objectName: "splitStudioOrphanChecklist"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(dialog.names.length * 3 * dialog.baseFontPx, 18 * dialog.baseFontPx)
            clip: true
            model: dialog.names
            enabled: !dialog.workflow.orphanCleanupBusy
            ScrollBar.vertical: ScrollBar {}
            delegate: CheckBox {
                id: sampleChoice
                required property string modelData
                width: checklist.width
                height: 3 * dialog.baseFontPx
                text: sampleChoice.modelData
                checked: dialog.workflow.orphanCleanupSelectedNames.includes(sampleChoice.modelData)
                onClicked: dialog.workflow.setOrphanCleanupSelected(sampleChoice.modelData, checked)
            }
        }
        Label {
            objectName: "splitStudioOrphanStatus"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: dialog.workflow.orphanCleanupStatus
            visible: text.length > 0
            color: dialog.colors.windowText
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: dialog.layoutSpaces.one
            Button {
                objectName: "splitStudioOrphanKeep"
                text: qsTr("Keep")
                enabled: !dialog.workflow.orphanCleanupBusy
                onClicked: dialog.workflow.answerOrphanCleanup(false)
            }
            Button {
                objectName: "splitStudioOrphanDelete"
                text: qsTr("Delete")
                enabled: !dialog.workflow.orphanCleanupBusy && dialog.names.length > 0
                onClicked: dialog.workflow.answerOrphanCleanup(true)
            }
        }
    }
}
