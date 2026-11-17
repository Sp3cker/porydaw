// Swift owns velocity geometry and editing; QML hosts bulk drawing and input.
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
    /// The same-frame camera scroll converts plot pointers to Swift's stable geometry space.
    property real contentScrollX: 0

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
            color: page.gridPalette.windowBackground
        }
        // The label strip sits under the keyboard column, set apart from the header column.
        Rectangle {
            readonly property real stripWidth: page.gridModel ? page.gridModel.keyboardWidth : 0
            objectName: "velocityRulerLabelStrip"
            x: Math.max(0, parent.width - stripWidth)
            width: Math.min(parent.width, stripWidth)
            height: parent.height
            color: page.gridPalette.alternateBackground
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
                onDispatch: (x, y, buttons, modifiers) => rulerMoves.dispatchMove(x, y, buttons, modifiers)
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

    // Pointer conversion consumes the synchronous scroll row, not a queued bridge NOTIFY.
    Repeater {
        id: scrollCarrier

        model: page.gridModel ? page.gridModel.scene.cameraScroll : null
        delegate: Item {
            id: scrollRow
            required property var model
            readonly property real scrollX: scrollRow.model.x
            readonly property real dpr: page.Screen.devicePixelRatio
            onScrollXChanged: applyScrollFrame()
            onDprChanged: applyScrollFrame()
            Component.onCompleted: applyScrollFrame()
            function applyScrollFrame(): void {
                page.contentScrollX = Math.round(scrollRow.scrollX * scrollRow.dpr) / scrollRow.dpr
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
            color: page.gridPalette.windowBackground
        }

        DisplayList {
            objectName: "velocityGridLines"
            anchors.fill: parent
            clip: true
            source: page.pageModel
            list: 0
            revision: page.pageModel ? page.pageModel.displayRevision : 0
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
                onDispatch: (x, y, buttons, modifiers) => plotMoves.dispatchMove(x, y, buttons, modifiers)
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
