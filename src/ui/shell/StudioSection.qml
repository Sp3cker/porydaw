pragma ComponentBehavior: Bound

import QtQuick
import PorydawStyle
import QtQuick.Layouts
import PorydawApp

// Studio inspector section: caption title with optional trailing controls, rows, then a divider.
ColumnLayout {
    id: section
    required property string title
    required property GridPalette colors
    required property font captionFont
    required property real unit
    default property alias content: body.data
    property alias headerControls: controls.data
    Layout.fillWidth: true
    spacing: section.unit
    RowLayout {
        Layout.fillWidth: true
        spacing: section.unit / 2
        Label {
            Layout.fillWidth: true
            text: section.title
            font: section.captionFont
            color: section.colors.secondaryText
            Component.onCompleted: {
                font.letterSpacing = section.unit / 13
                font.capitalization = Font.AllUppercase
            }
        }
        RowLayout { id: controls; spacing: section.unit / 2 }
    }
    ColumnLayout {
        id: body
        Layout.fillWidth: true
        spacing: section.unit * 0.7
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: section.unit
        Layout.preferredHeight: Math.max(1, Math.round(section.unit / 13))
        color: section.colors.outline
    }
}
