import QtQuick
import QtQuick.Controls.Fusion as Fusion

// Fusion's CheckBox with a glyph check mark.
Fusion.CheckBox {
    id: control

    indicator: CheckIndicator {
        x: control.text ? (control.mirrored ? control.width - width - control.rightPadding : control.leftPadding)
                        : control.leftPadding + (control.availableWidth - width) / 2
        y: control.topPadding + (control.availableHeight - height) / 2
        baseLightness: control.enabled ? 1.25 : 1.0
        control: control
    }
}
