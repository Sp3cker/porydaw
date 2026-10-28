pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import PorydawStyle
import Porydaw.Icons
import PorydawApp

// Empty-state target: dashed outline and one glyph; click or Enter activates, hover/focus/invalid recolour.
Item {
    id: zone
    required property GridPalette colors
    required property real unit
    required property IconSpec glyph
    property bool dropHover: false
    property bool dropInvalid: false
    signal activated()
    readonly property color ink: zone.dropInvalid ? zone.colors.errorText
        : (zone.dropHover || pointer.containsMouse || zone.activeFocus) ? zone.colors.selectionEdge : zone.colors.secondaryText
    activeFocusOnTab: true
    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !event.isAutoRepeat) {
            zone.activated()
            event.accepted = true
        }
    }
    Accessible.role: Accessible.Button
    Accessible.onPressAction: zone.activated()

    Shape {
        id: outline
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: zone.ink
            strokeWidth: zone.dropHover || zone.dropInvalid ? Math.max(2, Math.round(zone.unit / 6)) : Math.max(1, Math.round(zone.unit / 13))
            strokeStyle: zone.dropHover || zone.dropInvalid ? ShapePath.SolidLine : ShapePath.DashLine
            dashPattern: [4, 3]
            fillColor: "transparent"
            PathRectangle {
                x: 1
                y: 1
                width: outline.width - 2
                height: outline.height - 2
                radius: zone.unit / 2
            }
        }
    }
    AppIcon {
        anchors.centerIn: parent
        width: Math.round(2.5 * zone.unit)
        height: width
        icon: zone.glyph
        color: zone.ink
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: zone.activated()
    }
}
