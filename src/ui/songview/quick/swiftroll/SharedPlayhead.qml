// Swift publishes the shared camera projection; this input-transparent surface
// clips the playhead and guides to the roll and each visible drawer body.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Porydaw.Ui
import PorydawApp as App

Item {
    id: root

    objectName: "sharedPlayhead"

    required property App.SharedPlayheadPresenter presenter
    required property color playheadColor
    required property bool rollBodyVisible
    required property App.PlayheadGuidesPresenter guides
    required property color hoverGuideColor
    required property color editGuideColor
    // The canonical plot rectangle in surface coordinates: its x is the shared
    // plot origin, so every segment's line reads the same presenter contentX.
    required property rect rollPlotRect
    // The drawer container's surface-local rectangle; each section state below
    // carries that kind's drawer-local body rectangle.
    required property rect drawerRect
    required property App.EditorDrawerSectionState velocitySection
    required property App.EditorDrawerSectionState voiceChangesSection
    required property App.EditorDrawerSectionState automationSection
    readonly property real contentX: presenter.contentX
    readonly property real glowLeft: presenter.glowLeft
    readonly property real glowRight: presenter.glowRight
    readonly property real peakAlpha: presenter.peakAlpha
    readonly property real triangleHalfWidthPx: presenter.triangleHalfWidthPx
    readonly property real triangleHeightPx: presenter.triangleHeightPx
    readonly property bool trianglePointsUp: presenter.trianglePointsUp
    readonly property rect velocityBodyRect: Qt.rect(plotOrigin, drawerRect.y + velocitySection.bodyY,
                                                    plotWidth, velocitySection.bodyHeight)
    readonly property rect voiceChangesBodyRect: Qt.rect(plotOrigin, drawerRect.y + voiceChangesSection.bodyY,
                                                        plotWidth, voiceChangesSection.bodyHeight)
    readonly property rect automationBodyRect: Qt.rect(plotOrigin, drawerRect.y + automationSection.bodyY,
                                                      plotWidth, automationSection.bodyHeight)
    readonly property bool velocityAvailable: velocitySection !== null && velocitySection.available && velocitySection.visible
    readonly property bool voiceChangesAvailable: voiceChangesSection !== null && voiceChangesSection.available && voiceChangesSection.visible
    readonly property bool automationAvailable: automationSection !== null && automationSection.available && automationSection.visible

    function glowColor(alpha: real): color {
        return Qt.rgba(root.playheadColor.r, root.playheadColor.g, root.playheadColor.b, alpha)
    }

    /// The shared plot origin: where projected x == 0 lands on the surface.
    readonly property real plotOrigin: rollPlotRect.x
    readonly property real plotWidth: Math.max(rollPlotRect.width, 0)
    readonly property real devicePixelRatio: Screen.devicePixelRatio > 0
        ? Screen.devicePixelRatio : 1
    readonly property real hairline: 1 / devicePixelRatio
    // Keep the core centered on one physical pixel as the camera moves through
    // fractional positions; otherwise its apparent width pulses on Windows.
    readonly property real alignedContentX:
        (Math.round((plotOrigin + contentX) * devicePixelRatio - 0.5)
         + 0.5) / devicePixelRatio - plotOrigin

    // Only the ruler triangle extends beyond the shared plot clip.
    component PlayheadSegment: Item {
        id: segment

        required property rect clipRect
        required property bool available
        required property bool rulerSegment

        readonly property real triangleOverhang: rulerSegment
            ? root.triangleHalfWidthPx : 0

        x: clipRect.x - triangleOverhang
        y: clipRect.y
        width: Math.max(clipRect.width + triangleOverhang, 0)
        height: Math.max(clipRect.height, 0)
        clip: true
        // Swift visibility excludes projections outside the viewport.
        visible: root.presenter !== null && root.presenter.timelineAttached && root.presenter.visible
                 && available && clipRect.width > 0 && width > 0 && height > 0

        // Body/core pixels retain the original strict segment clip.
        Item {
            id: bodyClip
            objectName: "sharedPlayheadBody"
            visible: !segment.rulerSegment || root.rollBodyVisible
            x: segment.triangleOverhang
            y: 0
            width: Math.max(segment.clipRect.width, 0)
            height: segment.height
            clip: true

            // Moving this one item translates the entire visual. Appearance
            // changes alter only its fixed geometry, never the segment layout.
            Item {
                id: playheadVisual
                x: root.alignedContentX - root.glowLeft
                y: 0
                width: root.glowLeft + root.hairline + root.glowRight
                height: segment.height

                Rectangle {
                    id: leftGlow
                    x: 0
                    y: 0
                    width: root.glowLeft
                    height: segment.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: root.glowColor(0)
                        }
                        GradientStop {
                            position: 0.125
                            color: root.glowColor(root.peakAlpha * 0.015625)
                        }
                        GradientStop {
                            position: 0.25
                            color: root.glowColor(root.peakAlpha * 0.0625)
                        }
                        GradientStop {
                            position: 0.375
                            color: root.glowColor(root.peakAlpha * 0.140625)
                        }
                        GradientStop {
                            position: 0.5
                            color: root.glowColor(root.peakAlpha * 0.25)
                        }
                        GradientStop {
                            position: 0.625
                            color: root.glowColor(root.peakAlpha * 0.390625)
                        }
                        GradientStop {
                            position: 0.75
                            color: root.glowColor(root.peakAlpha * 0.5625)
                        }
                        GradientStop {
                            position: 0.875
                            color: root.glowColor(root.peakAlpha * 0.765625)
                        }
                        GradientStop {
                            position: 1
                            color: root.glowColor(root.peakAlpha)
                        }
                    }
                }

                Rectangle {
                    id: rightGlow
                    x: root.glowLeft
                    y: 0
                    width: root.glowRight
                    height: segment.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: root.glowColor(root.peakAlpha)
                        }
                        GradientStop {
                            position: 0.125
                            color: root.glowColor(root.peakAlpha * 0.765625)
                        }
                        GradientStop {
                            position: 0.25
                            color: root.glowColor(root.peakAlpha * 0.5625)
                        }
                        GradientStop {
                            position: 0.375
                            color: root.glowColor(root.peakAlpha * 0.390625)
                        }
                        GradientStop {
                            position: 0.5
                            color: root.glowColor(root.peakAlpha * 0.25)
                        }
                        GradientStop {
                            position: 0.625
                            color: root.glowColor(root.peakAlpha * 0.140625)
                        }
                        GradientStop {
                            position: 0.75
                            color: root.glowColor(root.peakAlpha * 0.0625)
                        }
                        GradientStop {
                            position: 0.875
                            color: root.glowColor(root.peakAlpha * 0.015625)
                        }
                        GradientStop {
                            position: 1
                            color: root.glowColor(0)
                        }
                    }
                }

                Rectangle {
                    objectName: "sharedPlayheadLine"
                    x: root.glowLeft - root.hairline / 2
                    y: 0
                    width: root.hairline
                    height: segment.height
                    color: root.playheadColor
                }
            }
        }

        // The ruler triangle stays centered while its left half clips.
        Item {
            id: triangleClip
            visible: segment.rulerSegment
            x: 0
            y: 0
            width: Math.max(segment.clipRect.width + segment.triangleOverhang, 0)
            height: root.triangleHeightPx
            clip: true

            Shape {
                id: rulerTriangle
                x: root.alignedContentX
                y: 0
                width: 2 * root.triangleHalfWidthPx
                height: root.triangleHeightPx

                // The current roll geometry points down; retain the published
                // orientation so a future ruler layout can point it up.
                rotation: root.trianglePointsUp ? 180 : 0

                ShapePath {
                    fillColor: root.playheadColor
                    strokeWidth: 0
                    startX: 0
                    startY: 0
                    PathLine {
                        x: 2 * root.triangleHalfWidthPx
                        y: 0
                    }
                    PathLine {
                        x: root.triangleHalfWidthPx
                        y: root.triangleHeightPx
                    }
                    PathLine {
                        x: 0
                        y: 0
                    }
                }
            }
        }
    }

    // Repeat logical-pixel dashes from each body's top edge.
    component GuideSegment: Item {
        id: guideSegment

        required property rect clipRect
        required property App.PlayheadGuideState guide
        required property color guideColor
        required property bool available

        x: clipRect.x
        y: clipRect.y
        width: Math.max(clipRect.width, 0)
        height: Math.max(clipRect.height, 0)
        clip: true
        visible: root.guides !== null && guide !== null && root.guides.timelineAttached
                 && guide.visible && available && width > 0 && height > 0

        // Only x changes with the guide; dash geometry depends on height.
        Shape {
            id: guideLine
            x: guideSegment.guide.contentX
            y: 0
            width: 1
            height: guideSegment.height

            ShapePath {
                strokeColor: guideSegment.guideColor
                strokeWidth: 1
                fillColor: "transparent"
                dashPattern: [1, 1]
                startX: 0.5
                startY: 0
                PathLine {
                    x: 0.5
                    y: guideSegment.height
                }
            }
        }
    }

    PlayheadSegment {
        objectName: "sharedPlayheadRollClip"
        clipRect: root.rollPlotRect
        available: true
        rulerSegment: true
    }

    PlayheadSegment {
        objectName: "sharedPlayheadVelocityClip"
        clipRect: root.velocityBodyRect
        available: root.velocityAvailable
        rulerSegment: false
    }

    PlayheadSegment {
        objectName: "sharedPlayheadVoiceChangesClip"
        clipRect: root.voiceChangesBodyRect
        available: root.voiceChangesAvailable
        rulerSegment: false
    }

    PlayheadSegment {
        objectName: "sharedPlayheadAutomationClip"
        clipRect: root.automationBodyRect
        available: root.automationAvailable
        rulerSegment: false
    }

    // Draw the edit guide first; the presenter hides it whenever a hover guide
    // is visible, and the hover group remains the topmost guide layer.
    GuideSegment {
        objectName: "sharedPlayheadEditRollGuide"
        clipRect: root.rollPlotRect
        guide: root.guides?.edit ?? null
        guideColor: root.editGuideColor
        available: root.rollBodyVisible
    }

    GuideSegment {
        objectName: "sharedPlayheadEditVelocityGuide"
        clipRect: root.velocityBodyRect
        guide: root.guides?.edit ?? null
        guideColor: root.editGuideColor
        available: root.velocityAvailable
    }

    GuideSegment {
        objectName: "sharedPlayheadEditVoiceChangesGuide"
        clipRect: root.voiceChangesBodyRect
        guide: root.guides?.edit ?? null
        guideColor: root.editGuideColor
        available: root.voiceChangesAvailable
    }

    GuideSegment {
        objectName: "sharedPlayheadEditAutomationGuide"
        clipRect: root.automationBodyRect
        guide: root.guides?.edit ?? null
        guideColor: root.editGuideColor
        available: root.automationAvailable
    }

    GuideSegment {
        objectName: "sharedPlayheadHoverRollGuide"
        clipRect: root.rollPlotRect
        guide: root.guides?.hover ?? null
        guideColor: root.hoverGuideColor
        available: root.rollBodyVisible
    }

    GuideSegment {
        objectName: "sharedPlayheadHoverVelocityGuide"
        clipRect: root.velocityBodyRect
        guide: root.guides?.hover ?? null
        guideColor: root.hoverGuideColor
        available: root.velocityAvailable
    }

    GuideSegment {
        objectName: "sharedPlayheadHoverVoiceChangesGuide"
        clipRect: root.voiceChangesBodyRect
        guide: root.guides?.hover ?? null
        guideColor: root.hoverGuideColor
        available: root.voiceChangesAvailable
    }

    GuideSegment {
        objectName: "sharedPlayheadHoverAutomationGuide"
        clipRect: root.automationBodyRect
        guide: root.guides?.hover ?? null
        guideColor: root.hoverGuideColor
        available: root.automationAvailable
    }

}
