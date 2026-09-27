pragma ComponentBehavior: Bound

import QtQuick
import Porydaw.Ui

Item {
    id: plot

    objectName: "automationPlot"
    required property var model
    required property var pageModel
    required property var gridModel
    required property var gridPalette
    required property real baseFontPx
    required property real devicePixelRatio
    required property bool pageVisible
    required property var hintService
    required property bool hintScopeAllowed
    required property int plotSurface
    required property bool pencilCursorVisible
    property alias input: plotInput

    function cursorFor(kind) {
        switch (kind) {
        case 2: return Qt.SizeVerCursor
        case 3: return Qt.SizeHorCursor
        case 4: return Qt.ClosedHandCursor
        default: return Qt.ArrowCursor
        }
    }

    clip: true
    activeFocusOnTab: true
    Binding {
        target: plot.model
        property: "plotFocused"
        value: (plot.activeFocus || plotInput.activeFocus) && plot.pageVisible
        when: plot.model !== null
        restoreMode: Binding.RestoreNone
    }

    Rectangle {
        anchors.fill: parent
        color: plot.gridPalette.rollBackground
    }

    TimelineQuickItem {
        objectName: "automationGridLines"
        anchors.fill: parent
        rects: (plot.pageModel ? plot.pageModel.gridLines : [])
    }

    TimelineQuickItem {
        objectName: "automationValueLines"
        anchors.fill: parent
        rects: (plot.pageModel ? plot.pageModel.valueLines : [])
    }

    Repeater {
        model: (plot.pageModel ? plot.pageModel.valueLabels : [])

        delegate: Text {
            required property var labelSpec
            required property string labelText
            required property var labelFont
            objectName: "automationScaleLabel"

            x: labelSpec.x
            y: labelSpec.y
            width: labelSpec.width
            height: labelSpec.height
            text: labelText
            color: plot.gridPalette.primaryText
            font: Qt.font(labelFont)
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            horizontalAlignment: labelSpec.horizontal
            verticalAlignment: labelSpec.vertical
            elide: Text.ElideRight
            maximumLineCount: 1
            clip: true
        }
    }

    TimelineQuickItem {
        objectName: "automationSelectionRects"
        anchors.fill: parent
        rects: (plot.pageModel ? plot.pageModel.selectionRects : [])
    }

    TimelineQuickItem {
        objectName: "automationCurveRuns"
        anchors.fill: parent
        rects: (plot.pageModel ? plot.pageModel.curveRuns : [])
    }

    Repeater {
        model: (plot.pageModel ? plot.pageModel.ghostNameLabels : [])
        delegate: Rectangle {
            required property var labelSpec
            required property string labelText
            required property var labelFont
            property alias text: ghostCaption.text
            objectName: "automationGhostNameLabel"
            x: labelSpec.x
            y: labelSpec.y
            width: labelSpec.width
            height: labelSpec.height
            color: plot.gridPalette.chromeBackground
            Text {
                id: ghostCaption
                objectName: "automationGhostCaption"
                anchors.fill: parent
                text: labelText
                color: plot.gridPalette.windowText
                font: Qt.font(labelFont)
                textFormat: Text.PlainText
                renderType: Text.NativeRendering
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    Rectangle {
        id: hoverGuide
        objectName: "automationHoverGuide"
        readonly property var display: plot.pageModel.hoverDisplay
        visible: display.visible && display.hasGhost
        x: display.guideX - width / 2
        y: 0
        width: 1 / plot.devicePixelRatio
        height: plot.height
        color: plot.gridPalette.windowText
        Accessible.ignored: true
    }

    Rectangle {
        objectName: "automationHoverGhost"
        readonly property var display: plot.pageModel.hoverDisplay
        readonly property real radiusPx: Math.max(1, Math.round(plot.baseFontPx * 3 / 16))
        visible: display.visible && display.hasGhost
        x: display.guideX - radiusPx
        y: display.ghostY - radiusPx
        width: radiusPx * 2
        height: width
        radius: radiusPx
        color: plot.gridPalette.windowText
        Accessible.ignored: true
    }

    // Draw published nodes and the origin phantom with selected/hover rings.
    Repeater {
        model: (plot.pageModel ? plot.pageModel.nodes : [])

        delegate: Item {
            id: node

            required property var model
            // One packed spec per node: every child binding reads the local
            // map instead of paying a metaCall per property.
            readonly property var s: model ? model.spec : ({})

            objectName: node.s.primitiveName + (node.s.phantom ? "Phantom" : "")
            x: 0
            y: 0
            width: plot.width
            height: plot.height
            Accessible.ignored: true

            Rectangle {
                objectName: "automationNodeRing"
                visible: node.s.selected
                x: node.s.x - node.s.ringRadius
                y: node.s.y - node.s.ringRadius
                width: 2 * node.s.ringRadius
                height: 2 * node.s.ringRadius
                radius: node.s.ringRadius
                color: "transparent"
                border.width: Math.max(1, node.s.outlineWidth)
                border.color: node.s.ringColor
            }

            Rectangle {
                objectName: "automationNodeHover"
                visible: plot.pageModel.hoverDisplay.hasNode
                         && plot.pageModel.hoverDisplay.nodeTick === node.s.tick
                         && !node.s.selected
                x: node.s.x - node.s.ringRadius
                y: node.s.y - node.s.ringRadius
                width: 2 * node.s.ringRadius
                height: 2 * node.s.ringRadius
                radius: node.s.ringRadius
                color: "transparent"
                border.width: Math.max(1, node.s.outlineWidth)
                border.color: node.s.ringColor
            }

            Rectangle {
                objectName: "automationNodeFill"
                x: node.s.x - node.s.radius
                y: node.s.y - node.s.radius
                width: 2 * node.s.radius
                height: 2 * node.s.radius
                radius: node.s.radius
                color: node.s.fillColor
                border.width: Math.max(1, node.s.outlineWidth)
                border.color: node.s.outlineColor
            }
        }
    }

    // The range press's own band.
    Rectangle {
        objectName: "automationRangeBand"

        visible: (plot.pageModel ? plot.pageModel.bandVisible : false)
        x: (plot.pageModel ? plot.pageModel.bandRect.x : 0)
        y: (plot.pageModel ? plot.pageModel.bandRect.y : 0)
        width: (plot.pageModel ? plot.pageModel.bandRect.width : 0)
        height: (plot.pageModel ? plot.pageModel.bandRect.height : 0)
        color: plot.gridPalette.selectionFill
        border.width: 1
        border.color: plot.gridPalette.selectionEdge
        Accessible.ignored: true
    }

    // The frozen gesture's draft markers.
    TimelineQuickItem {
        objectName: "automationPreviewRects"
        anchors.fill: parent
        rects: (plot.pageModel ? plot.pageModel.previewRects : [])
    }

    // The hover value label and the live gesture's own readout.
    Text {
        objectName: "automationHoverLabel"

        visible: plot.pageModel.hoverDisplay.visible
        x: plot.pageModel.hoverDisplay.x
        y: plot.pageModel.hoverDisplay.y
        width: plot.pageModel.hoverDisplay.width
        height: plot.pageModel.hoverDisplay.height
        text: plot.pageModel.hoverDisplay.text
        color: plot.gridPalette.primaryText
        font: Qt.font(plot.pageModel ? plot.pageModel.noteNameFont : {})
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        clip: true
    }

    Text {
        objectName: "automationPreviewLabel"

        visible: (plot.pageModel ? plot.pageModel.previewLabelVisible : false)
        x: (plot.pageModel ? plot.pageModel.previewLabelRect.x : 0)
        y: (plot.pageModel ? plot.pageModel.previewLabelRect.y : 0)
        width: (plot.pageModel ? plot.pageModel.previewLabelRect.width : 0)
        height: (plot.pageModel ? plot.pageModel.previewLabelRect.height : 0)
        text: (plot.pageModel ? plot.pageModel.previewLabelText : "")
        color: plot.gridPalette.primaryText
        font: Qt.font(plot.pageModel ? plot.pageModel.noteNameFont : {})
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        clip: true
    }

    // The effective context readout: the active parameter and the value it
    // holds at the shared tick.
    Text {
        objectName: "automationReadout"

        visible: (plot.pageModel ? plot.pageModel.readoutVisible : false)
        x: (plot.pageModel ? plot.pageModel.readoutRect.x : 0)
        y: (plot.pageModel ? plot.pageModel.readoutRect.y : 0)
        width: (plot.pageModel ? plot.pageModel.readoutRect.width : 0)
        height: (plot.pageModel ? plot.pageModel.readoutRect.height : 0)
        text: (plot.pageModel ? plot.pageModel.readoutText : "")
        color: plot.gridPalette.primaryText
        font: Qt.font(plot.pageModel ? plot.pageModel.titleFont : {})
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        clip: true
    }

    Text {
        objectName: "automationPlotMessage"

        visible: !(plot.pageModel ? plot.pageModel.trackAvailable : false)
                 && (plot.pageModel ? plot.pageModel.plotMessage : "").length > 0
        anchors.centerIn: parent
        text: (plot.pageModel ? plot.pageModel.plotMessage : "")
        color: plot.gridPalette.primaryText
        font: Qt.font(plot.pageModel ? plot.pageModel.captionFont : {})
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
    }

    MouseArea {
        id: plotInput

        objectName: "automationPlotInput"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: plot.pencilCursorVisible ? Qt.BlankCursor
            : plot.cursorFor(plot.pageModel ? plot.pageModel.cursorKind : 0)

        onPressed: mouse => {
            plotMoves.flush()
            mouse.accepted = plot.pageModel.pointerPress(
                mouse.x, mouse.y, plot.plotSurface, mouse.button, mouse.modifiers)
            if (mouse.accepted)
                plotInput.forceActiveFocus(Qt.MouseFocusReason)
        }
        onDoubleClicked: (mouse) => {
            plotMoves.flush()
            if (mouse.button === Qt.LeftButton)
                plot.pageModel.pointerDoubleClick(mouse.x, mouse.y)
            mouse.accepted = true
        }
        onPositionChanged: (mouse) => plotMoves.enqueue(
            mouse.x, mouse.y, mouse.buttons, mouse.modifiers)
        onReleased: (mouse) => {
            plotMoves.flush()
            plotHint.settleRelease(plotInput.mapToItem(null, mouse.x, mouse.y))
            mouse.accepted = plot.pageModel.pointerRelease(
                mouse.x, mouse.y, mouse.button, mouse.modifiers)
        }
        onCanceled: {
            plotMoves.flush()
            plotHint.settleRelease(plotHint.point.scenePosition)
            plot.pageModel.cancelSectionInteraction()
        }
        onExited: {
            plotMoves.flush()
            plot.pageModel.pointerLeave()
        }
        MoveCoalescer {
            id: plotMoves
            dispatch: (x, y, buttons, modifiers) =>
                plot.pageModel.pointerMove(x, y, buttons, modifiers)
        }
        Accessible.role: Accessible.Canvas
        Accessible.name: qsTr("Automation plot")
        Accessible.description: plot.pageModel.accessibleDescription
        Accessible.focusable: true
    }

    // Retain hover profile during the real grab, then settle on release.
    HoverHint {
        id: plotHint

        source: plot
        hintService: plot.hintService
        scopeAllowed: plot.hintScopeAllowed
        gestureOwning: plotInput.pressed
        profile: plot.pageModel.hoverHintProfile
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        onWheel: (event) => {
            // The shared navigation owner: the roll's own wheel entry, with
            // this plot's anchor, so zoom stays anchored where the pointer is.
            if (!plot.gridModel)
                return
            plot.gridModel.handleWheel(
                event.angleDelta.x, event.angleDelta.y,
                event.pixelDelta.x, event.pixelDelta.y,
                event.modifiers, event.phase, false, event.x, event.y)
            event.accepted = true
        }
    }

    Accessible.role: Accessible.Canvas
    Accessible.name: qsTr("Automation")
    Accessible.description: (plot.pageModel ? plot.pageModel.accessibleDescription : "")
    Accessible.focusable: true
}
