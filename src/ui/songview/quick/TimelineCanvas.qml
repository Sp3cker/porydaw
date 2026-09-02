import QtQuick
import Porydaw.Ui

Item {
    id: root

    property rect rulerBandRect: Qt.rect(0, 0, 0, 0)
    property rect rollBandRect: Qt.rect(0, 0, 0, 0)
    property rect velocityBandRect: Qt.rect(0, 0, 0, 0)
    property rect voiceChangesBandRect: Qt.rect(0, 0, 0, 0)
    property rect otherEventsBandRect: Qt.rect(0, 0, 0, 0)
    property rect automationBandRect: Qt.rect(0, 0, 0, 0)
    property bool rulerBandVisible: false
    property bool rollBandVisible: false
    property bool velocityBandVisible: false
    property bool voiceChangesBandVisible: false
    property bool otherEventsBandVisible: false
    property bool automationBandVisible: false

    Component {
        id: bandTextDelegate

        Item {
            required property rect labelRect
            required property rect labelClipRect
            required property string labelText
            required property color labelColor
            required property font labelFont
            required property int labelHorizontalAlignment
            required property int labelVerticalAlignment

            readonly property rect effectiveClipRect: labelClipRect.width > 0
                                                       && labelClipRect.height > 0
                                                       ? labelClipRect : labelRect

            x: effectiveClipRect.x
            y: effectiveClipRect.y
            width: effectiveClipRect.width
            height: effectiveClipRect.height
            clip: true

            Text {
                x: labelRect.x - parent.x
                y: labelRect.y - parent.y
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

    component TimelineChromeBand: Item {
        required property rect bandRect
        required property bool bandVisible
        required property string bandName
        z: 9

        TimelineChromeItem {
            objectName: bandName + "HoverChrome"
            x: timelineQuickView.hoverRootContentX - bandRect.x
            width: parent.width
            height: parent.height
            visible: timelineQuickView.hoverVisible && bandVisible
            kind: TimelineChromeItem.Hover
            z: 9
        }

        TimelineChromeItem {
            objectName: bandName + "EditChrome"
            x: timelineQuickView.editRootContentX - bandRect.x
            width: parent.width
            height: parent.height
            visible: timelineQuickView.editVisible && !timelineQuickView.hoverVisible && bandVisible
            kind: TimelineChromeItem.Edit
            z: 10
        }

    }

    component TimelineSceneBand: Item {
        id: sceneBand

        required property rect bandRect
        required property bool bandVisible
        required property string bandName

        x: bandRect.x
        y: bandRect.y
        width: bandRect.width
        height: bandRect.height
        clip: true
        visible: bandVisible

        TimelineChromeBand {
            anchors.fill: parent
            bandRect: sceneBand.bandRect
            bandVisible: sceneBand.bandVisible
            bandName: sceneBand.bandName
        }
    }

    component TimelineSceneLayer: TimelineQuickItem {
        anchors.fill: parent
    }

    component TimelineTextLayer: Item {
        id: textLayer

        required property var textModel

        anchors.fill: parent

        Repeater {
            model: textLayer.textModel
            delegate: bandTextDelegate
        }
    }

    TimelineSceneBand {
        bandRect: root.rulerBandRect
        bandVisible: root.rulerBandVisible
        bandName: "timelineQuickRuler"

        TimelineSceneLayer {
            objectName: "timelineQuickRulerChrome"
            sceneLayer: TimelineQuickItem.RulerChrome
            z: 0
        }
        TimelineSceneLayer {
            objectName: "timelineQuickRulerMarks"
            sceneLayer: TimelineQuickItem.RulerMarks
            z: 1
        }
        TimelineTextLayer {
            textModel: timelineScene.rulerTextModel
            z: 2
        }

        TimelineInputItem {
            objectName: "timelineRulerInput"
            anchors.fill: parent
            Accessible.description: accessibilityDescription
        }
    }

    TimelineSceneBand {
        bandRect: root.rollBandRect
        bandVisible: root.rollBandVisible
        bandName: "timelineQuickRoll"

        PianoRollCanvas {
            anchors.fill: parent
        }

        TimelineInputItem {
            objectName: "timelineRollInput"
            anchors.fill: parent
            Accessible.description: accessibilityDescription
        }
    }

    TimelineSceneBand {
        bandRect: root.automationBandRect
        bandVisible: root.automationBandVisible
        bandName: "timelineQuickAutomation"
        z: 1

        TimelineSceneLayer {
            objectName: "timelineQuickAutomationGrid"
            sceneLayer: TimelineQuickItem.AutomationGrid
            z: 0
        }
        TimelineSceneLayer {
            objectName: "timelineQuickAutomationCurves"
            sceneLayer: TimelineQuickItem.AutomationCurves
            z: 1
        }
        TimelineSceneLayer {
            objectName: "timelineQuickAutomationNodes"
            sceneLayer: TimelineQuickItem.AutomationNodes
            z: 2
        }
        TimelineSceneLayer {
            objectName: "timelineQuickAutomationSelection"
            sceneLayer: TimelineQuickItem.AutomationSelection
            z: 3
        }
        TimelineSceneLayer {
            objectName: "timelineQuickAutomationTransient"
            sceneLayer: TimelineQuickItem.AutomationTransient
            z: 4
        }
        TimelineSceneLayer {
            objectName: "timelineQuickAutomationHover"
            sceneLayer: TimelineQuickItem.AutomationHover
            z: 5
        }
        TimelineTextLayer {
            textModel: timelineScene.automationTextModel
            z: 6
        }
        TimelineTextLayer {
            textModel: timelineScene.automationHoverTextModel
            z: 7
        }
        TimelineTextLayer {
            textModel: timelineScene.automationTransientTextModel
            z: 8
        }
        TimelineInputItem {
            objectName: "timelineAutomationInput"
            anchors.fill: parent
            Accessible.description: accessibilityDescription
        }
    }

    TimelineSceneBand {
        bandRect: root.velocityBandRect
        bandVisible: root.velocityBandVisible
        bandName: "timelineQuickVelocity"
        z: 1

        TimelineSceneLayer {
            objectName: "timelineQuickVelocityChrome"
            sceneLayer: TimelineQuickItem.VelocityChrome
            z: 0
        }
        TimelineSceneLayer {
            objectName: "timelineQuickVelocityAxis"
            sceneLayer: TimelineQuickItem.VelocityAxis
            z: 1
        }
        TimelineSceneLayer {
            objectName: "timelineQuickVelocityGrid"
            sceneLayer: TimelineQuickItem.VelocityGrid
            z: 2
        }
        TimelineSceneLayer {
            objectName: "timelineQuickVelocityBands"
            sceneLayer: TimelineQuickItem.VelocityBands
            z: 3
        }
        TimelineSceneLayer {
            objectName: "timelineQuickVelocityStems"
            sceneLayer: TimelineQuickItem.VelocityStems
            z: 4
        }
        TimelineSceneLayer {
            objectName: "timelineQuickVelocityNodes"
            sceneLayer: TimelineQuickItem.VelocityNodes
            z: 5
        }
        TimelineSceneLayer {
            objectName: "timelineQuickVelocityTransient"
            sceneLayer: TimelineQuickItem.VelocityTransient
            z: 6
        }
        TimelineTextLayer {
            textModel: timelineScene.velocityTextModel
            z: 7
        }
        TimelineInputItem {
            objectName: "timelineVelocityInput"
            anchors.fill: parent
            Accessible.description: accessibilityDescription
        }
    }

    TimelineSceneBand {
        bandRect: root.voiceChangesBandRect
        bandVisible: root.voiceChangesBandVisible
        bandName: "timelineQuickVoiceChanges"
        z: 2

        TimelineSceneLayer {
            objectName: "timelineQuickVoiceChangesChrome"
            sceneLayer: TimelineQuickItem.VoiceChangesChrome
            z: 0
        }
        TimelineSceneLayer {
            objectName: "timelineQuickVoiceChangesGrid"
            sceneLayer: TimelineQuickItem.VoiceChangesGrid
            z: 1
        }
        TimelineSceneLayer {
            objectName: "timelineQuickVoiceChangesSpans"
            sceneLayer: TimelineQuickItem.VoiceChangesSpans
            z: 2
        }
        TimelineSceneLayer {
            objectName: "timelineQuickVoiceChangesMarkers"
            sceneLayer: TimelineQuickItem.VoiceChangesMarkers
            z: 3
        }
        TimelineSceneLayer {
            objectName: "timelineQuickVoiceChangesTransient"
            sceneLayer: TimelineQuickItem.VoiceChangesTransient
            z: 4
        }
        TimelineSceneLayer {
            objectName: "timelineQuickVoiceChangesHover"
            sceneLayer: TimelineQuickItem.VoiceChangesHover
            z: 5
        }
        TimelineTextLayer {
            textModel: timelineScene.voiceChangesTextModel
            z: 6
        }
        TimelineTextLayer {
            textModel: timelineScene.voiceChangesHoverTextModel
            z: 7
        }
        TimelineInputItem {
            objectName: "timelineVoiceChangesInput"
            anchors.fill: parent
            Accessible.description: accessibilityDescription
        }
    }

    TimelineSceneBand {
        bandRect: root.otherEventsBandRect
        bandVisible: root.otherEventsBandVisible
        bandName: "timelineQuickOtherEvents"

        TimelineSceneLayer {
            objectName: "timelineQuickOtherEventsChrome"
            sceneLayer: TimelineQuickItem.OtherEventsChrome
            z: 0
        }
        TimelineSceneLayer {
            objectName: "timelineQuickOtherEventsMarkers"
            sceneLayer: TimelineQuickItem.OtherEventsMarkers
            z: 1
        }
        TimelineTextLayer {
            textModel: timelineScene.otherEventsTextModel
            z: 2
        }

        TimelineInputItem {
            objectName: "timelineOtherEventsInput"
            anchors.fill: parent
            Accessible.description: accessibilityDescription
        }
    }

}
