// The Velocity drawer page: the ruler column, the plot's grid and PSG level
// bands, the note handles and the gesture transient.
//
// Swift owns every value (VelocityPage.swift): the shared camera projection, the
// axis ladder, the note handles, the hover/selection/preview state, the frozen
// gesture and the prompt transaction. This file renders published primitives and
// delivers real pointer, wheel, keyboard and accessibility input to that owner.
// It holds no velocity, no axis rule, no camera and no clock, and it reads no
// document: the plot origin and base font come from the same published facts the
// roll and the container use.
//
// Two input surfaces, two coordinate spaces, exactly as the legacy velocity band
// splits them: `velocityRuler` owns the click-to-set column in ruler-local
// coordinates, and `velocityPlot` owns editing in plot-local coordinates (the
// same space the camera projects into).
pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui

FocusScope {
    id: page

    objectName: "velocityPage"

    required property QtObject applicationSession
    property var hintService: null
    property bool hintScopeAllowed: true

    /// The page's Swift owner for the current document, and the neutral empty
    /// model while there is none: `velocityPage()` fails once no document is
    /// presented, and the host removes this scene before the session releases the
    /// page. A guarded binding is therefore what a teardown re-evaluation
    /// resolves, and it re-reads the owner when the session publishes the next
    /// document.
    readonly property var model: page.applicationSession
                                 && page.applicationSession.songOpen
                                 ? page.applicationSession.velocityPage()
                                 : null
    /// Every read below resolves against this: the installed owner, or the
    /// neutral empty model while there is none.
    readonly property var pageModel: page.model !== null && page.model !== undefined
                                     ? page.model : emptyModel

    readonly property var gridModel: page.applicationSession
                                     && page.applicationSession.songOpen
                                     ? page.applicationSession.gridPresenter()
                                     : null
    /// The palette this page draws with. The page can be re-evaluated during scene
    /// teardown, after the session released the grid, so every palette read
    /// below goes through this guarded expression; the fallback draws nothing.
    readonly property var gridPalette: page.gridModel ? page.gridModel.palette : fallbackPalette

    QtObject {
        id: fallbackPalette

        /// Neutral colors for the window between scene removal and the session's
        /// release; nothing drawn then reaches a frame.
        readonly property color chromeBackground: "transparent"
        readonly property color rollBackground: "transparent"
        readonly property color primaryText: "transparent"
        readonly property color windowBackground: "transparent"
        readonly property color windowText: "transparent"
        readonly property color outline: "transparent"
        readonly property color focusOutline: "transparent"
        readonly property color buttonBackground: "transparent"
        readonly property color buttonText: "transparent"
        readonly property color buttonPressedBackground: "transparent"
        readonly property color buttonPressedText: "transparent"
        readonly property color disabledText: "transparent"
    }
    QtObject {
        id: emptyModel

        readonly property list<QtObject> axisTicks: []
        readonly property list<QtObject> axisGraduations: []
        readonly property list<QtObject> axisMarkers: []
        readonly property list<QtObject> axisLabels: []
        readonly property list<QtObject> gridLines: []
        readonly property list<QtObject> psgBands: []
        readonly property list<QtObject> transientRects: []
        readonly property list<QtObject> handles: []
        readonly property bool rampVisible: false
        readonly property double rampX0: 0
        readonly property double rampY0: 0
        readonly property double rampLength: 0
        readonly property double rampSlopeY: 0
        readonly property string rampColor: page.gridPalette.primaryText
        readonly property bool contextUnsupported: false
        readonly property string contextDiagnostic: ""
        readonly property bool readoutVisible: false
        readonly property bool detentsEnabled: true
        readonly property double baseFontPx: 13
        readonly property bool promptOpen: false
        readonly property string promptDraft: ""
        readonly property string promptError: ""
        readonly property string promptTitle: ""
        readonly property string promptLabel: ""
        readonly property int promptMinimum: 1
        readonly property int promptMaximum: 127

        readonly property string axisAccessibleDescription: "Velocity"
        readonly property string readoutText: ""

        function configureBody(width: real, height: real, rulerWidth: real,
                               devicePixelRatio: real, baseFontPx: real,
                               dragDistance: real): void {}
        function pointerPress(x: real, y: real, surface: int, button: int, modifiers: int): bool { return false }
        function pointerMove(x: real, y: real, buttons: int): bool { return false }
        function pointerRelease(x: real, y: real, button: int): bool { return false }
        function pointerLeave(): void {}
        function handleEscape(): bool { return false }
        function toggleDetents(): void {}
        function setUseDetents(enabled: bool): void {}
        function updatePromptDraft(text: string): void {}
        function acceptPrompt(): bool { return false }
        function cancelPrompt(): void {}
        function cancelSectionInteraction(): void {}
    }
    /// The shared plot origin: the gutter the roll draws at and the container
    /// publishes as `plotOrigin`.
    readonly property real plotOrigin: page.gridModel
                                       ? (page.gridModel.trackHeaderWidth || 0)
                                         + page.gridModel.keyboardWidth : 0
    readonly property real plotWidth: Math.max(page.width - page.plotOrigin, 0)
    /// The snapped surface scroll the handle container translates by, and the
    /// zoom scale handles place ticks with; both track the scene scroll row.
    property real contentScrollX: 0
    property real contentPixelsPerTick: 0
    readonly property real contentDpr: page.Screen.devicePixelRatio
    /// This page's own base-font seed, for the window before a document is
    /// presented.
    readonly property real seedBaseFontPx: 13
    /// The application font's line spacing and the grid's base font are the same
    /// facts the drawer chrome is measured with.
    readonly property real baseFontPx: page.gridModel
                                       ? page.gridModel.baseFontPx
                                       : page.seedBaseFontPx

    function pushBodyFacts(): void {
        if (!page.pageModel || page.width <= 0 || page.height <= 0)
            return
        page.pageModel.configureBody(page.width, page.height, page.plotOrigin,
                                 page.Screen.devicePixelRatio, page.baseFontPx,
                                 Application.styleHints.startDragDistance)
    }

    // Every fact `configureBody` publishes is a dependency: the owner's arrival,
    // the drawn size, the plot origin and the font the page's own geometry is
    // measured from. The owner compares and rebuilds only for real changes.
    onModelChanged: page.pushBodyFacts()
    onWidthChanged: page.pushBodyFacts()
    onHeightChanged: page.pushBodyFacts()
    onPlotOriginChanged: page.pushBodyFacts()
    onBaseFontPxChanged: page.pushBodyFacts()
    Component.onCompleted: page.pushBodyFacts()

    // The shared clock reaches this page in Swift: `ApplicationSession` fans the
    // presenter's distinct presentations into the page owner, so no QML surface
    // reads the presenter or calls a page mutator through a bridge wrapper.

    // A live gesture or an open prompt claims Escape; everything else passes on
    // to the window, so the shared routing keeps owning Escape.
    Keys.onEscapePressed: (event) => event.accepted = page.pageModel.handleEscape()
    onActiveFocusChanged: {
        // The prompt is hosted above the drawer, outside this FocusScope.
        // Moving focus into its field must not cancel the very prompt that
        // requested focus; section hide/detach still cancels at its owner.
        if (!activeFocus && !page.pageModel.promptOpen)
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
                model: page.pageModel ? page.pageModel.axisTicks : []
                delegate: Rectangle {
                    required property var frame
                    required property string fillColor
                    required property string primitiveName
                    objectName: primitiveName
                    x: frame.x
                    y: frame.y
                    width: frame.width
                    height: frame.height
                    color: fillColor
                }
            }
        }

        Item {
            objectName: "velocityRulerGraduations"
            anchors.fill: parent
            Repeater {
                model: page.pageModel ? page.pageModel.axisGraduations : []
                delegate: Rectangle {
                    required property var frame
                    required property string fillColor
                    required property string primitiveName
                    objectName: primitiveName
                    x: frame.x
                    y: frame.y
                    width: frame.width
                    height: frame.height
                    color: fillColor
                }
            }
        }

        Item {
            objectName: "velocityRulerMarkers"
            anchors.fill: parent
            Repeater {
                model: page.pageModel ? page.pageModel.axisMarkers : []
                delegate: Rectangle {
                    required property var frame
                    required property string fillColor
                    required property string primitiveName
                    objectName: primitiveName
                    x: frame.x
                    y: frame.y
                    width: frame.width
                    height: frame.height
                    color: fillColor
                }
            }
        }

        Repeater {
            model: (page.pageModel ? page.pageModel.axisLabels : [])

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
                page.pageModel.cancelSectionInteraction()
            }
            onExited: {
                rulerMoves.flush()
                page.pageModel.pointerLeave()
            }
            MoveCoalescer {
                id: rulerMoves
                function dispatchMove(x: real, y: real, buttons: int, modifiers: int): bool {
                    return page.pageModel.pointerMove(x, y, buttons)
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

        model: page.gridModel ? page.gridModel.scene.cameraScroll : []
        delegate: Item {
            required property var frame
            onFrameChanged: applyScrollFrame()
            Component.onCompleted: applyScrollFrame()
            function applyScrollFrame(): void {
                if (frame) {
                    var dpr = page.Screen.devicePixelRatio
                    page.contentScrollX = Math.round(frame.x * dpr) / dpr
                    page.contentPixelsPerTick = frame.width
                }
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

        // Note stems and nodes. One delegate per handle; a selected handle draws
        // its ring and its unfilled center exactly as the row model publishes it,
        // and a single selected note keeps its outline while a multi-selection
        // dims the unselected rows.
        Item {
            id: handleContent

            width: plot.width
            height: plot.height
            // Stable rows translate once here from the surface scroll carrier,
            // same-turn like the roll plot content.
            x: -page.contentScrollX

            Repeater {
                model: (page.pageModel ? page.pageModel.handles : [])

                // Retained handles stay tick-space stable; rows enter and leave
                // only when the camera escapes the published overscan window.
                delegate: Item {
                    id: node

                    required property var model
                    // Packed Swift values remain a map until the typed publication wave.
                    readonly property var s: node.model.spec
                    // Zoom re-evaluates only the root x and the stem end; children sit relative.
                    x: Math.round(node.s.tick * page.contentPixelsPerTick * page.contentDpr)
                       / page.contentDpr
                    readonly property real endX: Math.round(
                        node.s.endTick * page.contentPixelsPerTick * page.contentDpr) / page.contentDpr

                    Rectangle {
                        objectName: node.s.primitiveName + "Stem"
                        x: Math.min(0, node.endX - node.x)
                        y: node.s.y - node.s.stemWidth / 2
                        width: Math.max(1, Math.abs(node.endX - node.x))
                        height: node.s.stemWidth
                        color: node.s.stemColor
                    }

                    Rectangle {
                        objectName: node.s.primitiveName + "Ring"
                        visible: node.s.selected
                        x: -node.s.ringRadius
                        y: node.s.y - node.s.ringRadius
                        width: 2 * node.s.ringRadius
                        height: 2 * node.s.ringRadius
                        radius: node.s.ringRadius
                        color: "transparent"
                        border.color: node.s.ringColor
                        border.width: node.s.ringWidth
                    }

                    Rectangle {
                        objectName: node.s.primitiveName + "Fill"
                        x: -node.s.nodeRadius
                        y: node.s.y - node.s.nodeRadius
                        width: 2 * node.s.nodeRadius
                        height: 2 * node.s.nodeRadius
                        radius: node.s.nodeRadius
                        color: node.s.fillColor
                        border.width: node.s.selected || !node.s.dimmed
                                      ? node.s.outlineWidth : 0
                        border.color: node.s.outlineColor
                    }

                    Rectangle {
                        objectName: node.s.primitiveName + "Hover"
                        visible: node.s.hovered && !node.s.selected
                        x: -node.s.outlineRadius
                        y: node.s.y - node.s.outlineRadius
                        width: 2 * node.s.outlineRadius
                        height: 2 * node.s.outlineRadius
                        radius: node.s.outlineRadius
                        color: "transparent"
                        border.color: node.s.ringColor
                        border.width: node.s.ringWidth
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
                page.pageModel.cancelSectionInteraction()
            }
            onExited: {
                plotMoves.flush()
                page.pageModel.pointerLeave()
            }
            MoveCoalescer {
                id: plotMoves
                function dispatchMove(x: real, y: real, buttons: int, modifiers: int): bool {
                    return page.pageModel.pointerMove(x, y, buttons)
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
