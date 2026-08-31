import QtQuick
import Porydaw.Ui

Item {
    id: root

    TimelineQuickItem {
        objectName: "timelineQuickPianoGrid"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoGrid
        z: 0
    }

    TimelineQuickItem {
        objectName: "timelineQuickPianoNoteFills"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoNoteFills
        z: 0
    }

    TimelineQuickItem {
        objectName: "timelineQuickPianoDrawPreviewFill"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoDrawPreviewFill
        z: 0
    }

    Item {
        anchors.fill: parent
        z: 1

        Repeater {
            model: timelineScene.pianoNoteTextModel

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
            }
        }
    }

    TimelineQuickItem {
        objectName: "timelineQuickPianoNoteBordersAndSelection"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoNoteBordersAndSelection
        z: 2
    }

    TimelineQuickItem {
        objectName: "timelineQuickPianoOverlay"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoOverlay
        z: 2
    }

    TimelineQuickItem {
        objectName: "timelineQuickPianoKeyboardKeys"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoKeyboardKeys
        z: 4
    }

    TimelineQuickItem {
        objectName: "timelineQuickPianoKeyboardHighlights"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoKeyboardHighlights
        z: 4
    }

    Rectangle {
        objectName: "timelineQuickPianoHoverChip"
        x: timelineScene.hoverChipRect.x
        y: timelineScene.hoverChipRect.y
        width: timelineScene.hoverChipRect.width
        height: timelineScene.hoverChipRect.height
        visible: timelineScene.hoverChipVisible
        color: timelineScene.hoverChipFill
        radius: timelineScene.hoverChipRadius
        z: 4.5
    }

    Item {
        anchors.fill: parent
        z: 5

        Repeater {
            model: timelineScene.pianoKeyboardTextModel

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
            }
        }
    }

    Text {
        objectName: "timelineQuickPianoHoverChipText"
        x: timelineScene.hoverChipRect.x
        y: timelineScene.hoverChipRect.y
        width: timelineScene.hoverChipRect.width
        height: timelineScene.hoverChipRect.height
        visible: timelineScene.hoverChipVisible
        text: timelineScene.hoverChipText
        color: "white"
        font: timelineScene.hoverChipFont
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
        anchors.fill: parent
        z: 5

        Repeater {
            model: timelineScene.pianoLoadingTextModel

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
            }
        }
    }
}
