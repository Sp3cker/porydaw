import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: page
    required property QtObject controller
    required property QtObject colors
    required property var typography
    required property var layoutSpaces
    onVisibleChanged: { if (visible) songName.forceActiveFocus() }
    GridLayout {
        anchors.fill: parent
        anchors.margins: page.layoutSpaces.three
        columns: 2
        columnSpacing: page.layoutSpaces.three
        rowSpacing: page.layoutSpaces.three
        Label { Layout.row: 0; Layout.column: 0; text: qsTr("Name:"); color: page.colors.windowText }
        TextField {
            id: songName
            objectName: "importSongName"
            Layout.row: 0
            Layout.column: 1
            Layout.fillWidth: true
            text: page.controller.label
            placeholderText: qsTr("mus_my_song")
            onTextChanged: {
                const cursor = cursorPosition
                const accepted = page.controller.editLabel(text)
                if (accepted !== text) {
                    text = accepted
                    cursorPosition = Math.min(cursor, accepted.length)
                }
            }
        }
        Label {
            objectName: "importSongNameHint"
            Layout.row: 1
            Layout.column: 1
            Layout.fillWidth: true
            text: page.controller.nameHint
            visible: text.length > 0
            color: page.colors.errorText
            wrapMode: Text.WordWrap
        }
        Label { Layout.row: 2; Layout.column: 0; text: qsTr("Constant:"); color: page.colors.windowText }
        TextField { objectName: "importSongConstant"; Layout.row: 2; Layout.column: 1; Layout.fillWidth: true; text: page.controller.constant; onTextEdited: page.controller.editConstant(text) }
        Label { Layout.row: 3; Layout.column: 0; text: qsTr("Player:"); color: page.colors.windowText }
        ComboBox {
            objectName: "importIdentityPlayer"
            Layout.row: 3
            Layout.column: 1
            Layout.fillWidth: true
            model: page.controller.identityPlayers
            currentIndex: page.controller.playerIndex
            ToolTip.text: qsTr("Select Background music for a song. Select Sound effect for a sound. Also select it for a fanfare.")
            ToolTip.visible: hovered
            onActivated: index => page.controller.selectPlayer(index)
        }
        Item { Layout.row: 4; Layout.columnSpan: 2; Layout.fillHeight: true }
    }
}
