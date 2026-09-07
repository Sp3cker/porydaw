// Opaque note-automation popup shell. The session object (PitchBendEditor)
// is injected before load and owns geometry/appearance resolution; the two
// PitchBendGraph lanes own their canvases and all C++ input algorithms. This
// file only hosts the chrome: labels aligned to each canvasRect, the reset
// buttons, and the BENDR / LFO speed scrub fields. QtQuick only.
import QtQuick

Rectangle {
    id: root

    objectName: "pitchBendPopup"

    required property var session

    property font fallbackFont

    readonly property var metrics: session ? session.metrics : null
    readonly property var appearance: session ? session.appearance : null

    readonly property real outerInset: metrics ? metrics.outerInset : 0
    readonly property real headerHeight: metrics ? metrics.headerHeight : 0
    readonly property real graphHeight: metrics ? metrics.graphHeight : 0
    readonly property real titleHeight: metrics ? metrics.titleHeight : 0
    readonly property real descriptionHeight: metrics ? metrics.descriptionHeight : 0
    readonly property real controlsHeight: metrics ? metrics.controlsHeight : 0
    readonly property real fieldWidth: metrics ? metrics.fieldWidth : 0
    readonly property real fieldHeight: metrics ? metrics.fieldHeight : 0
    readonly property real resetWidth: metrics ? metrics.resetWidth : 0
    readonly property real resetHeight: metrics ? metrics.resetHeight : 0
    readonly property real axisLabelHeight: metrics ? metrics.axisLabelHeight : 0
    readonly property real hairline: metrics ? metrics.hairline : 0

    // Secondary gaps derive from resolved chrome metrics; no raw widget pixel
    // sizes appear in this shell.
    readonly property real controlGap: outerInset / 2
    readonly property real rowGap: hairline * 2
    readonly property real axisPad: hairline * 4

    readonly property color windowBackgroundColor: appearance ? appearance.windowBackground
                                                              : "transparent"
    readonly property color primaryTextColor: appearance ? appearance.primaryText : "transparent"
    readonly property color secondaryTextColor: appearance ? appearance.secondaryText
                                                           : "transparent"
    readonly property color outlineColor: appearance ? appearance.outline : "transparent"
    readonly property font titleFont: appearance ? appearance.titleFont : fallbackFont
    readonly property font captionFont: appearance ? appearance.captionFont : fallbackFont
    readonly property font monospaceFont: appearance ? appearance.monospaceFont : fallbackFont

    width: metrics ? metrics.popupWidth : 0
    height: metrics ? metrics.popupHeight : 0

    color: windowBackgroundColor
    border.width: hairline
    border.color: outlineColor

    Accessible.role: Accessible.Client
    Accessible.name: qsTr("Note automation editor")
    Accessible.description: session ? session.description : ""

    function resetLane(graph) {
        if (!session || !graph)
            return
        if (graph === pitchGraph)
            session.resetPitchCurve()
        else
            session.resetModCurve()
        graph.forceActiveFocus(Qt.OtherFocusReason)
    }

    component GraphLaneLabels: Item {
        id: labels

        required property Item graph

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

            x: labels.canvas.x
            y: 0
            // The lane's Reset button shares this band, vertically centered
            // like this readout and right-aligned to the canvas edge; stop
            // the readout one control gap short so it stays fully visible.
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

        required property Item graph
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
            color: resetButton.pressed ? Qt.alpha(root.outlineColor, 0.35)
                  : resetButton.hovered ? Qt.alpha(root.outlineColor, 0.18)
                  : "transparent"
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


    PitchBendGraph {
        id: pitchGraph

        objectName: "pitchBendGraph"
        x: 0
        y: root.headerHeight
        width: root.width
        height: root.graphHeight
        activeFocusOnTab: true
    }

    PitchBendGraph {
        id: modGraph

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

        x: root.outerInset
        y: root.titleHeight
        width: root.width - root.outerInset * 2
        height: root.descriptionHeight
        verticalAlignment: Text.AlignVCenter
        color: root.secondaryTextColor
        font: root.captionFont
        text: session ? session.noteDescription : ""
        textFormat: Text.PlainText
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
        appearance: session.appearance.dragInput
        minimumValue: 0
        maximumValue: 127
        accessibleDescription: qsTr("Pitch-bend range in semitones for this note")
        x: bendRangeLabel.x + bendRangeLabel.implicitWidth + root.controlGap
        y: root.titleHeight + root.descriptionHeight
           + (root.controlsHeight - height) / 2
        width: root.fieldWidth
        height: root.fieldHeight
        value: session ? session.bendRange : 0
        onValueCommitted: (committed) => {
            if (session)
                session.setBendRange(committed)
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
        appearance: session.appearance.dragInput
        minimumValue: 0
        maximumValue: 127
        accessibleDescription: qsTr("M4A LFO speed for this note")
        x: lfoSpeedLabel.x + lfoSpeedLabel.implicitWidth + root.controlGap
        y: bendRangeField.y
        width: root.fieldWidth
        height: root.fieldHeight
        value: session ? session.lfoSpeed : 0
        onValueCommitted: (committed) => {
            if (session)
                session.setLfoSpeed(committed)
        }
    }
}
