import QtQuick
import QtQuick.Controls.Fusion as Fusion

// Fusion's ProgressBar fill without its image stripe mask; indeterminate
// progress sweeps a lighter band across the full fill instead.
Fusion.ProgressBar {
    id: control

    contentItem: Item {
        scale: control.mirrored ? -1 : 1
        clip: true

        Rectangle {
            height: parent.height
            width: (control.indeterminate ? 1.0 : control.position) * parent.width
            radius: 2
            border.color: Fusion.Fusion.highContrast ? Fusion.Fusion.outline(control.palette)
                                                         : Qt.darker(Fusion.Fusion.highlight(control.palette), 1.4)
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.lighter(Fusion.Fusion.highlight(control.palette), 1.2)
                }
                GradientStop {
                    position: 1
                    color: Fusion.Fusion.highlight(control.palette)
                }
            }
        }

        Rectangle {
            width: parent.width / 4
            height: parent.height
            visible: control.indeterminate
            color: Qt.lighter(Fusion.Fusion.highlight(control.palette), 1.4)

            NumberAnimation on x {
                running: control.indeterminate && control.visible
                from: -control.availableWidth / 4
                to: control.availableWidth
                loops: Animation.Infinite
                duration: 750
            }
        }
    }
}
