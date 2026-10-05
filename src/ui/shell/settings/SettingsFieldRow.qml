pragma ComponentBehavior: Bound

import QtQuick
import PorydawApp

Item {
    id: row
    required property real unit
    required property real labelWidth
    required property GridPalette colors
    required property TypographyFonts typography
    required property string label
    property bool compact: false
    property real bottomInset: 0
    readonly property real controlHeight: compact ? 22 + 12 * (unit - 1) : 25 + 15 * (unit - 1)
    height: controlHeight + bottomInset
    default property alias controls: field.data

    Text {
        width: row.labelWidth
        height: row.controlHeight
        text: row.label
        color: row.colors.windowText
        font: row.typography.body
        verticalAlignment: Text.AlignVCenter
    }
    Item {
        id: field
        x: row.labelWidth
        width: row.width - x
        height: row.controlHeight
    }
}
