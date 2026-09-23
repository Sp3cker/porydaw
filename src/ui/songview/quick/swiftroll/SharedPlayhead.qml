// The shared playhead: one clipped vertical segment over the roll plot column
// and one over every visible drawer body, all reading the same published
// position.
//
// Swift owns the position (SharedPlayhead.swift: the authoritative audio sample
// mapped through the session timeline and projected through the session camera).
// This file renders published values only: it invents no position, no clock, no
// animation, no timer and no second camera, it owns no page, and it takes no
// input -- pointer and key traffic passes straight through to the roll and the
// drawer below it.
//
// Every body's clip is the shared plot column: the canonical origin is the
// roll gutter width, so body/core pixels can never cross the keyboard gutter, a
// drawer gutter, a resize handle, a hidden or unavailable body, or the chrome
// bar that sits below the bodies. The roll triangle alone extends its clip
// left by half its width, matching the native ruler clip. A segment is hidden,
// never moved, while its projected x is outside the camera viewport.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: root

    objectName: "sharedPlayhead"

    required property QtObject presenter
    required property color playheadColor
    required property QtObject guides
    required property color hoverGuideColor
    required property color editGuideColor
    // The canonical plot rectangle in surface coordinates: its x is the shared
    // plot origin, so every segment's line reads the same presenter contentX.
    required property rect rollPlotRect
    // The drawer container's surface-local rectangle; each section state below
    // carries that kind's drawer-local body rectangle.
    required property rect drawerRect
    required property QtObject velocitySection
    required property QtObject voiceChangesSection
    required property QtObject automationSection

    /// The shared plot origin: where projected x == 0 lands on the surface.
    readonly property real plotOrigin: rollPlotRect.x
    readonly property real plotWidth: Math.max(rollPlotRect.width, 0)

    // One clipped segment. `available` is the kind's own availability; the roll
    // segment is always available while a timeline is attached. The roll's
    // triangle clip is the only deliberate half-width overhang, matching the
    // native ruler clip while the body remains strict to `clipRect`.
    component PlayheadSegment: Item {
        id: segment

        required property rect clipRect
        required property bool available
        required property bool rulerSegment

        readonly property real triangleOverhang: rulerSegment
            ? root.presenter.triangleHalfWidthPx : 0

        x: clipRect.x - triangleOverhang
        y: clipRect.y
        width: Math.max(clipRect.width + triangleOverhang, 0)
        height: Math.max(clipRect.height, 0)
        clip: true
        // The item stays mounted while the timeline is attached; only its own
        // clip decides whether a pixel is drawn, and the presenter's published
        // visibility already excludes a projection outside the viewport.
        visible: root.presenter.timelineAttached && root.presenter.visible
                 && available && clipRect.width > 0 && width > 0 && height > 0

        // Body/core pixels retain the original strict segment clip.
        Item {
            id: bodyClip
            x: segment.triangleOverhang
            y: 0
            width: Math.max(segment.clipRect.width, 0)
            height: segment.height
            clip: true

            // Moving this one item translates the entire visual. Appearance
            // changes alter only its fixed geometry, never the segment layout.
            Item {
                id: playheadVisual
                x: root.presenter.contentX - root.presenter.glowLeft
                y: 0
                width: root.presenter.glowLeft
                       + root.presenter.lineWidthPx
                       + root.presenter.glowRight
                height: segment.height

                Rectangle {
                    id: leftGlow
                    x: 0
                    y: 0
                    width: root.presenter.glowLeft
                    height: segment.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b, 0)
                        }
                        GradientStop {
                            position: 0.125
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.015625)
                        }
                        GradientStop {
                            position: 0.25
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.0625)
                        }
                        GradientStop {
                            position: 0.375
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.140625)
                        }
                        GradientStop {
                            position: 0.5
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.25)
                        }
                        GradientStop {
                            position: 0.625
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.390625)
                        }
                        GradientStop {
                            position: 0.75
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.5625)
                        }
                        GradientStop {
                            position: 0.875
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.765625)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha)
                        }
                    }
                }

                Rectangle {
                    id: rightGlow
                    x: root.presenter.glowLeft
                    y: 0
                    width: root.presenter.glowRight
                    height: segment.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha)
                        }
                        GradientStop {
                            position: 0.125
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.765625)
                        }
                        GradientStop {
                            position: 0.25
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.5625)
                        }
                        GradientStop {
                            position: 0.375
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.390625)
                        }
                        GradientStop {
                            position: 0.5
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.25)
                        }
                        GradientStop {
                            position: 0.625
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.140625)
                        }
                        GradientStop {
                            position: 0.75
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.0625)
                        }
                        GradientStop {
                            position: 0.875
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b,
                                           root.presenter.peakAlpha * 0.015625)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.rgba(root.playheadColor.r, root.playheadColor.g,
                                           root.playheadColor.b, 0)
                        }
                    }
                }

                Rectangle {
                    objectName: "sharedPlayheadLine"
                    x: root.presenter.glowLeft - root.presenter.lineWidthPx / 2
                    y: 0
                    width: root.presenter.lineWidthPx
                    height: segment.height
                    color: root.playheadColor
                }
            }
        }

        // The roll plot has no separate Swift ruler band. Its ruler marks start
        // at this segment's top, so this clip keeps the down-pointing triangle
        // centered at contentX even when its left half is off the plot.
        Item {
            id: triangleClip
            visible: segment.rulerSegment
            x: 0
            y: 0
            width: Math.max(segment.clipRect.width + segment.triangleOverhang, 0)
            height: root.presenter.triangleHeightPx
            clip: true

            Shape {
                id: rulerTriangle
                x: root.presenter.contentX
                y: 0
                width: 2 * root.presenter.triangleHalfWidthPx
                height: root.presenter.triangleHeightPx

                // The current roll geometry points down; retain the published
                // orientation so a future ruler layout can point it up.
                rotation: root.presenter.trianglePointsUp ? 180 : 0

                ShapePath {
                    fillColor: root.playheadColor
                    strokeWidth: 0
                    startX: 0
                    startY: 0
                    PathLine {
                        x: 2 * root.presenter.triangleHalfWidthPx
                        y: 0
                    }
                    PathLine {
                        x: root.presenter.triangleHalfWidthPx
                        y: root.presenter.triangleHeightPx
                    }
                    PathLine {
                        x: 0
                        y: 0
                    }
                }
            }
        }
    }

    // One clipped dashed guide segment. The presenter owns visibility and
    // projected x; this component only clips it to the band and repeats
    // one-pixel marks with a one-pixel gap, starting at the band's top.
    component GuideSegment: Item {
        id: guideSegment

        required property rect clipRect
        required property QtObject guide
        required property color guideColor
        required property bool available

        x: clipRect.x
        y: clipRect.y
        width: Math.max(clipRect.width, 0)
        height: Math.max(clipRect.height, 0)
        clip: true
        visible: root.guides.timelineAttached && guide.visible && available
                 && width > 0 && height > 0

        // One scene-graph node for the whole dashed run: the stroke's dash
        // pattern is in stroke-width multiples, so [1, 1] is the native
        // one-pixel mark / one-pixel gap starting at the band's top. Only this
        // item's x re-evaluates when the guide moves; the dash geometry is
        // static per height.
        Shape {
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
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.velocitySection.bodyY,
                          root.plotWidth, root.velocitySection.bodyHeight)
        available: root.velocitySection.available && root.velocitySection.visible
        rulerSegment: false
    }

    PlayheadSegment {
        objectName: "sharedPlayheadVoiceChangesClip"
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.voiceChangesSection.bodyY,
                          root.plotWidth, root.voiceChangesSection.bodyHeight)
        available: root.voiceChangesSection.available && root.voiceChangesSection.visible
        rulerSegment: false
    }

    PlayheadSegment {
        objectName: "sharedPlayheadAutomationClip"
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.automationSection.bodyY,
                          root.plotWidth, root.automationSection.bodyHeight)
        available: root.automationSection.available && root.automationSection.visible
        rulerSegment: false
    }

    // Draw the edit guide first; the presenter hides it whenever a hover guide
    // is visible, and the hover group remains the topmost guide layer.
    GuideSegment {
        objectName: "sharedPlayheadEditRollGuide"
        clipRect: root.rollPlotRect
        guide: root.guides.edit
        guideColor: root.editGuideColor
        available: true
    }

    GuideSegment {
        objectName: "sharedPlayheadEditVelocityGuide"
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.velocitySection.bodyY,
                          root.plotWidth, root.velocitySection.bodyHeight)
        guide: root.guides.edit
        guideColor: root.editGuideColor
        available: root.velocitySection.available && root.velocitySection.visible
    }

    GuideSegment {
        objectName: "sharedPlayheadEditVoiceChangesGuide"
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.voiceChangesSection.bodyY,
                          root.plotWidth, root.voiceChangesSection.bodyHeight)
        guide: root.guides.edit
        guideColor: root.editGuideColor
        available: root.voiceChangesSection.available && root.voiceChangesSection.visible
    }

    GuideSegment {
        objectName: "sharedPlayheadEditAutomationGuide"
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.automationSection.bodyY,
                          root.plotWidth, root.automationSection.bodyHeight)
        guide: root.guides.edit
        guideColor: root.editGuideColor
        available: root.automationSection.available && root.automationSection.visible
    }

    GuideSegment {
        objectName: "sharedPlayheadHoverRollGuide"
        clipRect: root.rollPlotRect
        guide: root.guides.hover
        guideColor: root.hoverGuideColor
        available: true
    }

    GuideSegment {
        objectName: "sharedPlayheadHoverVelocityGuide"
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.velocitySection.bodyY,
                          root.plotWidth, root.velocitySection.bodyHeight)
        guide: root.guides.hover
        guideColor: root.hoverGuideColor
        available: root.velocitySection.available && root.velocitySection.visible
    }

    GuideSegment {
        objectName: "sharedPlayheadHoverVoiceChangesGuide"
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.voiceChangesSection.bodyY,
                          root.plotWidth, root.voiceChangesSection.bodyHeight)
        guide: root.guides.hover
        guideColor: root.hoverGuideColor
        available: root.voiceChangesSection.available && root.voiceChangesSection.visible
    }

    GuideSegment {
        objectName: "sharedPlayheadHoverAutomationGuide"
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.automationSection.bodyY,
                          root.plotWidth, root.automationSection.bodyHeight)
        guide: root.guides.hover
        guideColor: root.hoverGuideColor
        available: root.automationSection.available && root.automationSection.visible
    }

}
