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
    property rect rulerBandPlotRect: Qt.rect(0, 0, 0, 0)
    property rect rollBandPlotRect: Qt.rect(0, 0, 0, 0)
    property rect velocityBandPlotRect: Qt.rect(0, 0, 0, 0)
    property rect voiceChangesBandPlotRect: Qt.rect(0, 0, 0, 0)
    property rect otherEventsBandPlotRect: Qt.rect(0, 0, 0, 0)
    property rect automationBandPlotRect: Qt.rect(0, 0, 0, 0)
    property rect trackHeadersBandPlotRect: Qt.rect(0, 0, 0, 0)
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

    component TimelineSceneBand: Item {
        id: sceneBand

        required property rect bandRect
        required property rect plotRect
        required property bool bandVisible
        required property string bandName
        required property string plotInputName
        required property string gutterInputName
        readonly property real gutterWidth: Math.max(0, plotRect.x - bandRect.x)
        property alias gutterSide: gutterBox
        property alias plotSide: plotBox

        x: bandRect.x
        y: bandRect.y
        width: bandRect.width
        height: bandRect.height
        clip: true
        visible: bandVisible

        Item {
            id: gutterBox

            objectName: sceneBand.bandName + "Gutter"
            width: sceneBand.gutterWidth
            height: parent.height
            clip: true

            TimelineInputItem {
                objectName: sceneBand.gutterInputName
                anchors.fill: parent
                Accessible.description: accessibilityDescription
                z: 2
            }
        }

        Item {
            id: plotBox

            objectName: sceneBand.bandName + "Plot"
            x: sceneBand.gutterWidth
            y: sceneBand.plotRect.y - sceneBand.bandRect.y
            width: sceneBand.plotRect.width
            height: sceneBand.plotRect.height
            clip: true

            TimelineInputItem {
                objectName: sceneBand.plotInputName
                anchors.fill: parent
                Accessible.description: accessibilityDescription
                z: 8.5
            }

            TimelineChromeBand {
                anchors.fill: parent
                bandRect: sceneBand.plotRect
                bandVisible: sceneBand.bandVisible
                bandName: sceneBand.bandName
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
        plotRect: root.rulerBandPlotRect
        bandVisible: root.rulerBandVisible
        bandName: "timelineQuickRuler"
        plotInputName: "timelineRulerInput"
        gutterInputName: "timelineRulerGutterInput"

        TimelineSceneLayer {
            parent: rulerBand.gutterSide
            objectName: "timelineQuickRulerGutterChrome"
            sceneLayer: TimelineQuickItem.RulerGutterChrome
            z: 0
        }

        TimelineSceneLayer {
            parent: rulerBand.plotSide
            objectName: "timelineQuickRulerChrome"
            sceneLayer: TimelineQuickItem.RulerChrome
            z: 0
        }
        TimelineSceneLayer {
            parent: rulerBand.plotSide
            objectName: "timelineQuickRulerMarks"
            sceneLayer: TimelineQuickItem.RulerMarks
            z: 1
        }
        TimelineTextLayer {
            parent: rulerBand.plotSide
            textModel: timelineScene.rulerTextModel
            z: 2
        }

        // Controls stay physically in the gutter; the menu anchor maps into
        // the plot host, and the tooltip overlays the unclipped canvas root.
        RulerControls {
            parent: rulerBand.gutterSide
            objectName: "timelineRulerControls"
            width: rulerBand.gutterSide.width
            height: parent.height
            menuTarget: rulerBand.plotSide
            overlayRoot: root
            ruler: timeRuler
            z: 3
        }
    }

    TimelineSceneBand {
        id: rollBand

        bandRect: root.rollBandRect
        plotRect: root.rollBandPlotRect
        bandVisible: root.rollBandVisible
        bandName: "timelineQuickRoll"
        plotInputName: "timelineRollInput"
        gutterInputName: "timelineRollGutterInput"

        PianoRollCanvas {
            gutterSide: rollBand.gutterSide
            plotSide: rollBand.plotSide
        }
    }

    TimelineSceneBand {
        id: automationBand

        bandRect: root.automationBandRect
        plotRect: root.automationBandPlotRect
        bandVisible: root.automationBandVisible
        bandName: "timelineQuickAutomation"
        plotInputName: "timelineAutomationInput"
        gutterInputName: "timelineAutomationGutterInput"
        z: 1

        TimelineSceneLayer {
            parent: automationBand.gutterSide
            objectName: "timelineQuickAutomationGutterChrome"
            sceneLayer: TimelineQuickItem.AutomationGutterChrome
            z: 0
        }

        TimelineTextLayer {
            parent: automationBand.gutterSide
            textModel: timelineScene.automationTextModel
            z: 1
        }
        TimelineSceneLayer {
            parent: automationBand.plotSide
            objectName: "timelineQuickAutomationGrid"
            sceneLayer: TimelineQuickItem.AutomationGrid
            z: 0
        }
        TimelineSceneLayer {
            parent: automationBand.plotSide
            objectName: "timelineQuickAutomationCurves"
            sceneLayer: TimelineQuickItem.AutomationCurves
            z: 1
        }
        TimelineSceneLayer {
            parent: automationBand.plotSide
            objectName: "timelineQuickAutomationNodes"
            sceneLayer: TimelineQuickItem.AutomationNodes
            z: 2
        }
        TimelineSceneLayer {
            parent: automationBand.plotSide
            objectName: "timelineQuickAutomationSelection"
            sceneLayer: TimelineQuickItem.AutomationSelection
            z: 3
        }
        TimelineSceneLayer {
            parent: automationBand.plotSide
            objectName: "timelineQuickAutomationTransient"
            sceneLayer: TimelineQuickItem.AutomationTransient
            z: 4
        }
        TimelineSceneLayer {
            parent: automationBand.plotSide
            objectName: "timelineQuickAutomationHover"
            sceneLayer: TimelineQuickItem.AutomationHover
            z: 5
        }
        TimelineTextLayer {
            parent: automationBand.plotSide
            textModel: timelineScene.automationHoverTextModel
            z: 7
        }
        TimelineTextLayer {
            parent: automationBand.plotSide
            textModel: timelineScene.automationTransientTextModel
            z: 8
        }
    }

    TimelineSceneBand {
        id: velocityBand

        bandRect: root.velocityBandRect
        plotRect: root.velocityBandPlotRect
        bandVisible: root.velocityBandVisible
        bandName: "timelineQuickVelocity"
        plotInputName: "timelineVelocityInput"
        gutterInputName: "timelineVelocityGutterInput"
        z: 1

        TimelineSceneLayer {
            parent: velocityBand.gutterSide
            objectName: "timelineQuickVelocityGutterChrome"
            sceneLayer: TimelineQuickItem.VelocityGutterChrome
            z: 0
        }
        TimelineSceneLayer {
            parent: velocityBand.gutterSide
            objectName: "timelineQuickVelocityAxis"
            sceneLayer: TimelineQuickItem.VelocityAxis
            z: 1
        }
        TimelineTextLayer {
            parent: velocityBand.gutterSide
            textModel: timelineScene.velocityTextModel
            z: 2
        }

        TimelineSceneLayer {
            parent: velocityBand.plotSide
            objectName: "timelineQuickVelocityChrome"
            sceneLayer: TimelineQuickItem.VelocityChrome
            z: 0
        }
        TimelineSceneLayer {
            parent: velocityBand.plotSide
            objectName: "timelineQuickVelocityGrid"
            sceneLayer: TimelineQuickItem.VelocityGrid
            z: 2
        }
        TimelineSceneLayer {
            parent: velocityBand.plotSide
            objectName: "timelineQuickVelocityBands"
            sceneLayer: TimelineQuickItem.VelocityBands
            z: 3
        }
        TimelineSceneLayer {
            parent: velocityBand.plotSide
            objectName: "timelineQuickVelocityStems"
            sceneLayer: TimelineQuickItem.VelocityStems
            z: 4
        }
        TimelineSceneLayer {
            parent: velocityBand.plotSide
            objectName: "timelineQuickVelocityNodes"
            sceneLayer: TimelineQuickItem.VelocityNodes
            z: 5
        }
        TimelineSceneLayer {
            parent: velocityBand.plotSide
            objectName: "timelineQuickVelocityTransient"
            sceneLayer: TimelineQuickItem.VelocityTransient
            z: 6
        }
    }

    TimelineSceneBand {
        id: voiceChangesBand

        bandRect: root.voiceChangesBandRect
        plotRect: root.voiceChangesBandPlotRect
        bandVisible: root.voiceChangesBandVisible
        bandName: "timelineQuickVoiceChanges"
        plotInputName: "timelineVoiceChangesInput"
        gutterInputName: "timelineVoiceChangesGutterInput"
        z: 2

        TimelineSceneLayer {
            parent: voiceChangesBand.gutterSide
            objectName: "timelineQuickVoiceChangesGutterChrome"
            sceneLayer: TimelineQuickItem.VoiceChangesGutterChrome
            z: 0
        }
        TimelineTextLayer {
            parent: voiceChangesBand.gutterSide
            textModel: timelineScene.voiceChangesGutterTextModel
            z: 1
        }

        TimelineSceneLayer {
            parent: voiceChangesBand.plotSide
            objectName: "timelineQuickVoiceChangesChrome"
            sceneLayer: TimelineQuickItem.VoiceChangesChrome
            z: 0
        }
        TimelineSceneLayer {
            parent: voiceChangesBand.plotSide
            objectName: "timelineQuickVoiceChangesGrid"
            sceneLayer: TimelineQuickItem.VoiceChangesGrid
            z: 1
        }
        TimelineSceneLayer {
            parent: voiceChangesBand.plotSide
            objectName: "timelineQuickVoiceChangesSpans"
            sceneLayer: TimelineQuickItem.VoiceChangesSpans
            z: 2
        }
        TimelineSceneLayer {
            parent: voiceChangesBand.plotSide
            objectName: "timelineQuickVoiceChangesMarkers"
            sceneLayer: TimelineQuickItem.VoiceChangesMarkers
            z: 3
        }
        TimelineSceneLayer {
            parent: voiceChangesBand.plotSide
            objectName: "timelineQuickVoiceChangesTransient"
            sceneLayer: TimelineQuickItem.VoiceChangesTransient
            z: 4
        }
        TimelineSceneLayer {
            parent: voiceChangesBand.plotSide
            objectName: "timelineQuickVoiceChangesHover"
            sceneLayer: TimelineQuickItem.VoiceChangesHover
            z: 5
        }
        TimelineTextLayer {
            parent: voiceChangesBand.plotSide
            textModel: timelineScene.voiceChangesTextModel
            z: 6
        }
        TimelineTextLayer {
            parent: voiceChangesBand.plotSide
            textModel: timelineScene.voiceChangesHoverTextModel
            z: 7
        }
    }

    TimelineSceneBand {
        id: otherEventsBand

        bandRect: root.otherEventsBandRect
        plotRect: root.otherEventsBandPlotRect
        bandVisible: root.otherEventsBandVisible
        bandName: "timelineQuickOtherEvents"
        plotInputName: "timelineOtherEventsInput"
        gutterInputName: "timelineOtherEventsGutterInput"

        TimelineSceneLayer {
            parent: otherEventsBand.gutterSide
            objectName: "timelineQuickOtherEventsGutterChrome"
            sceneLayer: TimelineQuickItem.OtherEventsGutterChrome
            z: 0
        }
        TimelineTextLayer {
            parent: otherEventsBand.gutterSide
            textModel: timelineScene.otherEventsTextModel
            z: 1
        }

        TimelineSceneLayer {
            parent: otherEventsBand.plotSide
            objectName: "timelineQuickOtherEventsChrome"
            sceneLayer: TimelineQuickItem.OtherEventsChrome
            z: 0
        }
        TimelineSceneLayer {
            parent: otherEventsBand.plotSide
            objectName: "timelineQuickOtherEventsMarkers"
            sceneLayer: TimelineQuickItem.OtherEventsMarkers
            z: 1
        }
    }

    // Single Quick playhead: one static TimelinePlayheadItem paints the bloom,
    // core bar and ruler triangle once. Its QSG clips remain in the
    // timeline-column frame while its child transform moves only geometry, so
    // gutters and splitters get no body pixels on position-only moves.
    TimelinePlayheadItem {
        id: timelinePlayhead

        objectName: "timelineQuickRollPlayhead"
        z: 50
        enabled: false
        visible: timelineQuickView.playheadVisible

        // Bands the playhead may paint in, with their published plot
        // rectangles — never the track headers.
        readonly property var sceneBands: [
            { visible: root.rulerBandVisible, rect: root.rulerBandRect, plotRect: root.rulerBandPlotRect },
            { visible: root.rollBandVisible, rect: root.rollBandRect, plotRect: root.rollBandPlotRect },
            { visible: root.automationBandVisible, rect: root.automationBandRect, plotRect: root.automationBandPlotRect },
            { visible: root.velocityBandVisible, rect: root.velocityBandRect, plotRect: root.velocityBandPlotRect },
            { visible: root.voiceChangesBandVisible, rect: root.voiceChangesBandRect, plotRect: root.voiceChangesBandPlotRect },
            { visible: root.otherEventsBandVisible, rect: root.otherEventsBandRect, plotRect: root.otherEventsBandPlotRect }
        ]

        readonly property var visibleBandRects: sceneBands.filter(band => band.visible)
                                                             .map(band => band.rect)

        // Vertical span of the union of the visible band rects.
        y: visibleBandRects.length === 0
           ? 0
           : visibleBandRects.reduce((top, rect) => Math.min(top, rect.y), Infinity)
        height: visibleBandRects.length === 0
                ? 0
                : visibleBandRects.reduce((bottom, rect) => Math.max(bottom, rect.y + rect.height),
                                          -Infinity) - y

        // The host-local canonical split anchors this timeline-column surface.
        x: timelineQuickView.rulerPlotOrigin
        width: Math.max(0, root.width - x)

        // Published plot strips are host-local. Translate them by the canonical
        // split into this item's timeline-column-local body-mask coordinates.
        bodyPlotRects: {
            const strips = []
            for (const band of sceneBands) {
                if (band.visible && band.plotRect.width > 0) {
                    strips.push(Qt.rect(band.plotRect.x - timelineQuickView.rulerPlotOrigin,
                                        band.plotRect.y, band.plotRect.width,
                                        band.plotRect.height))
                }
            }
            return strips
        }
        // The item derives its triangle-only overhang clip from this local
        // ruler plot; the body strips above remain strict at x >= 0.
        rulerPlotRect: Qt.rect(root.rulerBandPlotRect.x - timelineQuickView.rulerPlotOrigin,
                               root.rulerBandPlotRect.y, root.rulerBandPlotRect.width,
                               root.rulerBandPlotRect.height)

        // Appearance (playheadChanged): color and shape.
        color: timelineQuickView.playheadColor
        glowLeft: timelineQuickView.playheadGlowLeft
        glowRight: timelineQuickView.playheadGlowRight
        peakAlpha: timelineQuickView.playheadPeakAlpha
        lineWidthPx: timelineQuickView.playheadLineWidthPx
        trianglePointsUp: timelineQuickView.playheadTrianglePointsUp
        triangleHalfWidthPx: timelineQuickView.playheadTriangleHalfWidthPx
        triangleHeightPx: timelineQuickView.playheadTriangleHeightPx

        // Position (playheadXChanged): raw timeline-local X moves only the
        // item's scene-graph geometry; clip paths and bounds stay static.
        localX: timelineQuickView.playheadLocalX
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
