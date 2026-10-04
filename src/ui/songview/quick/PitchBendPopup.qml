pragma ComponentBehavior: Bound
// Swift owns both graph lanes and their document transactions.
// The popup projects the scene models through Quick Shapes.
import QtQuick
import QtQuick.Shapes
import Porydaw.Ui
import PorydawApp

Rectangle {
    id: root

    objectName: "pitchBendPopup"

    required final property PitchBendPresenter bridge

    required final property font fallbackFont


    readonly property real outerInset: bridge ? bridge.outerInset : 0
    readonly property real headerHeight: bridge ? bridge.headerHeight : 0
    readonly property real graphHeight: bridge ? bridge.graphHeight : 0
    readonly property real titleHeight: bridge ? bridge.titleHeight : 0
    readonly property real descriptionHeight: bridge ? bridge.descriptionHeight : 0
    readonly property real controlsHeight: bridge ? bridge.controlsHeight : 0
    readonly property real fieldWidth: bridge ? bridge.fieldWidth : 0
    readonly property real fieldHeight: bridge ? bridge.fieldHeight : 0
    readonly property real resetWidth: bridge ? bridge.resetWidth : 0
    readonly property real resetHeight: bridge ? bridge.resetHeight : 0
    readonly property real axisLabelHeight: bridge ? bridge.axisLabelHeight : 0
    readonly property real hairline: bridge ? bridge.hairline : 0

    // Secondary gaps derive from resolved chrome metrics; no raw widget pixel
    // sizes appear in this shell.
    readonly property real controlGap: outerInset / 2
    readonly property real rowGap: hairline * 2
    readonly property real axisPad: hairline * 4

    readonly property color windowBackgroundColor: bridge ? bridge.windowBackground : "transparent"
    readonly property color primaryTextColor: bridge ? bridge.primaryText : "transparent"
    readonly property color secondaryTextColor: bridge ? bridge.secondaryText : "transparent"
    final readonly property color outlineColor: bridge ? bridge.outline : "transparent"
    readonly property font titleFont: bridge ? bridge.titleFont : fallbackFont
    readonly property font captionFont: bridge ? bridge.captionFont : fallbackFont
    readonly property font monospaceFont: bridge ? bridge.monospaceFont : fallbackFont

    implicitWidth: bridge ? bridge.popupWidth : 0
    implicitHeight: bridge ? bridge.popupHeight : 0

    color: windowBackgroundColor
    border.width: hairline
    border.color: outlineColor

    // Blank chrome shields the roll from pointer and wheel input.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onWheel: (wheel) => wheel.accepted = true
    }

    Keys.onShortcutOverride: (event) => {
        if (bridge && bridge.isOpen
                && !bendRangeField.textInput.activeFocus
                && !lfoSpeedField.textInput.activeFocus
                && !event.matches(StandardKey.Undo) && !event.matches(StandardKey.Redo))
            event.accepted = true
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            event.accepted = false
            return
        }
        if (!bendRangeField.textInput.activeFocus && !lfoSpeedField.textInput.activeFocus)
            bridge.routeUnclaimedKey(event.key, event.modifiers, event.isAutoRepeat)
        event.accepted = true
    }
    Keys.onReleased: (event) => event.accepted = true

    Accessible.role: Accessible.Client
    Accessible.name: qsTr("Note automation editor")
    Accessible.description: bridge ? bridge.description : ""

    function resetLane(graph: GraphCanvas): void {
        if (!bridge || !graph)
            return
        if (graph === pitchGraph)
            bridge.resetPitchCurve()
        else
            bridge.resetModCurve()
        graph.forceActiveFocus(Qt.OtherFocusReason)
    }
    function focusInitialGraph(): void { pitchGraph.forceActiveFocus(Qt.PopupFocusReason) }

    component GraphLaneLabels: Item {
        id: labels

        required property GraphCanvas graph

        readonly property rect canvas: graph ? graph.canvasRect : Qt.rect(0, 0, 0, 0)

        Text {
            id: laneTitle

            x: labels.canvas.x
            y: 0
            width: Math.max(0, liveValue.width - liveValue.implicitWidth - root.controlGap)
            height: labels.canvas.y
            clip: true
            verticalAlignment: Text.AlignVCenter
            color: root.secondaryTextColor
            font: root.captionFont
            text: labels.graph ? labels.graph.laneTitle : ""
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
        }

        Text {
            id: liveValue
            objectName: labels.graph && labels.graph === pitchGraph
                        ? "pitchBendLiveValue" : "modWheelLiveValue"

            x: labels.canvas.x
            y: 0
            // Leave one gap before the Reset button in this band.
            width: Math.max(0, labels.canvas.width - root.resetWidth - root.controlGap)
            height: labels.canvas.y
            clip: true
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            color: root.secondaryTextColor
            font: root.monospaceFont
            text: labels.graph ? labels.graph.liveValueText : ""
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
        }

        Text {
            id: upperValue

            x: 0
            y: labels.canvas.y - height / 2
            width: Math.max(0, labels.canvas.x - root.axisPad)
            horizontalAlignment: Text.AlignRight
            color: root.secondaryTextColor
            font: root.captionFont
            text: labels.graph ? labels.graph.upperValueText : ""
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
        }

        Text {
            id: zeroValue

            visible: labels.graph ? labels.graph.bipolar : false
            x: 0
            y: labels.canvas.y + labels.canvas.height / 2 - height / 2
            width: Math.max(0, labels.canvas.x - root.axisPad)
            horizontalAlignment: Text.AlignRight
            color: root.secondaryTextColor
            font: root.captionFont
            text: "0"
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
        }

        Text {
            id: lowerValue

            x: 0
            y: labels.canvas.y + labels.canvas.height - height / 2
            width: Math.max(0, labels.canvas.x - root.axisPad)
            horizontalAlignment: Text.AlignRight
            color: root.secondaryTextColor
            font: root.captionFont
            text: labels.graph ? labels.graph.lowerValueText : ""
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
        }

        Text {
            id: noteOnLabel

            x: labels.canvas.x
            y: labels.canvas.y + labels.canvas.height + root.rowGap
            width: labels.canvas.width
            height: root.axisLabelHeight
            clip: true
            verticalAlignment: Text.AlignVCenter
            color: root.secondaryTextColor
            font: root.captionFont
            text: qsTr("Note on")
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
        }

        Text {
            id: endLabel

            x: labels.canvas.x
            y: noteOnLabel.y
            width: labels.canvas.width
            height: root.axisLabelHeight
            clip: true
            horizontalAlignment: Text.AlignRight
            verticalAlignment: Text.AlignVCenter
            color: root.secondaryTextColor
            font: root.captionFont
            text: labels.graph ? labels.graph.endLabel : ""
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
        }
    }

    component ResetButton: Item {
        id: resetButton

        required property GraphCanvas graph
        required property string resetDescription

        readonly property bool hovered: hoverHandler.hovered
        readonly property bool pressed: tapHandler.pressed

        width: root.resetWidth
        height: root.resetHeight
        activeFocusOnTab: false

        Rectangle {
            anchors.fill: parent
            color: root.windowBackgroundColor
            border.width: root.hairline
            border.color: root.outlineColor
        }

        Rectangle {
            anchors.fill: parent
            color: {
                if (!resetButton.pressed && !resetButton.hovered)
                    return "transparent"
                const outline = root.outlineColor
                return Qt.rgba(outline.r, outline.g, outline.b, resetButton.pressed ? 0.35 : 0.18)
            }
        }

        Text {
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: root.primaryTextColor
            font: root.captionFont
            text: qsTr("Reset")
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
        }

        HoverHandler {
            id: hoverHandler

            cursorShape: Qt.ArrowCursor
        }

        TapHandler {
            id: tapHandler

            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: root.resetLane(resetButton.graph)
        }

        Accessible.role: Accessible.Button
        Accessible.name: qsTr("Reset")
        Accessible.description: resetButton.resetDescription
        Accessible.focusable: false
        Accessible.onPressAction: root.resetLane(resetButton.graph)
    }

    component GraphCanvas: Item {
        id: graphCanvas
        final property PitchBendLane lane
        function inCanvas(x: real, y: real): bool {
            return x >= canvasRect.x && x < canvasRect.x + canvasRect.width
                && y >= canvasRect.y && y < canvasRect.y + canvasRect.height
        }
        final readonly property rect canvasRect: lane
            ? Qt.rect(lane.canvasX, lane.canvasY, lane.canvasWidth, lane.canvasHeight)
            : Qt.rect(0, 0, 0, 0)
        readonly property string laneTitle: lane ? lane.laneTitle : ""
        readonly property string liveValueText: lane ? lane.liveValueText : ""
        readonly property string upperValueText: lane ? lane.upperValueText : ""
        readonly property string lowerValueText: lane ? lane.lowerValueText : ""
        readonly property string endLabel: lane ? lane.endLabel : ""
        readonly property bool bipolar: lane ? lane.bipolar : false
        readonly property int curveSegmentCount: renderedCurveSegments.count

        Rectangle {
            x: graphCanvas.canvasRect.x
            y: graphCanvas.canvasRect.y
            width: graphCanvas.canvasRect.width
            height: graphCanvas.canvasRect.height
            color: graphCanvas.lane ? graphCanvas.lane.plotBackground : "transparent"
            clip: true
        }
        Repeater {
            model: graphCanvas.lane ? graphCanvas.lane.gridLines : null
            delegate: Rectangle {
                required x
                required y
                required width
                required height
                required property color fillColor
                required property string primitiveName
                objectName: primitiveName
                color: fillColor
            }
        }
        Repeater {
            id: renderedCurveSegments
            model: graphCanvas.lane ? graphCanvas.lane.curveLines : null
            delegate: Shape {
                id: curveShape
                required property real x0
                required property real y0
                required property real x1
                required property real y1
                required property color strokeColor
                required property real strokeWidth
                anchors.fill: graphCanvas
                ShapePath {
                    strokeColor: curveShape.strokeColor
                    strokeWidth: curveShape.strokeWidth
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: curveShape.x0
                    startY: curveShape.y0
                    PathLine {
                        x: curveShape.x1
                        y: curveShape.y1
                    }
                }
            }
        }
        Repeater {
            model: graphCanvas.lane ? graphCanvas.lane.vertices : null
            delegate: Rectangle {
                required x
                required y
                required radius
                required property color fillColor
                required property color ringColor
                required property real ringWidth
                width: radius * 2
                height: radius * 2
                color: fillColor
                border.width: ringWidth
                border.color: ringColor
            }
        }
        Rectangle {
            x: graphCanvas.canvasRect.x + root.hairline
            y: graphCanvas.canvasRect.y + root.hairline
            width: graphCanvas.canvasRect.width - 2 * root.hairline
            height: graphCanvas.canvasRect.height - 2 * root.hairline
            color: "transparent"
            border.width: graphCanvas.activeFocus ? root.hairline : 0
            border.color: graphCanvas.lane ? graphCanvas.lane.focusColor : "transparent"
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.CrossCursor
            preventStealing: true
            onPressed: (mouse) => {
                if (!graphCanvas.lane || !graphCanvas.inCanvas(mouse.x, mouse.y))
                    return
                graphCanvas.forceActiveFocus(Qt.MouseFocusReason)
                graphCanvas.lane.press(mouse.x, mouse.y, mouse.modifiers)
            }
            onPositionChanged: (mouse) => {
                if (graphCanvas.lane && (mouse.buttons & Qt.LeftButton))
                    graphCanvas.lane.drag(mouse.x, mouse.y, mouse.modifiers)
            }
            onReleased: (mouse) => {
                if (graphCanvas.lane)
                    graphCanvas.lane.release(mouse.x, mouse.y, mouse.modifiers)
            }
            onCanceled: {
                if (graphCanvas.lane)
                    graphCanvas.lane.settleGesture()
            }
            onWheel: (wheel) => {
                if (graphCanvas.lane && graphCanvas.inCanvas(wheel.x, wheel.y))
                    graphCanvas.lane.wheel(wheel.angleDelta.y, wheel.pixelDelta.y,
                                           wheel.phase === Qt.ScrollMomentum)
                wheel.accepted = true
            }
        }
    }

    GraphCanvas {
        id: pitchGraph
        lane: root.bridge ? root.bridge.currentPitch : null
        objectName: "pitchBendGraph"
        x: 0
        y: root.headerHeight
        width: root.width
        height: root.graphHeight
        activeFocusOnTab: true
    }

    GraphCanvas {
        id: modGraph
        lane: root.bridge ? root.bridge.currentMod : null
        objectName: "modWheelGraph"
        x: 0
        y: root.headerHeight + root.graphHeight
        width: root.width
        height: root.graphHeight
        activeFocusOnTab: true
    }

    GraphLaneLabels {
        graph: pitchGraph
        x: pitchGraph.x
        y: pitchGraph.y
        width: pitchGraph.width
        height: pitchGraph.height
    }

    GraphLaneLabels {
        graph: modGraph
        x: modGraph.x
        y: modGraph.y
        width: modGraph.width
        height: modGraph.height
    }

    ResetButton {
        objectName: "pitchBendReset"

        graph: pitchGraph
        resetDescription: qsTr("Reset the pitch bend curve to its default")
        x: root.width - root.outerInset - root.resetWidth
        y: pitchGraph.y + Math.max(0, (pitchGraph.canvasRect.y - height) / 2)
    }

    ResetButton {
        objectName: "modWheelReset"

        graph: modGraph
        resetDescription: qsTr("Reset the mod wheel curve to its default")
        x: root.width - root.outerInset - root.resetWidth
        y: modGraph.y + Math.max(0, (modGraph.canvasRect.y - height) / 2)
    }

    Text {
        id: titleText
        objectName: "pitchBendTitle"

        x: root.outerInset
        y: 0
        width: root.width - root.outerInset * 2
        height: root.titleHeight
        verticalAlignment: Text.AlignVCenter
        color: root.primaryTextColor
        font: root.titleFont
        text: qsTr("Note automation")
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        elide: Text.ElideRight
    }

    Text {
        id: subtitleText
        objectName: "pitchBendDescription"

        x: root.outerInset
        y: root.titleHeight
        width: root.width - root.outerInset * 2
        height: root.descriptionHeight
        verticalAlignment: Text.AlignVCenter
        color: root.secondaryTextColor
        font: root.captionFont
        text: root.bridge ? root.bridge.noteDescription : ""
        renderType: Text.NativeRendering
        elide: Text.ElideRight
    }

    Text {
        id: bendRangeLabel

        x: root.outerInset
        y: root.titleHeight + root.descriptionHeight
        height: root.controlsHeight
        verticalAlignment: Text.AlignVCenter
        color: root.secondaryTextColor
        font: root.captionFont
        text: qsTr("BENDR")
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
    }

    DragInput {
        id: bendRangeField

        objectName: "bendRangeSpin"
        inputObjectName: "bendRangeInput"
        accessibleName: qsTr("Pitch-bend range")
        appearance: root.bridge.promptStyle
        minimumValue: 0
        maximumValue: 127
        accessibleDescription: qsTr("Pitch-bend range in semitones for this note")
        x: bendRangeLabel.x + bendRangeLabel.implicitWidth + root.controlGap
        y: root.titleHeight + root.descriptionHeight
           + (root.controlsHeight - height) / 2
        width: root.fieldWidth
        height: root.fieldHeight
        value: root.bridge ? root.bridge.bendRange : 0
        onValueCommitted: (committed) => {
            if (root.bridge)
                root.bridge.setBendRange(committed)
        }
        Connections {
            target: bendRangeField.textInput.Keys
            function onShortcutOverride(event: KeyEvent): void {
                event.accepted = event.key !== Qt.Key_Space
                    && !event.matches(StandardKey.Undo) && !event.matches(StandardKey.Redo)
            }
        }
    }

    Text {
        id: lfoSpeedLabel

        x: bendRangeField.x + bendRangeField.width + root.controlGap * 2
        y: bendRangeLabel.y
        height: root.controlsHeight
        verticalAlignment: Text.AlignVCenter
        color: root.secondaryTextColor
        font: root.captionFont
        text: qsTr("LFO speed")
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
    }

    DragInput {
        id: lfoSpeedField

        objectName: "lfoSpeedSpin"
        inputObjectName: "lfoSpeedInput"
        accessibleName: qsTr("LFO speed")
        appearance: root.bridge.promptStyle
        minimumValue: 0
        maximumValue: 127
        accessibleDescription: qsTr("M4A LFO speed for this note")
        x: lfoSpeedLabel.x + lfoSpeedLabel.implicitWidth + root.controlGap
        y: bendRangeField.y
        width: root.fieldWidth
        height: root.fieldHeight
        value: root.bridge ? root.bridge.lfoSpeed : 0
        onValueCommitted: (committed) => {
            if (root.bridge)
                root.bridge.setLfoSpeed(committed)
        }
        Connections {
            target: lfoSpeedField.textInput.Keys
            function onShortcutOverride(event: KeyEvent): void {
                event.accepted = event.key !== Qt.Key_Space
                    && !event.matches(StandardKey.Undo) && !event.matches(StandardKey.Redo)
            }
        }
    }
}
