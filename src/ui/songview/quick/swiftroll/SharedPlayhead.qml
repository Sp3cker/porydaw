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
// Every segment's clip is the shared plot column: the canonical origin is the
// roll gutter width, so a segment can never cross the keyboard gutter, a drawer
// gutter, a resize handle, a hidden or unavailable body, or the chrome bar that
// sits below the bodies. A segment is hidden, never moved, while its projected x
// is outside the camera viewport.
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    objectName: "sharedPlayhead"

    required property QtObject presenter
    required property color playheadColor
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
    // segment is always available while a timeline is attached.
    component PlayheadSegment: Item {
        id: segment

        required property rect clipRect
        required property bool available

        x: clipRect.x
        y: clipRect.y
        width: Math.max(clipRect.width, 0)
        height: Math.max(clipRect.height, 0)
        clip: true
        // The item stays mounted while the timeline is attached; only its own
        // clip decides whether a pixel is drawn, and the presenter's published
        // visibility already excludes a projection outside the viewport.
        visible: root.presenter.timelineAttached && root.presenter.visible
                 && available && width > 0 && height > 0

        Rectangle {
            objectName: "sharedPlayheadLine"
            x: root.presenter.contentX
            y: 0
            width: 1
            height: segment.height
            color: root.playheadColor
        }
    }

    PlayheadSegment {
        objectName: "sharedPlayheadRollClip"
        clipRect: root.rollPlotRect
        available: true
    }

    PlayheadSegment {
        objectName: "sharedPlayheadVelocityClip"
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.velocitySection.bodyY,
                          root.plotWidth, root.velocitySection.bodyHeight)
        available: root.velocitySection.available && root.velocitySection.visible
    }

    PlayheadSegment {
        objectName: "sharedPlayheadVoiceChangesClip"
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.voiceChangesSection.bodyY,
                          root.plotWidth, root.voiceChangesSection.bodyHeight)
        available: root.voiceChangesSection.available && root.voiceChangesSection.visible
    }

    PlayheadSegment {
        objectName: "sharedPlayheadAutomationClip"
        clipRect: Qt.rect(root.plotOrigin,
                          root.drawerRect.y + root.automationSection.bodyY,
                          root.plotWidth, root.automationSection.bodyHeight)
        available: root.automationSection.available && root.automationSection.visible
    }
}
