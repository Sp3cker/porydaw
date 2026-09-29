import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Porydaw.Ui

DialogWindow {
    id: wizard
    required property QtObject controller
    required property QtObject applicationSession
    readonly property var typography: applicationSession.typographyFonts
    readonly property var layoutSpaces: applicationSession.layoutSpaces
    readonly property int baseFontPx: applicationSession.baseFontPx
    title: controller.windowTitle
    modality: Qt.ApplicationModal
    width: Math.round(baseFontPx * 60)
    height: Math.round(baseFontPx * 44)
    minimumWidth: Math.round(baseFontPx * 60)
    minimumHeight: Math.round(baseFontPx * 44)
    font: Qt.font(typography.body)
    onVisibleChanged: {
        if (visible)
            analysisPage.focusFirst()
    }
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
                    objectName: "importWizardTitle"
                    text: wizard.controller.page === 0 ? qsTr("Check the MIDI file")
                          : wizard.controller.page === 1 ? qsTr("Song identity") : qsTr("Sound settings")
                    font: Qt.font(wizard.typography.bodyBold)
                    color: wizard.colors.windowText
                }
                Text {
                    objectName: "importWizardSubtitle"
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: wizard.controller.page === 0 ? wizard.controller.sourceFileName
                          : wizard.controller.page === 1
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
            ImportAnalysisPage { id: analysisPage; controller: wizard.controller; colors: wizard.colors; typography: wizard.typography; layoutSpaces: wizard.layoutSpaces; baseFontPx: wizard.baseFontPx }
            ImportIdentityPage { controller: wizard.controller; colors: wizard.colors; typography: wizard.typography; layoutSpaces: wizard.layoutSpaces }
            ImportSoundPage { controller: wizard.controller; colors: wizard.colors; typography: wizard.typography; layoutSpaces: wizard.layoutSpaces }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Math.round(wizard.baseFontPx / 12); color: wizard.colors.outline }
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: wizard.layoutSpaces.three
            spacing: wizard.layoutSpaces.two
            Item { Layout.fillWidth: true }
            Button { objectName: "importWizardBack"; text: qsTr("< Back"); visible: wizard.controller.page > 0; onClicked: wizard.controller.back() }
            Button {
                objectName: "importWizardNext"
                text: qsTr("Next >")
                visible: wizard.controller.page < 2
                enabled: wizard.controller.page === 0 || wizard.controller.identityComplete
                onClicked: wizard.controller.next()
            }
            Button {
                objectName: "importWizardFinish"
                text: qsTr("Finish")
                visible: wizard.controller.page === 2
                enabled: wizard.controller.identityComplete && !wizard.controller.busy
                onClicked: wizard.controller.finish()
            }
            Button { objectName: "importWizardCancel"; text: qsTr("Cancel"); onClicked: wizard.controller.cancel() }
        }
    }
    Shortcut {
        sequences: ["Return", "Enter"]
        context: Qt.WindowShortcut
        enabled: wizard.visible
        onActivated: {
            if (wizard.controller.page === 2) {
                if (wizard.controller.identityComplete && !wizard.controller.busy)
                    wizard.controller.finish()
            } else if (wizard.controller.page === 0 || wizard.controller.identityComplete) {
                wizard.controller.next()
            }
        }
    }
}
