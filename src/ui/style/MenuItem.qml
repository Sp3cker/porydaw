pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Fusion as Fusion
import Porydaw.Icons

// Fusion's MenuItem with glyph check mark and submenu arrow.
Fusion.MenuItem {
    id: control

    arrow: AppIcon {
        x: control.mirrored ? control.padding : control.width - width - control.padding
        y: control.topPadding + (control.availableHeight - height) / 2
        width: Math.round(control.font.pixelSize * 1.5)
        height: control.font.pixelSize
        visible: control.subMenu
        rotation: control.mirrored ? 180 : 0
        icon: Icons.submenuArrow
        color: control.down || control.hovered || control.highlighted
               ? Fusion.Fusion.highlightedText(control.palette) : control.palette.text
    }

    indicator: CheckIndicator {
        x: control.mirrored ? control.width - width - control.rightPadding : control.leftPadding
        y: control.topPadding + (control.availableHeight - height) / 2
        control: control
        visible: control.checkable
    }
}
