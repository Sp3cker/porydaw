pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import Porydaw.Ui
import "../midiimport"
import PorydawApp

DialogWindow {
    id: wizard
    required property NewSongController controller
    required property ApplicationSession applicationSession
    readonly property TypographyFonts typography: applicationSession.typographyFonts
    readonly property LayoutSpaces layoutSpaces: applicationSession.layoutSpaces
    readonly property int baseFontPx: applicationSession.baseFontPx
    objectName: "newSongWizard"
    title: controller.windowTitle
    modality: Qt.ApplicationModal
    width: Math.round(baseFontPx * 52)
    height: Math.round(baseFontPx * 38)
    minimumWidth: Math.round(baseFontPx * 52)
    minimumHeight: Math.round(baseFontPx * 38)
    font: typography.body
    onClosing: controller.cancel()

    WizardChrome {
        anchors.fill: parent
        typography: wizard.typography
        layoutSpaces: wizard.layoutSpaces
        baseFontPx: wizard.baseFontPx
        headerBackground: wizard.colors.inputBackground
        textColor: wizard.colors.windowText
        outlineColor: wizard.colors.outline
        currentIndex: wizard.controller.page
        titleObjectName: "newSongWizardTitle"
        titleText: wizard.controller.page === 0 ? qsTr("Song identity") : qsTr("Sound settings")
        subtitleText: wizard.controller.page === 0
            ? qsTr("Names the .mid file, the song_table.inc entry, and the songs.h constant.")
            : qsTr("The song's voicegroup and mid2agb flags — its entry in midi.cfg (or songs.mk). All of this can be changed later in Song Settings.")
            ImportIdentityPage {
                id: identityPage
                colors: wizard.colors; typography: wizard.typography; layoutSpaces: wizard.layoutSpaces
                label: wizard.controller.label
                constant: wizard.controller.constant
                nameHint: wizard.controller.nameHint
                identityPlayers: wizard.controller.identityPlayers
                playerIndex: wizard.controller.playerIndex
                onLabelEdited: function(text): void { identityPage.acceptLabel(wizard.controller.editLabel(text)) }
                onConstantEdited: function(text): void { wizard.controller.editConstant(text) }
                onPlayerSelected: function(index): void { wizard.controller.selectPlayer(index) }
            }
            ImportSoundPage {
                colors: wizard.colors; typography: wizard.typography; layoutSpaces: wizard.layoutSpaces
                voicegroupOptions: wizard.controller.voicegroupOptions
                voicegroupText: wizard.controller.voicegroupText
                volume: wizard.controller.volume
                reverb: wizard.controller.reverb
                priority: wizard.controller.priority
                exactGate: wizard.controller.exactGate
                extendedClocks: wizard.controller.extendedClocks
                noCompression: wizard.controller.noCompression
                onVoicegroupEdited: function(text): void { wizard.controller.changeVoicegroupText(text) }
                onVolumeEdited: function(value): void { wizard.controller.changeVolume(value) }
                onReverbEdited: function(value): void { wizard.controller.changeReverb(value) }
                onPriorityEdited: function(value): void { wizard.controller.changePriority(value) }
                onExactGateEdited: function(value): void { wizard.controller.changeExactGate(value) }
                onExtendedClocksEdited: function(value): void { wizard.controller.changeExtendedClocks(value) }
                onNoCompressionEdited: function(value): void { wizard.controller.changeNoCompression(value) }
            }
        footer: [
            Button { objectName: "newSongWizardBack"; text: qsTr("< Back"); visible: wizard.controller.page > 0; onClicked: wizard.controller.back() },
            Button {
                objectName: "newSongWizardNext"
                text: qsTr("Next >")
                visible: wizard.controller.page === 0
                enabled: wizard.controller.identityComplete
                onClicked: wizard.controller.next()
            },
            Button {
                objectName: "newSongWizardFinish"
                text: qsTr("Finish")
                visible: wizard.controller.page === 1
                enabled: wizard.controller.identityComplete && !wizard.controller.busy
                onClicked: wizard.controller.finish()
            },
            Button { objectName: "newSongWizardCancel"; text: qsTr("Cancel"); onClicked: wizard.controller.cancel() }
        ]
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
