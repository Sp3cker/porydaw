import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Flickable {
    id: page
    required property QtObject controller
    required property QtObject colors
    required property var typography
    required property var layoutSpaces
    required property int baseFontPx
    contentHeight: body.implicitHeight + layoutSpaces.three * 2
    clip: true
    property bool controllersExpanded: false
    function focusFirst() { player.forceActiveFocus() }
    onVisibleChanged: { if (visible) focusFirst() }
    ColumnLayout {
        id: body
        x: page.layoutSpaces.three
        y: page.layoutSpaces.three
        width: page.width - page.layoutSpaces.three * 2
        spacing: page.layoutSpaces.three
        RowLayout {
            Label { text: qsTr("The song will be used as:"); color: page.colors.windowText; font: Qt.font(page.typography.body) }
            ComboBox {
                id: player
                objectName: "importAnalysisPlayer"
                Layout.fillWidth: true
                model: page.controller.analysisPlayers
                currentIndex: page.controller.playerIndex
                ToolTip.text: qsTr("Select Background music for a song. Select Sound effect for a sound. Also select it for a fanfare.")
                ToolTip.visible: hovered
                onActivated: index => page.controller.selectPlayer(index)
            }
        }
        Item { Layout.preferredHeight: page.layoutSpaces.one }
        Label { objectName: "importFileTracks"; text: page.controller.fileTracksText; color: page.colors.windowText; font: Qt.font(page.typography.body) }
        Label { objectName: "importGameTrackLimit"; text: page.controller.gameTrackLimitText; color: page.colors.windowText; font: Qt.font(page.typography.body) }
        Label { objectName: "importStatus"; Layout.fillWidth: true; text: page.controller.statusText; font.bold: true; wrapMode: Text.WordWrap; color: page.colors.windowText }
        Label { objectName: "importSummary"; Layout.fillWidth: true; text: page.controller.summaryText; wrapMode: Text.WordWrap; color: page.colors.windowText }
        Label { objectName: "importTrackAction"; Layout.fillWidth: true; text: page.controller.trackActionText; visible: text.length > 0; wrapMode: Text.WordWrap; color: page.colors.warningText }
        Label { objectName: "importPolyphony"; Layout.fillWidth: true; text: page.controller.polyphonyText; visible: text.length > 0; wrapMode: Text.WordWrap; color: page.colors.warningText }
        Label { objectName: "importDefaultInstrument"; Layout.fillWidth: true; text: page.controller.defaultInstrumentText; visible: text.length > 0; wrapMode: Text.WordWrap; color: page.colors.warningText }
        Label { objectName: "importFormat"; Layout.fillWidth: true; text: page.controller.formatText; visible: text.length > 0; wrapMode: Text.WordWrap; color: page.colors.warningText }
        Label { objectName: "importControllerNotice"; Layout.fillWidth: true; text: page.controller.controllerText; visible: text.length > 0; wrapMode: Text.WordWrap; color: page.colors.warningText }
        CheckBox {
            objectName: "importRescale"
            text: qsTr("Adjust note timing for the Game Boy Advance (recommended)")
            visible: page.controller.offersRescale
            checked: page.controller.rescale
            onToggled: page.controller.setRescale(checked)
            ToolTip.text: qsTr("Use this adjustment to make the note timing in Porydaw agree with the note timing in the game.")
            ToolTip.visible: hovered
        }
        Button {
            objectName: "importControllerToggle"
            flat: true
            visible: page.controller.hasControllerRows
            text: (page.controllersExpanded ? "▾ " : "▸ ") + qsTr("CC commands")
            onClicked: page.controllersExpanded = !page.controllersExpanded
        }
        ColumnLayout {
            objectName: "importControllerTable"
            visible: page.controllersExpanded && page.controller.hasControllerRows
            Layout.leftMargin: page.layoutSpaces.eight
            Layout.fillWidth: true
            spacing: page.layoutSpaces.one
            RowLayout {
                Layout.fillWidth: true
                Label { objectName: "importCCController"; text: qsTr("Controller"); color: page.colors.windowText }
                Label { objectName: "importCCFunction"; text: qsTr("Function"); Layout.fillWidth: true; color: page.colors.windowText }
                Label { objectName: "importCCEvents"; text: qsTr("Events"); color: page.colors.windowText }
                Label { objectName: "importCCInGame"; text: qsTr("In the game"); color: page.colors.windowText }
            }
            Repeater {
                model: page.controller.controllerRows
                delegate: RowLayout {
                    Layout.fillWidth: true
                    Label { text: model.controller; color: page.colors.windowText }
                    Label { text: model.function; Layout.fillWidth: true; color: page.colors.windowText }
                    Label { text: model.events; color: page.colors.windowText }
                    Label { text: model.inGame; color: model.needsAttention ? page.colors.warningText : page.colors.windowText }
                }
            }
        }
    }
}
