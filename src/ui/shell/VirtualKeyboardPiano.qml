pragma ComponentBehavior: Bound

import QtQuick
import PorydawApp

// The keyboard's piano: 28 keys from the presenter's base C, each labelled with the
// computer key that plays it and each C with its octave. Geometry and hit testing
// are the presenter's; a press sounds a key, a drag glides, a release anywhere stops.
Item {
    id: piano
    objectName: "virtualKeyboardPiano"
    required property VirtualKeyboardPresenter presenter
    required property GridPalette colors
    required property real unit
    required property real labelPadding
    required property real labelHeight
    property font font
    readonly property real minimumHeight: piano.presenter.minimumPianoHeight(
        piano.labelHeight, piano.labelPadding, piano.unit)
    readonly property real line: Math.max(1, Math.round(piano.unit / 13))

    Rectangle {
        anchors.fill: parent
        color: piano.colors.windowBackground
    }

    Repeater {
        model: piano.presenter.keyCount
        delegate: Rectangle {
            id: key
            required property int index
            readonly property bool black: piano.presenter.isBlackKey(key.index)
            readonly property bool playable: key.index < piano.presenter.playableSpan
            readonly property bool lit: (piano.presenter.litMask & (1 << key.index)) !== 0
            objectName: "virtualKeyboardKey_" + key.index
            x: piano.presenter.keyX(key.index, piano.width, piano.height)
            width: piano.presenter.keyWidth(key.index, piano.width, piano.height)
            height: piano.presenter.keyHeight(key.index, piano.width, piano.height)
            z: key.black ? 1 : 0
            // Past G9 a key is drawn faded and plays nothing.
            color: !key.playable ? (key.black ? piano.colors.keyboardSeparator : piano.colors.windowBackground)
                : key.lit ? piano.colors.keyboardActiveKey
                : key.black ? piano.colors.keyboardBlack : piano.colors.keyboardNatural
            readonly property color ink: !key.playable ? piano.colors.disabledText
                : key.black && !key.lit ? piano.colors.keyboardNatural : piano.colors.keyboardLabel

            Rectangle {
                visible: !key.black
                anchors.right: parent.right
                width: piano.line
                height: parent.height
                color: piano.colors.keyboardSeparator
            }
            Rectangle {
                visible: !key.black
                anchors.bottom: parent.bottom
                width: parent.width
                height: piano.line
                color: piano.colors.keyboardSeparator
            }
            Rectangle {
                visible: key.index === 0
                width: piano.line
                height: parent.height
                color: piano.colors.keyboardSeparator
            }
            Text {
                id: letter
                objectName: "virtualKeyboardLetter_" + key.index
                y: key.height - piano.labelPadding - piano.labelHeight
                width: key.width
                height: piano.labelHeight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: piano.presenter.keyLetters[key.index]
                font: piano.font
                color: key.ink
            }
            Text {
                objectName: "virtualKeyboardOctaveLabel_" + key.index
                visible: text.length > 0
                y: letter.y - piano.labelHeight
                width: key.width
                height: piano.labelHeight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: piano.presenter.octaveLabels[key.index]
                font: piano.font
                color: key.ink
            }
        }
    }

    // No hover tracking: moves arrive only with the button down.
    MouseArea {
        objectName: "virtualKeyboardPointer"
        anchors.fill: parent
        z: 2
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        onPressed: mouse => piano.presenter.mousePressed(mouse.x, mouse.y, piano.width, piano.height)
        onPositionChanged: mouse => piano.presenter.mouseMoved(mouse.x, mouse.y, piano.width, piano.height)
        onReleased: piano.presenter.mouseReleased()
        onCanceled: piano.presenter.mouseReleased()
    }
}
