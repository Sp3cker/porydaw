import QtQuick

Item {
    id: controls

    required property Item rulerBand
    required property var ruler
    clip: true

    property font fallbackControlFont
    readonly property var appearance: ruler ? ruler.gridControlAppearance : null
    readonly property font controlFont: appearance ? appearance.font : fallbackControlFont
    readonly property color primaryText: appearance ? appearance.primaryText : "transparent"
    readonly property color buttonBackground: appearance ? appearance.buttonBackground : "transparent"
    readonly property color buttonText: appearance ? appearance.buttonText : "transparent"
    readonly property color buttonOutline: appearance ? appearance.buttonOutline : "transparent"
    readonly property color buttonHoverBackground: appearance
                                                   ? appearance.buttonHoverBackground : "transparent"
    readonly property bool toolTipVisible: rulerDivisionControl.hovered || rulerFeelControl.hovered
    readonly property string toolTipText: rulerDivisionControl.hovered
                                          ? rulerDivisionControl.controlToolTip
                                          : rulerFeelControl.hovered
                                            ? rulerFeelControl.controlToolTip : ""
    readonly property rect toolTipAnchorRect: {
        const control = rulerDivisionControl.hovered ? rulerDivisionControl
                                                      : rulerFeelControl.hovered
                                                        ? rulerFeelControl : null
        if (!control)
            return Qt.rect(0, 0, 0, 0)
        return Qt.rect(rulerBand.x + controls.x + control.x,
                       rulerBand.y + controls.y + control.y, control.width, control.height)
    }
    readonly property color buttonPressedBackground: appearance
                                                     ? appearance.buttonPressedBackground
                                                     : "transparent"
    readonly property real labelLeadingInset: 8
    readonly property real labelToControlGap: 4
    readonly property real controlGap: 4
    readonly property real controlVerticalPadding: 8
    readonly property real labelWidth: Math.min(gridLabel.implicitWidth,
                                                Math.max(0, width - labelLeadingInset))
    readonly property real availableControlWidth: Math.max(0, width - labelLeadingInset
                                                            - labelWidth - labelToControlGap)
    readonly property real controlWidth: Math.max(0, (availableControlWidth - controlGap) / 2)

    component GridControl: Item {
        id: control

        required property string accessibleName
        required property string controlText
        required property string controlToolTip
        required property bool divisionControl
        property bool controlsEnabled: true
        readonly property bool hovered: hoverHandler.hovered
        readonly property bool pressed: tapHandler.pressed

        enabled: controlsEnabled
        activeFocusOnTab: true

        function openMenu(localPosition) {
            if (!controls.ruler)
                return
            const point = mapToItem(controls.rulerBand, localPosition.x, localPosition.y)
            if (divisionControl)
                controls.ruler.openDivisionMenu(point)
            else
                controls.ruler.openFeelMenu(point)
        }

        function activateFromKeyboard(event) {
            openMenu(Qt.point(width / 2, height / 2))
            event.accepted = true
        }

        Rectangle {
            anchors.fill: parent
            color: control.pressed ? controls.buttonPressedBackground
                  : control.hovered ? controls.buttonHoverBackground : controls.buttonBackground
            border.color: controls.buttonOutline
            border.width: 1
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: controls.labelToControlGap
            anchors.right: controlArrow.left
            anchors.rightMargin: controls.labelToControlGap / 2
            anchors.verticalCenter: parent.verticalCenter
            clip: true
            color: controls.buttonText
            font: controls.controlFont
            text: control.controlText
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
            elide: Text.ElideRight
            maximumLineCount: 1
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            id: controlArrow

            anchors.right: parent.right
            anchors.rightMargin: controls.labelToControlGap
            anchors.verticalCenter: parent.verticalCenter
            color: controls.buttonText
            font: controls.controlFont
            text: "\u25be"
            textFormat: Text.PlainText
            renderType: Text.NativeRendering
        }

        HoverHandler {
            id: hoverHandler
        }
        TapHandler {
            id: tapHandler

            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: (eventPoint) => control.openMenu(eventPoint.position)
        }

        Keys.onReturnPressed: (event) => control.activateFromKeyboard(event)
        Keys.onEnterPressed: (event) => control.activateFromKeyboard(event)
        Keys.onSpacePressed: (event) => control.activateFromKeyboard(event)

        Accessible.role: Accessible.Button
        Accessible.name: control.accessibleName + ": " + control.controlText
        Accessible.description: control.controlToolTip
        Accessible.focusable: true
        Accessible.onPressAction: control.openMenu(Qt.point(width / 2, height / 2))
    }

    Text {
        id: gridLabel

        x: controls.labelLeadingInset
        width: controls.labelWidth
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        color: controls.primaryText
        font: controls.controlFont
        text: qsTr("Grid")
        textFormat: Text.PlainText
        renderType: Text.NativeRendering
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    GridControl {
        id: rulerDivisionControl

        objectName: "timelineRulerDivisionControl"
        x: controls.labelLeadingInset + controls.labelWidth + controls.labelToControlGap
        y: Math.max(0, (parent.height - height) / 2)
        width: controls.controlWidth
        height: Math.min(parent.height, gridLabel.implicitHeight + controls.controlVerticalPadding)
        accessibleName: qsTr("Grid division")
        controlText: controls.ruler ? controls.ruler.divisionText : ""
        controlToolTip: controls.ruler ? controls.ruler.divisionToolTip : ""
        divisionControl: true
        controlsEnabled: controls.ruler ? controls.ruler.gridControlsEnabled : false
    }

    GridControl {
        id: rulerFeelControl

        objectName: "timelineRulerFeelControl"
        x: rulerDivisionControl.x + rulerDivisionControl.width + controls.controlGap
        y: Math.max(0, (parent.height - height) / 2)
        width: controls.controlWidth
        height: Math.min(parent.height, gridLabel.implicitHeight + controls.controlVerticalPadding)
        accessibleName: qsTr("Grid feel")
        controlText: controls.ruler ? controls.ruler.feelText : ""
        controlToolTip: controls.ruler ? controls.ruler.feelToolTip : ""
        divisionControl: false
        controlsEnabled: controls.ruler ? controls.ruler.gridControlsEnabled : false
    }

    RulerToolTip {
        parent: controls.rulerBand.parent
        overlayRoot: controls.rulerBand.parent
        anchorRect: controls.toolTipAnchorRect
        toolTipText: controls.toolTipText
        visibleForControl: controls.rulerBand.visible && controls.toolTipVisible
        controlFont: controls.controlFont
        backgroundColor: controls.buttonBackground
        textColor: controls.buttonText
        outlineColor: controls.buttonOutline
        z: 30
    }
}
