import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Porydaw.Ui
import "../midiimport"
import PorydawApp

DialogWindow {
    id: wizard
    required property NewSongController controller
    required property ApplicationSession applicationSession
    readonly property var typography: applicationSession.typographyFonts
    readonly property var layoutSpaces: applicationSession.layoutSpaces
    readonly property int baseFontPx: applicationSession.baseFontPx
    objectName: "newSongWizard"
    title: controller.windowTitle
    modality: Qt.ApplicationModal
    width: Math.round(baseFontPx * 52)
    height: Math.round(baseFontPx * 38)
    minimumWidth: Math.round(baseFontPx * 52)
    minimumHeight: Math.round(baseFontPx * 38)
    font: Qt.font(typography.body)
    onClosing: controller.cancel()

    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: header.implicitHeight + wizard.layoutSpaces.three * 2
            color: wizard.colors.inputBackground
            ColumnLayout {
                id: header
                anchors.fill: parent
                anchors.margins: wizard.layoutSpaces.three
                spacing: wizard.layoutSpaces.one
                Text {
                    objectName: "newSongWizardTitle"
                    text: wizard.controller.page === 0 ? qsTr("Song identity") : qsTr("Sound settings")
                    font: Qt.font(wizard.typography.bodyBold)
                    color: wizard.colors.windowText
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: wizard.controller.page === 0
                        ? qsTr("Names the .mid file, the song_table.inc entry, and the songs.h constant.")
                        : qsTr("The song's voicegroup and mid2agb flags — its entry in midi.cfg (or songs.mk). All of this can be changed later in Song Settings.")
                    font: Qt.font(wizard.typography.body)
                    color: wizard.colors.windowText
                }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Math.round(wizard.baseFontPx / 12); color: wizard.colors.outline }
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: wizard.controller.page
            ImportIdentityPage { controller: wizard.controller; colors: wizard.colors; typography: wizard.typography; layoutSpaces: wizard.layoutSpaces }
            ImportSoundPage { controller: wizard.controller; colors: wizard.colors; typography: wizard.typography; layoutSpaces: wizard.layoutSpaces }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Math.round(wizard.baseFontPx / 12); color: wizard.colors.outline }
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: wizard.layoutSpaces.three
            spacing: wizard.layoutSpaces.two
            Item { Layout.fillWidth: true }
            Button { objectName: "newSongWizardBack"; text: qsTr("< Back"); visible: wizard.controller.page > 0; onClicked: wizard.controller.back() }
            Button {
                objectName: "newSongWizardNext"
                text: qsTr("Next >")
                visible: wizard.controller.page === 0
                enabled: wizard.controller.identityComplete
                onClicked: wizard.controller.next()
            }
            Button {
                objectName: "newSongWizardFinish"
                text: qsTr("Finish")
                visible: wizard.controller.page === 1
                enabled: wizard.controller.identityComplete && !wizard.controller.busy
                onClicked: wizard.controller.finish()
            }
            Button { objectName: "newSongWizardCancel"; text: qsTr("Cancel"); onClicked: wizard.controller.cancel() }
        }
    }
    Shortcut {
        sequences: ["Return", "Enter"]
        context: Qt.WindowShortcut
        enabled: wizard.visible
        onActivated: {
            if (!wizard.controller.identityComplete || wizard.controller.busy)
                return
            if (wizard.controller.page === 1)
                wizard.controller.finish()
            else
                wizard.controller.next()
        }
    }
}
