import QtQuick
import Porydaw.Ui

Item {
    id: root

    required property Item gutterContentSide
    required property Item bandSide
    required property Item plotSide
    required property Item plotContentSide
    required property QtObject timelineScene

    TimelineQuickItem {
        parent: root.plotContentSide
        objectName: "timelineQuickPianoGridRows"
        anchors.fill: parent
        rects: root.timelineScene.pianoGridRows
        batched: true
        z: 0
    }

    TimelineQuickItem {
        parent: root.plotContentSide
        objectName: "timelineQuickPianoGridTime"
        anchors.fill: parent
        rects: root.timelineScene.pianoGridTime
        batched: true
        z: 1
    }

    TimelineQuickItem {
        parent: root.plotContentSide
        objectName: "timelineQuickPianoNoteFills"
        anchors.fill: parent
        rects: root.timelineScene.pianoNoteFills
        batched: true
        exposeRows: true
        z: 2
    }

    TimelineQuickItem {
        parent: root.plotContentSide
        objectName: "timelineQuickPianoDrawPreviewFill"
        anchors.fill: parent
        rects: root.timelineScene.pianoDrawPreviewFill
        batched: true
        z: 3
    }

    Item {
        parent: root.plotContentSide
        anchors.fill: parent
        z: 4

        Repeater {
            model: root.timelineScene.pianoNoteTextModel

            delegate: Text {
                required property var labelSpec
                required property string labelText
                required property var labelFont

                x: labelSpec.x
                y: labelSpec.y
                width: labelSpec.width
                height: labelSpec.height
                text: labelText
                color: labelSpec.color
                font: Qt.font(labelFont)
                horizontalAlignment: labelSpec.horizontal
                verticalAlignment: labelSpec.vertical
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                elide: Text.ElideNone
                maximumLineCount: 1
                clip: contentWidth > width || contentHeight > height
            }
        }
    }

    TimelineQuickItem {
        parent: root.plotContentSide
        objectName: "timelineQuickPianoNoteBordersAndSelection"
        anchors.fill: parent
        rects: root.timelineScene.pianoNoteBordersAndSelection
        batched: true
        z: 5
    }

    TimelineQuickItem {
        parent: root.plotContentSide
        objectName: "timelineQuickPianoOverlay"
        anchors.fill: parent
        rects: root.timelineScene.pianoOverlay
        batched: true
        exposeRows: true
        z: 6
    }

    TimelineQuickItem {
        parent: root.gutterContentSide
        objectName: "timelineQuickPianoKeyboardKeys"
        anchors.fill: parent
        rects: root.timelineScene.pianoKeyboardKeys
        z: 0
        batched: true
    }

    TimelineQuickItem {
        parent: root.gutterContentSide
        objectName: "timelineQuickPianoKeyboardHighlights"
        anchors.fill: parent
        rects: root.timelineScene.pianoKeyboardHighlights
        z: 1
        batched: true
    }

    Rectangle {
        parent: root.bandSide
        objectName: "timelineQuickPianoHoverChip"
        x: root.timelineScene.hoverChipRect.x
        y: root.timelineScene.hoverChipRect.y
        width: root.timelineScene.hoverChipRect.width
        height: root.timelineScene.hoverChipRect.height
        visible: root.timelineScene.hoverChipVisible
        color: root.timelineScene.hoverChipFill
        radius: root.timelineScene.hoverChipRadius
        z: 8
    }

    Item {
        id: keyboardTextClip
        objectName: "timelineQuickPianoKeyboardTextViewport"
        parent: root.bandSide
        anchors.fill: parent
        clip: true
        z: 3
    }

    Item {
        parent: keyboardTextClip
        y: root.gutterContentSide.y
        width: parent.width
        height: parent.height

        Repeater {
            model: root.timelineScene.pianoKeyboardTextModel

            delegate: Item {
                required property var labelSpec
                required property string labelText
                required property var labelFont
                // Checks identify keyboard labels by these roles; keep them
                // declared even though drawing reads labelSpec.
                required property var labelRect
                required property var labelBackgroundRect

                x: labelSpec.x
                y: labelSpec.y
                width: labelSpec.width
                height: labelSpec.height

                Rectangle {
                    x: labelSpec.backgroundX - labelSpec.x
                    y: labelSpec.backgroundY - labelSpec.y
                    width: labelSpec.backgroundWidth
                    height: labelSpec.backgroundHeight
                    visible: labelSpec.backgroundWidth > 0 && labelSpec.backgroundHeight > 0
                    color: labelSpec.background
                }

                Text {
                    anchors.fill: parent
                    text: labelText
                    color: labelSpec.color
                    font: Qt.font(labelFont)
                    horizontalAlignment: labelSpec.horizontal
                    verticalAlignment: labelSpec.vertical
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
        x: root.timelineScene.hoverChipRect.x
        y: root.timelineScene.hoverChipRect.y
        width: root.timelineScene.hoverChipRect.width
        height: root.timelineScene.hoverChipRect.height
        visible: root.timelineScene.hoverChipVisible
        text: root.timelineScene.hoverChipText
        color: root.timelineScene.hoverChipTextColor
        font: Qt.font(root.timelineScene.hoverChipFont)
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
            model: root.timelineScene.pianoLoadingTextModel

            delegate: Text {
                required property var labelSpec
                required property string labelText
                required property var labelFont

                x: labelSpec.x
                y: labelSpec.y
                width: labelSpec.width
                height: labelSpec.height
                text: labelText
                color: labelSpec.color
                font: Qt.font(labelFont)
                horizontalAlignment: labelSpec.horizontal
                verticalAlignment: labelSpec.vertical
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                elide: Text.ElideNone
                maximumLineCount: 1
                clip: contentWidth > width || contentHeight > height
            }
        }
    }
}
