pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Fusion as Fusion
import Porydaw.Icons

// Fusion's ComboBox with a glyph arrow; its popup rows are this style's MenuItem.
Fusion.ComboBox {
    id: control

    delegate: MenuItem {
        required property var model
        required property int index

        width: ListView.view.width
        text: model[control.textRole]
        font.weight: control.currentIndex === index ? Font.DemiBold : Font.Normal
        highlighted: control.highlightedIndex === index
        hoverEnabled: control.hoverEnabled
    }

    indicator: AppIcon {
        x: control.mirrored ? control.padding : control.width - width - control.padding
        y: control.topPadding + (control.availableHeight - height) / 2
        width: Math.round(control.font.pixelSize * 1.5)
        height: control.font.pixelSize
        icon: Icons.comboArrow
        color: control.editable ? control.palette.text : control.palette.buttonText
    }
}
