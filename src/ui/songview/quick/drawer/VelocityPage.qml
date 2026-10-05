// Swift owns velocity projection and editing; QML renders rows and forwards input.
pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui
import PorydawApp as App

DrawerLanePage {
    id: page

    objectName: "velocityPage"

    property App.MouseHints hintService: null
    property bool hintScopeAllowed: true

    readonly property App.VelocityPage model: page.applicationSession.songOpen
                                            ? page.applicationSession.velocityPage() : null
    readonly property App.VelocityPage pageModel: page.model
    final readonly property App.GridPalette gridPalette: page.applicationSession.timeSigHost.palette
    enabled: page.pageModel !== null
    /// The snapped surface scroll the handle container translates by, and the
    /// zoom scale handles place ticks with; both track the scene scroll row.
    property real contentScrollX: 0
    property real contentPixelsPerTick: 0
    readonly property real contentDpr: page.Screen.devicePixelRatio

    function pushBodyFacts(): void {
        if (!page.pageModel || page.width <= 0 || page.height <= 0)
            return
        page.pageModel.configureBody(page.width, page.height, page.plotOrigin,
                                 page.Screen.devicePixelRatio, page.baseFontPx,
                                 Application.styleHints.startDragDistance)
    }

    // Publish body geometry only when its owner or measured facts change.
    onModelChanged: page.pushBodyFacts()
    onBodyFactsChanged: page.pushBodyFacts()

    // The session fans shared-playhead publications into the Swift page owner.

    // A live gesture or an open prompt claims Escape; everything else passes on
    // to the window, so the shared routing keeps owning Escape.
    Keys.onEscapePressed: (event) => event.accepted = page.pageModel ? page.pageModel.handleEscape() : false
    onActiveFocusChanged: {
        // Moving focus to the externally hosted prompt must not cancel it.
        if (!activeFocus && page.pageModel && !page.pageModel.promptOpen)
            page.pageModel.cancelSectionInteraction()
    }

    // ---- ruler column -------------------------------------------------------

    Item {
        id: ruler

        objectName: "velocityRuler"
        x: 0
        y: 0
        width: page.plotOrigin
        height: page.height
        clip: true

        Rectangle {
            anchors.fill: parent
            color: page.gridPalette.chromeBackground
        }

        Item {
            objectName: "velocityRulerMarks"
            anchors.fill: parent
            Repeater {
                model: page.pageModel ? page.pageModel.axisTicks : null
                delegate: Rectangle {
                    id: tick
                    required property var model
                    required property color fillColor
                    required property string primitiveName
                    objectName: tick.primitiveName
                    required x
                    required y
                    required width
                    required height
                    color: tick.fillColor
                }
            }
        }

        Item {
            objectName: "velocityRulerGraduations"
            anchors.fill: parent
            Repeater {
                model: page.pageModel ? page.pageModel.axisGraduations : null
                delegate: Rectangle {
                    id: graduation
                    required property var model
                    required property color fillColor
                    required property string primitiveName
                    objectName: graduation.primitiveName
                    required x
                    required y
                    required width
                    required height
                    color: graduation.fillColor
                }
            }
        }

        Item {
            objectName: "velocityRulerMarkers"
            anchors.fill: parent
            Repeater {
                model: page.pageModel ? page.pageModel.axisMarkers : null
                delegate: Rectangle {
                    id: axisMarker
                    required property var model
                    required property color fillColor
                    required property string primitiveName
                    objectName: axisMarker.primitiveName
                    required x
                    required y
                    required width
                    required height
                    color: axisMarker.fillColor
                }
            }
        }

        Repeater {
            model: page.pageModel ? page.pageModel.axisLabels : null

            delegate: Text {
                id: axisLabel
                required property var model
                required property string labelText
                required property font labelFont
                required property int horizontal
                required property int vertical

                required x
                required y
                required width
                required height
                text: axisLabel.labelText
                required color
                font: axisLabel.labelFont
                horizontalAlignment: axisLabel.horizontal
                verticalAlignment: axisLabel.vertical
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                elide: Text.ElideNone
                maximumLineCount: 1
                clip: contentWidth > width || contentHeight > height
            }
        }

        // The ruler's own pointer surface: click-to-set on the selected notes.
        MouseArea {
            id: rulerInput

            objectName: "velocityRulerInput"
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            preventStealing: true

            onPressed: (mouse) => {
                rulerMoves.flush()
                mouse.accepted =
                    page.pageModel.pointerPress(mouse.x, mouse.y, page.rulerSurface,
                                                mouse.button, mouse.modifiers)
            }
            onPositionChanged: (mouse) => rulerMoves.enqueue(
                mouse.x, mouse.y, mouse.buttons, mouse.modifiers)
            onReleased: (mouse) => {
                rulerMoves.flush()
                rulerHint.settleRelease(rulerInput.mapToItem(null, mouse.x, mouse.y))
                mouse.accepted = page.pageModel.pointerRelease(mouse.x, mouse.y, mouse.button)
            }
            onCanceled: {
                rulerMoves.flush()
                rulerHint.settleRelease(rulerHint.point.scenePosition)
                if (page.pageModel)
                    page.pageModel.cancelSectionInteraction()
            }
            onExited: {
                rulerMoves.flush()
                if (page.pageModel)
                    page.pageModel.pointerLeave()
            }
            MoveCoalescer {
                id: rulerMoves
                function dispatchMove(x: real, y: real, buttons: int, modifiers: int): bool {
                    return page.pageModel ? page.pageModel.pointerMove(x, y, buttons) : false
                }
                dispatch: rulerMoves.dispatchMove
            }
        }

        HoverHint {
            id: rulerHint

            source: ruler
            hintService: page.hintService
            scopeAllowed: page.hintScopeAllowed
            gestureOwning: rulerInput.pressed
            profile: HintProfiles.VelocityGutter
        }

        Accessible.role: Accessible.Column
        Accessible.name: qsTr("Velocity ruler")
        Accessible.description: (page.pageModel ? page.pageModel.axisAccessibleDescription : "Velocity")
        Accessible.focusable: false
    }

    // Scroll and handle rows update in one dataChanged sweep, so the container
    // translation never lags a queued bridge NOTIFY.
    Repeater {
        id: scrollCarrier

        model: page.gridModel ? page.gridModel.scene.cameraScroll : null
        delegate: Item {
            id: scrollRow
            required property var model
            readonly property real scrollX: scrollRow.model.x
            readonly property real pixelsPerTick: scrollRow.model.width
            onScrollXChanged: applyScrollFrame()
            onPixelsPerTickChanged: applyScrollFrame()
            Component.onCompleted: applyScrollFrame()
            function applyScrollFrame(): void {
                const dpr = page.Screen.devicePixelRatio
                page.contentScrollX = Math.round(scrollRow.scrollX * dpr) / dpr
                page.contentPixelsPerTick = scrollRow.pixelsPerTick
            }
        }
    }

    Item {
        id: plot

        objectName: "velocityPlot"
        x: page.plotOrigin
        y: 0
        width: page.plotWidth
        height: page.height
        clip: true
        activeFocusOnTab: true

        Rectangle {
            anchors.fill: parent
            color: page.gridPalette.rollBackground
        }

        DisplayList {
            objectName: "velocityGridLines"
            anchors.fill: parent
            clip: true
            source: page.pageModel
            list: 0
            revision: page.pageModel ? page.pageModel.displayRevision : 0
        }

        // Selected handles keep their ring; multi-selection dims unselected rows.
        Item {
            id: handleContent

            width: plot.width
            height: plot.height
            // Stable rows translate once here from the surface scroll carrier,
            // same-turn like the roll plot content.
            x: -page.contentScrollX

            Repeater {
                model: page.pageModel ? page.pageModel.handles : null

                // Retained handles stay tick-space stable; rows enter and leave
                // only when the camera escapes the published overscan window.
                delegate: Item {
                    id: node

                    required property var model
                    required property real tick
                    required property real endTick
                    required property real stemWidth
                    required property real nodeRadius
                    required property real outlineRadius
                    required property real outlineWidth
                    required property real ringRadius
                    required property real ringWidth
                    required property color stemColor
                    required property color fillColor
                    required property color ringColor
                    required property color outlineColor
                    required property bool selected
                    required property bool hovered
                    required property bool dimmed
                    required property string primitiveName
                    readonly property real nodeY: node.model.y
                    // Zoom re-evaluates only the root x and the stem end; children sit relative.
                    x: Math.round(node.tick * page.contentPixelsPerTick * page.contentDpr)
                       / page.contentDpr
                    readonly property real endX: Math.round(
                        node.endTick * page.contentPixelsPerTick * page.contentDpr) / page.contentDpr

                    Rectangle {
                        objectName: node.primitiveName + "Stem"
                        x: Math.min(0, node.endX - node.x)
                        y: node.nodeY - node.stemWidth / 2
                        width: Math.max(1, Math.abs(node.endX - node.x))
                        height: node.stemWidth
                        color: node.stemColor
                    }

                    Rectangle {
                        objectName: node.primitiveName + "Ring"
                        visible: node.selected
                        x: -node.ringRadius
                        y: node.nodeY - node.ringRadius
                        width: 2 * node.ringRadius
                        height: 2 * node.ringRadius
                        radius: node.ringRadius
                        color: "transparent"
                        border.color: node.ringColor
                        border.width: node.ringWidth
                    }

                    Rectangle {
                        objectName: node.primitiveName + "Fill"
                        x: -node.nodeRadius
                        y: node.nodeY - node.nodeRadius
                        width: 2 * node.nodeRadius
                        height: 2 * node.nodeRadius
                        radius: node.nodeRadius
                        color: node.fillColor
                        border.width: node.selected || !node.dimmed
                                      ? node.outlineWidth : 0
                        border.color: node.outlineColor
                    }

                    Rectangle {
                        objectName: node.primitiveName + "Hover"
                        visible: node.hovered && !node.selected
                        x: -node.outlineRadius
                        y: node.nodeY - node.outlineRadius
                        width: 2 * node.outlineRadius
                        height: 2 * node.outlineRadius
                        radius: node.outlineRadius
                        color: "transparent"
                        border.color: node.ringColor
                        border.width: node.ringWidth
                    }
                }
            }
        }

        // The gesture transient: the band reticle's fill and dashed edges, plus
        // the ramp line the press-to-pointer span draws.
        DisplayList {
            objectName: "velocityTransient"
            anchors.fill: parent
            clip: true
            source: page.pageModel
            list: 1
            revision: page.pageModel ? page.pageModel.displayRevision : 0
        }

        Rectangle {
            objectName: "velocityRamp"

            visible: (page.pageModel ? page.pageModel.rampVisible : false)
            x: (page.pageModel ? page.pageModel.rampX0 : 0)
            y: (page.pageModel ? page.pageModel.rampY0 : 0)
            width: (page.pageModel ? page.pageModel.rampLength : 0)
            height: 1
            color: (page.pageModel ? page.pageModel.rampColor : page.gridPalette.primaryText)
            transformOrigin: Item.TopLeft
            rotation: (page.pageModel ? page.pageModel.rampLength : 0) > 0
                      ? Math.atan2((page.pageModel ? page.pageModel.rampSlopeY : 0), (page.pageModel ? page.pageModel.rampLength : 0)) * 180 / Math.PI
                      : 0
        }

        MouseArea {
            id: plotInput

            objectName: "velocityPlotInput"
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            preventStealing: true

            onPressed: (mouse) => {
                plotMoves.flush()
                // Plot input arrives in plot space; adding the carrier scroll
                // restores the handles' scroll-stable space.
                mouse.accepted =
                    page.pageModel.pointerPress(mouse.x + page.contentScrollX,
                                                mouse.y, page.plotSurface,
                                                mouse.button, mouse.modifiers)
            }
            onPositionChanged: (mouse) => plotMoves.enqueue(
                mouse.x + page.contentScrollX, mouse.y, mouse.buttons, mouse.modifiers)
            onReleased: (mouse) => {
                plotMoves.flush()
                plotHint.settleRelease(plotInput.mapToItem(null, mouse.x, mouse.y))
                mouse.accepted = page.pageModel.pointerRelease(
                    mouse.x + page.contentScrollX, mouse.y, mouse.button)
            }
            onCanceled: {
                plotMoves.flush()
                plotHint.settleRelease(plotHint.point.scenePosition)
                if (page.pageModel)
                    page.pageModel.cancelSectionInteraction()
            }
            onExited: {
                plotMoves.flush()
                if (page.pageModel)
                    page.pageModel.pointerLeave()
            }
            MoveCoalescer {
                id: plotMoves
                function dispatchMove(x: real, y: real, buttons: int, modifiers: int): bool {
                    return page.pageModel ? page.pageModel.pointerMove(x, y, buttons) : false
                }
                dispatch: plotMoves.dispatchMove
            }
        }

        HoverHint {
            id: plotHint

            source: plot
            hintService: page.hintService
            scopeAllowed: page.hintScopeAllowed
            gestureOwning: plotInput.pressed
            profile: HintProfiles.VelocityBackground
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

            onWheel: (event) => {
                // The shared navigation owner: the roll's own wheel entry, with
                // this plot's anchor, so zoom stays anchored where the pointer is.
                if (!page.gridModel)
                    return
                page.gridModel.handleWheel(
                    event.angleDelta.x, event.angleDelta.y,
                    event.pixelDelta.x, event.pixelDelta.y,
                    event.modifiers, event.phase, false, event.x, event.y)
                event.accepted = true
            }
        }

        Accessible.role: Accessible.Canvas
        Accessible.name: qsTr("Velocity editor")
        Accessible.description: (page.pageModel ? page.pageModel.readoutVisible : false)
                                 ? (page.pageModel ? page.pageModel.axisAccessibleDescription : "Velocity") + ". "
                                   + (page.pageModel ? page.pageModel.readoutText : "")
                                 : (page.pageModel ? page.pageModel.axisAccessibleDescription : "Velocity")
        Accessible.focusable: true
    }


    readonly property int rulerSurface: 0
    readonly property int plotSurface: 1
}
