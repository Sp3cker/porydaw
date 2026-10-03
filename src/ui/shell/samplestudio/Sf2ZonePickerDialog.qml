import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Porydaw.Ui
import PorydawApp

DialogWindow {
    id: dialog
    objectName: "sf2ZonePickerDialog"
    required property SampleStudioWorkflow workflow
    required property Sf2ZonePickerPresenter picker
    required property ApplicationSession applicationSession
    readonly property real unit: applicationSession.baseFontPx
    modality: Qt.ApplicationModal
    width: 60 * unit
    height: 40 * unit
    title: picker.title
    font: Qt.font(applicationSession.typographyFonts.body)
    onClosing: workflow.cancelZone()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: dialog.unit
        spacing: dialog.unit
        TextField {
            id: search
            objectName: "sf2ZoneSearch"
            Layout.fillWidth: true
            placeholderText: dialog.picker.searchPlaceholder
            onTextEdited: dialog.picker.setFilter(text)
        }
        RowLayout {
            Layout.fillWidth: true
            Repeater {
                model: dialog.picker.columnTitles
                Label {
                    required property int index
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: index === 0 ? 3 : 1
                    text: modelData
                    color: dialog.colors.windowText
                }
            }
        }
        ListView {
            id: list
            objectName: "sf2ZoneRows"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: dialog.picker.rows
            delegate: Rectangle {
                id: row
                required property int index
                required property bool group
                required property bool selected
                required property string sample
                required property string key
                required property string rate
                required property string frames
                required property string loop
                required property string notes
                width: list.width
                height: 2 * dialog.unit
                color: row.selected ? dialog.colors.selectionRing : dialog.colors.windowBackground
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: row.group ? 0 : dialog.unit
                    readonly property var cells: [row.sample, row.key, row.rate, row.frames, row.loop, row.notes]
                    Repeater {
                        model: parent.cells
                        Label {
                            required property int index
                            required property string modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: index === 0 ? 3 : 1
                            text: modelData
                            elide: Text.ElideRight
                            color: row.selected ? dialog.colors.selectionText : dialog.colors.windowText
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: dialog.picker.select(row.index)
                    onDoubleClicked: {
                        dialog.picker.select(row.index)
                        if (dialog.picker.canAccept) dialog.workflow.acceptZone()
                    }
                }
            }
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            Button { text: qsTr("Cancel"); onClicked: dialog.close() }
            Button {
                objectName: "sf2ZoneAccept"
                text: qsTr("OK")
                enabled: dialog.picker.canAccept
                onClicked: dialog.workflow.acceptZone()
            }
        }
    }
}
