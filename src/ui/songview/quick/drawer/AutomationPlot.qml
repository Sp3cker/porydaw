pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Porydaw.Ui
import PorydawApp as App

Item {
    id: plot

    objectName: "automationPlot"
    required final property App.AutomationPage model
    required final property App.AutomationPage pageModel
    required final property App.PianoGrid gridModel
    required final property App.GridPalette gridPalette
    required final property real baseFontPx
    required final property real devicePixelRatio
    required final property bool pageVisible
    required final property App.MouseHints hintService
    required final property bool hintScopeAllowed
    required final property int plotSurface
    property alias input: plotInput
    final property color nodeFill
    Binding on nodeFill {
        when: plot.gridPalette !== null
        value: plot.gridPalette?.windowBackground
        restoreMode: Binding.RestoreNone
    }

    function cursorFor(kind: int): int {
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
        Binding on color {
            when: plot.gridPalette !== null
            value: plot.gridPalette?.rollBackground
            restoreMode: Binding.RestoreNone
        }
    }

    DisplayList {
        objectName: "automationAxis"
        anchors.fill: parent
        clip: true
        source: plot.pageModel
        list: 0
        revision: plot.pageModel ? plot.pageModel.displayRevision : 0
    }

    Repeater {
        model: plot.pageModel ? plot.pageModel.valueLabels : null

        delegate: Text {
            required x
            required y
            required width
            required height
            required property string labelText
            required property font labelFont
            required property int horizontal
            required property int vertical
            objectName: "automationScaleLabel"

            text: labelText
            Binding on color {
                when: plot.gridPalette !== null
                value: plot.gridPalette?.primaryText
                restoreMode: Binding.RestoreNone
            }
            font: labelFont
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            horizontalAlignment: horizontal
            verticalAlignment: vertical
            elide: Text.ElideRight
            maximumLineCount: 1
            clip: true
        }
    }


    DisplayList {
        objectName: "automationStatics"
        anchors.fill: parent
        clip: true
        source: plot.pageModel
        list: 1
        revision: plot.pageModel ? plot.pageModel.displayRevision : 0
    }

    Repeater {
        model: plot.pageModel ? plot.pageModel.ghostNameLabels : null
        delegate: Rectangle {
            id: ghostLabel
            required x
            required y
            required width
            required height
            required property string labelText
            required property font labelFont
            property alias text: ghostCaption.text
            objectName: "automationGhostNameLabel"
            Binding on color {
                when: plot.gridPalette !== null
                value: plot.gridPalette?.chromeBackground
                restoreMode: Binding.RestoreNone
            }
            Text {
                id: ghostCaption
                objectName: "automationGhostCaption"
                anchors.fill: parent
                text: ghostLabel.labelText
                Binding on color {
                    when: plot.gridPalette !== null
                    value: plot.gridPalette?.windowText
                    restoreMode: Binding.RestoreNone
                }
                font: ghostLabel.labelFont
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
        readonly property App.AutomationHoverDisplay hoverState: plot.pageModel ? plot.pageModel.hoverDisplay : null
        visible: hoverState !== null && hoverState.visible && hoverState.hasGhost
        x: hoverState ? hoverState.guideX - width / 2 : 0
        y: 0
        width: 1 / plot.devicePixelRatio
        height: plot.height
        Binding on color {
            when: plot.gridPalette !== null
            value: plot.gridPalette?.windowText
            restoreMode: Binding.RestoreNone
        }
        Accessible.ignored: true
    }

    Rectangle {
        objectName: "automationHoverGhost"
        readonly property App.AutomationHoverDisplay hoverState: plot.pageModel ? plot.pageModel.hoverDisplay : null
        readonly property real radiusPx: Math.max(1, Math.round(plot.baseFontPx * 3 / 16))
        visible: hoverState !== null && hoverState.visible && hoverState.hasGhost
        x: hoverState ? hoverState.guideX - radiusPx : 0
        y: hoverState ? hoverState.ghostY - radiusPx : 0
        width: radiusPx * 2
        height: width
        radius: radiusPx
        Binding on color {
            when: plot.gridPalette !== null
            value: plot.gridPalette?.windowText
            restoreMode: Binding.RestoreNone
        }
        Accessible.ignored: true
    }

    component NodeVisual: Item {
        id: node
        required property var model
        required property color fillColor
        property bool hovered: false
        readonly property real nodeX: model.x
        readonly property real nodeY: model.y
        required property real tick
        required property real radius
        required property real ringRadius
        required property real outlineWidth
        required property real outerRadius
        required property real ringWidth
        required property real ringOuterRadius
        required property real hoverOuterRadius
        required property color outlineColor
        required property color ringColor
        required property bool selected
        required property bool phantom
        required property string primitiveName
        objectName: node.primitiveName + (node.phantom ? "Phantom" : "")
        Accessible.ignored: true

        Shape {
            objectName: "automationNodeRing"
            visible: node.selected
            x: node.nodeX - node.ringOuterRadius
            y: node.nodeY - node.ringOuterRadius
            width: 2 * node.ringOuterRadius
            height: width
            ShapePath {
                fillColor: "transparent"
                strokeColor: node.ringColor
                strokeWidth: node.ringWidth
                PathAngleArc {
                    centerX: node.ringOuterRadius
                    centerY: node.ringOuterRadius
                    radiusX: node.ringRadius
                    radiusY: radiusX
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }
        Shape {
            objectName: "automationNodeHover"
            visible: node.hovered && !node.selected
            x: node.nodeX - node.hoverOuterRadius
            y: node.nodeY - node.hoverOuterRadius
            width: 2 * node.hoverOuterRadius
            height: width
            ShapePath {
                fillColor: "transparent"
                strokeColor: node.ringColor
                strokeWidth: 2
                PathAngleArc {
                    centerX: node.hoverOuterRadius
                    centerY: node.hoverOuterRadius
                    radiusX: node.hoverOuterRadius - 1
                    radiusY: radiusX
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }
        Shape {
            objectName: "automationNodeFill"
            x: node.nodeX - node.outerRadius
            y: node.nodeY - node.outerRadius
            width: 2 * node.outerRadius
            height: width
            ShapePath {
                fillColor: node.fillColor
                strokeColor: node.outlineColor
                strokeWidth: 2 * node.outlineWidth
                PathAngleArc {
                    centerX: node.outerRadius
                    centerY: node.outerRadius
                    radiusX: node.radius
                    radiusY: radiusX
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }
    }
    // Draw published nodes and the origin phantom with selected/hover rings.
    Repeater {
        model: plot.pageModel ? plot.pageModel.nodes : null

        delegate: NodeVisual {
            id: writtenNode
            fillColor: plot.nodeFill
            hovered: plot.pageModel !== null && plot.pageModel.hoverDisplay.hasNode
                     && plot.pageModel.hoverDisplay.nodeTick === writtenNode.tick
            width: plot.width
            height: plot.height
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
        Binding on color {
            when: plot.gridPalette !== null
            value: plot.gridPalette?.selectionFill
            restoreMode: Binding.RestoreNone
        }
        border.width: 1
        Binding on border.color {
            when: plot.gridPalette !== null
            value: plot.gridPalette?.selectionEdge
            restoreMode: Binding.RestoreNone
        }
        Accessible.ignored: true
    }

    // The frozen gesture's draft markers.
    DisplayList {
        objectName: "automationPreviewRects"
        anchors.fill: parent
        clip: true
        source: plot.pageModel
        list: 2
        revision: plot.pageModel ? plot.pageModel.displayRevision : 0
    }
    Repeater {
        model: plot.pageModel ? plot.pageModel.previewNodes : null
        delegate: NodeVisual {
            fillColor: plot.nodeFill
            width: plot.width
            height: plot.height
        }
    }

    // The hover value label and the live gesture's own readout.
    Text {
        objectName: "automationHoverLabel"

        visible: plot.pageModel !== null && plot.pageModel.hoverDisplay.visible
        x: plot.pageModel ? plot.pageModel.hoverDisplay.x : 0
        y: plot.pageModel ? plot.pageModel.hoverDisplay.y : 0
        width: plot.pageModel ? plot.pageModel.hoverDisplay.width : 0
        height: plot.pageModel ? plot.pageModel.hoverDisplay.height : 0
        text: plot.pageModel ? plot.pageModel.hoverDisplay.text : ""
        Binding on color {
            when: plot.gridPalette !== null
            value: plot.gridPalette?.primaryText
            restoreMode: Binding.RestoreNone
        }
        Binding on font {
            when: plot.pageModel !== null
            value: plot.pageModel?.noteNameFont
            restoreMode: Binding.RestoreNone
        }
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
        Binding on color {
            when: plot.gridPalette !== null
            value: plot.gridPalette?.primaryText
            restoreMode: Binding.RestoreNone
        }
        Binding on font {
            when: plot.pageModel !== null
            value: plot.pageModel?.noteNameFont
            restoreMode: Binding.RestoreNone
        }
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
        Binding on color {
            when: plot.gridPalette !== null
            value: plot.gridPalette?.primaryText
            restoreMode: Binding.RestoreNone
        }
        Binding on font {
            when: plot.pageModel !== null
            value: plot.pageModel?.titleFont
            restoreMode: Binding.RestoreNone
        }
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
        Binding on color {
            when: plot.gridPalette !== null
            value: plot.gridPalette?.primaryText
            restoreMode: Binding.RestoreNone
        }
        Binding on font {
            when: plot.pageModel !== null
            value: plot.pageModel?.captionFont
            restoreMode: Binding.RestoreNone
        }
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
    }

    MouseArea {
        id: plotInput

        objectName: "automationPlotInput"
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        enabled: plot.pageModel !== null
        hoverEnabled: true
        preventStealing: true

        ItemCursor {
            readonly property App.AutomationPage pageModel: plot.pageModel
            readonly property int kind: pageModel ? pageModel.cursorKind : 0
            readonly property bool pencilArmed: pageModel !== null && pageModel.isPencilMode
                && kind <= 1 && !pageModel.menuOpen && !pageModel.promptOpen
            objectName: "automationPlotCursor"
            target: plotInput
            shape: plot.cursorFor(kind)
            source: pencilArmed ? "qrc:/cursors/pencil.png" : ""
            extent: 16
            hotSpot: ItemCursor.BottomLeft
            devicePixelRatio: plot.devicePixelRatio
        }

        onPressed: mouse => {
            if (!plot.pageModel) { mouse.accepted = false; return }
            plotMoves.flush()
            mouse.accepted = plot.pageModel.pointerPress(
                mouse.x, mouse.y, plot.plotSurface, mouse.button, mouse.modifiers)
            if (mouse.accepted)
                plotInput.forceActiveFocus(Qt.MouseFocusReason)
        }
        onDoubleClicked: (mouse) => {
            plotMoves.flush()
            if (!plot.pageModel) { mouse.accepted = false; return }
            if (mouse.button === Qt.LeftButton)
                plot.pageModel.pointerDoubleClick(mouse.x, mouse.y)
            mouse.accepted = true
        }
        onPositionChanged: (mouse) => plotMoves.enqueue(
            mouse.x, mouse.y, mouse.buttons, mouse.modifiers)
        onReleased: (mouse) => {
            plotMoves.flush()
            plotHint.settleRelease(plotInput.mapToItem(null, mouse.x, mouse.y))
            mouse.accepted = plot.pageModel !== null && plot.pageModel.pointerRelease(
                mouse.x, mouse.y, mouse.button, mouse.modifiers)
        }
        onCanceled: {
            plotMoves.flush()
            plotHint.settleRelease(plotHint.point.scenePosition)
            if (plot.pageModel) plot.pageModel.cancelSectionInteraction()
        }
        onExited: {
            plotMoves.flush()
            if (plot.pageModel) plot.pageModel.pointerLeave()
        }
        MoveCoalescer {
            id: plotMoves
            dispatch: function(x: real, y: real, buttons: int, modifiers: int): bool {
                return plot.pageModel !== null && plot.pageModel.pointerMove(x, y, buttons, modifiers)
            }
        }
        Accessible.role: Accessible.Canvas
        Accessible.name: qsTr("Automation plot")
        Accessible.description: plot.pageModel ? plot.pageModel.accessibleDescription : ""
        Accessible.focusable: true
    }

    // Retain hover profile during the real grab, then settle on release.
    HoverHint {
        id: plotHint

        source: plot
        hintService: plot.hintService
        scopeAllowed: plot.hintScopeAllowed
        gestureOwning: plotInput.pressed
        profile: plot.pageModel ? plot.pageModel.hoverHintProfile : HintProfiles.Empty
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
