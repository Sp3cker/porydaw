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
    property rect trackHeadersBandRect: Qt.rect(0, 0, 0, 0)
    property bool rulerBandVisible: false
    property bool rollBandVisible: false
    property bool velocityBandVisible: false
    property bool voiceChangesBandVisible: false
    property bool otherEventsBandVisible: false
    property bool automationBandVisible: false
    property bool trackHeadersBandVisible: false
    property real rulerBandTimelineOrigin: 0
    property real rollBandTimelineOrigin: 0
    property real velocityBandTimelineOrigin: 0
    property real voiceChangesBandTimelineOrigin: 0
    property real otherEventsBandTimelineOrigin: 0
    property real automationBandTimelineOrigin: 0
    property real trackHeadersBandTimelineOrigin: 0
    property font fallbackRulerFont
    readonly property var rulerAppearance: timeRuler ? timeRuler.gridControlAppearance : null
    readonly property font rulerFont: rulerAppearance ? rulerAppearance.font : fallbackRulerFont


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

    // One half of the Quick playhead bloom: 9 quadratic alpha stops matching
    // setQuadStops in playheadoverlay.cpp, fading between the 1px core bar
    // (alpha = peak) and the outer edge (alpha = 0). brightAtStart tells
    // which side of the bar this half covers.
    component TimelinePlayheadGlow: Rectangle {
        id: playheadGlow

        required property bool brightAtStart

        function stopColor(position: real) : color {
            const t = brightAtStart ? 1.0 - position : position
            const c = timelineQuickView.playheadColor
            return Qt.rgba(c.r, c.g, c.b, timelineQuickView.playheadPeakAlpha * t * t)
        }

        x: brightAtStart ? timelineQuickView.playheadGlowLeft : 0
        width: brightAtStart ? timelineQuickView.playheadGlowRight : timelineQuickView.playheadGlowLeft
        height: parent.height
        visible: width > 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: playheadGlow.stopColor(0.0) }
            GradientStop { position: 0.125; color: playheadGlow.stopColor(0.125) }
            GradientStop { position: 0.25; color: playheadGlow.stopColor(0.25) }
            GradientStop { position: 0.375; color: playheadGlow.stopColor(0.375) }
            GradientStop { position: 0.5; color: playheadGlow.stopColor(0.5) }
            GradientStop { position: 0.625; color: playheadGlow.stopColor(0.625) }
            GradientStop { position: 0.75; color: playheadGlow.stopColor(0.75) }
            GradientStop { position: 0.875; color: playheadGlow.stopColor(0.875) }
            GradientStop { position: 1.0; color: playheadGlow.stopColor(1.0) }
        }
    }

    component TimelineSceneBand: Item {
        id: sceneBand

        required property rect bandRect
        required property bool bandVisible
        required property string bandName
        required property real timelineOrigin

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

        // Playhead-only plot clip: the gutter left of timelineOrigin carries
        // keyboard / track-header chrome that must keep the full band, so the
        // wrapper — not the band — owns the z: 50 playhead stacking slot.
        Item {
            id: playheadClip

            x: Math.max(0, sceneBand.timelineOrigin)
            y: 0
            width: Math.max(0, parent.width - x)
            height: parent.height
            clip: true
            z: 50
            // Match native WA_TransparentForMouseEvents: this wrapper covers
            // the whole plot so glow can clip, but must never steal input.
            enabled: false
            visible: timelineQuickView.playheadVisible && sceneBand.bandVisible

            Item {
                id: playheadBody

                // Quick counterpart of PlayheadOverlay's vector playhead: a
                // quadratic bloom (alpha = peak * t^2, matching setQuadStops
                // in playheadoverlay.cpp) around a 1px core bar.

                objectName: sceneBand.bandName + "Playhead"
                x: timelineQuickView.playheadRootX - sceneBand.bandRect.x
                   - timelineQuickView.playheadGlowLeft - playheadClip.x
                width: Math.max(timelineQuickView.playheadGlowLeft + timelineQuickView.playheadGlowRight,
                                timelineQuickView.playheadLineWidthPx)
                height: parent.height
                visible: timelineQuickView.playheadVisible && sceneBand.bandVisible

                TimelinePlayheadGlow {
                    brightAtStart: false
                }

                TimelinePlayheadGlow {
                    brightAtStart: true
                }

                Rectangle {
                    antialiasing: false
                    x: timelineQuickView.playheadGlowLeft
                    width: Math.max(1, timelineQuickView.playheadLineWidthPx)
                    height: parent.height
                    color: timelineQuickView.playheadColor
                }
            }
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
        id: rulerBand
        bandRect: root.rulerBandRect
        bandVisible: root.rulerBandVisible
        bandName: "timelineQuickRuler"
        timelineOrigin: root.rulerBandTimelineOrigin

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

        RulerControls {
            objectName: "timelineRulerControls"
            width: timelineQuickView.rulerControlsWidth
            height: parent.height
            rulerBand: rulerBand
            ruler: timeRuler
            z: 3
        }

        // Same plot-only clip as the body: the ruler triangle never paints
        // in the controls gutter.
        Item {
            id: rulerPlayheadClip

            x: Math.max(0, rulerBand.timelineOrigin)
            y: 0
            width: Math.max(0, parent.width - x)
            height: parent.height
            clip: true
            z: 50
            enabled: false
            visible: timelineQuickView.playheadVisible && rulerBand.bandVisible

            Canvas {
                id: timelineQuickPlayheadTriangle

                readonly property color triangleColor: timelineQuickView.playheadColor
                readonly property bool trianglePointsUp: timelineQuickView.playheadTrianglePointsUp
                readonly property int triangleHalfWidthPx: timelineQuickView.playheadTriangleHalfWidthPx
                readonly property int triangleHeightPx: timelineQuickView.playheadTriangleHeightPx

                // Native-parity ruler marker: apex on the playhead, pointing
                // up at the top when the roll band is absent, down at the
                // bottom otherwise.
                objectName: "timelineQuickPlayheadTriangle"
                x: timelineQuickView.playheadRootX - rulerBand.bandRect.x - triangleHalfWidthPx
                   - parent.x
                y: trianglePointsUp ? 0 : parent.height - triangleHeightPx
                width: 2 * triangleHalfWidthPx
                height: triangleHeightPx
                visible: timelineQuickView.playheadVisible && rulerBand.bandVisible

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = triangleColor
                    ctx.beginPath()
                    if (trianglePointsUp) {
                        ctx.moveTo(0, height)
                        ctx.lineTo(width, height)
                        ctx.lineTo(width / 2, 0)
                    } else {
                        ctx.moveTo(0, 0)
                        ctx.lineTo(width, 0)
                        ctx.lineTo(width / 2, height)
                    }
                    ctx.closePath()
                    ctx.fill()
                }

                // Contents depend only on color/geometry/orientation; moving
                // the item re-uses the painted texture.
                onTriangleColorChanged: requestPaint()
                onTrianglePointsUpChanged: requestPaint()
                onTriangleHalfWidthPxChanged: requestPaint()
                onTriangleHeightPxChanged: requestPaint()
            }
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
        timelineOrigin: root.rollBandTimelineOrigin

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
        timelineOrigin: root.automationBandTimelineOrigin
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
        timelineOrigin: root.velocityBandTimelineOrigin
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
        timelineOrigin: root.voiceChangesBandTimelineOrigin
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
        timelineOrigin: root.otherEventsBandTimelineOrigin

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

    TrackHeaderBand {
        anchors.fill: parent
        bandRect: root.trackHeadersBandRect
        bandVisible: root.trackHeadersBandVisible
        model: trackHeaderModel
        controlFont: root.rulerFont
    }

    TimelineChromeBand {
        x: root.trackHeadersBandRect.x
        y: root.trackHeadersBandRect.y
        width: root.trackHeadersBandRect.width
        height: root.trackHeadersBandRect.height
        bandRect: root.trackHeadersBandRect
        bandVisible: root.trackHeadersBandVisible
        bandName: "timelineQuickTrackHeaders"
    }
    TrackHeaderToolTip {
        bandRect: root.trackHeadersBandRect
        bandVisible: root.trackHeadersBandVisible
        overlayRoot: root
        model: trackHeaderModel
        controlFont: root.rulerFont
        z: 30
    }



    DrawerChromeLayer {
        anchors.fill: parent
        chrome: drawerChrome
        quickView: timelineQuickView
        z: 20
    }
}
