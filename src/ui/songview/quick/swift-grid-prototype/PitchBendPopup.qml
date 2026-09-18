import QtQuick

Rectangle {
    id: root

    objectName: "pitchBendPopup"

    required property var bridge
    signal hintChanged(string text)
    // Escape is forwarded, never decided here: the host routes it to the
    // single gridModel.escapePressed arbiter and executes the action it
    // returns (spec §3.5).
    signal escapePressed()

    function focusPitch() {
        pitchGraph.forceActiveFocus(Qt.PopupFocusReason);
    }

    readonly property var metrics: bridge.metrics
    readonly property var appearance: bridge.appearance

    readonly property real outerInset: metrics.outerInset
    readonly property real headerHeight: metrics.headerHeight
    readonly property real graphHeight: metrics.graphHeight
    readonly property real titleHeight: metrics.titleHeight
    readonly property real descriptionHeight: metrics.descriptionHeight
    readonly property real controlsHeight: metrics.controlsHeight
    readonly property real fieldWidth: metrics.fieldWidth
    readonly property real fieldHeight: metrics.fieldHeight
    readonly property real resetWidth: metrics.resetWidth
    readonly property real resetHeight: metrics.resetHeight
    readonly property real axisLabelHeight: metrics.axisLabelHeight
    readonly property real hairline: metrics.hairline

    readonly property real controlGap: outerInset / 2
    readonly property real rowGap: hairline * 2
    readonly property real axisPad: hairline * 4

    readonly property color windowBackgroundColor: appearance.windowBackground
    readonly property color primaryTextColor: appearance.primaryText
    readonly property color secondaryTextColor: appearance.secondaryText
    readonly property color outlineColor: appearance.outline
    readonly property font titleFont: Qt.font(appearance.titleFont)
    readonly property font captionFont: Qt.font(appearance.captionFont)
    readonly property font monospaceFont: Qt.font(appearance.monospaceFont)

    FontMetrics {
        id: titleMetrics
        font: root.titleFont
    }
    FontMetrics {
        id: captionMetrics
        font: root.captionFont
    }
    function measureChrome() {
        bridge.setFontHeights(Math.round(titleMetrics.height), Math.round(captionMetrics.height));
    }
    onTitleFontChanged: Qt.callLater(measureChrome)
    onCaptionFontChanged: Qt.callLater(measureChrome)
    Component.onCompleted: measureChrome()

    implicitWidth: metrics.popupWidth
    implicitHeight: metrics.popupHeight

    color: windowBackgroundColor
    border.width: hairline
    border.color: outlineColor

    // Root-level blank chrome must never hand clicks or wheel gestures to the
    // roll. Interactive controls appear later and therefore sit above this
    // shield.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onWheel: wheel => wheel.accepted = true
    }

    // Focused controls claim their keys before this popup sink.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape)
            root.escapePressed();
        else
            bridge.routeUnclaimedKey(event.key, event.modifiers, event.isAutoRepeat);
        event.accepted = true;
    }
    Keys.onReleased: event => event.accepted = true

    Accessible.role: Accessible.Client
    Accessible.name: qsTr("Note automation editor")
    Accessible.description: bridge.description

    function resetLane(graph) {
        if (graph === pitchGraph)
            bridge.resetPitchCurve();
        else
            bridge.resetModCurve();
        graph.forceActiveFocus(Qt.OtherFocusReason);
    }

    component GraphLaneLabels: Item {
        id: labels

        required property Item graph

        readonly property rect canvas: graph.canvasRect

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
            text: labels.graph.laneTitle
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
            text: labels.graph.liveValueText
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
            text: labels.graph.upperValueText
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
        }

        Text {
            id: zeroValue

            visible: labels.graph.bipolar
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
            text: labels.graph.lowerValueText
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
            text: labels.graph.endLabel
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
            color: resetButton.pressed ? Qt.alpha(root.outlineColor, 0.35) : resetButton.hovered ? Qt.alpha(root.outlineColor, 0.18) : "transparent"
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
        laneModel: root.bridge.pitchGraph
        onHintChanged: text => root.hintChanged(text)
        onEscapePressed: root.escapePressed()

        objectName: "pitchBendGraph"
        x: 0
        y: root.headerHeight
        width: root.width
        height: root.graphHeight
        activeFocusOnTab: true
    }

    PitchBendGraph {
        id: modGraph
        laneModel: root.bridge.modGraph
        onHintChanged: text => root.hintChanged(text)
        onEscapePressed: root.escapePressed()

        objectName: "modWheelGraph"
        x: 0
        y: root.headerHeight + root.graphHeight
        width: root.width
        height: root.graphHeight
        activeFocusOnTab: true
    }

    Connections {
        target: root.bridge.pitchGraph
        function onPreviewChanged() {
            root.bridge.previewRequested();
        }
        function onCommitRequested() {
            root.bridge.commitRequested();
        }
        function onCancelRequested() {
            root.bridge.cancelAndClose();
        }
        function onAuditionRequested() {
            root.bridge.auditionRequested();
        }
        function onRangeChangeRequested(steps) {
            root.bridge.changeBendRange(steps);
        }
    }

    Connections {
        target: root.bridge.modGraph
        function onPreviewChanged() {
            root.bridge.previewRequested();
        }
        function onCommitRequested() {
            root.bridge.commitRequested();
        }
        function onCancelRequested() {
            root.bridge.cancelAndClose();
        }
        function onAuditionRequested() {
            root.bridge.auditionRequested();
        }
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
        text: bridge.noteDescription
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
        appearance: bridge.appearance.dragInput
        minimumValue: 0
        maximumValue: 127
        accessibleDescription: qsTr("Pitch-bend range in semitones for this note")
        x: bendRangeLabel.x + bendRangeLabel.implicitWidth + root.controlGap
        y: root.titleHeight + root.descriptionHeight + (root.controlsHeight - height) / 2
        width: root.fieldWidth
        height: root.fieldHeight
        value: bridge.bendRange
        onValueCommitted: committed => bridge.setBendRange(committed)
        onHintChanged: text => root.hintChanged(text)
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
        appearance: bridge.appearance.dragInput
        minimumValue: 0
        maximumValue: 127
        accessibleDescription: qsTr("M4A LFO speed for this note")
        x: lfoSpeedLabel.x + lfoSpeedLabel.implicitWidth + root.controlGap
        y: bendRangeField.y
        width: root.fieldWidth
        height: root.fieldHeight
        value: bridge.lfoSpeed
        onValueCommitted: committed => bridge.setLfoSpeed(committed)
        onHintChanged: text => root.hintChanged(text)
    }
}
