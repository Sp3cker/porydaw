import QtQuick
import Porydaw.Ui

Item {
    id: root

    required property Item gutterSide
    required property Item bandSide
    required property Item plotSide

    // Keep pitch rows below pre-roll shading and time marks.
    TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoGridRows"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoGridRows
        z: 0
    }

    TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoGridTime"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoGridTime
        z: 1
    }

    TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoNoteFills"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoNoteFills
        z: 2
    }

    TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoDrawPreviewFill"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoDrawPreviewFill
        z: 3
    }

    Item {
        parent: root.plotSide
        anchors.fill: parent
        z: 4

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
                clip: contentWidth > width || contentHeight > height
            }
        }
    }

    TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoNoteBordersAndSelection"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoNoteBordersAndSelection
        z: 5
    }

    TimelineQuickItem {
        parent: root.plotSide
        objectName: "timelineQuickPianoOverlay"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoOverlay
        z: 6
    }

    TimelineQuickItem {
        parent: root.gutterSide
        objectName: "timelineQuickPianoKeyboardKeys"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoKeyboardKeys
        z: 0
    }

    TimelineQuickItem {
        parent: root.gutterSide
        objectName: "timelineQuickPianoKeyboardHighlights"
        anchors.fill: parent
        sceneLayer: TimelineQuickItem.PianoKeyboardHighlights
        z: 1
    }

    // Drum labels and hover chips may span the gutter and plot so full pad
    // names stay readable. Their coordinates are already band-local because
    // the gutter starts at band-local x = 0.
    Rectangle {
        parent: root.bandSide
        objectName: "timelineQuickPianoHoverChip"
        x: timelineScene.hoverChipRect.x
        y: timelineScene.hoverChipRect.y
        width: timelineScene.hoverChipRect.width
        height: timelineScene.hoverChipRect.height
        visible: timelineScene.hoverChipVisible
        color: timelineScene.hoverChipFill
        radius: timelineScene.hoverChipRadius
        z: 8
    }

    Item {
        parent: root.bandSide
        anchors.fill: parent
        z: 3

        Repeater {
            model: timelineScene.pianoKeyboardTextModel

            delegate: Item {
                required property rect labelRect
                required property string labelText
                required property color labelColor
                required property font labelFont
                required property int labelHorizontalAlignment
                required property int labelVerticalAlignment
                required property color labelBackground
                required property rect labelBackgroundRect

                x: labelRect.x
                y: labelRect.y
                width: labelRect.width
                height: labelRect.height

                Rectangle {
                    x: labelBackgroundRect.x - labelRect.x
                    y: labelBackgroundRect.y - labelRect.y
                    width: labelBackgroundRect.width
                    height: labelBackgroundRect.height
                    visible: labelBackgroundRect.width > 0 && labelBackgroundRect.height > 0
                    color: labelBackground
                }

                Text {
                    anchors.fill: parent
                    text: labelText
                    color: labelColor
                    font: labelFont
                    horizontalAlignment: labelHorizontalAlignment
                    verticalAlignment: labelVerticalAlignment
                    textFormat: Text.PlainText
                    renderType: Text.NativeRendering
                    elide: Text.ElideNone
                    maximumLineCount: 1
                    clip: contentWidth > width || contentHeight > height
                }
            }
        }
    }

    Text {
        parent: root.bandSide
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
        clip: contentWidth > width || contentHeight > height
        z: 9
    }

    Item {
        parent: root.plotSide
        anchors.fill: parent
        z: 7

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
                clip: contentWidth > width || contentHeight > height
            }
        }
    }
}
