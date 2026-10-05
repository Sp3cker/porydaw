pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import PorydawApp

Item {
    id: page
    required property string label
    required property string constant
    required property string nameHint
    required property list<string> identityPlayers
    required property int playerIndex
    required property GridPalette colors
    required property TypographyFonts typography
    required property LayoutSpaces layoutSpaces
    signal labelEdited(string text)
    signal constantEdited(string text)
    signal playerSelected(int index)

    function acceptLabel(accepted: string): void {
        if (accepted !== songName.text) {
            const cursor = songName.cursorPosition
            songName.text = accepted
            songName.cursorPosition = Math.min(cursor, accepted.length)
        }
    }
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
            text: page.label
            placeholderText: qsTr("mus_my_song")
            onTextChanged: page.labelEdited(text)
        }
        Label {
            objectName: "importSongNameHint"
            Layout.row: 1
            Layout.column: 1
            Layout.fillWidth: true
            text: page.nameHint
            visible: text.length > 0
            color: page.colors.errorText
            wrapMode: Text.WordWrap
        }
        Label { Layout.row: 2; Layout.column: 0; text: qsTr("Constant:"); color: page.colors.windowText }
        TextField { objectName: "importSongConstant"; Layout.row: 2; Layout.column: 1; Layout.fillWidth: true; text: page.constant; onTextEdited: page.constantEdited(text) }
        Label { Layout.row: 3; Layout.column: 0; text: qsTr("Player:"); color: page.colors.windowText }
        ComboBox {
            objectName: "importIdentityPlayer"
            Layout.row: 3
            Layout.column: 1
            Layout.fillWidth: true
            model: page.identityPlayers
            currentIndex: page.playerIndex
            ToolTip.text: qsTr("Select Background music for a song. Select Sound effect for a sound. Also select it for a fanfare.")
            ToolTip.visible: hovered
            onActivated: function(index): void { page.playerSelected(index) }
        }
        Item { Layout.row: 4; Layout.columnSpan: 2; Layout.fillHeight: true }
    }
}
