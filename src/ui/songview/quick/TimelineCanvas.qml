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

        Text {
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

    component TimelineChromeBand: Item {
        required property rect bandRect
        required property bool bandVisible
        required property string bandName
        property bool rulerBand: false

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
            visible: timelineQuickView.editVisible && bandVisible
            kind: TimelineChromeItem.Edit
            z: 10
        }

        TimelineChromeItem {
            objectName: bandName + "PlayheadChrome"
            x: timelineQuickView.playheadRootContentX - bandRect.x
            width: parent.width
            height: parent.height
            visible: timelineQuickView.playheadVisible && bandVisible
            kind: TimelineChromeItem.Playhead
            playing: timelineQuickView.playheadPlaying
            rulerTriangle: rulerBand
                           ? (root.rollBandVisible ? TimelineChromeItem.Down : TimelineChromeItem.Up)
                           : TimelineChromeItem.None
            z: 11
        }
    }

    Item {
        x: root.rulerBandRect.x
        y: root.rulerBandRect.y
        width: root.rulerBandRect.width
        height: root.rulerBandRect.height
        clip: true
        visible: root.rulerBandVisible

        TimelineQuickItem {
            objectName: "timelineQuickRulerChrome"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.RulerChrome
            z: 0
        }

        TimelineQuickItem {
            objectName: "timelineQuickRulerMarks"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.RulerMarks
            z: 1
        }

        Item {
            anchors.fill: parent
            z: 2

            Repeater {
                model: timelineScene.rulerTextModel
                delegate: bandTextDelegate
            }
        }
        TimelineChromeBand {
            anchors.fill: parent
            bandRect: root.rulerBandRect
            bandVisible: root.rulerBandVisible
            bandName: "timelineQuickRuler"
            rulerBand: true
        }
    }


    Item {
        x: root.rollBandRect.x
        y: root.rollBandRect.y
        width: root.rollBandRect.width
        height: root.rollBandRect.height
        clip: true
        visible: root.rollBandVisible

        PianoRollCanvas {
            anchors.fill: parent
        }
        TimelineChromeBand {
            anchors.fill: parent
            bandRect: root.rollBandRect
            bandVisible: root.rollBandVisible
            bandName: "timelineQuickRoll"
        }
    }


    Item {
        x: root.automationBandRect.x
        y: root.automationBandRect.y
        width: root.automationBandRect.width
        height: root.automationBandRect.height
        clip: true
        visible: root.automationBandVisible
        z: 1

        TimelineQuickItem {
            objectName: "timelineQuickAutomationGrid"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.AutomationGrid
            z: 0
        }

        TimelineQuickItem {
            objectName: "timelineQuickAutomationCurves"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.AutomationCurves
            z: 1
        }

        TimelineQuickItem {
            objectName: "timelineQuickAutomationNodes"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.AutomationNodes
            z: 2
        }

        TimelineQuickItem {
            objectName: "timelineQuickAutomationSelection"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.AutomationSelection
            z: 3
        }

        TimelineQuickItem {
            objectName: "timelineQuickAutomationTransient"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.AutomationTransient
            z: 4
        }

        TimelineQuickItem {
            objectName: "timelineQuickAutomationHover"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.AutomationHover
            z: 5
        }

        Item {
            anchors.fill: parent
            z: 6

            Repeater {
                model: timelineScene.automationTextModel
                delegate: bandTextDelegate
            }
        }

        Item {
            anchors.fill: parent
            z: 7

            Repeater {
                model: timelineScene.automationHoverTextModel
                delegate: bandTextDelegate
            }
        }

        Item {
            anchors.fill: parent
            z: 8

            Repeater {
                model: timelineScene.automationTransientTextModel
                delegate: bandTextDelegate
            }
        }
        TimelineChromeBand {
            anchors.fill: parent
            bandRect: root.automationBandRect
            bandVisible: root.automationBandVisible
            bandName: "timelineQuickAutomation"
        }
    }


    Item {
        x: root.velocityBandRect.x
        y: root.velocityBandRect.y
        width: root.velocityBandRect.width
        height: root.velocityBandRect.height
        clip: true
        visible: root.velocityBandVisible
        z: 1

        TimelineQuickItem {
            objectName: "timelineQuickVelocityChrome"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VelocityChrome
            z: 0
        }

        TimelineQuickItem {
            objectName: "timelineQuickVelocityAxis"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VelocityAxis
            z: 1
        }

        TimelineQuickItem {
            objectName: "timelineQuickVelocityGrid"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VelocityGrid
            z: 2
        }

        TimelineQuickItem {
            objectName: "timelineQuickVelocityBands"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VelocityBands
            z: 3
        }

        TimelineQuickItem {
            objectName: "timelineQuickVelocityStems"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VelocityStems
            z: 4
        }

        TimelineQuickItem {
            objectName: "timelineQuickVelocityNodes"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VelocityNodes
            z: 5
        }

        TimelineQuickItem {
            objectName: "timelineQuickVelocityTransient"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VelocityTransient
            z: 6
        }

        Item {
            anchors.fill: parent
            z: 7

            Repeater {
                model: timelineScene.velocityTextModel
                delegate: bandTextDelegate
            }
        }
        TimelineChromeBand {
            anchors.fill: parent
            bandRect: root.velocityBandRect
            bandVisible: root.velocityBandVisible
            bandName: "timelineQuickVelocity"
        }
    }


    Item {
        x: root.voiceChangesBandRect.x
        y: root.voiceChangesBandRect.y
        width: root.voiceChangesBandRect.width
        height: root.voiceChangesBandRect.height
        clip: true
        visible: root.voiceChangesBandVisible
        z: 2

        TimelineQuickItem {
            objectName: "timelineQuickVoiceChangesChrome"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VoiceChangesChrome
            z: 0
        }

        TimelineQuickItem {
            objectName: "timelineQuickVoiceChangesGrid"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VoiceChangesGrid
            z: 1
        }

        TimelineQuickItem {
            objectName: "timelineQuickVoiceChangesSpans"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VoiceChangesSpans
            z: 2
        }

        TimelineQuickItem {
            objectName: "timelineQuickVoiceChangesMarkers"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VoiceChangesMarkers
            z: 3
        }

        TimelineQuickItem {
            objectName: "timelineQuickVoiceChangesTransient"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VoiceChangesTransient
            z: 4
        }

        TimelineQuickItem {
            objectName: "timelineQuickVoiceChangesHover"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.VoiceChangesHover
            z: 5
        }

        Item {
            anchors.fill: parent
            z: 6

            Repeater {
                model: timelineScene.voiceChangesTextModel
                delegate: bandTextDelegate
            }
        }

        Item {
            anchors.fill: parent
            z: 7

            Repeater {
                model: timelineScene.voiceChangesHoverTextModel
                delegate: bandTextDelegate
            }
        }
        TimelineChromeBand {
            anchors.fill: parent
            bandRect: root.voiceChangesBandRect
            bandVisible: root.voiceChangesBandVisible
            bandName: "timelineQuickVoiceChanges"
        }
    }


    Item {
        x: root.otherEventsBandRect.x
        y: root.otherEventsBandRect.y
        width: root.otherEventsBandRect.width
        height: root.otherEventsBandRect.height
        clip: true
        visible: root.otherEventsBandVisible

        TimelineQuickItem {
            objectName: "timelineQuickOtherEventsChrome"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.OtherEventsChrome
            z: 0
        }

        TimelineQuickItem {
            objectName: "timelineQuickOtherEventsMarkers"
            anchors.fill: parent
            sceneLayer: TimelineQuickItem.OtherEventsMarkers
            z: 1
        }

        Item {
            anchors.fill: parent
            z: 2

            Repeater {
                model: timelineScene.otherEventsTextModel
                delegate: bandTextDelegate
            }
        }
        TimelineChromeBand {
            anchors.fill: parent
            bandRect: root.otherEventsBandRect
            bandVisible: root.otherEventsBandVisible
            bandName: "timelineQuickOtherEvents"
        }
    }

}
