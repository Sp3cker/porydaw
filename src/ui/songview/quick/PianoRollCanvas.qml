import QtQuick
import Porydaw.Ui

Item {
    id: root

    PianoRollQuickItem {
        objectName: "pianoRollQuickGrid"
        anchors.fill: parent
        sceneLayer: PianoRollQuickItem.Grid
        z: 0
    }

    PianoRollQuickItem {
        objectName: "pianoRollQuickNoteFills"
        anchors.fill: parent
        sceneLayer: PianoRollQuickItem.NoteFills
        z: 0
    }

    PianoRollQuickItem {
        objectName: "pianoRollQuickDrawPreviewFill"
        anchors.fill: parent
        sceneLayer: PianoRollQuickItem.DrawPreviewFill
        z: 0
    }

    Item {
        id: noteTextLayer
        anchors.fill: parent
        z: 1

        Repeater {
            model: pianoRollScene.noteTextModel

            delegate: Text {
                required property rect labelRect
                required property string labelText
                required property color labelColor
                required property font labelFont
                required property int labelHorizontalAlignment
                required property int labelVerticalAlignment

                x: labelRect.x
                y: labelRect.y
                width: labelRect.width
                height: labelRect.height
                text: labelText
                color: labelColor
                font: labelFont
                horizontalAlignment: labelHorizontalAlignment
                verticalAlignment: labelVerticalAlignment
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                elide: Text.ElideNone
                maximumLineCount: 1
                clip: true
                z: 0
            }
        }
    }

    PianoRollQuickItem {
        objectName: "pianoRollQuickNoteBordersAndSelection"
        anchors.fill: parent
        sceneLayer: PianoRollQuickItem.NoteBordersAndSelection
        z: 2
    }

    PianoRollQuickItem {
        objectName: "pianoRollQuickOverlay"
        anchors.fill: parent
        sceneLayer: PianoRollQuickItem.Overlay
        z: 2
    }

    PianoRollQuickItem {
        objectName: "pianoRollQuickKeyboardKeys"
        anchors.fill: parent
        sceneLayer: PianoRollQuickItem.KeyboardKeys
        z: 4
    }

    PianoRollQuickItem {
        objectName: "pianoRollQuickKeyboardHighlights"
        anchors.fill: parent
        sceneLayer: PianoRollQuickItem.KeyboardHighlights
        z: 4
    }

    Rectangle {
        id: hoverChip
        objectName: "pianoRollQuickHoverChip"
        x: pianoRollScene.hoverChipRect.x
        y: pianoRollScene.hoverChipRect.y
        width: pianoRollScene.hoverChipRect.width
        height: pianoRollScene.hoverChipRect.height
        visible: pianoRollScene.hoverChipVisible
        color: pianoRollScene.hoverChipFill
        radius: pianoRollScene.hoverChipRadius
        z: 4.5
    }

    Item {
        id: keyboardTextLayer
        anchors.fill: parent
        z: 5

        Repeater {
            model: pianoRollScene.keyboardTextModel

            delegate: Text {
                required property rect labelRect
                required property string labelText
                required property color labelColor
                required property font labelFont
                required property int labelHorizontalAlignment
                required property int labelVerticalAlignment

                x: labelRect.x
                y: labelRect.y
                width: labelRect.width
                height: labelRect.height
                text: labelText
                color: labelColor
                font: labelFont
                horizontalAlignment: labelHorizontalAlignment
                verticalAlignment: labelVerticalAlignment
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                elide: Text.ElideNone
                maximumLineCount: 1
                clip: true
                z: 0
            }
        }
    }

    Text {
        id: hoverChipText
        objectName: "pianoRollQuickHoverChipText"
        x: pianoRollScene.hoverChipRect.x
        y: pianoRollScene.hoverChipRect.y
        width: pianoRollScene.hoverChipRect.width
        height: pianoRollScene.hoverChipRect.height
        visible: pianoRollScene.hoverChipVisible
        text: pianoRollScene.hoverChipText
        color: "white"
        font: pianoRollScene.hoverChipFont
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        elide: Text.ElideNone
        maximumLineCount: 1
        clip: true
        z: 5
    }

    Item {
        id: loadingTextLayer
        anchors.fill: parent
        z: 5

        Repeater {
            model: pianoRollScene.loadingTextModel

            delegate: Text {
                required property rect labelRect
                required property string labelText
                required property color labelColor
                required property font labelFont
                required property int labelHorizontalAlignment
                required property int labelVerticalAlignment

                x: labelRect.x
                y: labelRect.y
                width: labelRect.width
                height: labelRect.height
                text: labelText
                color: labelColor
                font: labelFont
                horizontalAlignment: labelHorizontalAlignment
                verticalAlignment: labelVerticalAlignment
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                elide: Text.ElideNone
                maximumLineCount: 1
                clip: true
                z: 0
            }
        }
    }
}
